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

> **Note:** This means installing Kai makes it the **default persona for every Gemini CLI session**, not an opt-in agent you select. If Kai ran as a subagent instead, it wouldn't be able to call any other subagent — Gemini CLI's subagent registration doesn't allow subagent-to-subagent calls — so it has to load as the main persona via `GEMINI.md`. Contrast with OpenCode, where Kai installs as one of several selectable primary agents.

Kai has access to 21 specialized subagents:

| Tier | Agents |
|------|--------|
| **Pipeline** | engineering-team, architect, developer, reviewer, tester, docs, devops |
| **Quality** | security-auditor, performance-optimizer, integration-specialist, accessibility-expert |
| **Research** | research, fact-check |
| **Fast-Track** | explorer, doc-fixer, quick-reviewer, dependency-manager |
| **Learning** | postmortem, refactor-advisor |
| **Utility** | executive-summarizer, jira-writer |

The main agent (Kai) classifies every request using the routing table and delegates to the appropriate specialist subagent directly.

## Installation

See the root [README.md](../README.md#gemini-cli) "Gemini CLI" install section for the quick-install script and manual steps.

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
  - glob
  - list_directory
  - google_web_search
  - write_todos
temperature: 0.1
max_turns: 40
timeout_mins: 20
---
```
