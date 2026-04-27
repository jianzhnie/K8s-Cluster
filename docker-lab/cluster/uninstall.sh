#!/bin/bash
# Must be run with sudo

TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
REAL_USER=${SUDO_USER:-$(whoami)}

echo "===================================================="
echo "  DOCKER UNINSTALLER - $TIMESTAMP"
echo "===================================================="

# 1. Stop and Disable Service
echo "[$TIMESTAMP] [INFO] Stopping and disabling Docker service..."
systemctl stop docker 2>/dev/null || true
systemctl disable docker 2>/dev/null || true

# 2. Remove Binaries
echo "[$TIMESTAMP] [INFO] Removing Docker binaries from /usr/bin..."
rm -f /usr/bin/docker \
      /usr/bin/dockerd \
      /usr/bin/docker-proxy \
      /usr/bin/docker-init \
      /usr/bin/containerd \
      /usr/bin/containerd-shim-runc-v2 \
      /usr/bin/ctr \
      /usr/bin/runc

# 3. Remove Systemd Service
echo "[$TIMESTAMP] [INFO] Removing systemd service unit..."
rm -f /etc/systemd/system/docker.service
systemctl daemon-reload

# 4. Remove Configuration (Optional but recommended for clean slate)
echo "[$TIMESTAMP] [INFO] Removing docker configuration directory..."
rm -rf /etc/docker

# 5. Clean Data (Interactive Prompt)
echo "----------------------------------------------------"
read -p "Do you want to delete ALL Docker data (images, containers, volumes) in /var/lib/docker? [y/N]: " CONFIRM
if [[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]]; then
    echo "[$TIMESTAMP] [INFO] Wiping /var/lib/docker..."
    # Unmount any remaining overlays if necessary
    umount /var/lib/docker/overlay2 2>/dev/null || true
    rm -rf /var/lib/docker
    echo "[$TIMESTAMP] [INFO] Data wiped."
else
    echo "[$TIMESTAMP] [INFO] Data kept in /var/lib/docker."
fi

echo "----------------------------------------------------"
echo "✅ Docker has been uninstalled."
echo "[NOTE] You may want to manually remove $REAL_USER from the 'docker' group:"
echo "       sudo gpasswd -d $REAL_USER docker"
echo "===================================================="
