#!/usr/bin/env bash
# Backup diario: banco do Zabbix + dados do Grafana, Kuma e Portainer.
# Fica em /opt/monitor/backups (fora do git). Guarda BACKUP_DIAS dias.
set -euo pipefail
RAIZ="${RAIZ:-/opt/monitor}"
cd "$RAIZ"
set -a; . "$RAIZ/.env"; set +a

DESTINO="$RAIZ/backups"
HOJE="$(date +%Y-%m-%d)"
mkdir -p "$DESTINO"

docker exec postgres pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  | gzip > "$DESTINO/zabbix-$HOJE.sql.gz"

for v in grafana_dados kuma_dados portainer_dados; do
  docker run --rm -v "monitor_$v:/dados:ro" -v "$DESTINO:/saida" alpine:3 \
    tar czf "/saida/$v-$HOJE.tar.gz" -C /dados . 2>/dev/null || true
done

find "$DESTINO" -type f -mtime "+${BACKUP_DIAS:-7}" -delete
echo "backup de $HOJE pronto: $(du -sh "$DESTINO" | cut -f1) no total"
echo "AVISO: isto e copia LOCAL. Se a instancia sumir, some junto."
echo "Leve para fora: rclone/S3, ou 'scp -r ubuntu@IP:/opt/monitor/backups .'"
