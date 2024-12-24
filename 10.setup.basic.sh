#!/bin/bash

# Update and upgrade the system
echo "Updating and upgrading the system..."
apt update && sudo apt upgrade -y
apt install net-tools

echo "Update complete!"

