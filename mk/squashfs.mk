# ============================================================
# Squashfs 操作: extract / unpack / install / repack
# ============================================================
extract: check-deps ## [1/7] 提取原始 ISO 内容到 build/
	@echo "=== [1/7] 提取 ISO 到 $(BUILD_DIR) ==="
	@if [ -d "$(BUILD_DIR)/casper" ]; then \
		echo "  ⚠️  build/ 已存在，跳过提取。如需重新提取请先 make clean"; \
	else \
		rm -rf "$(BUILD_DIR)"; \
		mkdir -p "$(BUILD_DIR)"; \
		xorriso -osirrox on -indev "$(ISO_ORIG)" -extract / "$(BUILD_DIR)"; \
		chmod -R u+w "$(BUILD_DIR)"; \
		echo "  ✅ ISO 内容已提取"; \
	fi

squashfs-unpack: ## [2/7] 解压 minimal.squashfs 并挂载系统目录
	@echo "=== [2/7] 解压 squashfs ==="
	@if [ ! -f "$(SQUASHFS_FILE)" ]; then \
		echo "❌ $(SQUASHFS_FILE) 不存在，请先执行 make extract"; \
		exit 1; \
	fi
	@# 如果 squashfs-root 已存在，先安全卸载
	@if [ -d "$(SQUASHFS_DIR)" ]; then \
		echo "  squashfs-root 已存在，先卸载并清理..."; \
		$(MAKE) umount; \
		if mount | grep -q "$(SQUASHFS_DIR)"; then \
			echo "❌ 无法卸载！请手动处理"; \
			exit 1; \
		fi; \
		sudo rm -rf "$(SQUASHFS_DIR)"; \
	fi
	sudo unsquashfs -d "$(SQUASHFS_DIR)" "$(SQUASHFS_FILE)"
	@# === 合并 standard 层（解决 Ubuntu 24.04 多层 dpkg/status 覆盖问题）===
	@STANDARD_SQ="$(BUILD_DIR)/casper/minimal.standard.squashfs"; \
	if [ -f "$$STANDARD_SQ" ] && [ $$(stat -c%s "$$STANDARD_SQ") -gt 10000 ]; then \
		echo "  合并 standard 层..."; \
		sudo unsquashfs -d /tmp/standard-layer "$$STANDARD_SQ"; \
		sudo rsync -a /tmp/standard-layer/ "$(SQUASHFS_DIR)/"; \
		sudo rm -rf /tmp/standard-layer; \
		echo "  ✅ standard 层已合并到 squashfs-root"; \
	else \
		echo "  ⏭️ standard 层不存在或已为空，跳过合并"; \
	fi
	@echo "  挂载系统目录..."
	sudo mount --bind /dev "$(SQUASHFS_DIR)/dev"
	sudo mount --bind /proc "$(SQUASHFS_DIR)/proc"
	sudo mount --bind /sys "$(SQUASHFS_DIR)/sys"
	sudo mount --bind /run "$(SQUASHFS_DIR)/run"
	sudo cp /etc/resolv.conf "$(SQUASHFS_DIR)/etc/resolv.conf" 2>/dev/null || true
	@echo "  ✅ squashfs 已解压并挂载系统目录"

squashfs-install: ## [3/7] chroot 安装软件包 + DKMS
	@echo "=== [3/7] 安装软件包 ==="
	@if [ ! -d "$(SQUASHFS_DIR)/usr" ]; then \
		echo "❌ squashfs-root 不存在，请先执行 make squashfs-unpack"; \
		exit 1; \
	fi
	@# 确认系统目录已挂载
	@if ! mount | grep -q "$(SQUASHFS_DIR)/proc"; then \
		echo "  系统目录未挂载，正在挂载..."; \
		sudo mount --bind /dev "$(SQUASHFS_DIR)/dev" 2>/dev/null || true; \
		sudo mount --bind /proc "$(SQUASHFS_DIR)/proc" 2>/dev/null || true; \
		sudo mount --bind /sys "$(SQUASHFS_DIR)/sys" 2>/dev/null || true; \
		sudo mount --bind /run "$(SQUASHFS_DIR)/run" 2>/dev/null || true; \
		sudo cp /etc/resolv.conf "$(SQUASHFS_DIR)/etc/resolv.conf" 2>/dev/null || true; \
	fi
	@# 安装 packages.list 中的软件
	@if [ -f "$(PACKAGES_LIST)" ]; then \
		PACKAGES=$$(grep -v '^#' "$(PACKAGES_LIST)" | grep -v '^$$' | tr '\n' ' '); \
		echo "  安装包: $$PACKAGES"; \
		sudo chroot "$(SQUASHFS_DIR)" /bin/bash -c "apt-get update && apt-get install -y $$PACKAGES && apt-get clean && rm -rf /var/lib/apt/lists/*"; \
	fi
	@# --- FAKE UNAME START ---
	@echo "  创建 fake uname 以骗过 dkms 编译..."
	@sudo mv "$(SQUASHFS_DIR)/bin/uname" "$(SQUASHFS_DIR)/bin/uname.original"
	@sudo bash -c 'printf "#!/bin/sh\nif [ \"\$$1\" = \"-r\" ]; then ls /lib/modules | grep generic | head -1; else /bin/uname.original \"\$$@\"; fi\n" > "$(SQUASHFS_DIR)/bin/uname"'
	@sudo chmod +x "$(SQUASHFS_DIR)/bin/uname"
	@# 安装 DKMS deb 包
	@if [ -d "$(DKMS_DIR)" ] && ls "$(DKMS_DIR)"/*.deb &>/dev/null; then \
		echo "  安装 DKMS 包..."; \
		for deb in $(DKMS_DIR)/*.deb; do \
			echo "    - $$(basename $$deb)"; \
			sudo cp "$$deb" "$(SQUASHFS_DIR)/tmp/"; \
			sudo chroot "$(SQUASHFS_DIR)" /bin/bash -c "dpkg -i /tmp/$$(basename $$deb)" || true; \
			sudo rm -f "$(SQUASHFS_DIR)/tmp/$$(basename $$deb)"; \
		done; \
	fi
	@# 修复 DKMS: 创建标志文件使 DKMS 编译失败时不阻断内核安装
	@echo "  创建 /etc/dkms/no-autoinstall-errors 标志文件..."
	@sudo mkdir -p "$(SQUASHFS_DIR)/etc/dkms"
	@sudo touch "$(SQUASHFS_DIR)/etc/dkms/no-autoinstall-errors"
	@# === 安装 Docker-CE (阿里云镜像源, fake systemctl 绕过 postinst) ===
	@echo "  安装 Docker-CE..."
	@# 创建 fake systemctl 避免 postinst 失败
	@sudo bash -c 'printf "#!/bin/sh\\nexit 0\n" > "$(SQUASHFS_DIR)/usr/bin/systemctl.fake"'
	@sudo chmod +x "$(SQUASHFS_DIR)/usr/bin/systemctl.fake"
	@if [ -f "$(SQUASHFS_DIR)/usr/bin/systemctl" ]; then sudo cp "$(SQUASHFS_DIR)/usr/bin/systemctl" "$(SQUASHFS_DIR)/usr/bin/systemctl.bak"; fi
	@sudo cp "$(SQUASHFS_DIR)/usr/bin/systemctl.fake" "$(SQUASHFS_DIR)/usr/bin/systemctl"
	@sudo chroot "$(SQUASHFS_DIR)" /bin/bash -e -c "\
	  export DEBIAN_FRONTEND=noninteractive && \
	  apt-get update && \
	  apt-get install -y ca-certificates curl gnupg && \
	  install -m 0755 -d /etc/apt/keyrings && \
	  curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg && \
	  chmod a+r /etc/apt/keyrings/docker.gpg && \
	  echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.aliyun.com/docker-ce/linux/ubuntu noble stable' > /etc/apt/sources.list.d/docker.list && \
	  apt-get update && \
	  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin && \
	  docker --version && \
	  apt-get clean && rm -rf /var/lib/apt/lists/*"
	@# 恢复真实 systemctl
	@if [ -f "$(SQUASHFS_DIR)/usr/bin/systemctl.bak" ]; then sudo mv "$(SQUASHFS_DIR)/usr/bin/systemctl.bak" "$(SQUASHFS_DIR)/usr/bin/systemctl"; fi
	@sudo rm -f "$(SQUASHFS_DIR)/usr/bin/systemctl.fake"
	@# fake systemctl 跳过了 enable，这里用真实 systemctl 手动 enable
	@sudo chroot "$(SQUASHFS_DIR)" systemctl enable docker containerd 2>/dev/null || true
	@echo "  验证 docker 安装:"
	@sudo chroot "$(SQUASHFS_DIR)" dpkg -l docker-ce 2>/dev/null | tail -1
	@sudo chroot "$(SQUASHFS_DIR)" systemctl is-enabled docker 2>/dev/null || true
	@# 安装 docker-compose
	@echo "  安装 docker-compose..."
	@sudo cp $(PROJECT_ROOT)/customization/docker-compose "$(SQUASHFS_DIR)/usr/local/bin/docker-compose"
	@sudo chmod +x "$(SQUASHFS_DIR)/usr/local/bin/docker-compose"
	@echo "  ✅ Docker 安装完成"
	@# === 安装 RAID 检测脚本 ===
	@echo "  安装 raid-check.sh..."
	@sudo cp $(PROJECT_ROOT)/customization/scripts/raid-check.sh "$(SQUASHFS_DIR)/usr/local/bin/raid-check.sh"
	@sudo chmod +x "$(SQUASHFS_DIR)/usr/local/bin/raid-check.sh"
	@sudo chroot "$(SQUASHFS_DIR)" which mdadm 2>/dev/null || { \
	  sudo chroot "$(SQUASHFS_DIR)" bash -c 'add-apt-repository -y universe 2>/dev/null || true' && \
	  sudo chroot "$(SQUASHFS_DIR)" apt-get update -qq && \
	  sudo chroot "$(SQUASHFS_DIR)" apt-get install -y mdadm; }
	@echo "  ✅ raid-check.sh 已安装"
	@# === 安装 post-install 模块化脚本 ===
	@echo "  安装 post-install 脚本..."
	@sudo mkdir -p "$(SQUASHFS_DIR)/usr/local/bin/post-install"
	@sudo cp $(PROJECT_ROOT)/customization/scripts/late/*.sh "$(SQUASHFS_DIR)/usr/local/bin/post-install/"
	@sudo chmod +x "$(SQUASHFS_DIR)/usr/local/bin/post-install/"*.sh
	@echo "  ✅ post-install 脚本已安装"
	@# === 禁用系统自动更新 ===
	@echo "  禁用系统自动更新..."
	@sudo chroot "$(SQUASHFS_DIR)" /bin/bash -c "\
	  systemctl disable unattended-upgrades.service 2>/dev/null || true && \
	  systemctl disable apt-daily.timer 2>/dev/null || true && \
	  systemctl disable apt-daily-upgrade.timer 2>/dev/null || true && \
	  systemctl mask unattended-upgrades.service apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true && \
	  systemctl disable update-notifier.service 2>/dev/null || true && \
	  apt-get purge -y update-notifier update-manager 2>/dev/null || true && \
	  apt-get autoremove -y 2>/dev/null || true"
	@sudo bash -c 'printf "APT::Periodic::Update-Package-Lists \"0\";\nAPT::Periodic::Download-Upgradeable-Packages \"0\";\nAPT::Periodic::AutocleanInterval \"0\";\nAPT::Periodic::Unattended-Upgrade \"0\";\n" > "$(SQUASHFS_DIR)/etc/apt/apt.conf.d/20auto-upgrades"'
	@sudo bash -c 'printf "[org.gnome.software]\ndownload-updates=false\ndownload-updates-notify=false\n" >> "$(SQUASHFS_DIR)/etc/dconf/db/local.d/99-custom-defaults" 2>/dev/null || true'
	@echo "  ✅ 自动更新已禁用"
	@# === 桌面定制 ===
	@echo "  安装桌面定制..."
	@sudo mkdir -p "$(SQUASHFS_DIR)/usr/share/gnome-shell/extensions/hide-panel@custom"
	@sudo cp $(PROJECT_ROOT)/customization/desktop/hide-panel-extension/* "$(SQUASHFS_DIR)/usr/share/gnome-shell/extensions/hide-panel@custom/"
	@sudo cp $(PROJECT_ROOT)/customization/desktop/home_background.jpg "$(SQUASHFS_DIR)/usr/share/backgrounds/home_background.jpg"
	@sudo mkdir -p "$(SQUASHFS_DIR)/etc/dconf/db/local.d"
	@sudo cp $(PROJECT_ROOT)/customization/desktop/dconf/99-custom-defaults "$(SQUASHFS_DIR)/etc/dconf/db/local.d/"
	@sudo mkdir -p "$(SQUASHFS_DIR)/etc/dconf/profile"
	@echo "user-db:user" | sudo tee "$(SQUASHFS_DIR)/etc/dconf/profile/user" > /dev/null
	@echo "system-db:local" | sudo tee -a "$(SQUASHFS_DIR)/etc/dconf/profile/user" > /dev/null
	@sudo cp $(PROJECT_ROOT)/customization/desktop/gschema/99_disable-search-key.gschema.override "$(SQUASHFS_DIR)/usr/share/glib-2.0/schemas/"
	@sudo chroot "$(SQUASHFS_DIR)" /bin/bash -c "glib-compile-schemas /usr/share/glib-2.0/schemas/" 2>/dev/null || true
	@# 替换 Plymouth 启动 Logo
	@echo "  替换 Plymouth watermark..."
	@sudo cp $(PROJECT_ROOT)/customization/desktop/plymouth-watermark.png "$(SQUASHFS_DIR)/tmp/plymouth-watermark.png"
	@sudo chroot "$(SQUASHFS_DIR)" /bin/bash -c "cp /tmp/plymouth-watermark.png /usr/share/plymouth/themes/spinner/watermark.png" 2>/dev/null
	@sudo rm -f "$(SQUASHFS_DIR)/tmp/plymouth-watermark.png"
	@# === 安装中文输入法 (ibus-libpinyin) ===
	@echo "  安装中文输入法..."
	@sudo chroot "$(SQUASHFS_DIR)" /bin/bash -c "\
	  export DEBIAN_FRONTEND=noninteractive && \
	  apt-get install -y ibus ibus-libpinyin 2>&1 && \
	  apt-get clean && rm -rf /var/lib/apt/lists/*" 2>&1 | tee /dev/stderr | tail -3 || true
	@# 配置 GNOME 默认输入源：英文键盘 + 中文拼音
	@sudo bash -c 'printf "[org.gnome.desktop.input-sources]\nsources=[(\x27xkb\x27, \x27us\x27), (\x27ibus\x27, \x27libpinyin\x27)]\ncurrent=0\n" >> "$(SQUASHFS_DIR)/etc/dconf/db/local.d/99-custom-defaults"'
	@echo "  ✅ 中文输入法已安装"
	@sudo chroot "$(SQUASHFS_DIR)" /bin/bash -c "dconf update" 2>/dev/null || true
	@# === 创建 apt-get 离线拦截器 ===
	@echo "  创建 apt-get 拦截器以绕过 subiquity 离线内核失败..."
	@sudo bash -c 'printf "#!/bin/bash\nif [[ \"\$$*\" == *\"linux-generic\"* ]] || [[ \"\$$*\" == *\"linux-\"* ]]; then\n  echo \"[Offline Bypass] Skipping apt-get for kernel: \$$*\"\n  exit 0\nfi\nexec /usr/bin/apt-get \"\$$@\"\n" > "$(SQUASHFS_DIR)/usr/local/sbin/apt-get"'
	@sudo chmod +x "$(SQUASHFS_DIR)/usr/local/sbin/apt-get"
	
	@# --- FAKE UNAME CLEANUP ---
	@echo "  恢复原始 uname..."
	@if [ -f "$(SQUASHFS_DIR)/bin/uname.original" ]; then \
		sudo mv "$(SQUASHFS_DIR)/bin/uname.original" "$(SQUASHFS_DIR)/bin/uname"; \
	fi
	@echo "  ✅ 软件包安装完成"


squashfs-repack: umount ## [4/7] 卸载挂载并重新打包 squashfs
	@echo "=== [4/7] 重新打包 squashfs ==="
	@if [ ! -d "$(SQUASHFS_DIR)/usr" ]; then \
		echo "❌ squashfs-root 不存在"; \
		exit 1; \
	fi
	@# 再次确认无残留挂载
	@if mount | grep -q "$(SQUASHFS_DIR)"; then \
		echo "❌ 仍有挂载未卸载，拒绝打包！"; \
		mount | grep "$(SQUASHFS_DIR)"; \
		exit 1; \
	fi
	@echo "  ✅ 确认无挂载残留，开始打包..."
	sudo rm -f "$(SQUASHFS_FILE)"
	sudo mksquashfs "$(SQUASHFS_DIR)" "$(SQUASHFS_FILE)" -comp xz -noappend
	@echo "  ✅ squashfs 打包完成: $$(du -h $(SQUASHFS_FILE) | cut -f1)"
	@# === 替换 standard 层为空 ===
	@echo "  创建空 standard 层..."
	@mkdir -p /tmp/empty-standard
	@sudo mksquashfs /tmp/empty-standard "$(BUILD_DIR)/casper/minimal.standard.squashfs" -noappend 2>/dev/null
	@rm -rf /tmp/empty-standard
	@echo "  ✅ minimal.standard.squashfs 已替换为空层"
	@# === 更新 manifest ===
	@echo "  更新 manifest..."
	@sudo chroot "$(SQUASHFS_DIR)" dpkg-query -W --showformat='$${Package}\t$${Version}\n' > "$(BUILD_DIR)/casper/minimal.manifest" 2>/dev/null || true
	@echo "" > "$(BUILD_DIR)/casper/minimal.standard.manifest"
	@echo "  ✅ manifest 已更新"
