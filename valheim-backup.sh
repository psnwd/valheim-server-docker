#!/usr/bin/env bash
# =============================================================================
#  valheim-backup.sh — Backup Valheim world to UploadThing
#  Runs every hour via cron. Zips the world save files and uploads via API.
#
#  SETUP:
#    1. Set your UploadThing API key below (or export UPLOADTHING_API_KEY)
#    2. chmod +x valheim-backup.sh
#    3. Add to cron: 0 * * * * /path/to/valheim-backup.sh >> /var/log/valheim-backup.log 2>&1
# =============================================================================

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
UPLOADTHING_API_KEY="${UPLOADTHING_API_KEY:-"sk_live_REPLACE_ME"}"
WORLD_NAME="MidgardWorld"
BACKUP_DIR="/tmp/valheim_backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ARCHIVE_NAME="valheim_${WORLD_NAME}_${TIMESTAMP}.tar.gz"
ARCHIVE_PATH="${BACKUP_DIR}/${ARCHIVE_NAME}"

# World files live inside the Docker named volume
# Docker mounts it at this path on the host:
WORLDS_PATH="/var/lib/docker/volumes/midgard_valheim_config/_data/worlds_local"

# ── Colours for log output ────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[$(date '+%H:%M:%S')] ✔ $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠ $1${NC}"; }
fail() { echo -e "${RED}[$(date '+%H:%M:%S')] ✘ $1${NC}"; exit 1; }

# ── Pre-flight checks ─────────────────────────────────────────────────────────
command -v curl >/dev/null 2>&1 || fail "curl is not installed"
command -v jq   >/dev/null 2>&1 || fail "jq is not installed (sudo apt install jq)"
command -v tar  >/dev/null 2>&1 || fail "tar is not installed"

[[ "$UPLOADTHING_API_KEY" == "sk_live_REPLACE_ME" ]] && \
  fail "Set your UPLOADTHING_API_KEY in this script or as an env var"

[[ -d "$WORLDS_PATH" ]] || \
  fail "Worlds path not found: $WORLDS_PATH — check Docker volume mount"

mkdir -p "$BACKUP_DIR"

# ── Step 1: Create compressed archive ────────────────────────────────────────
log "Creating archive: ${ARCHIVE_NAME}"
tar -czf "$ARCHIVE_PATH" -C "$WORLDS_PATH" .
FILE_SIZE=$(stat -c%s "$ARCHIVE_PATH")
log "Archive ready — $(numfmt --to=iec $FILE_SIZE)"

# ── Step 2: Request a presigned upload URL from UploadThing ──────────────────
log "Requesting presigned URL from UploadThing..."

PRESIGN_RESPONSE=$(curl -sf -X POST "https://api.uploadthing.com/v6/uploadFiles" \
  -H "Content-Type: application/json" \
  -H "X-Uploadthing-Api-Key: ${UPLOADTHING_API_KEY}" \
  -d "{
    \"files\": [{
      \"name\": \"${ARCHIVE_NAME}\",
      \"size\": ${FILE_SIZE},
      \"type\": \"application/gzip\"
    }],
    \"acl\": \"private\",
    \"contentDisposition\": \"attachment\"
  }") || fail "Failed to get presigned URL from UploadThing"

# Parse the presigned URL and fields from response
UPLOAD_URL=$(echo "$PRESIGN_RESPONSE" | jq -r '.data[0].url // empty')
FILE_KEY=$(echo  "$PRESIGN_RESPONSE" | jq -r '.data[0].key // empty')

[[ -z "$UPLOAD_URL" ]] && fail "Could not parse upload URL. Response: $PRESIGN_RESPONSE"
log "Got presigned URL (key: ${FILE_KEY})"

# ── Step 3: Upload the archive via PUT ────────────────────────────────────────
log "Uploading to UploadThing..."

# Build multipart fields from presigned response
FIELDS=$(echo "$PRESIGN_RESPONSE" | jq -r '.data[0].fields | to_entries[] | "-F \"\(.key)=\(.value)\""' 2>/dev/null || echo "")

HTTP_STATUS=$(eval curl -sf -o /dev/null -w "%{http_code}" \
  -X POST "$UPLOAD_URL" \
  $FIELDS \
  -F "file=@${ARCHIVE_PATH};type=application/gzip")

if [[ "$HTTP_STATUS" == "204" || "$HTTP_STATUS" == "200" || "$HTTP_STATUS" == "201" ]]; then
  log "Upload succeeded (HTTP ${HTTP_STATUS})"
else
  # Fallback: try direct PUT (some UploadThing versions use PUT to presigned URL)
  warn "POST returned ${HTTP_STATUS}, trying direct PUT..."
  PUT_URL=$(echo "$PRESIGN_RESPONSE" | jq -r '.data[0].url // empty')
  HTTP_STATUS=$(curl -sf -o /dev/null -w "%{http_code}" \
    -X PUT "$PUT_URL" \
    -H "Content-Type: application/gzip" \
    --data-binary "@${ARCHIVE_PATH}")
  [[ "$HTTP_STATUS" == "200" || "$HTTP_STATUS" == "204" ]] || \
    fail "Upload failed with HTTP ${HTTP_STATUS}"
  log "Upload succeeded via PUT (HTTP ${HTTP_STATUS})"
fi

# ── Step 4: Cleanup old local backups (keep last 3) ──────────────────────────
log "Cleaning up old local backups..."
ls -t "${BACKUP_DIR}"/valheim_*.tar.gz 2>/dev/null | tail -n +4 | xargs -r rm --
log "Cleanup done"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
log "🛡  Backup complete: ${ARCHIVE_NAME}"
log "📁  File key on UploadThing: ${FILE_KEY}"
echo ""
