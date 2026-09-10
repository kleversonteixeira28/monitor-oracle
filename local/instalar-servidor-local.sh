#!/usr/bin/env bash
# Instala o monitoramento numa maquina SUA (mini PC, PC velho, Raspberry),
# publicada na internet por Cloudflare Tunnel - sem abrir porta no roteador.
#
# Rode numa instalacao limpa de Ubuntu Server 24.04:
#   sudo apt install -y git
#   sudo git clone https://github.com/kleversonteixeira28/monitor-oracle.git /opt/monitor
#   sudo bash /opt/monitor/local/instalar-servidor-local.sh
set -euo pipefail

RAIZ="/opt/monitor"
export RAIZ

log()   { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
aviso() { printf '\033[1;33m%s\033[0m\n' "$*"; }
erro()  { printf '\n\033[1;31mERRO: %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" = "0" ] || erro "rode com sudo"
[ -d "$RAIZ/.git" ] || erro "clone o repositorio em $RAIZ primeiro (veja o cabecalho deste arquivo)"

# ---------------------------------------------------------------- sobreviver
# Esta instalacao baixa ~1,5 GB e leva de 10 a 20 minutos. Rodando presa a uma
# sessao SSH, qualquer oscilacao de rede mata o processo no meio - com Docker
# baixado pela metade e a stack sem subir. Dentro do tmux ela continua rodando
# mesmo que a conexao caia, e voce volta para ela quando reconectar.
if [ -n "${SSH_CONNECTION:-}" ] && [ -z "${TMUX:-}" ] && [ "${SEM_TMUX:-0}" != "1" ]; then
  if ! command -v tmux >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq tmux >/dev/null 2>&1 || true
  fi
  if command -v tmux >/dev/null 2>&1; then
    aviso ""
    aviso "  Voce esta por SSH. Vou rodar dentro de um tmux, para a instalacao"
    aviso "  nao morrer se a conexao cair."
    aviso ""
    aviso "  Se cair: reconecte e volte com   tmux attach -t monitor"
    aviso ""
    sleep 3
    exec tmux new-session -A -s monitor "bash '$0' $*; echo; echo '--- terminou. Enter para sair.'; read -r _"
  fi
fi

# ------------------------------------------------------- como sera acessado
echo
cat <<'TXT'
  Como voce quer alcancar os paineis?

    1) Tailscale  - rede privada sua. Sem dominio, sem DNS, nada exposto na
                    internet. Funciona de qualquer lugar, mesmo com a maquina
                    atras do roteador da loja. Quem for ver precisa entrar no
                    seu tailnet. E o caminho mais curto.

    2) Cloudflare - endereco publico (grafana.seu-dominio) que qualquer um
       Tunnel       abre no navegador. Exige um dominio com os nameservers
                    na Cloudflare.

TXT
printf "  1 ou 2 [1]: "
read -r ESCOLHA
[ -n "$ESCOLHA" ] || ESCOLHA=1

definir() { # chave valor - troca se existir, acrescenta se nao
  if grep -q "^$1=" "$RAIZ/.env"; then
    sed -i "s|^$1=.*|$1=$2|" "$RAIZ/.env"
  else
    printf '%s=%s\n' "$1" "$2" >> "$RAIZ/.env"
  fi
}

if [ "$ESCOLHA" = "1" ]; then
  log "Preparando a maquina (isto leva alguns minutos)"
  bash "$RAIZ/scripts/gerar-env.sh"
  definir MODO tailscale
  chmod 600 "$RAIZ/.env"
  bash "$RAIZ/instalar.sh"
  log "Agora o Tailscale"
  bash "$RAIZ/local/tunel/instalar-tailscale.sh"
  exit 0
fi

# ------------------------------------------------------------------ dominio
DOMINIO="${DOMINIO:-}"
if [ -z "$DOMINIO" ] && [ -f "$RAIZ/.env" ]; then
  DOMINIO="$(sed -n 's/^DOMINIO=//p' "$RAIZ/.env" | head -1)"
fi

if [ -z "$DOMINIO" ]; then
  cat <<'TXT'

  Qual dominio vai publicar o monitoramento?

  Ele precisa estar com os NAMESERVERS na Cloudflare - e ai mora a decisao:
  mover o skfoods.com.br para la significa migrar o DNS de PRODUCAO. Se um
  registro se perder no caminho, a loja sai do ar. Isso e uma tarefa a parte,
  feita com calma, conferindo registro por registro antes de trocar.

  Se nao quiser mexer no dominio da loja agora, use outro dominio so para
  infraestrutura. Um .xyz ou .site custa poucos reais por ano e nao tem nada
  de producao dependendo dele.

TXT
  printf "  Dominio (ex: skfoods.com.br): "
  read -r DOMINIO
  [ -n "$DOMINIO" ] || erro "sem dominio nao da para seguir"
fi

# ---------------------------------------------------------------- .env / MODO
log "Marcando MODO=tunel no .env"
bash "$RAIZ/scripts/gerar-env.sh"

definir MODO tunel
definir DOMINIO "$DOMINIO"
chmod 600 "$RAIZ/.env"
echo "    MODO=tunel  DOMINIO=$DOMINIO"

# ------------------------------------------------------------------ o resto
# O instalar.sh ja faz pacotes, fuso, swap, docker, fail2ban, ufw e os timers.
# Com MODO=tunel ele nao abre porta nenhuma: so o SSH, para a rede local.
log "Preparando a maquina (isto leva alguns minutos)"
bash "$RAIZ/instalar.sh"

# ------------------------------------------------------------------- tunel
log "Agora o tunel"
bash "$RAIZ/local/tunel/instalar-tunel.sh"
