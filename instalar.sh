#!/usr/bin/env bash
# Prepara o servidor do zero. Roda no primeiro boot (cloud-init) e pode ser
# rodado de novo a qualquer momento - e idempotente.
#   sudo bash /opt/monitor/instalar.sh
set -euo pipefail

RAIZ="/opt/monitor"
ESTADO="/var/lib/monitor"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
erro() { printf '\n\033[1;31mERRO: %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" = "0" ] || erro "rode com sudo"

esperar_apt() {
  local i=0
  while pgrep -x apt-get >/dev/null || pgrep -x apt >/dev/null || pgrep -x unattended-upgr >/dev/null; do
    i=$((i + 1)); [ "$i" -gt 90 ] && break
    echo "    aguardando outro apt terminar ($i)"; sleep 10
  done
}

mkdir -p "$ESTADO"

# ---------------------------------------------------------------- 1. pacotes
log "Instalando pacotes base"
esperar_apt
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq git curl ca-certificates jq ufw fail2ban unattended-upgrades \
  chrony htop ncdu tzdata >/dev/null

# ------------------------------------------------------------------ 2. hora
log "Fuso horario America/Sao_Paulo"
timedatectl set-timezone America/Sao_Paulo || true
systemctl enable --now chrony >/dev/null 2>&1 || true

# ------------------------------------------------------------------- 3. swap
if ! swapon --show | grep -q .; then
  log "Criando swap de 2 GB"
  fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  sysctl -qw vm.swappiness=10
  echo 'vm.swappiness=10' > /etc/sysctl.d/99-monitor.conf
fi

# ------------------------------------------------------------------- 4. repo
if [ ! -d "$RAIZ/.git" ]; then
  erro "$RAIZ nao e um clone do repositorio. O cloud-init deveria ter clonado."
fi
cd "$RAIZ"
git config --global --add safe.directory "$RAIZ"

# -------------------------------------------------------------------- 5. env
log "Gerando/completando o .env"
bash "$RAIZ/scripts/gerar-env.sh"

# --------------------------------------------------------------- 6. firewall
# Antes do Docker de proposito: mexer em iptables com o Docker ja rodando
# derruba a rede dos containers no meio do caminho.
log "Configurando o firewall"
bash "$RAIZ/scripts/firewall.sh"

# ----------------------------------------------------------------- 7. docker
if ! command -v docker >/dev/null 2>&1; then
  log "Instalando o Docker"
  curl -fsSL https://get.docker.com | sh
fi
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'JSON'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "live-restore": true
}
JSON
systemctl enable --now docker >/dev/null 2>&1 || true
systemctl restart docker
id -nG ubuntu 2>/dev/null | grep -qw docker || usermod -aG docker ubuntu 2>/dev/null || true

# ----------------------------------------------------------------- 8. ssh/f2b
log "Endurecendo SSH e ligando o fail2ban"
cat > /etc/ssh/sshd_config.d/99-monitor.conf <<'SSH'
PasswordAuthentication no
PermitRootLogin no
X11Forwarding no
SSH
systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true

cat > /etc/fail2ban/jail.d/monitor.conf <<'F2B'
[sshd]
enabled = true
maxretry = 5
findtime = 10m
bantime = 1h
F2B
systemctl enable --now fail2ban >/dev/null 2>&1 || true

# Atualizacoes de seguranca sozinhas (sem reboot automatico).
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'AU'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
AU

# --------------------------------------------------------------- 9. systemd
log "Instalando os temporizadores (sincronizacao e backup)"
install -m 644 "$RAIZ/systemd/"*.service "$RAIZ/systemd/"*.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now monitor-sync.timer monitor-backup.timer >/dev/null

# --------------------------------------------------------------- 10. subir
log "Subindo a stack (a primeira vez baixa ~1,5 GB, leva alguns minutos)"
bash "$RAIZ/scripts/sincronizar.sh" --forcar

touch "$ESTADO/instalado"
log "Pronto"
bash "$RAIZ/scripts/senhas.sh"
