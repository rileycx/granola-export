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
    set homeFolder to POSIX path of (path to home folder)
    set exportScript to homeFolder & "granola-export/export_granola.py"
    set exportFolder to homeFolder & "granola-export/meetings"
    set indexFile to homeFolder & "granola-export/index.json"

    -- Get current meeting count
    set meetingCount to "0"
    try
        set indexContent to do shell script "cat " & quoted form of indexFile
        if indexContent contains "exported_count" then
            set oldDelims to AppleScript's text item delimiters
            set AppleScript's text item delimiters to "\"exported_count\": "
            set parts to text items of indexContent
            if (count of parts) > 1 then
                set afterCount to item 2 of parts
                set AppleScript's text item delimiters to ","
                set meetingCount to text item 1 of afterCount
            end if
            set AppleScript's text item delimiters to oldDelims
        end if
    end try

    -- Show main dialog
    set dialogResult to display dialog "Granola Export saves your meeting transcripts locally as JSON files for use with AI tools.

✓ Auto-exports after every Granola meeting
✓ " & meetingCount & " meetings exported so far

Transcripts are saved to:
~/granola-export/meetings/" buttons {"Open Folder", "Export Now"} default button "Export Now" with title "Granola Export" with icon note

    if button returned of dialogResult is "Open Folder" then
        do shell script "open " & quoted form of exportFolder
    else if button returned of dialogResult is "Export Now" then
        -- Run export
        try
            set output to do shell script "/usr/bin/python3 " & quoted form of exportScript

            -- Parse new count
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
                    set AppleScript's text item delimiters to {return, linefeed, " ", "}"}
                    set totalCount to text item 1 of totalCount
                end if
                set AppleScript's text item delimiters to oldDelims
            end if

            if newCount is "0" then
                display dialog "No new meetings to export.

Total meetings: " & totalCount buttons {"OK", "Open Folder"} default button "OK" with title "Granola Export" with icon note
            else
                display dialog "Exported " & newCount & " new meetings!

Total meetings: " & totalCount buttons {"OK", "Open Folder"} default button "Open Folder" with title "Granola Export" with icon note
            end if

            if button returned of result is "Open Folder" then
                do shell script "open " & quoted form of exportFolder
            end if

        on error errMsg
            display dialog "Export failed: " & errMsg buttons {"OK"} default button "OK" with title "Granola Export" with icon stop
        end try
    end if
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
