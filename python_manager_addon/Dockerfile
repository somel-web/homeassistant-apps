ARG BUILD_FROM=python:3.12-alpine
FROM $BUILD_FROM

# nginx      : reverse-proxy interne (ingress + proxy externe unique)
# ttyd+tmux  : terminal web (tmux permet de garder la session vivante entre reconnexions)
# bash       : entrypoint plus confortable que sh pour les traps de signaux
# git/curl   : utilitaires courants pour les scripts de l'utilisateur
RUN apk add --no-cache nginx ttyd tmux bash git curl shadow envsubst

COPY rootfs/opt/backend/requirements.txt /opt/backend/requirements.txt
RUN pip install --no-cache-dir -r /opt/backend/requirements.txt

COPY rootfs/ /

RUN mkdir -p /share/addon-python/scripts /data/logs && \
    chmod +x /entrypoint.sh

WORKDIR /opt/backend

# 8099 = ingress (interne, jamais mappé sur l'hôte via `ports:`)
# 8090 = proxy externe unique pour les scripts web (voir config.yaml)
EXPOSE 8099 8090

ENTRYPOINT [ "/entrypoint.sh" ]
