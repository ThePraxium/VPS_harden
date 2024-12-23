#move ssh certs out of root

#modify certs permissions so they can be scp'd
sudo chmod 644 ~/id_rsa_user1

#disable port 22


# remove default user
echo "removing default user"
sudo userdel -r $DEFAULT_USER

# disable default root user
echo "disable default root user"
sudo passwd -l root
sudo sed -i 's/^root:.*:/root:!:/g' /etc/passwd