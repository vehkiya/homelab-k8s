#!/bin/sh
set -e
echo "📂 Scanning /backups for native db backups..."

LATEST_DB_BACKUP=""
for f in /backups/com.plexapp.plugins.library.db-????-??-??; do
  [ -e "$f" ] && LATEST_DB_BACKUP="$f"
done

if [ -z "$LATEST_DB_BACKUP" ]; then
  echo "❌ No native DB backup files found in /backups!"
  exit 1
fi

DATE_SUFFIX="${LATEST_DB_BACKUP##*-}"
echo "Found latest native backup from $DATE_SUFFIX: $LATEST_DB_BACKUP"

DB_DIR="/config/Library/Application Support/Plex Media Server/Plug-in Support/Databases"
DB_PATH="$DB_DIR/com.plexapp.plugins.library.db"
BLOBS_PATH="$DB_DIR/com.plexapp.plugins.library.blobs.db"
PREFS_PATH="/config/Library/Application Support/Plex Media Server/Preferences.xml"

if [ ! -d "$DB_DIR" ]; then
  echo "❌ DB directory $DB_DIR does not exist. Please start plex at least once."
  exit 1
fi

echo "♻️  Restoring DB to: $DB_PATH..."

# Replace the DB and remove old wal/shm
cp -p "$LATEST_DB_BACKUP" "$DB_PATH"
rm -f "$DB_PATH-wal" "$DB_PATH-shm"

LATEST_BLOBS_BACKUP="/backups/com.plexapp.plugins.library.blobs.db-$DATE_SUFFIX"
if [ -f "$LATEST_BLOBS_BACKUP" ]; then
  echo "♻️  Restoring Blobs DB to: $BLOBS_PATH..."
  cp -p "$LATEST_BLOBS_BACKUP" "$BLOBS_PATH"
  rm -f "$BLOBS_PATH-wal" "$BLOBS_PATH-shm"
fi

if [ -f "/backups/Preferences.xml-$DATE_SUFFIX" ]; then
  echo "♻️  Restoring Preferences.xml..."
  cp -p "/backups/Preferences.xml-$DATE_SUFFIX" "$PREFS_PATH"
fi

echo "👤 Fixing ownership to 1027:100..."
chown 1027:100 "$DB_PATH"
[ -f "$BLOBS_PATH" ] && chown 1027:100 "$BLOBS_PATH"
[ -f "$PREFS_PATH" ] && chown 1027:100 "$PREFS_PATH"

echo "✅ Restore Complete."
