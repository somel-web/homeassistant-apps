#!/usr/bin/with-contenv bashio
# shellcheck disable=SC2034,SC2129,SC2016
# shellcheck shell=bash

ssl=$(bashio::config 'ssl')
website_name=$(bashio::config 'website_name')
if [ -z "$website_name" ] || [ "$website_name" = "null" ]; then
    website_name="web.local"
fi
certfile=$(bashio::config 'certfile')
keyfile=$(bashio::config 'keyfile')
DocumentRoot=$(bashio::config 'document_root')
phpini=$(bashio::config 'php_ini')
username=$(bashio::config 'username')
password=$(bashio::config 'password')
default_conf=$(bashio::config 'default_conf')
default_ssl_conf=$(bashio::config 'default_ssl_conf')
log_level=$(bashio::config 'log_level')
webrootdocker=/var/www/localhost/htdocs/

# Détection dynamique du chemin php.ini
PHP_V=$(ls -d /etc/php* 2>/dev/null | head -1 | sed 's|.*/php||')
phppath="/etc/php${PHP_V}/php.ini"

# Map Bashio log_level -> Apache log_level
apache_log_level="warn"
case "${log_level}" in
    trace|debug)   apache_log_level="debug" ;;
    info)          apache_log_level="info"  ;;
    notice)        apache_log_level="notice" ;;
    warning|warn)  apache_log_level="warn"  ;;
    error)         apache_log_level="error" ;;
    fatal)         apache_log_level="crit"  ;;
    *)             apache_log_level="warn"  ;;
esac

echo "Setting Apache log level to: ${apache_log_level}"
if grep -i -q "^LogLevel " /etc/apache2/httpd.conf 2>/dev/null; then
    sed -i -E "s/^LogLevel .*/LogLevel ${apache_log_level}/I" /etc/apache2/httpd.conf
else
    echo "LogLevel ${apache_log_level}" >> /etc/apache2/httpd.conf
fi

# Supprimer le VirtualHost SSL par défaut d'Alpine
if [ "$ssl" = "true" ]; then
    if [ -f "/etc/apache2/conf.d/ssl.conf" ]; then
        sed -i '/<VirtualHost _default_:443>/,/<\/VirtualHost>/d' /etc/apache2/conf.d/ssl.conf
    fi
fi

# Activer mod_status pour monitoring
sed -i 's/^#\(LoadModule status_module modules\/mod_status.so\)/\1/' /etc/apache2/httpd.conf
if ! grep -q "<Location /server-status>" /etc/apache2/httpd.conf; then
    cat >> /etc/apache2/httpd.conf << APACHEEOF
<Location /server-status>
    SetHandler server-status
    Require local
    Require ip 172.30.0.0/16
    Require ip 127.0.0.1
</Location>
ExtendedStatus On
APACHEEOF
fi

if [ "$phpini" = "get_file" ]; then
    cp "$phppath" /share/apache2App_php.ini
    echo "Copie de php.ini disponible dans /share/apache2App_php.ini"
    echo "L'add-on va s'arrêter. Modifiez php_ini dans la config."
    exit 0
fi

if bashio::config.has_value 'init_commands'; then
    echo "Detected custom init commands. Running them now."
    while read -r cmd; do
        if [[ -z "${cmd}" || "${cmd}" == "[]" ]]; then
            continue
        fi
        eval "${cmd}" || bashio::exit.nok "Failed executing init command: ${cmd}"
    done <<< "$(bashio::config 'init_commands')"
fi

rm -rf "$webrootdocker"

if [ ! -d "$DocumentRoot" ] || [ -z "$(ls -A "$DocumentRoot")" ]; then
    if [ ! -d "$DocumentRoot" ]; then
        echo "Dossier $DocumentRoot introuvable — site par défaut utilisé."
        mkdir -p "$DocumentRoot"
    fi
    echo "Site par défaut utilisé."
    mkdir -p "$webrootdocker"
    cp /index.html "$webrootdocker"
else
    ln -s "$DocumentRoot" /var/www/localhost/htdocs
fi

if [ -d "$DocumentRoot" ]; then
    find "$DocumentRoot" -type d -exec chmod 771 {} +
    if [ -n "$username" ] && [ -n "$password" ] && [ ! "$username" = "null" ] && [ ! "$password" = "null" ]; then
        if ! id "$username" &>/dev/null; then
            adduser -S "$username" -G www-data
        fi
        echo "$username:$password" | chpasswd
        chown -R "$username":www-data "$webrootdocker"
    else
        echo "Pas de username/password fourni. Droits www-data appliqués."
        chown -R www-data:www-data "$webrootdocker"
    fi
fi

if [ "$phpini" != "default" ]; then
    if [ -f "$phpini" ]; then
        echo "php.ini custom : $phpini"
        rm "$phppath"
        cp "$phpini" "$phppath"
    else
        echo "php.ini custom introuvable — php.ini par défaut utilisé."
    fi
fi

if [ "$ssl" = "true" ] && [ "$default_conf" = "default" ]; then
    echo "SSL activé."
    if [ ! -f "/ssl/$certfile" ]; then
        echo "Certificat introuvable : $certfile"
        exit 1
    fi
    if [ ! -f "/ssl/$keyfile" ]; then
        echo "Clé introuvable : $keyfile"
        exit 1
    fi
    mkdir -p /etc/apache2/sites-enabled
    sed -i '/LoadModule rewrite_module/s/^#//g' /etc/apache2/httpd.conf
    echo "Listen 443" >> /etc/apache2/httpd.conf

    cat > /etc/apache2/sites-enabled/000-default.conf << VHOSTEOF
<VirtualHost *:80>
    ServerName $website_name
    ServerAdmin webmaster@localhost
    DocumentRoot $webrootdocker
    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule (.*) https://%{HTTP_HOST}%{REQUEST_URI}
    ErrorLog /dev/stderr
</VirtualHost>
VHOSTEOF

    cat > /etc/apache2/sites-enabled/000-default-le-ssl.conf << SSLEOF
<IfModule mod_ssl.c>
<VirtualHost *:443>
    ServerName $website_name
    ServerAdmin webmaster@localhost
    DocumentRoot $webrootdocker
    ErrorLog /dev/stderr
    SSLCertificateFile /ssl/$certfile
    SSLCertificateKeyFile /ssl/$keyfile
</VirtualHost>
</IfModule>
SSLEOF
else
    echo "SSL désactivé ou config custom."
fi

if [ "$ssl" = "true" ] || [ "$default_conf" != "default" ]; then
    echo "Include /etc/apache2/sites-enabled/*.conf" >> /etc/apache2/httpd.conf
fi

sed -i -e '/AllowOverride/s/None/All/' /etc/apache2/httpd.conf

if [ "$default_conf" = "get_config" ]; then
    mkdir -p /etc/apache2/sites-enabled
    [ -f /etc/apache2/sites-enabled/000-default.conf ] && cp /etc/apache2/sites-enabled/000-default.conf /share/000-default.conf && echo "Config copiée dans /share/000-default.conf"
    [ -f /etc/apache2/httpd.conf ] && cp /etc/apache2/httpd.conf /share/httpd.conf && echo "httpd.conf copié dans /share/httpd.conf"
    [ "$default_ssl_conf" != "get_config" ] && echo "Arrêt." && exit 0
fi

if [[ ! $default_conf =~ ^(default|get_config)$ ]]; then
    if [ -f "$default_conf" ]; then
        mkdir -p /etc/apache2/sites-enabled
        rm -f /etc/apache2/sites-enabled/000-default.conf
        cp -rf "$default_conf" /etc/apache2/sites-enabled/000-default.conf
        echo "Config custom utilisée : $default_conf"
    else
        echo "Config custom introuvable : $default_conf"
        exit 1
    fi
fi

if [ "$default_ssl_conf" = "get_config" ]; then
    [ -f /etc/apache2/sites-enabled/000-default-le-ssl.conf ] && cp /etc/apache2/sites-enabled/000-default-le-ssl.conf /share/000-default-le-ssl.conf && echo "Config SSL copiée dans /share/"
    echo "Arrêt."
    exit 0
fi

if [ "$default_ssl_conf" != "default" ]; then
    if [ -f "$default_ssl_conf" ]; then
        mkdir -p /etc/apache2/sites-enabled
        rm -f /etc/apache2/sites-enabled/000-default-le-ssl.conf
        cp -rf "$default_ssl_conf" /etc/apache2/sites-enabled/000-default-le-ssl.conf
        echo "Config SSL custom utilisée : $default_ssl_conf"
    else
        echo "Config SSL custom introuvable : $default_ssl_conf"
        exit 1
    fi
fi

echo "Architecture des fichiers web :"
ls -l "$webrootdocker"

# IP et port pour le log de démarrage
host_ip=""
if [ -n "$SUPERVISOR_TOKEN" ]; then
    network_info=$(curl -sSL -H "Authorization: Bearer $SUPERVISOR_TOKEN" http://supervisor/network/info 2>/dev/null)
    if [ -n "$network_info" ] && echo "$network_info" | jq -e . >/dev/null 2>&1; then
        host_ip=$(echo "$network_info" | jq -r '.data.interfaces[]? | select(.primary == true) | .ipv4.address[]?' 2>/dev/null | head -n 1 | cut -d'/' -f1)
    fi
fi
[ -z "$host_ip" ] && host_ip="homeassistant.local"

protocol="http"
port="80"
if [ "$ssl" = "true" ]; then
    protocol="https"
    port="443"
fi

external_port=""
if [ -n "$SUPERVISOR_TOKEN" ]; then
    addon_info=$(curl -sSL -H "Authorization: Bearer $SUPERVISOR_TOKEN" http://supervisor/addons/self/info 2>/dev/null)
    if [ -n "$addon_info" ] && echo "$addon_info" | jq -e . >/dev/null 2>&1; then
        external_port=$(echo "$addon_info" | jq -r ".data.network.\"${port}/tcp\"?" 2>/dev/null)
    fi
fi

bashio::log.info "---------------------------------------------------"
bashio::log.info "Apache2 prêt."
if [ "$external_port" != "null" ] && [ -n "$external_port" ]; then
    bashio::log.info "Accès local : ${protocol}://${host_ip}:${external_port}"
else
    bashio::log.warning "Port externe non déterminé — vérifiez la config des ports."
    bashio::log.info "Accès interne : ${protocol}://$(hostname -i):${port}"
fi
bashio::log.info "---------------------------------------------------"
