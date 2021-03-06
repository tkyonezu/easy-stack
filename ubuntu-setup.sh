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

if ! grep -q "${PUB_INTERFACE}" /etc/network/interfaces; then
  cat <<EOF >>/etc/network/interfaces

auto ${PUB_INTERFACE}
iface ${PUB_INTERFACE} inet manual
up ip link set dev \$IFACE up
down ip link set dev \$IFACE down
EOF
fi

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

apt install -y chrony

if ! grep -q "ntp.nict.jp" /etc/chrony/chrony.conf; then
  sed -i '/^pool 2.debian.pool.ntp.org offline iburst/iserver ntp.nict.jp iburst \n' /etc/chrony/chrony.conf
fi

if ! grep -q "${PRIV_NETCIDR}" /etc/chrony/chrony.conf; then
  sed -i "/^#allow ::\/0/aallow ${PRIV_NETCIDR}\nallow ${PRIV_NET6CIDR}" /etc/chrony/chrony.conf
fi

service chrony restart

#
# OpenStack Packages
# https://docs.openstack.org/install-guide/environment-packages.html
#
# OpenStack Packages for Ubuntu
# https://docs.openstack.org/install-guide/environment-packages-ubuntu.html
#
logmsg "Setup OpenStack repository"

# Enable the OpenStack repository
apt install -y software-properties-common
add-opt-repository cloud0-archive:queens

# Finalize the installation
logmsg "Update Ubuntu software"

apt update
apt upgrade -y

# Install the OpenStack client
logmsg "Install OpenStack client"

apt install -y python-openstackclient

#
# SQL database
# https://docs.openstack.org/install-guide/environment-sql-database.html
#
# SQL database for Ubuntu
# https://docs.openstack.org/install-guide/environment-sql-database-ubuntu.html
#
logmsg "Install and Setup SQL Database"

# Install and configure components
apt install -y mariadb-server python-pymysql

if [ ! -f /etc/mysql/mariadb.conf.d/99-openstack.cnf ]; then
  cat <<EOF >/etc/mysql/mariadb.conf.d/99-openstack.cnf
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
service mysql restart

mysql_secure_installation

#
# Message queue
# https://docs.openstack.org/install-guide/environment-messaging.html
#
# Message queue for Ubuntu
# https://docs.openstack.org/install-guide/environment-messaging-ubuntu.html
#
logmsg "Install and Setup Message queue"

# Install and configure components
apt install -y rabbitmq-server

rabbitmqctl add_user openstack ${RABBIT_PASS}

rabbitmqctl set_permissions openstack ".*" ".*" ".*"

#
# Memcached
# https://docs.openstack.org/install-guide/environment-memcached.html
#
# Memcached for Ubuntu
# https://docs.openstack.org/install-guide/environment-memcached-ubuntu.html
#
logmsg "Install and Setup Memcached"

# Install and configure components
apt install -y memcached python-memcache

if ! grep -q "${PRIV_IP}" /etc/memcached.conf; then
  sed -i -e 's/^-l 127.0.0.1/#&/' -e "/^#-l 127.0.0.1/a-l ${PRIV_IP}" /etc/memcached.conf
fi

# Finalize installation
service memcached restart

#
# Etcd
# https://docs.openstack.org/install-guide/environment-etcd.html
#
# Etcd for Ubuntu
# https://docs.openstack.org/install-guide/environment-etcd-ubuntu.html
#
logmsg "Install and Setup Etcd"

# Install and configure components
if ! grep -q etcd /etc/group; then
  groupadd --system etcd
fi

if ! id etcd >/dev/null 2>/dev/null; then
  useradd --home-dir "/var/lib/etcd" --system --shell /bin/false -g etcd etcd
fi

if [ ! -d /etc/etcd ]; then
  mkdir -p /etc/etcd
  chown etcd:etcd /etc/etcd
fi

if [ ! -d /var/lib/etcd ]; then
  mkdir -p /var/lib/etcd
  chown etcd:etcd /var/lib/etcd
fi

if [ ! -x /usr/bin/etcd ]; then
  ETCD_VER=v3.2.7
  rm -fr /tmp/etcd && mkdir /tmp/etcd
  curl -L https://github.com/coreos/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz -o /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz
  tar zxvf /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz -C /tmp/etcd --strip-components=1
  cp /tmp/etcd/etcd /usr/bin/etcd
  cp /tmp/etcd/etcdctl /usr/bin/etcdctl
  rm -fr /tmp/etcd
fi

if [ ! -f /etc/etcd/etcd.conf.yml ]; then
  cat <<EOF >/etc/etcd/etcd.conf.yml
name: controller
data-dir: /var/lib/etcd
initial-cluster-state: 'new'
initial-cluster-token: 'etcd-cluster-01'
initial-cluster: controller=http://${CONTROLLER}:2380
initial-advertise-peer-urls: http://${CONTROLLER}:2380
advertise-client-urls: http://${CONTROLLER}:2379
listen-peer-urls: http://0.0.0.0:2380
listen-client-urls: http://${CONTROLLER}:2379
EOF
fi

if [ ! -f /lib/systemd/system/etcd.service ]; then
  cat <<EOF >/lib/systemd/system/etcd.service
[Unit]
After=network.target
Description=etcd - highly-available key value store

[Service]
LimitNOFILE=65536
Restart=on-failure
Type=notify
ExecStart=/usr/bin/etcd --config-file /etc/etcd/etcd.conf.yml
User=etcd

[Install]
WantedBy=multi-user.target
EOF
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
# https://docs.openstack.org/keystone/queens/install/keystone-install-ubuntu.html
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
apt install -y keystone apache2 libapache2-mod-wsgi

ecf --set /etc/keystone/keystone.conf database connection mysql+pymysql://keystone:${KEYSTONE_DBPASS}@${CONTROLLER}/keystone
ecf --add /etc/keystone/keystone.conf token provider fernet

su -s /bin/sh -c "keystone-manage db_sync" keystone

keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
# usage: keystone-manage [bootstrap|db_sync|db_version|domain_config_upload|fernet_rotate|fernet_setup|mapping_populate|mapping_purge|mapping_engine|pki_setup|saml_idp_metadata|ssl_setup|token_flush]
# keystone-manage: error: argument command: invalid choice: 'credential_setup' (choose from 'bootstrap', 'db_sync', 'db_version', 'domain_config_upload', 'fernet_rotate', 'fernet_setup', 'mapping_populate', 'mapping_purge', 'mapping_engine', 'pki_setup', 'saml_idp_metadata', 'ssl_setup', 'token_flush')
#
# keystone-manage credential_setup 
# https://bugs.launchpad.net/openstack-manuals/+bug/1688653
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone

keystone-manage bootstrap --bootstrap-password ${ADMIN_PASS} \
  --bootstrap-admin-url http://${CONTROLLER}:5000/v3/ \
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
