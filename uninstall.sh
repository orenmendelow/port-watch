#!/bin/bash
set -e

APP_BUNDLE="/Applications/PortWatch.app"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.oren.port-watch.plist"
CLI_TARGET="/usr/local/bin/port-watch"

echo "Uninstalling PortWatch..."

# Stop the app if running
pkill -x PortWatch 2>/dev/null || true

# Unload LaunchAgent
if [ -f "$LAUNCH_AGENT" ]; then
    launchctl unload "$LAUNCH_AGENT" 2>/dev/null || true
    rm "$LAUNCH_AGENT"
    echo "Removed LaunchAgent"
fi

# Remove app bundle
if [ -d "$APP_BUNDLE" ]; then
    rm -rf "$APP_BUNDLE"
    echo "Removed $APP_BUNDLE"
fi

# Remove CLI symlink
if [ -L "$CLI_TARGET" ]; then
    rm "$CLI_TARGET"
    echo "Removed CLI symlink"
fi

# Remove data directory
if [ -d "$HOME/.port-watch" ]; then
    rm -rf "$HOME/.port-watch"
    echo "Removed ~/.port-watch"
fi

echo "Done. PortWatch fully uninstalled."
