#!/usr/bin/env bash
# Mostra os enderecos e as senhas geradas. Nada disto esta no GitHub.
set -euo pipefail
RAIZ="${RAIZ:-/opt/monitor}"
set -a; . "$RAIZ/.env"; set +a

if [ -n "${DOMINIO:-}" ]; then
  G="https://grafana.$DOMINIO"; Z="https://zabbix.$DOMINIO"
  K="https://status.$DOMINIO"; P="https://docker.$DOMINIO"
else
  IP="$(curl -s --max-time 5 https://api.ipify.org || echo SEU-IP)"
  G="http://$IP:3000"; Z="http://$IP:8080"; K="http://$IP:3001"; P="http://$IP:9000"
fi

cat <<TXT

  ACESSOS
  --------------------------------------------------------------
  Grafana     $G
              $GRAFANA_ADMIN_USER / $GRAFANA_ADMIN_SENHA

  Zabbix      $Z
              Admin / $ZABBIX_ADMIN_SENHA

  Uptime Kuma $K
              (a primeira tela pede para voce criar o usuario)

  Portainer   $P
              admin / $PORTAINER_SENHA

  Prometheus  nao fica exposto de proposito (nao tem login nenhum).
              Para abrir no seu PC:  bash scripts/tunel-prometheus.sh
  --------------------------------------------------------------
  Para ver isto de novo:  sudo bash /opt/monitor/scripts/senhas.sh

TXT
