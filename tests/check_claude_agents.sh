#!/usr/bin/env bash
# Validates the Claude Code agent definition files in claude/agents/ for consistency.
# Single source of truth for the ecosystem version is the root README.md (**Version:** X.Y.Z).
#
# Checks, per agent file:
#   1. Required frontmatter fields present: name, description, tools.
#   2. `name:` matches the filename.
#   3. Footer/H1 version matches the ecosystem version.
#   4. No `memory:` frontmatter field (project memory is handled via .kai/, not
#      Claude Code's native per-agent memory scopes — see claude/README.md).
#   5. No bare `@name` mentions (Claude Code's real mention syntax is
#      `@agent-<name>`; internal routing/handoff references should use bare
#      names that match `name:` frontmatter, not `@`-prefixed text).
#   6. No deprecated `TodoWrite` tool (replaced by TaskCreate/TaskGet/TaskList/TaskUpdate).
set -euo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTS_DIR="$ROOT_DIR/claude/agents"
README="$ROOT_DIR/README.md"

if [ ! -d "$AGENTS_DIR" ]; then
  echo "[FAIL] claude agents directory not found: $AGENTS_DIR"
  exit 1
fi

EXPECTED_VERSION="$(grep -m1 -E '^\*\*Version:\*\*' "$README" | sed -E 's/[^0-9.]//g')"
if [ -z "$EXPECTED_VERSION" ]; then
  echo "[FAIL] could not read ecosystem version from $README"
  exit 1
fi
echo "[INFO] Ecosystem version (from README): $EXPECTED_VERSION"

errors=0
fail() { echo "[FAIL] $1"; errors=$((errors + 1)); }

# Registered agent names, used to scope the bare-@mention check (check 5) to
# real subagent references only — not JSDoc tags, npm scopes (@typescript-eslint),
# decorators (@patch), or version pins (actions/checkout@v4) that appear in
# ported code samples.
AGENT_NAMES="$(for f in "$AGENTS_DIR"/*.md; do basename "$f" .md; done | paste -sd '|' -)"

for f in "$AGENTS_DIR"/*.md; do
  name="$(basename "$f" .md)"
  file="$(basename "$f")"

  # 1. Required frontmatter fields
  for field in name description tools; do
    if ! grep -qE "^${field}:" "$f"; then
      fail "$file: missing required frontmatter field '${field}:'"
    fi
  done

  # 2. name: matches filename
  fm_name="$(grep -m1 -E '^name:' "$f" | sed -E 's/^name:[[:space:]]*//')"
  if [ -n "$fm_name" ] && [ "$fm_name" != "$name" ]; then
    fail "$file: name: '$fm_name' does not match filename '$name'"
  fi

  # 3. Footer/H1 version matches ecosystem version
  footer_ver="$(grep -oE '\*\*Version:\*\* [0-9]+\.[0-9]+\.[0-9]+' "$f" | head -1 | sed -E 's/[^0-9.]//g' || true)"
  if [ -z "$footer_ver" ]; then
    footer_ver="$(grep -oE '^v[0-9]+\.[0-9]+\.[0-9]+ \|' "$f" | head -1 | sed -E 's/[^0-9.]//g' || true)"
  fi
  if [ -z "$footer_ver" ]; then
    fail "$file: no version footer found"
  elif [ "$footer_ver" != "$EXPECTED_VERSION" ]; then
    fail "$file: footer version $footer_ver != ecosystem $EXPECTED_VERSION"
  fi

  header_ver="$(grep -m1 -oE '^# .*v[0-9]+\.[0-9]+(\.[0-9]+)?' "$f" | grep -oE 'v[0-9]+\.[0-9]+(\.[0-9]+)?$' | sed 's/^v//' || true)"
  if [ -n "$header_ver" ] && [ "$header_ver" != "$EXPECTED_VERSION" ]; then
    fail "$file: H1 title version $header_ver != ecosystem $EXPECTED_VERSION"
  fi

  # 4. No native memory: frontmatter field
  if grep -qE '^memory:' "$f"; then
    fail "$file: 'memory:' frontmatter is not allowed — project memory is handled via .kai/ (see claude/README.md)"
  fi

  # 5. No bare @<agent-name> mentions (only @agent-<name> is valid Claude Code
  #    mention syntax). Scoped to actual registered agent names so JSDoc tags,
  #    npm scopes, decorators, and version pins in code samples aren't flagged.
  bad_mentions="$(grep -noE "@(${AGENT_NAMES})\b" "$f" | grep -vE ':@agent-' || true)"
  if [ -n "$bad_mentions" ]; then
    fail "$file: bare @-mention of an agent name found (use @agent-<name> or a bare name, not @<name>): $(echo "$bad_mentions" | tr '\n' ' ')"
  fi

  # 6. No deprecated TodoWrite tool
  if grep -qE '^tools:.*TodoWrite' "$f"; then
    fail "$file: deprecated 'TodoWrite' tool in tools: — use TaskCreate, TaskGet, TaskList, TaskUpdate"
  fi
done

if [ "$errors" -gt 0 ]; then
  echo ""
  echo "[FAIL] Claude agent definition checks failed: $errors issue(s)."
  exit 1
fi

echo "[PASS] All claude agent definitions are consistent ($(ls "$AGENTS_DIR"/*.md | wc -l | tr -d ' ') files)."
