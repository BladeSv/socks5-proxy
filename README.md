# socks5-proxy

SOCKS5-прокси на базе [3proxy](https://3proxy.org/) в Docker. Используется
Telegram-ботом проекта [tabletop-trail-bot](https://github.com/) для
исходящих запросов к `api.telegram.org`, когда сервер бэкенда находится в
регионе с блокировкой Telegram.

## Архитектура

```
backend-prod (Java/Spring) ──► SOCKS5 ──► 3proxy (этот VPS) ──► api.telegram.org
                                          auth: USER + PASSWORD
                                          ACL: только IP бэкенда
```

В **этот** репозиторий коммитятся только шаблоны и `docker-compose.yml`.
Реальный `3proxy.cfg` с паролем создаётся на VPS из `3proxy.cfg.example`
и **никогда не попадает в git** (исключён `.gitignore`).

## Что в репозитории

| Файл                  | Коммитится | Назначение                                         |
| --------------------- | ---------- | -------------------------------------------------- |
| `Dockerfile`          | да         | Минимальный образ: Alpine + пакет `3proxy`         |
| `docker-compose.yml`  | да         | Запуск контейнера 3proxy (build из Dockerfile)     |
| `3proxy.cfg.example`  | да         | Шаблон конфига 3proxy с плейсхолдерами `CHANGEME*` |
| `README.md`           | да         | Этот файл                                          |
| `.gitignore`          | да         | Исключает секреты из git                           |
| `3proxy.cfg`          | НЕТ        | Реальный конфиг с паролем (создаётся на VPS)       |

> Почему свой `Dockerfile`, а не готовый образ? Популярные образы вроде
> `tarampampam/3proxy` имеют opinionated entrypoint-скрипты, которые
> пытаются рендерить конфиг и писать в read-only части файловой системы —
> контейнер падает с `Cannot create file: Read-only file system`.
> Собственный Dockerfile из ~5 строк (Alpine + `apk add 3proxy`) полностью
> снимает эту проблему, образ строится за ~10 секунд.

## Развёртывание на VPS

### Требования

- Linux VPS с публичным IP.
- Установлены `docker` и `docker compose` v2.
- Открыт исходящий трафик на порт 443 (для подключения к Telegram).
- Открыт входящий TCP/1080 (можно ограничить firewall'ом — см. ниже).

### Шаги

```bash
# 1. Клонируем репо на VPS
git clone <url-этого-репо> ~/socks5-proxy
cd ~/socks5-proxy

# 2. Готовим реальный конфиг из шаблона
cp 3proxy.cfg.example 3proxy.cfg

# 3. Генерируем учётку
PROXY_USER="tabletop_bot"
PROXY_PASS="$(openssl rand -base64 24)"
echo "USER=$PROXY_USER"
echo "PASS=$PROXY_PASS"   # сохранить в менеджер паролей!

# 4. Подставляем креды в 3proxy.cfg.
#    Если знаем IP бэкенда — ограничиваем доступ им (рекомендуется):
BACKEND_IP="<публичный IP вашего backend-prod>"
sed -i "s|CHANGEME_USER:CL:CHANGEME_PASS|${PROXY_USER}:CL:${PROXY_PASS}|" 3proxy.cfg
sed -i "s|^allow CHANGEME_USER CHANGEME_BACKEND_IP$|allow ${PROXY_USER} ${BACKEND_IP}|" 3proxy.cfg

# 4b. ИЛИ если IP бэкенда неизвестен/динамический — оставляем только auth:
# sed -i "s|CHANGEME_USER:CL:CHANGEME_PASS|${PROXY_USER}:CL:${PROXY_PASS}|" 3proxy.cfg
# sed -i "s|^allow CHANGEME_USER CHANGEME_BACKEND_IP$|allow ${PROXY_USER}|" 3proxy.cfg

# 5. Закрываем права на конфиг (там пароль в открытом виде)
chmod 600 3proxy.cfg

# 6. Билдим свой образ (один раз, ~10 секунд) и поднимаем контейнер.
#    Логи 3proxy идут в stdout — их видно через `docker compose logs`.
docker compose up -d --build
docker compose logs -f socks5
```

### Проверка

С хоста бэкенда (важно — именно с того IP, который указан в `allow`):

```bash
curl -v --socks5-hostname \
  "${PROXY_USER}:${PROXY_PASS}@<VPS_IP>:1080" \
  https://api.telegram.org
```

Любой ответ от Telegram (например, `HTTP/1.1 200 OK` или редирект) означает,
что соединение через прокси установилось.

## Firewall на VPS (опционально, но рекомендуется)

Дополнительный уровень защиты — пускать на 1080 только IP бэкенда.

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw allow from <BACKEND_IP> to any port 1080 proto tcp
sudo ufw enable
sudo ufw status verbose
```

Если firewall настраивать не хотите — оставьте `allow USER BACKEND_IP`
внутри `3proxy.cfg`, это даст почти эквивалентную защиту на уровне 3proxy.

## Обновление

```bash
cd ~/socks5-proxy
git pull
# --build пересоберёт образ, если в Dockerfile/Alpine что-то менялось
docker compose up -d --build
```

## Ротация пароля

1. Сгенерировать новый: `openssl rand -base64 24`.
2. Обновить строку `users ...` в `3proxy.cfg` на VPS.
3. `docker compose restart socks5`.
4. Обновить `TELEGRAM_PROXY_PASSWORD` в `.env` бэкенда и
   `docker compose up -d backend-prod` на стороне приложения.

## Безопасность

- **НИКОГДА не коммитить** `3proxy.cfg` или `.env` в git. Они в `.gitignore`.
- Пароль 3proxy хранится в clear-text в `3proxy.cfg` (ограничение SOCKS5):
  закрываем `chmod 600`, чтобы файл читал только владелец.
- Минимизировать поверхность: используйте firewall + ACL по IP в конфиге.
- Если пароль скомпрометирован — немедленно ротировать (см. выше).
- Для прода зафиксируйте базовый образ: в `Dockerfile` уже стоит конкретный
  тег `alpine:3.20` — его периодически обновляйте до свежей мажорной версии
  и пересобирайте (`docker compose up -d --build`).

## Диагностика

```bash
# Контейнер запущен?
docker compose ps

# Логи 3proxy (формат: дата время N.p E user CLIENT:port DEST:port ...)
docker compose logs -f socks5

# Только последние 100 строк
docker compose logs --tail=100 socks5

# Кто-то долбится на 1080?
sudo ss -tnp | grep :1080

# Резолв DNS внутри контейнера работает?
docker compose exec socks5 nslookup api.telegram.org
```

## Лицензия / приватность

Этот репозиторий содержит только инфра-конфиг. Логи 3proxy могут содержать
IP/порты клиентов — храните их в соответствии с вашей политикой.
