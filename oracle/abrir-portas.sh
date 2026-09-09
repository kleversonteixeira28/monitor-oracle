#!/usr/bin/env bash
# Abre as portas do monitoramento na Security List da VCN.
#
# POR QUE UMA LISTA NOVA, E NAO EDITAR A QUE EXISTE:
# a lista padrao e quem libera o SSH. Se eu reescrevesse as regras dela e
# errasse uma virgula, voce perderia o acesso a maquina e nao teria como
# voltar. As regras SOMAM entre listas, entao criar uma separada da o mesmo
# resultado sem nunca encostar na porta 22.
#
# Onde rodar: no Cloud Shell (o terminal dentro do painel da Oracle), que ja
# vem com o oci pronto. Tambem roda no seu PC, se voce ja tiver feito o
# 'oci setup config'.
#
#   bash abrir-portas.sh              abre 80, 443 e as portas do modo sem dominio
#   bash abrir-portas.sh --com-dominio    abre so 80 e 443
#   bash abrir-portas.sh --sim        nao pergunta antes
set -uo pipefail

NOME_LISTA="monitor-portas"
COM_DOMINIO=0
CONFIRMAR=1

for arg in "$@"; do
  case "$arg" in
    --com-dominio) COM_DOMINIO=1 ;;
    --sim)         CONFIRMAR=0 ;;
    *) echo "argumento desconhecido: $arg"; exit 1 ;;
  esac
done

vermelho() { printf '\033[1;31m%s\033[0m\n' "$*"; }
verde()    { printf '\033[1;32m%s\033[0m\n' "$*"; }
fraco()    { printf '\033[2m%s\033[0m\n' "$*"; }
morrer()   { vermelho ""; vermelho "  $*"; vermelho ""; exit 1; }

command -v oci >/dev/null || morrer "O oci nao esta disponivel. Rode isto no Cloud Shell."

# Compartimento: no Cloud Shell vem pronto; no PC sai do ~/.oci/config.
COMP="${OCI_TENANCY:-}"
if [ -z "$COMP" ] && [ -f "$HOME/.oci/config" ]; then
  COMP="$(sed -n 's/^[[:space:]]*tenancy[[:space:]]*=[[:space:]]*//p' "$HOME/.oci/config" | head -1)"
fi
[ -n "$COMP" ] || morrer "Nao descobri o compartimento. Rode no Cloud Shell ou faca 'oci setup config'."

echo
echo "  Procurando a sub-rede publica..."

SUBNET_ID="${SUBNET_ID:-}"
if [ -z "$SUBNET_ID" ]; then
  SUBNET_ID="$(oci network subnet list --compartment-id "$COMP" --all \
    --query 'data[?"prohibit-public-ip-on-vnic"==`false`].id | [0]' --raw-output 2>/dev/null)"
fi
[ -n "$SUBNET_ID" ] && [ "$SUBNET_ID" != "null" ] || \
  morrer "Nenhuma sub-rede publica encontrada. Crie uma antes (Assistente de VCN)."

SUBNET_JSON="$(oci network subnet get --subnet-id "$SUBNET_ID" 2>/dev/null)"
[ -n "$SUBNET_JSON" ] || morrer "Nao consegui ler a sub-rede $SUBNET_ID"

SUBNET_NOME="$(echo "$SUBNET_JSON" | jq -r '.data."display-name"')"
VCN_ID="$(echo "$SUBNET_JSON" | jq -r '.data."vcn-id"')"
LISTAS_ATUAIS="$(echo "$SUBNET_JSON" | jq -c '.data."security-list-ids"')"

fraco "    sub-rede: $SUBNET_NOME"
fraco "    vcn:      $VCN_ID"

# ------------------------------------------------------------------- regras
if [ "$COM_DOMINIO" = 1 ]; then
  PORTAS_TCP="80 443"
  RESUMO="80 e 443 (modo com dominio)"
else
  PORTAS_TCP="80 443 3000 8080 3001 9000"
  RESUMO="80, 443, 3000, 8080, 3001 e 9000 (modo sem dominio)"
fi

# protocolo 6 = TCP, 17 = UDP. A 443/udp e o HTTP/3 do Caddy.
REGRAS="$(
  {
    for p in $PORTAS_TCP; do
      jq -nc --argjson p "$p" '{
        protocol:"6", source:"0.0.0.0/0", sourceType:"CIDR_BLOCK", isStateless:false,
        tcpOptions:{destinationPortRange:{min:$p, max:$p}}
      }'
    done
    jq -nc '{
      protocol:"17", source:"0.0.0.0/0", sourceType:"CIDR_BLOCK", isStateless:false,
      udpOptions:{destinationPortRange:{min:443, max:443}}
    }'
  } | jq -sc .
)"

SAIDA_REGRAS='[{"protocol":"all","destination":"0.0.0.0/0","destinationType":"CIDR_BLOCK","isStateless":false}]'

echo
echo "  Vou liberar, vindo de qualquer lugar (0.0.0.0/0):"
echo "    TCP $RESUMO"
echo "    UDP 443"
echo
echo "  Numa lista NOVA chamada '$NOME_LISTA'."
fraco "  A regra do SSH (porta 22) fica onde esta - nao encosto nela."
echo

if [ "$CONFIRMAR" = 1 ]; then
  printf "  Confirma? [s/N] "
  read -r resposta
  case "$resposta" in [sSyY]*) ;; *) echo "  cancelado."; exit 0 ;; esac
  echo
fi

# ------------------------------------------------- criar ou atualizar a lista
EXISTENTE="$(oci network security-list list --compartment-id "$COMP" --vcn-id "$VCN_ID" --all \
  --query "data[?\"display-name\"=='$NOME_LISTA'].id | [0]" --raw-output 2>/dev/null)"

ARQ_ENTRADA="$(mktemp)"; echo "$REGRAS"       > "$ARQ_ENTRADA"
ARQ_SAIDA="$(mktemp)";   echo "$SAIDA_REGRAS" > "$ARQ_SAIDA"

if [ -n "$EXISTENTE" ] && [ "$EXISTENTE" != "null" ]; then
  echo "  A lista '$NOME_LISTA' ja existe - atualizando as regras dela."
  RESULTADO="$(oci network security-list update --security-list-id "$EXISTENTE" \
    --ingress-security-rules "file://$ARQ_ENTRADA" \
    --egress-security-rules "file://$ARQ_SAIDA" --force 2>&1)"
  CODIGO=$?
  LISTA_ID="$EXISTENTE"
else
  RESULTADO="$(oci network security-list create --compartment-id "$COMP" --vcn-id "$VCN_ID" \
    --display-name "$NOME_LISTA" \
    --ingress-security-rules "file://$ARQ_ENTRADA" \
    --egress-security-rules "file://$ARQ_SAIDA" 2>&1)"
  CODIGO=$?
  LISTA_ID="$(echo "$RESULTADO" | jq -r '.data.id // empty' 2>/dev/null)"
fi
rm -f "$ARQ_ENTRADA" "$ARQ_SAIDA"

[ "$CODIGO" -eq 0 ] && [ -n "$LISTA_ID" ] || morrer "Falhou ao criar/atualizar a lista:

$RESULTADO"

fraco "    lista: $LISTA_ID"

# -------------------------------------------------------- anexar a sub-rede
JA_ANEXADA="$(echo "$LISTAS_ATUAIS" | jq -r --arg id "$LISTA_ID" 'index($id) // empty')"
if [ -n "$JA_ANEXADA" ]; then
  echo "  A lista ja estava anexada a sub-rede."
else
  NOVAS="$(echo "$LISTAS_ATUAIS" | jq -c --arg id "$LISTA_ID" '. + [$id]')"
  ARQ_LISTAS="$(mktemp)"; echo "$NOVAS" > "$ARQ_LISTAS"
  RESULTADO="$(oci network subnet update --subnet-id "$SUBNET_ID" \
    --security-list-ids "file://$ARQ_LISTAS" --force 2>&1)"
  CODIGO=$?
  rm -f "$ARQ_LISTAS"
  [ "$CODIGO" -eq 0 ] || morrer "Criei a lista mas nao consegui anexar na sub-rede:

$RESULTADO"
  echo "  Lista anexada a sub-rede."
fi

echo
verde "  Portas liberadas do lado de FORA (Oracle)."
echo
fraco "  Do lado de dentro, o ufw e configurado sozinho pelo instalar.sh quando"
fraco "  a instancia subir. Sao dois firewalls: um so nao basta."
echo
echo "  Quando voce por um dominio, rode de novo com --com-dominio para"
echo "  fechar as portas 3000/8080/3001/9000."
echo
