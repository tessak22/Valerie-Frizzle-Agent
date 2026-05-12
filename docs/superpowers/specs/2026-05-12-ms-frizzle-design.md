# Ms. Frizzle Agent — Design Spec

**Date:** 2026-05-12  
**Status:** Approved

---

## Overview

Ms. Frizzle (Professor Valerie Felicity Frizzle, PhD) is a Hermes-based AI homeschool teacher agent that connects to Selah via MCP. Parents interact with her over Telegram. She handles lesson planning, curriculum, grade review, transcript monitoring, state standards compliance, and activity planning — documenting everything back to Selah so students have a complete, Harvard-ready homeschool record.

This repo is open-sourced as a marketing channel for Selah. The agent IS the interface; the Selah UI is read-only. GitHub issue creation is an optional add-on for Selah developers.

---

## Architecture

**Option A + C:** Single Hermes profile, single Railway service, Railway one-click template for parent-friendly deployment.

- One bot per family, multiple students handled via Hermes `group_sessions_per_user: true`
- Telegram as the messaging interface
- Selah MCP as the primary data layer (HTTP, bearer token auth)
- GitHub MCP as an optional add-on (only active when `GITHUB_TOKEN` + `GITHUB_ENABLED=true`)

---

## Repo Structure

```
ms-frizzle-agent/
├── Dockerfile
├── entrypoint.sh
├── railway.json
├── .env.example
├── .gitignore
├── README.md
├── hermes/
│   ├── SOUL.md           ← agent identity (already written)
│   └── config.yaml       ← Hermes config + MCP wiring
└── docs/
    └── superpowers/
        └── specs/
            └── 2026-05-12-ms-frizzle-design.md
```

---

## Hermes Configuration (`hermes/config.yaml`)

Single source of truth. Entrypoint copies it to both `cli-config.yaml` and `config.yaml` at startup (Gotcha 4 from Railway guide).

```yaml
model:
  default: "anthropic/claude-sonnet-4-6"
  provider: "anthropic"

agent:
  max_turns: 60
  reasoning_effort: medium
  api_max_retries: 1

memory:
  memory_enabled: true
  user_profile_enabled: true

group_sessions_per_user: true

mcp_servers:
  selah:
    url: "https://selahlearn.com/mcp/selah"
    headers:
      Authorization: "Bearer ${SELAH_API_KEY}"

  # github block is written conditionally by entrypoint.sh
  # only present when GITHUB_TOKEN env var is set
```

---

## Dockerfile

- Base: `python:3.13-slim`
- Installs: `curl bash git nodejs npm build-essential tini`
- Pre-installs `@modelcontextprotocol/server-github` via npm (avoids cold-start failures)
- Pins Hermes to a specific commit SHA for reproducibility
- Uses `tini` as PID 1 (zombie subprocess cleanup for stdio MCP servers)
- No `startCommand` in `railway.json` — Railway must use ENTRYPOINT directly so tini runs

---

## entrypoint.sh

On every container start:
1. Creates all Hermes home directories (volume may be empty on first deploy)
2. Copies `hermes/config.yaml` to both `~/.hermes/cli-config.yaml` and `~/.hermes/config.yaml`
3. Copies `hermes/SOUL.md` to `~/.hermes/SOUL.md`
4. Writes all secrets to `~/.hermes/.env` with `chmod 600` (Hermes reads from here, not system env)
5. If `GITHUB_TOKEN` is set, appends the GitHub MCP block to `config.yaml` dynamically
5. Runs `exec hermes gateway run` (not `gateway start` — that's for host machines only)

Volume mounted at `/root/.hermes` (full Hermes home, not a subdirectory) for persistence across deploys.

---

## Railway Template (`railway.json`)

Includes full template schema with env var descriptions so Railway prompts parents on one-click deploy. No CLI required for parents.

**Required env vars (prompted on deploy):**
| Variable | Description |
|---|---|
| `ANTHROPIC_API_KEY` | From console.anthropic.com |
| `TELEGRAM_BOT_TOKEN` | From @BotFather on Telegram |
| `TELEGRAM_ALLOWED_USERS` | Telegram user ID (from @userinfobot) |
| `TELEGRAM_HOME_CHANNEL` | Same as user ID for DM setup |
| `SELAH_API_KEY` | From Selah account settings |

**Optional env vars:**
| Variable | Description |
|---|---|
| `GITHUB_TOKEN` | PAT with Issues access (Selah devs only) |
| `GITHUB_ENABLED` | Set `true` to activate GitHub MCP |

---

## README Structure

Three sections, no jargon:
1. **What this is** — one paragraph
2. **Deploy in 5 minutes** — click button → fill in 5 fields → message your bot
3. **Getting your API keys** — where to find each one

Deploy button at the top linking to the Railway template.

---

## Key Decisions

- **Selah MCP auth is broken** at time of writing — `SELAH_API_KEY` is stubbed in, will be wired properly once fixed in Selah codebase
- **GitHub MCP is opt-in** — not relevant for families, only for Selah developers filing feature requests
- **No multi-profile setup** — Hermes handles multi-student per family natively
- **SOUL.md is already written** — persona fully defined, committed to repo
