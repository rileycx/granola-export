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

# Copy export script (skip if already in install dir)
echo "📄 Installing export script..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ "$SCRIPT_DIR" != "$INSTALL_DIR" ]; then
    cp "$SCRIPT_DIR/export_granola.py" "$INSTALL_DIR/"
fi
chmod +x "$INSTALL_DIR/export_granola.py"

# Create wrapper script (shows as "granola-export" in Activity Monitor)
cat > "$INSTALL_DIR/granola-export" << 'WRAPPER'
#!/bin/bash
exec /usr/bin/python3 "$(dirname "$0")/export_granola.py" "$@"
WRAPPER
chmod +x "$INSTALL_DIR/granola-export"

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
    cp "$SCRIPT_DIR/AppIcon.icns" "$APP_DIR/Granola Export.app/Contents/Resources/applet.icns" 2>/dev/null || true
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
        <string>$INSTALL_DIR/granola-export</string>
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

# Cloud sync setup
echo ""
echo "☁️  Cloud Sync Setup (optional)"
echo "   Sync exports to GitHub or run a custom command after each export."
echo ""
read -p "Enable cloud sync? (y/n) " -n 1 -r
echo ""

CONFIG_FILE="$HOME/.granola-export-config.json"

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "Sync methods:"
    echo "  1) GitHub - push to a private repo"
    echo "  2) Custom command - run your own sync command (rsync, s3, etc.)"
    echo ""
    read -p "Choose sync method (1 or 2): " -n 1 -r SYNC_METHOD
    echo ""

    if [[ $SYNC_METHOD == "1" ]]; then
        echo ""
        echo "GitHub Sync Setup"
        echo "-----------------"
        echo "You'll need a GitHub repo to push to."
        echo "Create one at: https://github.com/new (make it private!)"
        echo ""
        read -p "GitHub repo (e.g., username/granola-transcripts): " GITHUB_REPO
        read -p "Branch name (default: main): " GITHUB_BRANCH
        GITHUB_BRANCH=${GITHUB_BRANCH:-main}

        # Create config file
        cat > "$CONFIG_FILE" << CONFIGEOF
{
  "sync_enabled": true,
  "sync_method": "github",
  "github_repo": "$GITHUB_REPO",
  "github_branch": "$GITHUB_BRANCH"
}
CONFIGEOF

        # Initialize git repo in export directory
        echo ""
        echo "Initializing git repo..."
        cd "$INSTALL_DIR"
        if [ ! -d ".git" ]; then
            git init
            git branch -M "$GITHUB_BRANCH"
        fi

        # Check if remote exists
        if ! git remote get-url origin &>/dev/null; then
            git remote add origin "git@github.com:$GITHUB_REPO.git"
        fi

        # Create .gitignore for export dir
        cat > "$INSTALL_DIR/.gitignore" << GITIGNOREEOF
export.log
*.pyc
__pycache__/
.DS_Store
GITIGNOREEOF

        echo ""
        echo "✅ GitHub sync configured!"
        echo "   Repo: $GITHUB_REPO"
        echo "   Branch: $GITHUB_BRANCH"
        echo ""
        echo "⚠️  Make sure you've added your SSH key to GitHub."
        echo "   Test with: cd ~/granola-export && git push -u origin $GITHUB_BRANCH"

    elif [[ $SYNC_METHOD == "2" ]]; then
        echo ""
        echo "Custom Command Setup"
        echo "--------------------"
        echo "Enter a shell command to run after each export."
        echo "The command runs from ~/granola-export/"
        echo ""
        echo "Examples:"
        echo "  rsync -av meetings/ user@server:/backups/granola/"
        echo "  aws s3 sync meetings/ s3://my-bucket/granola/"
        echo ""
        read -p "Sync command: " SYNC_COMMAND

        # Create config file
        cat > "$CONFIG_FILE" << CONFIGEOF
{
  "sync_enabled": true,
  "sync_method": "command",
  "sync_command": "$SYNC_COMMAND"
}
CONFIGEOF

        echo ""
        echo "✅ Custom sync configured!"
        echo "   Command: $SYNC_COMMAND"
    fi
else
    # Create disabled config
    cat > "$CONFIG_FILE" << CONFIGEOF
{
  "sync_enabled": false
}
CONFIGEOF
    echo "   Sync disabled. Edit ~/.granola-export-config.json to enable later."
fi

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
