#!/bin/bash
set -e

# Capture system info
REAL_USER=$(whoami)
ARCH=$(uname -m)
KERNEL=$(uname -r)
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

echo "===================================================="
echo "  DOCKER OFFLINE INSTALLER - $TIMESTAMP"
echo "===================================================="
echo "[ENV] User:         $REAL_USER"
echo "[ENV] Architecture: $ARCH"
echo "[ENV] Current Dir:  $(pwd)"
echo "===================================================="

# 1. Pre-flight Checks
echo "[$TIMESTAMP] [INFO] Starting pre-flight checks..."
if ! sudo -v; then
    echo "[$TIMESTAMP] [ERROR] User $REAL_USER does not have sudo privileges!"
    exit 1
fi

DOCKER_TGZ=$(ls docker-*.tgz 2>/dev/null | head -n 1)
if [[ -z "$DOCKER_TGZ" ]]; then
    echo "[$TIMESTAMP] [ERROR] No docker-*.tgz package found in current directory!"
    exit 1
else
    echo "[$TIMESTAMP] [INFO] Found package: $DOCKER_TGZ"
fi

# 2. Extraction
echo "[$TIMESTAMP] [INFO] Extracting binaries..."
# Run extraction with sudo to ensure permissions on /data or other mounts
sudo tar -xzvf "$DOCKER_TGZ" > /dev/null || { echo "[$TIMESTAMP] [ERROR] Extraction failed"; exit 1; }

echo "[$TIMESTAMP] [INFO] Installing binaries to /usr/bin..."
sudo cp docker/* /usr/bin/ || { echo "[$TIMESTAMP] [ERROR] Binary copy failed"; exit 1; }

# Cleanup temporary extraction directory
sudo rm -rf docker/

# 3. User Group Configuration
echo "[$TIMESTAMP] [INFO] Configuring docker user group..."
if ! getent group docker > /dev/null; then
    sudo groupadd docker && echo "[$TIMESTAMP] [INFO] Created new group: docker"
else
    echo "[$TIMESTAMP] [INFO] Group 'docker' already exists."
fi

# gpasswd ensures the group file is updated immediately
sudo gpasswd -a "$REAL_USER" docker || { echo "[$TIMESTAMP] [ERROR] Failed to add $REAL_USER to docker group"; exit 1; }
echo "[$TIMESTAMP] [INFO] $REAL_USER has been added to the docker group."

# 4. Systemd Setup
echo "[$TIMESTAMP] [INFO] Creating systemd service unit..."
sudo tee /etc/systemd/system/docker.service > /dev/null <<EOF
[Unit]
Description=Docker Application Container Engine
After=network.target

[Service]
Type=notify
ExecStart=/usr/bin/dockerd
ExecReload=/bin/kill -s HUP \$MAINPID
LimitNOFILE=infinity
LimitNPROC=infinity
TimeoutStartSec=0
Delegate=yes
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 5. Service Activation
echo "[$TIMESTAMP] [INFO] Reloading systemd and starting Docker..."
sudo systemctl daemon-reload
sudo systemctl enable --now docker || {
    echo "[$TIMESTAMP] [ERROR] Docker failed to start.";
    sudo journalctl -u docker --no-pager | tail -n 20;
    exit 1;
}

echo "===================================================="
echo "✅ INSTALLATION SUCCESSFUL"
echo "===================================================="
echo "[STATUS] Docker version: $(docker --version)"
echo "[STATUS] Group Check:    $(grep "^docker" /etc/group)"
echo ""
echo "[ACTION] To use Docker without sudo, please run:"
echo "         newgrp docker"
echo "===================================================="
