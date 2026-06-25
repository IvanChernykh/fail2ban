#!/bin/bash
# Универсальный скрипт настройки Fail2Ban (мягкий режим + полный белый список)

set -e

echo "=== Настройка Fail2Ban на $(hostname) ==="

# ----- 1. Установка (если отсутствует) -----
if ! command -v fail2ban-client &> /dev/null; then
    echo "Устанавливаем fail2ban..."
    apt update
    apt install -y fail2ban
else
    echo "fail2ban уже установлен."
fi

# ----- 2. Остановка и очистка -----
echo "Останавливаем и чистим..."
systemctl stop fail2ban || true
rm -f /var/lib/fail2ban/fail2ban.sqlite3 /var/run/fail2ban/fail2ban.sock

# ----- 3. Белый список (все известные + 136.169.210.190) -----
ALLOWED_IPS="127.0.0.1 88.201.206.127 72.56.80.169 5.42.118.132 93.100.153.107 5.42.101.71 84.201.167.222 77.88.8.8 62.50.146.35 5.23.54.205 178.156.169.131 80.90.183.55 136.169.210.190"

# ----- 4. Создание jail.local -----
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 1h
findtime = 1h
maxretry = 10
backend = systemd
ignoreip = $ALLOWED_IPS

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
backend = %(sshd_backend)s
bantime = 1h
findtime = 1h
maxretry = 10
ignoreip = $ALLOWED_IPS
EOF

echo "✅ /etc/fail2ban/jail.local создан."

# ----- 5. Проверка конфига -----
if fail2ban-client -t; then
    echo "✅ Конфигурация верна."
else
    echo "❌ Ошибка конфигурации!"
    exit 1
fi

# ----- 6. Запуск и автозагрузка -----
systemctl start fail2ban
systemctl enable fail2ban

# ----- 7. Снятие банов -----
fail2ban-client unban --all

# ----- 8. Статус -----
echo "=== Статус sshd ==="
fail2ban-client status sshd
echo "=== Игнорируемые IP ==="
fail2ban-client get sshd ignoreip

echo "✅ Настройка завершена!"