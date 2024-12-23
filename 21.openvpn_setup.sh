#!/bin/bash

# Exit on any error
echo "1. Exit on any error"
set -e

# Update and install OpenVPN and Easy-RSA
echo "2. Update and install OpenVPN and Easy-RSA"
sudo apt update && sudo apt upgrade -y  # Ensure system is up-to-date
echo "System updated successfully."
sudo apt install openvpn easy-rsa -y   # Install required packages
echo "OpenVPN and Easy-RSA installed."

# Set up Easy-RSA
echo "3. Set up Easy-RSA"
if [ -d "~/openvpn-ca" ]; then
  echo "Directory ~/openvpn-ca already exists. Removing it to reinitialize."
  sudo rm -rf ~/openvpn-ca
fi

make-cadir ~/openvpn-ca  # Create the Easy-RSA directory
echo "Easy-RSA directory created."
cd ~/openvpn-ca          # Navigate to the Easy-RSA directory

# Initialize PKI and build the CA
echo "4. Initialize PKI and build the CA"
./easyrsa init-pki       # Initialize Public Key Infrastructure (PKI)
echo "PKI initialized."

# Create vars file with required defaults
echo "5. Create vars file with required defaults"
cat > ~/openvpn-ca/vars <<EOF
set_var EASYRSA_REQ_COUNTRY    "US"
set_var EASYRSA_REQ_PROVINCE   "California"
set_var EASYRSA_REQ_CITY       "San Francisco"
set_var EASYRSA_REQ_ORG        "MyOrg"
set_var EASYRSA_REQ_EMAIL      "admin@example.com"
set_var EASYRSA_REQ_OU         "MyOrgUnit"
EOF
echo "Vars file created and configured."

# Build the CA
echo "6. Build the CA"
./easyrsa build-ca nopass
echo "Certificate Authority created."

# Generate the server certificate and key
echo "7. Generate the server certificate and key"
./easyrsa gen-req server nopass  # Generate server request with defaults
echo "Server request generated."
echo yes | ./easyrsa sign-req server server  # Sign the server certificate
echo "Server certificate signed."

# Generate Diffie-Hellman parameters
echo "8. Generate Diffie-Hellman parameters"
./easyrsa gen-dh
echo "Diffie-Hellman parameters generated."

# Generate a CRL
echo "9. Generate a CRL"
./easyrsa gen-crl
echo "Certificate Revocation List created."

# Copy certificates and keys to OpenVPN directory
echo "10. Copy certificates and keys to OpenVPN directory"
sudo cp pki/ca.crt pki/issued/server.crt pki/private/server.key pki/dh.pem /etc/openvpn/
sudo cp pki/crl.pem /etc/openvpn/
echo "Server certificates and CRL copied to /etc/openvpn."

# Configure OpenVPN server
echo "11. Configure OpenVPN server"
sudo bash -c 'cat > /etc/openvpn/server.conf' <<EOF
port 1194
proto udp
dev tap
ca ca.crt
cert server.crt
key server.key
dh dh.pem
crl-verify crl.pem
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
push "route 192.168.1.0 255.255.255.0"
keepalive 10 120
cipher AES-256-CBC
user nobody
group nogroup
persist-key
persist-tun
status openvpn-status.log
log-append openvpn.log
verb 3
explicit-exit-notify 1
client-to-client
EOF
echo "OpenVPN server configuration file created."

# Enable IP forwarding
echo "12. Enable IP forwarding"
sudo sed -i '/net.ipv4.ip_forward/c\net.ipv4.ip_forward=1' /etc/sysctl.conf
sudo sysctl -p
echo "IP forwarding enabled."

# Set up firewall rules
echo "13. Set up firewall rules"
sudo ufw allow 1194/udp
sudo ufw allow OpenSSH
sudo ufw disable
sudo ufw enable
sudo iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
sudo iptables-save | sudo tee /etc/iptables/rules.v4
echo "Firewall and NAT configured."

# Start and enable OpenVPN
echo "14. Start and enable OpenVPN"
sudo systemctl start openvpn@server
sudo systemctl enable openvpn@server
echo "OpenVPN service started and enabled on boot."

# Generate client certificates and configurations
echo "15. Generate client certificates and configurations"
output_dir=/etc/openvpn/client-configs
sudo mkdir -p $output_dir
echo "Client configs directory created."

for i in {1..4}; do
  echo "Generating certificate and key for client$i..."
  ./easyrsa gen-req client$i nopass
  echo yes | ./easyrsa sign-req client client$i
  echo "Client$i certificate signed."
  
  client_dir=$output_dir/client$i
  sudo mkdir -p $client_dir
  sudo cp pki/issued/client$i.crt pki/private/client$i.key /etc/openvpn/ca.crt $client_dir/

  sudo bash -c "cat > $client_dir/client$i.ovpn" <<EOF
client
dev tap
proto udp
remote $(curl -s ipinfo.io/ip) 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-CBC
verb 3
route 192.168.1.0 255.255.255.0
<ca>
$(cat /etc/openvpn/ca.crt)
</ca>
<cert>
$(cat ~/openvpn-ca/pki/issued/client$i.crt)
</cert>
<key>
$(cat ~/openvpn-ca/pki/private/client$i.key)
</key>
EOF
  echo "Client$i configuration file created."
done

systemctl restart openvpn@server

echo "OpenVPN server setup is complete. Client configuration files are available in /etc/openvpn/client-configs/."
