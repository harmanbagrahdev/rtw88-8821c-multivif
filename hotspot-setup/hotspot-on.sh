#!/bin/bash
# hotspot-on.sh — start the ap0 hotspot on demand
set -e

echo "Starting hotspot..."
sudo systemctl start hotspot-ap0-iface.service
sudo systemctl start hotspot-ap0-dnsmasq.service
sudo systemctl start hostapd.service

sleep 1
if systemctl is-active --quiet hostapd.service; then
    echo "Hotspot is up."
else
    echo "Something failed to start. Check with:"
    echo "  systemctl status hotspot-ap0-iface.service hotspot-ap0-dnsmasq.service hostapd.service"
    exit 1
fi
