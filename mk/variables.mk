# ============================================================
# 变量定义（支持环境变量覆盖，用于 CI 环境）
# ============================================================
PROJECT_ROOT  := $(shell pwd)

# CI 环境下通过环境变量注入（本地默认值保持原来路径）
WORKDIR       ?= /home/nguser/ubuntu24
ISO_ORIG      ?= $(WORKDIR)/ubuntu-24.04.4-desktop-amd64.iso
BUILD_DIR     ?= $(WORKDIR)/build
SQUASHFS_DIR  ?= $(WORKDIR)/squashfs-root
SQUASHFS_FILE := $(BUILD_DIR)/casper/minimal.squashfs

# 启动文件（本地保存）
MBR_BIN := $(PROJECT_ROOT)/boot/mbr.bin
EFI_IMG := $(PROJECT_ROOT)/boot/efi.img

# 定制相关路径
PACKAGES_LIST := $(PROJECT_ROOT)/customization/packages.list
DKMS_DIR      := $(PROJECT_ROOT)/customization/dkms
DESKTOP_DIR   := $(PROJECT_ROOT)/customization/desktop

# 输出
ISO_NEW ?= $(PROJECT_ROOT)/output/ubuntu-24.04.4-autoinstall.iso
