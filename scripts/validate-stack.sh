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

is_mounted() {
  local target="$1"
  if command -v findmnt >/dev/null 2>&1; then
    findmnt -rn --target "$target" >/dev/null 2>&1
  else
    grep -qs " $target " /proc/mounts
  fi
}

if [ ! -f .env ]; then
  echo ".env is missing. Copy .env.example to .env first." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
. ./.env
set +a

echo "Checking SMB media mount ..."
if [ "${SMB_MOUNT_SHARES:-true}" = "true" ]; then
  is_mounted "${SMB_MOUNT:-/mnt/cinema}" || {
    echo "${SMB_MOUNT:-/mnt/cinema} is not mounted. Stop here before starting imports." >&2
    exit 1
  }
fi

for media_root in "${MOVIES_ROOT}" "${SERIES_ROOT}" "${MUSIC_ROOT}"; do
  test -d "$media_root" || {
    echo "${media_root} does not exist." >&2
    exit 1
  }
  echo "  ${media_root}: OK"
done

echo "Checking compose syntax ..."
compose config >/dev/null

echo "Checking containers ..."
compose ps

echo "Checking NZBGet download paths inside containers ..."
for service in radarr sonarr lidarr nzbget; do
  compose exec -T "$service" sh -c '
    test -d /data/usenet/completed/radarr &&
    test -d /data/usenet/completed/sonarr &&
    test -d /data/usenet/completed/lidarr
  '
  echo "  ${service}: OK"
done

echo "Checking Arr media library paths ..."
compose exec -T radarr sh -c 'test -d /data/media/movies'
echo "  radarr movies: OK"
compose exec -T sonarr sh -c 'test -d /data/media/series'
echo "  sonarr series: OK"
compose exec -T lidarr sh -c 'test -d /data/media/music'
echo "  lidarr music: OK"

echo "Checking reverse proxy host routes ..."
for item in \
  "${RADARR_HOST}:radarr" \
  "${SONARR_HOST}:sonarr" \
  "${LIDARR_HOST}:lidarr" \
  "${NZBGET_HOST}:nzbget" \
  "${EMBY_STREAM_HOST}:emby-stream" \
  "${EMBY_MAIN_HOST}:emby-main"; do
  host="${item%%:*}"
  name="${item##*:}"
  code="$(curl -sS -o /dev/null -w '%{http_code}' -H "Host: ${host}" "http://127.0.0.1:${CADDY_HTTP_PORT:-80}/" || true)"
  case "$code" in
    200|301|302|401)
      echo "  ${name} via ${host}: HTTP ${code}"
      ;;
    *)
      echo "  ${name} via ${host}: unexpected HTTP ${code}" >&2
      exit 1
      ;;
  esac
done

cat <<EOF

Validation finished.

Arr download client settings:
  Host: nzbget
  Port: 6789
  SSL: off
  URL Base: blank
  Username: ${NZBGET_USER:-nzbget}
  Password: from .env
  Categories: radarr, sonarr, lidarr

Root folders:
  Radarr: /data/media/movies
  Sonarr: /data/media/series
  Lidarr: /data/media/music

External Emby upstreams:
  ${EMBY_STREAM_HOST} -> ${EMBY_STREAM_UPSTREAM}
  ${EMBY_MAIN_HOST} -> ${EMBY_MAIN_UPSTREAM}
EOF
