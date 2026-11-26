#!/bin/bash
# Pull the latest repo changes and container images, then restart the media stack.
# Run on the NAS as root:  sudo ./restart-media-stack.sh
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this as root: sudo $0" >&2
  exit 1
fi

# Always run from the repo folder, wherever the script is called from.
cd "$(dirname "$0")"

echo "==> Pulling repo changes"
git pull

echo "==> Pulling latest container images"
docker compose pull

echo "==> Recreating containers with new images or config"
docker compose up -d

echo "==> Removing old, unused images"
docker image prune -f

echo "==> Current status"
docker compose ps
