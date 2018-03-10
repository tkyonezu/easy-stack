#!/bin/bash

# Copyright 2018 Takeshi Yonezu, All Rights Reserved.

#
# OpenStack Installations Guide for Queens
# https://docs.openstack.org/queens/install/
#
# OpenStack Installation Guide
# https://docs.openstack.org/install-guide/index.html
#

#
# Environment
# https://docs.openstack.org/install-guide/environment.html
#

# Management Network
PRIV_IP=192.168.56.101
PRIV_NETWORK=192.168.56.0
PRIV_NETMASK=255.255.255.0
PRIV_GATEWAY=192.168.56.1

# Privider Network
PUB_IP=10.0.2.15
PUB_NETWORK=10.0.2.0
PUB_NETMASK=255.255.255.0
PUB_GATEWAY=10.0.2.1

#
# OpenStack Queens Administrator Guide
# https://docs.openstack.org/queens/admin/
#

#
# Security
# https://docs.openstack.org/install-guide/environment-security.html
#
function makekeys {
  echo "# Generate OpenStack passwords on $(env LC_ALL=C date)"
  echo
  echo "ADMIN_PASS=$(openssl rand -hex 10)"
  echo "CINDER_DBPASS=$(openssl rand -hex 10)"
  echo "CINDER_PASS=$(openssl rand -hex 10)"
  echo "DASH_PASS=$(openssl rand -hex 10)"
  echo "DEMO_PASS=$(openssl rand -hex 10)"	# Password of user demo
  echo "GLANCE_DBPASS=$(openssl rand -hex 10)"
  echo "GLANCE_PASS=$(openssl rand -hex 10)"
  echo "KEYSTONE_DBPASS=$(openssl rand -hex 10)"
  echo "METADATA_SECRET=$(openssl rand -hex 10)"
  echo "NEUTRON_DBPASS=$(openssl rand -hex 10)"
  echo "NEUTRON_PASS=$(openssl rand -hex 10)"
  echo "NOVA_DBPASS=$(openssl rand -hex 10)"
  echo "NOVA_PASS=$(openssl rand -hex 10)"
  echo "PLACEMENT_PASS=$(openssl rand -hex 10)"
  echo "RABBIT_PASS=$(openssl rand -hex 10)"
}

makekeys | tee -a openstack.key

. ./openstack.key

exit 0

#
# Host networking
# https://docs.openstack.org/install-guide/environment-networking.html
#

#
# Network Time Protocol (NTP)
# https://docs.openstack.org/install-guide/environment-ntp.html
#
apt install -y chrony

# sed -i " " /etc/chrony.d/chrony.conf
# server NTP_SERVER iburst
# allow 10.0.0.0/24

service chrony restart

#
# OpenStack Packages
# https://docs.openstack.org/install-guide/environment-packages.html
#
# OpenStack Packages for Ubuntu
# https://docs.openstack.org/install-guide/environment-packages-ubuntu.html
#

# Enable the OpenStack repository
apt install software-properties-common
add-opt-repository cloud0-archive:queens

# Finalize the installation
apt update
apt upgrade -y

# Install the OpenStack client
apt install python-openstackclient

#
# SQL database
# https://docs.openstack.org/install-guide/environment-sql-database.html
#
# SQL database for Ubuntu
# https://docs.openstack.org/install-guide/environment-sql-database-ubuntu.html
#

# Install and configure components
apt install mariadb-server python-pymysql

cat <<EOF >>/etc/mysql/mariadb.conf.d/99-openstack.cnf
[mysqld]
bind-address = 10.0.0.11

default-storage-engine = innodb
innodb_file_per_table = on
max_connections = 4096
collation-server = utf8_general_ci
character-set-server = utf8
EOF


# Finalize installation
service mysql restart

mysql_secure_installation

#
# Message queue
# https://docs.openstack.org/install-guide/environment-messaging.html
#
# Message queue for Ubuntu
# https://docs.openstack.org/install-guide/environment-messaging-ubuntu.html
#

# Install and configure components
apt install rabbitmq-server

rabbitmqctl add_user openstack ${RABBIT_PASS}

rabbitmqctl set_permissions openstack ".*" ".*" ".*"

#
# Memcached
# https://docs.openstack.org/install-guide/environment-memcached.html
#
# Memcached for Ubuntu
# https://docs.openstack.org/install-guide/environment-memcached-ubuntu.html
#

# Install and configure components
apt install memcached python-memcache

sed -i "s/^-l 127.0.0.1/10.0.0.11/" /etc/memcached.conf

# Finalize installation
service memcached restart

#
# Etcd
# https://docs.openstack.org/install-guide/environment-etcd.html
#
# Etcd for Ubuntu
# https://docs.openstack.org/install-guide/environment-etcd-ubuntu.html
#

# Install and configure components
groupadd --system etcd
useradd --home-dir "/var/lib/etcd" --system --shell /bin/false -g etcd etcd

mkdir -p /etc/etcd
chown etcd:etcd /etc/etcd
mkdir -p /var/lib/etcd
chown etcd:etcd /var/lib/etcd

# Finalize installation
systemctl enable etcd
systemctl start etcd

#
# Install OpenStack Services
# https://docs.openstack.org/install-guide/openstack-services.html
#
# Minimal Deployment for Queens
#

#
# Identity service
# https://docs.openstack.org/keystone/queens/install/
#

#
# Image service
# https://docs.openstack.org/glance/queens/install/
#

#
# Compute service
# https://docs.openstack.org/nova/queens/install/
#

#
# Networking service
# https://docs.openstack.org/neutron/queens/install/
#

#
# Dashboard
# https://docs.openstack.org/horizon/queens/install/
#

#
# Block Storage service
# https://docs.openstack.org/cinder/queens/install/
#

#
# Launch an Instance
# https://docs.openstack.org/install-guide/launch-instance.html
#

#
# Firewall and default ports
# https://docs.openstack.org/install-guide/firewalls-default-ports.html
#

exit 0
