#!/usr/bin/env bash
# shellcheck disable=SC2154  # openstack_rev is injected by Terraform templatefile()

set -e

git clone https://opendev.org/openstack/octavia -b "${openstack_rev}" "$HOME/octavia"
cd "$HOME/octavia/diskimage-create"
python3 -m venv dib-venv
# shellcheck source=/dev/null
source dib-venv/bin/activate
pip install diskimage-builder
./diskimage-create.sh

# shellcheck source=/dev/null
source /opt/stack/devstack/openrc admin admin
openstack image create "$HOME/octavia/diskimage-create/amphora-x64-haproxy.qcow2" --container-format bare --disk-format qcow2 --private --tag amphora --file amphora-x64-haproxy.qcow2 --property hw_architecture="x86_64" --property hw_rng_model=virtio

openstack loadbalancer flavorprofile create --name m1.small --provider amphora --flavor-data '{"loadbalancer_topology": "SINGLE", "compute_flavor": "1"}'
openstack loadbalancer flavor create --name small-lb --flavorprofile m1.small --enable
