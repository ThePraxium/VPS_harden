#!/bin/bash

# Exit script on any error
set -e

# Update and upgrade the system
echo "Updating and upgrading the system..."
sudo apt update && sudo apt upgrade -y

echo "Update complete!"

INSTANCE_IP=$(curl -s ipinfo.io | grep -oP '"ip":\s*"\K[^"]+')

# find public IP
curl ipinfo.io


# Function to identify the default user
function get_default_user() {
  DEFAULT_USER=$(awk -F: '/\/home\// {print $1}' /etc/passwd | head -n 1)
  echo "Default user identified: $DEFAULT_USER"
  echo $DEFAULT_USER
}

# Function to create two new users and assign them to groups
function create_new_users() {
  # Create two new users with random usernames and passwords
  NEW_USER1=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 30)
  NEW_PASS1=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 30)
  NEW_USER2=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 30)
  NEW_PASS2=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 30)

  # Create 'wheel' group if it doesn't exist
  if ! grep -q '^wheel:' /etc/group; then
    echo "Creating group 'wheel' for admin privileges..."
    sudo groupadd wheel
  fi

  # Create 'wheeless' group if it doesn't exist
  if ! grep -q '^wheeless:' /etc/group; then
    echo "Creating group 'wheeless' for default users..."
    sudo groupadd wheeless
  fi

  # Create users and assign groups
  echo "Creating new admin user: $NEW_USER1..."
  sudo useradd -m -s /bin/bash -G wheel $NEW_USER1
  echo "$NEW_USER1:$NEW_PASS1" | sudo chpasswd

  echo "Creating new default user: $NEW_USER2..."
  sudo useradd -m -s /bin/bash -G wheeless $NEW_USER2
  echo "$NEW_USER2:$NEW_PASS2" | sudo chpasswd

  echo "Granting sudo privileges to 'wheel' group..."
  if ! grep -q '^%wheel' /etc/sudoers; then
    echo "%wheel ALL=(ALL) ALL" | sudo tee -a /etc/sudoers
  fi

  # Display user credentials
  echo "New admin user: $NEW_USER1"
  echo "Credentials for $NEW_USER1: Username=$NEW_USER1, Password=$NEW_PASS1"
  echo "New default user: $NEW_USER2"
  echo "Credentials for $NEW_USER2: Username=$NEW_USER2, Password=$NEW_PASS2"
}

create_new_users

## Function to generate two SSH keys and configure SSH access for users
function generate_ssh_keys() {
  mkdir -p ~/.ssh
  for i in 1 2; do
    KEY_NAME="$HOME/.ssh/id_rsa_user$i"
    USER_VAR="NEW_USER$i"
    USER=${!USER_VAR}

    echo "Generating SSH key pair for $USER..."
    ssh-keygen -t rsa -b 4096 -C "$USER@example.com" -f "$KEY_NAME" -N ""
    echo "Setting up SSH access for $USER..."
    sudo mkdir -p /home/$USER/.ssh
    sudo cp "$KEY_NAME.pub" /home/$USER/.ssh/authorized_keys
    if [ $i -eq 1 ]; then
      sudo chown -R $USER:wheel /home/$USER/.ssh
    else
      sudo chown -R $USER:wheeless /home/$USER/.ssh
    fi
    sudo chmod 700 /home/$USER/.ssh
    sudo chmod 600 /home/$USER/.ssh/authorized_keys
  done
  echo "SSH key setup complete for $NEW_USER1 and $NEW_USER2."
}

generate_ssh_keys

# Harden SSH configuration
echo "Hardening SSH configuration..."
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
echo "PasswordAuthentication no"
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
echo "PermitRootLogin no"
sudo sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
echo "PubkeyAuthentication yes"

# Enable UFW and allow SSH from a specific IP address
RANDOM_PORT=$((1025 + RANDOM % 64511))
read -p "Enter your public IP address: " PUBLIC_IP
echo "Configuring UFW to allow SSH only from $PUBLIC_IP via $RANDOM_PORT..."
sudo ufw allow from $PUBLIC_IP to any port $RANDOM_PORT
sudo ufw enable
echo "Your public IP is: $PUBLIC_IP"

# Change default SSH port to a random high port
echo "Changing SSH port to $RANDOM_PORT..."
sudo sed -i "s/^#\?Port.*/Port $RANDOM_PORT/" /etc/ssh/sshd_config
sudo ufw allow from $PUBLIC_IP to any port $RANDOM_PORT
sudo ufw delete allow 22/tcp
sudo ufw deny 22

echo "New SSH port is $RANDOM_PORT"



# Restart SSH service to apply changes
echo "Restarting SSH service..."
sudo systemctl restart sshd

# Install Fail2Ban for added security
echo "Installing Fail2Ban..."
sudo apt install fail2ban -y


#making keys accessible tos cp because i disabled root ssh
cp ~/.ssh/id_rsa_user1 /home/ubuntu/
cp ~/.ssh/id_rsa_user2 /home/ubuntu/
chmod 644 /home/ubuntu/id_rsa_user*

# printing stuff
echo "System hardening complete. Ensure you test your SSH connection before closing this session."

echo "Your public IP is: $PUBLIC_IP"

echo "keys generated in ~/.ssh/id_rsa_user*"

echo "New admin user: $NEW_USER1"
echo "Credentials for $NEW_USER1: Username=$NEW_USER1, Password=$NEW_PASS1"
echo "New default user: $NEW_USER2"
echo "Credentials for $NEW_USER2: Username=$NEW_USER2, Password=$NEW_PASS2"

echo "New SSH port is $RANDOM_PORT"

echo "public IP is $INSTANCE_IP"

echo "ssh command for this would be"
echo "scp -P $RANDOM_PORT -i ~/.ssh/AWS_KEY.pem ubuntu@$INSTANCE_IP:~/id_rsa_user1 ~/.ssh/"
echo "ssh -i ~.ssh/id_rsa_user1 -p $RANDOM_PORT $NEW_USER1@$INSTANCE_IP"
