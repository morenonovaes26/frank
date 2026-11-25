#!/usr/bin/env bash
# =============================================================================
# Bootstrap da VM srv-frank-wazuh (192.168.80.75)
# Serviço: Wazuh (manager, indexador e dashboard) via repositório wazuh-docker
#
# Exige a tag do wazuh-docker (versão 4.14.x). Confira em:
#   https://github.com/wazuh/wazuh-docker/tags
#
# Normalmente executado pelo deploy/deploy.sh. Também pode ser rodado direto:
#   sudo WAZUH_DOCKER_TAG=<tag> bash ~/frank/servers/wazuh/bootstrap.sh
#
# Não sobe o stack: os certificados e as senhas são tratados no README da pasta.
# =============================================================================
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SERVER_DIR="$ROOT/servers/wazuh"
# shellcheck source=../../shared/lib/common.sh
source "$ROOT/shared/lib/common.sh"

OWNER="${SUDO_USER:-root}"
LOG_DEV="/dev/sdb"
WAZUH_REPO="https://github.com/wazuh/wazuh-docker.git"
WAZUH_DIR="/srv/wazuh-docker"
trap 'echo -e "\nFalhou na linha $LINENO. Corrija a causa e rode de novo: o script é repetível." >&2' ERR

frank_require_root
frank_check_identity "srv-frank-wazuh" "192.168.80.75"

[[ -n "${WAZUH_DOCKER_TAG:-}" ]] || frank_die "Informe a tag: sudo WAZUH_DOCKER_TAG=<tag> bash $0"
if [[ ! "$WAZUH_DOCKER_TAG" =~ ^v?4\.14\.[0-9]+$ ]]; then
  frank_info "AVISO: a tag '$WAZUH_DOCKER_TAG' não tem o formato 4.14.x. Confirme no GitHub."
fi

frank_base_system "America/Sao_Paulo"
frank_logs_from_disk "$LOG_DEV"
frank_setup_docker "$OWNER"
frank_sysctl_max_map_count "wazuh"

frank_log "Pastas de dados do Wazuh"
frank_link_data_dir
mkdir -p /srv/logs/wazuh/{indexer,manager,dashboard}

frank_log "wazuh-docker ($WAZUH_DOCKER_TAG)"
if [[ -d "$WAZUH_DIR/.git" ]]; then
  current_tag="$(git -C "$WAZUH_DIR" describe --tags --exact-match 2>/dev/null || echo desconhecida)"
  [[ "$current_tag" == "$WAZUH_DOCKER_TAG" ]] \
    || frank_die "$WAZUH_DIR já está na versão '$current_tag'. Remova a pasta ou use a mesma tag."
  frank_info "Já está na tag $WAZUH_DOCKER_TAG."
else
  git clone --depth 1 --branch "$WAZUH_DOCKER_TAG" "$WAZUH_REPO" "$WAZUH_DIR"
fi
[[ -f "$WAZUH_DIR/single-node/docker-compose.yml" ]] \
  || frank_info "AVISO: single-node/docker-compose.yml não encontrado nesta tag. Confira a estrutura do repositório."

frank_log "Concluído: Wazuh preparado (sem subir o stack)"
cat <<EOF
Próximos passos, conforme $SERVER_DIR/README.md:
  1. Gerar os certificados do indexador.
  2. Trocar as senhas padrão do indexador, do manager e do dashboard.
  3. Subir o stack a partir de $WAZUH_DIR/single-node.
  4. Registrar os agentes e ativar a detecção de vulnerabilidades.
EOF
