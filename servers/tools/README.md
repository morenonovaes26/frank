# srv-frank-tools (192.168.80.76)

Ubuntu Server 26.04 com Docker. Serviços: Elasticsearch, TheHive, Cortex e os coletores de threat intelligence.

## Arquivos desta pasta

- `bootstrap.sh`: prepara a VM (sistema, disco de logs de 500 GB, Docker, `vm.max_map_count`, pastas, `.env`).
- `docker-compose.yml`: Elasticsearch, TheHive e Cortex.

## Passos

1. No PC de controle: `./deploy/deploy.sh tools`.
2. Na VM: validar as versões marcadas com TODO em `docker-compose.yml`. O TheHive 5 e o Cortex dependem da versão do Elasticsearch, então confira na documentação oficial antes de subir.
3. Na VM: preencher `~/frank/.env` com as senhas do Elasticsearch, do TheHive e do Cortex, e as chaves de API.
4. Na VM: `cd ~/frank/servers/tools && docker compose up -d`.
5. Ligar o TheHive ao NPM da VM de infra, atrás do Cloudflare Access.

## Dados

- Disco de logs: `/dev/sdb` (500 GB) em LVM, montado em `/srv/logs`.
- Dados do Elasticsearch, TheHive e Cortex: `/srv/data`, que aponta para `/srv/logs/data`.
- Logs dos serviços: `/srv/logs/{elasticsearch,thehive,cortex}`.

## Pontos de atenção

- O Elasticsearch exige `vm.max_map_count=262144`, que o bootstrap grava em `/etc/sysctl.d/99-frank-tools.conf`.
- O Cortex monta o socket do Docker para rodar analisadores. Isso dá privilégio alto ao container, então mantenha a porta 9001 só na rede interna.
