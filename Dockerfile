FROM alpine:latest AS start

RUN apk add --no-cache \
    build-base \
    linux-headers \
    curl \
    perl \
    pkgconf \
    openssl-dev \
    openssl-libs-static \
    libcap-dev \
    libcap-static \
    zlib-dev \
    zlib-static \
    libc++-static \
    libltdl-static \
    pcre2-static \
    libtool \
    autoconf \
    automake \
    bash

ARG SQUID_VERSION=7.4

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

WORKDIR /src
RUN shopt -s extglob && \
    # extglob trims any trailing ".0" segments (e.g. 7.4.0 -> 7.4, 7.0.0 -> 7)
    SQUID_VERSION_CURL="${SQUID_VERSION%%+(.0)}" && \
    curl -L "https://github.com/squid-cache/squid/releases/download/SQUID_${SQUID_VERSION_CURL//./_}/squid-${SQUID_VERSION_CURL}.tar.gz" \
    | tar -xzf - --strip-components=1

COPY patch /src/patch/

RUN SQUID_MAJOR_VERSION="${SQUID_VERSION%%.*}" && \
    SQUID_REST="${SQUID_VERSION#${SQUID_MAJOR_VERSION}}" && \
    SQUID_REST="${SQUID_REST#.}" && \
    IFS='.' read -r SQUID_MINOR_VERSION SQUID_PATCH_VERSION _extra <<< "$SQUID_REST" && \
    PATCH_BASE_DIR="/src/patch/${SQUID_MAJOR_VERSION}" && \
    if [[ -d "$PATCH_BASE_DIR" ]]; then \
      echo "Searching patches under $PATCH_BASE_DIR" && \
      shopt -s nullglob && \
      declare -A selected_patches=() && \
      collect_patches() { \
        local dir="$1"; \
        [[ -d "$dir" ]] || return 0; \
        for patch_file in "$dir"/*.patch; do \
          local base filename priority; \
          base="$(basename "$patch_file")"; \
          if [[ "$base" =~ ^([0-9]+)[[:space:]_](.+)$ ]]; then \
            priority="${BASH_REMATCH[1]}"; \
            filename="${BASH_REMATCH[2]}"; \
          else \
            priority="0"; \
            filename="$base"; \
          fi; \
          if [[ -z "${selected_patches[$filename]}" ]]; then \
            selected_patches["$filename"]="${priority}\t${filename}\t${patch_file}"; \
          fi; \
        done; \
      }; \
      if [[ -n "$SQUID_MINOR_VERSION" && -n "$SQUID_PATCH_VERSION" ]]; then \
        collect_patches "$PATCH_BASE_DIR/$SQUID_MINOR_VERSION/$SQUID_PATCH_VERSION"; \
      fi; \
      if [[ -n "$SQUID_MINOR_VERSION" ]]; then \
        collect_patches "$PATCH_BASE_DIR/$SQUID_MINOR_VERSION"; \
      fi; \
      collect_patches "$PATCH_BASE_DIR"; \
      if [[ ${#selected_patches[@]} -gt 0 ]]; then \
        printf "%b\n" "${selected_patches[@]}" \
          | sort -rn -k1,1 -k2,2 \
          | while IFS=$'\t' read -r priority filename patch_file; do \
              echo "Applying patch: $(basename "$patch_file")"; \
              patch -p1 --forward --batch < "$patch_file" || { echo "Failed to apply patch: $(basename "$patch_file")"; exit 1; }; \
            done; \
      else \
        echo "No patches found under $PATCH_BASE_DIR. Skipping."; \
      fi; \
    else \
      echo "No version-specific patches found for v${SQUID_MAJOR_VERSION} (missing $PATCH_BASE_DIR). Skipping."; \
    fi


FROM start AS builder

RUN export PKG_CONFIG="pkg-config --static" && \
    export CC="gcc -no-pie -static -pipe" && \
    export CXX="g++ -no-pie -static -pipe" && \
    export CFLAGS="-O2 -g0 -flto=auto" && \
    export CXXFLAGS="-O2 -g0 -flto=auto" && \
    export LDFLAGS="-static -Wl,--no-as-needed -lcap -Wl,-Bstatic -lssl -Wl,-Bstatic -lcrypto -Wl,-Bstatic -lc -Wl,-Bstatic -static-libgcc -static-libstdc++" && \
    ./configure \
    --prefix=/usr \
    --sysconfdir=/etc/squid \
    --datadir=/usr/share/squid \
    --libexecdir=/usr/lib/squid \
    --localstatedir=/var \
    --with-logdir=/var/log/squid \
    --with-pidfile=/var/run/squid.pid \
    --disable-shared \
    --enable-static \
    --disable-dependency-tracking \
    --disable-arch-native \
    --enable-auth-basic \
    --enable-auth-digest \
    --disable-auth-ntlm \
    --disable-auth-negotiate \
    --disable-external-acl-helpers \
    --enable-url-rewrite-helpers \
    --enable-storeid-rewrite-helpers \
    --disable-loadable-modules \
    --enable-icmp \
    --disable-ident-lookups \
    --enable-cache-digests \
    --enable-delay-pools \
    --enable-wccp \
    --enable-wccpv2 \
    --enable-snmp \
    --enable-htcp \
    --enable-carp \
    --enable-useragent-log \
    --enable-referer-log \
    --enable-follow-x-forwarded-for=no \
    --enable-zph-qos=no \
    --enable-eui=no \
    --enable-ssl \
    --enable-ssl-crtd \
    --enable-security-cert-generators="file" \
    --enable-linux-netfilter=no \
    --enable-arp-acl=no \
    --enable-async-io=no \
    --enable-disk-io="AIO" \
    --enable-storeio="aufs" \
    --enable-removal-policies="lru" \
    --enable-poll \
    --with-large-files \
    --with-openssl \
    --without-gnutls \
    --without-netfilter-conntrack \
    --without-krb5 \
    --without-heimdal-krb5 \
    --without-mit-krb5 \
    --without-gssapi \
    --with-libcap && \
    make -j$(nproc) && \
    make install-strip DESTDIR=/app

RUN echo "proxy:x:1000:1000:proxy,,,:/nonexistent:/bin/false" > /app/passwd && \
    echo "proxy:x:1000:" > /app/group

RUN mkdir -p /app/var/log/squid /app/var/cache/squid /app/var/run && \
    chown -R 1000:1000 /app/var/log/squid /app/var/cache/squid /app/var/run

RUN strip --strip-all --remove-section=.comment --remove-section=.note /app/usr/sbin/squid \
    && mkdir /app/lib \
    && cp /lib/ld-musl-x86_64.so.1 /app/lib/ \
    && cd /app/lib/ && ln -s ./ld-musl-x86_64.so.1 ./libc.musl-x86_64.so.1

COPY squid-init.c /src/

RUN gcc -no-pie -static -pipe -O2 -o /app/usr/sbin/squid-init squid-init.c \
    && strip --strip-all --remove-section=.comment --remove-section=.note /app/usr/sbin/squid-init

# --- Final Stage ---
FROM scratch AS final

COPY --from=builder /app/ /
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

COPY --from=builder /app/passwd /etc/passwd
COPY --from=builder /app/group /etc/group


EXPOSE 3128

USER 1000

# Note: Initialize cache (-z) is usually needed once, but here we just run.
ENTRYPOINT ["/usr/sbin/squid-init"]
