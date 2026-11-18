FROM ubuntu:24.04 AS compiler
ARG TARGETARCH
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc libc6-dev git curl ca-certificates xz-utils \
    && rm -rf /var/lib/apt/lists/*
RUN case "$TARGETARCH" in \
      amd64) relay_nim_arch=x64 ;; \
      arm64) relay_nim_arch=arm64 ;; \
      *) exit 1 ;; \
    esac \
    && curl -fsSL "https://github.com/nim-lang/nightlies/releases/download/2026-04-24-version-2-2-bfeb3146d1638b39f69007a4ae5a23e23ae4e5ef/nim-2.2.10-linux_${relay_nim_arch}.tar.xz" \
    | tar xJ -C /opt
ENV PATH=/opt/nim-2.2.10/bin:$PATH
WORKDIR /src/polyworld
COPY nimby.lock nimby.lock
COPY coworld/tools/sync_dependencies.nim coworld/tools/tooling.nim coworld/tools/
ENV POLYWORLD_DEPS=/src/polyworld/tmp/coworld/deps
RUN nim r --hints:off coworld/tools/sync_dependencies.nim
COPY config.nims config.nims
COPY src src
COPY tools/gameserver.nim tools/gameserver.nim
RUN nim c --threads:on -d:release -o:/out/gameserver tools/gameserver.nim
FROM ubuntu:24.04
RUN useradd --system --uid 10001 relay
COPY --from=compiler /out/gameserver /usr/local/bin/gameserver
USER relay
ENV BIND=0.0.0.0 PORT=8090
EXPOSE 8090
ENTRYPOINT ["/usr/local/bin/gameserver"]
