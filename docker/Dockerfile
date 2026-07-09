# syntax=docker/dockerfile:1
ARG RUBY_VERSION=4.0.1

# ── base ──────────────────────────────────────────────────────────────────────
FROM ruby:${RUBY_VERSION}-slim AS base

WORKDIR /app

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
      libsqlite3-dev sqlite3 \
    && rm -rf /var/lib/apt/lists/*

ENV RAILS_ENV=production \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_PATH="/usr/local/bundle"

# ── build ──────────────────────────────────────────────────────────────────────
FROM base AS build

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
      build-essential cmake git curl \
    && rm -rf /var/lib/apt/lists/*

# Node + pnpm (needed for esbuild and tailwind)
ARG NODE_VERSION=22
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g pnpm

# Gems
COPY Gemfile Gemfile.lock ./
RUN bundle install

# JS packages
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

# App source
COPY . .

# Compile assets
RUN pnpm run build
RUN bundle exec rails tailwindcss:build
RUN SECRET_KEY_BASE_DUMMY=1 bundle exec rails assets:precompile

# ── production ─────────────────────────────────────────────────────────────────
FROM base AS production

RUN useradd --create-home --uid 1000 rails

COPY --from=build --chown=rails:rails /usr/local/bundle /usr/local/bundle
COPY --from=build --chown=rails:rails /app /app

USER rails

EXPOSE 3000

CMD ["bundle", "exec", "falcon", "serve", "--bind", "http://0.0.0.0:3000"]
