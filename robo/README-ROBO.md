# Robô de tentativa

`Out of host capacity` não é erro seu: não há máquina Ampere livre naquele
instante. Mas capacidade **libera o tempo todo** — toda vez que alguém apaga
uma instância. O problema é que isso nunca acontece na hora em que você está
olhando a tela.

Este robô olha por você. Ele pede a instância de tempos em tempos, alternando
entre os tamanhos (4, 2 e 1 OCPU) e os três domínios de falha, e **para
sozinho assim que conseguir**. Aceite o primeiro tamanho que vier: dá para
aumentar depois sem recriar nada.

Duas versões, para dois usos:

| | Onde roda | Instalação | Aguenta |
|---|---|---|---|
| `robo-cloudshell.sh` | terminal dentro do painel da Oracle | nenhuma | algumas horas (a sessão cai) |
| `Robo-Tentativa.ps1` | seu PC | ~15 min | dias, enquanto o PC ficar ligado |

Comece pelo Cloud Shell para tentar já. Se não sair rápido, monte o do PC.

> ⚠️ **Não rode os dois ao mesmo tempo** — você acabaria com duas instâncias
> consumindo a mesma franquia.

---

## Antes de qualquer coisa

O robô cria uma instância **de verdade**, com o `cloud-init.yaml` deste
repositório. Então, antes de ligar:

1. O repositório precisa estar no GitHub (`git push` feito)
2. O `cloud-init.yaml` precisa apontar para o repositório certo — ele já vem
   com `kleversonteixeira28/monitor-oracle` na linha `REPO=`

Se a instância nascer com o cloud-init errado, ela sobe pelada e você perde a
vaga que esperou horas para conseguir. O robô do PC checa isso e se recusa a
rodar; o do Cloud Shell também.

---

## Versão rápida — Cloud Shell

No painel da Oracle, clique no ícone de terminal (**Cloud Shell**), no canto
superior direito. Espere ele abrir e cole:

```bash
export CLOUD_INIT_URL="https://raw.githubusercontent.com/kleversonteixeira28/monitor-oracle/main/cloud-init.yaml"
export CHAVE_SSH="ssh-ed25519 AAAA...cole aqui a sua chave publica..."
curl -fsSL "https://raw.githubusercontent.com/kleversonteixeira28/monitor-oracle/main/robo/robo-cloudshell.sh" | bash
```

A `CHAVE_SSH` é o conteúdo do seu `id_ed25519.pub` — sem ela você não entra na
máquina do seu PC depois.

Deixe a aba aberta. Quando conseguir, ele mostra o IP público.

---

## Versão longa — no seu PC

### 1. Instalar o OCI CLI

No PowerShell:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.ps1'))"
```

Aceite os padrões. **Feche e reabra o PowerShell** no fim (é o que coloca o
`oci` no PATH). Confira:

```bash
oci --version
```

### 2. Configurar o acesso

```bash
oci setup config
```

Ele faz perguntas nesta ordem:

| Pergunta | O que responder |
|---|---|
| Location for your config | Enter (aceita o padrão) |
| **User OCID** | no painel: ícone de perfil (canto sup. direito) → **Meu perfil** → copie o **OCID** |
| **Tenancy OCID** | ícone de perfil → **Tenancy: (nome)** → copie o **OCID** |
| Region | `us-sanjose-1` |
| Generate a new API key pair? | `Y` |
| Directory / nome da chave | Enter nos dois |
| **Passphrase** | **Enter (vazio)** — com senha, o robô trava pedindo ela |

No fim ele imprime o caminho da chave **pública**, algo como
`C:\Users\Kleverson\.oci\oci_api_key_public.pem`.

### 3. Cadastrar a chave na Oracle

Copie o conteúdo desse arquivo `.pem` e, no painel: ícone de perfil →
**Meu perfil** → **Chaves de API** → **Adicionar chave de API** →
**Colar uma chave pública** → colar → **Adicionar**.

Teste se ficou de pé:

```bash
oci iam region list --output table
```

Se listar as regiões, está pronto.

### 4. Ligar o robô

Dê dois cliques em **`TENTAR-CRIAR.bat`**, ou:

```bash
powershell -ExecutionPolicy Bypass -File robo\Robo-Tentativa.ps1
```

Na primeira vez ele descobre sozinho o compartimento, o domínio de
disponibilidade, a sub-rede pública e a imagem do Ubuntu, e salva tudo em
`robo\robo-config.json`. Confira o arquivo e rode de novo para começar a
tentar de fato.

Quando conseguir, ele apita, mostra o IP e **grava o IP em `servidor.txt`** —
o `CONECTAR.bat` da pasta principal já passa a funcionar.

---

## O que ele faz quando dá errado

Ele distingue os casos, em vez de repetir o mesmo erro a noite toda:

- **`Out of host capacity`** → é o esperado. Anota, espera e tenta o próximo
  combo de tamanho e domínio de falha.
- **429 / `TooManyRequests`** → a Oracle pediu calma. Espera 5 minutos.
- **`LimitExceeded`** → **para**. Isso é cota, não capacidade, e insistir não
  resolve nada. Vá em *Limites, Cotas e Uso* e olhe a linha
  `Cores for Standard.A1 based VM and BM instances`.
- **qualquer outro erro** → **para** e mostra a mensagem, para você ler.

Todas as tentativas ficam registradas em `robo\robo.log`.

## Ajustes

Editando `robo\robo-config.json`:

- `tamanhosOcpu`: `[4, 2, 1]`. Se você só aceita 4, deixe `[4]` — mas vai
  demorar muito mais.
- `discoGb`: 100. A franquia gratuita é 200 GB no total.
- `dominiosFalha`: os três. Não mexa.

E o intervalo entre tentativas (padrão 90 s):

```bash
powershell -ExecutionPolicy Bypass -File robo\Robo-Tentativa.ps1 -IntervaloSegundos 60
```

Não desça muito abaixo de 60 s — abaixo disso a Oracle começa a devolver 429 e
você tenta menos, não mais.

## Se nem o robô conseguir

Depois de um ou dois dias sem sucesso, o caminho é mudar a conta para
**Pay As You Go**. Os recursos Always Free continuam gratuitos, mas você sai da
fila dos trial e ganha prioridade de capacidade. É o que mais resolve. O
cuidado é só não criar nada fora da franquia depois.
