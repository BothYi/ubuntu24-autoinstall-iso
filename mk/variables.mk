# ============================================================
# 变量定义
# ============================================================
PROJECT_ROOT  := $(shell pwd)
WORKDIR       := /home/nguser/ubuntu24
ISO_ORIG      := $(WORKDIR)/ubuntu-24.04.4-desktop-amd64.iso
BUILD_DIR     := $(WORKDIR)/build
SQUASHFS_DIR  := $(WORKDIR)/squashfs-root
SQUASHFS_FILE := $(BUILD_DIR)/casper/minimal.squashfs

# 启动文件（本地保存）
MBR_BIN := $(PROJECT_ROOT)/boot/mbr.bin
EFI_IMG := $(PROJECT_ROOT)/boot/efi.img

# 定制相关路径
PACKAGES_LIST := $(PROJECT_ROOT)/customization/packages.list
DKMS_DIR      := $(PROJECT_ROOT)/customization/dkms
DESKTOP_DIR   := $(PROJECT_ROOT)/customization/desktop

# 输出
ISO_NEW := $(PROJECT_ROOT)/output/ubuntu-24.04.4-autoinstall.iso
