# Custom OpenClaw Dockerfile for Railway
# Adds Python 3 + exchangelib for EWS email integration

FROM node:22-bookworm AS base

# Install Bun (required for build scripts)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

WORKDIR /app

ARG OPENCLAW_DOCKER_APT_PACKAGES=""
RUN if [ -n "$OPENCLAW_DOCKER_APT_PACKAGES" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $OPENCLAW_DOCKER_APT_PACKAGES && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    fi

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY ui/package.json ./ui/package.json
COPY patches ./patches
COPY scripts ./scripts

RUN pnpm install --frozen-lockfile

COPY . .
RUN pnpm build
# Force pnpm for UI build (Bun may fail on ARM/Synology architectures)
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build

FROM node:22-bookworm-slim AS production

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv python3-dev \
    build-essential libxml2-dev libxslt1-dev libkrb5-dev \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/exchangelib-env \
    && /opt/exchangelib-env/bin/pip install --no-cache-dir exchangelib

ENV PATH="/opt/exchangelib-env/bin:$PATH"

RUN corepack enable && corepack prepare pnpm@latest --activate

WORKDIR /app

COPY --from=base /app/dist ./dist
COPY --from=base /app/ui/dist ./ui/dist
COPY --from=base /app/node_modules ./node_modules
COPY --from=base /app/package.json ./
COPY --from=base /app/openclaw.mjs ./
COPY --from=base /app/skills ./skills
COPY --from=base /app/extensions ./extensions

RUN mkdir -p /data && chown node:node /data
RUN chown -R node:node /app
USER node

ENV NODE_ENV=production
ENV OPENCLAW_STATE_DIR=/data
ENV PORT=3000

EXPOSE 3000

CMD ["node", "openclaw.mjs", "gateway", "--allow-unconfigured", "--port", "3000"]
