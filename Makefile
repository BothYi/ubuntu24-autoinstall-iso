# ============================================================
# Ubuntu 24.04 自定义 Autoinstall ISO 构建工具
# ============================================================
# 用法: make build      一键完整构建
#       make help       显示所有目标
#       make status     查看构建状态
# ============================================================

.DEFAULT_GOAL := help
SHELL := /bin/bash

# 加载各模块
include mk/variables.mk
include mk/setup.mk
include mk/squashfs.mk
include mk/iso.mk
include mk/status.mk
