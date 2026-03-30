#!/bin/bash
# 05-desktop-trust.sh - 信任桌面上的 .desktop 文件
# 必须在 04-debs.sh 之后运行（deb 的 postinst 会在桌面创建 .desktop 文件）

TARGET="${TARGET:-/target}"
USER_HOME="$TARGET/home/nguser"
LOG="/tmp/post-install.log"

log() { echo "[05-desktop-trust] $*" | tee -a "$LOG"; }

if [ ! -d "$USER_HOME/Desktop" ]; then
    log "桌面目录不存在，跳过"
    exit 0
fi

TRUSTED=0
for dtfile in "$USER_HOME/Desktop"/*.desktop; do
    [ -f "$dtfile" ] || continue
    # 1. 确保有可执行权限
    chmod +x "$dtfile"
    # 2. 设置 GNOME 信任标记（xattr user.metadata::trusted）
    python3 -c "
import os
try:
    os.setxattr('$dtfile', b'user.metadata::trusted', b'yes')
    print('[05-desktop-trust] xattr 设置成功: $(basename $dtfile)')
except Exception as e:
    print(f'[05-desktop-trust] WARNING: {e}')
" 2>&1 | tee -a "$LOG"
    TRUSTED=$((TRUSTED + 1))
done

log "✅ 共信任 $TRUSTED 个 .desktop 文件"
