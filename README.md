# DevStack on KVM

Deploy [DevStack](https://docs.openstack.org/devstack/latest/) on KVM! 🚀

_For those occasions when you want to test things against OpenStack (APIs) but you don't want to use the one(s) in production._ 😏

## ✅ Pre-requisites

* KVM
* OpenTofu (the `terraform` fork)

## 🗒️ Important notes

* It'll take some time for the DevStack installation to complete, please run `sudo virsh console devstack01` to follow the installation. Press `Ctrl+5` to exit the console. Please note that we're installing Octavia with everything included (like building of the Octavia worker image), so please be patient.
* Before starting, stop `ufw` temporarily if it's running locally, i haven't found a good combination of FW rules yet.
* Info on how to perform configuration customization when installing DevStack check [this](https://github.com/openstack/devstack/blob/master/doc/source/configuration.rst) out.

## 🏃 Getting started

### Provision cluster nodes

1. Change the `devstack.auto.tfvars` to fit your needs!
2. Run `tofu init`
3. Run `tofu plan`
4. Run `tofu apply`
5. The needed nodes shall be provisioned with everything included for you to start bootstrapping the cluster.

To see the progress of the DevStack installation, run the following command:

```bash
sudo virsh console devstack01
```

### Accessing the DevStack environment

_Remember to start your VMs after a reboot, they'll be shut off by default. Run `sudo virsh start` for each VM!_

#### Browse to the DevStack dashboard

Open your browser and go to the following URL:

```bash
http://<devstack01-ip>/
```

To find out the IP addresses of the VMs you can run the following using `virsh`:

```bash
sudo virsh net-dhcp-leases devstack_net
```

The DevStack dashboard (Horizon) can be logged into using the following credentials:

```
Username: demo
Password: secret
```

#### SSH to the DevStack instance

This requires that you have [`fzf`](https://github.com/junegunn/fzf) installed.

```bash
PRIVATE_SSH_KEY=~/.ssh/devstack scripts/ssh.sh
```

_Make sure you're using the private key that matches the public key added as part of the cluster node provisioning. We're adding a user called `cloud` by default that has the provided public key as one of the `ssh_authorized_keys`._

Run this to generate a new SSH key pair, make sure to point to the public key and it's path in the `tfvars` file:

```
ssh-keygen -t ed25519 -C "devstack-kvm" -f ~/.ssh/devstack
```

#### Using `tmux` and `xpanes` to SSH to all available nodes

Don't forget to inline the private key path below and replace `<PRIVATE_KEY>` before running the command:

```bash
tmux

sudo virsh net-dhcp-leases devstack_net | tail -n +3 | awk '{print $5 }' | cut -d"/" -f1 | xpanes -l ev -c 'ssh -l cloud -i <PRIVATE_KEY> {}'
```

### How to reach the public IP address range in DevStack

In DevStack the `public` network will have the following range by default: `172.24.4.0/24`.

1. Enable proxy arp in the `devstack01` VM primary interface:

```
echo 1 > /proc/sys/net/ipv4/conf/ens3/proxy_arp
```

_Please note that my interface were named `ens3`._

2. Associating floating IPs to e.g. Loadbalancers or instances
3. Update security groups if needed, i had to allow more in the `default` security group (created automatically)
4. Update your local routing table, i needed to do the following:

```
sudo ip route add 172.24.4.0/24 dev virbr1
```

`virbr1` was the bridge that my `devstack01` VM was connected to as of writing this.

### Cleaning things up

Run `tofu destroy`.

_Note that this destroys all of KVM related objects._

## 🛠️ Troubleshooting

### List all `systemd` units related to DevStack and their statuses

```
systemctl list-units 'devstack@*'
```

For `systemd` related documentation see [this](https://docs.openstack.org/devstack/latest/systemd.html) link.

### DevStack logs

Checking logs:

```
journalctl -f -u devstack@*
journalctl -f -u devstack@<service>
```

### Various encountered errors and problems

#### Updating objects in Glance 

When updating (increasing) the `image_size_total` in Glance via the `openstack` CLI the following where seen in the `g-api` logs:

```
Unhandled error: oslo_db.exception.DBDeadlock: (pymysql.err.OperationalError) (1205, 'Lock wait timeout exceeded; try restarting transaction')
```

Fixed by restarting the `mysql` service in the DevStack VM:

```
systemctl restart mysql
```

#### Error when listing instances after starting the DevStack VM

Horizon stack trace:

```
Traceback (most recent call last):
  File "/opt/stack/data/venv/lib/python3.10/site-packages/django/core/handlers/exception.py", line 55, in inner
    response = get_response(request)
  File "/opt/stack/data/venv/lib/python3.10/site-packages/django/core/handlers/base.py", line 197, in _get_response
    response = wrapped_callback(request, *callback_args, **callback_kwargs)
  File "/opt/stack/horizon/horizon/decorators.py", line 51, in dec
    return view_func(request, *args, **kwargs)
  File "/opt/stack/horizon/horizon/decorators.py", line 35, in dec
    return view_func(request, *args, **kwargs)
  File "/opt/stack/horizon/horizon/decorators.py", line 35, in dec
    return view_func(request, *args, **kwargs)
  File "/opt/stack/horizon/horizon/decorators.py", line 111, in dec
    return view_func(request, *args, **kwargs)
  File "/opt/stack/horizon/horizon/decorators.py", line 83, in dec
    return view_func(request, *args, **kwargs)
  File "/opt/stack/data/venv/lib/python3.10/site-packages/django/views/generic/base.py", line 104, in view
    return self.dispatch(request, *args, **kwargs)
  File "/opt/stack/data/venv/lib/python3.10/site-packages/django/views/generic/base.py", line 143, in dispatch
    return handler(request, *args, **kwargs)
  File "/opt/stack/horizon/horizon/tables/views.py", line 222, in get
    handled = self.construct_tables()
  File "/opt/stack/horizon/horizon/tables/views.py", line 213, in construct_tables
    handled = self.handle_table(table)
  File "/opt/stack/horizon/horizon/tables/views.py", line 122, in handle_table
    data = self._get_data_dict()
  File "/opt/stack/horizon/horizon/tables/views.py", line 251, in _get_data_dict
    self._data = {self.table_class._meta.name: self.get_data()}
  File "/opt/stack/horizon/openstack_dashboard/dashboards/project/instances/views.py", line 156, in get_data
    futurist_utils.call_functions_parallel(
  File "/opt/stack/horizon/openstack_dashboard/utils/futurist_utils.py", line 50, in call_functions_parallel
    return tuple(f.result() for f in futures)
  File "/opt/stack/horizon/openstack_dashboard/utils/futurist_utils.py", line 50, in <genexpr>
    return tuple(f.result() for f in futures)
  File "/usr/lib/python3.10/concurrent/futures/_base.py", line 451, in result
    return self.__get_result()
  File "/usr/lib/python3.10/concurrent/futures/_base.py", line 403, in __get_result
    raise self._exception
  File "/opt/stack/data/venv/lib/python3.10/site-packages/futurist/_utils.py", line 45, in run
    result = self.fn(*self.args, **self.kwargs)
  File "/opt/stack/horizon/openstack_dashboard/dashboards/project/instances/views.py", line 148, in _get_volumes
    exceptions.handle(self.request, ignore=True)
  File "/opt/stack/horizon/openstack_dashboard/dashboards/project/instances/views.py", line 145, in _get_volumes
    volumes = api.cinder.volume_list(self.request)
  File "/opt/stack/horizon/openstack_dashboard/api/cinder.py", line 298, in volume_list
    volumes, _, __ = volume_list_paged(
  File "/opt/stack/horizon/openstack_dashboard/api/cinder.py", line 337, in volume_list_paged
    c_client = _cinderclient_with_generic_groups(request)
  File "/opt/stack/horizon/openstack_dashboard/api/cinder.py", line 289, in _cinderclient_with_generic_groups
    return _cinderclient_with_features(request, 'groups')
  File "/opt/stack/horizon/openstack_dashboard/api/cinder.py", line 271, in _cinderclient_with_features
    version = get_microversion(request, features)
  File "/opt/stack/horizon/openstack_dashboard/api/cinder.py", line 263, in get_microversion
    min_ver, max_ver = cinder_client.get_server_version(cinder_url,
  File "/opt/stack/data/venv/lib/python3.10/site-packages/cinderclient/client.py", line 119, in get_server_version
    data = json.loads(response.text)
  File "/usr/lib/python3.10/json/__init__.py", line 346, in loads
    return _default_decoder.decode(s)
  File "/usr/lib/python3.10/json/decoder.py", line 337, in decode
    obj, end = self.raw_decode(s, idx=_w(s, 0).end())
  File "/usr/lib/python3.10/json/decoder.py", line 355, in raw_decode
    raise JSONDecodeError("Expecting value", s, err.value) from None
```

Which pointed at a Cinder related problem. I fixed this by restarting the Cinder API and Cinder Volume services:

```
systemctl restart devstack@c-api.service devstack@c-vol.service
```
