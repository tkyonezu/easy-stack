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

exit 0

#
# Host networking
# https://docs.openstack.org/install-guide/environment-networking.html
#

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

# Enable the OpenStack repository
apt install -y software-properties-common
add-opt-repository cloud0-archive:queens

# Finalize the installation
apt update
apt upgrade -y

# Install the OpenStack client
apt install -y python-openstackclient

#
# SQL database
# https://docs.openstack.org/install-guide/environment-sql-database.html
#
# SQL database for Ubuntu
# https://docs.openstack.org/install-guide/environment-sql-database-ubuntu.html
#

# Install and configure components
apt install -y mariadb-server python-pymysql

if [ ! -f mariadb.conf.d/99-openstack.cnf ]; then
  cat <<EOF >mariadb.conf.d/99-openstack.cnf
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

# Install and configure components
apt install -y memcached python-memcache

if ! grep -q "${PRIV_IP}" memcached.conf; then
  sed -i -e 's/^-l 127.0.0.1/#&/' -e "/^#-l 127.0.0.1/a-l ${PRIV_IP}" memcached.conf
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
initial-cluster: controller=http://${PRIV_IP}:2380
initial-advertise-peer-urls: http://${PRIV_IP}:2380
advertise-client-urls: http://${PRIV_IP}:2379
listen-peer-urls: http://0.0.0.0:2380
listen-client-urls: http://${PRIV_IP}:2379
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
