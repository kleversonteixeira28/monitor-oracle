#!/usr/bin/env bash
# Sobe a MESMA stack no seu proprio computador, para testar sem depender da
# Oracle. Roda dentro do WSL (Ubuntu) ou em qualquer Linux com Docker.
#
#   bash local/testar-local.sh          sobe tudo
#   bash local/testar-local.sh --parar  desliga (os dados ficam)
#   bash local/testar-local.sh --apagar desliga e APAGA os dados
#
# O que este script NAO faz, de proposito: firewall, swap, fail2ban, timers do
# systemd, sincronizacao com o GitHub. Isso e endurecimento de servidor exposto
# na internet - na sua maquina so atrapalharia. Para o servidor de verdade quem
# faz e o instalar.sh.
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export RAIZ
export MODO_LOCAL=1

vermelho() { printf '\033[1;31m%s\033[0m\n' "$*"; }
verde()    { printf '\033[1;32m%s\033[0m\n' "$*"; }
fraco()    { printf '\033[2m%s\033[0m\n' "$*"; }
morrer()   { vermelho ""; vermelho "  $*"; vermelho ""; exit 1; }

ARQS="-f $RAIZ/docker-compose.yml -f $RAIZ/compose/portas-ip.yml"

case "${1:-}" in
  --parar)
    cd "$RAIZ" && docker compose $ARQS down
    echo "  parado. Os dados continuam nos volumes; suba de novo quando quiser."
    exit 0 ;;
  --apagar)
    cd "$RAIZ" && docker compose $ARQS down -v
    rm -f /var/lib/monitor/zabbix-configurado 2>/dev/null || true
    echo "  parado e dados apagados."
    exit 0 ;;
  "") ;;
  *) morrer "argumento desconhecido: $1" ;;
esac

# ------------------------------------------------------------- pre-requisitos
command -v docker >/dev/null || morrer "Docker nao instalado. Dentro do WSL:
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker \$USER
e depois feche e reabra o terminal do WSL."

if ! docker info >/dev/null 2>&1; then
  morrer "O Docker esta instalado mas nao esta rodando.

No WSL, o jeito limpo e ligar o systemd. Crie /etc/wsl.conf com:
  [boot]
  systemd=true
depois, no PowerShell:  wsl --shutdown
reabra o WSL e rode:    sudo systemctl enable --now docker

Alternativa rapida sem systemd:  sudo dockerd > /tmp/docker.log 2>&1 &"
fi

# ------------------------------------------------------------------- preparo
echo
echo "  Preparando..."
bash "$RAIZ/scripts/gerar-env.sh"

# No modo local sempre o Caddyfile de IP: sem dominio, sem HTTPS.
cp "$RAIZ/caddy/Caddyfile.ip" "$RAIZ/caddy/Caddyfile"

# /var/lib/monitor guarda a marca de "zabbix ja configurado".
sudo mkdir -p /var/lib/monitor 2>/dev/null || mkdir -p /var/lib/monitor 2>/dev/null || true
sudo chown "$(id -u):$(id -g)" /var/lib/monitor 2>/dev/null || true

echo
echo "  Subindo os containers (a primeira vez baixa ~1,5 GB)..."
cd "$RAIZ"
docker compose $ARQS up -d --remove-orphans

echo
echo "  Configurando o Zabbix (ele demora uns minutos para responder)..."
bash "$RAIZ/scripts/configurar-zabbix.sh" || \
  fraco "    ainda nao respondeu - rode este script de novo daqui a pouco"

echo
verde "  No ar."
bash "$RAIZ/scripts/senhas.sh"

fraco "  Isto e teste local: so a sua maquina alcanca, e sem HTTPS."
fraco "  Para desligar:  bash local/testar-local.sh --parar"
echo
