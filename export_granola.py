#!/usr/bin/env python3
"""
Granola Transcript Exporter

Exports Granola meeting transcripts to AI-queryable JSON format.
Only exports new transcripts that haven't been saved before.

https://github.com/rileycx/granola-export
"""

import json
import os
import re
import subprocess
import sys
from datetime import datetime

# Paths (automatically use current user's home directory)
HOME = os.path.expanduser("~")
CACHE_PATH = os.path.join(HOME, "Library/Application Support/Granola/cache-v3.json")
EXPORT_DIR = os.path.join(HOME, "granola-export")
MEETINGS_DIR = os.path.join(EXPORT_DIR, "meetings")
INDEX_PATH = os.path.join(EXPORT_DIR, "index.json")
CONFIG_PATH = os.path.join(HOME, ".granola-export-config.json")
LOG_PATH = os.path.join(EXPORT_DIR, "export.log")


def slugify(text: str, max_length: int = 50) -> str:
    """Convert text to a safe filename slug."""
    text = text.lower()
    text = re.sub(r'[^\w\s-]', '', text)
    text = re.sub(r'[-\s]+', '-', text).strip('-')
    return text[:max_length]


def format_transcript(segments: list) -> list:
    """Format transcript segments for export."""
    formatted = []
    for seg in segments:
        formatted.append({
            "speaker": seg.get("source", "unknown"),
            "text": seg.get("text", ""),
            "start": seg.get("start_timestamp"),
            "end": seg.get("end_timestamp"),
        })
    return formatted


def get_full_transcript_text(segments: list) -> str:
    """Get plain text version of transcript for easy searching."""
    lines = []
    current_speaker = None
    current_text = []

    for seg in segments:
        speaker = seg.get("source", "unknown")
        text = seg.get("text", "").strip()

        if speaker != current_speaker:
            if current_text:
                lines.append(f"[{current_speaker}]: {' '.join(current_text)}")
            current_speaker = speaker
            current_text = [text] if text else []
        else:
            if text:
                current_text.append(text)

    if current_text:
        lines.append(f"[{current_speaker}]: {' '.join(current_text)}")

    return "\n\n".join(lines)


def extract_people(doc: dict) -> list:
    """Extract people/participants from document."""
    people = doc.get("people", [])
    if isinstance(people, list):
        return [p.get("name", p.get("email", "Unknown")) if isinstance(p, dict) else str(p) for p in people]
    return []


def log_message(message: str):
    """Append a message to the export log."""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    try:
        with open(LOG_PATH, 'a') as f:
            f.write(f"[{timestamp}] {message}\n")
    except:
        pass


def load_config() -> dict:
    """Load sync configuration from config file."""
    if not os.path.exists(CONFIG_PATH):
        return {}
    try:
        with open(CONFIG_PATH, 'r') as f:
            return json.load(f)
    except (json.JSONDecodeError, IOError):
        return {}


def git_has_changes() -> bool:
    """Check if export directory has uncommitted git changes."""
    git_dir = os.path.join(EXPORT_DIR, ".git")
    if not os.path.exists(git_dir):
        return False
    result = subprocess.run(
        ["git", "status", "--porcelain"],
        cwd=EXPORT_DIR,
        capture_output=True,
        text=True
    )
    return bool(result.stdout.strip())


def remote_matches_repo(repo: str, url: str) -> bool:
    """Best-effort match of configured repo against git remote url."""
    if not repo or not url:
        return False
    repo = repo[:-4] if repo.endswith(".git") else repo
    return repo in url


def sync_github(config: dict) -> bool:
    """Sync exports to GitHub repository."""
    repo = config.get("github_repo", "")
    branch = config.get("github_branch", "main")

    if not repo:
        log_message("SYNC WARNING: github_repo not configured")
        return False

    try:
        # Check if git repo is initialized
        git_dir = os.path.join(EXPORT_DIR, ".git")
        if not os.path.exists(git_dir):
            log_message("SYNC WARNING: Git not initialized in export dir. Run: cd ~/granola-export && git init && git remote add origin <repo-url>")
            return False

        # Validate remote matches configured repo
        remote = subprocess.run(
            ["git", "remote", "get-url", "origin"],
            cwd=EXPORT_DIR,
            capture_output=True,
            text=True
        )
        remote_url = remote.stdout.strip()
        if remote.returncode != 0 or not remote_matches_repo(repo, remote_url):
            log_message(f"SYNC WARNING: Git remote 'origin' does not match configured repo ({repo}).")
            print(f"Sync skipped: git remote 'origin' does not match configured repo ({repo}).")
            return False

        # Copy new meeting files from meetings/ to root (repo stores in root)
        import shutil
        for filename in os.listdir(MEETINGS_DIR):
            if filename.endswith('.json'):
                src = os.path.join(MEETINGS_DIR, filename)
                dst = os.path.join(EXPORT_DIR, filename)
                shutil.copy2(src, dst)

        # Stage all changes
        subprocess.run(
            ["git", "add", "-A"],
            cwd=EXPORT_DIR,
            capture_output=True,
            check=True
        )

        # Check if there are changes to commit
        result = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=EXPORT_DIR,
            capture_output=True,
            text=True
        )

        if not result.stdout.strip():
            log_message("SYNC: No changes to push")
            return True

        # Commit changes
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        subprocess.run(
            ["git", "commit", "-m", f"Auto-sync: {timestamp}"],
            cwd=EXPORT_DIR,
            capture_output=True,
            check=True
        )

        # Push to remote
        subprocess.run(
            ["git", "push", "origin", branch],
            cwd=EXPORT_DIR,
            capture_output=True,
            check=True
        )

        log_message(f"SYNC: Pushed to GitHub ({repo})")
        return True

    except subprocess.CalledProcessError as e:
        log_message(f"SYNC ERROR (github): {e.stderr.decode() if e.stderr else str(e)}")
        return False
    except Exception as e:
        log_message(f"SYNC ERROR (github): {str(e)}")
        return False


def sync_command(config: dict) -> bool:
    """Run custom sync command."""
    command = config.get("sync_command", "")

    if not command:
        log_message("SYNC WARNING: sync_command not configured")
        return False

    try:
        result = subprocess.run(
            command,
            shell=True,
            cwd=EXPORT_DIR,
            capture_output=True,
            text=True
        )

        if result.returncode == 0:
            log_message(f"SYNC: Custom command succeeded")
            return True
        else:
            log_message(f"SYNC ERROR (command): {result.stderr}")
            return False

    except Exception as e:
        log_message(f"SYNC ERROR (command): {str(e)}")
        return False


def run_sync(new_count: int):
    """Run sync if enabled and there are new exports."""
    config = load_config()

    if not config.get("sync_enabled", False):
        return

    if new_count == 0:
        log_message("SYNC: Skipped (no new exports)")
        return

    sync_method = config.get("sync_method", "")

    if sync_method == "github":
        if new_count == 0 and not git_has_changes():
            log_message("SYNC: Skipped (no new exports)")
            return
        sync_github(config)
    elif sync_method == "command":
        if new_count == 0 and not config.get("sync_on_no_new", False):
            log_message("SYNC: Skipped (no new exports)")
            return
        sync_command(config)
    else:
        log_message(f"SYNC WARNING: Unknown sync method '{sync_method}'")


def main():
    # Check if Granola cache exists
    if not os.path.exists(CACHE_PATH):
        print("Error: Granola cache not found.")
        print(f"Expected location: {CACHE_PATH}")
        print("Make sure Granola is installed and you've had at least one meeting.")
        sys.exit(1)

    # Load cache
    print(f"Loading Granola cache...")
    try:
        with open(CACHE_PATH, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        print("Error: Could not parse Granola cache file.")
        sys.exit(1)

    cache_blob = data.get('cache', {})
    if isinstance(cache_blob, str):
        try:
            inner = json.loads(cache_blob)
        except json.JSONDecodeError:
            print("Error: Could not parse Granola cache payload.")
            sys.exit(1)
    elif isinstance(cache_blob, dict):
        inner = cache_blob
    else:
        print("Error: Granola cache payload has unexpected type.")
        sys.exit(1)
    state = inner.get('state', {})

    documents = state.get('documents', {})
    transcripts = state.get('transcripts', {})

    if not isinstance(documents, dict) or not isinstance(transcripts, dict):
        print("Error: Granola cache schema changed (documents/transcripts missing).")
        sys.exit(1)

    print(f"Found {len(documents)} documents and {len(transcripts)} transcripts in cache")

    # Create meetings directory
    os.makedirs(MEETINGS_DIR, exist_ok=True)

    # Load existing index to check what's already exported
    existing_ids = set()
    existing_meetings = []

    if os.path.exists(INDEX_PATH):
        try:
            with open(INDEX_PATH, 'r') as f:
                existing_index = json.load(f)
                existing_meetings = existing_index.get("meetings", [])
                existing_ids = {m["id"] for m in existing_meetings}
                print(f"Found {len(existing_ids)} already exported meetings")
        except (json.JSONDecodeError, KeyError):
            print("Could not read existing index, starting fresh")

    new_count = 0
    skipped_no_transcript = 0
    already_exported = 0

    for doc_id, doc in documents.items():
        # Skip if already exported
        if doc_id in existing_ids:
            already_exported += 1
            continue

        # Get transcript for this document
        transcript_data = transcripts.get(doc_id, [])

        # Skip if no transcript
        if not transcript_data or not isinstance(transcript_data, list) or len(transcript_data) == 0:
            skipped_no_transcript += 1
            continue

        title = doc.get("title", "Untitled Meeting")
        created_at = doc.get("created_at", "")

        # Parse date for filename
        try:
            date_obj = datetime.fromisoformat(created_at.replace('Z', '+00:00'))
            date_str = date_obj.strftime("%Y-%m-%d")
        except:
            date_str = "unknown-date"

        # Create filename using doc_id to ensure uniqueness
        filename = f"{date_str}_{slugify(title)}_{doc_id[:8]}.json"
        filepath = os.path.join(MEETINGS_DIR, filename)

        # Build meeting export
        meeting = {
            "id": doc_id,
            "title": title,
            "date": created_at,
            "people": extract_people(doc),
            "summary": doc.get("summary"),
            "overview": doc.get("overview"),
            "notes_markdown": doc.get("notes_markdown"),
            "notes_plain": doc.get("notes_plain"),
            "chapters": doc.get("chapters"),
            "transcript_segments": format_transcript(transcript_data),
            "transcript_text": get_full_transcript_text(transcript_data),
        }

        # Write meeting file
        with open(filepath, 'w') as f:
            json.dump(meeting, f, indent=2)

        # Add to existing meetings list
        existing_meetings.append({
            "id": doc_id,
            "title": title,
            "date": created_at,
            "people": extract_people(doc),
            "file": f"meetings/{filename}",
            "has_summary": bool(doc.get("summary")),
            "segment_count": len(transcript_data),
        })

        new_count += 1
        print(f"  NEW: {filename}")

    # Sort all meetings by date descending
    existing_meetings.sort(key=lambda x: x.get("date", ""), reverse=True)

    # Build updated index
    index = {
        "exported_at": datetime.now().isoformat(),
        "total_documents": len(documents),
        "total_transcripts": len(transcripts),
        "exported_count": len(existing_meetings),
        "meetings": existing_meetings
    }

    # Write index
    with open(INDEX_PATH, 'w') as f:
        json.dump(index, f, indent=2)

    print(f"\nExport complete!")
    print(f"  New: {new_count} meetings exported")
    print(f"  Already exported: {already_exported}")
    print(f"  No transcript: {skipped_no_transcript}")
    print(f"  Total in index: {len(existing_meetings)}")

    # Run sync if enabled
    run_sync(new_count)

    # Return count for notification scripts
    return new_count


if __name__ == "__main__":
    main()
