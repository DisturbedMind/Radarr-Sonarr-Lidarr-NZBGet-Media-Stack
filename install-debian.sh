#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root: sudo bash install-debian.sh" >&2
  exit 1
fi

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST="${DEST:-/opt/arr-media-stack}"

compose_available() {
  docker compose version >/dev/null 2>&1 || command -v docker-compose >/dev/null 2>&1
}

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is not installed. Installing Debian packages docker.io and docker-compose ..."
  apt-get update
  apt-get install -y docker.io docker-compose
  systemctl enable --now docker
fi

if ! compose_available; then
  echo "Docker exists, but Compose was not found. Installing Debian docker-compose package ..."
  apt-get update
  apt-get install -y docker-compose
fi

missing_packages=""
command -v mount.cifs >/dev/null 2>&1 || missing_packages="${missing_packages} cifs-utils"
command -v curl >/dev/null 2>&1 || missing_packages="${missing_packages} curl"
if [ -n "$missing_packages" ]; then
  echo "Installing required Debian packages:${missing_packages}"
  apt-get update
  apt-get install -y $missing_packages
fi

install -d -m 0755 "${DEST}"

if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete \
    --exclude '.env' \
    --exclude 'config' \
    --exclude 'data' \
    --exclude 'downloads' \
    "${SRC_DIR}/" "${DEST}/"
else
  cp -a "${SRC_DIR}/." "${DEST}/"
fi

cd "${DEST}"

if [ ! -f .env ]; then
  cp .env.example .env
fi

media_uid="${MEDIA_UID:-${SUDO_UID:-1000}}"
media_gid="${MEDIA_GID:-${SUDO_GID:-1000}}"

sed -i "s/^PUID=.*/PUID=${media_uid}/" .env
sed -i "s/^PGID=.*/PGID=${media_gid}/" .env

if grep -q '^NZBGET_PASS=change-this-password$' .env; then
  if command -v openssl >/dev/null 2>&1; then
    pass="$(openssl rand -base64 24 | tr -d '=+/' | cut -c1-24)"
  else
    pass="change-this-password-now"
  fi
  sed -i "s/^NZBGET_PASS=.*/NZBGET_PASS=${pass}/" .env
fi

set -a
# shellcheck disable=SC1091
. ./.env
set +a

is_mounted() {
  local target="$1"
  if command -v findmnt >/dev/null 2>&1; then
    findmnt -rn --target "$target" >/dev/null 2>&1
  else
    grep -qs " $target " /proc/mounts
  fi
}

setup_smb_mount() {
  [ "${SMB_MOUNT_SHARES:-true}" = "true" ] || return 0

  if [ "${SMB_USERNAME:-CHANGE_ME}" = "CHANGE_ME" ] || [ "${SMB_PASSWORD:-CHANGE_ME}" = "CHANGE_ME" ]; then
    cat >&2 <<EOF
SMB credentials are not configured.

Edit ${DEST}/.env and set:
  SMB_USERNAME=your_windows_user
  SMB_PASSWORD=your_windows_password

The stack will not start until ${SMB_SOURCE:-//192.168.137.110/cinema} is mounted.
This prevents Arr from writing media into an empty local folder.
EOF
    exit 1
  fi

  install -d -m 0755 "${SMB_MOUNT:-/mnt/cinema}"
  install -d -m 0700 "$(dirname "${SMB_CREDENTIALS_FILE:-/etc/samba/credentials/cinema}")"
  cat > "${SMB_CREDENTIALS_FILE:-/etc/samba/credentials/cinema}" <<EOF
username=${SMB_USERNAME}
password=${SMB_PASSWORD}
domain=${SMB_DOMAIN:-WORKGROUP}
EOF
  chmod 600 "${SMB_CREDENTIALS_FILE:-/etc/samba/credentials/cinema}"

  local fstab_line
  fstab_line="${SMB_SOURCE:-//192.168.137.110/cinema} ${SMB_MOUNT:-/mnt/cinema} cifs credentials=${SMB_CREDENTIALS_FILE:-/etc/samba/credentials/cinema},uid=${PUID},gid=${PGID},dir_mode=0775,file_mode=0664,vers=${SMB_VERSION:-3.0},noperm,nofail,x-systemd.automount,_netdev 0 0"

  if ! grep -Fqs "${SMB_SOURCE:-//192.168.137.110/cinema} ${SMB_MOUNT:-/mnt/cinema} " /etc/fstab; then
    printf '%s\n' "$fstab_line" >> /etc/fstab
  fi

  systemctl daemon-reload || true
  mount "${SMB_MOUNT:-/mnt/cinema}" || mount -a

  if ! is_mounted "${SMB_MOUNT:-/mnt/cinema}"; then
    echo "Failed to mount ${SMB_SOURCE:-//192.168.137.110/cinema} at ${SMB_MOUNT:-/mnt/cinema}. Aborting before containers start." >&2
    exit 1
  fi
}

setup_smb_mount

mkdir -p \
  "${CONFIG_ROOT}/radarr" \
  "${CONFIG_ROOT}/sonarr" \
  "${CONFIG_ROOT}/lidarr" \
  "${CONFIG_ROOT}/nzbget" \
  "${CONFIG_ROOT}/caddy/data" \
  "${CONFIG_ROOT}/caddy/config" \
  "${DOWNLOAD_ROOT}/intermediate" \
  "${DOWNLOAD_ROOT}/queue" \
  "${DOWNLOAD_ROOT}/tmp" \
  "${DOWNLOAD_ROOT}/nzb" \
  "${DOWNLOAD_ROOT}/completed/radarr" \
  "${DOWNLOAD_ROOT}/completed/sonarr" \
  "${DOWNLOAD_ROOT}/completed/lidarr" \
  "${MOVIES_ROOT}" \
  "${SERIES_ROOT}" \
  "${MUSIC_ROOT}"

for media_root in "${MOVIES_ROOT}" "${SERIES_ROOT}" "${MUSIC_ROOT}"; do
  if [ "${SMB_MOUNT_SHARES:-true}" = "true" ] && ! is_mounted "$media_root"; then
    echo "${media_root} is not on a mounted filesystem. Aborting before containers start." >&2
    exit 1
  fi
done

chown -R "${PUID}:${PGID}" "${CONFIG_ROOT}" "${DOWNLOAD_ROOT}"
find "${CONFIG_ROOT}" "${DOWNLOAD_ROOT}" -type d -exec chmod 775 {} +
find "${CONFIG_ROOT}" "${DOWNLOAD_ROOT}" -type f -exec chmod 664 {} +

chmod +x scripts/*.sh

echo "Starting stack from ${DEST} ..."
scripts/arrctl.sh up
scripts/bootstrap-nzbget-paths.sh

cat <<EOF

Arr media stack installed at ${DEST}

Edit hostnames/passwords:
  nano ${DEST}/.env

Control commands:
  cd ${DEST}
  scripts/arrctl.sh status
  scripts/arrctl.sh logs
  scripts/arrctl.sh restart

Reverse proxy hostnames currently configured:
  http://${RADARR_HOST}
  http://${SONARR_HOST}
  http://${LIDARR_HOST}
  http://${NZBGET_HOST}
  http://${EMBY_STREAM_HOST}
  http://${EMBY_MAIN_HOST}

Windows media mount:
  ${SMB_SOURCE} -> ${SMB_MOUNT}

Point those DNS names to this Debian proxy server IP.
Run validation after DNS is set:
  cd ${DEST}
  scripts/validate-stack.sh
EOF
