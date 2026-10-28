# WireGuard: OpenAI для домашней сети через VPS

Домашние устройства -> Keenetic (WG-клиент) -> VPS (WG-сервер + NAT) -> OpenAI.
Через туннель идут только домены OpenAI, остальной трафик напрямую. 3proxy для
этого сценария не нужен (он остаётся для Telegram-бэкенда).

## 1. VPS

```bash
scp wireguard/setup-vps.sh user@<VPS_IP>:~
ssh user@<VPS_IP>
sudo bash setup-vps.sh        # при необходимости: WAN_IF=ens3 WG_PORT=51820 PUBLIC_IP=...
```

Скрипт ставит WireGuard, настраивает NAT, пускает из туннеля только tcp/udp 443
и создаёт `/root/keenetic-wg.conf`. Если используете облачный firewall
провайдера, откройте в нём `51820/udp`.

```bash
sudo scp ... # или: sudo cat /root/keenetic-wg.conf  и сохранить на ПК
sudo shred -u /root/keenetic-wg.conf   # после импорта в роутер
```

## 2. Keenetic

1. Обновить KeenOS. «Общие настройки -> Изменить набор компонентов» -> клиент
   «WireGuard VPN».
2. «Интернет -> Другие подключения -> WireGuard -> Создать подключение ->
   Импорт из файла» (`keenetic-wg.conf`).
3. В подключении **снять** «Использовать для выхода в интернет».
   Включить подключение, убедиться в рукопожатии (статус «подключено»).
4. Маршрутизация доменов OpenAI через это подключение. Название пункта зависит
   от версии KeenOS (4.x: «Сетевые правила -> Маршрутизация -> DNS-маршрутизация /
   Списки доменов»). Домены:
   `openai.com`, `chatgpt.com`, `oaistatic.com`, `oaiusercontent.com`.
   Если нужен web-логин ChatGPT, добавьте `auth0.com`, `challenges.cloudflare.com`.
   Нет такого раздела — используйте «Политики доступа в интернет» для
   отдельных устройств.
5. В браузерах и ОС отключить DoH / «безопасный DNS».

## 3. Проверка

```bash
curl -sS -o /dev/null -w "%{http_code}\n" https://api.openai.com/v1/models   # 401
curl -s https://ifconfig.me          # IP домашнего провайдера
```

На VPS: `sudo wg show` — свежий `latest handshake`.

Если запросы зависают: снизить MTU в WG-подключении (1280 уже минимальный
безопасный; проверить обратно 1380/1420 при стабильной работе).

## Важно

OpenAI запрещает доступ из неподдерживаемых стран; туннель это не меняет.
Ключи (`*.key`, `wg0.conf`, `keenetic-wg.conf`) не коммитить.
