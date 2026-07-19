#!/usr/bin/env bash
# Validates the agent definition files in gemini/agents/ for consistency,
# Gemini CLI tool-spec compliance, and the "only Kai chains subagents" rule.
# Single source of truth for the ecosystem version is README.md (**Version:** X.Y.Z).
#
# Checks, per agent file:
#   1. Required frontmatter fields present (name, description, kind, tools,
#      temperature, max_turns, timeout_mins).
#   2. Every entry in `tools:` is a recognized Gemini CLI tool name.
#   3. The footer version ("**Version:** X.Y.Z | Platform: Gemini CLI")
#      matches the ecosystem version.
#   4. A `## Limitations` section is present.
#   5. The file documents that it cannot itself chain subagent calls
#      ("only Kai can chain subagent calls" / "only Kai can invoke").
#   6. No line describes the AGENT ITSELF invoking/calling/delegating to
#      another subagent — only Kai may be described as the invoker.
#      (Gemini CLI subagents cannot invoke other subagents; Kai, the main
#      agent, is the only one allowed to chain subagent calls.)
set -euo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTS_DIR="$ROOT_DIR/gemini/agents"
README="$ROOT_DIR/README.md"

# Recognized Gemini CLI tool names (per gemini/README.md's "Agent File Format").
VALID_TOOLS=(
  read_file
  write_file
  replace
  run_shell_command
  glob
  grep_search
  web_fetch
  list_directory
  google_web_search
  write_todos
)

if [ ! -d "$AGENTS_DIR" ]; then
  echo "[FAIL] gemini agents directory not found: $AGENTS_DIR"
  exit 1
fi

EXPECTED_VERSION="$(grep -m1 -E '^\*\*Version:\*\*' "$README" | sed -E 's/[^0-9.]//g')"
if [ -z "$EXPECTED_VERSION" ]; then
  echo "[FAIL] could not read ecosystem version from $README"
  exit 1
fi
echo "[INFO] Ecosystem version (from README): $EXPECTED_VERSION"

# Invocation-verb + @mention pattern used for the self-invocation heuristic.
INVOKE_PATTERN='(invoke|invokes|invoking|call @|calls @|delegate|hand off|handoff to|escalat)[^.]*@[a-z-]+'
# Lines matching INVOKE_PATTERN are SAFE (Kai-attributed or explicit negation)
# if they also match one of these — case-insensitive.
SAFE_EXCLUDE='kai|❌|cannot invoke|never (call|invoke)|only kai|before invoking'

errors=0
fail() { echo "[FAIL] $1"; errors=$((errors + 1)); }

for f in "$AGENTS_DIR"/*.md; do
  name="$(basename "$f")"

  # 1. Required frontmatter fields
  for field in '^name:' '^description:' '^kind:' '^tools:' '^temperature:' '^max_turns:' '^timeout_mins:'; do
    if ! grep -qE "$field" "$f"; then
      fail "$name: missing frontmatter field matching '$field'"
    fi
  done

  # 2. tools: entries must be recognized Gemini CLI tool names
  tool_lines="$(awk '/^tools:/{flag=1; next} /^[a-z_]+:/{flag=0} flag && /^[[:space:]]*-/{print}' "$f" \
    | sed -E 's/^[[:space:]]*-[[:space:]]*//')"
  while IFS= read -r tool; do
    [ -z "$tool" ] && continue
    valid=false
    for vt in "${VALID_TOOLS[@]}"; do
      if [ "$tool" = "$vt" ]; then
        valid=true
        break
      fi
    done
    if [ "$valid" = false ]; then
      fail "$name: unrecognized tool '$tool' in frontmatter (not a valid Gemini CLI tool name)"
    fi
  done <<< "$tool_lines"

  # 3. Footer version
  footer_ver="$(grep -oE '^\*\*Version:\*\* [0-9]+\.[0-9]+\.[0-9]+ \| Platform: Gemini CLI' "$f" | head -1 | sed -E 's/[^0-9.]//g' || true)"
  if [ -z "$footer_ver" ]; then
    fail "$name: no version footer found (expected '**Version:** X.Y.Z | Platform: Gemini CLI')"
  elif [ "$footer_ver" != "$EXPECTED_VERSION" ]; then
    fail "$name: footer version $footer_ver != ecosystem $EXPECTED_VERSION"
  fi

  # 4. Limitations section
  if ! grep -qE '^##.*[Ll]imitation' "$f"; then
    fail "$name: missing '## Limitations' section"
  fi

  # 5. Must document it cannot itself chain subagent calls
  if ! grep -qiE 'only kai can (chain subagent calls|invoke)' "$f"; then
    fail "$name: missing 'only Kai can chain subagent calls / invoke' disclaimer"
  fi

  # 6. No self-invocation: flag any invocation-verb+@mention line not
  #    attributed to Kai and not an explicit negation.
  violations="$(grep -inE "$INVOKE_PATTERN" "$f" | grep -viE "$SAFE_EXCLUDE" || true)"
  if [ -n "$violations" ]; then
    while IFS= read -r line; do
      fail "$name: possible self-invocation (only Kai may invoke subagents): $line"
    done <<< "$violations"
  fi
done

if [ "$errors" -gt 0 ]; then
  echo ""
  echo "[FAIL] Gemini agent definition checks failed: $errors issue(s)."
  exit 1
fi

echo "[PASS] All gemini agent definitions are consistent ($(ls "$AGENTS_DIR"/*.md | wc -l | tr -d ' ') files)."
