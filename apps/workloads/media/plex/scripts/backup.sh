#!/bin/sh
PREFS_PATH="/config/Library/Application Support/Plex Media Server/Preferences.xml"
echo "🚀 Backup Sidecar Started (Inotify Mode)."
echo "👀 Watching /backups for native Plex DB backups..."
inotifywait -m -e close_write -q --format "%f" /backups/ | while read -r filename; do
  if echo "$filename" | grep -qEo '^com\.plexapp\.plugins\.library\.db-[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
    DATE_SUFFIX="${filename##*-}"
    echo "💾 Detected Plex native DB backup: $filename"

    if [ -f "$PREFS_PATH" ]; then
      echo "⚙️  Backing up Preferences.xml as Preferences.xml-$DATE_SUFFIX..."
      rsync -a --no-owner --no-group "$PREFS_PATH" "/backups/Preferences.xml-$DATE_SUFFIX"
      echo "✅ Preferences backup complete!"
    fi

    echo "🧹 Cleaning up old Preferences.xml backups (keeping last 5)..."
    ls -dt /backups/Preferences.xml-* 2>/dev/null | tail -n +6 | xargs -r rm -f
  fi
done
