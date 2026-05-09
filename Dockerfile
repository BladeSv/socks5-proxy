# Multi-stage build для минимального финального образа.
# 3proxy не входит в Alpine community-репо, поэтому собираем из исходников.

# ============================================
# Stage 1: компилируем 3proxy
# ============================================
FROM alpine:3.20 AS builder

RUN apk add --no-cache build-base curl ca-certificates

ARG VERSION=0.9.5
RUN curl -fsSL https://github.com/3proxy/3proxy/archive/refs/tags/${VERSION}.tar.gz \
      | tar -xz -C /tmp \
    && cd /tmp/3proxy-${VERSION} \
    && make -f Makefile.Linux \
    && install -m 755 bin/3proxy /usr/local/bin/3proxy

# ============================================
# Stage 2: минимальный runtime
# ============================================
FROM alpine:3.20

RUN apk add --no-cache ca-certificates

COPY --from=builder /usr/local/bin/3proxy /usr/local/bin/3proxy

EXPOSE 1080

# Запускаем 3proxy напрямую — никаких wrapper-скриптов.
# Конфиг монтируется снаружи в /etc/3proxy/3proxy.cfg (см. docker-compose.yml).
ENTRYPOINT ["3proxy"]
CMD ["/etc/3proxy/3proxy.cfg"]
