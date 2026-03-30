#!/bin/bash
# Post-installation configuration script
# This script runs on the target system after first boot.
# It can be called via autoinstall late-commands or a systemd oneshot service.
set -e

echo "=== Running post-install configuration ==="

# Example: Set timezone
# timedatectl set-timezone Asia/Shanghai

# Example: Disable automatic updates popup
# sed -i 's/Prompt=lts/Prompt=never/' /etc/update-manager/release-upgrades

# Example: Apply custom desktop settings
# if [ -d /opt/customization/desktop/dconf/user.d ]; then
#     cp /opt/customization/desktop/dconf/user.d/* /etc/dconf/db/local.d/
#     dconf update
# fi

echo "=== Post-install configuration complete ==="
