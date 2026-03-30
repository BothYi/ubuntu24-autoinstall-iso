# ============================================================
# ISO 构建: nocloud / grub-patch / iso / build + snapshot
# ============================================================
nocloud: ## [5/7] 安装 autoinstall 配置
	@echo "=== [5/7] 安装 autoinstall 配置 ==="
	mkdir -p "$(BUILD_DIR)/nocloud"
	cp "$(PROJECT_ROOT)/config/user-data" "$(BUILD_DIR)/nocloud/user-data"
	cp "$(PROJECT_ROOT)/config/meta-data" "$(BUILD_DIR)/nocloud/meta-data"
	@echo "  ✅ nocloud 配置已拷贝"

grub-patch: ## [6/7] 修改 GRUB 配置注入 autoinstall
	@echo "=== [6/7] 修改 GRUB 配置 ==="
	@bash "$(PROJECT_ROOT)/customization/scripts/grub-patch.sh" "$(BUILD_DIR)"

nocloud-extra: ## 拷贝 app-debs 到 ISO install/ 目录
	@APP_DEBS="$(PROJECT_ROOT)/customization/packages/app-debs"; \
	if [ -d "$$APP_DEBS" ]; then \
		mkdir -p "$(BUILD_DIR)/install/debs"; \
		cp -r "$$APP_DEBS"/. "$(BUILD_DIR)/install/debs/"; \
		echo "  ✅ app-debs 已拷贝到 ISO"; \
	fi

iso: ## [7/7] 重建 ISO 镜像
	@echo "=== [7/7] 重建 ISO ==="
	@echo "  更新 md5sum.txt..."
	@cd "$(BUILD_DIR)" && find . -type f -not -name md5sum.txt -not -path './boot.catalog' -not -path './EFI/*' -exec md5sum {} \; > md5sum.txt
	mkdir -p "$(PROJECT_ROOT)/output"
	xorriso -as mkisofs \
		-r -V "Ubuntu 24.04.4 LTS amd64" \
		-o "$(ISO_NEW)" \
		--grub2-mbr "$(MBR_BIN)" \
		--protective-msdos-label \
		-partition_cyl_align off \
		-partition_offset 16 \
		--mbr-force-bootable \
		-append_partition 2 28732ac11ff8d211ba4b00a0c93ec93b "$(EFI_IMG)" \
		-appended_part_as_gpt \
		-iso_mbr_part_type a2a0d0ebe5b9334487c068b6b72699c7 \
		-c '/boot.catalog' \
		-b '/boot/grub/i386-pc/eltorito.img' \
		-no-emul-boot \
		-boot-load-size 4 \
		-boot-info-table \
		--grub2-boot-info \
		-eltorito-alt-boot \
		-e '--interval:appended_partition_2:::' \
		-no-emul-boot \
		-boot-load-size 10160 \
		"$(BUILD_DIR)"
	@echo ""
	@echo "=== ✅ ISO 构建完成 ==="
	ls -lh "$(ISO_NEW)"

build: extract squashfs-unpack squashfs-install squashfs-repack nocloud nocloud-extra grub-patch iso ## 一键完整构建（需 sudo）
	@echo ""
	@echo "🎉 全部完成！ISO 路径: $(ISO_NEW)"
	@# === 保存 squashfs 快照和描述文件 ===
	@SNAP_DATE=$$(date +%Y%m%d-%H%M); \
	SNAP_DIR="$(PROJECT_ROOT)/snapshots"; \
	mkdir -p "$$SNAP_DIR"; \
	echo "  保存 squashfs 快照: minimal-$$SNAP_DATE.squashfs"; \
	cp "$(BUILD_DIR)/casper/minimal.squashfs" "$$SNAP_DIR/minimal-$$SNAP_DATE.squashfs"; \
	echo "# Squashfs 快照: $$SNAP_DATE" > "$$SNAP_DIR/minimal-$$SNAP_DATE.md"; \
	echo "" >> "$$SNAP_DIR/minimal-$$SNAP_DATE.md"; \
	echo "## 基础信息" >> "$$SNAP_DIR/minimal-$$SNAP_DATE.md"; \
	echo "| 项 | 值 |" >> "$$SNAP_DIR/minimal-$$SNAP_DATE.md"; \
	echo "|---|---|" >> "$$SNAP_DIR/minimal-$$SNAP_DATE.md"; \
	echo "| 构建时间 | $$(date '+%Y-%m-%d %H:%M:%S') |" >> "$$SNAP_DIR/minimal-$$SNAP_DATE.md"; \
	echo "| squashfs 大小 | $$(du -h $(BUILD_DIR)/casper/minimal.squashfs | cut -f1) |" >> "$$SNAP_DIR/minimal-$$SNAP_DATE.md"; \
	echo "| ISO 大小 | $$(du -h $(ISO_NEW) 2>/dev/null | cut -f1) |" >> "$$SNAP_DIR/minimal-$$SNAP_DATE.md"; \
	echo "" >> "$$SNAP_DIR/minimal-$$SNAP_DATE.md"; \
	echo "## 预装软件包" >> "$$SNAP_DIR/minimal-$$SNAP_DATE.md"; \
	grep -v "^#" "$(PACKAGES_LIST)" | grep -v "^$$" | sed "s/^/- /" >> "$$SNAP_DIR/minimal-$$SNAP_DATE.md"; \
	echo "" >> "$$SNAP_DIR/minimal-$$SNAP_DATE.md"; \
	echo "## DKMS 驱动" >> "$$SNAP_DIR/minimal-$$SNAP_DATE.md"; \
	ls $(DKMS_DIR)/*.deb 2>/dev/null | xargs -I{} basename {} | sed "s/^/- /" >> "$$SNAP_DIR/minimal-$$SNAP_DATE.md" || echo "- (无)" >> "$$SNAP_DIR/minimal-$$SNAP_DATE.md"; \
	echo "" >> "$$SNAP_DIR/minimal-$$SNAP_DATE.md"; \
	echo "## 桌面定制" >> "$$SNAP_DIR/minimal-$$SNAP_DATE.md"; \
	cat "$(PROJECT_ROOT)/customization/desktop/dconf/99-custom-defaults" | grep "^\[" | sed "s/^/- /" >> "$$SNAP_DIR/minimal-$$SNAP_DATE.md"; \
	echo "" >> "$$SNAP_DIR/minimal-$$SNAP_DATE.md"; \
	echo "## Docker" >> "$$SNAP_DIR/minimal-$$SNAP_DATE.md"; \
	echo "- docker-ce (阿里云镜像源)" >> "$$SNAP_DIR/minimal-$$SNAP_DATE.md"; \
	echo "- docker-compose ($$($(PROJECT_ROOT)/customization/docker-compose version 2>/dev/null || echo 预编译二进制))" >> "$$SNAP_DIR/minimal-$$SNAP_DATE.md"; \
	echo "" >> "$$SNAP_DIR/minimal-$$SNAP_DATE.md"; \
	echo "## 快捷键" >> "$$SNAP_DIR/minimal-$$SNAP_DATE.md"; \
	echo "- Ctrl+Alt+Shift+H = 活动概览" >> "$$SNAP_DIR/minimal-$$SNAP_DATE.md"; \
	echo "- Super/Fn+放大镜 = 已禁用" >> "$$SNAP_DIR/minimal-$$SNAP_DATE.md"; \
	echo "" >> "$$SNAP_DIR/minimal-$$SNAP_DATE.md"; \
	echo "## 启动与登录" >> "$$SNAP_DIR/minimal-$$SNAP_DATE.md"; \
	echo "- GDM 自动登录 (nguser)" >> "$$SNAP_DIR/minimal-$$SNAP_DATE.md"; \
	echo "- 跳过首次向导" >> "$$SNAP_DIR/minimal-$$SNAP_DATE.md"; \
	echo "- Plymouth Logo: 银河脑科学" >> "$$SNAP_DIR/minimal-$$SNAP_DATE.md"; \
	echo "  ✅ 快照已保存: $$SNAP_DIR/minimal-$$SNAP_DATE.*"

