#!/usr/bin/env bash
# =============================================================================
# Configuração da VM srv-frank-infra (192.168.80.74)
# Serviços: Cloudflared, Nginx Proxy Manager (NPM) e n8n
#
# Uso, dentro da VM, a partir da pasta copiada para /home/infra/frank:
#   sudo bash /home/infra/frank/scripts/setup-infra.sh
#
# O script é repetível: cada etapa verifica o que já foi feito.
# Ele NÃO sobe os containers. Isso é feito depois, com o .env preenchido.
# =============================================================================
set -Eeuo pipefail

HOST_EXPECTED="srv-frank-infra"
IP_EXPECTED="192.168.80.74"
TZ_NAME="America/Sao_Paulo"
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
  || die "Hostname é '$HOST_ACTUAL', esperado '$HOST_EXPECTED'. Este script é só para a VM de infra."

ADDRS="$(ip -4 -br addr)"
[[ "$ADDRS" == *"$IP_EXPECTED/"* ]] || die "IP $IP_EXPECTED não está configurado nesta VM."

[[ -f "$FRANK_DIR/infra/docker-compose.yml" ]] \
  || die "Não encontrei $FRANK_DIR/infra/docker-compose.yml. Copie a pasta frank completa."

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
# 2. Volume de logs: LVM no espaço livre do disco de sistema (ubuntu-vg)
# -----------------------------------------------------------------------------
log "Volume de logs em /srv/logs"
if mountpoint -q /srv/logs; then
  echo "/srv/logs já montado."
else
  if lvs ubuntu-vg/lv_logs >/dev/null 2>&1; then
    echo "Volume lv_logs já existe; apenas montando."
  else
    FREE_GB="$(vgs --noheadings --units g --nosuffix -o vg_free ubuntu-vg | tr -d ' ' | cut -d. -f1)"
    (( FREE_GB >= 20 )) || die "Espaço livre no ubuntu-vg insuficiente (${FREE_GB}G, mínimo 20G)."
    lvcreate -y -n lv_logs -l 100%FREE ubuntu-vg
    mkfs.xfs -f /dev/ubuntu-vg/lv_logs
  fi
  mkdir -p /srv/logs
  UUID="$(blkid -s UUID -o value /dev/ubuntu-vg/lv_logs)"
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
# 4. Pastas de dados dos serviços
# -----------------------------------------------------------------------------
log "Pastas de dados"
mkdir -p /srv/logs/{npm,n8n,cloudflared,data}
# /srv/data aponta para o volume de logs para os bancos e configurações não
# encherem o disco do sistema
[[ -e /srv/data ]] || ln -s /srv/logs/data /srv/data
mkdir -p /srv/data/{npm-db,npm/data,npm/letsencrypt,n8n}

# -----------------------------------------------------------------------------
# 5. Arquivo .env (criado como sendo do usuário, não do root)
# -----------------------------------------------------------------------------
log "Arquivo .env"
if [[ ! -f "$FRANK_DIR/.env" ]]; then
  cp "$FRANK_DIR/.env.example" "$FRANK_DIR/.env"
  echo "Criado $FRANK_DIR/.env a partir do exemplo. Preencha os valores antes de subir."
fi
chown "$OWNER:$OWNER" "$FRANK_DIR/.env"
chmod 600 "$FRANK_DIR/.env"
ln -sfn "$FRANK_DIR/.env" "$FRANK_DIR/infra/.env"

# -----------------------------------------------------------------------------
# 6. Validação do compose (sintaxe, sem subir nada)
# -----------------------------------------------------------------------------
log "Validando infra/docker-compose.yml"
docker compose -f "$FRANK_DIR/infra/docker-compose.yml" --env-file "$FRANK_DIR/.env" config -q \
  && echo "Compose válido."

# -----------------------------------------------------------------------------
# Resumo
# -----------------------------------------------------------------------------
log "Concluído. Próximos passos"
cat <<EOF
1. Preencher $FRANK_DIR/.env: domínio, token do túnel Cloudflare e senhas do NPM e do n8n.
2. Entrar no grupo docker (novo login) ou usar sudo.
3. cd $FRANK_DIR/infra && docker compose up -d
4. Criar o túnel no painel Zero Trust e apontar os hostnames para o NPM.
EOF
