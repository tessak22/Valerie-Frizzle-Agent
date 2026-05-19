#!/bin/bash
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"

if [ -z "${TELEGRAM_BOT_TOKEN:-}" ]; then
  echo "ERROR: TELEGRAM_BOT_TOKEN is required."
  exit 1
fi

if [ -z "${TELEGRAM_ALLOWED_USERS:-}" ]; then
  echo "ERROR: TELEGRAM_ALLOWED_USERS is required."
  exit 1
fi

if [ -z "${TELEGRAM_HOME_CHANNEL:-}" ]; then
  echo "ERROR: TELEGRAM_HOME_CHANNEL is required."
  exit 1
fi

if [ -z "${NOUS_API_KEY:-}" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "ERROR: Set at least one model key (NOUS_API_KEY or ANTHROPIC_API_KEY)."
  exit 1
fi

# Normalize common copy/paste mistakes in numeric/id env vars.
TELEGRAM_ALLOWED_USERS="$(echo "${TELEGRAM_ALLOWED_USERS}" | tr -d '[:space:]')"
TELEGRAM_HOME_CHANNEL="$(echo "${TELEGRAM_HOME_CHANNEL}" | tr -d '[:space:]')"

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

# Keep Hermes responsive even when only Anthropic is configured.
# Recent config defaults to Nous; Railway template historically only asked for Anthropic.
if [ -z "${NOUS_API_KEY:-}" ] && [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  echo "NOUS_API_KEY not set; switching default model provider to Anthropic."
  sed -i 's/default: "Hermes-4-70B"/default: "claude-sonnet-4-6"/' "$HERMES_HOME/config.yaml"
  sed -i 's/provider: "nous-api"/provider: "anthropic"/' "$HERMES_HOME/config.yaml"
fi

# Copy agent persona
cp /app/hermes/SOUL.md "$HERMES_HOME/SOUL.md"

# Empty values are intentional — Hermes ignores them, and the conditional below
# prevents GitHub MCP registration when GITHUB_TOKEN is unset
# Write all secrets to ~/.hermes/.env — Hermes reads from here, not system env
cat > "$HERMES_HOME/.env" << EOF
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}
NOUS_API_KEY=${NOUS_API_KEY:-}
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
export NOUS_API_KEY="${NOUS_API_KEY:-}"
export TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
export TELEGRAM_ALLOWED_USERS="${TELEGRAM_ALLOWED_USERS:-}"
export TELEGRAM_HOME_CHANNEL="${TELEGRAM_HOME_CHANNEL:-}"
export TELEGRAM_HOME_CHANNEL_NAME="${TELEGRAM_HOME_CHANNEL_NAME:-}"
export SELAH_API_KEY="${SELAH_API_KEY:-}"

telegram_api_call() {
  local method="$1"
  shift
  curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/${method}" \
    --max-time 15 \
    "$@" || true
}

telegram_preflight() {
  local me_response
  me_response="$(telegram_api_call getMe)"
  if echo "$me_response" | grep -q '"ok":true'; then
    echo "Telegram token validated via getMe."
  else
    echo "ERROR: Telegram getMe failed. Check TELEGRAM_BOT_TOKEN."
    echo "Telegram response: $me_response"
    exit 1
  fi

  local webhook_response
  webhook_response="$(telegram_api_call getWebhookInfo)"
  if echo "$webhook_response" | grep -q '"ok":true'; then
    local webhook_url
    webhook_url="$(echo "$webhook_response" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')"
    if [ -n "$webhook_url" ]; then
      echo "Telegram webhook is set; clearing webhook to allow polling mode."
      local delete_response
      delete_response="$(telegram_api_call deleteWebhook --data-urlencode "drop_pending_updates=false")"
      if echo "$delete_response" | grep -q '"ok":true'; then
        echo "Telegram webhook cleared."
      else
        echo "WARNING: Failed to clear Telegram webhook."
        echo "Telegram response: $delete_response"
      fi
    else
      echo "Telegram webhook is not set; polling mode should be available."
    fi
  else
    echo "WARNING: Telegram getWebhookInfo failed."
    echo "Telegram response: $webhook_response"
  fi
}

# Send a lightweight startup heartbeat to verify Telegram delivery path.
# This must never block startup.
send_telegram_startup_check() {
  local channel_label
  channel_label="${TELEGRAM_HOME_CHANNEL_NAME:-Home Channel}"

  local startup_text
  startup_text="Ms. Frizzle startup check: online and ready on ${channel_label}."

  local response
  response=$(telegram_api_call sendMessage \
    --data-urlencode "chat_id=${TELEGRAM_HOME_CHANNEL}" \
    --data-urlencode "text=${startup_text}" \
    --data-urlencode "disable_notification=true")

  if echo "$response" | grep -q '"ok":true'; then
    echo "Telegram startup check delivered."
  else
    echo "WARNING: Telegram startup check failed."
    echo "Telegram response: $response"
  fi
}

telegram_preflight
send_telegram_startup_check

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
