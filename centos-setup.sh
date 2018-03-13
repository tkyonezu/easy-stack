#!/bin/bash

# Copyright 2018 Takeshi Yonezu, All Rights Reserved.

msgno=0

function logmsg {
  ((msgno+=1))

  echo ">> ${msgno} $*"
}

function error {
  echo ">> ERROR: $*"
  exit 1
}

if [ ! -x /usr/local/bin/ecf ]; then
  logmsg "Install ecf (Edit Configuration File) script"
  cp ecf /usr/local/bin
  chmod +x /usr/local/bin/ecf
fi

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
PRIV_HOST=openstack1
PRIV_INTERFACE=enp0s8
PRIV_IP=192.168.56.101
PRIV_NETWORK=192.168.56.0
PRIV_NETMASK=255.255.255.0
PRIV_NETCIDR=192.168.56/24
PRIV_NET6CIDR=fe80::7f2e:c41a/64
PRIV_GATEWAY=192.168.56.1

# Provider Network
PUB_INTERFACE=enp0s3
PUB_IP=10.0.2.15
PUB_NETWORK=10.0.2.0
PUB_NETMASK=255.255.255.0
PUB_GATEWAY=10.0.2.1

# Controller Node
CONTROLLER=${PRIV_HOST}

#
# OpenStack Queens Administrator Guide
# https://docs.openstack.org/queens/admin/
#

#
# Security
# https://docs.openstack.org/install-guide/environment-security.html
#
logmsg "Make Passwords for OpenStack"

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

if [ -f openstack.key ]; then
  echo -n ">>> openstack.key exists. Do you want recreate it? (y/n) "
  read ans
  if [ "${ans}" = "y" ]; then
    makekeys | tee -a openstack.key
  fi
else
  makekeys | tee -a openstack.key
fi

. ./openstack.key

#
# Host networking
# https://docs.openstack.org/install-guide/environment-networking.html
#
logmsg "Setup Network"

sed -i '/^BOOTPROTO=/s/dhcp/none/' \
  /etc/sysconfig/network-scripts/ifcfg-${PUB_INTERFACE}

sed -i 's/^127.0.1.1/#&/' /etc/hosts

if ! grep -q "^${PRIV_IP}" hosts; then
  cat <<EOF >>/etc/hosts

${PRIV_IP} ${PRIV_HOST}
EOF
fi

#
# Network Time Protocol (NTP)
# https://docs.openstack.org/install-guide/environment-ntp.html
#
logmsg "Insall and Setup NTP"

yum install -y chrony

if ! grep -q "ntp.nict.jp" /etc/chrony/chrony.conf; then
  sed -i '/^pool 2.debian.pool.ntp.org offline iburst/iserver ntp.nict.jp iburst \n' /etc/chrony/chrony.conf
fi

if ! grep -q "${PRIV_NETCIDR}" /etc/chrony/chrony.conf; then
  sed -i "/^#allow ::\/0/aallow ${PRIV_NETCIDR}\nallow ${PRIV_NET6CIDR}" /etc/chrony/chrony.conf
fi

systemctl enable chronyd.service
systemctl start chronyd.service

#
# OpenStack Packages
# https://docs.openstack.org/install-guide/environment-packages.html
#
# OpenStack Packages for RHEL and CentOS
# https://docs.openstack.org/install-guide/environment-packages-rdo.html
#
logmsg "Enable the OpenStack repository (Queens)"

# Enable the OpenStack repository
yum install -y centos-release-openstack-queens

# Finalize the installation
logmsg "Update CentOS software"

yum upgrade -y

# Install the OpenStack client
logmsg "Install OpenStack client"

yum install -y python-openstackclient
yum install -y openstack-selinux

#
# SQL database
# https://docs.openstack.org/install-guide/environment-sql-database.html
#
# SQL database for RHEL and CentOS
# https://docs.openstack.org/install-guide/environment-sql-database-rdo.html
#
logmsg "Install and Setup SQL Database"

# Install and configure components
yum install mariadb mariadb-server python2-PyMySQL

if ! grep -q ${PRIV_IP} /etc/my.cnf.d/mysql-clients.cnf; then
  cat <<EOF >>/etc/my.cnf.d/mysql-clients.cnf

[mysqld]
bind-address = ${PRIV_IP}

default-storage-engine = innodb
innodb_file_per_table = on
max_connections = 4096
collation-server = utf8_general_ci
character-set-server = utf8
EOF
fi

# Finalize installation
systemctl enable mariadb.service
systemctl start mariadb.service

mysql_secure_installation

#
# Message queue
# https://docs.openstack.org/install-guide/environment-messaging.html
#
# Message queue for RHEL and CetnOS
# https://docs.openstack.org/install-guide/environment-messaging-rdo.html
#
logmsg "Install and Setup Message queue"

# Install and configure components
yum install -y rabbitmq-server

systemctl enable rabbitmq-server.service
systemctl start rabbitmq-server.service

rabbitmqctl add_user openstack ${RABBIT_PASS}

rabbitmqctl set_permissions openstack ".*" ".*" ".*"

#
# Memcached
# https://docs.openstack.org/install-guide/environment-memcached.html
#
# Memcached for RHEL and CentOS
# https://docs.openstack.org/install-guide/environment-memcached-rdo.html
#
logmsg "Install and Setup Memcached"

# Install and configure components
yum install -y memcached python-memcached

if ! grep -q "${PRIV_IP}" /etc/sysconfig/memcached; then
  sed -i "s/^OPTIONS=.*/OPTIONS=\"-l 127.0.0.1,::1,${PRIV_IP}\"/" /etc/sysconfig/memcached
fi

# Finalize installation
systemctl enable memcached.service
systemctl start memcached.service

#
# Etcd
# https://docs.openstack.org/install-guide/environment-etcd.html
#
# Etcd for RHEL and CentOS
# https://docs.openstack.org/install-guide/environment-etcd-rdo.html
#
logmsg "Install and Setup Etcd"

yum install -y etcd

# Edit /etc/etcd/etcd.conf
if ! grep -q ${CONTROLLER} /etc/etcd/etcd.conf; then
  sed -i 's/ETCD_DATA_DIR=.*/ETCD_DATA_DIR="\/var\/lib\/etcd\/default.etcd"/' /etc/etcd/etcd.conf
  sed -i "s/#ETCD_LISTEN_PEER_URLS=.*/ETCD_LISTEN_PEER_URLS=\"http:\/\/${CONTROLLER}:2380\"/" /etc/etcd/etcd.conf
  sed -i "s/ETCD_LISTEN_CLIENT_URLS=.*/ETCD_LISTEN_CLIENT_URLS=\"http:\/\/${CONTROLLER}:2379\"/" /etc/etcd/etcd.conf
  sed -i 's/ETCD_NAME=.*/ETCD_NAME="controller"/' /etc/etcd/etcd.conf
  sed -i "s/#ETCD_INITIAL_ADVERTISE_PEER_URLS=.*/ETCD_INITIAL_ADVERTISE_PEER_URLS=\"http:\/\/${CONTROLLER}:2380\"/" /etc/etcd/etcd.conf
  sed -i "s/ETCD_ADVERTISE_CLIENT_URLS=.*/ETCD_ADVERTISE_CLIENT_URLS=\"http:\/\/${CONTROLLER}:2379\"/" /etc/etcd/etcd.conf
  sed -i "s/#ETCD_INITIAL_CLUSTER=.*/ETCD_INITIAL_CLUSTER=\"controller=http:\/\/${CONTROLLER}:2380\"/" /etc/etcd/etcd.conf
  sed -i 's/#ETCD_INITIAL_CLUSTER_TOKEN=.*/ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster-01"/' /etc/etcd/etcd.conf
  sed -i 's/#ETCD_INITIAL_CLUSTER_STATE=.*/ETCD_INITIAL_CLUSTER_STATE="new"/' /etc/etcd/etcd.conf
fi

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
# Install and Configure
# https://docs.openstack.org/keystone/queens/install/keystone-install-rdo.html
#
logmsg "Install and Configure KEYSTONE"

#
# Prerequisites
#
cat <<EOF >/var/tmp/keystone.sql
CREATE DATABASE keystone;
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '${KEYSTONE_DBPASS}';
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '${KEYSTONE_DBPASS}';
FLUSH PRIVILEGES;
EXIT
EOF

mysql </var/tmp/keystone.sql

rm /var/tmp/keystone.sql

#
# Install and configure components
#
yum install -y openstack-keystone httpd mod-wsgi

if ! grep -q ${CONTROLLER} /etc/keystone/keystone.conf; then
  ecf --set /etc/keystone/keystone.conf database connection mysql+pymysql://keystone:${KEYSTONE_DBPASS}@${CONTROLLER}/keystone
  ecf --add /etc/keystone/keystone.conf token provider fernet
fi

su -s /bin/sh -c "keystone-manage db_sync" keystone

keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone

keystone-manage bootstrap --bootstrap-password ${ADMIN_PASS} \
  --bootstrap-admin-url http://${CONTROLLER}:35357/v3/ \
  --bootstrap-internal-url http://${CONTROLLER}:5000/v3/ \
  --bootstrap-public-url http://${CONTROLLER}:5000/v3/ \
  --bootstrap-region-id RegionOne

#
# Configure the Apache HTTP Server
#
logmsg "Configure the Apache HTTP Server"

if ! grep -q ${CONTROLLER} /etc/apache2/sites-available/000-default.conf; then
  sed -i "/#ServerName/aServerName ${CONTROLLER}" /etc/apache2/sites-available/000-default.conf
  sed -i "/${CONTROLLER}/s/^/\t/" /etc/apache2/sites-available/000-default.conf
fi

service apache2 restart

#
# Configure the administrative account
#
logmsg "Configure the administrative account"

cat <<EOF >~/admin-openrc
export OS_USERNAME=admin
export OS_PASSWORD=${ADMIN_PASS}
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://${CONTROLLER}:5000/v3
export OS_IDENTITY_API_VERSION=3
EOF

#
# Image service
# https://docs.openstack.org/glance/queens/install/
#
logmsg "Install and Configure GLANCE"

#
# Prerequisites
#
cat <<EOF >/var/tmp/glance.sql
CREATE DATABASE glance;
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '${GLANCE_DBPASS}';
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '${GLANCE_DBPASS}';
FLUSH PRIVILEGES;
EXIT
EOF

mysql </var/tmp/glance.sql

rm /var/tmp/glance.sql

. ~/admin-openrc

openstack user create --domain default --password-prompt glance
openstack role add --project service --user glance admin
openstack service create --name glance --description "OpenStack Image" image
openstack endpoint create --region RegionOne image public http://${CONTROLLER}:9292
openstack endpoint create --region RegionOne image internal http://${CONTROLLER}:9292
openstack endpoint create --region RegionOne image admin http://${CONTROLLER}:9292

#
# Install and configure components
#
apt install -y glance

## ecf --set /etc/glance/glance-api.conf database connection mysql+pymysql://glance:${GLANCE_DBPASS}@${CONTROLLER}/glance
## ecf --add /etc/keystone/keystone.conf token provider fernet

## su -s /bin/sh -c "keystone-manage db_sync" keystone

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
