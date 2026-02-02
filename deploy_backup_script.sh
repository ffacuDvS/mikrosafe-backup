#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$SCRIPT_DIR"
DATABASE_DIR="$BASE_DIR/database"

DEVICES_FILE="$DATABASE_DIR/mikrosafe-mkts.list"
CREDENTIALS_FILE="$DATABASE_DIR/credentials.env"

if [[ ! -f "$CREDENTIALS_FILE" ]]; then
  echo -e "${RED}[ERROR]${RESET} Missing $CREDENTIALS_FILE"
  exit 1
fi

RESET="\e[0m"
RED="\e[31m"
GREEN="\e[32m"
CYAN="\e[36m"

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

echo -e "${CYAN}[INFO]${RESET} Starting remote backup activation..."

if [[ ! -f "$DEVICES_FILE" ]]; then
  echo -e "${RED}[ERROR]${RESET} Missing $DEVICES_FILE"
  exit 1
fi

mapfile -t DEVICES < "$DEVICES_FILE"

for device in "${DEVICES[@]}"; do
  NAME=$(echo "$device" | cut -d':' -f1)
  IP=$(echo "$device" | cut -d':' -f2)

echo -e "${CYAN}[INFO]${RESET} Processing $NAME ($IP)..."

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

    IMPORT_OUTPUT=$(timeout "$SSH_TIMEOUT" sshpass -p "$PASS" ssh -T \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout="$SSH_TIMEOUT" \
      -o HostKeyAlgorithms=+ssh-rsa \
      -o LogLevel=ERROR \
      "$SSH_USER@$IP" <<EOF
/import file-name=backup_script.rsc
EOF
)

    if echo "$IMPORT_OUTPUT" | grep -qiE "failure|error|invalid"; then
      continue
    else
      SUCCESS=1
      break
    fi
  done

  if [[ $SUCCESS -eq 1 ]]; then
    echo -e "${GREEN}[SUCCESS]${RESET} Remote backup enabled for $NAME ($IP)"
  else
    echo -e "${RED}[ERROR]${RESET} Configuration failed on $NAME ($IP)"
  fi
done
