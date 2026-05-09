# Минимальный образ с 3proxy — без entrypoint-скриптов, без лишней магии.
# Собираем из Alpine + штатный пакет `3proxy` из community-репозитория.
FROM alpine:3.20

RUN apk add --no-cache 3proxy ca-certificates

EXPOSE 1080

# Запускаем 3proxy напрямую — никаких wrapper-скриптов.
# Конфиг монтируется снаружи в /etc/3proxy/3proxy.cfg (см. docker-compose.yml).
ENTRYPOINT ["3proxy"]
CMD ["/etc/3proxy/3proxy.cfg"]
