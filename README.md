# RTL8821C(E) AP+STA Concurrent Mode for Linux (rtw88)

Enables simultaneous WiFi client (STA) + hotspot (AP) mode on RTL8821C-family
chips using the mainline Linux `rtw88` driver — no USB dongle, no ethernet
cable.

## The problem

If you have a laptop with an RTL8821CE (or likely RTL8821CS/CU) WiFi chip,
running `iw list` shows:

```
interface combinations are not supported
```

This means you can't stay connected to WiFi while also hosting a hotspot from
the same card — even though Windows' proprietary Realtek driver on the exact
same hardware supports this ("Mobile Hotspot" while connected).

## The actual cause

The in-tree `rtw88` driver (`drivers/net/wireless/realtek/rtw88/main.c`) only
enables the `iface_combinations` capability for the **RTW_CHIP_TYPE_8822C**
chip. RTL8821C — a closely related chip in the same family — is simply never
included in that check. This isn't a hardware/firmware limitation; it's a gap
in the upstream driver that appears to have existed since the driver was
first submitted to the kernel (multi-interface support was explicitly noted
as unsupported in the original 2019 driver submission and, as far as I can
find, was only ever partially addressed for the 8822C chip).

Realtek's own vendor SDK for this chip family (used in embedded/Android
products) ships `CONFIG_CONCURRENT_MODE` as a standard build option across
nearly every platform profile — strong evidence the firmware itself supports
concurrent operation, and this really is just a missing `||` in the Linux
driver.

## The fix

A two-line patch (see `0001-rtw88-enable-ap-sta-concurrent-mode-for-RTL8821C.patch`)
that adds `RTW_CHIP_TYPE_8821C` to the existing chip check.

## Tested on

- Dell Inspiron 15 3535, RTL8821CE (PCIe), firmware 24.11.0 / H2C version 12,
  Arch Linux, kernel 7.2.2

**Not yet tested on**: RTL8821CS (SDIO) or RTL8821CU (USB) variants, other
laptop models, or under sustained heavy dual-mode load over long periods.
If you try this on different hardware, please open an issue with your
results (working or not) — this helps build confidence for eventually
submitting this upstream to the linux-wireless mailing list.

## Installation (Arch Linux / DKMS)

This installs the patch as a DKMS module, so it automatically rebuilds every
time your kernel updates — no manual rebuilding needed after a `pacman -Syu`.

```bash
git clone https://github.com/harmanbagrahdev/rtw88-8821c-multivif.git
cd rtw88-8821c-multivif
sudo ./install.sh
```

See `install.sh` for exactly what it does — in short: clones the mainline
kernel source (needed to get a matching version of the driver source to
patch; this is a ~300MB clone and takes a couple of minutes), applies the
patch, registers/builds/installs the result via DKMS.

## Setting up the actual hotspot

Getting the driver to *advertise* AP+STA support is only half the job — you
also need to actually create a second virtual interface and run a hotspot on
it. `hotspot-setup/install-hotspot.sh` does this for you:

```bash
cd rtw88-8821c-multivif/hotspot-setup
sudo ./install-hotspot.sh
```

It will ask for your main WiFi interface name, an SSID, and a password, then:

- Creates a second `ap0` virtual interface alongside your main WiFi interface
- Auto-detects the channel your main connection is currently on and matches
  the hotspot to it (**both interfaces must share one channel** — this is a
  hard requirement of the interface combination this patch unlocks, not a
  script limitation)
- Sets up NAT so `ap0` clients get internet routed through your main
  interface
- Wires everything into three ordered systemd services so it survives
  reboots

If you later reconnect your main interface to a different network (a
different channel), you'll need to update `channel=` in
`/etc/hostapd/hostapd.conf` to match and restart the services — the script
doesn't currently handle this automatically.

## Known limitations

- Both interfaces must share the **same channel** (`#channels <= 1` in the
  advertised combination) — you can't be on channel 6 for your main
  connection and host the hotspot on channel 11.
- Since it's a single radio being time-shared, expect a real throughput hit
  on both connections compared to using the radio for one job. In my
  testing: ~60-70 MB/s on the direct WiFi connection alone, ~30 MB/s through
  the hotspot while both were active.
- Single antenna (no MIMO) on this chip regardless of this patch.
- This has not been submitted to/reviewed by the upstream `rtw88`
  maintainers yet. It works reliably in my testing but carries the usual
  caveats of an unofficial, community patch to a kernel driver.

## Why I'm sharing this

I found this gap while trying to solve the exact "why can't Linux do what
Windows does on this same chip" problem, dug through kernel source, git
history, and Realtek's own vendor driver source to find and fix it. If you
have this exact chip and have been told "just buy a USB dongle," this might
save you the purchase.

Issues, test reports (positive or negative), and PRs welcome.
