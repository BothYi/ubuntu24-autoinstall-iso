#!/bin/bash
# 06-services.sh - 安装 first-boot service，在系统第一次启动后运行 docker compose up
# chroot 环境下 pivot_root 不支持，无法直接启动容器，改为在正式开机后由 systemd 完成

TARGET="${TARGET:-/target}"
LOG="/tmp/post-install.log"

log() { echo "[06-services] $*" | tee -a "$LOG"; }

# ---- 创建 first-boot 启动脚本 ----
cat > "$TARGET/usr/local/bin/ngiq-first-boot.sh" << 'SCRIPT'
#!/bin/bash
# ngiq-first-boot.sh - 在第一次开机时启动所有 docker-compose 服务
LOG=/var/log/ngiq-first-boot.log

fb_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }
fb_log "=== ngiq first-boot 开始 ==="

# 等待 docker 就绪
for i in $(seq 1 30); do
    docker info &>/dev/null && break
    sleep 2
done
docker info &>/dev/null || { fb_log "ERROR: docker 未就绪"; exit 1; }

# 遍历 /opt/ 下所有有 docker-compose.yml 的目录
for compose_file in /opt/*/docker-compose.yml /opt/*/compose/docker-compose.yml; do
    [ -f "$compose_file" ] || continue
    dir=$(dirname "$compose_file")
    name=$(basename "$(dirname "$compose_file")")
    fb_log "启动 $name ($dir)..."
    cd "$dir" && docker compose up -d 2>&1 | tee -a "$LOG" || fb_log "WARNING: $name 启动失败"
done

# 标记已执行，防止重复
systemctl disable ngiq-first-boot.service 2>/dev/null || true
fb_log "=== ngiq first-boot 完成 ==="
SCRIPT
chmod +x "$TARGET/usr/local/bin/ngiq-first-boot.sh"

# ---- 创建 systemd service ----
cat > "$TARGET/etc/systemd/system/ngiq-first-boot.service" << 'UNIT'
[Unit]
Description=NgIQ First Boot Docker Compose Startup
After=docker.service network-online.target
Wants=docker.service network-online.target
ConditionPathExists=!/var/lib/ngiq-first-boot-done

[Service]
Type=oneshot
ExecStart=/usr/local/bin/ngiq-first-boot.sh
ExecStartPost=/bin/touch /var/lib/ngiq-first-boot-done
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT

# ---- Enable ----
chroot "$TARGET" systemctl enable ngiq-first-boot.service 2>/dev/null || \
    ln -sf /etc/systemd/system/ngiq-first-boot.service \
           "$TARGET/etc/systemd/system/multi-user.target.wants/ngiq-first-boot.service"

log "✅ ngiq-first-boot.service 已安装，将在首次开机启动所有 docker-compose 服务"
