I ran into this exact wall (RTL8821CE, "interface combinations are not
supported" in `iw list`) and dug into why.

Turns out it's not a hardware/firmware limitation — mainline `rtw88`
(`drivers/net/wireless/realtek/rtw88/main.c`) only enables the
`iface_combinations` capability for `RTW_CHIP_TYPE_8822C`. RTL8821C is
never included in that check, even though it's the same chip family and
Realtek's own vendor SDK ships concurrent mode as a standard feature across
this family.

Two-line patch fixes it. I packaged it as a DKMS module (survives kernel
updates) plus a working hostapd/dnsmasq/systemd setup for actually running
the hotspot on a second virtual interface while staying connected:

https://github.com/<your-username>/rtw88-8821c-multivif

Tested working on a Dell Inspiron 15 3535 (RTL8821CE), Arch Linux, kernel
7.2.2. Real throughput hit when both are active (single antenna/radio,
forced same channel) but it genuinely works — no dongle needed.

If anyone here has an 8821C-family chip (especially the CS/CU variants,
which I haven't tested), I'd appreciate test reports either way — trying to
build confidence toward submitting this to linux-wireless eventually.
