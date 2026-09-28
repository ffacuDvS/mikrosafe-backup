#!/usr/bin/env bash
set -euo pipefail

# ====================================
# Script: mikrosafe.sh
# Project: MikroSafe
# Description: Automated backup system for MikroTik devices
# Author: Facundo Alarcón | @ffacu.dvs
# Repository: https://github.com/ffacuDvS/mikrosafe-backup
# License: MIT
# ====================================

readonly VERSION="1.2.0"

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
LOGO_PATH="$ASSETS_DIR/logo.png"

ENV_FILE="${ENV_FILE:-$DATABASE_DIR/credentials.env}"
DEVICES_FILE="${DEVICES_FILE:-$DATABASE_DIR/mikrosafe-mkts.list}"
EMAILS_FILE="${EMAILS_FILE:-$DATABASE_DIR/emails.list}"

ERROR_LOG="$DATABASE_DIR/error-log.txt"
ACTIVITY_LOG="$DATABASE_DIR/activity-log.txt"

LOCK_FILE="${LOCK_FILE:-$BASE_DIR/.mikrosafe.lock}"

DATE="$(date '+%Y-%m-%d_%H-%M-%S')"
ZIP_FILE="$OUTBOX_DIR/backup_$DATE.zip"

DRY_RUN=0
GROUP_FILTER=""

# ============================
# UI / COLORS
# ============================

USE_COLORS=1
[[ ! -t 1 ]] && USE_COLORS=0

if [[ $USE_COLORS -eq 1 ]]; then
    RESET="\e[0m"; BOLD="\e[1m"
    RED="\e[31m"; GREEN="\e[32m"; CYAN="\e[36m"; YELLOW="\e[33m"
else
    RESET=""; BOLD=""; RED=""; GREEN=""; CYAN=""; YELLOW=""
fi

OK="${GREEN}${BOLD}[ OK ]${RESET}"
ERR="${RED}${BOLD}[FAIL]${RESET}"
INFO="${CYAN}[INFO]${RESET}"
WARN="${YELLOW}${BOLD}[WARN]${RESET}"

log_error() {
    printf "%s | %s\n" "$(date '+%F %T')" "$1" >> "$ERROR_LOG"
}

# ============================
# CLI
# ============================

usage() {
    cat <<EOF
MikroSafe v$VERSION - Automated backup system for MikroTik devices

Usage: $(basename "$0") [options]

Options:
  -g, --group <GROUP>   Only back up devices belonging to <GROUP>
  -n, --dry-run         Show what would be done without connecting to devices
  -v, --version         Print version and exit
  -h, --help            Show this help and exit
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -g|--group)
                GROUP_FILTER="${2:-}"
                [[ -z "$GROUP_FILTER" ]] && { echo "[FATAL] --group requires a value" >&2; exit 1; }
                shift 2
                ;;
            -n|--dry-run)
                DRY_RUN=1
                shift
                ;;
            -v|--version)
                echo "MikroSafe v$VERSION"
                exit 0
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "[FATAL] Unknown option: $1" >&2
                usage >&2
                exit 1
                ;;
        esac
    done
}

# ============================
# ENV LOADING & VALIDATION
# ============================

load_env() {
    if [[ ! -f "$ENV_FILE" ]]; then
        echo "[FATAL] credentials.env not found at $ENV_FILE" >&2
        exit 1
    fi

    # credentials.env holds plaintext passwords; warn loudly if it's readable
    # by anyone other than the owner instead of silently trusting permissions.
    local perms
    perms="$(stat -c '%a' "$ENV_FILE" 2>/dev/null || stat -f '%OLp' "$ENV_FILE" 2>/dev/null || echo "")"
    if [[ -n "$perms" && "$perms" != "600" && "$perms" != "400" ]]; then
        printf "%b\n" "$WARN $ENV_FILE has permissions $perms, expected 600. Run: chmod 600 $ENV_FILE"
    fi

    set -a
    source "$ENV_FILE"
    set +a

    : "${SSH_USER:=admin}"
    : "${FROM_EMAIL:=mikrosafe@localhost}"
    : "${SSH_TIMEOUT:=10}"
    : "${SSH_PORT:=22}"

    PASSWORDS=(${SSH_PASSWORDS:-})
    if [[ ${#PASSWORDS[@]} -eq 0 ]]; then
        echo "[FATAL] SSH_PASSWORDS is empty in $ENV_FILE" >&2
        exit 1
    fi

    if [[ ! -f "$DEVICES_FILE" ]]; then
        echo "[FATAL] Devices list not found at $DEVICES_FILE" >&2
        exit 1
    fi
}

# ============================
# CONCURRENCY GUARD
# ============================

acquire_lock() {
    exec 200>"$LOCK_FILE"
    if ! flock -n 200; then
        echo "[FATAL] Another instance of MikroSafe is already running (lock: $LOCK_FILE)" >&2
        exit 1
    fi
}

# ============================
# FUNCTIONS
# ============================

# Reads NAME:IP:GROUP lines, skipping blank lines and comments (#...),
# and optionally filtering by GROUP_FILTER.
load_devices() {
    DEVICES=()
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        if [[ -n "$GROUP_FILTER" ]]; then
            local line_group="${line##*:}"
            [[ "$line_group" != "$GROUP_FILTER" ]] && continue
        fi

        DEVICES+=("$line")
    done < "$DEVICES_FILE"
}

perform_backups() {
    load_devices
    local total=${#DEVICES[@]}
    local ok=0 fail=0 count=0

    if [[ $total -eq 0 ]]; then
        printf "%b\n" "$WARN No devices matched (group filter: '${GROUP_FILTER:-<none>}')"
        return 0
    fi

    printf "%b\n" "$INFO Starting MikroTik backups (${total} device(s))"

    for device in "${DEVICES[@]}"; do
        IFS=':' read -r NAME IP GROUP <<< "$device"
        FILE="${GROUP}_${NAME}_${DATE}.rsc"
        ((++count))

        printf "%b [%s/%s] %s (%s)... " "$INFO" "$count" "$total" "$NAME" "$IP"

        if [[ $DRY_RUN -eq 1 ]]; then
            printf "\r%-80s\r%b %s (%s) -> would fetch to %s\n" "" "$INFO" "$NAME" "$IP" "$BACKUP_DIR/$FILE"
            ((++ok))
            continue
        fi

        SUCCESS=0
        for PASS in "${PASSWORDS[@]}"; do
            if SSHPASS="$PASS" sshpass -e scp \
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

    BACKUP_OK=$ok
    BACKUP_FAIL=$fail
}

compress_backups() {
    [[ $DRY_RUN -eq 1 ]] && { printf "%b\n" "$INFO [dry-run] Skipping compression"; return 0; }

    cp "$ERROR_LOG" "$BACKUP_DIR" 2>/dev/null || true

    cd "$BACKUP_DIR/.." || return 1
    zip -r "$ZIP_FILE" backups >/dev/null
}

send_email() {
    [[ $DRY_RUN -eq 1 ]] && { printf "%b\n" "$INFO [dry-run] Skipping email delivery"; return 0; }

    local file
    file=$(ls -t "$OUTBOX_DIR"/*.zip 2>/dev/null | head -n1)

    [[ -z "$file" ]] && { log_error "No zip file found to send"; return 1; }
    [[ ! -f "$EMAILS_FILE" ]] && { log_error "Emails list not found at $EMAILS_FILE"; return 1; }

    local subject="✅ MikroSafe – Backup Report"
    if [[ "${BACKUP_FAIL:-0}" -gt 0 ]]; then
        subject="⚠️ MikroSafe – Backup Report (${BACKUP_FAIL} failed)"
    fi

    export VERSION DATE

    mapfile -t MAILS < <(grep -vE '^\s*(#|$)' "$EMAILS_FILE")

    if [[ ${#MAILS[@]} -eq 0 ]]; then
        log_error "Emails list is empty, nothing to send"
        return 1
    fi

    local email
    for email in "${MAILS[@]}"; do
        if ! {
            echo "From: $FROM_EMAIL"
            echo "To: $email"
            echo "Subject: $subject"
            echo "MIME-Version: 1.0"
            echo "Content-Type: multipart/related; boundary=\"MIXED-BOUNDARY\""
            echo
            echo "--MIXED-BOUNDARY"
            echo "Content-Type: text/html; charset=\"utf-8\""
            echo
            sed "s|cid:logo-placeholder|cid:logo|" "$EMAIL_TEMPLATE"
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
        } | msmtp --read-envelope-from -t; then
            log_error "Failed to send email to $email"
        fi
    done
}

cleanup() {
    [[ $DRY_RUN -eq 1 ]] && { printf "%b\n" "$INFO [dry-run] Skipping cleanup"; return 0; }

    ls -tp "$OUTBOX_DIR"/*.zip 2>/dev/null | tail -n +4 | xargs -r rm --
    rm -rf "${BACKUP_DIR:?}"/*
}

main() {
    parse_args "$@"
    acquire_lock
    load_env

    mkdir -p "$BACKUP_DIR" "$OUTBOX_DIR"

    perform_backups
    compress_backups
    send_email
    cleanup

    if [[ $DRY_RUN -eq 0 ]]; then
        echo "$(date '+%F %T') - Backup completed (OK=${BACKUP_OK:-0} FAIL=${BACKUP_FAIL:-0})" >> "$ACTIVITY_LOG"
    fi
}

main "$@"
