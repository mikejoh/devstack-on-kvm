#!/usr/bin/env bash
# shellcheck disable=SC2154  # openstack_rev is injected by Terraform templatefile()

set -e

export NEEDRESTART_MODE=a

systemctl enable --now qemu-guest-agent

git config --global http.postBuffer 157286400
git clone https://github.com/openstack/devstack.git -b "${openstack_rev}" "$HOME/devstack"

cat <<'EOF' > "$HOME/devstack/local.conf"
[[local|localrc]]
ADMIN_PASSWORD=secret
DATABASE_PASSWORD=root
RABBIT_PASSWORD=secret
SERVICE_PASSWORD=secret
SWIFT_HASH=1234123412341234
USE_PYTHON3=True
INSTALL_TEMPEST=False
GIT_BASE=https://github.com

# Logging
LOGFILE=/opt/stack/logs/stack.sh.log
LOGDAYS=2
VERBOSE=True
LOG_COLOR=True

# Glance
GLANCE_LIMIT_IMAGE_SIZE_TOTAL=10000

# Enable OVN
Q_AGENT=ovn
Q_ML2_PLUGIN_MECHANISM_DRIVERS=ovn,logger
Q_ML2_PLUGIN_TYPE_DRIVERS=local,flat,vlan,geneve
Q_ML2_TENANT_NETWORK_TYPE="geneve"

# Enable OVN services
enable_service ovn-northd
enable_service ovn-controller
enable_service q-ovn-metadata-agent

# Use Neutron
enable_service q-svc

# Disable Neutron agents not used with OVN.
disable_service q-agt
disable_service q-l3
disable_service q-dhcp
disable_service q-meta

# Enable services, these services depend on neutron plugin.
enable_plugin neutron https://opendev.org/openstack/neutron ${openstack_rev}
enable_service q-trunk
enable_service q-dns

# Cinder (OpenStack Block Storage) is disabled by default to speed up
# DevStack a bit. You may enable it here if you would like to use it.
#disable_service cinder c-sch c-api c-vol

#ENABLE_CHASSIS_AS_GW=True

# If you wish to use the provider network for public access to the cloud,
# set the following
Q_USE_PROVIDERNET_FOR_PUBLIC=True

# This needs to be equalized with Neutron devstack
PUBLIC_NETWORK_GATEWAY="172.24.4.1"

# Octavia
enable_plugin octavia https://opendev.org/openstack/octavia ${openstack_rev}
enable_plugin octavia-dashboard https://opendev.org/openstack/octavia-dashboard ${openstack_rev}
enable_service octavia o-api o-cw o-hm o-hk o-da

# OVN octavia provider plugin
enable_plugin ovn-octavia-provider https://opendev.org/openstack/ovn-octavia-provider ${openstack_rev}
EOF

"$HOME/devstack/tools/create-stack-user.sh"

mv "$HOME/devstack" /opt/stack/
chown -R stack:stack /opt/stack/devstack/

install -o stack -g stack -m 0755 /root/build_octavia_image.sh /opt/stack/build_octavia_image.sh

su - stack -c /opt/stack/devstack/stack.sh

echo 'source /opt/stack/devstack/openrc admin admin' >> /opt/stack/.bashrc
