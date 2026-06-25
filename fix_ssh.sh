#!/bin/bash
# CUPOL SSH Recovery & VPN Fix Script
# Run as root on the NL server (72.56.80.169)
set -v

echo "=== STEP 1: DIAGNOSE PORT 22 ==="
echo "--- All xray processes ---"
ps aux | grep xray | grep -v grep

echo "--- All listening TCP ports ---"
ss -tlnp | sort

echo "--- All listening UDP ports ---"
ss -ulnp

echo "--- Local SSH test on 22 ---"
timeout 3 bash -c 'echo "" | nc -w2 127.0.0.1 22' 2>&1 | xxd | head -3

echo "--- Local SSH test on 2222 ---"
timeout 3 bash -c 'echo "" | nc -w2 127.0.0.1 2222' 2>&1 | xxd | head -3

echo "--- Find ALL xray configs ---"
find / -name "config*.json" -path "*/xray/*" 2>/dev/null
find / -name "config*.json" -path "*/cupol*" 2>/dev/null | head -10

echo "--- cupol-xray service ---"
systemctl status cupol-xray 2>/dev/null | head -10
cat /etc/systemd/system/cupol-xray.service 2>/dev/null

echo "--- hiddify-xray service ---"
systemctl status hiddify-xray 2>/dev/null | head -10
cat /etc/systemd/system/hiddify-xray.service 2>/dev/null
cat /etc/systemd/system/hiddify-xray.service.d/override.conf 2>/dev/null

echo "--- HAProxy full config ---"
cat /etc/haproxy/haproxy.cfg 2>/dev/null

echo "--- nftables full ---"
nft list ruleset 2>/dev/null

echo "--- iptables NAT ---"
iptables -t nat -L -n -v --line-numbers 2>/dev/null

echo "--- iptables FILTER ---"
iptables -L INPUT -n -v --line-numbers 2>/dev/null

echo "--- iptables MANGLE ---"
iptables -t mangle -L -n -v --line-numbers 2>/dev/null

echo "--- Docker containers ---"
docker ps -a 2>/dev/null

echo "--- Docker network ---"
docker network ls 2>/dev/null

echo "--- Check for TPROXY/REDIRECT in nft ---"
nft list ruleset 2>/dev/null | grep -i -E 'tproxy|redirect|dnat|snat|masquerade|port 22'

echo "--- Check for any process binding port 22 ---"
lsof -i :22 2>/dev/null || ss -tlnp | grep :22

echo "--- Check sshd_config ---"
grep -E '^#?Port|^#?ListenAddress|^#?PasswordAuth|^#?PermitRoot' /etc/ssh/sshd_config

echo "--- Check /etc/ssh/sshd_config.d/ ---"
ls -la /etc/ssh/sshd_config.d/ 2>/dev/null
cat /etc/ssh/sshd_config.d/*.conf 2>/dev/null

echo "--- Check hosts.allow / hosts.deny ---"
cat /etc/hosts.allow 2>/dev/null
cat /etc/hosts.deny 2>/dev/null

echo "--- Check fail2ban ---"
fail2ban-client status sshd 2>/dev/null

echo "=== STEP 2: FIND AND KILL PORT 22 INTERCEPTOR ==="

# Check if cupol-xray config has port 22
for cfg in /usr/local/etc/xray/config*.json; do
    if [ -f "$cfg" ]; then
        has22=$(python3 -c "import json; c=json.load(open('$cfg')); print(any(i.get('port')==22 for i in c.get('inbounds',[])))" 2>/dev/null)
        echo "Config $cfg has port 22: $has22"
        if [ "$has22" = "True" ]; then
            echo "REMOVING port 22 from $cfg"
            python3 -c "
import json
p='$cfg'
c=json.load(open(p))
b=len(c.get('inbounds',[]))
c['inbounds']=[i for i in c.get('inbounds',[]) if i.get('port')!=22]
a=len(c['inbounds'])
json.dump(c,open(p,'w'),indent=2)
print(f'Removed {b-a} inbound(s) on port 22 from $cfg')
"
        fi
    fi
done

# Check Hiddify xray configs
for cfg in /opt/hiddify-manager/*/xray/config.json /opt/hiddify-manager/hiddify-panel/assets/xray/config.json; do
    if [ -f "$cfg" ]; then
        has22=$(python3 -c "import json; c=json.load(open('$cfg')); print(any(i.get('port')==22 for i in c.get('inbounds',[])))" 2>/dev/null)
        echo "Hiddify config $cfg has port 22: $has22"
        if [ "$has22" = "True" ]; then
            echo "REMOVING port 22 from $cfg"
            python3 -c "
import json
p='$cfg'
c=json.load(open(p))
b=len(c.get('inbounds',[]))
c['inbounds']=[i for i in c.get('inbounds',[]) if i.get('port')!=22]
a=len(c['inbounds'])
json.dump(c,open(p,'w'),indent=2)
print(f'Removed {b-a} inbound(s) on port 22 from $cfg')
"
        fi
    fi
done

# Check for any xray config with port 22 anywhere
echo "--- Searching ALL json files for port 22 inbound ---"
find /opt/hiddify-manager /usr/local/etc/xray /etc/xray -name "*.json" -exec grep -l '"port": 22' {} \; 2>/dev/null

echo "=== STEP 3: RESTART XRAY ==="
systemctl restart cupol-xray 2>/dev/null
sleep 2
systemctl status cupol-xray 2>/dev/null | head -5

# Stop hiddify-xray if it's conflicting
systemctl stop hiddify-xray 2>/dev/null
systemctl disable hiddify-xray 2>/dev/null

echo "=== STEP 4: FIX SSH ==="
# Ensure SSH config
sed -i 's/^#*Port 22/Port 22/' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config

# Remove extra Port 2222 lines if any
sed -i '/^Port 2222$/d' /etc/ssh/sshd_config

# Check sshd_config.d for overrides
for f in /etc/ssh/sshd_config.d/*.conf; do
    if [ -f "$f" ]; then
        echo "Fixing $f"
        sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' "$f" 2>/dev/null
        sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' "$f" 2>/dev/null
    fi
done

# Clear fail2ban bans
fail2ban-client unban --all 2>/dev/null

# Restart SSH
systemctl restart sshd
sleep 2
systemctl status sshd | head -5

echo "=== STEP 5: RESTART SING-BOX (Hysteria2 + TUIC) ==="
pkill -f 'sing-box run' 2>/dev/null
sleep 2

# Check if hiddify-singbox is running
systemctl status hiddify-singbox 2>/dev/null | head -5

# Start sing-box manually if hiddify service is not managing it properly
if ! systemctl is-active hiddify-singbox 2>/dev/null | grep -q active; then
    echo "hiddify-singbox not active, starting manually..."
    nohup /usr/bin/sing-box run -c /usr/local/etc/sing-box/config.json >> /var/log/sing-box.log 2>&1 &
    sleep 3
else
    systemctl restart hiddify-singbox
    sleep 3
fi

echo "--- Verify UDP ports ---"
ss -ulnp | grep -E '38858|56804'

echo "=== STEP 6: RUN SYNC ==="
/opt/cupol/sync_vpn_configs.sh 2>&1 || true

echo "=== STEP 7: RESTART API ==="
docker restart cupol-api 2>/dev/null
sleep 5

echo "=== STEP 8: VERIFY ==="
echo "--- SSH port 22 ---"
ss -tlnp | grep ':22 '
echo "--- Local SSH banner ---"
timeout 3 bash -c 'echo "" | nc -w2 127.0.0.1 22' 2>&1 | xxd | head -3
echo "--- External SSH banner (from server itself) ---"
timeout 5 bash -c 'echo "" | nc -w3 72.56.80.169 22' 2>&1 | xxd | head -3
echo "--- UDP Hysteria2 ---"
ss -ulnp | grep 38858
echo "--- UDP TUIC ---"
ss -ulnp | grep 56804
echo "--- Xray processes ---"
ps aux | grep xray | grep -v grep
echo "--- Sing-box processes ---"
ps aux | grep sing-box | grep -v grep
echo "--- Health check ---"
curl -sk https://127.0.0.1/health 2>/dev/null
echo ""
echo "--- Docker containers ---"
docker ps 2>/dev/null
echo "=== DONE ==="
