#!/bin/bash
# post-install/main.sh
# 安装完成后的配置主入口，按顺序调用各模块
# 运行环境：autoinstall late-commands，/target 为已安装的系统

set -eo pipefail
SCRIPT_DIR="/usr/local/bin/post-install"
LOG="/target/var/log/post-install.log"

log() { echo "[post-install] $*" | tee -a "$LOG"; }

mkdir -p "$(dirname $LOG)"
log "=== 开始 post-install ==="

for module in "$SCRIPT_DIR"/[0-9][0-9]-*.sh; do
    [ -f "$module" ] || continue
    log "--- 执行: $(basename $module) ---"
    if ! bash "$module" 2>&1 | tee -a "$LOG"; then
        log "ERROR: $(basename $module) 失败，中止安装"
        exit 1
    fi
    log "--- 完成: $(basename $module) ---"
done

log "=== post-install 全部完成 ==="
