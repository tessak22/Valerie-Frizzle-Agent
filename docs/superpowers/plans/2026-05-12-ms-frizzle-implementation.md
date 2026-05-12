# Ms. Frizzle Agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a deployable Hermes agent named Ms. Frizzle that connects to Selah via MCP, runs on Railway, and can be deployed by non-technical parents via a one-click Railway template.

**Architecture:** Single Hermes profile deployed as a Docker container on Railway. Selah MCP is the primary data layer (HTTP, bearer token). GitHub MCP is optional, activated only when `GITHUB_TOKEN` is set. Telegram is the messaging interface. Volume at `/root/.hermes` persists memory and sessions across deploys.

**Tech Stack:** Hermes (NousResearch), Docker, Railway, Telegram, Selah MCP (HTTP), GitHub MCP (stdio via npx), tini, bash

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `hermes/SOUL.md` | Move from `SOUL.md` | Agent persona |
| `hermes/config.yaml` | Create | Hermes config + MCP wiring |
| `entrypoint.sh` | Create | Container startup, config hydration, conditional GitHub MCP |
| `Dockerfile` | Create | Container image: Hermes install, tini, pre-installed MCP packages |
| `railway.json` | Create | Railway template schema with env var prompts |
| `.env.example` | Create | Documents all env vars with descriptions |
| `.gitignore` | Update | Ensure `.env` and secrets are excluded |
| `README.md` | Create | Parent-friendly setup guide + Railway deploy button |

---

## Task 1: Move SOUL.md and scaffold hermes/ directory

**Files:**
- Move: `SOUL.md` → `hermes/SOUL.md`
- Modify: `.gitignore`

- [ ] **Step 1: Create hermes/ directory and move SOUL.md**

```bash
mkdir -p hermes
git mv SOUL.md hermes/SOUL.md
```

- [ ] **Step 2: Verify move**

```bash
ls hermes/
```
Expected output: `SOUL.md`

- [ ] **Step 3: Update .gitignore**

Replace the existing `.gitignore` with:

```gitignore
# Dependencies
node_modules/
.pnp
.pnp.js

# Environment — never commit real secrets
.env
.env.local
.env.*.local

# Build output
dist/
build/
.next/
out/

# Logs
*.log
npm-debug.log*

# Claude Code local settings
.claude/settings.local.json

# OS
.DS_Store

# Hermes runtime data (if running locally)
.hermes/
```

- [ ] **Step 4: Commit**

```bash
git add .gitignore
git commit -m "chore: move SOUL.md into hermes/ directory, update .gitignore"
```

---

## Task 2: Hermes configuration

**Files:**
- Create: `hermes/config.yaml`

- [ ] **Step 1: Create hermes/config.yaml**

```yaml
model:
  default: "anthropic/claude-sonnet-4-6"
  provider: "anthropic"

agent:
  max_turns: 60
  reasoning_effort: "medium"
  api_max_retries: 1

memory:
  memory_enabled: true
  user_profile_enabled: true
  memory_char_limit: 4000
  user_char_limit: 2000

group_sessions_per_user: true

session_reset:
  mode: both
  idle_minutes: 1440
  at_hour: 4

tool_loop_guardrails:
  warnings_enabled: true
  hard_stop_enabled: true

platform_toolsets:
  telegram: [hermes-telegram, session_search]

# IMPORTANT: top-level key must be mcp_servers — NOT mcp.servers (silent failure if wrong)
mcp_servers:
  selah:
    url: "https://selahlearn.com/mcp/selah"
    headers:
      Authorization: "Bearer ${SELAH_API_KEY}"

# GitHub MCP block is appended conditionally by entrypoint.sh when GITHUB_TOKEN is set
```

- [ ] **Step 2: Validate YAML syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('hermes/config.yaml')); print('YAML valid')"
```
Expected: `YAML valid`

- [ ] **Step 3: Commit**

```bash
git add hermes/config.yaml
git commit -m "feat: add Hermes config with Selah MCP"
```

---

## Task 3: entrypoint.sh

**Files:**
- Create: `entrypoint.sh`

The entrypoint runs on every container start. It hydrates `~/.hermes/` from the repo's `hermes/` directory, writes all secrets to `~/.hermes/.env`, and conditionally appends the GitHub MCP block to config when `GITHUB_TOKEN` is set.

- [ ] **Step 1: Create entrypoint.sh**

```bash
#!/bin/bash
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"

# Create directories Hermes expects (volume is empty on first deploy)
mkdir -p "$HERMES_HOME/memories" \
         "$HERMES_HOME/skills" \
         "$HERMES_HOME/sessions" \
         "$HERMES_HOME/cron" \
         "$HERMES_HOME/cron/output" \
         "$HERMES_HOME/hooks" \
         "$HERMES_HOME/logs"

# Copy config to both filenames — CLI reads cli-config.yaml, gateway reads config.yaml
cp /app/hermes/config.yaml "$HERMES_HOME/cli-config.yaml"
cp /app/hermes/config.yaml "$HERMES_HOME/config.yaml"

# Copy agent persona
cp /app/hermes/SOUL.md "$HERMES_HOME/SOUL.md"

# Write all secrets to ~/.hermes/.env — Hermes reads from here, not system env
cat > "$HERMES_HOME/.env" << EOF
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN:-}
TELEGRAM_ALLOWED_USERS=${TELEGRAM_ALLOWED_USERS:-}
TELEGRAM_HOME_CHANNEL=${TELEGRAM_HOME_CHANNEL:-}
TELEGRAM_HOME_CHANNEL_NAME=${TELEGRAM_HOME_CHANNEL_NAME:-}
SELAH_API_KEY=${SELAH_API_KEY:-}
GITHUB_TOKEN=${GITHUB_TOKEN:-}
EOF
chmod 600 "$HERMES_HOME/.env"

# Conditionally append GitHub MCP block when GITHUB_TOKEN is set
if [ -n "${GITHUB_TOKEN:-}" ]; then
  cat >> "$HERMES_HOME/config.yaml" << 'GITHUBBLOCK'

  github:
    command: "npx"
    args: ["-y", "@modelcontextprotocol/server-github"]
    env:
      GITHUB_PERSONAL_ACCESS_TOKEN: "${GITHUB_TOKEN}"
    tools:
      include: [create_issue, list_issues, get_issue, search_issues]
GITHUBBLOCK
  # Mirror to cli-config.yaml as well
  cp "$HERMES_HOME/config.yaml" "$HERMES_HOME/cli-config.yaml"
  echo "GitHub MCP enabled."
fi

echo "Ms. Frizzle is getting on the bus... 🚌"
exec hermes gateway run
```

- [ ] **Step 2: Make executable and validate bash syntax**

```bash
chmod +x entrypoint.sh
bash -n entrypoint.sh && echo "Syntax OK"
```
Expected: `Syntax OK`

- [ ] **Step 3: Commit**

```bash
git add entrypoint.sh
git commit -m "feat: add entrypoint.sh with conditional GitHub MCP support"
```

---

## Task 4: Dockerfile

**Files:**
- Create: `Dockerfile`

Pins Hermes to a specific commit for reproducibility. Pre-installs GitHub MCP npm package to avoid cold-start download failures. Uses tini as PID 1 for zombie subprocess cleanup.

- [ ] **Step 1: Create Dockerfile**

```dockerfile
FROM python:3.13-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl bash git nodejs npm build-essential tini \
    && rm -rf /var/lib/apt/lists/*

# Pre-install stdio MCP servers to avoid cold-start download failures in Railway
RUN npm install -g @modelcontextprotocol/server-github

# Pin Hermes to a specific commit for reproducibility
# To upgrade: update this SHA to a newer commit from github.com/NousResearch/hermes-agent
ARG HERMES_COMMIT=c23a87bc163b188abc7e40fbdccf07a9739231c3
RUN curl -fsSL "https://raw.githubusercontent.com/NousResearch/hermes-agent/${HERMES_COMMIT}/scripts/install.sh" \
    | bash -s -- --skip-setup

ENV PATH="/root/.local/bin:${PATH}"

WORKDIR /app
COPY . .

# Sanity check — fail the build early if Hermes didn't install correctly
RUN hermes --version

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8443

# tini as PID 1: handles zombie subprocess cleanup for stdio MCP servers
# Do NOT add startCommand in railway.json — it overrides ENTRYPOINT and prevents tini from running
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/entrypoint.sh"]
```

- [ ] **Step 2: Build the image locally to verify**

```bash
docker build -t ms-frizzle-test .
```
Expected: Build completes, final line shows `hermes --version` output (e.g. `hermes 0.x.x`)

- [ ] **Step 3: Commit**

```bash
git add Dockerfile
git commit -m "feat: add Dockerfile with Hermes, tini, and GitHub MCP pre-installed"
```

---

## Task 5: Railway configuration

**Files:**
- Create: `railway.json`

No `startCommand` — Railway must use the Docker ENTRYPOINT so tini runs as PID 1.

- [ ] **Step 1: Create railway.json**

```json
{
  "$schema": "https://railway.app/railway.schema.json",
  "build": {
    "builder": "DOCKERFILE"
  },
  "deploy": {
    "restartPolicyType": "ON_FAILURE",
    "restartPolicyMaxRetries": 10
  },
  "environments": {
    "production": {
      "variables": {
        "ANTHROPIC_API_KEY": {
          "description": "Your Anthropic API key — get one at console.anthropic.com"
        },
        "TELEGRAM_BOT_TOKEN": {
          "description": "Your Telegram bot token — create a bot via @BotFather"
        },
        "TELEGRAM_ALLOWED_USERS": {
          "description": "Your Telegram user ID — message @userinfobot to find it"
        },
        "TELEGRAM_HOME_CHANNEL": {
          "description": "Your Telegram user ID again (same value — sets your DM as home)"
        },
        "TELEGRAM_HOME_CHANNEL_NAME": {
          "description": "Your name or a label for the DM (e.g. 'Mom DM')"
        },
        "SELAH_API_KEY": {
          "description": "Your Selah API key — find it in your Selah account settings"
        }
      }
    }
  }
}
```

- [ ] **Step 2: Validate JSON**

```bash
python3 -c "import json; json.load(open('railway.json')); print('JSON valid')"
```
Expected: `JSON valid`

- [ ] **Step 3: Commit**

```bash
git add railway.json
git commit -m "feat: add Railway template config with env var prompts"
```

---

## Task 6: .env.example

**Files:**
- Create: `.env.example`

Documents every env var. Open-sourcers copy this to `.env` for local testing.

- [ ] **Step 1: Create .env.example**

```bash
# ─── Required ────────────────────────────────────────────────────────────────

# Anthropic API key — console.anthropic.com
ANTHROPIC_API_KEY=sk-ant-...

# Telegram bot token — create a bot via @BotFather on Telegram
TELEGRAM_BOT_TOKEN=

# Your Telegram user ID — message @userinfobot to find it
TELEGRAM_ALLOWED_USERS=

# Same as TELEGRAM_ALLOWED_USERS for a personal DM setup
TELEGRAM_HOME_CHANNEL=

# A display label for your home DM (e.g. "Mom DM")
TELEGRAM_HOME_CHANNEL_NAME=

# Selah API key — find it in your Selah account settings at selahlearn.com
SELAH_API_KEY=

# ─── Optional ─────────────────────────────────────────────────────────────────

# GitHub Personal Access Token — only needed if you're a Selah developer
# Create one at github.com/settings/tokens with Issues read/write on your Selah repo
# When set, Ms. Frizzle can file GitHub issues for missing Selah features
GITHUB_TOKEN=
```

- [ ] **Step 2: Verify .env is gitignored**

```bash
git check-ignore -v .env
```
Expected output includes `.env` — if nothing prints, `.gitignore` is missing the `.env` entry (fix it before continuing)

- [ ] **Step 3: Commit**

```bash
git add .env.example
git commit -m "docs: add .env.example with all environment variables documented"
```

---

## Task 7: README

**Files:**
- Create: `README.md`

Parent-friendly. No jargon. Three sections. Deploy button at the top. The Railway template URL will be a placeholder until the template is published — update it after the first Railway deploy.

- [ ] **Step 1: Create README.md**

````markdown
# Ms. Frizzle 🚌

**Your AI homeschool teacher.** Ms. Frizzle connects to [Selah](https://selahlearn.com) to help you plan lessons, track progress, document curriculum, and make sure your student's education exceeds state standards — so they're ready for wherever life takes them.

Talk to her on Telegram. She handles the rest.

[![Deploy on Railway](https://railway.app/button.svg)](https://railway.app/new/template?template=https://github.com/tessak22/Valerie-Frizzle-Agent)

---

## Deploy in 5 minutes

1. Click **Deploy on Railway** above
2. Fill in your API keys when prompted (see [Getting your keys](#getting-your-keys) below)
3. Railway builds and starts Ms. Frizzle automatically
4. Add the persistent volume: in your Railway service settings, add a volume mounted at `/root/.hermes`
5. Message your Telegram bot — she'll respond

That's it. No code, no terminal.

---

## Getting your keys

**Anthropic API key** (`ANTHROPIC_API_KEY`)
Go to [console.anthropic.com](https://console.anthropic.com), create an account, and generate an API key.

**Telegram bot** (`TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS`, `TELEGRAM_HOME_CHANNEL`)
1. Open Telegram and message [@BotFather](https://t.me/BotFather)
2. Send `/newbot` and follow the prompts — copy the token it gives you
3. Message [@userinfobot](https://t.me/userinfobot) — copy your numeric user ID
4. Use the token for `TELEGRAM_BOT_TOKEN` and your user ID for both `TELEGRAM_ALLOWED_USERS` and `TELEGRAM_HOME_CHANNEL`

**Selah API key** (`SELAH_API_KEY`)
Log in to [selahlearn.com](https://selahlearn.com), go to your account settings, and copy your API key.

---

## About Ms. Frizzle

Built with [Hermes](https://github.com/NousResearch/hermes-agent) by NousResearch and powered by [Selah](https://selahlearn.com). Ms. Frizzle is open-source — deploy your own, customize her, share her with other homeschool families.

*"Take chances, make mistakes, get messy!"*
````

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add parent-friendly README with Railway deploy button"
```

---

## Task 8: Push to GitHub

- [ ] **Step 1: Push all commits**

```bash
git push origin main
```

- [ ] **Step 2: Verify repo on GitHub**

Visit `https://github.com/tessak22/Valerie-Frizzle-Agent` and confirm:
- `hermes/SOUL.md` is present
- `hermes/config.yaml` is present
- `Dockerfile`, `entrypoint.sh`, `railway.json`, `.env.example`, `README.md` are all present
- `.env` does NOT appear (confirm gitignore is working)
- README renders with the Railway deploy button

- [ ] **Step 3: Do the initial Railway deploy and update the template URL**

```bash
railway init
railway up --detach
railway volume add --mount-path /root/.hermes
railway up --detach
```

Once the Railway template is published, update the deploy button URL in `README.md`:
```markdown
[![Deploy on Railway](https://railway.app/button.svg)](https://railway.app/new/template?template=https://github.com/tessak22/Valerie-Frizzle-Agent)
```
This URL is already correct if the repo is public — Railway reads it directly from GitHub.

- [ ] **Step 4: Final commit if README URL changed**

```bash
git add README.md
git commit -m "docs: update Railway template URL"
git push origin main
```

---

## Known Deferred Items

- **Selah MCP auth is broken** — `SELAH_API_KEY` is wired in but will return auth errors until fixed in the Selah codebase. Ms. Frizzle will start and respond on Telegram; Selah tools will fail gracefully until the fix lands.
- **Selah MCP tool filtering** — Once Selah auth is working, audit which tools Ms. Frizzle actually needs and add `tools: include: [...]` to the `selah` MCP block in `hermes/config.yaml` to reduce token usage.
- **Railway template registration** — After first deploy, register the repo as an official Railway template for the one-click deploy button to work from Railway's template gallery.
