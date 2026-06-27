# Apache2 Documentation

Apache 2 web server for Home Assistant OS PHP 8.5  MariaDB support.

## ⚙️ Configuration

Configure the app via the **Configuration** tab in the Home Assistant App page.

### Options

```yaml
certfile: fullchain.pem
default_conf: default
default_ssl_conf: default
document_root: /share/htdocs
init_commands: []
keyfile: privkey.pem
php_ini: default
ssl: true
website_name: null
```
### Config Apache 
3 modes via default_conf

| Valeur | Valeur |
| --- | --- |
| default | Config générée automatiquement par le script |
| get_config | Exporte la config générée vers /share/httpd.conf et /share/000-default.conf → tu récupères le template |
| /share/mon_apache.conf | Utilise ton fichier custom comme 000-default.conf | 


## Folder Usage

- `/share`: Used to store your website files. The default location is `/share/htdocs`. This allows you to easily edit your website files from outside the app container.
- `/ssl`: Used for SSL certificates (`certfile` and `keyfile`). Required if `ssl: true` is enabled.
- `/data`: Used for persistent storage of the MariaDB database and internal configurations.

<!-- PHP_INFO_START -->

## 🐘 PHP Information

**PHP Version**: 8.5

**Available PHP Modules**:

- bcmath
- bz2
- calendar
- ctype
- curl
- dom
- exif
- fileinfo
- ftp
- gd
- gettext
- iconv
- intl
- ldap
- mbstring
- mysqli
- mysqlnd
- pcntl
- pdo
- pdo_mysql
- pdo_sqlite
- pecl-apcu
- pecl-imagick
- pecl-imap
- pecl-redis
- pecl-xdebug
- phar
- posix
- session
- shmop
- simplexml
- soap
- sockets
- sodium
- sqlite3
- sysvmsg
- sysvsem
- sysvshm
- tokenizer
- xml
- xmlreader
- xmlwriter
- zip
<!-- PHP_INFO_END -->


