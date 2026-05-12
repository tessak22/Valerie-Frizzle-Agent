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
