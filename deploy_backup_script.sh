#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$SCRIPT_DIR"
DATABASE_DIR="$BASE_DIR/database"

DEVICES_FILE="$DATABASE_DIR/mikrosafe-mkts.list"
CREDENTIALS_FILE="$DATABASE_DIR/credentials.env"

if [[ ! -f "$CREDENTIALS_FILE" ]]; then
  echo "[ERROR] Missing $CREDENTIALS_FILE"
  exit 1
fi

set -a
source "$CREDENTIALS_FILE"
set +a

PASSWORDS=(${SSH_PASSWORDS:-})

if [[ -z "${SSH_USER:-}" ]]; then
  SSH_USER="admin"
fi

if [[ -z "${SSH_TIMEOUT:-}" ]]; then
  SSH_TIMEOUT=10
fi

echo "[INFO] Starting remote backup activation..."

if [[ ! -f "$DEVICES_FILE" ]]; then
  echo "[ERROR] Missing $DEVICES_FILE"
  exit 1
fi

mapfile -t DEVICES < "$DEVICES_FILE"

for device in "${DEVICES[@]}"; do
  NAME=$(echo "$device" | cut -d':' -f1)
  IP=$(echo "$device" | cut -d':' -f2)
  GROUP=$(echo "$device" | cut -d':' -f3)

echo "[INFO] Processing $NAME ($IP)..."

  ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$IP" >/dev/null 2>&1 || true

  SUCCESS=0

  for PASS in "${PASSWORDS[@]}"; do
    timeout "$SSH_TIMEOUT" sshpass -p "$PASS" scp \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout="$SSH_TIMEOUT" \
      -o HostKeyAlgorithms=+ssh-rsa \
      "$BASE_DIR/assets/backup_script.rsc" \
      "$SSH_USER@$IP:backup_script.rsc" >/dev/null 2>&1

    if [[ $? -ne 0 ]]; then
      continue
    fi

    timeout "$SSH_TIMEOUT" sshpass -p "$PASS" ssh \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout="$SSH_TIMEOUT" \
      -o HostKeyAlgorithms=+ssh-rsa \
      "$SSH_USER@$IP" <<EOF >/dev/null 2>&1
/import file-name=backup_script.rsc
EOF

    if [[ $? -eq 0 ]]; then
      SUCCESS=1
      break
    fi
  done

  if [[ $SUCCESS -eq 1 ]]; then
    echo "[SUCCESS] Remote backup enabled for $NAME ($IP)"
  else
    echo "[ERROR] Configuration failed on $NAME ($IP)"
  fi
done
