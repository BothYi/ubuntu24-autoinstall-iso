#!/bin/bash
# 02-desktop.sh - 桌面配置
# GDM 自动登录、跳过首次设置向导、英文家目录

TARGET="${TARGET:-/target}"
USERNAME="nguser"
USER_HOME="$TARGET/home/$USERNAME"

# GDM 自动登录
sed -i "/\[daemon\]/a AutomaticLoginEnable=true\nAutomaticLogin=$USERNAME" \
    "$TARGET/etc/gdm3/custom.conf" 2>/dev/null || true

# 跳过 GNOME 首次登录向导
mkdir -p "$USER_HOME/.config"
echo "yes" > "$USER_HOME/.config/gnome-initial-setup-done"

# 强制英文家目录（不受 zh_CN locale 影响）
cat > "$USER_HOME/.config/user-dirs.dirs" << 'EOF'
XDG_DESKTOP_DIR="$HOME/Desktop"
XDG_DOWNLOAD_DIR="$HOME/Downloads"
XDG_DOCUMENTS_DIR="$HOME/Documents"
XDG_MUSIC_DIR="$HOME/Music"
XDG_PICTURES_DIR="$HOME/Pictures"
XDG_VIDEOS_DIR="$HOME/Videos"
XDG_TEMPLATES_DIR="$HOME/Templates"
XDG_PUBLICSHARE_DIR="$HOME/Public"
EOF
echo "en_US" > "$USER_HOME/.config/user-dirs.locale"

# 同步到 skel（对未来新建用户生效）
mkdir -p "$TARGET/etc/skel/.config"
cp "$USER_HOME/.config/user-dirs.dirs" "$TARGET/etc/skel/.config/"
cp "$USER_HOME/.config/user-dirs.locale" "$TARGET/etc/skel/.config/"

# 实际创建英文目录（不创建的话 xdg-user-dirs-gtk 会弹窗询问）
for dir in Desktop Downloads Documents Music Pictures Videos Templates Public; do
    mkdir -p "$USER_HOME/$dir"
done

# 禁用 xdg-user-dirs-gtk 弹窗（enabled=False 阻止首次登录时弹出询问）
mkdir -p "$TARGET/etc/xdg"
echo "enabled=False" > "$TARGET/etc/xdg/user-dirs.conf"

# 修正所有权
chown -R 1000:1000 "$USER_HOME"

echo "[02-desktop] 完成"
