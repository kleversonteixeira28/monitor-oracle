#!/usr/bin/env bash
# Publica o monitoramento pela internet usando Cloudflare Tunnel.
#
# POR QUE TUNEL E NAO ABRIR PORTA NO ROTEADOR:
# o cloudflared faz uma conexao de SAIDA para a Cloudflare e o trafego volta
# por ela. Nao existe porta aberta no seu roteador, entao nao ha o que alguem
# varrer, e o IP da sua loja nao aparece em lugar nenhum. Alem disso o HTTPS
# fica por conta da Cloudflare - sem certificado para renovar aqui dentro.
#
# PRE-REQUISITO: o dominio precisa estar com os NAMESERVERS na Cloudflare.
# Nao basta ter conta: o dominio tem que estar la.
set -euo pipefail

RAIZ="${RAIZ:-/opt/monitor}"
NOME_TUNEL="${NOME_TUNEL:-monitor}"
CFDIR="/etc/cloudflared"

log()   { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
aviso() { printf '\033[1;33m%s\033[0m\n' "$*"; }
verde() { printf '\033[1;32m%s\033[0m\n' "$*"; }
erro()  { printf '\n\033[1;31mERRO: %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" = "0" ] || erro "rode com sudo"
[ -f "$RAIZ/.env" ] || erro "$RAIZ/.env nao existe - rode o instalador primeiro"

set -a; . "$RAIZ/.env"; set +a
[ -n "${DOMINIO:-}" ] || erro "DOMINIO vazio no .env"
[ "${MODO:-}" = "tunel" ] || aviso "  aviso: MODO no .env nao e 'tunel' - o Caddy pode estar publicando portas."

command -v jq >/dev/null || { apt-get update -qq; apt-get install -y -qq jq >/dev/null; }

# ------------------------------------------------------------ 1. cloudflared
if ! command -v cloudflared >/dev/null 2>&1; then
  log "Instalando o cloudflared"
  install -d -m 0755 /usr/share/keyrings
  curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
    -o /usr/share/keyrings/cloudflare-main.gpg
  echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" \
    > /etc/apt/sources.list.d/cloudflared.list
  apt-get update -qq
  apt-get install -y -qq cloudflared >/dev/null
fi
echo "    $(cloudflared --version 2>&1 | head -1)"

# ----------------------------------------------------------------- 2. login
if [ ! -f /root/.cloudflared/cert.pem ]; then
  log "Autorizando na sua conta Cloudflare"
  cat <<'TXT'
    Vai aparecer um endereco aqui embaixo. Abra ele no navegador de QUALQUER
    maquina (nao precisa ser esta), entre na sua conta Cloudflare e escolha o
    dominio. Se este servidor nao tem navegador, e assim mesmo que se faz.

TXT
  cloudflared tunnel login
  [ -f /root/.cloudflared/cert.pem ] || erro "a autorizacao nao concluiu"
fi

# ------------------------------------------------------------------ 3. tunel
achar_uuid() {
  cloudflared tunnel list --output json 2>/dev/null \
    | jq -r --arg n "$NOME_TUNEL" '.[] | select(.name==$n) | .id' | head -1
}

UUID="$(achar_uuid)"
if [ -z "$UUID" ]; then
  log "Criando o tunel '$NOME_TUNEL'"
  cloudflared tunnel create "$NOME_TUNEL"
  UUID="$(achar_uuid)"
  [ -n "$UUID" ] || erro "criei o tunel mas nao achei o id dele"
else
  echo "    tunel '$NOME_TUNEL' ja existia: $UUID"
fi

install -d -m 0755 "$CFDIR"
install -m 600 "/root/.cloudflared/$UUID.json" "$CFDIR/$UUID.json"

# --------------------------------------------------------------- 4. ingress
# Cada nome vai direto na porta que o Caddy escuta no loopback.
log "Escrevendo $CFDIR/config.yml"
cat > "$CFDIR/config.yml" <<EOF
# Gerado por local/tunel/instalar-tunel.sh - editar aqui e perder na proxima vez.
tunnel: $UUID
credentials-file: $CFDIR/$UUID.json

# originRequest sem TLS: o trafego daqui ate o Caddy nunca sai da maquina.
ingress:
  - hostname: grafana.$DOMINIO
    service: http://localhost:3000
  - hostname: zabbix.$DOMINIO
    service: http://localhost:8080
  - hostname: status.$DOMINIO
    service: http://localhost:3001
  - hostname: docker.$DOMINIO
    service: http://localhost:9000
  # Obrigatorio: o que nao casar com nada acima morre aqui.
  - service: http_status:404
EOF

# ------------------------------------------------------------------- 5. DNS
log "Apontando os nomes para o tunel"
for nome in grafana zabbix status docker; do
  if cloudflared tunnel route dns "$NOME_TUNEL" "$nome.$DOMINIO" >/dev/null 2>&1; then
    echo "    criado:  $nome.$DOMINIO"
  else
    # Ja existir e o caso normal ao rodar de novo.
    echo "    ja havia: $nome.$DOMINIO"
  fi
done

# --------------------------------------------------------------- 6. servico
if systemctl list-unit-files 2>/dev/null | grep -q '^cloudflared\.service'; then
  log "Reiniciando o servico"
  systemctl restart cloudflared
else
  log "Instalando o servico"
  cloudflared service install
  systemctl enable --now cloudflared
fi

sleep 5
if systemctl is-active --quiet cloudflared; then
  verde "  Tunel no ar."
else
  aviso "  O servico nao subiu. Veja o motivo com:"
  aviso "    journalctl -u cloudflared -n 50 --no-pager"
  exit 1
fi

cat <<TXT

  ENDERECOS
  --------------------------------------------------------------
  Grafana      https://grafana.$DOMINIO
  Zabbix       https://zabbix.$DOMINIO
  Uptime Kuma  https://status.$DOMINIO
  Portainer    https://docker.$DOMINIO
  --------------------------------------------------------------
  As senhas:  sudo bash $RAIZ/scripts/senhas.sh

  O DNS da Cloudflare pode levar um ou dois minutos para propagar.

  IMPORTANTE: qualquer um na internet que souber o endereco chega na tela de
  login. As senhas geradas sao fortes, mas se quiser fechar de vez, o
  Cloudflare Access (gratis ate 50 usuarios) poe uma autenticacao ANTES de
  chegar aqui - se configura no painel da Cloudflare, em Zero Trust.

TXT
