# Projeto Frank – Ecossistema de IA para Segurança

Estrutura de referência do homelab, com arquivos de configuração para subir o ambiente.

## Topologia

| Host | Função | Serviços |
|---|---|---|
| pc-gpu | Inferência de IA | Ollama, Ubuntu Server 24.04 |
| pve-prod02 | Hypervisor (Proxmox VE 9.2) | VM Alma Linux (Wazuh), VM Ubuntu 26.04 Infra, VM Ubuntu 26.04 Tools |

### VMs no pve-prod02

- **alma-wazuh** (AlmaLinux): Wazuh (SIEM/XDR, detecção e inventário de vulnerabilidades).
- **ubuntu-infra** (Ubuntu 26.04, Docker): Cloudflared, Nginx Proxy Manager (NPM), n8n.
- **ubuntu-tools** (Ubuntu 26.04, Docker): TheHive, Cortex, Threat Intelligence e scripts de consulta de APIs.

## Estrutura da pasta

```
frank/
├── README.md                  este arquivo
├── inventario.yaml            fonte da verdade: hosts, VMs, serviços, portas e discos
├── .env.example               variáveis (copiar para .env, nunca versionar o .env)
├── infra/
│   └── docker-compose.yml     Cloudflared, NPM, n8n
├── tools/
│   └── docker-compose.yml     TheHive, Cortex (template, validar versões)
├── scripts/
│   ├── proxmox-add-log-disk.sh   (executar no Proxmox) cria e anexa disco para logs
│   └── guest-setup-log-volume.sh (executar na VM) prepara LVM e monta /srv/logs
├── vulnerabilidades/
│   └── README.md              ideias e pipeline de Assessment de Vulnerabilidades
└── cloudflare/
    └── README.md              recursos Cloudflare e custos
```

## Ordem sugerida de implantação

1. Confirmar IPs e nomes no `inventario.yaml`.
2. Criar o disco de logs (ver seção abaixo e `scripts/`).
3. Subir a VM `ubuntu-infra` e instalar Docker; copiar `infra/`, preencher `.env` e executar `docker compose up -d`.
4. Configurar o túnel Cloudflare (ver `cloudflare/README.md`) apontando para o NPM.
5. Subir a VM `ubuntu-tools` com `tools/`.
6. Instalar Wazuh na VM `alma-wazuh` e configurar os agentes.
7. Implementar o pipeline de vulnerabilidades (ver `vulnerabilidades/README.md`).

## Disco dedicado para logs

Recomendação: um disco virtual separado por VM que gera logs (alma-wazuh e ubuntu-tools principalmente), montado em `/srv/logs` com LVM.

Por que LVM e não um disco montado direto:

- Permite aumentar o volume depois sem reparticionar (`lvextend -r`), bastando crescer o disco no Proxmox.
- Facilita trocar ou adicionar discos no futuro.
- Os diretórios de log dos serviços (Wazuh em `/var/ossec/logs`, Docker, etc.) podem apontar para subpastas de `/srv/logs` via bind mount ou symlink, sem mexer na configuração dos serviços.

Fluxo:

1. No Proxmox: `scripts/proxmox-add-log-disk.sh <VMID> <tamanho_GB> <storage>`.
2. Na VM: `sudo scripts/guest-setup-log-volume.sh` (detecta o disco novo, cria VG/LV, formata XFS e grava no `/etc/fstab` por UUID).
3. Para crescer depois: aumentar o disco no Proxmox e rodar `sudo lvextend -r -l +100%FREE /dev/vg_logs/lv_logs`.

Retenção sugerida: Wazuh com rotação do próprio serviço e um `logrotate` para `/srv/logs`; alerta de uso acima de 80% (ver inventário).

## Segurança

- Nenhum segredo neste repositório. Senhas e tokens ficam em `.env` (ignorado pelo git) ou em um gerenciador de segredos.
- Serviços administrativos (NPM, TheHive, Cortex, n8n) não devem ser expostos diretamente à internet; acessar via Cloudflare Access ou rede interna.
- Atualizar imagens Docker periodicamente e fixar versões nos compose quando possível.
