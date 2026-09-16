ARG ELIXIR_VERSION=1.18.4
ARG OTP_VERSION=28.3.1
ARG DEBIAN_VERSION=bookworm-20260202-slim
ARG NODE_VERSION=22

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

ARG NODE_VERSION

RUN apt-get update -y && \
    apt-get install -y build-essential git curl && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - && \
    apt-get install -y nodejs && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV

RUN mkdir config
COPY config/config.exs config/prod.exs config/

RUN mix deps.compile

COPY assets/package.json assets/package-lock.json ./assets/
RUN npm ci --prefix assets

COPY priv priv
COPY assets assets

COPY lib lib

# Baked into Estimate.BuildInfo at compile time; late ARG keeps deps layers cacheable.
# Pass from CI: --build-arg GIT_SHA=$CI_COMMIT_SHORT_SHA
ARG GIT_SHA=""
ENV GIT_SHA=${GIT_SHA}
RUN mix compile

RUN mix assets.deploy

COPY config/runtime.exs config/

RUN mix phx.gen.release
RUN mix release


RUN echo '#!/bin/sh\nset -e\nSKIP_RLS_ROLE=true /app/bin/migrate\nexec /app/bin/server' > /app/_build/prod/rel/estimate/bin/migrate_and_server && \
    chmod +x /app/_build/prod/rel/estimate/bin/migrate_and_server


FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
      libstdc++6 \
      openssl \
      libncurses6 \
      locales \
      ca-certificates \
      wget \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app
RUN chown nobody:nogroup /app

ENV MIX_ENV=prod

COPY --from=builder --chown=nobody:nogroup /app/_build/prod/rel/estimate ./

USER nobody

EXPOSE 4000

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD wget --spider -q http://localhost:4000/healthz || exit 1

CMD ["/app/bin/migrate_and_server"]
