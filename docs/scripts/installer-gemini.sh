#!/usr/bin/env bash
# Installs Kai's Gemini CLI platform (KAI.md + gemini subagents) from a
# GitHub release into ~/.gemini, mirroring installer.sh's OpenCode flow.
set -euo pipefail
IFS=$'\n\t'

REPO="BackendStack21/kai"
CONFIG_DIR="${GEMINI_CONFIG_DIR:-$HOME/.gemini}"
AGENTS_DIR="$CONFIG_DIR/agents"
TMPDIR="${TMPDIR:-/tmp}"

DRY_RUN=false
VERBOSE=false
AUTO_YES=false
OUTPUT_DIR=""
BACKUP=false
DOWNLOAD_PATH=""
EXTRACT_DIR=""

cleanup() {
  local exit_code=$?
  [ -z "$DOWNLOAD_PATH" ] || rm -f "$DOWNLOAD_PATH" 2>/dev/null || true
  [ -z "$EXTRACT_DIR" ] || rm -rf "$EXTRACT_DIR" 2>/dev/null || true
  return $exit_code
}
trap cleanup EXIT

log() { if [ "$VERBOSE" = true ]; then printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; fi; }
info() { printf "[INFO] %s\n" "$*"; }
warn() { printf "[WARN] %s\n" "$*" >&2; }
die() { printf "[ERROR] %s\n" "$*" >&2; exit 1; }

print_usage() {
  cat <<USAGE
Usage: $(basename "$0") <version-or-url> [--repo owner/repo] [--config-dir DIR] [--dry-run] [--backup] [--output-dir DIR] [--yes|--force] [-v|--verbose]

Examples:
  $(basename "$0") v1.2.3
  $(basename "$0") 1.2.3
  $(basename "$0") https://github.com/BackendStack21/kai/releases/download/v1.2.3/kai-gemini-v1.2.3.zip
  $(basename "$0") latest --repo BackendStack21/kai

This script will:
  - download a release zip (e.g. kai-gemini-VERSION.zip) to $TMPDIR (or --output-dir)
  - extract and copy the included gemini/agents/ folder to $AGENTS_DIR (overwriting existing files)
  - copy gemini/KAI.md to $CONFIG_DIR/KAI.md (overwriting existing file)
  - install gemini/GEMINI.md to $CONFIG_DIR/GEMINI.md:
      * if you don't have one yet, it's copied as-is
      * if you already have one, we only append the "@KAI.md" import line
        (never overwriting your existing GEMINI.md content)

Flags:
  --dry-run        Perform a trial run; no changes will be made.
  --backup         Create a timestamped backup of existing agents/KAI.md/GEMINI.md before overwriting.
  --output-dir DIR Place temporary download and extraction files in DIR instead of system temp.
  --yes, --force, -y  Suppress interactive prompts (answer yes to confirmations).
  -v, --verbose    Enable verbose logging (timestamps and extra details).

USAGE
}

if [[ ${#@} -lt 1 ]]; then
  print_usage
  exit 1
fi

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

if [ "$DRY_RUN" = true ]; then
  info "DRY-RUN: Skipping external tool checks (curl/unzip will not be required)"
else
  command -v curl >/dev/null 2>&1 || { die "curl is required. Install it and retry."; }
  command -v unzip >/dev/null 2>&1 || { die "unzip is required. Install it and retry."; }
fi

if [ "$DRY_RUN" = true ]; then
  info "DRY-RUN: Skipping Gemini CLI detection"
elif ! command -v gemini >/dev/null 2>&1; then
  warn "Gemini CLI does not appear to be installed (no 'gemini' binary on PATH)."
  warn "Install it from https://github.com/google-gemini/gemini-cli before using these agents."
  if [ "$AUTO_YES" = false ]; then
    read -r -p "Continue installing Kai's agent files anyway? [y/N] " yn
    if [[ ! "$yn" =~ ^[Yy]$ ]]; then
      die "Aborted by user."
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
    VERSION_WITH_V="v${VERSION}"
    URLS=(
      "https://github.com/${REPO}/releases/download/${LATEST_TAG}/kai-gemini-${LATEST_TAG}.zip"
      "https://github.com/${REPO}/releases/latest/download/kai-gemini-${LATEST_TAG}.zip"
    )
  else
    VERSION_WITH_V="v${VERSION}"
    URLS=(
      "https://github.com/${REPO}/releases/download/${VERSION_WITH_V}/kai-gemini-${VERSION_WITH_V}.zip"
      "https://github.com/${REPO}/releases/download/${TARGET}/kai-gemini-${TARGET}.zip"
      "https://github.com/${REPO}/releases/download/${VERSION}/kai-gemini-${VERSION}.zip"
    )
  fi
fi

mkdir -p "$OUTPUT_DIR"
DOWNLOAD_PATH=""

if [ "$DRY_RUN" = true ]; then
  if $is_url; then
    info "DRY-RUN: Would download $URL -> $OUTPUT_DIR/$FILENAME"
  else
    if [[ "${VERSION}" == "latest" ]]; then
      info "DRY-RUN: Would query GitHub API for latest release from $REPO"
      info "DRY-RUN: Would download latest kai-gemini release zip"
    else
      info "DRY-RUN: Would attempt to download kai-gemini-$VERSION.zip from $REPO releases (trying multiple URL patterns):"
      for u in "${URLS[@]}"; do info "  $u"; done
    fi
  fi
  info "DRY-RUN: Would extract the archive and copy 'gemini/agents/' to $AGENTS_DIR (overwriting existing files)"
  info "DRY-RUN: Would copy 'gemini/KAI.md' to $CONFIG_DIR/KAI.md (overwriting existing file)"
  info "DRY-RUN: Would install 'gemini/GEMINI.md' to $CONFIG_DIR/GEMINI.md (merge-safe: appends @KAI.md import if a GEMINI.md already exists instead of overwriting)"
  if [ "$BACKUP" = true ]; then
    info "DRY-RUN: Would create a timestamped backup of existing agents/KAI.md/GEMINI.md in $CONFIG_DIR"
  fi
  exit 0
fi

if $is_url; then
  DOWNLOAD_PATH="$OUTPUT_DIR/$FILENAME"
  info "Downloading $URL -> $DOWNLOAD_PATH"
  curl -fL -o "$DOWNLOAD_PATH" "$URL" || { die "Download failed: $URL"; }
else
  info "Attempting to download kai-gemini-$VERSION.zip from $REPO releases (trying multiple URL patterns)..."
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

if ! unzip -t "$DOWNLOAD_PATH" >/dev/null 2>&1; then
  die "Downloaded file is not a valid zip archive: $DOWNLOAD_PATH"
fi

EXTRACT_DIR="$(mktemp -d "$OUTPUT_DIR/kai-gemini-extract.XXXX")"
unzip -q "$DOWNLOAD_PATH" -d "$EXTRACT_DIR"

# Find the gemini/ folder inside the extracted archive
GEMINI_SRC="$(find "$EXTRACT_DIR" -type d -name gemini -print -quit || true)"
if [[ -z "$GEMINI_SRC" || ! -d "$GEMINI_SRC" ]]; then
  echo "Could not find a 'gemini' directory inside the downloaded release. Inspecting contents:"
  find "$EXTRACT_DIR" -maxdepth 3 -type d -print
  echo "Aborting."
  exit 7
fi
if [[ ! -d "$GEMINI_SRC/agents" ]] || [[ ! -f "$GEMINI_SRC/KAI.md" ]]; then
  die "Downloaded 'gemini' directory is incomplete (missing agents/ or KAI.md)"
fi

timestamp() { date -u +%Y%m%dT%H%M%S; }

if [ "$BACKUP" = true ]; then
  if [ -d "$AGENTS_DIR" ]; then
    BACKUP_FILE="$CONFIG_DIR/kai-gemini-agents-backup-$(timestamp).tar.gz"
    info "Creating backup of existing agents -> $BACKUP_FILE"
    tar -C "$CONFIG_DIR" -czf "$BACKUP_FILE" agents || warn "Backup tar failed; continuing"
  fi
  for f in KAI.md GEMINI.md; do
    if [ -f "$CONFIG_DIR/$f" ]; then
      bak="$CONFIG_DIR/$f.bak.$(timestamp)"
      cp "$CONFIG_DIR/$f" "$bak" || warn "Failed to backup $CONFIG_DIR/$f"
      info "Backed up $CONFIG_DIR/$f -> $bak"
    fi
  done
fi

if [ -d "$AGENTS_DIR" ] && [ "$AUTO_YES" = false ]; then
  read -r -p "This will overwrite existing files in $AGENTS_DIR and $CONFIG_DIR/KAI.md. Proceed? [y/N] " yn
  if [[ ! "$yn" =~ ^[Yy]$ ]]; then
    die "Aborted by user."
  fi
fi

info "Copying agents from $GEMINI_SRC/agents -> $AGENTS_DIR (existing files will be overwritten)"
mkdir -p "$AGENTS_DIR"
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete "$GEMINI_SRC/agents/" "$AGENTS_DIR/"
else
  cp -a "$GEMINI_SRC/agents/." "$AGENTS_DIR/"
fi

info "Installing $CONFIG_DIR/KAI.md"
mkdir -p "$CONFIG_DIR"
cp "$GEMINI_SRC/KAI.md" "$CONFIG_DIR/KAI.md"

# GEMINI.md: never blindly overwrite -- it may hold the user's own global
# context (other tool instructions, project notes, etc). Only ensure the
# "@KAI.md" import line is present.
GEMINI_MD="$CONFIG_DIR/GEMINI.md"
IMPORT_LINE="@KAI.md"
if [ -f "$GEMINI_MD" ]; then
  if grep -qF "$IMPORT_LINE" "$GEMINI_MD" 2>/dev/null; then
    info "$GEMINI_MD already imports KAI.md — leaving your existing content untouched"
  else
    info "Appending '$IMPORT_LINE' to existing $GEMINI_MD (your existing content is preserved)"
    printf '\n%s\n' "$IMPORT_LINE" >> "$GEMINI_MD"
  fi
else
  info "Creating $GEMINI_MD"
  cp "$GEMINI_SRC/GEMINI.md" "$GEMINI_MD"
fi

echo "✅ Kai's Gemini CLI agents installed to: $AGENTS_DIR"
echo "✅ Kai persona installed to: $CONFIG_DIR/KAI.md"
echo "✅ $GEMINI_MD imports KAI.md"
echo ""
echo "Restart Gemini CLI or run '/memory reload' to load the new context."

exit 0
