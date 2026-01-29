#!/bin/bash
#
# Granola Export Uninstaller
# Removes the Granola transcript exporter
#

INSTALL_DIR="$HOME/granola-export"
APP_DIR="$HOME/Applications"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
LAUNCH_AGENT_FILE="com.granola.export.plist"

echo "🥣 Granola Export Uninstaller"
echo "============================="
echo ""

# Confirm
read -p "This will remove Granola Export. Your exported meetings will be kept. Continue? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# Unload LaunchAgent
echo "⏹️  Stopping automatic export..."
launchctl unload "$LAUNCH_AGENT_DIR/$LAUNCH_AGENT_FILE" 2>/dev/null || true
rm -f "$LAUNCH_AGENT_DIR/$LAUNCH_AGENT_FILE"

# Remove app
echo "🗑️  Removing app..."
rm -rf "$APP_DIR/Granola Export.app"
rm -f "$INSTALL_DIR/export_granola.py"
rm -f "$INSTALL_DIR/export.log"

echo ""
echo "✅ Uninstall complete!"
echo ""
echo "📁 Your exported meetings are still at: $INSTALL_DIR/meetings/"
echo "   To remove them too, run: rm -rf $INSTALL_DIR"
