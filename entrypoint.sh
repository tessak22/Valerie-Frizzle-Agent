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

# Copy base config — cli-config.yaml will be synced after all conditional modifications below
cp /app/hermes/config.yaml "$HERMES_HOME/config.yaml"

# Copy agent persona
cp /app/hermes/SOUL.md "$HERMES_HOME/SOUL.md"

# Empty values are intentional — Hermes ignores them, and the conditional below
# prevents GitHub MCP registration when GITHUB_TOKEN is unset
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
  echo "GitHub MCP enabled."
fi

# Sync cli-config.yaml after all conditional modifications to config.yaml
cp "$HERMES_HOME/config.yaml" "$HERMES_HOME/cli-config.yaml"

# Export platform vars so Hermes gateway can detect messaging platforms
# (sourcing .env is unsafe — values with spaces break shell parsing)
export ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
export TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
export TELEGRAM_ALLOWED_USERS="${TELEGRAM_ALLOWED_USERS:-}"
export TELEGRAM_HOME_CHANNEL="${TELEGRAM_HOME_CHANNEL:-}"
export TELEGRAM_HOME_CHANNEL_NAME="${TELEGRAM_HOME_CHANNEL_NAME:-}"
export SELAH_API_KEY="${SELAH_API_KEY:-}"

# Start web dashboard in background (port 9119, bound to all interfaces for Railway)
echo "Railway PORT env: ${PORT:-not set}"
DASHBOARD_PORT="${PORT:-9119}"

# Build dashboard frontend if not already built
HERMES_DIR="/usr/local/lib/python3.13/site-packages/hermes_cli"
if [ ! -d "${HERMES_DIR}/web_dist" ]; then
  echo "Building dashboard frontend..."
  cd "${HERMES_DIR}/web" && npm install --silent && npm run build
  echo "Dashboard frontend built."
  cd /app
fi

echo "Starting dashboard on port $DASHBOARD_PORT..."
hermes dashboard --host 0.0.0.0 --port "$DASHBOARD_PORT" --no-open --insecure &
DASH_PID=$!
sleep 3
if kill -0 $DASH_PID 2>/dev/null; then
  echo "Dashboard running on PID $DASH_PID port $DASHBOARD_PORT"
else
  echo "Dashboard failed to start"
fi

echo "Ms. Frizzle is getting on the bus... 🚌"
exec hermes gateway run
