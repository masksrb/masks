# syntax = docker/dockerfile:1

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=3.3.5
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /masks

# Install base packages
RUN apt-get update -qq && \
  apt-get install --no-install-recommends -y curl libjemalloc2 libvips postgresql-client && \
  rm -rf /var/lib/apt/lists /var/cache/apt/archives

RUN curl -fsSL https://deb.nodesource.com/setup_22.x -o nodesource_setup.sh
RUN bash nodesource_setup.sh
RUN apt-get install -y nodejs

# Set production environment
ENV RAILS_ENV="production" \
  BUNDLE_DEPLOYMENT="1" \
  BUNDLE_PATH="/usr/local/bundle" \
  BUNDLE_WITHOUT="development"

# Set default paths
ENV MASKS_DIR=/masks/conf \
  MASKS_STORAGE_DIR=/masks/storage \
  MASKS_DATA_DIR=/masks/data \
  MASKS_MODE=engine

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems
RUN apt-get update -qq && \
  apt-get install --no-install-recommends -y build-essential git libpq-dev pkg-config && \
  rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY masks.gemspec Gemfile Gemfile.lock ./
COPY lib/masks/version.rb ./lib/masks/version.rb

RUN bundle install && \
  rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
  bundle exec bootsnap precompile --gemfile

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times
RUN bundle exec bootsnap precompile app/ lib/
RUN npm install
RUN gem install foreman
RUN SECRET_KEY_BASE=`bundle exec rails secret` bundle exec rails app:assets:precompile

# Final stage for app image
FROM base

# Copy built artifacts: gems, application
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /masks /masks

# Run and own only the runtime files as a non-root user for security
RUN groupadd --system --gid 1000 masks && \
  useradd masks --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
  chown -R masks:masks /masks
USER 1000:1000

# Entrypoint prepares the database.
ENTRYPOINT ["/masks/bin/docker-entrypoint"]

# Start the server by default, this can be overwritten at runtime
EXPOSE 5000 9394
CMD ["server"]
