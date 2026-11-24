#!/usr/bin/env bash
# Executar DENTRO da VM como root, após anexar o disco no Proxmox.
# Detecta o disco novo (sem partições e sem sistema de arquivos), cria VG/LV com LVM,
# formata em XFS e monta em /srv/logs via /etc/fstab (por UUID).
#
# Uso: sudo ./guest-setup-log-volume.sh [/dev/sdX]
#   Sem argumento, o script tenta detectar o disco automaticamente e pede confirmação.

set -euo pipefail

MOUNT_POINT="/srv/logs"
VG_NAME="vg_logs"
LV_NAME="lv_logs"
DEVICE="${1:-}"

if [[ $EUID -ne 0 ]]; then
  echo "Execute como root (sudo)." >&2
  exit 1
fi

for cmd in lsblk pvcreate vgcreate lvcreate mkfs.xfs blkid; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Comando ausente: $cmd (instale lvm2 e xfsprogs)" >&2; exit 1; }
done

if [[ -z "$DEVICE" ]]; then
  # Disco sem partições, sem fstype e sem ponto de montagem, excluindo o disco de sistema
  mapfile -t CANDIDATES < <(lsblk -dpno NAME,TYPE | awk '$2=="disk"{print $1}' | while read -r d; do
    children=$(lsblk -no NAME "$d" | wc -l)
    fstype=$(lsblk -dno FSTYPE "$d")
    if [[ "$children" -eq 1 && -z "$fstype" ]]; then echo "$d"; fi
  done)
  if [[ ${#CANDIDATES[@]} -ne 1 ]]; then
    echo "Não foi possível detectar um único disco novo. Candidatos: ${CANDIDATES[*]:-nenhum}" >&2
    echo "Informe explicitamente: sudo $0 /dev/sdX" >&2
    lsblk
    exit 1
  fi
  DEVICE="${CANDIDATES[0]}"
fi

if [[ ! -b "$DEVICE" ]]; then
  echo "Dispositivo inválido: $DEVICE" >&2
  exit 1
fi

if [[ -n "$(lsblk -no FSTYPE "$DEVICE" | grep -v '^$' || true)" || "$(lsblk -no NAME "$DEVICE" | wc -l)" -gt 1 ]]; then
  echo "$DEVICE já possui partições ou sistema de arquivos. Abortando para não apagar dados." >&2
  lsblk "$DEVICE"
  exit 1
fi

echo "Disco selecionado: $DEVICE"
lsblk "$DEVICE"
read -rp "ATENÇÃO: todos os dados em $DEVICE serão apagados. Digite SIM para continuar: " CONFIRM
[[ "$CONFIRM" == "SIM" ]] || { echo "Cancelado."; exit 1; }

pvcreate "$DEVICE"
vgcreate "$VG_NAME" "$DEVICE"
lvcreate -n "$LV_NAME" -l 100%FREE "$VG_NAME"
mkfs.xfs -f "/dev/$VG_NAME/$LV_NAME"

mkdir -p "$MOUNT_POINT"
UUID=$(blkid -s UUID -o value "/dev/$VG_NAME/$LV_NAME")
FSTAB_LINE="UUID=$UUID $MOUNT_POINT xfs defaults,noatime,nofail 0 2"

if ! grep -q "$UUID" /etc/fstab; then
  echo "$FSTAB_LINE" >> /etc/fstab
fi

mount -a
mkdir -p "$MOUNT_POINT"/{wazuh,docker,npm,n8n,thehive,cortex,elasticsearch,other}
chmod 0755 "$MOUNT_POINT"

echo
echo "Volume de logs pronto em $MOUNT_POINT:"
df -h "$MOUNT_POINT"
echo
echo "Subpastas criadas: wazuh, docker, npm, n8n, thehive, cortex, elasticsearch, other"
echo "Para crescer depois: sudo lvextend -r -l +100%FREE /dev/$VG_NAME/$LV_NAME"
