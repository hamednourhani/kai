#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

REPO="BackendStack21/kai"
CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
AGENTS_DIR="$CONFIG_DIR/agents"
TMPDIR="${TMPDIR:-/tmp}"

DRY_RUN=false
VERBOSE=false
AUTO_YES=false
OUTPUT_DIR=""
BACKUP=false
DOWNLOAD_PATH=""
EXTRACT_DIR=""

# Cleanup handler for temp files on exit or error
cleanup() {
  local exit_code=$?
  [ -z "$DOWNLOAD_PATH" ] || rm -f "$DOWNLOAD_PATH" 2>/dev/null || true
  [ -z "$EXTRACT_DIR" ] || rm -rf "$EXTRACT_DIR" 2>/dev/null || true
  return $exit_code
}
trap cleanup EXIT

# Logging helpers
log() {
  if [ "$VERBOSE" = true ]; then
    printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
  fi
}
info() { printf "[INFO] %s\n" "$*"; }
warn() { printf "[WARN] %s\n" "$*" >&2; }
die() { printf "[ERROR] %s\n" "$*" >&2; exit 1; }

print_usage() {
  cat <<USAGE
Usage: $(basename "$0") <version-or-url> [--repo owner/repo] [--config-dir DIR] [--dry-run] [--backup] [--output-dir DIR] [--yes|--force] [-v|--verbose]

Examples:
  $(basename "$0") v1.2.3
  $(basename "$0") 1.2.3
  $(basename "$0") https://github.com/BackendStack21/kai/releases/download/v1.2.3/kai-claude-v1.2.3.zip
  $(basename "$0") latest --repo BackendStack21/kai

This script will:
  - download a release zip (e.g. kai-claude-VERSION.zip) to $TMPDIR (or --output-dir)
  - extract and copy the included claude/agents/ folder to $AGENTS_DIR (overwriting existing files)

Kai is a subagent on Claude Code, not an auto-loaded persona — after install,
invoke it with '--agent kai' (session-wide) or '@agent-kai' (per-task).

Flags:
  --dry-run        Perform a trial run; no changes will be made.
  --backup         Create a timestamped backup of existing agents before overwriting.
  --output-dir DIR Place temporary download and extraction files in DIR instead of system temp.
  --yes, --force, -y  Suppress interactive prompts (answer yes to confirmations).
  -v, --verbose    Enable verbose logging (timestamps and extra details).

USAGE
}

if [[ ${#@} -lt 1 ]]; then
  print_usage
  exit 1
fi

# parse args
TARGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) print_usage; exit 0 ;;
    --repo) REPO="$2"; shift 2 ;;
    --config-dir) CONFIG_DIR="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --backup) BACKUP=true; shift ;;
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    --yes|--force|-y) AUTO_YES=true; shift ;;
    --verbose|-v) VERBOSE=true; shift ;;
    *)
      if [[ -z "$TARGET" ]]; then TARGET="$1"; shift; else echo "Unknown arg: $1"; print_usage; exit 1; fi
      ;;
  esac
done

if [[ -z "$TARGET" ]]; then
  echo "Error: version or URL is required" >&2
  print_usage
  exit 1
fi

# Recompute derived paths after arg parsing
AGENTS_DIR="$CONFIG_DIR/agents"
OUTPUT_DIR="${OUTPUT_DIR:-$TMPDIR}"

# Requirements
if [ "$DRY_RUN" = true ]; then
  info "DRY-RUN: Skipping external tool checks (curl/unzip will not be required)"
else
  command -v curl >/dev/null 2>&1 || { die "curl is required. Install it and retry."; }
  command -v unzip >/dev/null 2>&1 || { die "unzip is required. Install it and retry."; }
fi

# Check Claude Code
if [ "$DRY_RUN" = true ]; then
  info "DRY-RUN: Skipping Claude Code detection and interactive prompts"
else
  claude_present=false
  if command -v claude >/dev/null 2>&1; then
    claude_present=true
  fi
  if [[ -d "$CONFIG_DIR" ]]; then
    claude_present=true
  fi

  if ! $claude_present; then
    warn "Claude Code does not appear to be installed or configured at $CONFIG_DIR."
    if [ "$AUTO_YES" = true ]; then
      info "Continuing anyway (--yes)"
    else
      read -r -p "Continue installing Kai's agents anyway? [y/N] " yn
      if [[ ! "$yn" =~ ^[Yy]$ ]]; then
        die "Aborted by user. Install Claude Code first: https://claude.com/claude-code"
      fi
    fi
  fi
fi

# Determine download URL / filename
is_url=false
if [[ "$TARGET" =~ ^https?:// ]]; then
  is_url=true
  URL="$TARGET"
  FILENAME="$(basename "$URL")"
else
  VERSION="$TARGET"
  VERSION="${VERSION#v}"

  if [[ "$VERSION" == "latest" ]]; then
    info "Querying GitHub API for latest release..."
    LATEST_TAG=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | grep -o '"tag_name": *"[^"]*"' | head -1 | sed 's/"tag_name": *"\(.*\)"/\1/' || echo "")
    if [[ -z "$LATEST_TAG" ]]; then
      die "Failed to determine latest release version from GitHub API"
    fi
    info "Latest release: $LATEST_TAG"
    VERSION="${LATEST_TAG#v}"
    URLS=(
      "https://github.com/${REPO}/releases/download/${LATEST_TAG}/kai-claude-${LATEST_TAG}.zip"
      "https://github.com/${REPO}/releases/latest/download/kai-claude-${LATEST_TAG}.zip"
    )
  else
    VERSION_WITH_V="v${VERSION}"
    URLS=(
      "https://github.com/${REPO}/releases/download/${VERSION_WITH_V}/kai-claude-${VERSION_WITH_V}.zip"
      "https://github.com/${REPO}/releases/download/${TARGET}/kai-claude-${TARGET}.zip"
      "https://github.com/${REPO}/releases/download/${VERSION}/kai-claude-${VERSION}.zip"
    )
  fi
fi

# Download to temp (respecting --output-dir)
mkdir -p "$OUTPUT_DIR"
DOWNLOAD_PATH=""

if [ "$DRY_RUN" = true ]; then
  if $is_url; then
    info "DRY-RUN: Would download $URL -> $OUTPUT_DIR/$FILENAME"
  else
    if [[ "${VERSION}" == "latest" ]]; then
      info "DRY-RUN: Would query GitHub API for latest release from $REPO"
      info "DRY-RUN: Would download latest kai-claude release zip"
    else
      info "DRY-RUN: Would attempt to download kai-claude-$VERSION.zip from $REPO releases (trying multiple URL patterns):"
      for u in "${URLS[@]}"; do info "  $u"; done
    fi
  fi
  info "DRY-RUN: Would extract the archive and copy 'claude/agents/' to $AGENTS_DIR (overwriting existing files)"
  if [ "$BACKUP" = true ]; then
    info "DRY-RUN: Would create a backup of existing agents in $CONFIG_DIR"
  fi
  exit 0
fi

if $is_url; then
  DOWNLOAD_PATH="$OUTPUT_DIR/$FILENAME"
  info "Downloading $URL -> $DOWNLOAD_PATH"
  curl -fL -o "$DOWNLOAD_PATH" "$URL" || { die "Download failed: $URL"; }
else
  info "Attempting to download kai-claude-$VERSION.zip from $REPO releases (trying multiple URL patterns)..."
  success=false
  for u in "${URLS[@]}"; do
    info "  trying: $u"
    FNAME="$(basename "$u")"
    TMPFILE="$OUTPUT_DIR/$FNAME"
    if curl -fL -o "$TMPFILE" "$u"; then
      DOWNLOAD_PATH="$TMPFILE"
      info "Downloaded: $DOWNLOAD_PATH"
      success=true
      break
    else
      rm -f "$TMPFILE" 2>/dev/null || true
    fi
  done
  if ! $success; then
    die "Failed to download release. Please check the version or provide a direct URL."
  fi
fi

# Verify zip
if ! unzip -t "$DOWNLOAD_PATH" >/dev/null 2>&1; then
  die "Downloaded file is not a valid zip archive: $DOWNLOAD_PATH"
fi

# Extract
EXTRACT_DIR="$(mktemp -d "$OUTPUT_DIR/kai-claude-extract.XXXX")"
unzip -q "$DOWNLOAD_PATH" -d "$EXTRACT_DIR"

# Find claude/ folder inside extracted archive, then validate claude/agents
CLAUDE_SRC="$(find "$EXTRACT_DIR" -type d -name claude -print -quit || true)"
if [[ -z "$CLAUDE_SRC" || ! -d "$CLAUDE_SRC/agents" ]]; then
  echo "Could not find a 'claude/agents' directory inside the downloaded release. Inspecting contents:"
  find "$EXTRACT_DIR" -maxdepth 3 -type d -print
  echo "Aborting."
  exit 7
fi
AGENTS_SRC="$CLAUDE_SRC/agents"

# Backup existing agents if requested
if [ "$BACKUP" = true ] && [ -d "$AGENTS_DIR" ]; then
  timestamp="$(date -u +%Y%m%dT%H%M%S)$(printf '%06d' $((RANDOM * 10)))Z"
  BACKUP_FILE="$CONFIG_DIR/kai-claude-agents-backup-$timestamp.tar.gz"
  info "Creating backup of existing agents -> $BACKUP_FILE"
  tar -C "$CONFIG_DIR" -czf "$BACKUP_FILE" agents || warn "Backup tar failed; continuing"
fi

# Confirm overwrite unless --yes was provided
if [ -d "$AGENTS_DIR" ] && [ "$AUTO_YES" = false ]; then
  read -r -p "This will overwrite existing files in $AGENTS_DIR. Proceed? [y/N] " yn
  if [[ ! "$yn" =~ ^[Yy]$ ]]; then
    die "Aborted by user."
  fi
fi

info "Copying agents from $AGENTS_SRC -> $AGENTS_DIR (existing files will be overwritten)"
mkdir -p "$AGENTS_DIR"
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete "$AGENTS_SRC/" "$AGENTS_DIR/"
else
  cp -a "$AGENTS_SRC/." "$AGENTS_DIR/"
fi

echo "✅ Kai's Claude Code agents installed to: $AGENTS_DIR"
echo
echo "Restart Claude Code or start a new session, then invoke Kai with:"
echo "  claude --agent kai        # session-wide"
echo "  @agent-kai <task>         # per-task, without switching the whole session"

exit 0
