#!/usr/bin/env bash
# Configuração inicial de cada VM do projeto Frank (Ubuntu Server 26.04).
#
# Uso (dentro da VM, a partir da pasta copiada do srv-frank-ia):
#   sudo bash scripts/setup-server.sh wazuh
#   sudo bash scripts/setup-server.sh infra
#   sudo bash scripts/setup-server.sh tools
#
# Para o Wazuh, informe a tag da versão do wazuh-docker antes de rodar:
#   sudo WAZUH_DOCKER_TAG=<tag> bash scripts/setup-server.sh wazuh
#
# O script é seguro de rodar de novo: cada etapa verifica se já foi feita.
# Ele NÃO sobe os containers. Isso é feito depois, manualmente, com os .env preenchidos.

set -euo pipefail

ROLE="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRANK_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

log()  { echo -e "\n==> $*"; }
warn() { echo -e "\n!! $*" >&2; }

if [[ $EUID -ne 0 ]]; then
  echo "Execute com sudo." >&2
  exit 1
fi

case "$ROLE" in
  wazuh) EXPECTED_IP="192.168.80.75"; EXPECTED_HOST="srv-frank-wazuh" ;;
  infra) EXPECTED_IP="192.168.80.74"; EXPECTED_HOST="srv-frank-infra" ;;
  tools) EXPECTED_IP="192.168.80.76"; EXPECTED_HOST="srv-frank-tools" ;;
  *)
    echo "Uso: sudo bash $0 <wazuh|infra|tools>" >&2
    exit 1
    ;;
esac

# ---------------------------------------------------------------------------
# 0. Confirmar que está na VM certa
# ---------------------------------------------------------------------------
log "Verificando host e IP"
CURRENT_HOST="$(hostnamectl --static 2>/dev/null || hostname)"
if [[ "$CURRENT_HOST" != "$EXPECTED_HOST" ]]; then
  warn "Hostname atual é '$CURRENT_HOST', esperado '$EXPECTED_HOST'."
  read -rp "Continuar mesmo assim? Digite SIM: " CONFIRM
  [[ "$CONFIRM" == "SIM" ]] || exit 1
fi
if ! ip -br addr | grep -q "$EXPECTED_IP"; then
  echo "IP $EXPECTED_IP não encontrado nesta VM. Abortando." >&2
  exit 1
fi
echo "OK: $CURRENT_HOST com IP $EXPECTED_IP"

# ---------------------------------------------------------------------------
# 1. Base do sistema
# ---------------------------------------------------------------------------
log "Fuso horário e atualizações"
timedatectl set-timezone America/Sao_Paulo
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get -y full-upgrade

log "Pacotes básicos e agente do QEMU"
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  qemu-guest-agent lvm2 xfsprogs curl ca-certificates git
systemctl enable --now qemu-guest-agent

# ---------------------------------------------------------------------------
# 2. Docker
# ---------------------------------------------------------------------------
log "Docker"
if ! command -v docker >/dev/null 2>&1; then
  DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io docker-compose-v2
fi
systemctl enable --now docker
if [[ -n "${SUDO_USER:-}" ]]; then
  usermod -aG docker "$SUDO_USER"
  echo "Usuário $SUDO_USER adicionado ao grupo docker (vale após novo login)."
fi

# ---------------------------------------------------------------------------
# 3. Volume de logs em /srv/logs
# ---------------------------------------------------------------------------
setup_log_volume() {
  if mountpoint -q /srv/logs; then
    echo "/srv/logs já montado."
    return
  fi

  if [[ "$ROLE" == "infra" ]]; then
    # Infra: usa o espaço livre do grupo de volumes do disco de sistema
    if lvs ubuntu-vg/lv_logs >/dev/null 2>&1; then
      echo "Volume lv_logs já existe, apenas montando."
    else
      log "Criando lv_logs com o espaço livre do ubuntu-vg"
      lvcreate -y -n lv_logs -l 100%FREE ubuntu-vg
      mkfs.xfs /dev/ubuntu-vg/lv_logs
    fi
    mkdir -p /srv/logs
    UUID="$(blkid -s UUID -o value /dev/ubuntu-vg/lv_logs)"
    grep -q "$UUID" /etc/fstab || \
      echo "UUID=$UUID /srv/logs xfs defaults,noatime,nofail 0 2" >> /etc/fstab
    mount -a
  else
    # Wazuh e Tools: disco de 500 GB dedicado (/dev/sdb), com confirmação no script
    if [[ ! -b /dev/sdb ]]; then
      warn "Disco /dev/sdb não encontrado. Pulando volume de logs."
      return
    fi
    log "Preparando /dev/sdb como volume de logs"
    bash "$SCRIPT_DIR/guest-setup-log-volume.sh" /dev/sdb
  fi
}

log "Volume de logs"
setup_log_volume

# /srv/data aponta para o volume de logs, para que os dados dos containers
# (bancos, índices, configurações) não encham o disco do sistema.
if mountpoint -q /srv/logs; then
  mkdir -p /srv/logs/data
  if [[ ! -e /srv/data ]]; then
    ln -s /srv/logs/data /srv/data
    echo "/srv/data -> /srv/logs/data criado."
  fi
fi

# ---------------------------------------------------------------------------
# 4. Parâmetros específicos de cada papel
# ---------------------------------------------------------------------------
case "$ROLE" in

  wazuh)
    log "Parâmetro do kernel para o indexador do Wazuh"
    echo "vm.max_map_count=262144" > /etc/sysctl.d/99-frank.conf
    sysctl --system >/dev/null

    log "Diretórios de dados do Wazuh"
    mkdir -p /srv/logs/wazuh/{indexer,manager,dashboard}

    log "wazuh-docker"
    if [[ -z "${WAZUH_DOCKER_TAG:-}" ]]; then
      warn "WAZUH_DOCKER_TAG não informada. Clone pulado."
      echo "Rode de novo com: sudo WAZUH_DOCKER_TAG=<tag> bash $0 wazuh"
      echo "Confira a tag da versão 4.14.x em https://github.com/wazuh/wazuh-docker/tags"
    elif [[ -d /srv/wazuh-docker ]]; then
      echo "/srv/wazuh-docker já existe, pulando clone."
    else
      git clone --depth 1 --branch "$WAZUH_DOCKER_TAG" \
        https://github.com/wazuh/wazuh-docker.git /srv/wazuh-docker
    fi
    ;;

  infra)
    log "Estrutura de dados da infra"
    mkdir -p /srv/logs/{npm,n8n,cloudflared}
    mkdir -p /srv/data/{npm-db,npm/data,npm/letsencrypt,n8n}

    log "Arquivo .env"
    if [[ ! -f "$FRANK_DIR/.env" ]]; then
      cp "$FRANK_DIR/.env.example" "$FRANK_DIR/.env"
      chmod 600 "$FRANK_DIR/.env"
      warn "Criado $FRANK_DIR/.env a partir do exemplo. Preencha os valores antes de subir os containers."
    fi
    ln -sfn "$FRANK_DIR/.env" "$FRANK_DIR/infra/.env"
    ;;

  tools)
    log "Parâmetro do kernel para o Elasticsearch"
    echo "vm.max_map_count=262144" > /etc/sysctl.d/99-frank.conf
    sysctl --system >/dev/null

    log "Estrutura de dados das ferramentas"
    mkdir -p /srv/logs/{elasticsearch,thehive,cortex}
    mkdir -p /srv/data/{elasticsearch,thehive,cortex}

    log "Arquivo .env"
    if [[ ! -f "$FRANK_DIR/.env" ]]; then
      cp "$FRANK_DIR/.env.example" "$FRANK_DIR/.env"
      chmod 600 "$FRANK_DIR/.env"
      warn "Criado $FRANK_DIR/.env a partir do exemplo. Preencha os valores antes de subir os containers."
    fi
    ln -sfn "$FRANK_DIR/.env" "$FRANK_DIR/tools/.env"
    ;;
esac

# ---------------------------------------------------------------------------
# 5. Resumo e próximos passos
# ---------------------------------------------------------------------------
log "Resumo"
df -h / /srv/logs 2>/dev/null || true
docker --version
docker compose version

log "Próximos passos ($ROLE)"
case "$ROLE" in
  wazuh)
    echo "1. Gerar certificados e subir o stack, seguindo o README do wazuh-docker em /srv/wazuh-docker."
    echo "2. Trocar as senhas padrão do indexador, do manager e do dashboard."
    echo "3. Registrar os agentes e ativar a detecção de vulnerabilidades."
    ;;
  infra)
    echo "1. Preencher $FRANK_DIR/.env (domínio, token do túnel, senhas do NPM e do n8n)."
    echo "2. cd $FRANK_DIR/infra && docker compose up -d"
    ;;
  tools)
    echo "1. Preencher $FRANK_DIR/.env (senhas do Elasticsearch, TheHive e Cortex e chaves de API)."
    echo "2. Validar as versões do TheHive e do Cortex em tools/docker-compose.yml."
    echo "3. cd $FRANK_DIR/tools && docker compose up -d"
    ;;
esac
