#!/usr/bin/env bash
# Automated NixOS server installation script
# Run this from your local machine after booting the server from the installer USB

set -euo pipefail

# Configuration
NETWORK="192.168.50.0/24"
GITHUB_REPO="https://github.com/frerom/dotfiles.git"
DISK="auto"  # Set to /dev/sda or /dev/nvme0n1 if you want to skip auto-detection
SSH_KEY="$HOME/.ssh/id_ed25519"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${GREEN}ℹ${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

echo_error() {
    echo -e "${RED}✗${NC} $1"
}

echo_success() {
    echo -e "${GREEN}✓${NC} $1"
}

# Check prerequisites
echo
echo "========================================"
echo "NixOS Server Automated Installation"
echo "========================================"
echo

echo_info "Checking prerequisites..."

if [ ! -f "$SSH_KEY" ]; then
    echo_error "SSH key not found at $SSH_KEY"
    exit 1
fi

if ! command -v ssh &> /dev/null; then
    echo_error "ssh command not found"
    exit 1
fi

echo_success "Prerequisites OK"

# Find the installer
echo
echo_info "Searching for NixOS installer on network $NETWORK..."
echo_info "This may take 1-2 minutes..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_IP=$(bash "$SCRIPT_DIR/find-installer.sh" "$NETWORK" | tail -1)

if [ -z "$INSTALLER_IP" ]; then
    echo_error "Failed to find NixOS installer"
    exit 1
fi

echo_success "Found installer at $INSTALLER_IP"

# Confirm installation
echo
echo "Installation will:"
echo "  1. Partition and format the disk on the server"
echo "  2. Clone configuration from: $GITHUB_REPO"
echo "  3. Install NixOS with the 'server' configuration"
echo "  4. Set up SSH, Jellyfin, Samba, NFS, WebDAV"
echo
echo_warn "This will ERASE ALL DATA on the server's primary disk!"
echo

read -p "Continue with installation? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Installation cancelled"
    exit 0
fi

# Upload and run remote installation script
echo
echo_info "Uploading installation script..."

scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$SCRIPT_DIR/remote-install.sh" root@"$INSTALLER_IP":/tmp/

echo_success "Script uploaded"

echo
echo_info "Starting remote installation..."
echo_info "You'll be connected to the installer for the installation process"
echo

# SSH into installer and run the script
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -t root@"$INSTALLER_IP" \
    "bash /tmp/remote-install.sh '$GITHUB_REPO' '$DISK'"

# Wait for reboot
echo
echo_info "Server is rebooting..."
echo_info "Waiting 30 seconds for the server to come back online..."
sleep 30

# Wait for server to be accessible
echo_info "Waiting for server to be accessible at 192.168.50.100..."
MAX_WAIT=120
WAITED=0

while [ $WAITED -lt $MAX_WAIT ]; do
    if timeout 2 bash -c "echo >/dev/tcp/192.168.50.100/22" 2>/dev/null; then
        echo_success "Server is online!"
        break
    fi
    sleep 5
    WAITED=$((WAITED + 5))
    echo -n "."
done

echo

if [ $WAITED -ge $MAX_WAIT ]; then
    echo_warn "Server did not come online within $MAX_WAIT seconds"
    echo_warn "It may still be booting. Try connecting manually:"
    echo "  ssh frerom@192.168.50.100"
    exit 1
fi

# Run post-installation setup
echo
echo_info "Running post-installation setup..."
echo

# Function to run commands on the server
run_remote() {
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        frerom@192.168.50.100 "$@"
}

echo_info "Setting Samba password..."
echo "Please enter the Samba password for user 'frerom':"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -t frerom@192.168.50.100 "sudo smbpasswd -a frerom"

echo
echo_info "Setting WebDAV password..."
echo "Please enter the WebDAV password for user 'frerom':"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -t frerom@192.168.50.100 \
    'echo "frerom:$(openssl passwd -apr1)" | sudo tee /etc/nginx/webdav.passwd && sudo chmod 640 /etc/nginx/webdav.passwd && sudo chown root:nginx /etc/nginx/webdav.passwd'

echo
echo_info "Verifying services..."
SERVICES=("jellyfin" "smbd" "nfs-server" "nginx" "sshd" "avahi-daemon")

for service in "${SERVICES[@]}"; do
    if run_remote "systemctl is-active --quiet $service"; then
        echo_success "$service is running"
    else
        echo_error "$service is NOT running"
    fi
done

echo
echo "========================================"
echo_success "Installation Complete!"
echo "========================================"
echo
echo "Your server is ready and accessible at:"
echo "  • SSH: ssh frerom@192.168.50.100 or ssh frerom@server.local"
echo "  • Jellyfin: http://192.168.50.100:8096 or http://server.local:8096"
echo "  • Samba: \\\\server.local\\media or \\\\192.168.50.100\\media"
echo
echo "Next steps:"
echo "  1. Add media storage drive (see INSTALL.md Part 10)"
echo "  2. Configure Jellyfin at http://server.local:8096"
echo "  3. Copy media files to /mnt/media"
echo
echo "To backup the hardware configuration to git:"
echo "  cd ~/dotfiles"
echo "  scp frerom@server.local:/etc/nixos/hosts/server/hardware-configuration.nix hosts/server/"
echo "  git add hosts/server/hardware-configuration.nix"
echo "  git commit -m 'Add server hardware configuration'"
echo "  git push"
echo
