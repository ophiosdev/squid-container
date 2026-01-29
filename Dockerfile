# 1. Use Alpine for true static linking (Musl Libc)
FROM alpine:3.21 AS builder

# 2. Install build dependencies
# Note: Alpine splits static libraries into "-static" packages.
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
    zlib-static

ARG SQUID_VERSION=6.12

# 3. Download and Extract
WORKDIR /src
RUN curl -L "http://www.squid-cache.org/Versions/v6/squid-${SQUID_VERSION}.tar.gz" \
    | tar -xzf - --strip-components=1

# 4. Configure and Compile
# - We use --enable-security-cert-generators=file for the SSL helper
# - We create the specific user/group files here to copy later
RUN export PKG_CONFIG="pkg-config --static" && \
    export CFLAGS="-O2 -g0 -flto=auto -pipe -static" && \
    export CXXFLAGS="-O2 -g0 -flto=auto -pipe -static" && \
    export LDFLAGS="-static -static-libgcc -static-libstdc++ -s -flto=auto" && \
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
    --disable-strict-error-checking \
    --disable-arch-native \
    --enable-auth-basic="NCSA" \
    --enable-auth-digest \
    --disable-auth-ntlm \
    --disable-auth-negotiate \
    --disable-external-acl-helpers \
    --disable-url-rewrite-helpers \
    --disable-storeid-rewrite-helpers \
    --disable-loadable-modules \
    --disable-ipv6 \
    --disable-esi \
    --enable-icmp \
    --disable-ident-lookups \
    --enable-cache-digests \
    --disable-delay-pools \
    --enable-wccp \
    --enable-wccpv2 \
    --disable-snmp \
    --enable-htcp \
    --enable-carp \
    --disable-useragent-log \
    --disable-referer-log \
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

# 5. Post-Processing
# Create the proxy user/group files manually to copy to scratch
RUN echo "proxy:x:1000:1000:proxy,,,:/nonexistent:/bin/false" > /app/passwd && \
    echo "proxy:x:1000:" > /app/group

# Ensure permissions for log/cache directories exist in the /app structure
RUN mkdir -p /app/var/log/squid /app/var/cache/squid /app/var/run && \
    chown -R 1000:1000 /app/var/log/squid /app/var/cache/squid /app/var/run

# Further strip (optional, install-strip usually does enough)
RUN strip --strip-all --remove-section=.comment --remove-section=.note /app/usr/sbin/squid

# --- Final Stage ---
FROM scratch AS final

# Copy the entire install tree (binaries, config, libs)
COPY --from=builder /app/ /

# Copy CA Certs (Essential for SSL bumping/verification)
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

# Copy User/Group definitions
COPY --from=builder /app/passwd /etc/passwd
COPY --from=builder /app/group /etc/group

# Expose ports
EXPOSE 3128

# Define user (Must use ID because 'proxy' name resolution might fail in scratch without glibc NSS, though usually fine with /etc/passwd present)
USER 1000

# Entrypoint
# Note: Initialize cache (-z) is usually needed once, but here we just run.
ENTRYPOINT ["/usr/sbin/squid", "-N", "-f", "/etc/squid/squid.conf"]
