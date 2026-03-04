# Stage 1: Build renovate from specified repo
FROM node:24-slim AS renovate-build
ARG RENOVATE_REPO
ARG RENOVATE_REF=main
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates && \
    corepack enable
WORKDIR /renovate
RUN git clone --depth 1 --branch $RENOVATE_REF $RENOVATE_REPO . && \
    pnpm install --frozen-lockfile --ignore-scripts && \
    pnpm run build

# Stage 2: Runtime (Rust + Node.js)
FROM rust:1.90-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates git && \
    curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

COPY --from=renovate-build /renovate /opt/renovate
ENV PATH="/opt/renovate/node_modules/.bin:$PATH"
RUN ln -s /opt/renovate/dist/renovate.js /usr/local/bin/renovate && chmod +x /usr/local/bin/renovate

WORKDIR /tests
