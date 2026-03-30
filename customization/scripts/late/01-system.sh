#!/bin/bash
# 01-system.sh - 系统配置
# 清理 OEM 源、netplan、禁用时间同步

TARGET="${TARGET:-/target}"

# 清理 Dell OEM apt 源（防止有网时自动拉 OEM 包）
rm -f "$TARGET"/etc/apt/sources.list.d/oem-*.list

# 清理 installer 生成的 netplan 配置
rm -f "$TARGET/etc/netplan/00-installer-config.yaml"

# 禁用自动时间同步（timesyncd）
ln -sf /dev/null "$TARGET/etc/systemd/system/systemd-timesyncd.service" 2>/dev/null || true

# 禁用 TTY 切换（Ctrl+Alt+F2-F6）
# 若启动时携带 debug_tty=1 参数则跳过，保留 TTY 供调试
if grep -q 'debug_tty=1' /proc/cmdline 2>/dev/null; then
    echo "[01-system] debug_tty=1 检测到，保留 TTY 切换"
else
    echo "[01-system] 禁用 TTY 切换（mask getty@tty2-6）"
    for tty in 2 3 4 5 6; do
        ln -sf /dev/null "$TARGET/etc/systemd/system/getty@tty${tty}.service"
    done
fi



# ---- 禁用 APT 自动更新，锁定当前内核版本 ----
echo "[01-system] 禁用 APT 自动更新..."
# 禁用 periodic 更新
sed -i 's/^APT::Periodic::Update-Package-Lists .*/APT::Periodic::Update-Package-Lists "0";/' \
    "$TARGET/etc/apt/apt.conf.d/10periodic" 2>/dev/null || true
sed -i 's/1/0/g' "$TARGET/etc/apt/apt.conf.d/20auto-upgrades" 2>/dev/null || true
# 确保文件存在且配置正确
cat > "$TARGET/etc/apt/apt.conf.d/10periodic" << 'APT_EOF'
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Download-Upgradeable-Packages "0";
APT::Periodic::AutocleanInterval "0";
APT::Periodic::Unattended-Upgrade "0";
APT_EOF
cat > "$TARGET/etc/apt/apt.conf.d/20auto-upgrades" << 'APT_EOF'
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Unattended-Upgrade "0";
APT_EOF
# 锁定当前内核（不允许通过 apt 自动升级）
KERNEL_VER=$(ls "$TARGET/boot/vmlinuz-"* 2>/dev/null | sort -V | tail -1 | sed 's|.*/vmlinuz-||')
if [ -n "$KERNEL_VER" ]; then
    echo "[01-system] 锁定内核版本: $KERNEL_VER"
    chroot "$TARGET" apt-mark hold "linux-image-$KERNEL_VER" "linux-headers-$KERNEL_VER" 2>/dev/null || true
    chroot "$TARGET" apt-mark hold linux-generic linux-image-generic linux-headers-generic 2>/dev/null || true
fi

# ---- 隐藏 GRUB 内核选择菜单 ----
echo "[01-system] 设置 GRUB_TIMEOUT=0 (隐藏内核菜单)..."
GRUB_CONF="$TARGET/etc/default/grub"
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' "$GRUB_CONF"
grep -q '^GRUB_TIMEOUT_STYLE=' "$GRUB_CONF" \
    && sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/' "$GRUB_CONF" \
    || echo 'GRUB_TIMEOUT_STYLE=hidden' >> "$GRUB_CONF"
sed -i 's/^GRUB_RECORDFAIL_TIMEOUT=.*/GRUB_RECORDFAIL_TIMEOUT=0/' "$GRUB_CONF" || true
grep -q '^GRUB_RECORDFAIL_TIMEOUT=' "$GRUB_CONF" \
    || echo 'GRUB_RECORDFAIL_TIMEOUT=0' >> "$GRUB_CONF"
chroot "$TARGET" update-grub 2>&1 | tee -a "$LOG" || true

# ---- 配置 UFW 防火墙（监控子网访问特定端口）----
echo "[01-system] 配置 UFW..."
chroot "$TARGET" /bin/bash -c "
    systemctl enable ufw 2>&1
    ufw --force enable
    ufw allow from 172.30.0.0/24 to any port 9633
    ufw allow from 172.30.0.0/24 to any port 9100
    ufw allow from 172.30.0.0/24 to any port 9835
" 2>&1 | tee -a "$LOG" || true

echo "[01-system] 完成"
