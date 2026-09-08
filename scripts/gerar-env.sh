#!/usr/bin/env bash
# Cria /opt/monitor/.env a partir de .env.exemplo.
# Chave que ja existe no .env NUNCA e sobrescrita - senha nao muda sozinha.
# Chave nova no molde e acrescentada. Valor "GERAR" vira senha aleatoria.
set -euo pipefail

RAIZ="${RAIZ:-/opt/monitor}"
ENV="$RAIZ/.env"
MOLDE="$RAIZ/.env.exemplo"

[ -f "$ENV" ] || { : > "$ENV"; }
chmod 600 "$ENV"

senha() {
  # Sem / + = $ : quebram URL do Postgres e a interpolacao do compose.
  openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | cut -c1-24
}

novas=0
while IFS= read -r linha || [ -n "$linha" ]; do
  case "$linha" in ''|\#*) continue ;; esac
  chave="${linha%%=*}"
  valor="${linha#*=}"
  case "$chave" in *[!A-Za-z0-9_]*) continue ;; esac
  grep -q "^${chave}=" "$ENV" && continue
  [ "$valor" = "GERAR" ] && valor="$(senha)"
  printf '%s=%s\n' "$chave" "$valor" >> "$ENV"
  novas=$((novas + 1))
done < "$MOLDE"

[ "$novas" -gt 0 ] && echo "    $novas chave(s) nova(s) no .env"

# GRAFANA_URL e derivada, entao e recalculada toda vez.
set -a; . "$ENV"; set +a
if [ -n "${DOMINIO:-}" ]; then
  URL="https://grafana.${DOMINIO}"
else
  IP="$(curl -s --max-time 5 https://api.ipify.org || true)"
  [ -n "$IP" ] || IP="$(curl -s --max-time 5 -H 'Authorization: Bearer Oracle' \
      http://169.254.169.254/opc/v2/vnics/ | jq -r '.[0].publicIp // empty' || true)"
  [ -n "$IP" ] || IP="localhost"
  URL="http://${IP}:3000"
fi
grep -v '^GRAFANA_URL=' "$ENV" > "$ENV.tmp" || true
printf 'GRAFANA_URL=%s\n' "$URL" >> "$ENV.tmp"
mv "$ENV.tmp" "$ENV"
chmod 600 "$ENV"

# O Portainer trava a conta se ninguem definir a senha em 5 min. Esta arquivo
# e montado no container e resolve isso antes de existir o problema.
mkdir -p "$RAIZ/dados"
grep '^PORTAINER_SENHA=' "$ENV" | cut -d= -f2- > "$RAIZ/dados/portainer_senha"
chmod 600 "$RAIZ/dados/portainer_senha"
