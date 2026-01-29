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
RUN curl -L "https://github.com/squid-cache/squid/releases/download/SQUID_${SQUID_VERSION//./_}/squid-${SQUID_VERSION}.tar.gz" \
    | tar -xzf - --strip-components=1

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
COPY squid.conf /etc/squid/squid.conf
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

COPY --from=builder /app/passwd /etc/passwd
COPY --from=builder /app/group /etc/group


EXPOSE 3128

USER 1000

# Note: Initialize cache (-z) is usually needed once, but here we just run.
ENTRYPOINT ["/usr/sbin/squid-init"]
