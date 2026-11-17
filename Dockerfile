# syntax=docker/dockerfile:1
# Gemfile.lock only carries x86_64-linux native gems (sqlite-vec, tailwindcss-ruby),
# so build with: docker build --platform linux/amd64 .
ARG RUBY_VERSION=4.0.9
ARG NODE_VERSION=24.22.2

# ── node ──────────────────────────────────────────────────────────────────────
# Official image as the Node source; avoids piping a setup script into bash.
FROM node:${NODE_VERSION}-slim AS node

# ── base ──────────────────────────────────────────────────────────────────────
FROM ruby:${RUBY_VERSION}-slim AS base

WORKDIR /app

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
      libsqlite3-0 sqlite3 libjemalloc2 \
    && ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so \
    && rm -rf /var/lib/apt/lists/*

ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_PATH="/usr/local/bundle" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# ── build ──────────────────────────────────────────────────────────────────────
FROM base AS build

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
      build-essential cmake git pkg-config libssl-dev libyaml-dev libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

# Node + corepack (needed for esbuild); pnpm is pinned by package.json "packageManager"
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules/corepack /usr/local/lib/node_modules/corepack
RUN ln -s /usr/local/lib/node_modules/corepack/dist/corepack.js /usr/local/bin/corepack \
    && corepack enable pnpm

ENV HUSKY=0 \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0

# Gems
COPY Gemfile Gemfile.lock ./
RUN bundle install \
    && rm -rf ~/.bundle "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

# JS packages
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN corepack install && pnpm install --frozen-lockfile

# App source
COPY . .

# Compile assets (jsbundling and tailwindcss-rails hook into assets:precompile),
# then drop build-only files from /app
RUN SECRET_KEY_BASE_DUMMY=1 bundle exec rails assets:precompile \
    && rm -rf node_modules tmp/cache

# ── production ─────────────────────────────────────────────────────────────────
FROM base AS production

RUN useradd --create-home --uid 1000 rails

COPY --from=build --chown=rails:rails /usr/local/bundle /usr/local/bundle
COPY --from=build --chown=rails:rails /app /app

USER rails

EXPOSE 3000

HEALTHCHECK --interval=10s --timeout=3s --start-period=30s --retries=3 \
  CMD ["ruby", "-rnet/http", "-e", "exit Net::HTTP.get_response(URI('http://127.0.0.1:3000/up')).is_a?(Net::HTTPSuccess)"]

ENTRYPOINT ["bin/docker-entrypoint"]
CMD ["bundle", "exec", "falcon", "serve", "--count", "1", "--bind", "http://0.0.0.0:3000"]
