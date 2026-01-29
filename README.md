# Granola Export

Export your [Granola](https://granola.ai) meeting transcripts to local JSON files, optimized for AI querying and search.

## Features

- **Automatic export** — Transcripts are exported automatically when meetings end
- **Incremental sync** — Only exports new transcripts, skips already-exported ones
- **AI-optimized format** — JSON structure designed for easy AI/LLM consumption
- **Searchable index** — Master index file for quick lookups across all meetings
- **Manual export** — Click the app anytime to export on-demand

## What Gets Exported

Each meeting is saved as a JSON file containing:

```json
{
  "id": "meeting-uuid",
  "title": "Weekly Team Sync",
  "date": "2024-01-15T10:00:00.000Z",
  "people": ["Alice", "Bob"],
  "summary": "AI-generated meeting summary...",
  "notes_markdown": "Your notes in markdown...",
  "transcript_text": "Full conversation with speaker labels...",
  "transcript_segments": [
    {
      "speaker": "Alice",
      "text": "Let's get started...",
      "start": 0,
      "end": 2500
    }
  ]
}
```

## Requirements

- macOS 10.15+
- [Granola](https://granola.ai) installed
- Python 3 (included with macOS)

## Installation

```bash
git clone https://github.com/rileycx/granola-export.git
cd granola-export
./install.sh
```

The installer will:
1. Create `~/granola-export/` directory
2. Set up automatic export (triggers when Granola saves a meeting)
3. Create a macOS app for manual exports
4. Run an initial export of all cached transcripts

## Usage

### Automatic Export
After installation, transcripts are exported automatically whenever you finish a Granola meeting. No action needed.

### Manual Export
Double-click `GranolaExport.app` in `~/granola-export/` or add it to your Dock.

### Command Line
```bash
python3 ~/granola-export/export_granola.py
```

## Export Location

```
~/granola-export/
├── index.json              # Searchable index of all meetings
├── export.log              # Export history and errors
├── GranolaExport.app       # Click to export manually
└── meetings/
    ├── 2024-01-15_weekly-team-sync_abc12345.json
    ├── 2024-01-14_product-review_def67890.json
    └── ...
```

## Querying with AI

The export format is optimized for AI assistants. Example prompts:

- "Search my meetings for discussions about pricing"
- "Summarize what Alice said in last week's meetings"
- "Find all action items from January meetings"

Load the `index.json` for quick lookups, or individual meeting files for full transcripts.

## Important Notes

**Granola only caches recent transcripts locally.** To export older meetings:
1. Open the meeting in Granola (this caches the transcript)
2. Run the export (automatic or manual)

The exporter reads from Granola's local cache at:
```
~/Library/Application Support/Granola/cache-v3.json
```

## Uninstall

```bash
cd granola-export
./uninstall.sh
```

Your exported meetings in `~/granola-export/meetings/` will be preserved.

## License

MIT License - see [LICENSE](LICENSE)

## Credits

Built for the Granola community. Not affiliated with Granola.
