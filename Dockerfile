# The bot is one native binary.
#
# The build stage compiles the Salam sources with a compiler staged into
# .salam-toolchain by build.sh, because the socket.io client this bot needs
# is newer than the last published Salam release. Once a release carries
# std/net/socketio, this stage can fetch it with the official install.sh
# instead and the toolchain copy can go.
#
# The runtime stage keeps the binary, SQLite and a CA bundle, and nothing
# else: no compiler, no standard library, no source.
ARG DEBIAN_VERSION=trixie-slim

FROM debian:${DEBIAN_VERSION} AS build

# clang links the native target; libsqlite3-dev is what std/db links against.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates clang libc6-dev libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

# Staged by `./build.sh image`: the compiler and the standard library it
# needs. SALAM_STD is named outright because the binary-relative lookup does
# not fire when the compiler is invoked through PATH.
COPY .salam-toolchain/salam /opt/salam/salam
COPY .salam-toolchain/std /opt/salam/std
ENV PATH="/opt/salam:${PATH}" \
    SALAM_STD="/opt/salam/std"

WORKDIR /src
COPY main.salam ./
COPY src ./src
COPY checks ./checks

# The suite runs here, so an image that builds is an image whose bot passed
# its tests on the way in.
RUN salam build checks/tests.salam --output=/src/tests \
    && /src/tests \
    && salam build main.salam --output=/src/bot

FROM debian:${DEBIAN_VERSION} AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates libsqlite3-0 \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 1000 bot \
    && useradd --system --uid 1000 --gid 1000 --create-home --home-dir /app bot

ENV DB_PATH=/app/data/bot.sqlite \
    HEARTBEAT_PATH=/app/data/heartbeat

WORKDIR /app
COPY --from=build /src/bot /app/bot
COPY docker/entrypoint.sh docker/healthcheck.sh /app/docker/
# useradd --create-home leaves /app at mode 700, which stops the container
# from starting at all under any other uid - including a DOCKER_UID that does
# not happen to be 1000. The directory has to be traversable by whoever runs.
RUN mkdir -p /app/data \
    && chmod +x /app/docker/*.sh \
    && chown -R bot:bot /app \
    && chmod 755 /app /app/docker

USER bot
STOPSIGNAL SIGTERM
ENTRYPOINT ["/app/docker/entrypoint.sh"]
CMD ["/app/bot"]
