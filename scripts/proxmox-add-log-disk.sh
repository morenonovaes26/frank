#!/usr/bin/env bash
# Executar NO PROXMOX (pve-prod02) como root.
# Cria e anexa um disco virtual dedicado para logs a uma VM.
#
# Uso: ./proxmox-add-log-disk.sh <VMID> <TAMANHO_GB> <STORAGE> [SLOT]
#   Ex.: ./proxmox-add-log-disk.sh 101 200 local-lvm
#
# Depois de anexar, dentro da VM rode: sudo guest-setup-log-volume.sh

set -euo pipefail

VMID="${1:?Informe o VMID}"
SIZE_GB="${2:?Informe o tamanho em GB}"
STORAGE="${3:?Informe o storage (ex.: local-lvm)}"
SLOT="${4:-scsi1}"          # slot de disco livre na VM (ajustar se já estiver em uso)

if ! [[ "$SIZE_GB" =~ ^[0-9]+$ ]]; then
  echo "Tamanho inválido: $SIZE_GB" >&2
  exit 1
fi

if ! qm status "$VMID" >/dev/null 2>&1; then
  echo "VM $VMID não encontrada." >&2
  exit 1
fi

if qm config "$VMID" | grep -q "^${SLOT}:"; then
  echo "O slot $SLOT já está em uso na VM $VMID. Informe outro slot (ex.: scsi2)." >&2
  exit 1
fi

echo ">> Criando disco de ${SIZE_GB}G em ${STORAGE} e anexando em ${SLOT} da VM ${VMID}"
# Cria o disco com o nome padrão do Proxmox e anexa, com discard e iothread para melhor desempenho
qm set "$VMID" --"$SLOT" "${STORAGE}:${SIZE_GB},discard=on,iothread=1"

echo ">> Concluído. Configuração atual de disco da VM:"
qm config "$VMID" | grep -E "^(scsi|virtio|sata|ide)[0-9]+:" || true

cat <<EOF

Próximos passos:
  1. Dentro da VM, rode: sudo /opt/frank/scripts/guest-setup-log-volume.sh
  2. Para aumentar o disco no futuro:
       qm resize $VMID ${SLOT} +50G      (no Proxmox)
       sudo lvextend -r -l +100%FREE /dev/vg_logs/lv_logs   (na VM)
EOF
