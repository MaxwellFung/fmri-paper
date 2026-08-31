#!/usr/bin/env bash
set -euo pipefail

# Lightweight GCP startup script for every VM boot.
# The one-time installer is scripts/gcp_jupyter_startup.sh.
JUPYTER_USER="${JUPYTER_USER:-maxwellfung}"
JUPYTER_PORT="${JUPYTER_PORT:-8888}"
SERVICE_NAME="${SERVICE_NAME:-jupyter-fmri.service}"
TOKEN_FILE="/home/${JUPYTER_USER}/.jupyter_fmri_token"

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"
systemctl restart "${SERVICE_NAME}"

EXTERNAL_IP="$(curl -fsS -H 'Metadata-Flavor: Google' \
  http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip || true)"

echo "JupyterLab service status:"
systemctl --no-pager --full status "${SERVICE_NAME}" || true
echo

if [ -s "${TOKEN_FILE}" ]; then
  JUPYTER_TOKEN="$(cat "${TOKEN_FILE}")"
  echo "Jupyter token: ${JUPYTER_TOKEN}"
  if [ -n "${EXTERNAL_IP}" ]; then
    echo "Jupyter URL: http://${EXTERNAL_IP}:${JUPYTER_PORT}/lab?token=${JUPYTER_TOKEN}"
  else
    echo "Jupyter URL: http://<EXTERNAL_IP>:${JUPYTER_PORT}/lab?token=${JUPYTER_TOKEN}"
  fi
else
  echo "Missing token file: ${TOKEN_FILE}"
fi
