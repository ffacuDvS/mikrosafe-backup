#!/usr/bin/env bash
set -euo pipefail

# ====================================
# Script: mikrosafe.sh
# Project: MikroSafe
# Description: Automated backup system for MikroTik devices
# Author: Facundo Alarcón | @ffacu.dvs
# License: MIT
# ====================================

readonly VERSION="1.1.0"

# ============================
# PATHS & CONFIG
# ============================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BASE_DIR="${BASE_DIR:-$SCRIPT_DIR}"
DATABASE_DIR="${DATABASE_DIR:-$BASE_DIR/database}"
BACKUP_DIR="${BACKUP_DIR:-$BASE_DIR/backups}"
OUTBOX_DIR="${OUTBOX_DIR:-$BASE_DIR/outbox}"
ASSETS_DIR="${ASSETS_DIR:-$BASE_DIR/assets}"
EMAIL_TEMPLATE="$ASSETS_DIR/email_template.html"

ENV_FILE="${ENV_FILE:-$DATABASE_DIR/credentials.env}"
DEVICES_FILE="${DEVICES_FILE:-$DATABASE_DIR/mikrosafe-mkts.list}"
EMAILS_FILE="${EMAILS_FILE:-$DATABASE_DIR/emails.list}"

ERROR_LOG="$DATABASE_DIR/error-log.txt"
ACTIVITY_LOG="$DATABASE_DIR/activity-log.txt"

DATE="$(date '+%Y-%m-%d_%H-%M-%S')"
ZIP_FILE="$OUTBOX_DIR/backup_$DATE.zip"

mkdir -p "$BACKUP_DIR" "$OUTBOX_DIR"

# ============================
# ENV LOADING
# ============================

if [[ ! -f "$ENV_FILE" ]]; then
    echo "[FATAL] credentials.env not found"
    exit 1
fi

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

: "${SSH_USER:=admin}"
: "${FROM_EMAIL:=mikrosafe@localhost}"
: "${SSH_TIMEOUT:=10}"
: "${SSH_PORT:=22}"

PASSWORDS=(${SSH_PASSWORDS:-})

# ============================
# UI / COLORS
# ============================

USE_COLORS=1
[[ ! -t 1 ]] && USE_COLORS=0

if [[ $USE_COLORS -eq 1 ]]; then
    RESET="\e[0m"; BOLD="\e[1m"
    RED="\e[31m"; GREEN="\e[32m"; CYAN="\e[36m"
else
    RESET=""; BOLD=""; RED=""; GREEN=""; CYAN=""
fi

OK="${GREEN}${BOLD}[ OK ]${RESET}"
ERR="${RED}${BOLD}[FAIL]${RESET}"
INFO="${CYAN}[INFO]${RESET}"

log_error() {
    printf "%s | %s\n" "$(date '+%F %T')" "$1" >> "$ERROR_LOG"
}

# ============================
# FUNCTIONS
# ============================

perform_backups() {
    mapfile -t DEVICES < "$DEVICES_FILE"
    local total=${#DEVICES[@]}
    local ok=0 fail=0 count=0

    printf "%b\n" "$INFO Starting MikroTik backups"

    for device in "${DEVICES[@]}"; do
        IFS=':' read -r NAME IP GROUP <<< "$device"
        FILE="${GROUP}_${NAME}_${DATE}.rsc"
        ((++count))

        printf "%b [%s/%s] %s (%s)... " "$INFO" "$count" "$total" "$NAME" "$IP"

        SUCCESS=0
        for PASS in "${PASSWORDS[@]}"; do
            if sshpass -p "$PASS" scp \
                -P "$SSH_PORT" \
                -o ConnectTimeout="$SSH_TIMEOUT" \
                -o StrictHostKeyChecking=accept-new \
                "$SSH_USER@$IP:/mikrosafebackup.rsc" "$BACKUP_DIR/$FILE" 2>/dev/null; then
                SUCCESS=1
                break
            fi
        done

        if [[ $SUCCESS -eq 1 ]]; then
            printf "\r%-80s\r%b %s (%s)\n" "" "$OK" "$NAME" "$IP"
            ((++ok))
        else
            printf "\r%-80s\r%b %s (%s)\n" "" "$ERR" "$NAME" "$IP"
            ((++fail))
            log_error "$NAME ($IP) backup failed"
        fi
    done

    printf "%b\n" "\n$INFO Summary: OK=$ok FAIL=$fail TOTAL=$total"
}

compress_backups() {
    cp "$ERROR_LOG" "$BACKUP_DIR" 2>/dev/null || true

    cd "$BACKUP_DIR/.." || return 1
    zip -r "$ZIP_FILE" backups >/dev/null
}


send_email() {
    local EMAILS="$DATABASE_DIR/emails.list"
    local HTML_TEMPLATE="$ASSETS_DIR/email_template.html"
    local LOGO_PATH="$ASSETS_DIR/logo.png"
    local file=$(ls -t "$OUTBOX_DIR"/*.zip 2>/dev/null | head -n1)

    export VERSION DATE

    [ -z "$file" ] && return 1

    mapfile -t MAILS < "$EMAILS"

    for email in "${MAILS[@]}"; do
        {
            echo "From: $FROM_EMAIL"
            echo "To: $email"
            echo "Subject: ✅ MikroSafe – Backup Report"
            echo "MIME-Version: 1.0"
            echo "Content-Type: multipart/related; boundary=\"MIXED-BOUNDARY\""
            echo
            echo "--MIXED-BOUNDARY"
            echo "Content-Type: text/html; charset=\"utf-8\""
            echo
            sed "s|cid:logo-placeholder|cid:logo|" "$HTML_TEMPLATE"
            echo
            echo "--MIXED-BOUNDARY"
            echo "Content-Type: image/png"
            echo "Content-ID: <logo>"
            echo "Content-Transfer-Encoding: base64"
            echo
            base64 "$LOGO_PATH"
            echo
            echo "--MIXED-BOUNDARY"
            echo "Content-Type: application/zip"
            echo "Content-Disposition: attachment; filename=\"$(basename "$file")\""
            echo "Content-Transfer-Encoding: base64"
            echo
            base64 "$file"
            echo
            echo "--MIXED-BOUNDARY--"
        } | msmtp --read-envelope-from -t
    done
}

cleanup() {
    ls -tp "$OUTBOX_DIR"/*.zip 2>/dev/null | tail -n +4 | xargs -r rm --
    rm -rf "${BACKUP_DIR:?}"/*
}

main() {
    perform_backups
    compress_backups
    send_email
    cleanup
    echo "$(date '+%F %T') - Backup completed" >> "$ACTIVITY_LOG"
}

main
