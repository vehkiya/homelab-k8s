#!/bin/sh
PREFS_PATH="/config/Library/Application Support/Plex Media Server/Preferences.xml"
echo "🚀 Backup Sidecar Started (Inotify Mode)."
echo "🔍 Checking for missing Preferences.xml backups on startup..."
LATEST_DB_BACKUP=""
for f in /backups/com.plexapp.plugins.library.db-????-??-??; do
  [ -e "$f" ] && LATEST_DB_BACKUP="$f"
done
if [ -n "$LATEST_DB_BACKUP" ]; then
  DATE_SUFFIX="${LATEST_DB_BACKUP##*-}"
  if [ ! -f "/backups/Preferences.xml-$DATE_SUFFIX" ] && [ -f "$PREFS_PATH" ]; then
    echo "⚙️  Backing up missing Preferences.xml-$DATE_SUFFIX on startup..."
    rsync -a --no-owner --no-group "$PREFS_PATH" "/backups/Preferences.xml-$DATE_SUFFIX"
  fi
fi

echo "👀 Watching /backups for native Plex DB backups..."
inotifywait -m -e close_write -e moved_to -q --format "%f" /backups/ | while read -r filename; do
  if echo "$filename" | grep -qEo '^com\.plexapp\.plugins\.library\.db-[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
    DATE_SUFFIX="${filename##*-}"
    echo "💾 Detected Plex native DB backup: $filename"

    if [ -f "$PREFS_PATH" ]; then
      echo "⚙️  Backing up Preferences.xml as Preferences.xml-$DATE_SUFFIX..."
      rsync -a --no-owner --no-group "$PREFS_PATH" "/backups/Preferences.xml-$DATE_SUFFIX"
      echo "✅ Preferences backup complete!"
    fi

    echo "🧹 Cleaning up old Preferences.xml backups (keeping last 5)..."
    # Shell globs expand alphabetically. Since our suffix is YYYY-MM-DD,
    # alphabetical order matches chronological order (oldest first).
    set -- /backups/Preferences.xml-*
    if [ -e "$1" ]; then
      total=$#
      if [ "$total" -gt 5 ]; then
        limit=$((total - 5))
        for file do
          if [ "$limit" -le 0 ]; then break; fi
          rm -f "$file"
          limit=$((limit - 1))
        done
      fi
    fi
  fi
done
