#!/usr/bin/env bash
# Baixa as imagens novas e recria os containers. Rode quando quiser -
# a sincronizacao automatica NAO faz isso sozinha de proposito, para o
# servidor nao mudar de versao numa madrugada sem ninguem olhando.
set -euo pipefail
RAIZ="${RAIZ:-/opt/monitor}"
cd "$RAIZ"
set -a; . "$RAIZ/.env"; set +a
ARQS="-f docker-compose.yml"
[ -z "${DOMINIO:-}" ] && ARQS="$ARQS -f compose/portas-ip.yml"

bash "$RAIZ/scripts/backup.sh"
docker compose $ARQS pull
docker compose $ARQS up -d --remove-orphans
docker image prune -af --filter 'until=168h' >/dev/null
echo "atualizado"
