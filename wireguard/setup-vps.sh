#!/usr/bin/env bash
# Настройка WireGuard-сервера на VPS (Ubuntu/Debian) для выхода домашней сети
# (Keenetic) к OpenAI. Запускать от root:  sudo bash setup-vps.sh
#
# Создаёт /etc/wireguard/wg0.conf, ключи и готовый конфиг клиента
# /root/keenetic-wg.conf (содержит приватный ключ — не коммитить, после
# импорта в роутер удалить).
set -euo pipefail

WG_IF=wg0
WG_PORT="${WG_PORT:-51820}"
WG_NET=10.8.0.0/24
SERVER_ADDR=10.8.0.1
KEENETIC_ADDR=10.8.0.2

[ "$(id -u)" -eq 0 ] || { echo "Запустите от root" >&2; exit 1; }

WAN_IF="${WAN_IF:-$(ip -4 route get 1.1.1.1 | sed -n 's/.* dev \([^ ]*\).*/\1/p' | head -n1)}"
PUBLIC_IP="${PUBLIC_IP:-$(curl -fsS4 https://ifconfig.me || true)}"
[ -n "$WAN_IF" ] || { echo "Не удалось определить WAN-интерфейс, задайте WAN_IF=..." >&2; exit 1; }
[ -n "$PUBLIC_IP" ] || { echo "Не удалось определить внешний IP, задайте PUBLIC_IP=..." >&2; exit 1; }
echo "WAN_IF=$WAN_IF PUBLIC_IP=$PUBLIC_IP PORT=$WG_PORT"

apt-get update -qq
apt-get install -y -qq wireguard iptables curl

umask 077
mkdir -p /etc/wireguard
cd /etc/wireguard

[ -f server.key ]   || wg genkey | tee server.key | wg pubkey > server.pub
[ -f keenetic.key ] || wg genkey | tee keenetic.key | wg pubkey > keenetic.pub

# Разрешаем из туннеля только HTTPS (tcp/udp 443); DNS резолвит сам Keenetic.
cat > "/etc/wireguard/${WG_IF}.conf" <<EOF
[Interface]
Address = ${SERVER_ADDR}/24
ListenPort = ${WG_PORT}
PrivateKey = $(cat server.key)
PostUp   = sysctl -w net.ipv4.ip_forward=1
PostUp   = iptables -t nat -A POSTROUTING -s ${WG_NET} -o ${WAN_IF} -j MASQUERADE
PostUp   = iptables -A FORWARD -i ${WG_IF} -o ${WAN_IF} -p tcp --dport 443 -j ACCEPT
PostUp   = iptables -A FORWARD -i ${WG_IF} -o ${WAN_IF} -p udp --dport 443 -j ACCEPT
PostUp   = iptables -A FORWARD -i ${WAN_IF} -o ${WG_IF} -m state --state RELATED,ESTABLISHED -j ACCEPT
PostUp   = iptables -A FORWARD -i ${WG_IF} -j DROP
PostDown = iptables -t nat -D POSTROUTING -s ${WG_NET} -o ${WAN_IF} -j MASQUERADE
PostDown = iptables -D FORWARD -i ${WG_IF} -o ${WAN_IF} -p tcp --dport 443 -j ACCEPT
PostDown = iptables -D FORWARD -i ${WG_IF} -o ${WAN_IF} -p udp --dport 443 -j ACCEPT
PostDown = iptables -D FORWARD -i ${WAN_IF} -o ${WG_IF} -m state --state RELATED,ESTABLISHED -j ACCEPT
PostDown = iptables -D FORWARD -i ${WG_IF} -j DROP

[Peer]
# keenetic
PublicKey  = $(cat keenetic.pub)
AllowedIPs = ${KEENETIC_ADDR}/32
EOF

# Конфиг клиента для Keenetic
cat > /root/keenetic-wg.conf <<EOF
[Interface]
PrivateKey = $(cat keenetic.key)
Address = ${KEENETIC_ADDR}/24
MTU = 1280

[Peer]
PublicKey = $(cat server.pub)
Endpoint = ${PUBLIC_IP}:${WG_PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
chmod 600 /root/keenetic-wg.conf

if command -v ufw >/dev/null 2>&1; then
  ufw allow "${WG_PORT}/udp"
fi

systemctl enable --now "wg-quick@${WG_IF}"
wg show "${WG_IF}"

echo
echo "Готово. Конфиг для роутера: /root/keenetic-wg.conf"
echo "Скачайте его (scp), импортируйте в Keenetic и удалите с VPS."
