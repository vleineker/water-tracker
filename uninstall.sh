#!/bin/bash
set -euo pipefail

APP_NAME="Water Tracker"
BUNDLE_ID="com.vleineker.gota"
INSTALL_DIR="$HOME/Applications/$APP_NAME.app"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"

echo "==> Desregistrando login item"
if [ -d "$INSTALL_DIR" ]; then
  "$INSTALL_DIR/Contents/MacOS/$APP_NAME" --unregister-login || true
fi

echo "==> Removendo LaunchAgent de fallback (se existir)"
if [ -f "$LAUNCH_AGENT" ]; then
  launchctl unload "$LAUNCH_AGENT" 2>/dev/null || true
  rm -f "$LAUNCH_AGENT"
fi

echo "==> Encerrando processo"
pkill -x "$APP_NAME" || true

echo "==> Removendo app"
rm -rf "$INSTALL_DIR"

echo "==> Removendo preferências (defaults)"
defaults delete "$BUNDLE_ID" 2>/dev/null || true

echo "==> Water Tracker desinstalado."
