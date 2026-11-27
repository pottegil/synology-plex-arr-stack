#!/bin/bash
# Run restart-media-stack.sh on the Synology from your laptop over SSH.
#
#   ./remote-restart-media-stack.sh
#
# Override the defaults with environment variables, e.g.:
#   NAS_USER=myadmin ./remote-restart-media-stack.sh
set -euo pipefail

NAS_HOST="${NAS_HOST:-10.1.1.165}"
NAS_USER="${NAS_USER:-pottegil}"
NAS_REPO="${NAS_REPO:-/volume1/plex/docker/synology-plex-arr-stack}"

echo "==> Updating media stack on ${NAS_USER}@${NAS_HOST}"
# -t gives sudo a terminal so it can ask for your NAS password.
# "sudo bash" works even if the script lost its executable bit on the NAS.
ssh -t "${NAS_USER}@${NAS_HOST}" "sudo bash '${NAS_REPO}/restart-media-stack.sh'"
