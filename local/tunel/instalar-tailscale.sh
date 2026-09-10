#!/usr/bin/env bash
# Publica os paineis numa rede privada Tailscale.
#
# POR QUE ISTO E MAIS SIMPLES QUE O CLOUDFLARE TUNNEL:
# nao precisa de dominio, nem de DNS, nem de mexer em nameserver de producao.
# O Tailscale monta uma rede propria por cima da internet, entao nao importa
# se esta maquina esta em outro roteador, atras de NAT ou em outra cidade.
# Nada fica exposto para a internet: so quem esta no SEU tailnet enxerga.
#
# O limite honesto: para alguem ver os paineis, essa pessoa precisa entrar no
# seu tailnet. Se um dia voce quiser mandar um link para um cliente abrir,
# o caminho e o Cloudflare Tunnel (local/tunel/instalar-tunel.sh).
set -euo pipefail

RAIZ="${RAIZ:-/opt/monitor}"

log()   { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
aviso() { printf '\033[1;33m%s\033[0m\n' "$*"; }
verde() { printf '\033[1;32m%s\033[0m\n' "$*"; }
fraco() { printf '\033[2m%s\033[0m\n' "$*"; }
erro()  { printf '\n\033[1;31mERRO: %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" = "0" ] || erro "rode com sudo"

command -v jq >/dev/null || { apt-get update -qq; apt-get install -y -qq jq >/dev/null; }

# --------------------------------------------------------------- 1. instalar
if ! command -v tailscale >/dev/null 2>&1; then
  log "Instalando o Tailscale"
  curl -fsSL https://tailscale.com/install.sh | sh
fi
echo "    $(tailscale version | head -1)"

# ----------------------------------------------------------------- 2. entrar
if ! tailscale status >/dev/null 2>&1; then
  log "Entrando na sua rede Tailscale"
  cat <<'TXT'
    Vai aparecer um endereco aqui embaixo. Abra ele no celular ou em outro PC,
    entre com a sua conta (Google, Microsoft, GitHub - a que preferir) e
    autorize esta maquina.

TXT
  tailscale up
  tailscale status >/dev/null 2>&1 || erro "a maquina nao entrou no tailnet"
fi

IP_TS="$(tailscale ip -4 | head -1)"
NOME_TS="$(tailscale status --json | jq -r '.Self.DNSName' | sed 's/\.$//')"
[ -n "$NOME_TS" ] && [ "$NOME_TS" != "null" ] || erro "nao consegui descobrir o nome desta maquina no tailnet"

echo "    IP no tailnet:   $IP_TS"
echo "    nome no tailnet: $NOME_TS"

# ------------------------------------------------------------- 3. publicar
# Os containers escutam so no 127.0.0.1 (compose/tunel.yml). O 'tailscale
# serve' pega essas portas e oferece para o tailnet - nada vaza para a rede
# local da loja, que e justamente onde ficam as maquinas dos clientes.
log "Publicando os paineis no tailnet"

# Limpa publicacoes antigas, senao rodar de novo empilha configuracao.
tailscale serve reset >/dev/null 2>&1 || true

HTTPS=1
if ! tailscale cert "$NOME_TS" >/dev/null 2>&1; then
  HTTPS=0
  aviso "    Certificado HTTPS indisponivel."
  aviso "    Para ligar: login.tailscale.com/admin/dns -> HTTPS Certificates -> Enable."
  aviso "    Sigo em HTTP. O trafego continua criptografado pelo Tailscale de"
  aviso "    ponta a ponta - o HTTPS aqui e so para o navegador nao reclamar."
fi

publicar() { # $1 = porta publica, $2 = porta local, $3 = nome
  if [ "$HTTPS" = 1 ]; then
    tailscale serve --bg --https="$1" "http://127.0.0.1:$2" >/dev/null
    echo "    https://$NOME_TS:$1  ->  $3"
  else
    tailscale serve --bg --http="$1" "http://127.0.0.1:$2" >/dev/null
    echo "    http://$NOME_TS:$1  ->  $3"
  fi
}

if [ "$HTTPS" = 1 ]; then
  publicar 443  3000 "Grafana"
  publicar 8443 8080 "Zabbix"
  publicar 8444 3001 "Uptime Kuma"
  publicar 8445 9000 "Portainer"
  BASE="https://$NOME_TS"
  ENDERECO_GRAFANA="$BASE"
else
  publicar 3000 3000 "Grafana"
  publicar 8080 8080 "Zabbix"
  publicar 3001 3001 "Uptime Kuma"
  publicar 9000 9000 "Portainer"
  BASE="http://$NOME_TS"
  ENDERECO_GRAFANA="$BASE:3000"
fi

# ------------------------------------------------------------------ 4. .env
log "Gravando os enderecos no .env"
definir() {
  if grep -q "^$1=" "$RAIZ/.env"; then
    sed -i "s|^$1=.*|$1=$2|" "$RAIZ/.env"
  else
    printf '%s=%s\n' "$1" "$2" >> "$RAIZ/.env"
  fi
}
definir MODO tailscale
definir TAILSCALE_HOST "$NOME_TS"
definir TAILSCALE_URL "$ENDERECO_GRAFANA"
chmod 600 "$RAIZ/.env"

# O Grafana precisa saber a propria URL publica, senao os redirecionamentos
# de login voltam para localhost e a tela fica em branco.
log "Recarregando a stack com o endereco certo"
bash "$RAIZ/scripts/sincronizar.sh" --forcar

verde "
  Pronto."
bash "$RAIZ/scripts/senhas.sh"

cat <<TXT
  Para acessar do seu PC ou do celular:
    1. instale o Tailscale (tailscale.com/download)
    2. entre com a MESMA conta
    3. abra os enderecos acima

  Dai em diante voce entra nesta maquina de qualquer lugar, sem VPN da loja
  e sem depender do IP dela:
    ssh $(logname 2>/dev/null || echo SEU-USUARIO)@$IP_TS

TXT
