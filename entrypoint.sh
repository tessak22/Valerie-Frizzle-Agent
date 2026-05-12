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
