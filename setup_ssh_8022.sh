#!/bin/bash
# Setup SSH on port 8022 (bypasses DPI on port 22)
# Run as root on any CUPOL server
set -v

echo "=== DISABLE SSH SOCKET ACTIVATION ==="
systemctl stop ssh.socket 2>/dev/null
systemctl disable ssh.socket 2>/dev/null
systemctl stop sshd.socket 2>/dev/null
systemctl disable sshd.socket 2>/dev/null

echo "=== CONFIGURE SSHD ==="
# Remove any existing Port 8022
sed -i '/^Port 8022$/d' /etc/ssh/sshd_config
# Add Port 8022 alongside existing Port 22
echo "Port 8022" >> /etc/ssh/sshd_config
# Ensure password auth and root login
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
# Fix sshd_config.d overrides
for f in /etc/ssh/sshd_config.d/*.conf; do
    [ -f "$f" ] && sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' "$f" 2>/dev/null
done

echo "=== RESTART SSHD ==="
systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
sleep 2

echo "=== OPEN UFW PORT 8022 ==="
if ufw status | grep -q "Status: active"; then
    ufw allow 8022/tcp
    echo "UFW: port 8022 opened"
else
    echo "UFW: inactive, no action needed"
fi

echo "=== VERIFY ==="
ss -tlnp | grep 8022
echo "=== DONE ==="
