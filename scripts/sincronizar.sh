#!/usr/bin/env bash
# O laco GitOps: puxa o repositorio e faz a maquina virar o que o repositorio
# diz. Roda de 5 em 5 minutos pelo monitor-sync.timer.
# Voce edita no PC -> git push -> em ate 5 min o servidor esta assim.
set -euo pipefail

RAIZ="${RAIZ:-/opt/monitor}"
cd "$RAIZ"
export RAIZ

# Duas execucoes ao mesmo tempo bagunçam o docker compose.
exec 9>/var/lock/monitor-sync.lock
flock -n 9 || { echo "outra sincronizacao em andamento"; exit 0; }

FORCAR=0
[ "${1:-}" = "--forcar" ] && FORCAR=1

git config --global --add safe.directory "$RAIZ" 2>/dev/null || true
git fetch --quiet origin || { echo "sem rede para o GitHub agora"; }

LOCAL="$(git rev-parse HEAD)"
REMOTO="$(git rev-parse '@{u}' 2>/dev/null || echo "$LOCAL")"

MUDOU=0
if [ "$LOCAL" != "$REMOTO" ]; then
  echo "==> Repositorio mudou: $(git log --oneline -1 "$REMOTO")"
  # reset --hard e seguro aqui: .env, dados/ e backups/ estao no .gitignore.
  git reset --hard --quiet "$REMOTO"
  MUDOU=1
fi
[ "$FORCAR" = 1 ] && MUDOU=1

bash "$RAIZ/scripts/gerar-env.sh"
set -a; . "$RAIZ/.env"; set +a

# Escolhe o Caddyfile e as portas conforme o MODO.
case "${MODO:-oracle}" in
  tunel)
    # Quem termina o HTTPS e a Cloudflare. O Caddy so roteia, em HTTP, e
    # escuta apenas no 127.0.0.1 - o cloudflared roda na mesma maquina.
    # Usar o Caddyfile.dominio aqui seria erro: ele tentaria tirar certificado
    # e falharia para sempre, porque nao ha porta 80 aberta vinda de fora.
    [ -n "${DOMINIO:-}" ] || { echo "MODO=tunel exige DOMINIO no .env"; exit 1; }
    MODELO="caddy/Caddyfile.ip"
    ARQS="-f docker-compose.yml -f compose/tunel.yml"
    ;;
  *)
    if [ -n "${DOMINIO:-}" ]; then
      MODELO="caddy/Caddyfile.dominio"
      ARQS="-f docker-compose.yml"
    else
      MODELO="caddy/Caddyfile.ip"
      ARQS="-f docker-compose.yml -f compose/portas-ip.yml"
    fi
    ;;
esac
if ! cmp -s "$MODELO" caddy/Caddyfile 2>/dev/null; then
  cp "$MODELO" caddy/Caddyfile
  echo "==> Caddyfile trocado para $(basename "$MODELO")"
  MUDOU=1
fi

# Barato e idempotente: so mexe se as portas desejadas mudaram.
if [ "$(id -u)" = "0" ]; then bash "$RAIZ/scripts/firewall.sh"; fi

if [ "$MUDOU" = 1 ]; then
  docker compose $ARQS pull --quiet || true
fi
docker compose $ARQS up -d --remove-orphans

bash "$RAIZ/scripts/configurar-zabbix.sh" || echo "aviso: Zabbix ainda nao respondeu; tento de novo no proximo ciclo"

echo "==> Sincronizado em $(date '+%d/%m %H:%M')"
