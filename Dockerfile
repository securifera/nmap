# ─── STAGE 1: Build Nmap from Official Release ─────────────────────────────
FROM debian:bookworm-slim AS builder

# 1) Install only what's needed: compiler, libs, wget, bzip2
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential \
      autoconf \
      wget \
      bzip2 \
      libpcap-dev \
      libssl-dev \
      libssh2-1-dev \
      liblua5.4-dev \
      ca-certificates \
      git \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# 2) Download & unpack the release (configure already present)
#RUN git clone -c http.sslVerify=false https://github.com/securifera/nmap.git
COPY . /build/nmap

WORKDIR /build/nmap

# 3) Configure for static linking (no shared libs), install into /dist
RUN ./configure \
      --disable-shared \
      --enable-static \
      --without-zenmap \
      --without-ndiff \
      --without-ncat \
      --without-nping \
      --prefix=/usr/local \
      LDFLAGS="-static" \
 && make -j"$(nproc)" \
 && make install DESTDIR=/dist    # install everything: bin, libexec (NSE), share, man… :contentReference[oaicite:1]{index=1}

# ─── STAGE 2: Bundle into One tar.gz ───────────────────────────────────────
FROM debian:bookworm-slim AS packager

# tar is already available, but ensure it
RUN apt-get update \
 && apt-get install -y --no-install-recommends tar \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /dist
COPY --from=builder /dist .

# Create the single archive with bin/, libexec/, share/, man/, etc.
RUN tar czf /nmap-static-full.tar.gz .

# ─── STAGE 3: Minimal “scratch” Runtime (Optional) ─────────────────────────
FROM scratch AS final

COPY --from=builder /dist/usr/local/bin/nmap /usr/local/bin/nmap
ENTRYPOINT ["/usr/local/bin/nmap"]
CMD ["--help"]
