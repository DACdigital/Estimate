# =============================================================================
# Build stage
# =============================================================================
ARG ELIXIR_VERSION=1.18.4
ARG OTP_VERSION=28.3.1
ARG DEBIAN_VERSION=bookworm-20260202-slim
ARG NODE_VERSION=22

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

ARG NODE_VERSION

# Install build dependencies (gcc/make for argon2, git for deps, curl for node)
RUN apt-get update -y && \
    apt-get install -y build-essential git curl && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Node.js (for npm dependencies in assets)
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - && \
    apt-get install -y nodejs && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV=prod

# Install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV

# Copy compile-time config
RUN mkdir config
COPY config/config.exs config/prod.exs config/

# Compile dependencies
RUN mix deps.compile

# Install npm dependencies
COPY assets/package.json assets/package-lock.json ./assets/
RUN npm ci --prefix assets

# Copy priv and assets
COPY priv priv
COPY assets assets

# Copy application code and compile (generates colocated hooks)
COPY lib lib
RUN mix compile

# Build assets (after compile, so colocated hooks exist)
RUN mix assets.deploy

# Copy runtime config
COPY config/runtime.exs config/

# Generate release files (includes migrate script for ecto)
RUN mix phx.gen.release
RUN mix release

# Create startup script that runs migrations before server
# SKIP_RLS_ROLE=true disables SET ROLE estimate_app so migrations run as superuser
RUN echo '#!/bin/sh\nSKIP_RLS_ROLE=true /app/bin/migrate\nexec /app/bin/server' > /app/_build/prod/rel/estimate/bin/migrate_and_server && \
    chmod +x /app/_build/prod/rel/estimate/bin/migrate_and_server

# =============================================================================
# Runtime stage
# =============================================================================
FROM ${RUNNER_IMAGE}

# Install runtime dependencies
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
      libstdc++6 \
      openssl \
      libncurses6 \
      locales \
      ca-certificates \
      wget \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Set locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app
RUN chown nobody:nogroup /app

ENV MIX_ENV=prod

# Copy release from builder
COPY --from=builder --chown=nobody:nogroup /app/_build/prod/rel/estimate ./

USER nobody

EXPOSE 4000

# Healthcheck (--spider accepts any response, including 302 redirects)
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --spider -q http://localhost:4000/ || exit 1

# Available commands:
#   /app/bin/server  - start the Phoenix server
#   /app/bin/migrate - run database migrations
#   /app/bin/estimate remote - connect to running node
CMD ["/app/bin/migrate_and_server"]
