#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose "$@"
  else
    echo "Docker Compose was not found. Install the docker compose plugin or legacy docker-compose." >&2
    exit 1
  fi
}

if [ ! -f .env ]; then
  cp .env.example .env
fi

set -a
# shellcheck disable=SC1091
. ./.env
set +a

CONFIG_ROOT="${CONFIG_ROOT:-/srv/media-stack/config}"
NZBGET_CONF="${CONFIG_ROOT}/nzbget/nzbget.conf"

mkdir -p "${CONFIG_ROOT}/nzbget"

if [ ! -f "${NZBGET_CONF}" ]; then
  echo "Starting NZBGet once so it creates ${NZBGET_CONF} ..."
  compose up -d nzbget
  for _ in $(seq 1 60); do
    [ -f "${NZBGET_CONF}" ] && break
    sleep 2
  done
fi

if [ ! -f "${NZBGET_CONF}" ]; then
  echo "NZBGet config was not created at ${NZBGET_CONF}. Check: docker logs nzbget" >&2
  exit 1
fi

echo "Stopping NZBGet before editing paths ..."
compose stop nzbget >/dev/null

backup="${NZBGET_CONF}.$(date +%Y%m%d-%H%M%S).bak"
cp -a "${NZBGET_CONF}" "${backup}"

set_or_add() {
  local key="$1"
  local value="$2"
  local file="$3"
  if grep -qE "^${key}=" "${file}"; then
    sed -i "s#^${key}=.*#${key}=${value}#" "${file}"
  else
    printf '%s=%s\n' "${key}" "${value}" >> "${file}"
  fi
}

set_or_add MainDir /data/usenet "${NZBGET_CONF}"
set_or_add DestDir '${MainDir}/completed' "${NZBGET_CONF}"
set_or_add InterDir '${MainDir}/intermediate' "${NZBGET_CONF}"
set_or_add NzbDir '${MainDir}/nzb' "${NZBGET_CONF}"
set_or_add QueueDir '${MainDir}/queue' "${NZBGET_CONF}"
set_or_add TempDir '${MainDir}/tmp' "${NZBGET_CONF}"

set_or_add Category1.Name radarr "${NZBGET_CONF}"
set_or_add Category1.DestDir '${DestDir}/radarr' "${NZBGET_CONF}"
set_or_add Category2.Name sonarr "${NZBGET_CONF}"
set_or_add Category2.DestDir '${DestDir}/sonarr' "${NZBGET_CONF}"
set_or_add Category3.Name lidarr "${NZBGET_CONF}"
set_or_add Category3.DestDir '${DestDir}/lidarr' "${NZBGET_CONF}"

echo "NZBGet path config updated. Backup saved to ${backup}"
compose up -d nzbget
