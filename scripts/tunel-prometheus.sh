#!/usr/bin/env bash
# O Prometheus nao tem login. Em vez de expor, publique-o so para voce:
# este script sobe a porta 9090 do servidor no seu proprio PC.
# Rode NO SEU PC (Git Bash / WSL), nao no servidor:
#   IP=SEU-IP bash tunel-prometheus.sh   -> depois abra http://localhost:9090
set -euo pipefail
: "${IP:?informe o IP:  IP=1.2.3.4 bash tunel-prometheus.sh}"
echo "Abrindo tunel. Deixe esta janela aberta. Ctrl+C encerra."
echo "Acesse: http://localhost:9090"
ssh -N -L 9090:127.0.0.1:9090 "ubuntu@$IP" \
  -o ExitOnForwardFailure=yes
