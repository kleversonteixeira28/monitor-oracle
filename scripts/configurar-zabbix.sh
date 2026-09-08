#!/usr/bin/env bash
# O Zabbix nasce com Admin/zabbix e com o proprio host apontando para
# 127.0.0.1 - que dentro do container nao e o agente, entao o painel fica
# todo cinza e parece quebrado. Este script conserta as duas coisas pela
# API, uma vez so, e marca que ja fez.
set -euo pipefail

RAIZ="${RAIZ:-/opt/monitor}"
ESTADO="/var/lib/monitor"
MARCA="$ESTADO/zabbix-configurado"
mkdir -p "$ESTADO"

[ -f "$MARCA" ] && exit 0

set -a; . "$RAIZ/.env"; set +a
API="http://zabbix-web:8080/api_jsonrpc.php"
IMG="curlimages/curl:latest"

post() { # corpo na entrada padrao; $1 = token (opcional)
  if [ -n "${1:-}" ]; then
    docker run --rm -i --network monitor "$IMG" -s --max-time 20 -X POST \
      -H 'Content-Type: application/json-rpc' -H "Authorization: Bearer $1" -d @- "$API"
  else
    docker run --rm -i --network monitor "$IMG" -s --max-time 20 -X POST \
      -H 'Content-Type: application/json-rpc' -d @- "$API"
  fi
}

# Login NUNCA leva o cabecalho de token - o Zabbix recusa se levar.
entrar() {
  printf '{"jsonrpc":"2.0","method":"user.login","params":{"username":"Admin","password":"%s"},"id":1}' "$1" \
    | post | jq -r '.result // empty' || true
}

TOKEN=""
TROCAR=0
# A interface web demora a subir depois de um boot frio: ate ~5 min.
for _ in $(seq 1 20); do
  TOKEN="$(entrar "$ZABBIX_ADMIN_SENHA")"
  if [ -n "$TOKEN" ]; then echo "    Zabbix ja estava com a senha do .env"; break; fi
  TOKEN="$(entrar 'zabbix')"
  if [ -n "$TOKEN" ]; then TROCAR=1; break; fi
  sleep 15
done
[ -n "$TOKEN" ] || { echo "    Zabbix nao respondeu ainda"; exit 1; }

USERID="$(printf '{"jsonrpc":"2.0","method":"user.get","params":{"filter":{"username":"Admin"}},"id":2}' \
  | post "$TOKEN" | jq -r '.result[0].userid // empty')"
[ -n "$USERID" ] || { echo "    nao achei o usuario Admin"; exit 1; }

if [ "$TROCAR" = 1 ]; then
  # Zabbix 6+ exige a senha atual para trocar a propria senha.
  printf '{"jsonrpc":"2.0","method":"user.update","params":{"userid":"%s","current_passwd":"zabbix","passwd":"%s"},"id":3}' \
    "$USERID" "$ZABBIX_ADMIN_SENHA" | post "$TOKEN" | jq -e '.result' >/dev/null \
    || { echo "    nao consegui trocar a senha do Admin"; exit 1; }
  echo "    senha do Admin trocada"
  TOKEN="$(entrar "$ZABBIX_ADMIN_SENHA")"
  [ -n "$TOKEN" ] || { echo "    senha trocada mas o login novo falhou"; exit 1; }
fi

# O host "Zabbix server" precisa falar com o container do agente.
INFO="$(printf '{"jsonrpc":"2.0","method":"host.get","params":{"filter":{"host":["Zabbix server"]},"selectInterfaces":["interfaceid"]},"id":4}' | post "$TOKEN")"
HOSTID="$(echo "$INFO" | jq -r '.result[0].hostid // empty')"
IFACE="$(echo "$INFO" | jq -r '.result[0].interfaces[0].interfaceid // empty')"

if [ -n "$IFACE" ]; then
  printf '{"jsonrpc":"2.0","method":"hostinterface.update","params":{"interfaceid":"%s","useip":0,"dns":"zabbix-agent","port":"10050"},"id":5}' \
    "$IFACE" | post "$TOKEN" | jq -e '.result' >/dev/null \
    && echo "    host aponta para o container do agente"
fi
if [ -n "$HOSTID" ]; then
  printf '{"jsonrpc":"2.0","method":"host.update","params":{"hostid":"%s","status":0},"id":6}' \
    "$HOSTID" | post "$TOKEN" >/dev/null
fi

touch "$MARCA"
echo "    Zabbix configurado"
