#!/usr/bin/env bash
# =============================================================================
# Configuração da VM srv-frank-tools (192.168.80.76)
# Serviços: Elasticsearch, TheHive, Cortex e coletores de threat intelligence
#
# Uso, dentro da VM, a partir da pasta copiada para /home/infra/frank:
#   sudo bash /home/infra/frank/scripts/setup-tools.sh
#
# O script é repetível. Ele NÃO sobe os containers: antes é preciso validar
# as versões do TheHive e do Cortex e preencher o .env.
# =============================================================================
set -Eeuo pipefail

HOST_EXPECTED="srv-frank-tools"
IP_EXPECTED="192.168.80.76"
TZ_NAME="America/Sao_Paulo"
LOG_DEV="/dev/sdb"
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
  || die "Hostname é '$HOST_ACTUAL', esperado '$HOST_EXPECTED'. Este script é só para a VM de tools."

ADDRS="$(ip -4 -br addr)"
[[ "$ADDRS" == *"$IP_EXPECTED/"* ]] || die "IP $IP_EXPECTED não está configurado nesta VM."

[[ -f "$FRANK_DIR/tools/docker-compose.yml" ]] \
  || die "Não encontrei $FRANK_DIR/tools/docker-compose.yml. Copie a pasta frank completa."

echo "OK: $HOST_ACTUAL ($IP_EXPECTED), projeto em $FRANK_DIR"

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
# 4. Parâmetro do kernel exigido pelo Elasticsearch
# -----------------------------------------------------------------------------
log "vm.max_map_count"
echo "vm.max_map_count=262144" > /etc/sysctl.d/99-frank-tools.conf
sysctl -p /etc/sysctl.d/99-frank-tools.conf >/dev/null
[[ "$(sysctl -n vm.max_map_count)" == "262144" ]] || die "vm.max_map_count não foi aplicado."

# -----------------------------------------------------------------------------
# 5. Pastas de dados (no volume de logs, não no disco de sistema)
# -----------------------------------------------------------------------------
log "Pastas de dados"
mkdir -p /srv/logs/{elasticsearch,thehive,cortex,data}
[[ -e /srv/data ]] || ln -s /srv/logs/data /srv/data
mkdir -p /srv/data/{elasticsearch,thehive,cortex}

# -----------------------------------------------------------------------------
# 6. Arquivo .env (criado como sendo do usuário, não do root)
# -----------------------------------------------------------------------------
log "Arquivo .env"
if [[ ! -f "$FRANK_DIR/.env" ]]; then
  cp "$FRANK_DIR/.env.example" "$FRANK_DIR/.env"
  echo "Criado $FRANK_DIR/.env a partir do exemplo. Preencha os valores antes de subir."
fi
chown "$OWNER:$OWNER" "$FRANK_DIR/.env"
chmod 600 "$FRANK_DIR/.env"
ln -sfn "$FRANK_DIR/.env" "$FRANK_DIR/tools/.env"

# -----------------------------------------------------------------------------
# 7. Validação do compose (sintaxe, sem subir nada)
# -----------------------------------------------------------------------------
log "Validando tools/docker-compose.yml"
docker compose -f "$FRANK_DIR/tools/docker-compose.yml" --env-file "$FRANK_DIR/.env" config -q \
  && echo "Compose válido."

# -----------------------------------------------------------------------------
# Resumo
# -----------------------------------------------------------------------------
log "Concluído. Próximos passos"
cat <<EOF
1. Preencher $FRANK_DIR/.env: senhas do Elasticsearch, TheHive e Cortex e chaves de API.
2. Validar as versões das imagens do TheHive e do Cortex em $FRANK_DIR/tools/docker-compose.yml
   (estão marcadas com TODO). Versões incompatíveis impedem o TheHive de subir.
3. cd $FRANK_DIR/tools && docker compose up -d
EOF
