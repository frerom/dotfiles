#!/usr/bin/env bash
# Find the NixOS installer on the network
# Usage: ./find-installer.sh [network-range]

set -euo pipefail

NETWORK="${1:-192.168.50.0/24}"
TIMEOUT=1

echo "Scanning network $NETWORK for NixOS installer..."
echo "This may take a minute..."
echo

# Try to find hosts that respond to ping and have SSH open
FOUND_HOSTS=()

# Quick ping scan
for i in {1..254}; do
    IP="${NETWORK%.*}.$i"
    if ping -c 1 -W "$TIMEOUT" "$IP" &>/dev/null; then
        # Check if SSH is open (installer has SSH on port 22)
        if timeout 2 bash -c "echo >/dev/tcp/$IP/22" 2>/dev/null; then
            # Try to detect if it's the installer by checking hostname
            HOSTNAME=$(timeout 2 ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                -o ConnectTimeout=2 -o BatchMode=yes \
                root@"$IP" "hostname" 2>/dev/null || echo "")

            if [[ "$HOSTNAME" == "nixos" ]]; then
                FOUND_HOSTS+=("$IP")
                echo "✓ Found NixOS installer at: $IP"
            fi
        fi
    fi
done

echo
if [ ${#FOUND_HOSTS[@]} -eq 0 ]; then
    echo "❌ No NixOS installer found on network $NETWORK"
    echo
    echo "Troubleshooting:"
    echo "  1. Wait 1-2 minutes for the installer to fully boot"
    echo "  2. Check that the server is connected to the network"
    echo "  3. Try scanning a different network range"
    echo "  4. Check your router's DHCP leases page"
    exit 1
elif [ ${#FOUND_HOSTS[@]} -eq 1 ]; then
    echo "Found installer at: ${FOUND_HOSTS[0]}"
    echo "${FOUND_HOSTS[0]}"
else
    echo "⚠ Multiple NixOS installers found:"
    for host in "${FOUND_HOSTS[@]}"; do
        echo "  - $host"
    done
    echo
    echo "Please specify which one to use:"
    select IP in "${FOUND_HOSTS[@]}"; do
        echo "$IP"
        exit 0
    done
fi
