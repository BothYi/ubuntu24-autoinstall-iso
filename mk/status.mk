# ============================================================
# 状态查看: list-packages / status
# ============================================================
list-packages: ## 显示预装软件包列表
	@echo "=== 预装软件包 ==="
	@grep -v '^#' "$(PACKAGES_LIST)" | grep -v '^$$'

status: ## 查看当前构建状态
	@echo "=== 构建状态 ==="
	@echo "原始 ISO:"
	@[ -f "$(ISO_ORIG)" ] && ls -lh "$(ISO_ORIG)" || echo "  ❌ 不存在"
	@echo ""
	@echo "build 目录:"
	@[ -d "$(BUILD_DIR)" ] && echo "  ✅ 存在 ($$(du -sh $(BUILD_DIR) 2>/dev/null | cut -f1))" || echo "  ❌ 不存在"
	@echo ""
	@echo "squashfs-root:"
	@[ -d "$(SQUASHFS_DIR)" ] && echo "  ✅ 存在 ($$(du -sh $(SQUASHFS_DIR) 2>/dev/null | cut -f1))" || echo "  ❌ 不存在"
	@echo ""
	@echo "挂载状态:"
	@if mount | grep -q "$(SQUASHFS_DIR)"; then \
		mount | grep "$(SQUASHFS_DIR)"; \
	else \
		echo "  无绑定挂载"; \
	fi
	@echo ""
	@echo "输出 ISO:"
	@[ -f "$(ISO_NEW)" ] && ls -lh "$(ISO_NEW)" || echo "  ❌ 尚未构建"
