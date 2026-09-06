#!/bin/bash
# install.sh
#
# Applies the AP+STA concurrent-mode patch to a copy of the current kernel's
# rtw88 driver source, and installs it via DKMS so it survives kernel
# updates.
set -e

DKMS_NAME="rtw88-multivif"
DKMS_VERSION="1.0"
DKMS_SRC="/usr/src/${DKMS_NAME}-${DKMS_VERSION}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_FILE="${SCRIPT_DIR}/0001-rtw88-enable-ap-sta-concurrent-mode-for-RTL8821C.patch"

if [ "$EUID" -ne 0 ]; then
    echo "Run this script with sudo."
    exit 1
fi

echo "=== Checking chip ==="
if ! lspci -k 2>/dev/null | grep -qi "RTL8821C"; then
    echo "Warning: couldn't detect an RTL8821C-family chip via lspci."
    echo "This patch is specifically for RTL8821C(E/S/U). Continue anyway? [y/N]"
    read -r ans
    [[ "$ans" =~ ^[Yy]$ ]] || exit 1
fi

echo "=== Installing dependencies (dkms, kernel headers) ==="
if command -v pacman &> /dev/null; then
    pacman -S --needed --noconfirm dkms linux-headers
else
    echo "This install script currently only supports Arch/pacman-based systems."
    echo "See README.md for the manual DKMS steps on other distros."
    exit 1
fi

echo "=== Fetching current kernel's rtw88 driver source ==="
TMP_KERNEL="/tmp/rtw88-source-$$"
mkdir -p "$TMP_KERNEL"
git clone --depth 1 https://github.com/torvalds/linux.git "$TMP_KERNEL"

RTW88_DIR="$TMP_KERNEL/drivers/net/wireless/realtek/rtw88"

echo "=== Applying patch ==="
cd "$TMP_KERNEL"
patch -p1 < "$PATCH_FILE"

echo "=== Packaging as DKMS module ==="
rm -rf "$DKMS_SRC"
mkdir -p "$DKMS_SRC"
cp "$RTW88_DIR"/*.c "$RTW88_DIR"/*.h "$RTW88_DIR"/Makefile "$RTW88_DIR"/Kconfig "$DKMS_SRC"/

cat > "$DKMS_SRC/dkms.conf" <<EOF
PACKAGE_NAME="${DKMS_NAME}"
PACKAGE_VERSION="${DKMS_VERSION}"
BUILT_MODULE_NAME[0]="rtw88_core"
DEST_MODULE_LOCATION[0]="/kernel/drivers/net/wireless/realtek/rtw88"
BUILT_MODULE_NAME[1]="rtw88_8821c"
DEST_MODULE_LOCATION[1]="/kernel/drivers/net/wireless/realtek/rtw88"
BUILT_MODULE_NAME[2]="rtw88_8821ce"
DEST_MODULE_LOCATION[2]="/kernel/drivers/net/wireless/realtek/rtw88"
BUILT_MODULE_NAME[3]="rtw88_pci"
DEST_MODULE_LOCATION[3]="/kernel/drivers/net/wireless/realtek/rtw88"
AUTOINSTALL="yes"
MAKE[0]="make -C \${kernel_source_dir} M=\${dkms_tree}/\${PACKAGE_NAME}/\${PACKAGE_VERSION}/build modules"
CLEAN="make -C \${kernel_source_dir} M=\${dkms_tree}/\${PACKAGE_NAME}/\${PACKAGE_VERSION}/build clean"
EOF

echo "=== Building and installing with DKMS ==="
dkms remove -m "$DKMS_NAME" -v "$DKMS_VERSION" --all 2>/dev/null || true
dkms add -m "$DKMS_NAME" -v "$DKMS_VERSION"
dkms build -m "$DKMS_NAME" -v "$DKMS_VERSION"
dkms install -m "$DKMS_NAME" -v "$DKMS_VERSION" --force

depmod -a

echo ""
echo "=== Done ==="
echo "Reload the driver to apply immediately, or just reboot:"
echo "  sudo modprobe -r rtw88_8821ce rtw88_pci rtw88_8821c rtw88_core"
echo "  sudo modprobe rtw88_8821ce"
echo ""
echo "Verify with:"
echo "  iw list | grep -A5 'valid interface combinations'"
echo ""
echo "See hotspot-setup/ in this repo for setting up an actual hotspot"
echo "using the newly unlocked capability."

rm -rf "$TMP_KERNEL"
