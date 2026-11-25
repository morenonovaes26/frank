#!/usr/bin/env bash
# =============================================================================
# Deploy do projeto Frank a partir do PC de controle.
# O PC NÃO faz parte do ecossistema: ele só envia os arquivos e dispara os
# bootstraps dentro de cada VM.
#
# Uso:
#   ./deploy/deploy.sh <infra|wazuh|tools|all> [--copy-only]
#
#   --copy-only  só copia a pasta do projeto para a VM, sem rodar o bootstrap
#
# Para o wazuh, informe a tag antes:
#   WAZUH_DOCKER_TAG=4.14.x ./deploy/deploy.sh wazuh
#
# O .env nunca é enviado: ele é criado e preenchido dentro de cada VM.
# =============================================================================
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=hosts.conf
source "$ROOT/deploy/hosts.conf"

die() { echo "ERRO: $*" >&2; exit 1; }
log() { printf '\n==> %s\n' "$*"; }

TARGET="${1:-}"
COPY_ONLY="${2:-}"
[[ -n "$TARGET" ]] || die "Uso: $0 <infra|wazuh|tools|all> [--copy-only]"

if [[ "$TARGET" == "all" ]]; then
  ROLES=(infra wazuh tools)
else
  [[ -n "${VM_IP[$TARGET]:-}" ]] || die "Papel desconhecido: $TARGET"
  ROLES=("$TARGET")
fi

for role in "${ROLES[@]}"; do
  ip="${VM_IP[$role]}"
  target="$SSH_USER@$ip"

  log "[$role] Copiando projeto para $target:~/frank"
  # tar via ssh: envia tudo, exceto Git, segredos e imagens grandes
  tar -C "$ROOT" \
      --exclude='.git' --exclude='.env' --exclude='*.iso' --exclude='*.ova' \
      -cf - . \
    | ssh "$target" 'mkdir -p ~/frank && tar -C ~/frank -xf -'

  if [[ "$COPY_ONLY" == "--copy-only" ]]; then
    echo "Cópia concluída. Bootstrap não executado."
    continue
  fi

  log "[$role] Executando bootstrap (vai pedir a senha do sudo na VM)"
  if [[ "$role" == "wazuh" ]]; then
    [[ -n "$WAZUH_DOCKER_TAG" ]] || die "Defina WAZUH_DOCKER_TAG para o Wazuh."
    ssh -t "$target" "sudo env WAZUH_DOCKER_TAG=$WAZUH_DOCKER_TAG bash ~/frank/servers/$role/bootstrap.sh"
  else
    ssh -t "$target" "sudo bash ~/frank/servers/$role/bootstrap.sh"
  fi
done

log "Deploy finalizado."
