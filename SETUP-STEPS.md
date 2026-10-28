# Пошаговый план

Два независимых потока на одном зарубежном VPS: WireGuard для дома (Keenetic) и 3proxy для Telegram-бэкенда. Их можно делать по очереди.

## Часть A. VPS с нуля (общая)

1. Войдите `ssh root@<VPS_IP>` и выполните `apt update && apt -y upgrade`.
2. Создайте пользователя: `adduser deploy && usermod -aG sudo deploy`. Добавьте свой публичный ключ в `/home/deploy/.ssh/authorized_keys` (права 700 для папки и 600 для файла).
3. Во втором окне проверьте `ssh deploy@<VPS_IP>`.
4. Отключите пароль и root-вход: в `/etc/ssh/sshd_config` поставьте `PasswordAuthentication no` и `PermitRootLogin no`, затем `sudo sshd -t && sudo systemctl restart ssh`.
5. Поставьте защиту: `sudo apt install -y ufw fail2ban unattended-upgrades git`.
6. Настройте firewall: `ufw default deny incoming`, `ufw allow 22/tcp`, `ufw allow 51820/udp`, `ufw enable`.
7. Если у провайдера есть облачный firewall, откройте там `22/tcp` и `51820/udp`.
8. Проверьте, что OpenAI доступен: `curl -sS -o /dev/null -w "%{http_code}\n" https://api.openai.com/v1/models` должен вернуть 401. Если нет, смените VPS и дальше не идите.
9. Поставьте Docker (нужен для части C): `curl -fsSL https://get.docker.com | sudo sh && sudo usermod -aG docker deploy`. После этого перелогиньтесь.

## Часть B. Дом: WireGuard и Keenetic

1. С ПК скопируйте скрипт: `scp socks5-proxy/wireguard/setup-vps.sh deploy@<VPS_IP>:~`.
2. На VPS запустите `sudo bash setup-vps.sh`. Сверьте напечатанные `WAN_IF` и `PUBLIC_IP`.
3. Скачайте конфиг: `sudo cat /root/keenetic-wg.conf`, сохраните как файл на ПК и удалите его с VPS (`sudo shred -u /root/keenetic-wg.conf`).
4. На Keenetic обновите KeenOS и в «Общие настройки → Изменить набор компонентов» поставьте клиент «WireGuard VPN».
5. «Интернет → Другие подключения → WireGuard → Импорт из файла». **Снимите** «Использовать для выхода в интернет» и включите подключение.
6. Добавьте домены `openai.com`, `chatgpt.com`, `oaistatic.com`, `oaiusercontent.com` в доменную маршрутизацию через это подключение. Если такого раздела нет, используйте политику доступа для отдельных устройств.
7. В браузерах и ОС отключите DoH.
8. Проверка: с домашнего ПК `curl https://api.openai.com/v1/models` должен вернуть 401. На VPS `sudo wg show` должен показать свежий handshake.

## Часть C. Бэкенд: 3proxy для Telegram

1. Закоммитьте и запушьте `socks5-proxy`. Либо скопируйте папку: `scp -r socks5-proxy deploy@<VPS_IP>:~`.
2. На прокси-VPS: `cd ~/socks5-proxy && cp 3proxy.cfg.example 3proxy.cfg`.
3. Сгенерируйте пароль и подставьте значения командами из раздела «Шаги» в `README.md` (логин, пароль, статический IP бэкенда). Затем `chmod 600 3proxy.cfg`. Пароль сохраните в менеджере паролей.
4. Запустите: `docker compose up -d --build && docker compose logs -f socks5`.
5. Закройте порт 1080 для всех, кроме IP бэкенда, правилами `DOCKER-USER` из раздела «Firewall» в `README.md`. Затем `sudo apt install -y iptables-persistent`.
6. Проверьте с хоста бэкенда: `curl -v --socks5-hostname USER:PASS@<VPS_IP>:1080 https://api.telegram.org`. Любой ответ от Telegram считается успехом.
7. Проверьте с постороннего IP: `nc -vz <VPS_IP> 1080` не должен соединяться.
8. В `.env` бэкенда задайте `TELEGRAM_PROXY_ENABLED=true`, `TELEGRAM_PROXY_HOST=<IP прокси-VPS>`, `TELEGRAM_PROXY_PORT=1080`, `TELEGRAM_PROXY_USERNAME` и `TELEGRAM_PROXY_PASSWORD`. Если деплой идёт через GitHub, добавьте эти же значения в Secrets.
9. Перезапустите бэкенд: `docker compose up -d backend-prod`. В логах должно появиться `SOCKS5 proxy ...`, и бот должен ответить в Telegram.

## Финальная проверка

- `nmap <VPS_IP>` снаружи: открыты только 22 и 51820/udp (1080 для чужих закрыт).
- Дом: IP при открытии `openai.com` и другого сайта разный.
- Перезагрузите VPS и роутер: туннель и прокси должны подняться сами.
