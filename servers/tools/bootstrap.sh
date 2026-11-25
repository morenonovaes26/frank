#!/usr/bin/env bash
# =============================================================================
# Bootstrap da VM srv-frank-tools (192.168.80.76)
# Serviços: Elasticsearch, TheHive, Cortex e coletores de threat intelligence
#
# Normalmente executado pelo deploy/deploy.sh. Também pode ser rodado direto:
#   sudo bash ~/frank/servers/tools/bootstrap.sh
#
# Não sobe os containers: antes é preciso validar as versões de TheHive e Cortex
# e preencher o .env.
# =============================================================================
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SERVER_DIR="$ROOT/servers/tools"
# shellcheck source=../../shared/lib/common.sh
source "$ROOT/shared/lib/common.sh"

OWNER="${SUDO_USER:-root}"
LOG_DEV="/dev/sdb"
trap 'echo -e "\nFalhou na linha $LINENO. Corrija a causa e rode de novo: o script é repetível." >&2' ERR

frank_require_root
frank_check_identity "srv-frank-tools" "192.168.80.76"
frank_base_system "America/Sao_Paulo"
frank_logs_from_disk "$LOG_DEV"
frank_setup_docker "$OWNER"
frank_sysctl_max_map_count "tools"

frank_log "Pastas de dados das ferramentas"
frank_link_data_dir
mkdir -p /srv/logs/{elasticsearch,thehive,cortex}
mkdir -p /srv/data/{elasticsearch,thehive,cortex}

frank_prepare_env "$ROOT" "$OWNER"
frank_link_env "$ROOT" "$SERVER_DIR"
frank_validate_compose "$ROOT" "$SERVER_DIR"

frank_log "Concluído: ferramentas prontas"
cat <<EOF
Próximos passos (na VM, como usuário $OWNER):
  1. Preencher $ROOT/.env: senhas do Elasticsearch, TheHive e Cortex, chaves de API.
  2. Validar as versões de TheHive e Cortex em $SERVER_DIR/docker-compose.yml (marcadas com TODO).
  3. cd $SERVER_DIR && docker compose up -d
EOF
