#!/bin/bash

# Function to check command execution success
check_command() {
    if [ $? -ne 0 ]; then
        echo "Error: Command failed. Exiting."
        exit 1
    fi
}

mariadb_version="mariadb-10.4.33-linux-systemd-x86_64.tar.gz"
mariadb_conf="ServiceNow_mariadb10.4_my.cnf-20220429-512GB"

# Create and configure LVM
systemctl stop firewalld.service
systemctl disable firewalld.service

sudo yum install lvm2 vim -y
sudo pvcreate /dev/sdb
sudo vgcreate volgrp01 /dev/sdb
sudo lvcreate -L 999.99G -n lv01 volgrp01
sudo mkfs -t xfs /dev/volgrp01/lv01
sudo mkdir /glide
sudo mount /dev/volgrp01/lv01 /glide
check_command

# make it persistence
echo '/dev/volgrp01/lv01 /glide  xfs  defaults,nofail 0 0' | sudo  tee -a /etc/fstab
sudo mount -a
df -Th /glide
check_command

#Add a MySQL service account on the database server.
groupadd mysql
useradd mysql -g mysql

# Install the glibc, libaio and perl  RPMs package, if not installed, please install it.

yum install -y glibc libaio perl

# Disable SELinux
sudo sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config

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

# database configuration
cp /tmp/$mariadb_conf /etc/my.cnf
cp /tmp/$mariadb_version /glide

cat /etc/my.cnf

# #
cd /glide/
tar -zxvpf /glide/$mariadb_version
tar -zxvpf /glide/$mariadb_conf
ln -s mariadb-10.4.32-linux-systemd-x86_64 /glide/mysql
mkdir -p /glide/mysql/data
mkdir -p /glide/mysql/temp
chown -HR mysql:mysql /glide/mysql

/glide/mysql/scripts/mariadb-install-db --defaults-file=/etc/my.cnf --datadir=/glide/mysql/data --user=mysql --basedir=/glide/mysql

cp /glide/mysql/support-files/systemd/mariadb.service /usr/lib/systemd/system/mariadb.service

sed -i 's|/usr/local/mysql|/glide/mysql|g' /usr/lib/systemd/system/mariadb.service
cat /usr/lib/systemd/system/mariadb.service

mkdir /etc/systemd/system/mariadb.service.d/
cat > /etc/systemd/system/mariadb.service.d/datadir.conf <<EOF
[Service]
ReadWritePaths=/glide/mysql/data
EOF

export PATH=$PATH:/glide/mysql/bin/

### ERROR
### mysql
### mysql: error while loading shared libraries: libncurses.so.5: cannot open shared object file: No such file or directory

sudo yum install libncurses*
echo 'export PATH=$PATH:/glide/mysql/bin/' >> ~/.bashrc

### system reboot

systemctl daemon-reload
systemctl start mariadb.service
systemctl enable mariadb.service
systemctl status mariadb.service


### please make sure system has been rebooted, otherwise will below issue has occured:
###-- Unit mariadb.service has begun starting up.
### May 27 03:23:17 T057-0069 sh[315609]: /glide/mysql/bin/galera_recovery: line 109: /usr/local/mysql/bin/my_print_defaults: No such >
### May 27 03:23:17 T057-0069 systemd[315613]: mariadb.service: Failed to execute command: Permission denied
### May 27 03:23:17 T057-0069 systemd[315613]: mariadb.service: Failed at step EXEC spawning /glide/mysql/bin/mysqld: Permission denied
### -- Subject: Process /glide/mysql/bin/mysqld could not be executed

### USer create
### MariaDB [(none)]> create database db-name;
### MariaDB [(none)]> CREATE USER 'snow'@'%' IDENTIFIED BY 'Snow@db-name';
### MariaDB [(none)]> GRANT ALL PRIVILEGES ON *.* TO 'snow'@'%';
### CREATE USER 'repl_user'@'%' IDENTIFIED BY 'repl@db-name#';
### GRANT REPLICATION SLAVE ON *.* TO 'repl_user'@'%';
### FLUSH PRIVILEGES;

CHANGE MASTER TO
  MASTER_HOST='ip-addr',
  MASTER_USER='repl_user',
  MASTER_PASSWORD='repl@db-name#',
  MASTER_LOG_FILE='mysql-binlog.000001',
  MASTER_LOG_POS=331;

## 
## # mkdir -p /glide/mysql/binlog
## # chown -HR mysql:mysql /glide/mysql
## # systemctl restart mariadb.service
