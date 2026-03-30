# Ubuntu 24.04 定制桌面版

基于 Ubuntu 24.04.3 Desktop 构建无人值守安装 ISO，支持预装软件、桌面定制、系统配置。

## 目录结构

```
config/           autoinstall 配置（user-data / meta-data）
scripts/          构建脚本和安装后脚本
customization/    定制内容（软件包、桌面、品牌、系统配置）
iso/              原始 ISO 存放（git 忽略）
output/           构建产物输出（git 忽略）
```

## 快速开始

1. 将 `ubuntu-24.04.3-desktop-amd64.iso` 放到 `~/ubuntu24/` 目录
2. 编辑 `config/user-data` 配置安装参数
3. 编辑 `customization/packages.list` 添加预装软件
4. 运行构建：

```bash
make build
```

构建完成的 ISO 将输出到 `output/` 目录。

## 常用命令

```bash
make help           # 查看可用命令
make build          # 构建 ISO
make clean          # 清理构建产物
make list-packages  # 查看预装包列表
```
