# Monitoramento na Oracle Cloud (gratis)

Zabbix, Grafana, Prometheus, Uptime Kuma e Portainer em Docker, num Ubuntu.
A mesma stack roda em tres lugares, mudando uma linha do `.env`:

| Onde | `MODO` | Como e acessado |
|---|---|---|
| Oracle Cloud Always Free | `oracle` | IP publico, HTTPS pelo Caddy |
| Maquina sua (mini PC na loja) | `tunel` | Cloudflare Tunnel, sem abrir porta no roteador |
| Seu PC, so para testar | — | `local/testar-local.sh`, em `localhost` |

A ideia central: **o servidor nao guarda configuracao.** Ele clona este
repositorio no primeiro boot, se instala sozinho, e depois puxa daqui de 5 em
5 minutos. Voce muda um arquivo no PC, da `git push`, e o servidor vira aquilo.
Se ele morrer, voce cria outro com o mesmo cloud-init e em ~10 minutos esta
tudo de volta (menos o historico, que vem do backup).

---

## O que sobe

| Servico | Para que serve |
|---|---|
| **Zabbix 7** | monitoramento classico: servidores, switches, impressoras, SNMP, alertas |
| **Grafana** | os graficos, lendo do Zabbix e do Prometheus |
| **Prometheus + node-exporter + cAdvisor** | metricas da maquina e de cada container |
| **Uptime Kuma** | "meu site esta no ar?" — checagem externa, com alerta no Telegram |
| **Portainer** | mexer nos containers pelo navegador |
| **Caddy** | porta de entrada unica, com HTTPS automatico se voce tiver dominio |

Cabe folgado nos 4 OCPU / 24 GB da instancia ARM gratuita: usa ~3 GB de RAM.

---

## Passo 1 — criar o repositorio no GitHub

Nesta pasta (`C:\Users\Kleverson\MonitorOracle`):

```bash
git init -b main && git add . && git commit -m "Stack de monitoramento que se instala sozinha"
```

```bash
gh repo create monitor-oracle --public --source=. --push
```

Sem o `gh`: crie o repositorio pelo site, depois `git remote add origin ...` e
`git push -u origin main`.

> **Publico ou privado?** Nao ha segredo nenhum aqui — as senhas nascem no
> servidor e ficam so la. Publico e mais simples (o servidor clona sem
> credencial). Para privado, veja "Repositorio privado" no fim.

O `cloud-init.yaml` ja aponta para `kleversonteixeira28/monitor-oracle`. Se voce
usar outra conta ou outro nome de repositorio, ajuste a linha `REPO=` la dentro.

## Passo 2 — a chave SSH

No PowerShell, se ainda nao tiver:

```bash
ssh-keygen -t ed25519 -C "oracle-monitor"
```

O conteudo de `C:\Users\Kleverson\.ssh\id_ed25519.pub` e o que voce cola na
Oracle no passo seguinte.

## Passo 3 — criar a instancia na Oracle

1. Conta em <https://www.oracle.com/br/cloud/free/> (pede cartao so para
   validar; cobra e estorna alguns reais). **A regiao de origem escolhida no
   cadastro nao muda depois** — e os recursos Always Free so existem nela.
   Regiao usada aqui: **US West (San Jose)**. Latencia de ~170 ms do Brasil:
   o painel fica um pouco mais lento de clicar, a coleta nao sofre.
   O servidor mantem o relogio em America/Sao_Paulo mesmo assim (o
   `instalar.sh` cuida disso), entao graficos e backup seguem em horario
   de Brasilia.
2. Menu -> **Compute -> Instances -> Create instance**
3. Preencha:
   - **Name:** `monitor`
   - **Compartimento:** o raiz (o que tem o nome da conta)
   - **Placement:** o unico AD que houver. Em *opcoes avancadas*:
     **Capacidade sob demanda** (a *preemptiva* e mais barata mas a Oracle
     mata a instancia quando quiser, e nao conta como Always Free) e
     **dominio de falha em automatico** — fixar um so reduz o hardware onde
     ela procura, e e justamente isso que voce nao quer
   - **Instancia blindada / computacao confidencial:** desligado (nem
     funciona nos shapes Ampere)
   - **Image:** Canonical **Ubuntu 24.04**
   - **Shape:** *Change shape* -> **Ampere** -> `VM.Standard.A1.Flex`
     -> **4 OCPUs / 24 GB** (tem que aparecer o selo *Always Free eligible*)
   - **Networking:** cria uma VCN nova, com **Assign a public IPv4 address**
   - **Add SSH keys:** *Paste public keys* -> cole o `id_ed25519.pub`
   - **Boot volume:** marque *Specify a custom boot volume size* e ponha
     **100 GB** (o padrao de 47 GB aperta quando o historico do Zabbix cresce;
     a franquia gratuita e 200 GB no total)
   - **Show advanced options -> Management -> Cloud-init script:**
     cole o conteudo de `cloud-init.yaml` **ja com o seu usuario do GitHub**
4. *Create*. Anote o **Public IP address**.
5. Liberar as portas na Security List. O jeito rapido e rodar
   `oracle/abrir-portas.sh` no Cloud Shell (veja abaixo). Na mao:
   **Networking -> Virtual Cloud Networks -> sua VCN -> Subnets -> a subnet
   -> Default Security List -> Add Ingress Rules**, com Source `0.0.0.0/0`:

   | Porta | Protocolo | Quando |
   |---|---|---|
   | 80, 443 | TCP | sempre |
   | 443 | UDP | sempre (HTTP/3 do Caddy) |
   | 3000, 8080, 3001, 9000 | TCP | so enquanto voce estiver **sem dominio** |

> Reserve o IP publico (**Reserved**, nao *Ephemeral*) se for apontar DNS para
> ele — IP efemero muda quando a instancia para.

## Passo 4 — esperar e entrar

A instalacao completa leva de 8 a 15 minutos (baixa ~1,5 GB de imagens).

```bash
ssh ubuntu@SEU-IP
```

```bash
sudo tail -f /var/log/monitor-instalacao.log
```

Quando terminar:

```bash
sudo bash /opt/monitor/scripts/senhas.sh
```

Isso imprime os enderecos e as senhas geradas. **Copie para o seu gerenciador
de senhas** — elas nao existem em nenhum outro lugar.

---

## Depois: por um dominio na frente

Enquanto for por IP, e HTTP puro — a senha do Grafana viaja em texto claro.
Voce ja tem o `skfoods.com.br`. Crie 4 registros **A** apontando para o IP:

```
grafana.skfoods.com.br   status.skfoods.com.br
zabbix.skfoods.com.br    docker.skfoods.com.br
```

Depois, **no servidor**, edite so estas duas linhas do `/opt/monitor/.env`:

```
DOMINIO=skfoods.com.br
EMAIL_TLS=kteixeira28@hotmail.com
```

Em ate 5 minutos a sincronizacao troca o Caddyfile, o Caddy tira certificado
sozinho e o firewall fecha as portas 3000/8080/3001/9000. Feche as mesmas
portas na Security List da Oracle depois disso.

## Numa maquina sua, publicada por Cloudflare Tunnel

Serve para um mini PC ou PC velho na loja. Custo mensal: so a energia. E o
tunel tem uma vantagem que nao e obvia: **nenhuma porta do roteador e aberta**.
O `cloudflared` faz conexao de SAIDA e o trafego volta por ela — nao ha o que
alguem varrer, e o IP da loja nao aparece em lugar nenhum. O HTTPS fica por
conta da Cloudflare, entao nao ha certificado para renovar aqui dentro.

### Antes: a decisao do dominio

O tunel exige que o dominio esteja com os **nameservers na Cloudflare**. Nao
basta ter conta — o dominio tem que estar la.

Mover o `skfoods.com.br` significa **migrar o DNS de producao**. Se um registro
se perder no caminho, a loja sai do ar. Isso e uma tarefa a parte, feita com
calma, conferindo registro por registro antes de trocar os nameservers.

Se voce nao quer mexer no dominio da loja agora, use **outro dominio so para
infraestrutura**: um `.xyz` ou `.site` custa poucos reais por ano e nao tem
nada de producao dependendo dele.

> Se so **voce** precisa ver esses paineis, existe caminho sem dominio nenhum:
> **Tailscale** poe a maquina numa rede privada sua e voce acessa por
> `http://100.x.x.x:3000` do celular ou do PC. Zero DNS, zero exposicao. O
> tunel ganha quando alguem de fora precisa abrir o link.

### Instalacao

Num Ubuntu Server 24.04 limpo:

```bash
sudo apt update && sudo apt install -y git
```

```bash
sudo git clone https://github.com/kleversonteixeira28/monitor-oracle.git /opt/monitor
```

```bash
sudo bash /opt/monitor/local/instalar-servidor-local.sh
```

Ele pergunta o dominio, marca `MODO=tunel` no `.env`, prepara a maquina
(Docker, swap, fail2ban, ufw, timers) e no fim instala o tunel. A unica parte
manual e autorizar na Cloudflare: aparece um endereco, voce abre no navegador
de qualquer maquina e escolhe o dominio.

No fim voce tem `grafana.SEU-DOMINIO`, `zabbix.`, `status.` e `docker.`, todos
com HTTPS.

### O que muda no `MODO=tunel`

- o Caddy escuta **so em 127.0.0.1** — nem a rede local ve as portas
- o Caddy **nao** tenta certificado: quem termina o HTTPS e a Cloudflare
- o `ufw` libera **so o SSH**, para voce administrar pela rede local
- a sincronizacao com o GitHub continua igual: `git push` e em 5 min a maquina
  mudou

### Um limite honesto

Qualquer um na internet que souber o endereco chega na **tela de login**. As
senhas geradas sao fortes, mas a porta esta la. Para fechar de vez, o
**Cloudflare Access** (gratis ate 50 usuarios) exige autenticacao *antes* de
chegar no servidor — configura no painel da Cloudflare, em Zero Trust.

## Testar na sua propria maquina (sem nuvem nenhuma)

A camada gratuita da Oracle vive sem capacidade ARM, e isso pode travar por
dias. Para **testar** — ver o Zabbix e o Grafana funcionando, aprender, mostrar
para alguem — nao precisa de nuvem: a mesma stack sobe no seu PC pelo WSL.

No PowerShell, uma vez:

```bash
wsl --install -d Ubuntu
```

Ele pede um usuario e senha do Linux e pode pedir para reiniciar. Depois, com
`wsl` aberto:

```bash
curl -fsSL https://get.docker.com | sh
```

```bash
sudo usermod -aG docker $USER
```

Feche e reabra o WSL, ligue o systemd (crie `/etc/wsl.conf` com `[boot]` e
`systemd=true`, depois `wsl --shutdown` no PowerShell), e entao:

```bash
git clone https://github.com/kleversonteixeira28/monitor-oracle.git ~/monitor && cd ~/monitor
```

```bash
bash local/testar-local.sh
```

Pronto: Grafana em `http://localhost:3000`, Zabbix em `:8080`, Kuma em `:3001`,
Portainer em `:9000`. As senhas saem na tela no fim.

Para desligar sem perder nada: `bash local/testar-local.sh --parar`.
Para zerar: `--apagar`.

O que o modo local **nao** faz, de proposito: firewall, swap, fail2ban, timers
e sincronizacao com o GitHub. Isso e endurecimento de servidor exposto na
internet; na sua maquina so atrapalharia. E so a sua maquina alcanca — nao ha
HTTPS nem acesso de fora.

## Abrir as portas sem clicar no painel

`oracle/abrir-portas.sh` faz isso pela API. Rode no **Cloud Shell** (o terminal
dentro do painel da Oracle), que ja vem com o `oci` pronto:

```bash
curl -fsSL https://raw.githubusercontent.com/kleversonteixeira28/monitor-oracle/main/oracle/abrir-portas.sh | bash
```

Ele cria uma Security List **nova** e a anexa a sub-rede, em vez de editar a
que ja existe. Regras somam entre listas, entao o efeito e o mesmo — mas a
regra que libera o SSH fica intocada. Se algo desse errado editando a lista
padrao, voce perderia o acesso a maquina sem ter como voltar.

Quando puser um dominio, rode de novo com `--com-dominio` para fechar as
portas 3000/8080/3001/9000.

## O dia a dia

```bash
sudo bash /opt/monitor/scripts/raio-x.sh
```

```bash
sudo bash /opt/monitor/scripts/senhas.sh
```

```bash
sudo bash /opt/monitor/scripts/sincronizar.sh
```

```bash
sudo bash /opt/monitor/scripts/atualizar.sh
```

`raio-x` = estado de tudo em uma tela. `senhas` = enderecos e acessos.
`sincronizar` = puxar do GitHub agora, sem esperar os 5 min.
`atualizar` = baixar versoes novas das imagens (faz backup antes).

Para ver por que um container caiu:

```bash
docker logs --tail 50 zabbix-server
```

Mudar a stack: edite aqui no PC, `git push`, espere 5 minutos.

---

## Armadilhas que custam tempo

**"Out of host capacity" ao criar a instancia ARM.**
E o problema numero um do free tier, e nao e erro seu: nao ha maquina Ampere
livre naquele momento.

O que mais resolve: **pedir menos**. Pedir 4 OCPU / 24 GB e pedir a franquia
inteira num bloco so, e a Oracle precisa achar um host com tudo isso livre de
uma vez. Peca **1 OCPU / 6 GB** — cabe em capacidade fragmentada, que e o que
sobra num datacenter cheio. E 6 GB rodam esta stack com folga (ela usa ~3 GB);
1 OCPU aguenta bem enquanto forem poucos hosts monitorados. Nada no repositorio
muda por causa disso.

Depois, com a maquina de pe, voce cresce sem recriar: *instancia -> Editar ->
Shape configuration -> 4 OCPUs*, e reinicia. Isso tambem depende de capacidade
na hora, mas voce ja esta dentro, com IP e disco prontos.

Se nem 1 OCPU passar, **use o robo**: `robo/` tem um script que fica pedindo a
instancia pela API, alternando tamanho e dominio de falha, e para sozinho
quando conseguir. Capacidade libera o tempo todo — so nunca na hora em que
voce esta olhando a tela. Veja `robo/README-ROBO.md`.

Em paralelo, na ordem:

1. varrer os **dominios de falha** na mao. Em regiao de um AD so (Sao Paulo,
   Vinhedo, San Jose), este e o equivalente de "tentar outro AD": volte em
   *opcoes avancadas* e force FD-1, depois FD-2, depois FD-3, tentando criar
   a cada troca. Se a regiao tiver mais de um AD, varra os ADs tambem;
2. tentar em horarios diferentes por alguns dias. San Jose e UTC-7: a
   madrugada de la e o meio da tarde aqui, entre 14h e 18h;
3. mudar a conta para **Pay As You Go**. Os recursos Always Free continuam
   gratuitos, mas a fila de capacidade passa a ser prioritaria. E o que mais
   resolve — so tome cuidado para nao criar recurso pago sem querer.

**Nao adianta cair para a instancia AMD gratuita.**
A `VM.Standard.E2.1.Micro` tem 1 GB de RAM. So o Zabbix com Postgres ja passa
disso. Se for ARM ou nada, e ARM.

**Sao dois firewalls, nao um.**
A Security List da VCN (painel da Oracle) e o `ufw` (dentro da maquina). Porta
liberada em um e fechada no outro = nao responde, e sem mensagem de erro. O
`raio-x.sh` mostra o lado de dentro; o de fora so o painel mostra.

**A imagem Ubuntu da Oracle vem com regras de iptables proprias** que descartam
quase tudo na entrada. O `instalar.sh` remove essas regras e passa o comando
para o `ufw`, para existir um lugar so onde olhar. Se voce reinstalar o
`iptables-persistent` depois, volta a confusao.

**Container que publica porta passa por baixo do ufw.**
O Docker escreve regra de NAT antes da cadeia que o `ufw` controla — um
`ufw deny` nao bloqueia porta publicada de container. Por isso, aqui, nenhum
servico publica porta para fora: so o Caddy. Se voce acrescentar um servico,
mantenha essa regra ou vai abrir buraco sem perceber.

**A Oracle recupera instancia Always Free ociosa.**
Se a maquina ficar dias com CPU, rede e memoria muito baixas, ela pode ser
recuperada. Esta stack sozinha ja gera atividade suficiente; so nao deixe tudo
parado por semanas.

**Backup local nao e backup.**
O `backup.sh` grava em `/opt/monitor/backups`, no proprio disco. Se a instancia
sumir, some junto. Leve para fora de vez em quando:

```bash
scp -r ubuntu@SEU-IP:/opt/monitor/backups .
```

---

## Ideias de uso imediato

- **Uptime Kuma:** monitor HTTP em `https://skfoods.com.br` e nas lojas.
  Alerta por Telegram sai em 2 minutos de configuracao.
- **Zabbix:** agente nas maquinas das lojas. O servidor escuta em 10051, hoje
  so no localhost — libere via VPN, nunca direto na internet.

## O que NAO por neste servidor

Ele esta fora do Brasil. Metrica de monitoramento nao e dado pessoal, entao
Zabbix, Grafana e Kuma estao de boa. Mas **backup do `prod.db` do SKFOODS nao
vai aqui** — isso e dado de cliente saindo do pais, e vira conversa de LGPD
sem necessidade. O backup do SKFOODS tem o caminho dele, no S3.
- **Grafana:** o painel "Servidor Oracle" ja vem provisionado. Para um painel
  completo de Linux, importe o dashboard **1860** (Node Exporter Full).

## Repositorio privado

O servidor precisa de credencial para clonar. O caminho limpo e uma
**deploy key**: gere uma chave no servidor, cadastre a publica em
*Settings -> Deploy keys* do repositorio (somente leitura) e troque o `REPO` do
`/etc/monitor.conf` para a forma SSH (`git@github.com:usuario/repo.git`). Como
isso exige um passo manual depois do boot, comece publico e mude se quiser.

## Estrutura

```
cloud-init.yaml     colado no painel da Oracle; clona e chama o instalar.sh
instalar.sh         primeiro boot: pacotes, swap, firewall, docker, timers
docker-compose.yml  a stack (ninguem publica porta para fora, so o Caddy)
compose/            portas extras usadas so no modo sem dominio
caddy/              dois modelos de Caddyfile; o instalador escolhe um
scripts/            sincronizar, gerar-env, firewall, zabbix, raio-x, backup
systemd/            timers de sincronizacao (5 min) e backup (03:20)
grafana/            datasources, plugin do Zabbix e o painel inicial
prometheus/         o que raspar
```
