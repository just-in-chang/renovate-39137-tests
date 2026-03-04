# Stage 1: Install renovate from specified repo
FROM node:24-slim AS renovate-deps
ARG RENOVATE_REPO
ARG RENOVATE_REF=main
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates && \
    corepack enable
WORKDIR /renovate
RUN git clone --depth 1 --branch $RENOVATE_REF $RENOVATE_REPO . && \
    pnpm install --frozen-lockfile --ignore-scripts && \
    pnpm run generate

# Stage 2: Runtime (Rust + Node.js)
FROM rust:1.90-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates git && \
    curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*
RUN npm install -g tsx

COPY --from=renovate-deps /renovate /opt/renovate

WORKDIR /tests
COPY workspace/ ./workspace/
COPY test.sh ./test.sh

RUN chmod +x /tests/test.sh
CMD ["./test.sh"]
