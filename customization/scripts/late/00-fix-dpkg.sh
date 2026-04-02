#!/bin/bash
# 00-fix-dpkg.sh - 从 live 系统恢复 squashfs 预装包的 dpkg 状态
# Ubuntu installer 提取 squashfs 后重建 dpkg status，导致预装包"丢失"
# 本脚本从 live 系统的 dpkg status 恢复缺失的记录，并配置 openssh-server

TARGET="${TARGET:-/target}"
LOG="/tmp/post-install.log"

log() { echo "[00-fix-dpkg] $*" | tee -a "$LOG"; }

# ---- 从 live 系统复制 openssh-server 的 dpkg status 到 /target ----
restore_dpkg_status() {
    local pkg="$1"
    if grep -q "^Package: ${pkg}$" "$TARGET/var/lib/dpkg/status" 2>/dev/null; then
        log "$pkg 已在 target dpkg，跳过"
        return 0
    fi

    # 从 live 系统的 dpkg status 提取该包的完整记录
    local status_block
    status_block=$(awk "/^Package: ${pkg}$/,/^$/" /var/lib/dpkg/status)
    if [ -z "$status_block" ]; then
        log "WARNING: live 系统也无 $pkg dpkg 记录"
        return 1
    fi

    log "恢复 $pkg dpkg status..."
    echo "" >> "$TARGET/var/lib/dpkg/status"
    echo "$status_block" >> "$TARGET/var/lib/dpkg/status"

    # 恢复 dpkg info 文件（如果 /target 里缺失）
    for f in /var/lib/dpkg/info/${pkg}.*; do
        local basename
        basename=$(basename "$f")
        [ -f "$TARGET/var/lib/dpkg/info/$basename" ] || cp "$f" "$TARGET/var/lib/dpkg/info/" 2>/dev/null
    done
    return 0
}

# ---- 恢复 openssh-server 及依赖 ----
for pkg in openssh-server openssh-sftp-server; do
    restore_dpkg_status "$pkg"
done

# ---- 生成 SSH host keys（如果不存在）----
if [ ! -f "$TARGET/etc/ssh/ssh_host_rsa_key" ]; then
    log "生成 SSH host keys..."
    chroot "$TARGET" ssh-keygen -A 2>/dev/null || true
fi

# ---- 启用 sshd ----
log "启用 sshd 服务..."
chroot "$TARGET" systemctl enable ssh.service 2>/dev/null || \
    ln -sf /usr/lib/systemd/system/ssh.service \
           "$TARGET/etc/systemd/system/multi-user.target.wants/ssh.service" 2>/dev/null || true

# ---- 确保允许密码登录 ----
if ! grep -q "^PasswordAuthentication yes" "$TARGET/etc/ssh/sshd_config" 2>/dev/null; then
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' "$TARGET/etc/ssh/sshd_config" 2>/dev/null || true
fi

log "✅ openssh-server 配置完成"
