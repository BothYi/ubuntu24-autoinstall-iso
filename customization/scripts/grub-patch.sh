#!/bin/bash
# grub-patch.sh - 注入 autoinstall 参数并添加 Debug 菜单
# 用法: grub-patch.sh <build_dir>

BUILD_DIR="${1:?用法: grub-patch.sh <build_dir>}"
GRUB_CFG="$BUILD_DIR/boot/grub/grub.cfg"
LOOPBACK_CFG="$BUILD_DIR/boot/grub/loopback.cfg"

patch_grub() {
    local cfg="$1"
    [ -f "$cfg" ] || return 0

    if grep -q 'autoinstall' "$cfg"; then
        echo "  ⚠️  $(basename $cfg) 已包含 autoinstall 配置，跳过"
        return 0
    fi

    # 注入 autoinstall 参数（\; 是 GRUB 中分号的转义，必须保留）
    sed -i 's|---| autoinstall ds=nocloud\\;s=/cdrom/nocloud/ ---|g' "$cfg"
    echo "  ✅ $(basename $cfg) 已修改"
    grep -n "autoinstall" "$cfg" | head -3

    # 追加 Debug 菜单（含 debug_tty=1，保留 TTY 切换供调试）
    cat >> "$cfg" << 'GRUB_ENTRY'

menuentry "[DEBUG] Autoinstall (TTY enabled)" {
	set gfxpayload=keep
	linux	/casper/vmlinuz autoinstall ds=nocloud\;s=/cdrom/nocloud/ debug_tty=1 --- quiet splash
	initrd	/casper/initrd
}
GRUB_ENTRY
    echo "  ✅ Debug 菜单已添加到 $(basename $cfg)"
}

if [ ! -f "$GRUB_CFG" ]; then
    echo "❌ grub.cfg 不存在: $GRUB_CFG"
    exit 1
fi

patch_grub "$GRUB_CFG"
patch_grub "$LOOPBACK_CFG"
