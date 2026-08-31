#!/usr/bin/env bash
set -euo pipefail

# GCP startup script for the fMRI notebook VM.
# Edit these three values if your VM username or paths differ.
JUPYTER_USER="${JUPYTER_USER:-maxwellfung}"
PROJECT_DIR="${PROJECT_DIR:-/home/${JUPYTER_USER}/brain-project}"
REPO_URL="${REPO_URL:-https://github.com/MaxwellFung/fmri-paper.git}"
JUPYTER_PORT="${JUPYTER_PORT:-8888}"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y git python3-venv python3-pip

if ! id "${JUPYTER_USER}" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "${JUPYTER_USER}"
fi

install -d -o "${JUPYTER_USER}" -g "${JUPYTER_USER}" "$(dirname "${PROJECT_DIR}")"

if [ ! -d "${PROJECT_DIR}/.git" ]; then
  sudo -u "${JUPYTER_USER}" git clone "${REPO_URL}" "${PROJECT_DIR}"
else
  sudo -u "${JUPYTER_USER}" git -C "${PROJECT_DIR}" pull --ff-only
fi

VENV_DIR="${PROJECT_DIR}/.venv"
if [ ! -d "${VENV_DIR}" ]; then
  sudo -u "${JUPYTER_USER}" python3 -m venv --system-site-packages "${VENV_DIR}"
fi

sudo -u "${JUPYTER_USER}" "${VENV_DIR}/bin/python" -m pip install --upgrade pip
sudo -u "${JUPYTER_USER}" "${VENV_DIR}/bin/python" -m pip install \
  jupyterlab ipykernel \
  numpy pandas scipy matplotlib tqdm h5py scikit-image \
  diffusers accelerate transformers safetensors einops

sudo -u "${JUPYTER_USER}" "${VENV_DIR}/bin/python" -m ipykernel install \
  --user \
  --name fmri-paper \
  --display-name "fmri-paper"

TOKEN_FILE="/home/${JUPYTER_USER}/.jupyter_fmri_token"
if [ ! -s "${TOKEN_FILE}" ]; then
  openssl rand -hex 24 > "${TOKEN_FILE}"
  chown "${JUPYTER_USER}:${JUPYTER_USER}" "${TOKEN_FILE}"
  chmod 600 "${TOKEN_FILE}"
fi
JUPYTER_TOKEN="$(cat "${TOKEN_FILE}")"

cat >/etc/systemd/system/jupyter-fmri.service <<EOF
[Unit]
Description=JupyterLab for fMRI notebooks
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${JUPYTER_USER}
WorkingDirectory=${PROJECT_DIR}
Environment=PATH=${VENV_DIR}/bin:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=${VENV_DIR}/bin/jupyter lab \\
  --ip=0.0.0.0 \\
  --port=${JUPYTER_PORT} \\
  --no-browser \\
  --notebook-dir=${PROJECT_DIR} \\
  --ServerApp.token=${JUPYTER_TOKEN} \\
  --ServerApp.password='' \\
  --ServerApp.allow_remote_access=True
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable jupyter-fmri.service
systemctl restart jupyter-fmri.service

EXTERNAL_IP="$(curl -fsS -H 'Metadata-Flavor: Google' \
  http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip || true)"

echo "JupyterLab service status:"
systemctl --no-pager --full status jupyter-fmri.service || true
echo
echo "Jupyter token: ${JUPYTER_TOKEN}"
if [ -n "${EXTERNAL_IP}" ]; then
  echo "Jupyter URL: http://${EXTERNAL_IP}:${JUPYTER_PORT}/lab?token=${JUPYTER_TOKEN}"
else
  echo "Jupyter URL: http://<EXTERNAL_IP>:${JUPYTER_PORT}/lab?token=${JUPYTER_TOKEN}"
fi
