#!/usr/bin/env bash

set -euo pipefail

# Remove all resources created with tofu
for dom in $(sudo virsh list --all --name); do
    echo "Shutting down $dom..."
    sudo virsh shutdown "$dom" || true

    # Wait for the VM to stop
    while [[ $(sudo virsh domstate "$dom") != "shut off" ]]; do
        echo "Waiting for $dom to stop..."
        sleep 1
    done

    # Undefine and remove storage once stopped
    echo "Undefining $dom and removing storage..."
    sudo virsh undefine "$dom" --remove-all-storage || true
done

rm -rf terraform.tfstate*

sudo virsh net-undefine devstack_net || true
sudo virsh net-destroy devstack_net || true
sudo virsh pool-undefine devstack || true
sudo virsh pool-destroy devstack || true
