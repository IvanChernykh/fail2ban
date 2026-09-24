#!/bin/bash
# ============================================================
#  diagnose_ssh.sh — диагностика SSH и настройка входа root
#  по паролю. Запускать от имени root.
# ============================================================

set -euo pipefail

# ---------- Шаг 1. Проверка прав root ----------
if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Скрипт должен быть запущен от имени root."
    exit 1
fi
echo "[OK] Скрипт запущен от root."

# ---------- Шаг 2. Определение порта SSH ----------
SSH_PORT=""

# 2.1. Из sshd_config
if [[ -f /etc/ssh/sshd_config ]]; then
    PORT_FROM_CONF=$(grep -i '^[[:space:]]*Port[[:space:]]' /etc/ssh/sshd_config \
        | awk '{print $2}' | head -n1)
    if [[ -n "$PORT_FROM_CONF" ]]; then
        SSH_PORT="$PORT_FROM_CONF"
        echo "[INFO] Порт SSH из sshd_config: $SSH_PORT"
    fi
fi

# 2.2. Из слушающих сокетов (ss)
if [[ -z "$SSH_PORT" ]]; then
    PORT_FROM_SS=$(ss -tlnp 2>/dev/null | grep -i sshd | awk '{print $4}' \
        | sed 's/.*://' | head -n1)
    if [[ -n "$PORT_FROM_SS" ]]; then
        SSH_PORT="$PORT_FROM_SS"
        echo "[INFO] Порт SSH из ss: $SSH_PORT"
    fi
fi

# 2.3. Из процессов sshd
if [[ -z "$SSH_PORT" ]]; then
    PORT_FROM_PS=$(ps aux | grep -i '[s]shd' | grep -oP '(?<=-p )\d+' | head -n1)
    if [[ -n "$PORT_FROM_PS" ]]; then
        SSH_PORT="$PORT_FROM_PS"
        echo "[INFO] Порт SSH из процессов: $SSH_PORT"
    fi
fi

# Значение по умолчанию
if [[ -z "$SSH_PORT" ]]; then
    SSH_PORT=22
    echo "[WARN] Не удалось определить порт SSH, используется значение по умолчанию: 22"
fi

# ---------- Шаг 3. Удаление парольной фразы из ключей root ----------
SSH_DIR="/root/.ssh"
if [[ -d "$SSH_DIR" ]]; then
    echo "[INFO] Поиск приватных ключей в $SSH_DIR ..."
    shopt -s nullglob
    for keyfile in "$SSH_DIR"/*; do
        # Пропускаем публичные ключи, known_hosts, config и т.п.
        [[ "$keyfile" == *.pub ]] && continue
        [[ "$(basename "$keyfile")" == known_hosts* ]] && continue
        [[ "$(basename "$keyfile")" == config ]] && continue
        [[ "$(basename "$keyfile")" == authorized_keys ]] && continue

        # Проверяем, является ли файл приватным ключом
        if ! head -n1 "$keyfile" | grep -q 'PRIVATE KEY'; then
            continue
        fi

        echo "[INFO] Обработка ключа: $keyfile"
        # Попытка удалить парольную фразу (если она есть).
        # Если ключ без пароля — ssh-keygen вернёт ошибку, но это не критично.
        if ssh-keygen -p -P "" -N "" -f "$keyfile" 2>/dev/null; then
            echo "[OK] Парольная фраза удалена (или её не было): $keyfile"
        else
            echo "[WARN] Не удалось автоматически удалить парольную фразу для $keyfile."
            echo "       Возможно, ключ защищён паролем, который не является пустым."
            echo "       Выполните вручную: ssh-keygen -p -f $keyfile"
        fi
    done
    shopt -u nullglob
else
    echo "[WARN] Каталог $SSH_DIR не существует. Пропускаем шаг удаления парольной фразы."
fi

# ---------- Шаг 4. Настройка sshd_config ----------
SSHD_CONFIG="/etc/ssh/sshd_config"
if [[ ! -f "$SSHD_CONFIG" ]]; then
    echo "[ERROR] Файл $SSHD_CONFIG не найден."
    exit 1
fi

# Резервная копия
BACKUP="${SSHD_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
cp -a "$SSHD_CONFIG" "$BACKUP"
echo "[INFO] Создана резервная копия: $BACKUP"

# 4.1. PermitRootLogin yes
if grep -qi '^[[:space:]]*PermitRootLogin' "$SSHD_CONFIG"; then
    sed -i 's/^[[:space:]]*PermitRootLogin.*/PermitRootLogin yes/I' "$SSHD_CONFIG"
    echo "[OK] PermitRootLogin установлен в yes."
else
    echo "PermitRootLogin yes" >> "$SSHD_CONFIG"
    echo "[OK] Добавлен параметр PermitRootLogin yes."
fi

# 4.2. PasswordAuthentication yes
if grep -qi '^[[:space:]]*PasswordAuthentication' "$SSHD_CONFIG"; then
    sed -i 's/^[[:space:]]*PasswordAuthentication.*/PasswordAuthentication yes/I' "$SSHD_CONFIG"
    echo "[OK] PasswordAuthentication установлен в yes."
else
    echo "PasswordAuthentication yes" >> "$SSHD_CONFIG"
    echo "[OK] Добавлен параметр PasswordAuthentication yes."
fi

# ---------- Шаг 5. Перезапуск SSH ----------
echo "[INFO] Перезапуск службы SSH ..."
if systemctl restart ssh 2>/dev/null; then
    echo "[OK] Служба ssh перезапущена."
elif systemctl restart sshd 2>/dev/null; then
    echo "[OK] Служба sshd перезапущена."
else
    echo "[WARN] Не удалось перезапустить SSH через systemctl. Перезапустите вручную."
fi

# ---------- Шаг 6. Финальная диагностика ----------
echo ""
echo "========== ИТОГОВАЯ ДИАГНОСТИКА =========="
echo "Порт SSH: $SSH_PORT"
echo "Статус SSH:"
systemctl is-active ssh 2>/dev/null || systemctl is-active sshd 2>/dev/null || echo "  (не удалось определить)"
echo ""
echo "Приватные ключи в /root/.ssh:"
ls -la /root/.ssh 2>/dev/null || echo "  (каталог отсутствует)"
echo ""
echo "Значения в $SSHD_CONFIG:"
grep -iE '^\s*(PermitRootLogin|PasswordAuthentication)' "$SSHD_CONFIG" || echo "  (параметры не найдены)"
echo ""
echo "[DONE] Скрипт завершён."