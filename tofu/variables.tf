variable "libvirt_uri" {
  description = "Libvirt connection URI"
  type        = string
  default     = "qemu:///system"
}

variable "base_image_url" {
  description = "URL to Debian 12 (Bookworm) genericcloud qcow2 image"
  type        = string
  default     = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
}

variable "storage_pool" {
  description = "Libvirt storage pool name"
  type        = string
  default     = "default"
}

variable "network_name" {
  description = "Name for the k3s libvirt network"
  type        = string
  default     = "k3s-net"
}

variable "network_cidr" {
  description = "CIDR for the k3s NAT network"
  type        = string
  default     = "192.168.100.0/24"
}

variable "gateway" {
  description = "Gateway IP for the k3s network"
  type        = string
  default     = "192.168.100.1"
}

variable "dns_servers" {
  description = "DNS servers for VMs"
  type        = list(string)
  default     = ["8.8.8.8", "1.1.1.1"]
}

variable "ssh_public_key" {
  description = "SSH public key content for VM access"
  type        = string
}

variable "masters" {
  description = "Master node configurations (2 GB RAM each for etcd + API server)"
  type = map(object({
    ip     = string
    vcpu   = number
    memory = number
  }))
  default = {
    "k3s-master-1" = { ip = "192.168.100.11", vcpu = 2, memory = 2048 }
    "k3s-master-2" = { ip = "192.168.100.12", vcpu = 2, memory = 2048 }
    "k3s-master-3" = { ip = "192.168.100.13", vcpu = 2, memory = 2048 }
  }
}

variable "workers" {
  description = "Worker node configurations (1.5 GB RAM each, k3s agent is lightweight)"
  type = map(object({
    ip     = string
    vcpu   = number
    memory = number
  }))
  default = {
    "k3s-worker-1" = { ip = "192.168.100.21", vcpu = 1, memory = 1536 }
    "k3s-worker-2" = { ip = "192.168.100.22", vcpu = 1, memory = 1536 }
    "k3s-worker-3" = { ip = "192.168.100.23", vcpu = 1, memory = 1536 }
  }
}

