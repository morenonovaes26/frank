#!/usr/bin/env bash
# =============================================================================
# Bootstrap da VM srv-frank-infra (192.168.80.74)
# Serviços: Cloudflared, Nginx Proxy Manager (NPM) e n8n
#
# Normalmente executado pelo deploy/deploy.sh a partir do PC de controle.
# Também pode ser rodado direto na VM:
#   sudo bash ~/frank/servers/infra/bootstrap.sh
#
# Não sobe os containers. Isso é feito depois, com o .env preenchido.
# =============================================================================
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SERVER_DIR="$ROOT/servers/infra"
# shellcheck source=../../shared/lib/common.sh
source "$ROOT/shared/lib/common.sh"

OWNER="${SUDO_USER:-root}"
trap 'echo -e "\nFalhou na linha $LINENO. Corrija a causa e rode de novo: o script é repetível." >&2' ERR

frank_require_root
frank_check_identity "srv-frank-infra" "192.168.80.74"
frank_base_system "America/Sao_Paulo"
frank_logs_from_free_space
frank_setup_docker "$OWNER"

frank_log "Pastas de dados da infra"
frank_link_data_dir
mkdir -p /srv/logs/{npm,n8n,cloudflared}
mkdir -p /srv/data/{npm-db,npm/data,npm/letsencrypt,n8n}

frank_prepare_env "$ROOT" "$OWNER"
frank_link_env "$ROOT" "$SERVER_DIR"
frank_validate_compose "$ROOT" "$SERVER_DIR"

frank_log "Concluído: infra pronta"
cat <<EOF
Próximos passos (na VM, como usuário $OWNER):
  1. Preencher $ROOT/.env: DOMAIN, CLOUDFLARE_TUNNEL_TOKEN, senhas do NPM e do n8n.
  2. cd $SERVER_DIR && docker compose up -d
  3. Criar o túnel no painel Zero Trust e apontar os hostnames para o NPM (porta 80).
EOF
