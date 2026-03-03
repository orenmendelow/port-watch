#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="PortWatch"
INSTALL_DIR="$HOME/Applications"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.oren.port-watch.plist"
CLI_TARGET="/usr/local/bin/port-watch"

echo "Building PortWatch..."
cd "$SCRIPT_DIR"
swift build -c release 2>&1

# Create .app bundle
APP_BUNDLE="$INSTALL_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"

mkdir -p "$MACOS_DIR"

# Copy binary
cp ".build/release/$APP_NAME" "$MACOS_DIR/$APP_NAME"

# Create Info.plist
cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>PortWatch</string>
    <key>CFBundleIdentifier</key>
    <string>com.oren.port-watch</string>
    <key>CFBundleName</key>
    <string>PortWatch</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

echo "Installed app to $APP_BUNDLE"

# Install CLI
if [ -d "/usr/local/bin" ]; then
    ln -sf "$SCRIPT_DIR/scripts/port-watch" "$CLI_TARGET"
    echo "CLI installed to $CLI_TARGET"
else
    echo "Warning: /usr/local/bin does not exist. Skipping CLI symlink."
    echo "  You can manually symlink: ln -s $SCRIPT_DIR/scripts/port-watch /usr/local/bin/port-watch"
fi

# Install LaunchAgent
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$LAUNCH_AGENT" << LAUNCHD
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.oren.port-watch</string>
    <key>ProgramArguments</key>
    <array>
        <string>$MACOS_DIR/$APP_NAME</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
LAUNCHD

echo "LaunchAgent installed to $LAUNCH_AGENT"

# Create ~/.port-watch directory
mkdir -p "$HOME/.port-watch"

echo ""
echo "Done! To start PortWatch now:"
echo "  open $APP_BUNDLE"
echo ""
echo "It will auto-start on login via LaunchAgent."
