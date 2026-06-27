ARG BUILD_FROM=ghcr.io/hassio-addons/base:21.0.0
FROM ${BUILD_FROM}

ARG BUILD_DATE="1970-01-01T00:00:00Z"

SHELL ["/bin/ash", "-o", "pipefail", "-c"]

ENV APP_VERSION="1.0.0"
ENV APP_NAME="Apache2"
ENV APP_SLUG="apache2"

WORKDIR /tmp

ARG PHP_VERSION="8.5"
ARG APACHE2_VERSION="2.4.67-r0"

# hadolint ignore=DL3018
RUN mkdir /run/apache2 \
    && apk add --no-cache \
        libcrypto3 libssl3 \
        apache2${APACHE2_VERSION:+=$APACHE2_VERSION} \
        curl \
        jq \
    && PHP_V=$(echo "${PHP_VERSION}" | cut -d. -f1-2 | tr -d '.') \
    && apk add --no-cache \
        "php${PHP_V}-apache2" \
        apache2-utils \
        apache2-ssl \
        apache2-proxy \
        "php${PHP_V}" \
        "php${PHP_V}-fpm" \
        "php${PHP_V}-mysqli" \
        "php${PHP_V}-mysqlnd" \
        "php${PHP_V}-gd" \
        "php${PHP_V}-intl" \
        "php${PHP_V}-curl" \
        "php${PHP_V}-phar" \
        "php${PHP_V}-mbstring" \
        "php${PHP_V}-zip" \
        "php${PHP_V}-xml" \
        "php${PHP_V}-iconv" \
        "php${PHP_V}-pdo" \
        "php${PHP_V}-pdo_mysql" \
        "php${PHP_V}-pdo_sqlite" \
        "php${PHP_V}-sqlite3" \
        "php${PHP_V}-session" \
        "php${PHP_V}-ctype" \
        "php${PHP_V}-simplexml" \
        "php${PHP_V}-dom" \
        "php${PHP_V}-tokenizer" \
        "php${PHP_V}-xmlreader" \
        "php${PHP_V}-xmlwriter" \
        "php${PHP_V}-fileinfo" \
        "php${PHP_V}-soap" \
        "php${PHP_V}-gettext" \
        "php${PHP_V}-bz2" \
        "php${PHP_V}-posix" \
        "php${PHP_V}-bcmath" \
        "php${PHP_V}-sodium" \
        "php${PHP_V}-sockets" \
        "php${PHP_V}-pecl-redis" \
        "php${PHP_V}-pecl-apcu" \
        mariadb-client \
    && rm -f /var/www/localhost/htdocs/index.html

RUN sed -i -r 's@Errorlog .*@Errorlog /dev/stderr@i' /etc/apache2/httpd.conf \
 && sed -i 's/User apache/User www-data/' /etc/apache2/httpd.conf \
 && sed -i 's/Group apache/Group www-data/' /etc/apache2/httpd.conf \
 && echo "Transferlog /dev/stdout" >> /etc/apache2/httpd.conf \
 && (addgroup -S www-data || true) \
 && (adduser -S -G www-data www-data || true)

COPY rootfs /
COPY index.html /var/www/localhost/htdocs/index.html

RUN chmod +x /etc/cont-init.d/apache2.sh /etc/services.d/apache2/run

HEALTHCHECK --interval=60s --timeout=15s --retries=3 CMD curl --fail http://127.0.0.1:80 || exit 1

LABEL org.opencontainers.image.title="Apache2"
LABEL org.opencontainers.image.description="Apache2 PHP MariaDB for Home Assistant"
LABEL org.opencontainers.image.vendor="somel"
LABEL org.opencontainers.image.authors="somel <https://github.com/somel-web>"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
