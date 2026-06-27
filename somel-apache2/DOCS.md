# Documentation

Serveur web Apache 2 pour Home Assistant OS — PHP 8.5, support MariaDB externe.

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
| `get_config` | Exporte la config générée vers `/share/httpd.conf` et `/share/000-default.conf`, puis arrête l'add-on |
| `/share/mon_apache.conf` | Utilise ton fichier comme `000-default.conf` |

### Configuration PHP — `php_ini`

| Valeur | Comportement |
|---|---|
| `default` | php.ini par défaut |
| `get_file` | Exporte le php.ini vers `/share/apache2App_php.ini`, puis arrête l'add-on |
| `/share/mon.ini` | Utilise ton fichier comme `php.ini` |

## Dossiers

| Dossier | Usage |
|---|---|
| `/share/htdocs` | Fichiers du site web (valeur par défaut de `document_root`) |
| `/ssl` | Certificats SSL (`certfile` et `keyfile`) — requis si `ssl: true` |

## Connexion MariaDB

Pour connecter une application PHP (ex. WordPress) à l'add-on officiel MariaDB :
- **Host** : `core-mariadb`
- **Port** : `3306`
