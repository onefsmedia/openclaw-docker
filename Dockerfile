# syntax=docker/dockerfile:1

# ─────────────────────────────────────────────
#  OpenClaw Gateway — Docker image
#  Node 22 LTS, Python 3, gog CLI, wacli
# ─────────────────────────────────────────────
FROM node:22-slim

LABEL maintainer="OpenClaw Docker Setup"
LABEL description="OpenClaw gateway with WhatsApp, Google Sheets, and ClickUp integration"

# ── System dependencies ───────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    curl \
    wget \
    ca-certificates \
    dnsutils \
    git \
    && rm -rf /var/lib/apt/lists/*

# ── OpenClaw (npm global) ─────────────────────
ARG OPENCLAW_VERSION=latest
RUN npm install -g openclaw@${OPENCLAW_VERSION} \
    && openclaw --version

# ── gog CLI (Google Workspace CLI) ───────────
# Downloads the Linux binary from GitHub releases.
# Build arg lets you pin a specific version.
ARG GOG_VERSION=0.12.0
RUN set -e; \
    ARCH=$(uname -m); \
    case "$ARCH" in \
        x86_64)  GOARCH=amd64 ;; \
        aarch64) GOARCH=arm64 ;; \
        *)        GOARCH=amd64 ;; \
    esac; \
    URL="https://github.com/steipete/gogcli/releases/download/v${GOG_VERSION}/gog_linux_${GOARCH}"; \
    echo "Downloading gog from $URL"; \
    wget -q "$URL" -O /usr/local/bin/gog \
        && chmod +x /usr/local/bin/gog \
        && echo "gog installed: $(gog --version)" \
    || echo "WARNING: gog binary could not be downloaded — Google Sheets features require manual setup"

# ── wacli (WhatsApp CLI) ──────────────────────
ARG WACLI_VERSION=0.2.0
RUN set -e; \
    ARCH=$(uname -m); \
    case "$ARCH" in \
        x86_64)  GOARCH=amd64 ;; \
        aarch64) GOARCH=arm64 ;; \
        *)        GOARCH=amd64 ;; \
    esac; \
    URL="https://github.com/steipete/wacli/releases/download/v${WACLI_VERSION}/wacli_linux_${GOARCH}"; \
    echo "Downloading wacli from $URL"; \
    wget -q "$URL" -O /usr/local/bin/wacli \
        && chmod +x /usr/local/bin/wacli \
        && echo "wacli installed: $(wacli --version)" \
    || echo "WARNING: wacli binary could not be downloaded — WhatsApp history search requires manual setup"

# ── Runtime environment ───────────────────────
# OpenClaw reads OPENCLAW_STATE_DIR to find its config/credentials
ENV OPENCLAW_STATE_DIR=/data
ENV NODE_ENV=production

# ── Data volume ───────────────────────────────
# Create the mount point and hand it to the non-root user before VOLUME
# so Docker initialises named volumes with the correct ownership.
RUN mkdir -p /data && chown node:node /data

VOLUME ["/data"]

# ── Gateway port ──────────────────────────────
EXPOSE 9090

# ── Entrypoint (copy + chmod as root, before dropping privileges) ─────────────
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# ── Drop privileges — run as non-root (node = uid 1000) ──────────────────────
USER node

ENTRYPOINT ["/entrypoint.sh"]
