#!/bin/bash
# install-hotspot.sh
#
# Sets up the actual hotspot on top of the patched driver: creates a
# second virtual interface (ap0), configures hostapd + dnsmasq, and wires
# everything into systemd so it survives reboots.
#
# Run this AFTER installing the driver patch (../install.sh) and after
# confirming `iw list` shows a valid interface combination.
set -e

if [ "$EUID" -ne 0 ]; then
    echo "Run this script with sudo."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "This will set up a WPA2 hotspot on a second virtual interface (ap0)"
echo "while keeping your main WiFi connection alive."
echo ""
read -rp "Your main WiFi interface name (check with 'iw dev', e.g. wlp2s0): " STA_IFACE
read -rp "Hotspot SSID [HarmanHotspot]: " SSID
SSID="${SSID:-HarmanHotspot}"
read -rsp "Hotspot password (min 8 chars): " WPA_PASSPHRASE
echo ""

if [ -z "$STA_IFACE" ] || ! iw dev | grep -q "$STA_IFACE"; then
    echo "Interface '$STA_IFACE' not found via 'iw dev'. Aborting."
    exit 1
fi

if [ "${#WPA_PASSPHRASE}" -lt 8 ]; then
    echo "Password must be at least 8 characters (WPA2 requirement). Aborting."
    exit 1
fi

echo "=== Detecting current channel of $STA_IFACE ==="
# IMPORTANT: both interfaces share one radio and must be on the same
# channel (this is exactly what the unlocked interface combination
# requires: "#channels <= 1"). Hardcoding a channel here was our original
# bug — it must match whatever channel your main connection is actually on,
# which varies by network and can change if you reconnect.
CHANNEL=$(iw dev "$STA_IFACE" info | grep -oP 'channel \K[0-9]+')
if [ -z "$CHANNEL" ]; then
    echo "Could not detect current channel. Is $STA_IFACE connected to a network?"
    echo "Connect it first, then re-run this script."
    exit 1
fi
echo "Detected channel: $CHANNEL"

if [ "$CHANNEL" -gt 14 ]; then
    echo "Warning: channel $CHANNEL is a 5GHz channel. hw_mode=g (2.4GHz) below"
    echo "will not work with this channel. This script currently only supports"
    echo "a 2.4GHz main connection. Edit hostapd.conf's hw_mode manually if"
    echo "you need 5GHz support, and test carefully."
fi

echo "=== Installing packages ==="
pacman -S --needed --noconfirm hostapd dnsmasq

echo "=== Installing interface bring-up script ==="
sed "s/wlp2s0/${STA_IFACE}/g" "$SCRIPT_DIR/hotspot-ap0-iface.sh" > /usr/local/bin/hotspot-ap0-iface.sh
chmod +x /usr/local/bin/hotspot-ap0-iface.sh

echo "=== Writing hostapd config ==="
mkdir -p /etc/hostapd
cat > /etc/hostapd/hostapd.conf <<EOF
interface=ap0
driver=nl80211
ssid=${SSID}
hw_mode=g
channel=${CHANNEL}
wmm_enabled=1
auth_algs=1
wpa=2
wpa_passphrase=${WPA_PASSPHRASE}
wpa_key_mgmt=WPA-PSK
wpa_pairwise=CCMP
rsn_pairwise=CCMP
ieee80211n=1
ht_capab=[HT20]
EOF
chmod 600 /etc/hostapd/hostapd.conf

echo "=== Writing dnsmasq config ==="
cp "$SCRIPT_DIR/dnsmasq_ap0.conf" /etc/dnsmasq_ap0.conf

echo "=== Installing systemd services ==="
cp "$SCRIPT_DIR/hotspot-ap0-iface.service" /etc/systemd/system/
cp "$SCRIPT_DIR/hotspot-ap0-dnsmasq.service" /etc/systemd/system/
mkdir -p /etc/systemd/system/hostapd.service.d
cp "$SCRIPT_DIR/hostapd-override.conf" /etc/systemd/system/hostapd.service.d/override.conf

echo "=== Enabling and starting everything ==="
systemctl daemon-reload
systemctl enable hotspot-ap0-iface.service
systemctl enable hotspot-ap0-dnsmasq.service
systemctl enable hostapd.service
systemctl restart hotspot-ap0-iface.service
systemctl restart hotspot-ap0-dnsmasq.service
systemctl restart hostapd.service

echo ""
echo "=== Done ==="
echo "Check status with:"
echo "  systemctl status hotspot-ap0-iface.service"
echo "  systemctl status hotspot-ap0-dnsmasq.service"
echo "  systemctl status hostapd.service"
echo ""
echo "Connect a device to SSID '${SSID}' to test."
echo ""
echo "Note: if you reconnect $STA_IFACE to a different network/channel later,"
echo "you'll need to update the 'channel=' line in /etc/hostapd/hostapd.conf"
echo "to match, then restart the services above."
