#!/usr/bin/env bash
# =============================================================================
# Configuração da VM srv-frank-wazuh (192.168.80.75)
# Serviço: Wazuh (manager, indexador e dashboard) via wazuh-docker
#
# Uso, dentro da VM, informando a tag do wazuh-docker:
#   sudo WAZUH_DOCKER_TAG=<tag> bash /home/infra/frank/scripts/setup-wazuh.sh
#
# A tag precisa existir em https://github.com/wazuh/wazuh-docker/tags
# (versão 4.14.x, igual à do OVA usado antes).
#
# O script é repetível. Ele NÃO sobe o stack: isso é feito depois, com os
# certificados gerados e as senhas trocadas.
# =============================================================================
set -Eeuo pipefail

HOST_EXPECTED="srv-frank-wazuh"
IP_EXPECTED="192.168.80.75"
TZ_NAME="America/Sao_Paulo"
LOG_DEV="/dev/sdb"
WAZUH_REPO="https://github.com/wazuh/wazuh-docker.git"
WAZUH_DIR="/srv/wazuh-docker"
FRANK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OWNER="${SUDO_USER:-root}"

trap 'echo -e "\nERRO na linha $LINENO. Verifique a mensagem acima antes de repetir." >&2' ERR
log() { printf '\n==> %s\n' "$*"; }
die() { echo "ERRO: $*" >&2; exit 1; }

# -----------------------------------------------------------------------------
# 0. Checagens antes de qualquer alteração
# -----------------------------------------------------------------------------
[[ $EUID -eq 0 ]] || die "Execute com sudo."

HOST_ACTUAL="$(hostnamectl --static)"
[[ "$HOST_ACTUAL" == "$HOST_EXPECTED" ]] \
  || die "Hostname é '$HOST_ACTUAL', esperado '$HOST_EXPECTED'. Este script é só para a VM do Wazuh."

ADDRS="$(ip -4 -br addr)"
[[ "$ADDRS" == *"$IP_EXPECTED/"* ]] || die "IP $IP_EXPECTED não está configurado nesta VM."

[[ -n "${WAZUH_DOCKER_TAG:-}" ]] \
  || die "Informe a tag: sudo WAZUH_DOCKER_TAG=<tag> bash $0"
if [[ ! "$WAZUH_DOCKER_TAG" =~ ^v?4\.14\.[0-9]+$ ]]; then
  echo "AVISO: a tag '$WAZUH_DOCKER_TAG' não tem o formato 4.14.x. Confirme no GitHub antes de seguir."
fi

echo "OK: $HOST_ACTUAL ($IP_EXPECTED), tag $WAZUH_DOCKER_TAG"

# -----------------------------------------------------------------------------
# 1. Sistema base
# -----------------------------------------------------------------------------
log "Fuso horário, atualizações e pacotes"
timedatectl set-timezone "$TZ_NAME"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get -y full-upgrade
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  qemu-guest-agent lvm2 xfsprogs git curl ca-certificates
systemctl enable --now qemu-guest-agent

# -----------------------------------------------------------------------------
# 2. Disco de logs: /dev/sdb (500 GB, vazio) em LVM, montado em /srv/logs
# -----------------------------------------------------------------------------
log "Volume de logs em /srv/logs"
if mountpoint -q /srv/logs; then
  echo "/srv/logs já montado."
else
  [[ -b "$LOG_DEV" ]] || die "$LOG_DEV não existe."
  [[ "$(lsblk -dno TYPE "$LOG_DEV")" == "disk" ]] || die "$LOG_DEV não é um disco."

  CHILDREN="$(lsblk -no NAME "$LOG_DEV" | wc -l)"
  FSTYPE="$(lsblk -dno FSTYPE "$LOG_DEV")"
  if (( CHILDREN != 1 )) || [[ -n "$FSTYPE" ]]; then
    lsblk "$LOG_DEV"
    die "$LOG_DEV já tem partições ou sistema de arquivos. Abortando para não apagar dados."
  fi

  lsblk "$LOG_DEV"
  read -rp "ATENÇÃO: todos os dados em $LOG_DEV serão APAGADOS. Digite SIM para continuar: " CONFIRM
  [[ "$CONFIRM" == "SIM" ]] || die "Cancelado pelo usuário."

  pvcreate -y "$LOG_DEV"
  vgcreate vg_logs "$LOG_DEV"
  lvcreate -y -n lv_logs -l 100%FREE vg_logs
  mkfs.xfs -f /dev/vg_logs/lv_logs

  mkdir -p /srv/logs
  UUID="$(blkid -s UUID -o value /dev/vg_logs/lv_logs)"
  grep -qF "$UUID" /etc/fstab || echo "UUID=$UUID /srv/logs xfs defaults,noatime,nofail 0 2" >> /etc/fstab
  mount /srv/logs
fi
df -h /srv/logs

# -----------------------------------------------------------------------------
# 3. Docker: dados e logs no volume de logs, com rotação
# -----------------------------------------------------------------------------
log "Docker"
if ! command -v docker >/dev/null 2>&1; then
  DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io
fi
if ! docker compose version >/dev/null 2>&1; then
  apt-cache show docker-compose-v2 >/dev/null 2>&1 \
    || die "docker-compose-v2 não está nos repositórios. Instale o plugin Compose pelo repositório oficial do Docker."
  DEBIAN_FRONTEND=noninteractive apt-get install -y docker-compose-v2
fi

mkdir -p /srv/logs/docker
cat > /tmp/frank-daemon.json <<'EOF'
{
  "data-root": "/srv/logs/docker",
  "log-driver": "json-file",
  "log-opts": { "max-size": "50m", "max-file": "5" }
}
EOF
if ! cmp -s /tmp/frank-daemon.json /etc/docker/daemon.json; then
  install -m 644 /tmp/frank-daemon.json /etc/docker/daemon.json
  systemctl restart docker
fi
rm -f /tmp/frank-daemon.json
systemctl enable --now docker

ROOT_DIR="$(docker info --format '{{.DockerRootDir}}')"
[[ "$ROOT_DIR" == "/srv/logs/docker" ]] || die "Docker usa '$ROOT_DIR', esperado /srv/logs/docker."

if [[ "$OWNER" != "root" ]]; then
  usermod -aG docker "$OWNER"
  echo "Usuário $OWNER adicionado ao grupo docker (vale após novo login)."
fi

# -----------------------------------------------------------------------------
# 4. Parâmetro do kernel exigido pelo indexador (OpenSearch)
# -----------------------------------------------------------------------------
log "vm.max_map_count"
echo "vm.max_map_count=262144" > /etc/sysctl.d/99-frank-wazuh.conf
sysctl -p /etc/sysctl.d/99-frank-wazuh.conf >/dev/null
[[ "$(sysctl -n vm.max_map_count)" == "262144" ]] || die "vm.max_map_count não foi aplicado."

# -----------------------------------------------------------------------------
# 5. Pastas de dados
# -----------------------------------------------------------------------------
log "Pastas de dados"
mkdir -p /srv/logs/{wazuh/indexer,wazuh/manager,wazuh/dashboard,data}
[[ -e /srv/data ]] || ln -s /srv/logs/data /srv/data

# -----------------------------------------------------------------------------
# 6. Código do wazuh-docker na tag escolhida
# -----------------------------------------------------------------------------
log "wazuh-docker ($WAZUH_DOCKER_TAG)"
if [[ -d "$WAZUH_DIR/.git" ]]; then
  CURRENT_TAG="$(git -C "$WAZUH_DIR" describe --tags --exact-match 2>/dev/null || echo "desconhecida")"
  if [[ "$CURRENT_TAG" != "$WAZUH_DOCKER_TAG" ]]; then
    die "$WAZUH_DIR já existe na versão '$CURRENT_TAG'. Remova a pasta ou use a mesma tag."
  fi
  echo "Repositório já está na tag $WAZUH_DOCKER_TAG."
else
  git clone --depth 1 --branch "$WAZUH_DOCKER_TAG" "$WAZUH_REPO" "$WAZUH_DIR"
fi

SINGLE_NODE="$WAZUH_DIR/single-node"
[[ -f "$SINGLE_NODE/docker-compose.yml" ]] \
  || echo "AVISO: não encontrei $SINGLE_NODE/docker-compose.yml. Confira a estrutura do repositório nesta tag."

# -----------------------------------------------------------------------------
# Resumo
# -----------------------------------------------------------------------------
log "Concluído. Próximos passos"
cat <<EOF
1. Ler o README do wazuh-docker em $WAZUH_DIR para a versão $WAZUH_DOCKER_TAG.
2. Gerar os certificados do indexador seguindo esse README.
3. Trocar as senhas padrão do indexador, do manager e do dashboard.
4. Subir o stack a partir de $SINGLE_NODE (docker compose up -d).
5. Registrar os agentes e ativar a detecção de vulnerabilidades.
EOF
