#!/bin/bash
# 03-storage.sh - 存储配置
# 持久化 mdadm RAID 配置、创建 /data 挂载点、写入 fstab、更新 initramfs

TARGET="${TARGET:-/target}"

# 持久化 mdadm 配置（确保重启后 RAID 自动识别）
mkdir -p "$TARGET/etc/mdadm"
mdadm --detail --scan >> "$TARGET/etc/mdadm/mdadm.conf" 2>/dev/null || true

# 更新 initramfs（使 mdadm 配置生效）
chroot "$TARGET" update-initramfs -u 2>&1 || true

# 创建 /data 挂载点
mkdir -p "$TARGET/data"

# 写入 fstab（用 LABEL=data，mkfs.ext4 格式化时已加 -L data）
if ! grep -q "LABEL=data" "$TARGET/etc/fstab" 2>/dev/null; then
    echo "LABEL=data  /data  ext4  defaults,nofail  0  2" >> "$TARGET/etc/fstab"
fi

echo "[03-storage] 完成"
