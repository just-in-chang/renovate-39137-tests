# Stage 1: Install renovate dependencies (no build needed -- tsx runs source directly)
FROM node:24-slim AS renovate-deps
ARG RENOVATE_REPO
ARG RENOVATE_REF=main
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates && corepack enable
WORKDIR /renovate
RUN git clone --depth 1 --branch $RENOVATE_REF $RENOVATE_REPO . && \
    pnpm install --frozen-lockfile --ignore-scripts && \
    pnpm run generate

# Stage 2: Runtime (Rust + Node.js)
FROM rust:1.90-slim

# Install Node.js and git
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates git && \
    curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# Install tsx globally for running TypeScript directly
RUN npm install -g tsx

# Copy renovate with installed dependencies (no build step needed)
COPY --from=renovate-deps /renovate /opt/renovate

# Copy e2e test files (fixtures include committed Cargo.lock files)
WORKDIR /tests
COPY fixtures/ ./fixtures/
COPY test.sh ./test.sh

RUN chmod +x /tests/test.sh
CMD ["./test.sh"]
