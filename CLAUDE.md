# Monitoramento (GitOps) — diretrizes para o Claude Code

Stack de monitoramento (Zabbix, Grafana, Prometheus, Uptime Kuma, Portainer) em
Docker, num Ubuntu. A mesma stack roda em três lugares mudando uma linha do
`.env`: Oracle Cloud (`MODO=oracle`), máquina própria por Cloudflare Tunnel
(`MODO=tunel`) ou local, só para testar.

**O servidor não guarda configuração.** Ele clona este repositório no primeiro
boot e puxa daqui a cada 5 minutos (`systemd/monitor-sync.timer`).

## Stack e Tecnologias
- Bash + `docker compose` + systemd (unit + timer)
- Caddy na frente (HTTPS automático) · `cloud-init.yaml` cria a máquina do zero
- Repositório: `github.com/kleversonteixeira28/monitor-oracle`
- Testes: não há suíte. A verificação é `scripts/raio-x.sh` e
  `local/testar-local.sh`.

## Regras de Ouro (Hard Constraints)
- Otimize sempre para **NÃO quebrar o comportamento existente**, não para velocidade.
- **NUNCA** adicione tratamento de erro para cenário impossível de acontecer.
- Siga o padrão de nomes do diretório em que você está mexendo.
- Prefira editar arquivo existente a criar arquivo novo.
- Em tarefa complexa: mapeie o impacto, apresente o plano e **espere aprovação**
  antes de mudar código.
- **`git push` aqui é deploy.** Em até 5 minutos o servidor vira o que está no
  `main`. Commitar é uma decisão; empurrar é outra — só quando o Kleverson mandar.
- Configuração fica em arquivo versionado; segredo fica no `.env`, que **nunca**
  vai para o GitHub (junto com `dados/`, `backups/`, `caddy/Caddyfile`,
  `servidor.txt`, `robo/robo-config.json`). Confira o `.gitignore` antes de mexer nele.
- Mudança tem que funcionar nos três `MODO`. Não escreva IP nem domínio fixo no
  meio do compose: isso é gerado (`scripts/gerar-env.sh`, `caddy/Caddyfile.*`).
- O histórico do Zabbix mora em volume, não no git. Antes de qualquer coisa que
  recrie container com volume, `scripts/backup.sh`.

## Comandos Úteis
```bash
local/testar-local.sh        # sobe a stack no seu PC, em localhost
scripts/raio-x.sh            # estado de tudo (o que está de pé, o que não está)
scripts/atualizar.sh         # puxa do git e aplica (é o que o servidor roda)
scripts/backup.sh            # backup dos volumes
scripts/senhas.sh            # mostra as senhas geradas
docker compose ps            # o que está rodando
docker compose logs -f <servico>
```
No Windows há os atalhos `CONECTAR.bat` (SSH) e `ENVIAR.bat` (commit + push).
