# Devstack on KVM

Deploy [Devstack](https://docs.openstack.org/devstack/latest/) on KVM! 🚀

_For those occasions when you want to test things against OpenStack (APIs) but you don't want to use the one(s) in production._ 😏

## ✅ Pre-requisites

* KVM
* OpenTofu (the `terraform` fork)

## 🗒️ Important notes

Info on how to perform configuration cusomization when installing Devstack check [this](https://github.com/openstack/devstack/blob/master/doc/source/configuration.rst) out.

## 🏃 Getting started

Before starting, stop `ufw` temporarily if it's running locally.

### Provision cluster nodes

1. Change the `devstack.auto.tfvars` to fit your needs!
2. Run `tofu init`
3. Run `tofu plan`
4. Run `tofu apply`
5. The needed nodes shall be provisioned with everything included for you to start bootstrapping the cluster.

### Accessing the nodes

_Remember to start your VMs after a reboot, they'll be shut off by default. Run `sudo virsh start` for each VM!_

#### SSH to one node a time

To find out the IP addresses of the VMs you can run the following using `virsh`:

```bash
sudo virsh net-dhcp-leases devstack_net
```

#### SSH using the provided helper script

This requires that you have [`fzf`](https://github.com/junegunn/fzf) installed.

```bash
PRIVATE_SSH_KEY=~/.ssh/devstack scripts/ssh.sh
```

_Make sure you're using the private key that matches the public key added as part of the cluster node provisioning. We're adding a user called `cloud` by default that has the provided public key as one of the `ssh_authorized_keys`._

#### Using `tmux` and `xpanes` to SSH to all available nodes

Don't forget to inline the private key path below and replace `<PRIVATE_KEY>` before running the command:

```bash
tmux

sudo virsh net-dhcp-leases devstack_net | tail -n +3 | awk '{print $5 }' | cut -d"/" -f1 | xpanes -l ev -c 'ssh -l cloud -i <PRIVATE_KEY> {}'
```

### Troubleshooting

#### Devstack logs

Various ways of checking logs:

```
journalctl -f -u devstack@*
journalctl -f -u devstack@* | grep -v dstat

```

#### Various encountered errors and problems

When updating (increasing) the `image_size_total` in Glance via the `openstack` CLI the following where seen in the `g-api` logs:

```
Unhandled error: oslo_db.exception.DBDeadlock: (pymysql.err.OperationalError) (1205, 'Lock wait timeout exceeded; try restarting transaction')
```

Fixed by restarting the `mysql` service in the Devstack VM.

### Clean up

Use the provided `clean_up.sh` script in the `scripts/` directory.
