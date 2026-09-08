#!/usr/bin/env bash
# Estado do servidor em uma tela. Roda sem quebrar nada.
set -uo pipefail
RAIZ="${RAIZ:-/opt/monitor}"
cd "$RAIZ" 2>/dev/null || true
set -a; . "$RAIZ/.env" 2>/dev/null; set +a

echo "=============================================================="
echo " RAIO-X  -  $(date '+%d/%m/%Y %H:%M')"
echo "=============================================================="
echo
echo "-- Maquina"
echo "   ligada ha: $(uptime -p 2>/dev/null)"
echo "   carga:     $(cut -d' ' -f1-3 /proc/loadavg)"
free -h | awk 'NR==1||NR==2{printf "   %s\n",$0}'
df -h / | awk 'NR==2{printf "   disco /: %s de %s usados (%s)\n",$3,$2,$5}'
echo

echo "-- Containers"
if command -v docker >/dev/null; then
  docker ps -a --format '   {{.Names}}|{{.State}}|{{.Status}}' \
    | column -t -s'|' 2>/dev/null || docker ps -a --format '   {{.Names}} {{.Status}}'
  PARADOS="$(docker ps -a --filter 'status=exited' --filter 'status=dead' --format '{{.Names}}')"
  [ -n "$PARADOS" ] && { echo; echo "   ATENCAO - parados: $PARADOS"; echo "   veja o motivo: docker logs --tail 50 NOME"; }
else
  echo "   docker nao instalado"
fi
echo

echo "-- Firewall (ufw)"
ufw status 2>/dev/null | sed 's/^/   /' || echo "   sem permissao (use sudo)"
echo
echo "   Lembrete: a Security List da VCN na Oracle e um SEGUNDO firewall."
echo "   Porta liberada aqui e fechada la = nao responde."
echo

echo "-- Sincronizacao com o GitHub"
echo "   commit atual: $(git -C "$RAIZ" log --oneline -1 2>/dev/null)"
systemctl is-active monitor-sync.timer >/dev/null 2>&1 \
  && echo "   timer: ativo (a cada 5 min)" || echo "   timer: INATIVO"
echo "   ultima: $(systemctl show monitor-sync.service -p ExecMainStartTimestamp --value 2>/dev/null)"
echo

echo "-- Backups"
ls -lh "$RAIZ/backups" 2>/dev/null | tail -n 8 | sed 's/^/   /' || echo "   nenhum ainda"
echo
