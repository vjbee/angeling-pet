#!/bin/bash
# Remove Angeling: app, login item, Claude Code hooks and the limit status line wrapper. Keeps ~/.claude/angeling-pet
# unless --purge is given.
set -euo pipefail
RUNTIME="$HOME/.claude/angeling-pet"
SETTINGS="$HOME/.claude/settings.json"
PLIST="$HOME/Library/LaunchAgents/local.angeling.pet.plist"

pkill -x Angeling 2>/dev/null || true
launchctl bootout "gui/$(id -u)/local.angeling.pet" 2>/dev/null || true
rm -f "$PLIST"
rm -rf "$HOME/Applications/Angeling.app"

if [ -f "$SETTINGS" ] && command -v jq >/dev/null; then
  cp "$SETTINGS" "$SETTINGS.angeling-backup"
  jq '
    if .hooks then
      .hooks |= (with_entries(.value |= map(select(([.hooks[]?.command] | map(tostring | contains("angeling-pet/hook.sh")) | any) | not)))
                 | with_entries(select(.value | length > 0)))
    else . end' "$SETTINGS.angeling-backup" > "$SETTINGS.tmp" && jq -e . "$SETTINGS.tmp" >/dev/null && mv "$SETTINGS.tmp" "$SETTINGS"
  echo "Removed hooks from $SETTINGS (backup: $SETTINGS.angeling-backup)"
  # Put back the user's own status line if Angeling's limit wrapper (menu 📊) still holds it.
  ORIG=null
  [ -s "$RUNTIME/statusline-orig.json" ] && ORIG=$(cat "$RUNTIME/statusline-orig.json")
  if jq --argjson orig "$ORIG" '
      if ((.statusLine.command? // "") | tostring | contains("angeling-pet/statusline.sh")) then
        (if $orig == null then del(.statusLine) else .statusLine = $orig end)
      else . end' "$SETTINGS" > "$SETTINGS.tmp" 2>/dev/null && jq -e . "$SETTINGS.tmp" >/dev/null; then
    mv "$SETTINGS.tmp" "$SETTINGS"
  else
    rm -f "$SETTINGS.tmp"
  fi
  rm -f "$RUNTIME/statusline-orig.json" "$RUNTIME/statusline-orig.cmd" "$RUNTIME/statusline.sh" "$RUNTIME/limits.json"
fi

if [ "${1:-}" = "--purge" ]; then
  rm -rf "$RUNTIME"
  defaults delete local.angeling.pet 2>/dev/null || true
  echo "Removed $RUNTIME and preferences"
fi
echo "Angeling uninstalled."
