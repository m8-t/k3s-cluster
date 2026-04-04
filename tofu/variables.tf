variable "libvirt_uri" {
  description = "Libvirt connection URI"
  type        = string
  default     = "qemu:///system"
}

variable "base_image_url" {
  description = "URL to openSUSE MicroOS OpenStack Cloud qcow2 image"
  type        = string
  default     = "https://download.opensuse.org/tumbleweed/appliances/openSUSE-MicroOS.x86_64-OpenStack-Cloud.qcow2"
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

  validation {
    condition     = can(cidrhost(var.network_cidr, 0))
    error_message = "network_cidr must be a valid CIDR block (e.g., 192.168.100.0/24)."
  }
}

variable "gateway" {
  description = "Gateway IP for the k3s network"
  type        = string
  default     = "192.168.100.1"

  validation {
    condition     = can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$", var.gateway))
    error_message = "gateway must be a valid IPv4 address."
  }
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

variable "k3s_token" {
  description = "Shared cluster token — generate with: openssl rand -hex 32"
  type        = string
  sensitive   = true
  default     = ""
}

variable "k3s_version" {
  description = "k3s version to install"
  type        = string
  default     = "v1.35.3+k3s1"
}

variable "kube_vip_ip" {
  description = "ARP virtual IP for the k3s API server (kube-vip)"
  type        = string
  default     = "192.168.100.100"

  validation {
    condition     = can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$", var.kube_vip_ip))
    error_message = "kube_vip_ip must be a valid IPv4 address."
  }
}

variable "kube_vip_version" {
  description = "kube-vip image version"
  type        = string
  default     = "v0.8.9"
}

variable "suc_version" {
  description = "system-upgrade-controller version"
  type        = string
  default     = "v0.19.0"
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

