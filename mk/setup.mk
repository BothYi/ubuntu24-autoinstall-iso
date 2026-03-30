# ============================================================
# 基础设施: help / check-deps / clean / umount
# ============================================================
.PHONY: help check-deps clean umount

help: ## 显示帮助信息
	@echo "Ubuntu 24.04 自定义 Autoinstall ISO 构建工具"
	@echo ""
	@echo "用法: make [目标]"
	@echo ""
	@echo "目标:"
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

umount: ## 安全卸载 squashfs-root 下所有绑定挂载
	@echo "=== 检查并卸载 squashfs-root 绑定挂载 ==="
	@for mp in run sys proc dev; do \
		if mount | grep -q "$(SQUASHFS_DIR)/$$mp"; then \
			echo "  卸载 $(SQUASHFS_DIR)/$$mp ..."; \
			sudo umount -lf "$(SQUASHFS_DIR)/$$mp" 2>/dev/null || true; \
		fi; \
	done
	@echo "✅ 所有绑定挂载已安全卸载（或本来就没有挂载）"

clean: umount ## 安全清理 build/ 和 squashfs-root/（含 umount 检查）
	@echo "=== 清理构建环境 ==="
	@if [ -d "$(BUILD_DIR)" ]; then \
		echo "  删除 $(BUILD_DIR) ..."; \
		sudo rm -rf "$(BUILD_DIR)"; \
	fi
	@if [ -d "$(SQUASHFS_DIR)" ]; then \
		echo "  删除 $(SQUASHFS_DIR) ..."; \
		sudo rm -rf "$(SQUASHFS_DIR)"; \
	fi
	@echo "✅ 清理完成"

check-deps: ## 检查并安装依赖工具
	@echo "=== 检查依赖 ==="
	@for cmd in xorriso mksquashfs unsquashfs; do \
		if ! command -v $$cmd &>/dev/null; then \
			echo "  安装 $$cmd ..."; \
			sudo apt-get install -y xorriso squashfs-tools; \
			break; \
		fi; \
	done
	@echo "  ✅ 所有依赖就绪"
