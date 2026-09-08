#!/usr/bin/env bash
# A imagem Ubuntu da Oracle vem com regras de iptables proprias que descartam
# quase tudo na entrada. Elas confundem: voce libera a porta na Security List
# do painel, testa, e nada responde. Aqui elas saem e quem manda passa a ser
# o ufw - um lugar so para olhar.
#
# CUIDADO que este script toma: a limpeza pesada de iptables acontece UMA VEZ,
# antes do Docker existir. Depois disso, so acrescenta e remove regra do ufw.
# Um "iptables -F FORWARD" com o Docker rodando apaga as regras dele e derruba
# a rede de todos os containers - e o modo dominio mexe no firewall justamente
# quando tudo ja esta no ar.
set -euo pipefail

RAIZ="${RAIZ:-/opt/monitor}"
ESTADO="/var/lib/monitor"
mkdir -p "$ESTADO"

set -a; . "$RAIZ/.env"; set +a

# Universo de portas que este script controla. O que nao esta aqui ele nao toca.
TODAS="22/tcp 80/tcp 443/tcp 443/udp 3000/tcp 8080/tcp 3001/tcp 9000/tcp"

if [ -n "${DOMINIO:-}" ]; then
  QUERO="22/tcp 80/tcp 443/tcp 443/udp"
else
  QUERO="$TODAS"
fi

IMPRESSAO="$(echo "$QUERO" | tr ' ' '\n' | sort | tr '\n' ' ')"
if [ -f "$ESTADO/firewall" ] && [ "$(cat "$ESTADO/firewall")" = "$IMPRESSAO" ] \
   && ufw status 2>/dev/null | grep -q '^Status: active'; then
  echo "    firewall ja esta como deveria"
  exit 0
fi

if [ ! -f "$ESTADO/firewall" ]; then
  # ---- primeira vez: tira as regras da Oracle do caminho -------------------
  # Ordem importa: politica ACCEPT ANTES do flush, senao o flush derruba o SSH.
  iptables -P INPUT ACCEPT
  iptables -P FORWARD ACCEPT
  iptables -F INPUT || true
  iptables -F FORWARD || true
  ip6tables -P INPUT ACCEPT 2>/dev/null || true
  ip6tables -F INPUT 2>/dev/null || true

  DEBIAN_FRONTEND=noninteractive apt-get purge -y -qq \
    netfilter-persistent iptables-persistent >/dev/null 2>&1 || true

  ufw --force reset >/dev/null
  ufw default deny incoming >/dev/null
  ufw default allow outgoing >/dev/null
  for p in $QUERO; do ufw allow "$p" >/dev/null; done
  ufw --force enable >/dev/null
else
  # ---- depois: so converge, sem reset e sem tocar nas cadeias do Docker ----
  for p in $TODAS; do
    if echo " $QUERO " | grep -q " $p "; then
      ufw allow "$p" >/dev/null
    else
      ufw delete allow "$p" >/dev/null 2>&1 || true
    fi
  done
  ufw status | grep -q '^Status: active' || ufw --force enable >/dev/null
fi

echo "$IMPRESSAO" > "$ESTADO/firewall"
echo "    liberado: $IMPRESSAO"
echo "    LEMBRE: a Security List da VCN na Oracle e um segundo firewall."
