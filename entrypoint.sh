#!/bin/bash
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
TELEGRAM_STARTUP_CHECK_STRICT="${TELEGRAM_STARTUP_CHECK_STRICT:-true}"

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

normalize_env_value() {
  local value="$1"
  value="$(printf "%s" "$value" | tr -d '\r')"
  value="${value%\"}"
  value="${value#\"}"
  value="${value%\'}"
  value="${value#\'}"
  printf "%s" "$value"
}

# Normalize common copy/paste mistakes in Railway env vars.
TELEGRAM_BOT_TOKEN="$(normalize_env_value "${TELEGRAM_BOT_TOKEN}")"
TELEGRAM_ALLOWED_USERS="$(normalize_env_value "${TELEGRAM_ALLOWED_USERS}" | tr -d '[:space:]')"
TELEGRAM_HOME_CHANNEL="$(normalize_env_value "${TELEGRAM_HOME_CHANNEL}" | tr -d '[:space:]')"
TELEGRAM_HOME_CHANNEL_NAME="$(normalize_env_value "${TELEGRAM_HOME_CHANNEL_NAME:-}")"
NOUS_API_KEY="$(normalize_env_value "${NOUS_API_KEY:-}")"
ANTHROPIC_API_KEY="$(normalize_env_value "${ANTHROPIC_API_KEY:-}")"

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
  echo "Telegram preflight: home_channel=${TELEGRAM_HOME_CHANNEL} allowed_users=${TELEGRAM_ALLOWED_USERS}"

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
    return 0
  else
    echo "WARNING: Telegram startup check failed."
    echo "Telegram response: $response"
    if [ "$TELEGRAM_STARTUP_CHECK_STRICT" = "true" ]; then
      echo "ERROR: Strict Telegram startup check is enabled; aborting boot."
      exit 1
    fi
    return 1
  fi
}

telegram_preflight
send_telegram_startup_check

start_dashboard_non_blocking() {
  echo "Railway PORT env: ${PORT:-not set}"
  DASHBOARD_PORT="${PORT:-9119}"

  local hermes_dir
  hermes_dir="$(python3 - << 'PY'
import os
import sys
try:
    import hermes_cli
    print(os.path.dirname(hermes_cli.__file__))
except Exception:
    sys.exit(1)
PY
  )"

  if [ -z "${hermes_dir}" ] || [ ! -d "${hermes_dir}" ]; then
    echo "WARNING: Could not resolve hermes_cli path; skipping dashboard startup."
    return 0
  fi

  if [ ! -d "${hermes_dir}/web_dist" ]; then
    echo "Dashboard frontend missing; building in best-effort mode..."
    if (cd "${hermes_dir}/web" && npm install --silent && npm run build); then
      echo "Dashboard frontend built."
    else
      echo "WARNING: Dashboard frontend build failed; continuing with gateway only."
      return 0
    fi
  fi

  echo "Starting dashboard on port ${DASHBOARD_PORT}..."
  if hermes dashboard --host 0.0.0.0 --port "${DASHBOARD_PORT}" --no-open --insecure >/proc/1/fd/1 2>/proc/1/fd/2 & then
    DASH_PID=$!
    sleep 3
    if kill -0 "${DASH_PID}" 2>/dev/null; then
      echo "Dashboard running on PID ${DASH_PID} port ${DASHBOARD_PORT}"
    else
      echo "WARNING: Dashboard exited early; continuing with gateway only."
    fi
  else
    echo "WARNING: Dashboard failed to launch; continuing with gateway only."
  fi
}

start_dashboard_non_blocking

echo "Ms. Frizzle is getting on the bus... 🚌"
exec hermes gateway run
