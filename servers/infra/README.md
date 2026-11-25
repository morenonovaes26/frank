# srv-frank-infra (192.168.80.74)

Ubuntu Server 26.04 com Docker. Serviços: Cloudflared, Nginx Proxy Manager e n8n.

## Arquivos desta pasta

- `bootstrap.sh`: prepara a VM (sistema, volume de logs, Docker, pastas, `.env`).
- `docker-compose.yml`: os três serviços.

## Passos

1. No PC de controle: `./deploy/deploy.sh infra`. Isso copia o projeto e roda o bootstrap.
2. Na VM: preencher `~/frank/.env` com `DOMAIN`, `CLOUDFLARE_TUNNEL_TOKEN`, senhas do NPM e do n8n.
3. Na VM: `cd ~/frank/servers/infra && docker compose up -d`.
4. No painel Cloudflare Zero Trust: criar o túnel com o token e apontar os hostnames para o NPM (porta 80).
5. No NPM (acesso só por SSH ou túnel em `127.0.0.1:81`): criar os hosts para o n8n e para o TheHive.

## Dados

- Volume de logs: `/srv/logs`, criado a partir do espaço livre do disco de sistema (LVM `lv_logs`).
- Dados dos containers: `/srv/data`, que aponta para `/srv/logs/data`.
- Docker: `/srv/logs/docker`, com rotação de logs de 50 MB por arquivo, 5 arquivos.

## Segurança

- A porta 81 do NPM só escuta em `127.0.0.1`.
- O n8n só escuta em `127.0.0.1` e deve ficar atrás do Cloudflare Access.
- O `.env` fica com permissão 600 e nunca sai da VM.
