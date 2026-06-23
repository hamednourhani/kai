# Kai on Claude Code

To use Kai as your orchestrator on Claude Code:

## Quick Start

```bash
# Session-wide: Claude IS Kai
claude --agent kai

# Per-task: summon Kai via @-mention
@kai build an auth system

# Install agents (one-time)
cp claude/agents/*.md ~/.claude/agents/
```

## Architecture

Kai runs as a **subagent** on Claude Code. When invoked (via `--agent kai` or `@kai`), Kai orchestrates a team of 20 specialized subagents:

| Tier | Agents |
|------|--------|
| **Pipeline** | engineering-team, architect, developer, reviewer, tester, docs, devops |
| **Quality** | security-auditor, performance-optimizer, integration-specialist, accessibility-expert |
| **Research** | research, fact-check |
| **Fast-Track** | explorer, doc-fixer, quick-reviewer, dependency-manager |
| **Learning** | postmortem, refactor-advisor |
| **Utility** | executive-summarizer |

Kai uses Claude Code's `Agent` tool to spawn subagents, with full support for nested orchestration (subagents can spawn subagents in Claude Code v2.1.172+).

## Installation

Copy the agent definitions to your Claude Code user directory:

```bash
cp claude/agents/*.md ~/.claude/agents/
```

Restart Claude Code or start a new session. Agents are loaded at session start.

## Agent File Format

Each agent is a Markdown file with YAML frontmatter following Claude Code's subagent specification:

```yaml
---
name: agent-name
description: What the agent does and when to use it
tools: Read, Write, Edit, Bash, Glob, Grep, WebFetch
model: inherit
permissionMode: default
memory: user
color: cyan
---
```
