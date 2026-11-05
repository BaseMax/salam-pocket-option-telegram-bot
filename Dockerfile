# The bot is one native binary.
#
# The build stage installs the Salam compiler with the official installer,
# pinned to a release (0.6.2 carries std/net/socketio, which this bot needs),
# so `docker compose up -d --build` works on any machine with Docker and
# nothing has to be staged beforehand. Change SALAM_VERSION to move to another
# release.
#
# The runtime stage keeps the binary, SQLite and a CA bundle, and nothing
# else: no compiler, no standard library, no source.
ARG DEBIAN_VERSION=trixie-slim
ARG SALAM_VERSION=0.6.2

FROM debian:${DEBIAN_VERSION} AS build
ARG SALAM_VERSION

# clang links the native target; libsqlite3-dev is what std/db links against;
# curl and unzip are what the installer downloads and unpacks the compiler with.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl unzip clang libc6-dev libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

# The installer is taken from the release tag, not from main, so the same
# version always installs the same way. SALAM_STD is named outright because the
# binary-relative lookup does not fire when the compiler is invoked through
# PATH.
RUN curl -fsSL "https://raw.githubusercontent.com/SalamLang/Salam/v${SALAM_VERSION}/install.sh" \
        | SALAM_NO_MODIFY_PATH=1 sh -s -- --dir /opt/salam --version "${SALAM_VERSION}" \
    && /opt/salam/salam version | head -1
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
