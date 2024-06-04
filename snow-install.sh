#!/bin/bash

snow_pkg=glide-vancouver-07-06-2023__patch7-02-08-2024_02-19-2024_0243.zip

# Function to check command execution success
check_command() {
    if [ $? -ne 0 ]; then
        echo "Error: Command failed. Exiting."
        exit 1
    fi
}

# Set user and timezone to UTC
sudo useradd servicenow 
sudo timedatectl set-timezone "UTC"
check_command

# Disable SELinux
sudo sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
check_command

# Install required packages
sudo yum install -y glibc glibc.i686 libgcc libgcc.i686 rng-tools vim
systemctl status firewalld
systemctl stop firewalld
systemctl disable firewalld
iptables -L
check_command

# Create and configure LVM
sudo yum install lvm2 -y
sudo pvcreate /dev/sdb
sudo vgcreate volgrp01 /dev/sdb
sudo lvcreate -L 199.99G -n lv01 volgrp01
sudo mkfs -t xfs /dev/volgrp01/lv01
sudo mkdir /glide
sudo mount /dev/volgrp01/lv01 /glide

echo '/dev/volgrp01/lv01 /glide  xfs  defaults,nofail 0 0' | sudo  tee -a /etc/fstab
sudo mount -a
df -Th /glide
check_command

# Set swappiness
echo 1 > /proc/sys/vm/swappiness
echo "vm.swappiness=1" >> /etc/sysctl.conf
sudo sysctl -p
check_command

# Update limits
echo "*          soft    nproc     10240" | sudo tee -a /etc/security/limits.d/90-nproc.conf
echo "*         soft     nofile    16000" | sudo tee -a /etc/security/limits.d/amb-sockets.conf
echo "*         hard     nofile    16000" | sudo tee -a /etc/security/limits.d/amb-sockets.conf
check_command

# Download and extract glide
# sudo wget -q -O /tmp/glide-base.tar.gz https://shot.service-now.com/binaries/glide-base-20220708.tar.gz
# sudo tar zxf /tmp/glide-base.tar.gz -C /glide/
# check_command

# Install Java
sudo yum install -y java-11-openjdk java-11-openjdk-devel
check_command

# Set Java environment variables
ln -s /usr/lib/jvm/java-11-openjdk /glide/java
cat >> ~/.bashrc << EOF 
export JAVA_HOME=/glide/java/
export PATH=\$PATH:/glide/java/bin
EOF
source ~/.bashrc
check_command

# Print completion message
echo "Setup completed successfully."

#

#java -Djava.io.tmpdir=/tmp -jar /glide/${snow_pkg} --dst-dir /glide/nodes/instance0_16000 install -n instance0 -p 16000

cp /glide/scripts/glide_node_dir_name /glide/scripts/glide_instance0_16000
sudo sed -i 's/node_dir_name/instance0_16000/g' /glide/scripts/glide_instance0_16000
mv /glide/scripts/glide_instance0_16000 /etc/init.d/
systemctl daemon-reload
systemctl enable glide_instance0_16000
cd /glide/nodes/instance0_16000/
./shutdown.sh
sleep 30s
systemctl start glide_instance0_16000
systemctl status glide_instance0_16000
