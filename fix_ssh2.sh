#!/bin/bash
set -v

echo "=== FIX SSH SOCKET ACTIVATION ==="
systemctl stop ssh.socket 2>/dev/null
systemctl disable ssh.socket 2>/dev/null
systemctl stop sshd.socket 2>/dev/null
systemctl disable sshd.socket 2>/dev/null

echo "=== CLEAN sshd_config ==="
# Remove duplicate Port lines
sed -i '/^Port 8022$/d' /etc/ssh/sshd_config
sed -i '/^Port 22$/d' /etc/ssh/sshd_config
# Set single Port 22
sed -i 's/^#*Port.*/Port 22/' /etc/ssh/sshd_config
# Ensure password auth and root login
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
# Show result
grep -E '^Port|^PasswordAuth|^PermitRoot' /etc/ssh/sshd_config

echo "=== RESTART SSHD ==="
systemctl restart sshd
sleep 2
systemctl status sshd | head -8

echo "=== CHECK PORT 22 ==="
ss -tlnp | grep ':22 '

echo "=== LOCAL TEST ==="
timeout 3 bash -c 'echo "" | nc -w2 127.0.0.1 22' 2>&1 | xxd | head -3

echo "=== EXTERNAL TEST (from server itself) ==="
timeout 5 bash -c 'echo "" | nc -w3 72.56.80.169 22' 2>&1 | xxd | head -3

echo "=== CHECK systemd SOCKET FILES ==="
ls -la /etc/systemd/system/ssh.socket 2>/dev/null
ls -la /etc/systemd/system/sshd.socket 2>/dev/null
cat /etc/systemd/system/ssh.socket 2>/dev/null
cat /lib/systemd/system/ssh.socket 2>/dev/null

echo "=== CHECK sshd_config.d ==="
ls -la /etc/ssh/sshd_config.d/ 2>/dev/null
cat /etc/ssh/sshd_config.d/*.conf 2>/dev/null

echo "=== KILL ANY STALE SSH LISTENERS ==="
# Kill any stale hiddify-core that might intercept
ps aux | grep -E 'hiddify-core|xray' | grep -v grep

echo "=== CHECK hiddify-core PORTS ==="
ss -tlnp | grep hiddify

echo "=== TCPDUMP TEST ==="
timeout 8 tcpdump -i eth0 port 22 -c 3 -n 2>&1 &
sleep 1
echo "" | nc -w2 72.56.80.169 22 2>/dev/null
wait
echo ""
echo "=== DONE ==="
