variable "openstack_rev" {
  type = string
}

variable "ssh_public_key_path" {
  type = string
}

variable "devstack_network_cidr" {
  type = string
}

variable "devstack_nodes" {
  type = set(object({
    name      = string
    vcpu      = number
    memory    = number
    disk_size = number
  }))
}

variable "image_source" {
  type = string
}

variable "pool_path" {
  type = string
}
