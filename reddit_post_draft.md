Title: Got AP+STA concurrent mode (WiFi hotspot while connected) working on RTL8821CE — turns out it's just a missing chip check in rtw88, not a hardware limit

Body:

If you've got a laptop with a Realtek RTL8821CE and have run into "interface
combinations are not supported" when trying to use nmcli/hostapd to run a
hotspot while staying connected to WiFi — I dug into why, and it turns out
it's not a hardware/firmware limitation at all.

The mainline `rtw88` driver only enables AP+STA concurrent mode for the
RTW_CHIP_TYPE_8822C chip specifically. RTL8821C (same family, different
chip ID) never got the same check added, even though Realtek's own vendor
SDK for this chip family ships concurrent mode as a standard feature and
Windows' proprietary driver supports it fine on the exact same hardware.

Turned out to be a two-line fix. Packaged it as a DKMS module so it survives
kernel updates, plus a hostapd/dnsmasq/systemd setup for the actual hotspot
part.

Repo with the patch, install script, and full writeup:
https://github.com/harmanbagrahdev/rtw88-8821c-multivif

Tested on a Dell Inspiron 15 3535 (RTL8821CE) on Arch, kernel 7.2.2. Speed
takes a real hit when both are active at once (single antenna, single radio,
forced same-channel) — went from ~60-70MB/s on plain WiFi to ~30MB/s through
the hotspot — but it works, no dongle needed.

If anyone else has this chip (or the SDIO/USB variants — RTL8821CS/CU) and
wants to test it, I'd genuinely appreciate hearing whether it works for you
too — trying to gauge if this is solid enough to eventually submit upstream
to linux-wireless.
