# Robo de tentativa - fica pedindo a instancia ARM ate a Oracle ter capacidade.
#
# Capacidade Ampere libera o tempo todo, quando alguem apaga uma instancia.
# So que nunca na hora em que voce esta olhando a tela. Este script olha por
# voce, alternando entre os tamanhos e os dominios de falha a cada tentativa.
#
# Uso:  .\Robo-Tentativa.ps1
# Parar: Ctrl+C

param(
  [string]$Config = "$PSScriptRoot\robo-config.json",
  [int]$IntervaloSegundos = 90,
  [switch]$SoDescobrir
)

$ErrorActionPreference = "Stop"
$raizRepo = Split-Path -Parent $PSScriptRoot

function Aviso($texto)  { Write-Host $texto -ForegroundColor Yellow }
function Erro($texto)   { Write-Host $texto -ForegroundColor Red }
function Bom($texto)    { Write-Host $texto -ForegroundColor Green }
function Fraco($texto)  { Write-Host $texto -ForegroundColor DarkGray }

function Sair($texto) {
  Erro ""
  Erro "  $texto"
  Erro ""
  exit 1
}

# ---------------------------------------------------------------- pre-requisitos
$comandoOci = Get-Command oci -ErrorAction SilentlyContinue
if (-not $comandoOci) {
  Sair @"
O OCI CLI nao esta instalado (ou nao esta no PATH).
Instale com o comando abaixo, feche e reabra o PowerShell, e rode de novo:

powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.ps1'))"

Depois configure com:  oci setup config
(o README-ROBO.md explica cada resposta)
"@
}

$arquivoOciConfig = Join-Path $HOME ".oci\config"
if (-not (Test-Path $arquivoOciConfig)) {
  Sair "Falta configurar o OCI CLI. Rode:  oci setup config   (veja o README-ROBO.md)"
}

# Chama o oci e devolve o objeto ja convertido. Erro vira excecao.
function OciJson([string[]]$argumentos) {
  $texto = & oci @argumentos
  if ($LASTEXITCODE -ne 0) { throw "oci $($argumentos -join ' ') falhou" }
  if (-not $texto) { return $null }
  return ($texto | Out-String | ConvertFrom-Json)
}

# ------------------------------------------------------------------ descoberta
function DescobrirConfig {
  Aviso "`n  Descobrindo os identificadores da sua conta..."

  $linhaTenancy = Select-String -Path $arquivoOciConfig -Pattern '^\s*tenancy\s*=\s*(\S+)' |
                  Select-Object -First 1
  if (-not $linhaTenancy) { Sair "Nao achei 'tenancy=' em $arquivoOciConfig" }
  $tenancy = $linhaTenancy.Matches[0].Groups[1].Value
  Fraco "    compartimento (raiz): $tenancy"

  $ads = OciJson @('iam','availability-domain','list','--compartment-id',$tenancy)
  if (-not $ads.data) { Sair "Nenhum dominio de disponibilidade retornado." }
  $ad = $ads.data[0].name
  Fraco "    dominio de disponibilidade: $ad"

  $subnets = OciJson @('network','subnet','list','--compartment-id',$tenancy,'--all')
  $publica = $subnets.data |
    Where-Object { $_.'prohibit-public-ip-on-vnic' -eq $false } |
    Select-Object -First 1
  if (-not $publica) {
    Sair "Nenhuma sub-rede PUBLICA encontrada. Crie uma antes (veja o README)."
  }
  Fraco "    sub-rede publica: $($publica.'display-name')"

  $imgs = OciJson @('compute','image','list','--compartment-id',$tenancy,
                    '--operating-system','Canonical Ubuntu',
                    '--operating-system-version','24.04',
                    '--shape','VM.Standard.A1.Flex',
                    '--sort-by','TIMECREATED','--sort-order','DESC')
  if (-not $imgs.data) { Sair "Nenhuma imagem Ubuntu 24.04 para ARM encontrada." }
  $img = $imgs.data[0]
  Fraco "    imagem: $($img.'display-name')"

  $chavePub = Join-Path $HOME ".ssh\id_ed25519.pub"
  if (-not (Test-Path $chavePub)) {
    Sair "Falta a chave SSH em $chavePub. Gere com:  ssh-keygen -t ed25519"
  }

  return [ordered]@{
    nome                    = "monitor"
    compartimento           = $tenancy
    dominioDisponibilidade  = $ad
    subnet                  = $publica.id
    imagem                  = $img.id
    chavePublicaSsh         = $chavePub
    cloudInit               = (Join-Path $raizRepo "cloud-init.yaml")
    discoGb                 = 100
    # Tentadas nesta ordem, uma por vez. Aceite a primeira que vier: da para
    # aumentar o shape depois sem recriar a instancia.
    tamanhosOcpu            = @(4, 2, 1)
    dominiosFalha           = @("FAULT-DOMAIN-1","FAULT-DOMAIN-2","FAULT-DOMAIN-3")
  }
}

if ((-not (Test-Path $Config)) -or $SoDescobrir) {
  $cfg = DescobrirConfig
  $cfg | ConvertTo-Json -Depth 5 | Set-Content -Path $Config -Encoding UTF8
  Bom "`n  Configuracao salva em $Config"
  Write-Host ""
  Write-Host "  Confira o arquivo - principalmente o disco e os tamanhos - e rode"
  Write-Host "  de novo para comecar a tentar. Parei aqui de proposito: a partir"
  Write-Host "  da proxima execucao ele cria uma instancia DE VERDADE."
  Write-Host ""
  exit 0
}

$cfg = Get-Content -Raw -Path $Config | ConvertFrom-Json

foreach ($campo in @('compartimento','dominioDisponibilidade','subnet','imagem')) {
  if (-not $cfg.$campo) { Sair "Campo '$campo' vazio em $Config" }
}
if (-not (Test-Path $cfg.chavePublicaSsh)) { Sair "Chave SSH nao encontrada: $($cfg.chavePublicaSsh)" }
if (-not (Test-Path $cfg.cloudInit))       { Sair "cloud-init nao encontrado: $($cfg.cloudInit)" }

# ------------------------------------------------------- checagem do cloud-init
$textoCloudInit = Get-Content -Raw -Path $cfg.cloudInit
if ($textoCloudInit -match 'SEU-USUARIO') {
  Sair @"
O cloud-init.yaml ainda tem 'SEU-USUARIO'. Se a instancia nascer assim, ela
sobe pelada - o git clone falha e voce perde a vaga que tanto esperou.
Troque pelo seu usuario do GitHub, faca o push, e rode de novo.
"@
}

# ---------------------------------------------------------- arquivos auxiliares
# JSON vai em arquivo (file://) porque argumento com aspas se perde no caminho
# entre o PowerShell e um executavel nativo.
$pastaTmp = Join-Path $env:TEMP "robo-oracle"
New-Item -ItemType Directory -Force -Path $pastaTmp | Out-Null

function EscreverJsonSemBom($caminho, $objeto) {
  $texto = $objeto | ConvertTo-Json -Compress -Depth 5
  # Sem BOM: o OCI CLI le o arquivo como JSON puro e engasga com o marcador.
  [IO.File]::WriteAllText($caminho, $texto, (New-Object Text.UTF8Encoding($false)))
}

$chave = (Get-Content -Raw -Path $cfg.chavePublicaSsh).Trim()
$userData = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($textoCloudInit))

$caminhoMeta = Join-Path $pastaTmp "metadata.json"
EscreverJsonSemBom $caminhoMeta ([ordered]@{
  ssh_authorized_keys = $chave
  user_data           = $userData
})

$caminhosShape = @{}
foreach ($ocpu in $cfg.tamanhosOcpu) {
  $caminho = Join-Path $pastaTmp "shape-$ocpu.json"
  # A1 da 6 GB de memoria por OCPU.
  EscreverJsonSemBom $caminho ([ordered]@{ ocpus = $ocpu; memoryInGBs = ($ocpu * 6) })
  $caminhosShape[$ocpu] = $caminho
}

function ParaFileUrl($caminho) { return "file://" + ($caminho -replace '\\','/') }

# ------------------------------------------------------------- lista de combos
$combos = @()
foreach ($ocpu in $cfg.tamanhosOcpu) {
  foreach ($fd in $cfg.dominiosFalha) {
    $combos += [pscustomobject]@{ Ocpu = $ocpu; Fd = $fd }
  }
}

$registro = Join-Path $PSScriptRoot "robo.log"

Write-Host ""
Bom     "  ROBO DE TENTATIVA"
Fraco   "  ---------------------------------------------------------------"
Write-Host "  instancia .... $($cfg.nome)"
Write-Host "  tamanhos ..... $($cfg.tamanhosOcpu -join ', ') OCPU (6 GB por OCPU)"
Write-Host "  dominios ..... $($cfg.dominiosFalha.Count) de falha, alternando"
Write-Host "  intervalo .... $IntervaloSegundos s entre tentativas"
Write-Host "  registro ..... $registro"
Fraco   "  ---------------------------------------------------------------"
Fraco   "  Deixe esta janela aberta. Ctrl+C para parar."
Fraco   "  Aceita o primeiro tamanho que vier - da para crescer depois."
Write-Host ""

$tentativa = 0
$inicio = Get-Date
$indice = 0

while ($true) {
  $combo = $combos[$indice % $combos.Count]
  $indice++
  $tentativa++

  $saidaArq = Join-Path $pastaTmp "saida.json"
  $erroArq  = Join-Path $pastaTmp "erro.txt"

  $argumentos = @(
    'compute','instance','launch',
    '--availability-domain', $cfg.dominioDisponibilidade,
    '--compartment-id',      $cfg.compartimento,
    '--shape',               'VM.Standard.A1.Flex',
    '--shape-config',        (ParaFileUrl $caminhosShape[$combo.Ocpu]),
    '--display-name',        $cfg.nome,
    '--image-id',            $cfg.imagem,
    '--subnet-id',           $cfg.subnet,
    '--assign-public-ip',    'true',
    '--boot-volume-size-in-gbs', "$($cfg.discoGb)",
    '--metadata',            (ParaFileUrl $caminhoMeta),
    '--fault-domain',        $combo.Fd
  )

  # Caminho resolvido, nao o nome: o Start-Process nao usa a mesma busca de
  # PATH que o operador de chamada, e "oci" pode ser um atalho.
  $processo = Start-Process -FilePath $comandoOci.Source -ArgumentList $argumentos `
    -NoNewWindow -Wait -PassThru `
    -RedirectStandardOutput $saidaArq -RedirectStandardError $erroArq

  $agora = (Get-Date).ToString("HH:mm:ss")
  $rotulo = "$($combo.Ocpu) OCPU / $($combo.Ocpu * 6) GB  $($combo.Fd)"

  if ($processo.ExitCode -eq 0) {
    # ---------------------------------------------------------------- consegui
    $instancia = (Get-Content -Raw -Path $saidaArq | ConvertFrom-Json).data
    Write-Host ""
    Bom "  =============================================================="
    Bom "   CONSEGUIU  -  $rotulo"
    Bom "  =============================================================="
    Write-Host ""
    Write-Host "  instancia: $($instancia.'display-name')"
    Fraco       "  ocid:      $($instancia.id)"

    Add-Content -Path $registro -Value "$agora CONSEGUIU $rotulo $($instancia.id)"

    Write-Host ""
    Write-Host "  Esperando o IP publico..."
    $ip = $null
    for ($i = 0; $i -lt 30; $i++) {
      Start-Sleep -Seconds 10
      try {
        $vnics = OciJson @('compute','instance','list-vnics','--instance-id',$instancia.id)
        $ip = $vnics.data[0].'public-ip'
      } catch { $ip = $null }
      if ($ip) { break }
    }

    for ($i = 0; $i -lt 5; $i++) { [console]::beep(880, 250); Start-Sleep -Milliseconds 120 }

    if ($ip) {
      Bom "`n  IP publico: $ip`n"
      Set-Content -Path (Join-Path $raizRepo "servidor.txt") -Value $ip -Encoding ASCII
      Write-Host "  Gravei o IP em servidor.txt - o CONECTAR.bat ja usa ele."
      Write-Host ""
      Write-Host "  A instalacao roda sozinha por 8 a 15 minutos. Acompanhe com:"
      Write-Host "    ssh ubuntu@$ip"
      Write-Host "    sudo tail -f /var/log/monitor-instalacao.log"
    } else {
      Aviso "`n  A instancia subiu mas o IP ainda nao apareceu. Veja no painel."
    }

    Write-Host ""
    Write-Host "  NAO ESQUECA: libere as portas na Security List da VCN."
    Write-Host "    80,443  e  3000,8080,3001,9000 (enquanto estiver sem dominio)"
    Write-Host ""
    exit 0
  }

  # --------------------------------------------------------------- nao consegui
  $mensagemErro = ""
  if (Test-Path $erroArq) { $mensagemErro = (Get-Content -Raw -Path $erroArq) }
  if (-not $mensagemErro) { $mensagemErro = "erro sem mensagem" }

  $decorrido = [int]((Get-Date) - $inicio).TotalMinutes
  $espera = $IntervaloSegundos

  if ($mensagemErro -match 'Out of host capacity') {
    Fraco ("  [{0}] {1,-4} {2,-28} sem capacidade   ({3} min tentando)" -f $agora, $tentativa, $rotulo, $decorrido)
    Add-Content -Path $registro -Value "$agora sem-capacidade $rotulo"
  }
  elseif ($mensagemErro -match 'TooManyRequests' -or $mensagemErro -match '\b429\b') {
    Aviso "  [$agora] a Oracle pediu calma (429). Esperando 5 minutos."
    Add-Content -Path $registro -Value "$agora rate-limit"
    $espera = 300
  }
  elseif ($mensagemErro -match 'LimitExceeded' -or $mensagemErro -match 'QuotaExceeded') {
    Add-Content -Path $registro -Value "$agora limite-excedido"
    Sair @"
A conta bateu no LIMITE de cota, nao em falta de capacidade. Insistir nao
resolve. Veja em Governanca e Administracao -> Limites, Cotas e Uso a linha
'Cores for Standard.A1 based VM and BM instances'. Se estiver em 0, esta
regiao nao da Ampere gratuito para a sua conta.

Mensagem da Oracle:
$mensagemErro
"@
  }
  else {
    Add-Content -Path $registro -Value "$agora erro-desconhecido $mensagemErro"
    Sair @"
Erro que nao e falta de capacidade - parei para voce ler, em vez de repetir
o mesmo erro a noite toda:

$mensagemErro
"@
  }

  Start-Sleep -Seconds $espera
}
