# Python Script Manager — add-on Home Assistant

## Installation
1. Copier le dossier `python_manager/` dans `/addons/local/python_manager` sur HAOS
   (via Samba, SSH, ou l'éditeur de fichiers HA).
2. Paramètres → Modules complémentaires → Boutique des modules → ⋮ → Recharger.
3. L'add-on apparaît dans "Add-on local". Installer, régler `terminal_password`
   dans l'onglet Configuration (le mot de passe par défaut `changeme` protège
   uniquement le terminal, changez-le avant tout démarrage).
4. Démarrer. L'UI est accessible via le panneau latéral HA (ingress).

## Stratégie de proxy retenue (pour ne pas exposer un port Docker par script)

Note : le port hôte par défaut est `8095` (conteneur → hôte). Le conteneur
écoute en interne sur `8090`, ce qui n'entre jamais en conflit avec un autre
add-on (chaque conteneur a son propre espace réseau) ; seul le mapping hôte
peut entrer en collision, et il est modifiable sans toucher au YAML via
Paramètres → Modules complémentaires → cet add-on → onglet **Réseau**.

Le problème : si chaque script Python qui tourne un petit serveur web (Flask,
http.server, etc.) devait avoir son propre port mappé dans `config.yaml`,
chaque nouveau script imposerait de republier l'add-on, de rouvrir le
firewall/la box, et complexifierait indéfiniment la conf.

Solution à 3 niveaux :

1. **Aucun port n'est jamais exposé directement par un script.** Chaque
   script qui coche "Expose un service web" reçoit un port interne
   (`$PORT`, alloué dynamiquement dans la plage `script_port_range_start`–
   `script_port_range_end`, par défaut 9000–9099) mais ce port n'écoute
   qu'en local dans le conteneur (`127.0.0.1`).

2. **Un seul port Docker est publié : `8090/tcp`.** Le backend régénère à
   chaque start/stop un fichier de conf nginx
   (`/etc/nginx/conf.d/dynamic_scripts.conf`) qui route
   `http://<host>:8090/s/<nom_du_script>/` → `127.0.0.1:<port_interne>`,
   puis recharge nginx à chaud (`nginx -s reload`, sans coupure). Ajouter un
   100ᵉ script n'ajoute aucun port Docker, aucune règle firewall
   supplémentaire — uniquement une nouvelle entrée dans ce fichier généré.

3. **Pour l'exposition vers Internet**, plutôt que de mapper `8090` sur la
   box/le routeur, il est préférable de le faire remonter dans votre NPM
   existant (déjà utilisé pour `web.somel.ovh`/MQTT WSS) : une entrée
   `scripts.somel.ovh` (ou un chemin dédié) → `192.168.1.70:8090`, avec TLS
   géré par NPM comme pour vos autres flux. Un seul point d'entrée réseau à
   maintenir, cohérent avec le reste de votre infra.

L'UI d'administration, l'éditeur et le terminal, eux, **ne passent jamais
par le port 8090** : ils ne sont accessibles que via l'ingress HA (port
interne 8099, jamais publié sur l'hôte), donc protégés par l'authentification
HA elle-même. Le port 8090 ne sert que le préfixe `/s/…/` ; tout le reste y
renvoie 404.

## Accès API Supervisor
`hassio_api: true` + `homeassistant_api: true` dans `config.yaml` injectent
la variable d'environnement `SUPERVISOR_TOKEN`. Le backend expose deux
routes d'exemple (`/api/supervisor/info`, `/api/supervisor/addons`) — à
étendre selon vos besoins (ex. appeler `/core/api/services/...` pour piloter
des entités HA depuis un script, en passant par le backend ou directement
depuis le script via `SUPERVISOR_TOKEN`, qui lui est aussi accessible en
variable d'environnement pour tout script lancé par le manager).

`hassio_role: manager` est large (accès à d'autres add-ons). Si vos scripts
n'ont besoin que de l'API Core (états, services), passez à `hassio_role:
default` — moindre surface.

## Points où j'ai dû trancher (à valider / corriger si besoin)

Votre prompt ne précisait pas certains choix ; voici les hypothèses prises
et comment les changer si elles ne conviennent pas :

1. **Isolation des scripts** : ils tournent tous comme process du même
   conteneur (pas un conteneur Docker par script). C'est plus simple et
   plus léger, mais un script buggé peut consommer les ressources des
   autres. Si vous voulez une vraie isolation (limites CPU/RAM par script,
   crash indépendant), il faudrait passer à du Docker-in-Docker ou exposer
   le socket Docker de l'hôte à l'add-on — nettement plus lourd à
   sécuriser, dites-moi si c'est un besoin réel avant de le faire.

2. **Terminal** : un terminal web global (`ttyd` + `tmux`), pas un terminal
   par script. Pour "attacher" un script précis, on peut faire
   `tmux new -A -s <nom_script>` côté script si besoin — pas encore câblé
   dans l'UI (case à cocher facile à ajouter si vous voulez ce lien direct
   depuis la liste des scripts).

3. **Persistance de l'état au redémarrage** : les métadonnées (needs_port,
   autostart) survivent dans `/data/state.json`, mais l'implémentation
   actuelle ne relance pas automatiquement les scripts `autostart` au boot
   de l'add-on — c'est un TODO explicite (`start_script()` existe déjà,
   il suffit de boucler dessus dans `entrypoint.sh`/au démarrage FastAPI ;
   je ne l'ai pas activé par défaut pour éviter qu'un script mal débogué
   ne reparte en boucle silencieusement).

4. **Authentification de l'API backend** : protégée uniquement par
   l'ingress HA (donc par votre session HA). Aucune authentification
   séparée sur les routes `/api/*`. C'est cohérent avec le modèle ingress
   standard, mais à garder en tête : quiconque a accès à votre HA a accès
   à l'exécution de code arbitraire sur le mini-PC via ce module.

5. **`/share/addon-python`** : le dossier `map: - share:rw` de `config.yaml`
   monte tout `/share`, j'ai fait créer `/share/addon-python/scripts` au
   démarrage. Si vous préférez restreindre strictement au sous-dossier
   (plutôt que tout `/share`), HA ne permet pas de mapper un sous-dossier
   précis de `/share` nativement — seule option : `addon_config:rw` (dossier
   dédié par add-on, hors de `/share`) si l'isolement du reste de `/share`
   compte plus que la visibilité facile via Samba/l'éditeur de fichiers HA.

## Fichiers du dépôt
```
python_manager/
├── config.yaml                          # manifest add-on (ingress, ports, options)
├── Dockerfile
├── README.md
└── rootfs/
    ├── entrypoint.sh                    # lance nginx + ttyd + backend, gère SIGTERM
    ├── etc/nginx/templates/nginx.conf.template
    └── opt/backend/
        ├── app.py                       # FastAPI : CRUD, start/stop, proxy dynamique
        ├── requirements.txt
        └── static/{index.html,app.js,style.css}
```
