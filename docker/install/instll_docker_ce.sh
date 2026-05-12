#!/bin/bash
set -euo pipefail

# Capture system info
REAL_USER="${SUDO_USER:-$(whoami)}"
ARCH=$(uname -m)
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

# Configurable ISO path (override via environment)
ISO_PATH="${DOCKER_ISO_PATH:-/home/jianzhnie/llmtuner/software/archived/HCE-2.0-aarch64-dvd.iso}"
MOUNT_POINT="/mnt"

echo "===================================================="
echo "  DOCKER CE INSTALLER (HCE Local Repo) - $TIMESTAMP"
echo "===================================================="
echo "[ENV] User:         $REAL_USER"
echo "[ENV] Architecture: $ARCH"
echo "[ENV] ISO Path:     $ISO_PATH"
echo "[ENV] Mount Point:  $MOUNT_POINT"
echo "===================================================="

# 1. Pre-flight Checks
echo "[$TIMESTAMP] [INFO] Running pre-flight checks..."

if ! sudo -v; then
    echo "[$TIMESTAMP] [ERROR] User $REAL_USER does not have sudo privileges!"
    exit 1
fi

if [[ ! -f "$ISO_PATH" ]]; then
    echo "[$TIMESTAMP] [ERROR] ISO file not found: $ISO_PATH"
    exit 1
fi

if mountpoint -q "$MOUNT_POINT"; then
    echo "[$TIMESTAMP] [INFO] $MOUNT_POINT is already mounted, skipping mount."
else
    echo "[$TIMESTAMP] [INFO] Mounting ISO to $MOUNT_POINT..."
    sudo mount -o loop "$ISO_PATH" "$MOUNT_POINT" || {
        echo "[$TIMESTAMP] [ERROR] Failed to mount ISO."
        exit 1
    }
fi

# 2. Backup existing repo files
echo "[$TIMESTAMP] [INFO] Backing up existing repo configuration..."
sudo mkdir -p /etc/yum.repos.d/backup
if compgen -G "/etc/yum.repos.d/*.repo" > /dev/null; then
    sudo mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/backup/
    echo "[$TIMESTAMP] [INFO] Moved existing .repo files to backup/."
else
    echo "[$TIMESTAMP] [INFO] No existing .repo files to back up."
fi

# 3. Create local repo configuration
echo "[$TIMESTAMP] [INFO] Creating local repo configuration..."
sudo tee /etc/yum.repos.d/local.repo > /dev/null <<EOF
[local]
name=Local HCE 2.0 Repo
baseurl=file://$MOUNT_POINT
enabled=1
gpgcheck=1
gpgkey=file://$MOUNT_POINT/RPM-GPG-KEY-HCE-2
EOF

# 4. Rebuild DNF cache
echo "[$TIMESTAMP] [INFO] Rebuilding DNF cache..."
sudo dnf clean all
sudo dnf makecache

# 5. Determine the correct Docker package name
echo "[$TIMESTAMP] [INFO] Searching for available Docker packages..."
DOCKER_PKG=$(sudo dnf search docker 2>/dev/null | grep -oP '^(docker(-ce|-engine)?|podman)\b' | head -n 1)
if [[ -z "$DOCKER_PKG" ]]; then
    echo "[$TIMESTAMP] [ERROR] No Docker package found in the local repo."
    exit 1
fi
echo "[$TIMESTAMP] [INFO] Found Docker package: $DOCKER_PKG"

# 6. Install Docker
echo "[$TIMESTAMP] [INFO] Installing $DOCKER_PKG..."
sudo dnf install -y "$DOCKER_PKG" || {
    echo "[$TIMESTAMP] [ERROR] Docker installation failed."
    exit 1
}

# 7. Configure user group
echo "[$TIMESTAMP] [INFO] Configuring docker user group..."
if ! getent group docker > /dev/null; then
    sudo groupadd docker && echo "[$TIMESTAMP] [INFO] Created group: docker"
else
    echo "[$TIMESTAMP] [INFO] Group 'docker' already exists."
fi
sudo gpasswd -a "$REAL_USER" docker || echo "[$TIMESTAMP] [WARN] Could not add $REAL_USER to docker group."

# 8. Start and enable Docker service
echo "[$TIMESTAMP] [INFO] Starting and enabling Docker service..."
sudo systemctl enable --now docker || {
    echo "[$TIMESTAMP] [ERROR] Docker failed to start."
    sudo journalctl -u docker --no-pager | tail -n 20
    exit 1
}

# 9. Verify installation
echo "===================================================="
echo "  INSTALLATION RESULT"
echo "===================================================="
echo "[STATUS] Docker version: $(sudo docker --version 2>/dev/null || echo 'N/A')"
echo "[STATUS] Service status: $(systemctl is-active docker 2>/dev/null || echo 'N/A')"
echo ""

# 10. Unmount ISO
echo "[$TIMESTAMP] [INFO] Unmounting ISO from $MOUNT_POINT..."
if mountpoint -q "$MOUNT_POINT"; then
    sudo umount "$MOUNT_POINT" && echo "[$TIMESTAMP] [INFO] ISO unmounted."
fi

echo ""
echo "[ACTION] To use Docker without sudo, please run:"
echo "         newgrp docker"
echo "===================================================="
