# Projeto Frank: Ecossistema de IA para Segurança

Material completo do projeto: scripts, composes, inventário e documentação. Este PC é só a estação de trabalho: ele edita os arquivos, versiona no Git e envia o material para os servidores. Ele não faz parte da infraestrutura.

## Topologia

| Host | IP | Função | Recursos |
|---|---|---|---|
| srv-frank-ia | 192.168.80.77 | IA: Ollama com RTX 3080 (10 GB) | Ubuntu 26.04, 15 GB RAM |
| pve-prod02 | 192.168.80.52 | Hypervisor Proxmox 9.2.2 | 24 vCPUs, 62 GiB RAM |
| srv-frank-infra | 192.168.80.74 | Cloudflared, NPM, n8n | 2 vCPUs, 8 GB RAM |
| srv-frank-wazuh | 192.168.80.75 | Wazuh 4.14.x via Docker | 4 vCPUs, 16 GB RAM |
| srv-frank-tools | 192.168.80.76 | Elasticsearch, TheHive, Cortex, coletores | 4 vCPUs, 32 GB RAM |

## Estrutura

```
frank/
├── README.md                 este arquivo
├── inventario.yaml           fonte da verdade: hosts, VMs, discos e serviços
├── .env.example              variáveis de todos os serviços (o .env real fica só nas VMs)
├── .gitignore                bloqueia .env, ISOs, OVAs e dados
├── git-comandos.md           guia de comandos Git do projeto
├── deploy/
│   ├── deploy.sh             copia o projeto para cada VM e roda o bootstrap (roda no PC)
│   └── hosts.conf            IPs, usuário SSH e tag do Wazuh
├── shared/
│   └── lib/common.sh         funções comuns: checagens, disco de logs, Docker, .env
├── servers/
│   ├── infra/                bootstrap.sh, docker-compose.yml, README.md
│   ├── wazuh/                bootstrap.sh, README.md
│   └── tools/                bootstrap.sh, docker-compose.yml, README.md
├── scripts/
│   └── proxmox-add-log-disk.sh   roda no Proxmox: cria e anexa o disco de logs
├── vulnerabilidades/README.md    pipeline de assessment de vulnerabilidades
└── cloudflare/README.md          recursos e custos da Cloudflare
```

## Fluxo de trabalho

1. Editar os arquivos neste PC, dentro de `/opt/frank`.
2. Versionar: `git add -A && git commit -m "..." && git push` (ver `git-comandos.md`).
3. Enviar para as VMs e configurar:
   - tudo de uma vez: `./deploy/deploy.sh all` (o Wazuh precisa de `WAZUH_DOCKER_TAG`);
   - uma VM só: `./deploy/deploy.sh infra`, `wazuh` ou `tools`;
   - só copiar, sem rodar: `./deploy/deploy.sh tools --copy-only`.
4. Na VM, preencher o `.env` e subir os containers, conforme o README da pasta do servidor.

## Ordem de implantação

1. Proxmox: discos de logs e VMs já criados (VMIDs 100, 101 e 102).
2. Ubuntu 26.04 nas três VMs, com IPs fixos.
3. `./deploy/deploy.sh all`, com a tag do Wazuh definida.
4. Preencher o `.env` em cada VM e subir os serviços, na ordem: infra, tools e depois Wazuh.
5. Configurar o túnel Cloudflare e o NPM.
6. Registrar os agentes do Wazuh e montar o pipeline de vulnerabilidades.

## Segurança

- Nenhum segredo fica no repositório. Senhas e tokens ficam só no `.env` de cada VM, com permissão 600.
- O deploy não envia o `.env`.
- Painéis administrativos (NPM, TheHive, Cortex e Wazuh) não ficam expostos diretamente: passam por Cloudflare Access ou ficam em rede interna.
- O Ollama está em `127.0.0.1`, sem autenticação própria. Não exponha na Cloudflare sem proxy com login.
- Manter o repositório privado.

## Arquivos antigos a remover

Estes arquivos foram substituídos pela nova estrutura e devem sair do repositório:

```bash
git rm -r infra tools
git rm scripts/setup-server.sh scripts/setup-infra.sh scripts/setup-wazuh.sh scripts/setup-tools.sh scripts/guest-setup-log-volume.sh
```
