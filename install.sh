#!/bin/bash
#
# Granola Export Installer
# Installs the Granola transcript exporter with automatic sync
#

set -e

INSTALL_DIR="$HOME/granola-export"
APP_DIR="$HOME/Applications"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
LAUNCH_AGENT_FILE="com.granola.export.plist"
GRANOLA_CACHE="$HOME/Library/Application Support/Granola/cache-v3.json"

echo "🥣 Granola Export Installer"
echo "==========================="
echo ""

# Check if Granola is installed
if [ ! -f "$GRANOLA_CACHE" ]; then
    echo "⚠️  Warning: Granola cache not found."
    echo "   Make sure Granola is installed and you've had at least one meeting."
    echo "   Expected: $GRANOLA_CACHE"
    echo ""
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Create install directory
echo "📁 Creating install directory..."
mkdir -p "$INSTALL_DIR/meetings"

# Copy export script
echo "📄 Installing export script..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp "$SCRIPT_DIR/export_granola.py" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/export_granola.py"

# Create the macOS app for manual exports
echo "🖱️  Creating menu bar app..."
cat > /tmp/granola_app.applescript << 'APPLESCRIPT'
on run
    set exportScript to (POSIX path of (path to home folder)) & "granola-export/export_granola.py"
    set logFile to (POSIX path of (path to home folder)) & "granola-export/export.log"

    display notification "Starting export..." with title "Granola Export" sound name "Submarine"

    try
        set output to do shell script "/usr/bin/python3 " & quoted form of exportScript

        -- Log the output with timestamp
        set timestamp to do shell script "date '+%Y-%m-%d %H:%M:%S'"
        do shell script "echo '\\n--- " & timestamp & " ---\\n" & output & "' >> " & quoted form of logFile

        -- Parse export count
        set newCount to "0"
        if output contains "New:" then
            set oldDelims to AppleScript's text item delimiters
            set AppleScript's text item delimiters to "New: "
            set parts to text items of output
            if (count of parts) > 1 then
                set afterNew to item 2 of parts
                set AppleScript's text item delimiters to " meetings"
                set newCount to text item 1 of afterNew
            end if
            set AppleScript's text item delimiters to oldDelims
        end if

        -- Parse total count
        set totalCount to "0"
        if output contains "Total in index:" then
            set oldDelims to AppleScript's text item delimiters
            set AppleScript's text item delimiters to "Total in index: "
            set parts to text items of output
            if (count of parts) > 1 then
                set totalCount to item 2 of parts
                -- Remove any trailing whitespace/newlines
                set AppleScript's text item delimiters to {return, linefeed, " "}
                set totalCount to text item 1 of totalCount
            end if
            set AppleScript's text item delimiters to oldDelims
        end if

        if newCount is "0" then
            display notification "No new meetings to export. Total: " & totalCount with title "Granola Export" sound name "Pop"
        else
            display notification "Exported " & newCount & " new meetings. Total: " & totalCount with title "Granola Export Complete" sound name "Glass"
        end if

    on error errMsg
        display notification errMsg with title "Granola Export Failed" sound name "Basso"

        set timestamp to do shell script "date '+%Y-%m-%d %H:%M:%S'"
        do shell script "echo '\\n--- " & timestamp & " ERROR ---\\n" & errMsg & "' >> " & quoted form of logFile
    end try
end run
APPLESCRIPT

# Create ~/Applications if it doesn't exist (for Launchpad visibility)
mkdir -p "$APP_DIR"
osacompile -o "$APP_DIR/Granola Export.app" /tmp/granola_app.applescript
rm /tmp/granola_app.applescript

# Add custom icon
if [ -f "$SCRIPT_DIR/AppIcon.icns" ]; then
    cp "$SCRIPT_DIR/AppIcon.icns" "$APP_DIR/Granola Export.app/Contents/Resources/applet.icns"
    # Touch the app to refresh icon cache
    touch "$APP_DIR/Granola Export.app"
fi

# Create LaunchAgent for automatic exports
echo "⚡ Setting up automatic export on meeting end..."
mkdir -p "$LAUNCH_AGENT_DIR"

cat > "$LAUNCH_AGENT_DIR/$LAUNCH_AGENT_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.granola.export</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>$INSTALL_DIR/export_granola.py</string>
    </array>
    <key>WatchPaths</key>
    <array>
        <string>$HOME/Library/Application Support/Granola/cache-v3.json</string>
    </array>
    <key>StandardOutPath</key>
    <string>$INSTALL_DIR/export.log</string>
    <key>StandardErrorPath</key>
    <string>$INSTALL_DIR/export.log</string>
    <key>ThrottleInterval</key>
    <integer>30</integer>
</dict>
</plist>
EOF

# Load the LaunchAgent
launchctl unload "$LAUNCH_AGENT_DIR/$LAUNCH_AGENT_FILE" 2>/dev/null || true
launchctl load "$LAUNCH_AGENT_DIR/$LAUNCH_AGENT_FILE"

# Run initial export
echo "🚀 Running initial export..."
python3 "$INSTALL_DIR/export_granola.py"

echo ""
echo "✅ Installation complete!"
echo ""
echo "📍 Export location: $INSTALL_DIR/meetings/"
echo "📊 Index file: $INSTALL_DIR/index.json"
echo "📝 Log file: $INSTALL_DIR/export.log"
echo ""
echo "🔄 Automatic export: Enabled (triggers when Granola cache updates)"
echo ""
echo "📌 App installed: $APP_DIR/Granola Export.app"
echo "   (Available in Launchpad and Spotlight)"
echo ""
echo "To uninstall, run: ./uninstall.sh"
