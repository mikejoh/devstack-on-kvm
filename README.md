# DevStack on KVM

Deploy [DevStack](https://docs.openstack.org/devstack/latest/) on KVM! 🚀

_For those occasions when you want to test things against OpenStack (APIs) but you don't want to use the one(s) in production._ 😏

## ✅ Pre-requisites

* KVM (see your favourite Linux distribution how-to)
* OpenTofu (the `terraform` fork)

## 🗒️ Important notes

* See the `scripts/` folder for various utility scripts.
* You probably want to change `user` and `group` to `libvirt-qemu` and `kvm` respectively in `/etc/libvirt/qemu.conf` to mitigate permission issues on storage pools.
* All nodes will be running Ubuntu 22.04 by default (tied to the Octavia/DevStack stable branch).
* Installation takes a while — DevStack + building the Octavia amphora image is 30+ minutes. Watch progress with `sudo virsh console devstack-01` (exit with `Ctrl+5`).
* Info on DevStack configuration customization is [here](https://github.com/openstack/devstack/blob/master/doc/source/configuration.rst).

## 🏃 Getting started

### Firewall rules (only if `ufw` is active on the host)

Skip this section if you don't run `ufw`. If you do, don't disable it — add narrowly-scoped rules instead. The VMs sit behind a libvirt NAT network and rely on the host to forward their traffic to the internet; during provisioning cloud-init pulls apt packages, DevStack clones several OpenStack repos, and the amphora image builder downloads more. `ufw`'s default-drop `FORWARD` policy will silently kill those packets and bootstrap will hang partway through.

The VM subnet is deterministic — whatever you set as `devstack_network_cidr` in `devstack01.auto.tfvars`. Scope rules to that CIDR rather than to the bridge interface (libvirt picks `virbr0`, `virbr1`, ... based on creation order, and the name can drift if you recreate networks).

```bash
# Replace 192.168.11.0/24 with your devstack_network_cidr.

# Allow forwarded traffic from the VM network to anywhere (internet access)
sudo ufw route allow from 192.168.11.0/24

# Allow the VMs to reach libvirt's dnsmasq on the host for DHCP and DNS
sudo ufw allow in on virbr1 to any port 67 proto udp
sudo ufw allow in on virbr1 to any port 53
```

If you don't know which bridge libvirt assigned to `devstack_net`, check with `virsh net-dumpxml devstack_net | grep bridge`.

### Set up libvirt for rootless access

The scripts in this repo assume you can talk to the system libvirt daemon without `sudo`. Three things need to be true:

1. **Your user is in the `libvirt` group.** Add yourself if not:

    ```bash
    sudo usermod -aG libvirt "$USER"
    ```

    Log out and back in (or `newgrp libvirt`) so the group is active in your shell.

2. **The system libvirt daemon is running.** Recent libvirt (default in Arch, Fedora, RHEL 9+) splits the old monolithic `libvirtd` into one socket-activated daemon per subsystem — `virtqemud` handles VM domains, `virtnetworkd` virtual networks, `virtstoraged` storage pools, `virtnwfilterd` packet filters, `virtsecretd` secrets. Enable their sockets so each starts on demand:

    ```bash
    sudo systemctl enable --now virtqemud.socket virtnetworkd.socket virtstoraged.socket virtnwfilterd.socket virtsecretd.socket
    ```

    On distros that still ship the monolithic daemon (e.g. Debian, Ubuntu), `sudo systemctl enable --now libvirtd.socket` replaces all of the above.

3. **`virsh` defaults to `qemu:///system`.** Without configuration, bare `virsh` connects to `qemu:///session` — a separate per-user daemon that does *not* see the VMs this repo creates. Point libvirt clients at the system daemon:

    ```bash
    mkdir -p ~/.config/libvirt
    echo 'uri_default = "qemu:///system"' >> ~/.config/libvirt/libvirt.conf
    ```

Verify the wiring before provisioning:

```bash
virsh uri          # should print qemu:///system
virsh list --all   # should return without permission errors
```

### Provision the VM

1. Generate an SSH keypair that cloud-init will embed into the `cloud` user (skip if you already have one you want to reuse):

    ```bash
    ssh-keygen -t ed25519 -C "devstack-kvm" -f ~/.ssh/devstack
    ```

2. Change the `devstack01.auto.tfvars` to fit your needs:

    - `ssh_public_key_path` — path to the `.pub` from step 1.
    - `pool_path` — an existing directory on your host that qemu (typically running as `libvirt-qemu:kvm`) can read and write.
    - `cluster_name` — prefix used for libvirt domains and volumes. Default `devstack`; the single node becomes `devstack-01`.
    - `devstack_network_cidr`, `openstack_rev`, and the `devstack_nodes` list — tune to match what you want.

3. Run `tofu init`, `tofu plan`, `tofu apply`.

4. The node(s) will be provisioned with DevStack (OVN, Neutron, Octavia) running `stack.sh` automatically.

To follow the installation:

```bash
virsh console devstack-01
```

### Accessing the DevStack environment

_Remember to start your VMs after a reboot; `tofu apply` starts them but they'll be shut off by default after a host reboot. Run `virsh start devstack-01` for each VM._

#### Browse to the DevStack dashboard (Horizon)

```
http://<node-ip>/
```

Credentials:

```
Username: demo
Password: secret
```

Find VM IPs with:

```bash
virsh net-dhcp-leases devstack_net
```

#### SSH to the DevStack instance

This requires [`fzf`](https://github.com/junegunn/fzf):

```bash
PRIVATE_SSH_KEY=~/.ssh/devstack scripts/ssh.sh
```

_Make sure you're using the private key that matches the public key added as part of node provisioning. A `cloud` user is created with the provided public key as one of the `ssh_authorized_keys`._

#### Using `tmux` and `xpanes` to SSH to all available nodes

```bash
tmux

virsh net-dhcp-leases devstack_net | tail -n +3 | awk '{print $5 }' | cut -d"/" -f1 | xpanes -l ev -c 'ssh -l cloud -i <PRIVATE_KEY> {}'
```

### Building the Octavia amphora image

`install_devstack.sh` runs `stack.sh` but does **not** build the amphora image. After DevStack finishes, SSH to the node and run:

```bash
sudo -u stack bash /opt/stack/build_octavia_image.sh
```

### How to reach the public IP address range in DevStack

In DevStack the `public` network will have the following range by default: `172.24.4.0/24`.

1. Enable proxy arp on the VM's primary interface (inside the VM):

    ```bash
    echo 1 > /proc/sys/net/ipv4/conf/ens3/proxy_arp
    ```

2. Associate floating IPs to e.g. loadbalancers or instances, and update security groups if needed (the `default` security group is typically too restrictive).

3. Update your host's routing table:

    ```bash
    sudo ip route add 172.24.4.0/24 dev virbr1
    ```

    `virbr1` was the bridge assigned to the VM at time of writing — check with `virsh net-dumpxml devstack_net | grep bridge`. Both of these steps are **not persistent** across reboots.

### Cleaning up

Run `scripts/clean_up.sh` to tear down this cluster and reset tofu state. The script reads `cluster_name` from `devstack01.auto.tfvars` and only touches domains whose name starts with that prefix, so unrelated VMs on the same libvirt host are left alone. It also destroys the `devstack_net` network and `devstack` pool (both created by this repo) and removes `terraform.tfstate*` files.

## 🛠️ Troubleshooting

### List all `systemd` units related to DevStack and their statuses

```
systemctl list-units 'devstack@*'
```

For `systemd` related documentation see [this](https://docs.openstack.org/devstack/latest/systemd.html) link.

### DevStack logs

```
journalctl -f -u devstack@*
journalctl -f -u devstack@<service>
```

### Various encountered errors and problems

#### Updating objects in Glance

When updating (increasing) the `image_size_total` in Glance via the `openstack` CLI the following was seen in the `g-api` logs:

```
Unhandled error: oslo_db.exception.DBDeadlock: (pymysql.err.OperationalError) (1205, 'Lock wait timeout exceeded; try restarting transaction')
```

Fixed by restarting `mysql` in the DevStack VM:

```
systemctl restart mysql
```

#### Error when listing instances after starting the DevStack VM

Horizon stack trace pointed at a Cinder-related problem. Fixed by restarting the Cinder API and Cinder Volume services:

```
systemctl restart devstack@c-api.service devstack@c-vol.service
```
