#!/usr/bin/env bash
# Versao para o Oracle Cloud Shell (o terminal dentro do painel da Oracle).
# Vantagem: nao precisa instalar nem configurar nada - o oci ja esta pronto
# e ja sabe quem voce e.
# Limite: a sessao do Cloud Shell cai sozinha depois de um tempo. Use este
# para uma primeira tentativa; para deixar rodando dias, use o
# Robo-Tentativa.ps1 no seu PC.
#
# Como usar:
#   1. No painel da Oracle, clique no icone de terminal (Cloud Shell), no topo
#   2. Cole o conteudo deste arquivo e de Enter
#   3. Deixe a aba aberta
set -uo pipefail

NOME="${NOME:-monitor}"
DISCO_GB="${DISCO_GB:-100}"
INTERVALO="${INTERVALO:-90}"
TAMANHOS="${TAMANHOS:-4 2 1}"
FDS="FAULT-DOMAIN-1 FAULT-DOMAIN-2 FAULT-DOMAIN-3"

# URL do cloud-init.yaml no SEU repositorio (raw). Deixe vazio para criar a
# instancia sem nenhuma configuracao automatica.
CLOUD_INIT_URL="${CLOUD_INIT_URL:-}"

vermelho() { printf '\033[1;31m%s\033[0m\n' "$*"; }
verde()    { printf '\033[1;32m%s\033[0m\n' "$*"; }
fraco()    { printf '\033[2m%s\033[0m\n' "$*"; }

morrer() { vermelho ""; vermelho "  $*"; vermelho ""; exit 1; }

COMP="${OCI_TENANCY:-}"
[ -n "$COMP" ] || morrer "Nao achei OCI_TENANCY. Voce esta mesmo no Cloud Shell?"

echo
echo "  Descobrindo os identificadores..."

AD="$(oci iam availability-domain list --compartment-id "$COMP" \
      --query 'data[0].name' --raw-output 2>/dev/null)"
[ -n "$AD" ] || morrer "Nenhum dominio de disponibilidade retornado."
fraco "    dominio de disponibilidade: $AD"

SUBNET="$(oci network subnet list --compartment-id "$COMP" --all \
          --query 'data[?"prohibit-public-ip-on-vnic"==`false`].id | [0]' \
          --raw-output 2>/dev/null)"
[ -n "$SUBNET" ] && [ "$SUBNET" != "null" ] || \
  morrer "Nenhuma sub-rede PUBLICA encontrada. Crie uma antes (veja o README)."
fraco "    sub-rede publica: $SUBNET"

IMAGEM="$(oci compute image list --compartment-id "$COMP" \
          --operating-system 'Canonical Ubuntu' \
          --operating-system-version '24.04' \
          --shape 'VM.Standard.A1.Flex' \
          --sort-by TIMECREATED --sort-order DESC \
          --query 'data[0].id' --raw-output 2>/dev/null)"
[ -n "$IMAGEM" ] && [ "$IMAGEM" != "null" ] || morrer "Nenhuma imagem Ubuntu 24.04 ARM encontrada."
fraco "    imagem: $IMAGEM"

# Chave SSH: o Cloud Shell tem a sua propria. Se voce quiser entrar do seu PC,
# gere la e cole aqui em CHAVE_SSH antes de rodar.
CHAVE_SSH="${CHAVE_SSH:-}"
if [ -z "$CHAVE_SSH" ]; then
  [ -f "$HOME/.ssh/id_rsa.pub" ] && CHAVE_SSH="$(cat "$HOME/.ssh/id_rsa.pub")"
fi
[ -n "$CHAVE_SSH" ] || morrer "Sem chave SSH. Gere com 'ssh-keygen -t rsa' ou defina CHAVE_SSH."

META="$(mktemp)"
if [ -n "$CLOUD_INIT_URL" ]; then
  CI="$(mktemp)"
  curl -fsSL "$CLOUD_INIT_URL" -o "$CI" || morrer "Nao consegui baixar $CLOUD_INIT_URL"
  grep -q 'SEU-USUARIO' "$CI" && morrer "O cloud-init ainda tem 'SEU-USUARIO'. Corrija e faca o push."
  USERDATA="$(base64 -w0 < "$CI")"
  jq -n --arg k "$CHAVE_SSH" --arg u "$USERDATA" \
     '{ssh_authorized_keys:$k, user_data:$u}' > "$META"
  fraco "    cloud-init: $CLOUD_INIT_URL"
else
  jq -n --arg k "$CHAVE_SSH" '{ssh_authorized_keys:$k}' > "$META"
  fraco "    cloud-init: nenhum (a instancia sobe limpa)"
fi

echo
verde "  ROBO DE TENTATIVA"
fraco "  ---------------------------------------------------------------"
echo   "  tamanhos:  $TAMANHOS OCPU (6 GB por OCPU)"
echo   "  intervalo: ${INTERVALO}s"
fraco "  ---------------------------------------------------------------"
fraco "  Ctrl+C para parar. Aceita o primeiro tamanho que vier."
echo

TENTATIVA=0
INICIO="$(date +%s)"

while true; do
  for OCPU in $TAMANHOS; do
    for FD in $FDS; do
      TENTATIVA=$((TENTATIVA + 1))
      SHAPE="$(mktemp)"
      printf '{"ocpus": %s, "memoryInGBs": %s}' "$OCPU" "$((OCPU * 6))" > "$SHAPE"

      SAIDA="$(oci compute instance launch \
        --availability-domain "$AD" \
        --compartment-id "$COMP" \
        --shape 'VM.Standard.A1.Flex' \
        --shape-config "file://$SHAPE" \
        --display-name "$NOME" \
        --image-id "$IMAGEM" \
        --subnet-id "$SUBNET" \
        --assign-public-ip true \
        --boot-volume-size-in-gbs "$DISCO_GB" \
        --metadata "file://$META" \
        --fault-domain "$FD" 2>&1)"
      CODIGO=$?
      rm -f "$SHAPE"

      AGORA="$(date +%H:%M:%S)"
      MIN=$((($(date +%s) - INICIO) / 60))
      ROTULO="$OCPU OCPU / $((OCPU * 6)) GB  $FD"

      if [ "$CODIGO" -eq 0 ]; then
        ID="$(echo "$SAIDA" | jq -r '.data.id')"
        echo
        verde "  =============================================================="
        verde "   CONSEGUIU  -  $ROTULO"
        verde "  =============================================================="
        echo
        echo "  Esperando o IP publico..."
        for _ in $(seq 1 30); do
          sleep 10
          IP="$(oci compute instance list-vnics --instance-id "$ID" \
                --query 'data[0]."public-ip"' --raw-output 2>/dev/null)"
          [ -n "$IP" ] && [ "$IP" != "null" ] && break
        done
        echo
        verde "  IP publico: ${IP:-ainda nao apareceu, veja no painel}"
        echo
        echo "  Libere as portas na Security List da VCN:"
        echo "    80,443  e  3000,8080,3001,9000 (enquanto estiver sem dominio)"
        echo
        exit 0
      fi

      case "$SAIDA" in
        *"Out of host capacity"*)
          printf '\033[2m  [%s] %-4s %-28s sem capacidade   (%s min)\033[0m\n' \
            "$AGORA" "$TENTATIVA" "$ROTULO" "$MIN"
          ;;
        *TooManyRequests*|*" 429"*)
          echo "  [$AGORA] a Oracle pediu calma (429). Esperando 5 minutos."
          sleep 300
          ;;
        *LimitExceeded*|*QuotaExceeded*)
          morrer "Bateu no LIMITE de cota, nao em falta de capacidade. Insistir nao resolve.
Veja em Limites, Cotas e Uso a linha 'Cores for Standard.A1 based VM and BM
instances'. Se estiver em 0, esta regiao nao da Ampere gratuito para voce.

$SAIDA"
          ;;
        *)
          morrer "Erro que nao e falta de capacidade - parei para voce ler:

$SAIDA"
          ;;
      esac

      sleep "$INTERVALO"
    done
  done
done
