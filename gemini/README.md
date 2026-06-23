# Kai on Gemini CLI

To use Kai as your orchestrator on Gemini CLI:

## Quick Start

```bash
# Kai is always active — just start Gemini CLI
gemini

# Or explicitly route to a specialist
@architect design the API
@explorer how does auth work?
```

## Architecture

Kai runs as the **main agent persona** via `GEMINI.md`. Unlike Claude Code where Kai is a subagent, on Gemini CLI Kai IS the main agent — this is because Gemini CLI subagents cannot spawn other subagents (recursion protection).

Kai has access to 20 specialized subagents:

| Tier | Agents |
|------|--------|
| **Pipeline** | engineering-team, architect, developer, reviewer, tester, docs, devops |
| **Quality** | security-auditor, performance-optimizer, integration-specialist, accessibility-expert |
| **Research** | research, fact-check |
| **Fast-Track** | explorer, doc-fixer, quick-reviewer, dependency-manager |
| **Learning** | postmortem, refactor-advisor |
| **Utility** | executive-summarizer |

The main agent (Kai) classifies every request using the routing table and delegates to the appropriate specialist subagent directly.

## Installation

Copy the agent definitions and context files to your Gemini CLI user directory:

```bash
cp gemini/agents/*.md ~/.gemini/agents/
cp gemini/KAI.md ~/.gemini/
cp gemini/GEMINI.md ~/.gemini/
```

Restart Gemini CLI or run `/memory refresh` to load the new context.

## Agent File Format

Each agent is a Markdown file with YAML frontmatter following Gemini CLI's subagent specification:

```yaml
---
name: agent_name
description: What the agent does and when to use it
kind: local
tools:
  - read_file
  - write_file
  - replace
  - run_shell_command
  - grep_search
temperature: 0.1
max_turns: 40
timeout_mins: 20
---
```
