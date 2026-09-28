#!/usr/bin/env bash
set -uo pipefail

# ====================================
# Script: deploy_backup_script.sh
# Project: MikroSafe
# Description: One-time deployment of the RouterOS backup script
#              and scheduler to every device in mikrosafe-mkts.list
# Author: Facundo Alarcón | @ffacu.dvs
# Repository: https://github.com/ffacuDvS/mikrosafe-backup
# License: MIT
# ====================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$SCRIPT_DIR"
DATABASE_DIR="$BASE_DIR/database"
ASSETS_DIR="$BASE_DIR/assets"

DEVICES_FILE="$DATABASE_DIR/mikrosafe-mkts.list"
CREDENTIALS_FILE="$DATABASE_DIR/credentials.env"
DEPLOY_SCRIPT="$ASSETS_DIR/mikrosafebackup.rsc"

RESET="\e[0m"
RED="\e[31m"
GREEN="\e[32m"
CYAN="\e[36m"
YELLOW="\e[33m"

if [[ ! -f "$CREDENTIALS_FILE" ]]; then
  echo -e "${RED}[ERROR]${RESET} Missing $CREDENTIALS_FILE"
  exit 1
fi

if [[ ! -f "$DEVICES_FILE" ]]; then
  echo -e "${RED}[ERROR]${RESET} Missing $DEVICES_FILE"
  exit 1
fi

if [[ ! -f "$DEPLOY_SCRIPT" ]]; then
  echo -e "${RED}[ERROR]${RESET} Missing $DEPLOY_SCRIPT"
  exit 1
fi

set -a
source "$CREDENTIALS_FILE"
set +a

PASSWORDS=(${SSH_PASSWORDS:-})

if [[ ${#PASSWORDS[@]} -eq 0 ]]; then
  echo -e "${RED}[ERROR]${RESET} SSH_PASSWORDS is empty in $CREDENTIALS_FILE"
  exit 1
fi

: "${SSH_USER:=admin}"
: "${SSH_TIMEOUT:=10}"
: "${SSH_PORT:=22}"

echo -e "${CYAN}[INFO]${RESET} Starting remote backup activation..."

DEVICES=()
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
  DEVICES+=("$line")
done < "$DEVICES_FILE"

if [[ ${#DEVICES[@]} -eq 0 ]]; then
  echo -e "${YELLOW}[WARN]${RESET} No devices found in $DEVICES_FILE"
  exit 0
fi

FAIL_COUNT=0

for device in "${DEVICES[@]}"; do
  IFS=':' read -r NAME IP GROUP <<< "$device"

  echo -e "${CYAN}[INFO]${RESET} Processing $NAME ($IP)..."

  ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$IP" >/dev/null 2>&1 || true

  SUCCESS=0

  LAST_ERROR=""

  for PASS in "${PASSWORDS[@]}"; do
    SCP_OUTPUT=$(SSHPASS="$PASS" timeout "$SSH_TIMEOUT" sshpass -e scp \
      -P "$SSH_PORT" \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout="$SSH_TIMEOUT" \
      -o HostKeyAlgorithms=+ssh-rsa \
      "$DEPLOY_SCRIPT" \
      "$SSH_USER@$IP:mikrosafebackup.rsc" 2>&1)
    SCP_STATUS=$?

    if [[ $SCP_STATUS -ne 0 ]]; then
      LAST_ERROR="scp failed: $SCP_OUTPUT"
      continue
    fi

    IMPORT_OUTPUT=$(SSHPASS="$PASS" timeout "$SSH_TIMEOUT" sshpass -e ssh -T \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout="$SSH_TIMEOUT" \
      -o HostKeyAlgorithms=+ssh-rsa \
      -o LogLevel=ERROR \
      "$SSH_USER@$IP" 2>&1 <<EOF
/import file-name=mikrosafebackup.rsc
EOF
)
    IMPORT_STATUS=$?

    if [[ $IMPORT_STATUS -ne 0 ]] || echo "$IMPORT_OUTPUT" | grep -qiE "failure|error|invalid"; then
      LAST_ERROR="import failed (exit=$IMPORT_STATUS): $IMPORT_OUTPUT"
      continue
    else
      SUCCESS=1
      break
    fi
  done

  if [[ $SUCCESS -eq 1 ]]; then
    echo -e "${GREEN}[SUCCESS]${RESET} Remote backup enabled for $NAME ($IP)"
  else
    echo -e "${RED}[ERROR]${RESET} Configuration failed on $NAME ($IP)${LAST_ERROR:+ - $LAST_ERROR}"
    ((++FAIL_COUNT))
  fi
done

if [[ $FAIL_COUNT -gt 0 ]]; then
  echo -e "${YELLOW}[WARN]${RESET} $FAIL_COUNT device(s) failed to configure"
  exit 1
fi

exit 0
