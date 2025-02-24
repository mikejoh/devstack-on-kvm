openstack_rev         = "stable/2024.1"
image_source          = "https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img"
pool_path             = "<path>/devstack-pool"
ssh_public_key_path   = "<path>/devstack.pub"
devstack_network_cidr = "192.168.11.0/24"

devstack_nodes = [
  {
    name      = "devstack01"
    vcpu      = 6
    memory    = 12288
    disk_size = 42949672960
  }
]
