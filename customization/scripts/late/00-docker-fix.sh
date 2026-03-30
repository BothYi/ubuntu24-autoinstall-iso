#!/bin/bash
# 00-docker-fix.sh - 恢复 docker-ce dpkg 元数据
# Ubuntu installer (ubuntu-desktop-minimal) 会把 docker-ce 从 dpkg 里移除
# 本脚本从 squashfs 构建时备份的元数据中恢复

TARGET="${TARGET:-/target}"
BACKUP="$TARGET/opt/docker-dpkg-backup"
LOG="/tmp/post-install.log"

log() { echo "[00-docker-fix] $*" | tee -a "$LOG"; }

if [ ! -d "$BACKUP" ]; then
    log "无备份目录，跳过"
    exit 0
fi

# 逐包检测并恢复
FIXED=0
for status_file in "$BACKUP"/*.status; do
    [ -f "$status_file" ] || continue
    PKG=$(grep "^Package:" "$status_file" | awk '{print $2}')
    [ -z "$PKG" ] && continue

    if grep -q "^Package: $PKG$" "$TARGET/var/lib/dpkg/status" 2>/dev/null; then
        log "$PKG 已在 dpkg，跳过"
    else
        log "恢复 $PKG 到 /target dpkg..."
        echo "" >> "$TARGET/var/lib/dpkg/status"
        cat "$status_file" >> "$TARGET/var/lib/dpkg/status"
        # 恢复 info 文件
        cp "$BACKUP/${PKG}".* "$TARGET/var/lib/dpkg/info/" 2>/dev/null || true
        FIXED=$((FIXED + 1))
    fi
done

[ $FIXED -gt 0 ] && log "✅ 恢复了 $FIXED 个包的 dpkg 元数据" || log "无需恢复"
