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

case "${1:-status}" in
  up)
    compose up -d
    ;;
  down)
    compose down
    ;;
  restart)
    compose up -d --force-recreate
    ;;
  pull)
    compose pull
    ;;
  logs)
    compose logs -f "${@:2}"
    ;;
  ps|status)
    compose ps
    ;;
  config)
    compose config
    ;;
  *)
    echo "Usage: $0 {up|down|restart|pull|logs|ps|status|config}" >&2
    exit 2
    ;;
esac
