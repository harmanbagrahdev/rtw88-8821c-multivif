#!/bin/bash
# hotspot-off.sh — stop the ap0 hotspot and remove the virtual interface
set -e

echo "Stopping hotspot..."
sudo systemctl stop hostapd.service
sudo systemctl stop hotspot-ap0-dnsmasq.service
sudo systemctl stop hotspot-ap0-iface.service

# Remove the virtual interface entirely so it doesn't linger in a stale
# state until the next hotspot-on run.
if iw dev | grep -q "ap0"; then
    sudo iw dev ap0 del
fi

echo "Hotspot is off."
