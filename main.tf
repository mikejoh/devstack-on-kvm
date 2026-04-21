locals {
  network_prefix  = tonumber(split("/", var.devstack_network_cidr)[1])
  network_gateway = cidrhost(var.devstack_network_cidr, 1)

  install_devstack_sh = templatefile(
    "${path.module}/cloud-init/install_devstack.sh",
    { openstack_rev = var.openstack_rev }
  )

  build_octavia_image_sh = templatefile(
    "${path.module}/cloud-init/build_octavia_image.sh",
    { openstack_rev = var.openstack_rev }
  )

  cloud_init_user_data = {
    for node in var.devstack_nodes : node.name => templatefile(
      "${path.module}/cloud-init/cloud_init.cfg",
      {
        ssh_public_key         = file(pathexpand(var.ssh_public_key_path))
        hostname               = "${var.cluster_name}-${node.name}"
        install_devstack_sh    = local.install_devstack_sh
        build_octavia_image_sh = local.build_octavia_image_sh
      }
    )
  }

  cloud_init_network_config = file("${path.module}/cloud-init/network_config.cfg")
}

resource "libvirt_pool" "pool" {
  name = "devstack"
  type = "dir"
  target = {
    path = var.pool_path
  }
}

resource "libvirt_volume" "base" {
  name = "${var.cluster_name}-base.qcow2"
  pool = libvirt_pool.pool.name
  target = {
    format = {
      type = "qcow2"
    }
  }
  create = {
    content = {
      url = var.image_source
    }
  }
}

resource "libvirt_volume" "node_disk" {
  for_each = { for node in var.devstack_nodes : node.name => node }
  name     = "${var.cluster_name}-${each.value.name}.qcow2"
  pool     = libvirt_pool.pool.name
  capacity = each.value.disk_size
  target = {
    format = {
      type = "qcow2"
    }
  }
  backing_store = {
    path = libvirt_volume.base.path
    format = {
      type = "qcow2"
    }
  }
}

resource "libvirt_cloudinit_disk" "cloud_init" {
  for_each       = { for node in var.devstack_nodes : node.name => node }
  name           = "${var.cluster_name}-${each.value.name}-cloudinit.iso"
  user_data      = local.cloud_init_user_data[each.key]
  network_config = local.cloud_init_network_config
  meta_data = yamlencode({
    instance-id    = "${var.cluster_name}-${each.value.name}"
    local-hostname = "${var.cluster_name}-${each.value.name}"
  })
}

resource "libvirt_volume" "cloudinit_iso" {
  for_each = { for node in var.devstack_nodes : node.name => node }
  name     = "${var.cluster_name}-${each.value.name}-cloudinit-disk.iso"
  pool     = libvirt_pool.pool.name
  create = {
    content = {
      url = libvirt_cloudinit_disk.cloud_init[each.key].path
    }
  }
}

resource "libvirt_network" "network" {
  name      = "devstack_net"
  autostart = true
  forward = {
    mode = "nat"
  }
  ips = [
    {
      address = local.network_gateway
      prefix  = local.network_prefix
      dhcp = {
        ranges = [
          {
            start = cidrhost(var.devstack_network_cidr, 2)
            end   = cidrhost(var.devstack_network_cidr, -2)
          }
        ]
      }
    }
  ]
}

resource "libvirt_domain" "nodes" {
  for_each    = { for node in var.devstack_nodes : node.name => node }
  name        = "${var.cluster_name}-${each.value.name}"
  description = "DevStack"
  memory      = each.value.memory
  memory_unit = "MiB"
  vcpu        = each.value.vcpu
  type        = "kvm"
  running     = true

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
  }

  cpu = {
    mode = "host-passthrough"
  }

  devices = {
    disks = [
      {
        source = {
          volume = {
            pool   = libvirt_volume.node_disk[each.key].pool
            volume = libvirt_volume.node_disk[each.key].name
          }
        }
        target = {
          dev = "vda"
          bus = "virtio"
        }
        driver = {
          type = "qcow2"
        }
      },
      {
        device = "cdrom"
        source = {
          volume = {
            pool   = libvirt_volume.cloudinit_iso[each.key].pool
            volume = libvirt_volume.cloudinit_iso[each.key].name
          }
        }
        target = {
          dev = "sda"
          bus = "sata"
        }
      },
    ]

    interfaces = [
      {
        model = {
          type = "virtio"
        }
        source = {
          network = {
            network = libvirt_network.network.name
          }
        }
      },
    ]

    serials = [
      {
        type = "pty"
      }
    ]

    consoles = [
      {
        type        = "pty"
        target_type = "serial"
        target_port = "0"
      }
    ]
  }
}
