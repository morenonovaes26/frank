# srv-frank-wazuh (192.168.80.75)

Ubuntu Server 26.04 com Docker. Serviço: Wazuh 4.14.x (manager, indexador e dashboard), a partir do repositório oficial `wazuh-docker`.

## Arquivos desta pasta

- `bootstrap.sh`: prepara a VM (sistema, disco de logs de 500 GB, Docker, `vm.max_map_count`, clone do wazuh-docker na tag escolhida).

O stack do Wazuh vem do repositório oficial, então não há compose próprio aqui. A tag é obrigatória.

## Passos

1. Confira a tag em https://github.com/wazuh/wazuh-docker/tags (formato `v4.14.x`).
2. No PC de controle: `WAZUH_DOCKER_TAG=<tag> ./deploy/deploy.sh wazuh`.
3. Na VM, siga o README do wazuh-docker em `/srv/wazuh-docker` para a mesma versão:
   - gerar os certificados do indexador;
   - trocar as senhas padrão do indexador, do manager e do dashboard;
   - subir o stack a partir de `/srv/wazuh-docker/single-node`.
4. Registrar os agentes (Linux e Windows) e ativar a detecção de vulnerabilidades.

## Dados

- Disco de logs: `/dev/sdb` (500 GB) em LVM `vg_logs/lv_logs`, montado em `/srv/logs`. Nunca roda em disco que já tenha partições.
- Índices e arquivos do Wazuh: `/srv/logs/wazuh/{indexer,manager,dashboard}`.
- Docker: `/srv/logs/docker`, então os volumes dos containers também ficam no disco de logs.

## Pontos de atenção

- O indexador exige `vm.max_map_count=262144`, que o bootstrap grava em `/etc/sysctl.d/99-frank-wazuh.conf`.
- Retenção de 90 dias é um ponto a definir com o volume real de alertas (ver o `inventario.yaml`).
