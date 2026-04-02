# ============================================================
# ISO 组装: nocloud / grub-patch / nocloud-extra / scripts / iso
# ============================================================
scripts: ## 拷贝自定义脚本到 ISO（/cdrom/scripts/）
	@echo "=== 安装自定义脚本 ==="
	mkdir -p "$(BUILD_DIR)/scripts/late"
	cp "$(PROJECT_ROOT)/customization/scripts/raid-check.sh" "$(BUILD_DIR)/scripts/"
	cp "$(PROJECT_ROOT)/customization/scripts/late/"*.sh "$(BUILD_DIR)/scripts/late/"
	chmod +x "$(BUILD_DIR)/scripts/"*.sh "$(BUILD_DIR)/scripts/late/"*.sh
	@echo "  ✅ 脚本已拷贝到 ISO"

nocloud: ## 拷贝 autoinstall 配置
	@echo "=== 安装 autoinstall 配置 ==="
	mkdir -p "$(BUILD_DIR)/nocloud"
	cp "$(PROJECT_ROOT)/config/user-data" "$(BUILD_DIR)/nocloud/user-data"
	cp "$(PROJECT_ROOT)/config/meta-data" "$(BUILD_DIR)/nocloud/meta-data"
	@echo "  ✅ nocloud 配置已拷贝"

nocloud-extra: ## 拷贝 app-debs 到 ISO install/ 目录
	@APP_DEBS="$(PROJECT_ROOT)/customization/packages/app-debs"; \
	if [ -d "$$APP_DEBS" ]; then \
		mkdir -p "$(BUILD_DIR)/install/debs"; \
		cp -r "$$APP_DEBS"/. "$(BUILD_DIR)/install/debs/"; \
		echo "  ✅ app-debs 已拷贝到 ISO"; \
	fi

grub-patch: ## 修改 GRUB 配置注入 autoinstall
	@echo "=== 修改 GRUB 配置 ==="
	@bash "$(PROJECT_ROOT)/customization/scripts/grub-patch.sh" "$(BUILD_DIR)"

iso: ## 重建 ISO 镜像
	@echo "=== 重建 ISO ==="
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
	@echo "  保存 squashfs 快照..."
	@mkdir -p "$(PROJECT_ROOT)/snapshots"
	@cp "$(BUILD_DIR)/casper/minimal.squashfs" "$(PROJECT_ROOT)/snapshots/minimal-$$(date +%Y%m%d-%H%M).squashfs"
	@echo "  ✅ 快照已保存: $(PROJECT_ROOT)/snapshots/minimal-$$(date +%Y%m%d-%H%M).squashfs"

.PHONY: scripts nocloud nocloud-extra grub-patch iso build extract squashfs-unpack squashfs-install squashfs-repack
