FROM python:3.13-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl bash git nodejs npm build-essential tini \
    && rm -rf /var/lib/apt/lists/*

# Pre-install stdio MCP servers to avoid cold-start download failures in Railway
RUN npm install -g @modelcontextprotocol/server-github

# Pin Hermes to a specific commit for reproducibility
# To upgrade: update this SHA to a newer commit from github.com/NousResearch/hermes-agent
ARG CACHE_BUST=1
ARG HERMES_COMMIT=b833d85019463b101f52667390557f3fc86a25e5
RUN curl -fsSL "https://raw.githubusercontent.com/NousResearch/hermes-agent/${HERMES_COMMIT}/scripts/install.sh" \
    | bash -s -- --skip-setup

ENV PATH="/root/.local/bin:${PATH}"

# Install web dashboard extras (web=FastAPI/Uvicorn, pty=in-browser terminal)
RUN pip install 'hermes-agent[web,pty]'

# Build the dashboard frontend
RUN HERMES_WEB=$(python3 -c "import hermes_cli, os; print(os.path.join(os.path.dirname(hermes_cli.__file__), 'web'))") && \
    cd "$HERMES_WEB" && npm install --silent && npm run build

WORKDIR /app
COPY . .

# Sanity check — fail the build early if Hermes didn't install correctly
RUN hermes --version

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 9119

# tini as PID 1: handles zombie subprocess cleanup for stdio MCP servers
# Do NOT add startCommand in railway.json — it overrides ENTRYPOINT and prevents tini from running
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/entrypoint.sh"]
