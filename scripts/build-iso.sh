#!/bin/bash
# Repack Ubuntu 24.04 Desktop ISO with autoinstall
# - Customize squashfs (pre-install packages from packages.list)
# - Add extras/ directory (deb packages for late-commands)
# - Add autoinstall config (nocloud)
set -e

# Project root is one level up from scripts/
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKDIR=/home/nguser/ubuntu24
ISO_ORIG="$WORKDIR/ubuntu-24.04.3-desktop-amd64.iso"
ISO_NEW="$PROJECT_ROOT/output/ubuntu-24.04.3-autoinstall.iso"
BUILD_DIR="$WORKDIR/build"
MBR_BIN="$WORKDIR/mbr.bin"
EFI_IMG="$WORKDIR/efi.img"
SQUASHFS_DIR="$WORKDIR/squashfs-root"

echo "=== Ubuntu 24.04 Autoinstall ISO Builder ==="
echo "  Project root: $PROJECT_ROOT"

# Check dependencies
for cmd in xorriso unsquashfs mksquashfs; do
    if ! command -v $cmd &>/dev/null; then
        echo "Installing missing tools..."
        sudo apt-get install -y xorriso squashfs-tools
        break
    fi
done

# Clean up previous build
rm -rf "$BUILD_DIR" "$SQUASHFS_DIR"
mkdir -p "$BUILD_DIR"

# Extract ISO contents
echo "[1/7] Extracting ISO contents..."
xorriso -osirrox on -indev "$ISO_ORIG" -extract / "$BUILD_DIR"
chmod -R u+w "$BUILD_DIR"

# Customize squashfs: pre-install packages
echo "[2/7] Customizing squashfs (pre-installing packages)..."
SQUASHFS_FILE="$BUILD_DIR/casper/minimal.squashfs"
if [ -f "$SQUASHFS_FILE" ]; then
    sudo unsquashfs -d "$SQUASHFS_DIR" "$SQUASHFS_FILE"

    # Mount necessary filesystems
    sudo mount --bind /dev "$SQUASHFS_DIR/dev"
    sudo mount --bind /proc "$SQUASHFS_DIR/proc"
    sudo mount --bind /sys "$SQUASHFS_DIR/sys"
    sudo mount --bind /run "$SQUASHFS_DIR/run"
    sudo cp /etc/resolv.conf "$SQUASHFS_DIR/etc/resolv.conf"

    # Install packages from packages.list
    PACKAGES_LIST="$PROJECT_ROOT/customization/packages.list"
    if [ -f "$PACKAGES_LIST" ]; then
        PACKAGES=$(grep -v '^#' "$PACKAGES_LIST" | grep -v '^$' | tr '\n' ' ')
        echo "  Installing packages: $PACKAGES"
        sudo chroot "$SQUASHFS_DIR" /bin/bash -c "apt-get update && apt-get install -y $PACKAGES && apt-get clean && rm -rf /var/lib/apt/lists/*"
    fi

    # Install DKMS deb packages from customization/dkms/
    DKMS_DIR="$PROJECT_ROOT/customization/dkms"
    if [ -d "$DKMS_DIR" ] && ls "$DKMS_DIR"/*.deb &>/dev/null; then
        echo "  Installing DKMS packages..."
        for deb in "$DKMS_DIR"/*.deb; do
            echo "    - $(basename $deb)"
            sudo cp "$deb" "$SQUASHFS_DIR/tmp/"
            sudo chroot "$SQUASHFS_DIR" /bin/bash -c "dpkg -i /tmp/$(basename $deb)"
            sudo rm -f "$SQUASHFS_DIR/tmp/$(basename $deb)"
        done
    fi

    # Cleanup
    sudo umount "$SQUASHFS_DIR/dev" 2>/dev/null || true
    sudo umount "$SQUASHFS_DIR/proc" 2>/dev/null || true
    sudo umount "$SQUASHFS_DIR/sys" 2>/dev/null || true
    sudo umount "$SQUASHFS_DIR/run" 2>/dev/null || true

    # Repack squashfs
    echo "  Repacking squashfs..."
    sudo rm -f "$SQUASHFS_FILE"
    sudo mksquashfs "$SQUASHFS_DIR" "$SQUASHFS_FILE" -comp xz -noappend
    sudo rm -rf "$SQUASHFS_DIR"
    echo "  Squashfs customization complete."
else
    echo "  WARNING: $SQUASHFS_FILE not found, skipping squashfs customization."
fi

# Create nocloud directory and copy autoinstall config
echo "[3/7] Adding autoinstall configuration..."
mkdir -p "$BUILD_DIR/nocloud"
cp "$PROJECT_ROOT/config/user-data" "$BUILD_DIR/nocloud/user-data"
cp "$PROJECT_ROOT/config/meta-data" "$BUILD_DIR/nocloud/meta-data"

# Copy extras directory (deb packages for late-commands)
echo "[4/7] Copying extras directory..."
EXTRAS_DIR="$PROJECT_ROOT/customization/extras"
if [ -d "$EXTRAS_DIR" ] && [ "$(ls -A $EXTRAS_DIR 2>/dev/null)" ]; then
    mkdir -p "$BUILD_DIR/extras"
    cp "$EXTRAS_DIR"/* "$BUILD_DIR/extras/"
    echo "  Extras copied: $(ls $BUILD_DIR/extras/)"
else
    echo "  No extras found, skipping."
fi

# Copy customization files if they exist
if [ -d "$PROJECT_ROOT/customization/system/etc" ]; then
    echo "  Copying system customization files..."
    cp -r "$PROJECT_ROOT/customization/system/etc" "$BUILD_DIR/" 2>/dev/null || true
fi

# Modify GRUB config
echo "[5/7] Modifying GRUB configuration..."
GRUB_CFG="$BUILD_DIR/boot/grub/grub.cfg"
if [ -f "$GRUB_CFG" ]; then
    sed -i 's|---| autoinstall ds=nocloud\\;s=/cdrom/nocloud/ ---|g' "$GRUB_CFG"
    echo "  GRUB config updated. Preview:"
    grep -n "autoinstall" "$GRUB_CFG" | head -3
fi

# Extract MBR and EFI partition from original ISO
echo "[6/7] Extracting boot records from original ISO..."
dd if="$ISO_ORIG" bs=1 count=446 of="$MBR_BIN" 2>/dev/null
echo "  MBR extracted."

EFI_START=$((3095872 * 512))
EFI_SIZE=$((10160 * 512))
dd if="$ISO_ORIG" bs=1 skip=$EFI_START count=$EFI_SIZE of="$EFI_IMG" 2>/dev/null
echo "  EFI partition extracted ($(du -h "$EFI_IMG" | cut -f1))."

# Rebuild ISO
echo "[7/7] Rebuilding ISO..."
mkdir -p "$PROJECT_ROOT/output"
xorriso -as mkisofs \
    -r -V "Ubuntu 24.04.3 LTS amd64" \
    -o "$ISO_NEW" \
    --grub2-mbr "$MBR_BIN" \
    --protective-msdos-label \
    -partition_cyl_align off \
    -partition_offset 16 \
    --mbr-force-bootable \
    -append_partition 2 28732ac11ff8d211ba4b00a0c93ec93b "$EFI_IMG" \
    -appended_part_as_gpt \
    -iso_mbr_part_type a2a0d0ebe5b9334487c068b6b72699c7 \
    -c '/boot.catalog' \
    -b '/boot/grub/i386-pc/eltorito.img' \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    --grub2-boot-info \
    -eltorito-alt-boot \
    -e '--interval:appended_partition_2:::' \
    -no-emul-boot \
    -boot-load-size 10160 \
    "$BUILD_DIR"

echo ""
echo "=== Done! ==="
ls -lh "$ISO_NEW"

# Clean up
rm -rf "$BUILD_DIR" "$MBR_BIN" "$EFI_IMG"
echo "Build directory cleaned up."
