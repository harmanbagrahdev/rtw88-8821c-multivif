#!/bin/bash
# hotspot-ap0-iface.sh
#
# Creates the ap0 virtual AP interface alongside the main STA interface,
# and sets up NAT so ap0 clients route out through the STA interface.
#
# Run as a systemd oneshot service BEFORE hostapd starts — hostapd needs
# the interface to already exist and be in AP mode.
set -e

STA_IFACE="wlp2s0"   # <-- change to your interface name (check: iw dev)
AP_IFACE="ap0"
AP_IP="192.168.50.1/24"

# Wait for the main interface to exist (driver may still be loading at boot)
for i in $(seq 1 30); do
    if iw dev | grep -q "$STA_IFACE"; then
        break
    fi
    sleep 1
done

# Always start from a clean state: delete any leftover ap0 from a previous
# run before creating a fresh one. Without this, repeated restarts can hit
# stale nl80211 registration state ("Match already configured" errors in
# hostapd, or "Name not unique on network" from iw).
if iw dev | grep -q "$AP_IFACE"; then
    iw dev "$AP_IFACE" del || true
    sleep 2
fi
iw dev "$STA_IFACE" interface add "$AP_IFACE" type __ap
sleep 1

# The interface comes up as type "managed" by default even when created
# with "type __ap" in some driver/kernel combinations — explicitly force
# the type before bringing it up, or hostapd will fail with
# "Could not set interface flags (UP): Device or resource busy".
ip link set "$AP_IFACE" down
iw dev "$AP_IFACE" set type __ap
ip link set "$AP_IFACE" up

ip addr flush dev "$AP_IFACE" 2>/dev/null || true
ip addr add "$AP_IP" dev "$AP_IFACE"

sysctl -w net.ipv4.ip_forward=1

# Idempotent iptables rules (check-then-add, so re-running this script
# doesn't duplicate rules)
iptables -t nat -C POSTROUTING -o "$STA_IFACE" -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -o "$STA_IFACE" -j MASQUERADE
iptables -C FORWARD -i "$STA_IFACE" -o "$AP_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
    iptables -A FORWARD -i "$STA_IFACE" -o "$AP_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -C FORWARD -i "$AP_IFACE" -o "$STA_IFACE" -j ACCEPT 2>/dev/null || \
    iptables -A FORWARD -i "$AP_IFACE" -o "$STA_IFACE" -j ACCEPT
