#!/usr/bin/env bash
# =============================================================================
# Funções compartilhadas pelos bootstraps das VMs do projeto Frank.
# Este arquivo é carregado com "source" pelos servers/<papel>/bootstrap.sh.
# Não execute diretamente.
# =============================================================================

frank_log()  { printf '\n==> %s\n' "$*"; }
frank_info() { printf '    %s\n' "$*"; }
frank_die()  { printf '\nERRO: %s\n' "$*" >&2; exit 1; }

# Só roda como root (o bootstrap é chamado com sudo)
frank_require_root() {
  [[ $EUID -eq 0 ]] || frank_die "Execute com sudo."
}

# Confere hostname e IP antes de qualquer alteração.
# Uso: frank_check_identity <hostname> <ip>
frank_check_identity() {
  local host_expected="$1" ip_expected="$2"
  local host_actual addrs
  host_actual="$(hostnamectl --static)"
  [[ "$host_actual" == "$host_expected" ]] \
    || frank_die "Hostname é '$host_actual', esperado '$host_expected'. Bootstrap errado para esta VM."
  addrs="$(ip -4 -br addr)"
  [[ "$addrs" == *"$ip_expected/"* ]] || frank_die "IP $ip_expected não está configurado nesta VM."
  frank_info "OK: $host_actual ($ip_expected)"
}

# Fuso, atualizações, agente do QEMU e ferramentas de disco.
# Uso: frank_base_system <fuso>
frank_base_system() {
  local tz="$1"
  frank_log "Sistema base"
  timedatectl set-timezone "$tz"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get -y full-upgrade
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    qemu-guest-agent lvm2 xfsprogs git curl ca-certificates
  systemctl enable --now qemu-guest-agent
}

# Monta /dev/<vg>/<lv> em /srv/logs via fstab (UUID, nofail).
frank_mount_logs_lv() {
  local vg="$1" lv="$2" uuid
  mkdir -p /srv/logs
  uuid="$(blkid -s UUID -o value "/dev/$vg/$lv")"
  [[ -n "$uuid" ]] || frank_die "Não consegui ler o UUID de /dev/$vg/$lv."
  grep -qF "$uuid" /etc/fstab || echo "UUID=$uuid /srv/logs xfs defaults,noatime,nofail 0 2" >> /etc/fstab
  mountpoint -q /srv/logs || mount /srv/logs
  df -h /srv/logs
}

# Infra: cria lv_logs com o espaço livre do ubuntu-vg (disco de sistema).
frank_logs_from_free_space() {
  frank_log "Volume de logs (LVM no espaço livre do disco de sistema)"
  if mountpoint -q /srv/logs; then
    frank_info "/srv/logs já montado."
    return
  fi
  if lvs ubuntu-vg/lv_logs >/dev/null 2>&1; then
    frank_info "lv_logs já existe; montando."
  else
    local free_gb
    free_gb="$(vgs --noheadings --units g --nosuffix -o vg_free ubuntu-vg | tr -d ' ' | cut -d. -f1)"
    (( free_gb >= 20 )) || frank_die "Espaço livre no ubuntu-vg insuficiente (${free_gb}G, mínimo 20G)."
    lvcreate -y -n lv_logs -l 100%FREE ubuntu-vg
    mkfs.xfs -f /dev/ubuntu-vg/lv_logs
  fi
  frank_mount_logs_lv ubuntu-vg lv_logs
}

# Wazuh e Tools: disco dedicado (vazio) vira LVM e é montado em /srv/logs.
# Recusa qualquer disco com partição ou sistema de arquivos e pede confirmação.
# Uso: frank_logs_from_disk <dispositivo>
frank_logs_from_disk() {
  local dev="$1" children fstype confirm
  frank_log "Volume de logs em $dev"
  if mountpoint -q /srv/logs; then
    frank_info "/srv/logs já montado."
    return
  fi
  [[ -b "$dev" ]] || frank_die "$dev não existe."
  [[ "$(lsblk -dno TYPE "$dev")" == "disk" ]] || frank_die "$dev não é um disco."

  children="$(lsblk -no NAME "$dev" | wc -l)"
  fstype="$(lsblk -dno FSTYPE "$dev")"
  if (( children != 1 )) || [[ -n "$fstype" ]]; then
    lsblk "$dev"
    frank_die "$dev já tem partições ou sistema de arquivos. Abortando para não apagar dados."
  fi

  lsblk "$dev"
  read -rp "ATENÇÃO: todos os dados em $dev serão APAGADOS. Digite SIM para continuar: " confirm
  [[ "$confirm" == "SIM" ]] || frank_die "Cancelado pelo usuário."

  pvcreate -y "$dev"
  vgcreate vg_logs "$dev"
  lvcreate -y -n lv_logs -l 100%FREE vg_logs
  mkfs.xfs -f /dev/vg_logs/lv_logs
  frank_mount_logs_lv vg_logs lv_logs
}

# Docker com dados em /srv/logs/docker e rotação de logs dos containers.
# Uso: frank_setup_docker <usuario_do_sudo>
frank_setup_docker() {
  local owner="$1" tmp root_dir
  frank_log "Docker"
  if ! command -v docker >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io
  fi
  if ! docker compose version >/dev/null 2>&1; then
    apt-cache show docker-compose-v2 >/dev/null 2>&1 \
      || frank_die "docker-compose-v2 não está nos repositórios. Instale o plugin Compose pelo repositório oficial do Docker."
    DEBIAN_FRONTEND=noninteractive apt-get install -y docker-compose-v2
  fi

  mkdir -p /srv/logs/docker
  tmp="$(mktemp)"
  cat > "$tmp" <<'EOF'
{
  "data-root": "/srv/logs/docker",
  "log-driver": "json-file",
  "log-opts": { "max-size": "50m", "max-file": "5" }
}
EOF
  if ! cmp -s "$tmp" /etc/docker/daemon.json; then
    install -m 644 "$tmp" /etc/docker/daemon.json
    systemctl restart docker
  fi
  rm -f "$tmp"
  systemctl enable --now docker

  root_dir="$(docker info --format '{{.DockerRootDir}}')"
  [[ "$root_dir" == "/srv/logs/docker" ]] || frank_die "Docker usa '$root_dir', esperado /srv/logs/docker."

  if [[ "$owner" != "root" ]]; then
    usermod -aG docker "$owner"
    frank_info "Usuário $owner adicionado ao grupo docker (vale no próximo login)."
  fi
}

# Parâmetro do kernel exigido pelo indexador/Elasticsearch.
# Uso: frank_sysctl_max_map_count <nome_do_arquivo>
frank_sysctl_max_map_count() {
  local name="$1" file="/etc/sysctl.d/99-frank-$1.conf"
  frank_log "vm.max_map_count"
  echo "vm.max_map_count=262144" > "$file"
  sysctl -p "$file" >/dev/null
  [[ "$(sysctl -n vm.max_map_count)" == "262144" ]] || frank_die "vm.max_map_count não foi aplicado."
}

# Pasta /srv/data aponta para o volume de logs, para dados de containers
# não encherem o disco de sistema.
frank_link_data_dir() {
  mountpoint -q /srv/logs || frank_die "/srv/logs não está montado; não vou criar /srv/data no disco de sistema."
  mkdir -p /srv/logs/data
  [[ -e /srv/data ]] || ln -s /srv/logs/data /srv/data
}

# Cria o .env a partir do exemplo, com dono correto e permissão 600.
# Uso: frank_prepare_env <raiz_do_projeto> <usuario>
frank_prepare_env() {
  local root="$1" owner="$2"
  frank_log "Arquivo .env"
  if [[ ! -f "$root/.env" ]]; then
    cp "$root/.env.example" "$root/.env"
    frank_info "Criado $root/.env a partir do exemplo. Preencha os valores antes de subir os serviços."
  else
    frank_info "$root/.env já existe; mantido sem alterações."
  fi
  chown "$owner:$owner" "$root/.env"
  chmod 600 "$root/.env"
}

# Liga o .env do projeto dentro da pasta do serviço, para o compose encontrá-lo.
# Uso: frank_link_env <raiz_do_projeto> <pasta_do_servico>
frank_link_env() {
  ln -sfn "$1/.env" "$2/.env"
}

# Valida a sintaxe do compose sem subir nada.
# Uso: frank_validate_compose <raiz_do_projeto> <pasta_do_servico>
frank_validate_compose() {
  frank_log "Validando docker-compose.yml de $(basename "$2")"
  docker compose -f "$2/docker-compose.yml" --env-file "$1/.env" config -q \
    || frank_die "docker-compose.yml inválido em $2."
  frank_info "Compose válido."
}
