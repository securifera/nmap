# ─── STAGE 1: Build truly-static nmap with full OpenSSL/NSE support ────────
#
# Why Alpine + musl:
#   glibc fundamentally cannot produce a fully-static binary that uses
#   getpwuid (NSS dlopen) or OpenSSL 3.x providers (dlopen at startup).
#   Both crash at runtime in static glibc. musl has no NSS plugin system
#   and no provider-style dlopen, so true full-static works cleanly.
#
# Critical build requirements (any of these missing → broken binary):
#   • openssl-libs-static, libssh2-static, zlib-static — static archives
#     for the C libs nmap links against; without them configure silently
#     falls back to a build without OpenSSL, which kills NSE scripts that
#     `require "openssl"` (ssl-cert, ssl-enum-ciphers, http-vuln-*, etc.).
#   • LIBS="-ldl -lpthread" — OpenSSL's static archives reference these
#     symbols; without them the OpenSSL link check in nmap's configure
#     fails and HAVE_OPENSSL is left undefined.
#   • LDFLAGS="-static" + --disable-shared --enable-static — actual full
#     static linking, not just "disable internal shared libs".
#
# In-tree patches that ship with this fork (see commits):
#   • nse_openssl.cc — no-op the OSSL_PROVIDER_unload at shutdown so
#     OpenSSL 3.x doesn't crash inside CRYPTO_THREAD_read_lock(NULL).
#     Harmless on OpenSSL 1.1; the providers don't exist there.
#   • nmap.cc — prefer $HOME over getpwuid for the current uid so static
#     glibc doesn't dlopen libnss_files.so. (Belt-and-suspenders; musl
#     isn't affected, but keeps the source portable.)
#   • nse_ssl_cert.cc — gate EC_GROUP_get_field_type behind an explicit
#     OpenSSL ≥ 3.0 check. Upstream's HAVE_OPAQUE_STRUCTS gate was too
#     permissive — 1.1.x has opaque EC structs but still uses the older
#     EC_METHOD_get_field_type API.

FROM alpine:3.20 AS builder

RUN apk add --no-cache \
      build-base autoconf wget bzip2 \
      libpcap-dev \
      openssl-dev openssl-libs-static \
      libssh2-dev libssh2-static \
      zlib-dev zlib-static \
      lua5.3-dev \
      libnl3-dev rdma-core-dev \
      ca-certificates git linux-headers

WORKDIR /build
COPY . /build/nmap
WORKDIR /build/nmap

RUN ./configure \
      --disable-shared --enable-static \
      --without-zenmap --without-ndiff --without-ncat --without-nping \
      --prefix=/usr/local \
      LDFLAGS="-static" \
      LIBS="-ldl -lpthread" \
 && make -j"$(nproc)" \
 && make install DESTDIR=/dist

# ─── STAGE 2: Bundle the install tree into one tar.gz ─────────────────────
FROM alpine:3.20 AS packager
RUN apk add --no-cache tar
WORKDIR /dist
COPY --from=builder /dist .
RUN tar czf /nmap-static-full.tar.gz .

# ─── STAGE 3: Minimal "scratch" runtime (optional) ────────────────────────
FROM scratch AS final
COPY --from=builder /dist/usr/local/bin/nmap /usr/local/bin/nmap
ENTRYPOINT ["/usr/local/bin/nmap"]
CMD ["--help"]
