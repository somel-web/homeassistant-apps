# Documentation

Serveur web Apache 2 pour Home Assistant OS — PHP 8.5
php composer installé

## ⚙️ Configuration

Configure l'add-on via l'onglet **Configuration** dans la page de l'add-on.

### Options

```yaml
document_root: /share/htdocs
website_name: "web.local"
ssl: false
certfile: fullchain.pem
keyfile: privkey.pem
php_ini: default
default_conf: default
default_ssl_conf: default
init_commands: []
```

### Configuration Apache — `default_conf`

| Valeur | Comportement |
|---|---|
| `default` | Config Apache générée automatiquement |
| `get_config` | Exporte la config vers `/share/somel-apache-httpd.conf` (httpd.conf complet, informatif) et `/share/somel-apache-000-default.conf` (gabarit de VirtualHost, généré même sans SSL — c'est **celui-ci** qu'il faut éditer et réutiliser), puis arrête l'add-on |
| `/share/mon_apache.conf` | Copie ton fichier dans `sites-enabled/000-default.conf`, inclus depuis `httpd.conf` — donc utilisé comme un VirtualHost, PAS comme remplacement du `httpd.conf` (ne pas y mettre `ServerRoot`, `Listen`, `LoadModule`, `User`/`Group`, déjà définis ailleurs) |

### Configuration PHP — `php_ini`

| Valeur | Comportement |
|---|---|
| `default` | php.ini par défaut |
| `get_file` | Exporte le php.ini vers `/share/apache2App_php.ini`, puis arrête l'add-on |
| `/share/mon.ini` | Utilise ton fichier comme `php.ini` pour PHP |

### Résumé du workflow complet de configuration (exemple pour apache)

1. default_conf: get_config
   → exporte les httpd.conf + 000-default.conf dans /share/
   → arrête l'add-on

2. Tu édites une des conf par ex /share/somel-apache-000-default.conf selon tes besoins

3. dans default_conf: /share/somel-apache-000-default.conf
   → utilise ce fichier comme VirtualHost
   
On peut donc aavoir plusieurs conf differentes

## Dossiers

| Dossier | Usage |
|---|---|
| `/share/htdocs` | Fichiers du site web (valeur par défaut de `document_root`) |
| `/ssl` | Certificats SSL (`certfile` et `keyfile`) — requis si `ssl: true` |

## utilisation composer

depuis le terminal de l'add-on via le SSH add-on ou le terminal HA
```bash
# trouver le nom du container
docker ps --format "table {{.Names}}" | grep apache
#par exemple addon_2f52e210_somel-apache2

# Entrer dans le container
docker exec -it addon_xxxx_somel-apache2 ash

# Dans le container
cd /share/htdocs/mon-projet
composer install
```
Ou via init_commands dans la config de l'add-on :
```yaml
init_commands:
  - "cd /share/htdocs/mon-projet && composer install --no-dev"
```
## Connexion MariaDB

Pour connecter une application PHP à l'add-on officiel MariaDB :
- **Host** : `core-mariadb`
- **Port** : `3306`

## Client SSH

`openssh-client` est installé dans l'image (depuis la v1.0.4), pour les scripts
PHP qui ont besoin de se connecter en sortant vers un autre appareil du LAN
(ex: watchdog qui vérifie/relance un service distant via SSH par clé).

Générer une clé dédiée, stockée dans `/share/` pour survivre aux redémarrages :
```bash
mkdir -p /share/ssh_keys
ssh-keygen -t ed25519 -N "" -f /share/ssh_keys/ma_cle -C "description"
```

⚠️ Les requêtes PHP sont traitées par les process enfants Apache, qui tournent
en `www-data` — pas en `root`, même si le shell `docker exec`/terminal l'est.
La clé privée doit appartenir à `www-data` pour être lisible par PHP :
```bash
chown www-data:www-data /share/ssh_keys/ma_cle
chmod 600 /share/ssh_keys/ma_cle
```
