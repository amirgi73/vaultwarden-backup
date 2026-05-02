#!/bin/bash
# =============================================================================
# Vaultwarden Backup Script
# Verschlüsseltes Backup → Backblaze B2 (Bucket: lopito)
#
# Voraussetzungen:
#   - sqlite3 installiert (apt install sqlite3)
#   - gpg installiert, public key importiert
#   - rclone konfiguriert (rclone config → remote name: "b2") - WriteOnly API KEY
#   - Docker-Container läuft oder ist gestoppt (beides funktioniert)
#
# Platzhalter anpassen:
#   VW_DATA          → Pfad zum Vaultwarden /data Verzeichnis
#   GPG_FINGERPRINT  → Fingerprint ohne Leerzeichen (gpg --fingerprint)
# =============================================================================

set -euo pipefail

# --- Konfiguration -----------------------------------------------------------
VW_DATA="/home/amir/vaultwarden/vw-data"       # ← ANPASSEN
GPG_FINGERPRINT="EE1A9B8673870A9287E1AE6E404C182F3416A4A8"         # ← ANPASSEN (Leerzeichen entfernen)
GPG_RECIPIENT="0x${GPG_FINGERPRINT}"      # Fingerprint als Recipient (keine E-Mail nötig)
B2_REMOTE="b2"                             # rclone remote name
B2_BUCKET="lopito"
B2_PREFIX="vw"
TMP_DIR="/tmp/vw-backup-$$"               # $$ = PID für Eindeutigkeit
LOG_TAG="vaultwarden-backup"
# -----------------------------------------------------------------------------

DATE=$(date +%Y-%m-%d_%H%M%S)
ARCHIVE_NAME="vw_backup_${DATE}.tar.gz.gpg"
TMPFILE="${TMP_DIR}/${ARCHIVE_NAME}"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | systemd-cat -t "$LOG_TAG" -p info
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_err() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | systemd-cat -t "$LOG_TAG" -p err
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# --- Validierung -------------------------------------------------------------
if [ ! -f "${VW_DATA}/db.sqlite3" ]; then
    log_err "SQLite DB nicht gefunden: ${VW_DATA}/db.sqlite3"
    exit 1
fi

# GPG Fingerprint-Validierung (verhindert Verschlüsselung an falschen Key)
ACTUAL_FP=$(gpg --fingerprint --with-colons "$GPG_RECIPIENT" 2>/dev/null \
    | awk -F: '/^fpr/{print $10; exit}')

if [ -z "$ACTUAL_FP" ]; then
    log_err "GPG public key nicht gefunden für Fingerprint: $GPG_FINGERPRINT"
    exit 1
fi

if [ "$ACTUAL_FP" != "$GPG_FINGERPRINT" ]; then
    log_err "GPG Fingerprint stimmt nicht überein! Erwartet: ${GPG_FINGERPRINT}, Gefunden: ${ACTUAL_FP}"
    exit 1
fi

log "GPG Fingerprint verifiziert: ${ACTUAL_FP}"

if ! rclone listremotes | grep -q "^${B2_REMOTE}:"; then
    log_err "rclone remote '${B2_REMOTE}' nicht konfiguriert"
    exit 1
fi

# --- Backup ------------------------------------------------------------------
mkdir -p "$TMP_DIR"
STAGING="${TMP_DIR}/staging"
mkdir -p "$STAGING"

log "Starte Backup: ${ARCHIVE_NAME}"

# SQLite safe backup (funktioniert auch bei laufendem Container)
log "Sichere SQLite DB..."
sqlite3 "${VW_DATA}/db.sqlite3" ".backup '${STAGING}/db.sqlite3'"

# Optionale Dateien (kein Fehler wenn nicht vorhanden)
for item in attachments config.json rsa_key.pem rsa_key.pub.pem sends; do
    if [ -e "${VW_DATA}/${item}" ]; then
        cp -r "${VW_DATA}/${item}" "${STAGING}/"
        log "  → ${item} gesichert"
    fi
done

# Archivieren + verschlüsseln (pipe: kein unverschlüsseltes Archiv auf Disk)
log "Verschlüssele und archiviere..."
tar -czf - -C "$STAGING" . | \
    gpg \
        --encrypt \
        --recipient "$GPG_RECIPIENT" \
        --batch \
        --compress-level 0 \
        -o "$TMPFILE"

FILESIZE=$(du -sh "$TMPFILE" | cut -f1)
log "Archiv erstellt: ${FILESIZE}"

# --- Upload ------------------------------------------------------------------
log "Lade hoch nach B2: ${B2_REMOTE}:${B2_BUCKET}/${B2_PREFIX}/"
rclone copy \
    "$TMPFILE" \
    "${B2_REMOTE}:${B2_BUCKET}/${B2_PREFIX}/" \
    --no-check-dest \
    --progress \
    --stats-one-line

log "Backup erfolgreich abgeschlossen: ${ARCHIVE_NAME} (${FILESIZE})"
