#!/bin/bash
# 07-release-info.sh - 将发布信息写入目标系统
# ISO 根目录的 /cdrom/release.json 由 CI 构建时写入

TARGET="${TARGET:-/target}"
LOG="/tmp/post-install.log"
SRC="/cdrom/release.json"
DEST="$TARGET/etc/release.json"

log() { echo "[07-release-info] $*" | tee -a "$LOG"; }

if [ -f "$SRC" ]; then
    cp "$SRC" "$DEST"
    chmod 644 "$DEST"
    log "release.json 已写入 $DEST"
else
    log "WARNING: $SRC 不存在，跳过"
fi
