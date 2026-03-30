#!/bin/bash
# raid-check.sh - 自动检测两块机械盘并管理 RAID-1
# 运行于 autoinstall early-commands 阶段

set -e
LOG="/tmp/raid-check.log"
MD_DEV="/dev/md0"

log() { echo "[raid-check] $*" | tee -a "$LOG"; }

log "=== 开始 RAID 检测 ==="

# 确保 mdadm 可用
if ! command -v mdadm &>/dev/null; then
    log "ERROR: mdadm 未找到，退出"
    exit 1
fi

# 找到已经运行中的 md 设备（系统 boot 时可能自动组装）
find_active_md() {
    # 查找正在运行的 md 设备（排除 md_d 等特殊设备）
    for md in /dev/md[0-9]* /dev/md/[0-9]*; do
        [ -b "$md" ] && echo "$md" && return 0
    done
    return 1
}

# 自动识别机械盘（排除 U 盘/启动盘）
DISK_A=""
DISK_B=""
for dev in /sys/block/sd*; do
    [ -e "$dev" ] || continue
    name=$(basename "$dev")
    path="/dev/$name"

    ro=$(cat "$dev/ro" 2>/dev/null)
    [ "$ro" = "1" ] && continue

    if lsblk -no MOUNTPOINTS "$path" 2>/dev/null | grep -qiE "cdrom|/run/live|ventoy|casper|/rofs"; then
        echo "[raid-check] 跳过 $path（启动盘）" | tee -a "$LOG"
        continue
    fi

    echo "[raid-check] 候选机械盘: $path ($(lsblk -dno SIZE "$path" 2>/dev/null))" | tee -a "$LOG"

    if [ -z "$DISK_A" ]; then
        DISK_A="$path"
    elif [ -z "$DISK_B" ]; then
        DISK_B="$path"
        break
    fi
done

log "磁盘 A: ${DISK_A:-<未检测到>}"
log "磁盘 B: ${DISK_B:-<未检测到>}"

if [ -z "$DISK_A" ] || [ -z "$DISK_B" ]; then
    log "ERROR: 找到的机械盘不足 2 块"
    lsblk | tee -a "$LOG"
    exit 1
fi

# 检测 RAID 超级块
A_UUID=$(mdadm --examine "$DISK_A" 2>/dev/null | awk '/Array UUID/{print $NF}' || true)
B_UUID=$(mdadm --examine "$DISK_B" 2>/dev/null | awk '/Array UUID/{print $NF}' || true)

log "磁盘A RAID UUID: ${A_UUID:-<无>}"
log "磁盘B RAID UUID: ${B_UUID:-<无>}"

if [ -z "$A_UUID" ] && [ -z "$B_UUID" ]; then
    log "情况1: 两盘均无 RAID 信息 → 新建 RAID-1"
    # 停止可能已自动组装的 md
    ACTIVE_MD=$(find_active_md || true)
    if [ -n "$ACTIVE_MD" ]; then
        log "停止已有 md 设备: $ACTIVE_MD"
        mdadm --stop "$ACTIVE_MD" 2>&1 | tee -a "$LOG" || true
    fi
    wipefs -af "$DISK_A" 2>&1 | tee -a "$LOG"
    wipefs -af "$DISK_B" 2>&1 | tee -a "$LOG"
    mdadm --create "$MD_DEV" \
        --level=1 \
        --raid-devices=2 \
        --metadata=1.2 \
        --run \
        --force \
        "$DISK_A" "$DISK_B" 2>&1 | tee -a "$LOG"
    log "✅ RAID-1 新建完成"

elif [ -n "$A_UUID" ] && [ -n "$B_UUID" ]; then
    if [ "$A_UUID" = "$B_UUID" ]; then
        log "情况2a: 两盘 UUID 一致 → 处理已有 RAID"

        # 检查系统是否已自动组装（可能是 md127 等非 md0 设备）
        ACTIVE_MD=$(find_active_md || true)
        if [ -n "$ACTIVE_MD" ] && [ "$ACTIVE_MD" != "$MD_DEV" ]; then
            log "系统已自动组装为 $ACTIVE_MD，重命名为 $MD_DEV"
            # 停止当前设备，用 --homehost 重组为 md0
            mdadm --stop "$ACTIVE_MD" 2>&1 | tee -a "$LOG" || true
            sleep 1
            mdadm --assemble "$MD_DEV" "$DISK_A" "$DISK_B" \
                --update=name 2>&1 | tee -a "$LOG" || \
            mdadm --assemble --run --force "$MD_DEV" "$DISK_A" "$DISK_B" 2>&1 | tee -a "$LOG" || true
        elif [ -n "$ACTIVE_MD" ] && [ "$ACTIVE_MD" = "$MD_DEV" ]; then
            log "已有 $MD_DEV，无需重组装"
        else
            log "尝试组装 $MD_DEV"
            mdadm --assemble "$MD_DEV" "$DISK_A" "$DISK_B" 2>&1 | tee -a "$LOG" || \
            mdadm --assemble --run --force "$MD_DEV" "$DISK_A" "$DISK_B" 2>&1 | tee -a "$LOG" || true
        fi
        log "✅ RAID 处理完成"
    else
        log "ERROR: 两盘 RAID UUID 不一致！"
        log "  磁盘A UUID: $A_UUID"
        log "  磁盘B UUID: $B_UUID"
        echo ""
        echo "=========================================="
        echo " ❌ RAID 错误：两块磁盘 RAID UUID 不一致"
        echo "    $DISK_A: $A_UUID"
        echo "    $DISK_B: $B_UUID"
        echo "  请手动处理后重新安装！"
        echo "=========================================="
        exit 1
    fi

elif [ -n "$A_UUID" ] && [ -z "$B_UUID" ]; then
    log "情况3: 磁盘A有RAID，磁盘B无 → 将B加入已有阵列"
    ACTIVE_MD=$(find_active_md || true)
    if [ -n "$ACTIVE_MD" ] && [ "$ACTIVE_MD" != "$MD_DEV" ]; then
        log "重命名 $ACTIVE_MD 为 $MD_DEV"
        mdadm --stop "$ACTIVE_MD" 2>&1 | tee -a "$LOG" || true
        sleep 1
    fi
    wipefs -af "$DISK_B" 2>&1 | tee -a "$LOG"
    mdadm --assemble --run "$MD_DEV" "$DISK_A" 2>&1 | tee -a "$LOG" || true
    mdadm "$MD_DEV" --add "$DISK_B" 2>&1 | tee -a "$LOG"
    log "✅ 磁盘B已加入阵列"

elif [ -z "$A_UUID" ] && [ -n "$B_UUID" ]; then
    log "情况4: 磁盘B有RAID，磁盘A无 → 将A加入已有阵列"
    ACTIVE_MD=$(find_active_md || true)
    if [ -n "$ACTIVE_MD" ] && [ "$ACTIVE_MD" != "$MD_DEV" ]; then
        log "重命名 $ACTIVE_MD 为 $MD_DEV"
        mdadm --stop "$ACTIVE_MD" 2>&1 | tee -a "$LOG" || true
        sleep 1
    fi
    wipefs -af "$DISK_A" 2>&1 | tee -a "$LOG"
    mdadm --assemble --run "$MD_DEV" "$DISK_B" 2>&1 | tee -a "$LOG" || true
    mdadm "$MD_DEV" --add "$DISK_A" 2>&1 | tee -a "$LOG"
    log "✅ 磁盘A已加入阵列"
fi

# 等待 md0 就绪（同时兼容系统可能仍用 md127）
log "等待 md 设备就绪..."
FINAL_MD=""
for i in $(seq 1 30); do
    if [ -b "$MD_DEV" ]; then
        FINAL_MD="$MD_DEV"
        break
    fi
    # 也检查 md127 等备选
    ACTIVE_MD=$(find_active_md || true)
    if [ -n "$ACTIVE_MD" ]; then
        FINAL_MD="$ACTIVE_MD"
        break
    fi
    sleep 1
done

if [ -z "$FINAL_MD" ]; then
    log "ERROR: md 设备 30 秒内未就绪"
    cat /proc/mdstat | tee -a "$LOG"
    exit 1
fi

log "使用 md 设备: $FINAL_MD"

# 检查文件系统
FS_TYPE=$(blkid -o value -s TYPE "$FINAL_MD" 2>/dev/null || true)
if [ -z "$FS_TYPE" ]; then
    log "格式化 $FINAL_MD 为 ext4..."
    mkfs.ext4 -F -L "data" "$FINAL_MD" 2>&1 | tee -a "$LOG"
    log "✅ ext4 格式化完成"
else
    log "$FINAL_MD 已有文件系统: $FS_TYPE，跳过格式化"
fi

# 确保 /dev/md0 存在（供 fstab LABEL=data 使用）
if [ "$FINAL_MD" != "$MD_DEV" ] && [ ! -b "$MD_DEV" ]; then
    log "创建 $MD_DEV 软链接 → $FINAL_MD"
    ln -sf "$FINAL_MD" "$MD_DEV" 2>/dev/null || true
fi

mdadm --detail --scan > /tmp/mdadm-scan.conf
log "=== RAID 检测处理完成 ==="
cat /proc/mdstat | tee -a "$LOG"
