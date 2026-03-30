#!/bin/bash
# 04-debs.sh - 从 ISO 安装业务 deb 包
# 关键：生产 dockerd 用 --containerd=/run/containerd/containerd.sock（数据在/var/lib/containerd）
# 必须在安装时也启动系统 containerd 并将数据写入 /target/var/lib/containerd

TARGET="${TARGET:-/target}"
DEB_DIR="/cdrom/install/debs"
LOG="/tmp/post-install.log"
DOCKER_PID=""
CONTAINERD_PID=""
DOCKER_TCP="tcp://127.0.0.1:2375"
CONTAINERD_SOCK="/run/containerd-install/containerd.sock"
MOUNTS_DONE=0

log() { echo "[04-debs] $*" | tee -a "$LOG"; }

# ---- trap 清理（任何退出都执行）----
cleanup() {
    [ -n "$DOCKER_PID" ] && {
        kill "$DOCKER_PID" 2>/dev/null
        wait "$DOCKER_PID" 2>/dev/null || true
    }
    [ -n "$CONTAINERD_PID" ] && {
        kill "$CONTAINERD_PID" 2>/dev/null
        wait "$CONTAINERD_PID" 2>/dev/null || true
    }
    if [ "$MOUNTS_DONE" -eq 1 ]; then
        log "卸载 chroot 挂载点..."
        for mnt in cdrom run dev/pts dev sys/fs/cgroup sys proc; do
            mountpoint -q "$TARGET/$mnt" 2>/dev/null && umount -l "$TARGET/$mnt" 2>/dev/null || true
        done
        MOUNTS_DONE=0
    fi
}
trap cleanup EXIT

# ---- 前置检查 ----
if [ ! -d "$DEB_DIR" ] || [ -z "$(ls "$DEB_DIR"/*.deb 2>/dev/null)" ]; then
    log "无 deb 文件，跳过"
    exit 0
fi

if [ ! -x "$TARGET/usr/bin/dockerd" ]; then
    log "ERROR: $TARGET/usr/bin/dockerd 不存在"
    exit 1
fi

# ---- 停止 live 系统已有的 dockerd ----
stop_live_docker() {
    if pgrep -x dockerd > /dev/null 2>&1; then
        log "停止 live 系统 dockerd..."
        systemctl stop docker containerd 2>/dev/null || pkill -x dockerd 2>/dev/null || true
        sleep 3
        rm -f /var/run/docker.pid /var/run/docker.sock 2>/dev/null || true
        log "live dockerd 已停止"
    fi
}

# ---- 挂载 chroot 所需目录 ----
do_mount() {
    log "挂载 chroot 环境..."
    mount -t proc  proc           "$TARGET/proc"          || true
    mount -t sysfs sysfs          "$TARGET/sys"           || true
    mount --bind   /sys/fs/cgroup "$TARGET/sys/fs/cgroup" || true
    mount --bind   /dev           "$TARGET/dev"           || true
    mount --bind   /dev/pts       "$TARGET/dev/pts"       || true
    mount --bind   /run           "$TARGET/run"           || true
    mount --bind   /cdrom         "$TARGET/cdrom"         || true
    MOUNTS_DONE=1
}

# ---- 启动系统 containerd（写 /target/var/lib/containerd，与生产 dockerd 一致）----
start_containerd() {
    log "启动系统 containerd（socket: $CONTAINERD_SOCK）..."
    # 在 chroot 内，/var/lib/containerd = $TARGET/var/lib/containerd（持久化）
    # socket 在 /run/containerd-install/ = $TARGET/run/containerd-install/（会 bind 到 live /run）
    mkdir -p "$TARGET/run/containerd-install"
    cat > "$TARGET/tmp/containerd-install.toml" << 'EOF'
version = 2
root = "/var/lib/containerd"
state = "/run/containerd-install"
[grpc]
  address = "/run/containerd-install/containerd.sock"
EOF
    chroot "$TARGET" containerd --config /tmp/containerd-install.toml >> "$LOG" 2>&1 &
    CONTAINERD_PID=$!

    for i in $(seq 1 15); do
        [ -S "$TARGET/run/containerd-install/containerd.sock" ] && {
            log "containerd 就绪（PID=$CONTAINERD_PID）"
            return 0
        }
        sleep 2
    done
    log "ERROR: containerd 启动超时"
    return 1
}

# ---- 启动 dockerd（指向上面的 containerd）----
start_docker() {
    log "启动 dockerd（$DOCKER_TCP，使用系统 containerd）..."
    chroot "$TARGET" dockerd \
        -H "$DOCKER_TCP" \
        --data-root /var/lib/docker \
        --containerd="$CONTAINERD_SOCK" \
        >> "$LOG" 2>&1 &
    DOCKER_PID=$!

    for i in $(seq 1 30); do
        if chroot "$TARGET" docker -H "$DOCKER_TCP" info &>/dev/null; then
            log "dockerd 就绪（PID=$DOCKER_PID）"
            return 0
        fi
        sleep 2
    done
    log "ERROR: dockerd 启动超时（60s）"
    return 1
}

# ---- 安装 deb ----
install_debs() {
    log "安装 $(ls "$DEB_DIR"/*.deb | wc -l) 个 deb..."
    chroot "$TARGET" /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive
        export DOCKER_HOST='$DOCKER_TCP'
        dpkg -i /cdrom/install/debs/*.deb
    "
    RET=$?
    if [ $RET -eq 0 ]; then
        log "✅ 安装完成"
    else
        log "WARNING: dpkg 返回 $RET（部分 postinst 失败，通常为容器启动问题，开机后正常）"
    fi
    return 0  # 不因 postinst 失败而中止安装
}

# ---- 主流程 ----
stop_live_docker
do_mount
start_containerd || exit 1
start_docker || exit 1
install_debs
exit $?
