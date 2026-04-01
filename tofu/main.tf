terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.9"
    }
  }
  required_version = ">= 1.6.0"
}

provider "libvirt" {
  uri = var.libvirt_uri
}

locals {
  all_vms = merge(
    { for k, v in var.masters : k => merge(v, { role = "master" }) },
    { for k, v in var.workers : k => merge(v, { role = "worker" }) }
  )

  init_master_key  = "k3s-master-1"
  init_master_ip   = var.masters["k3s-master-1"].ip
  master_ips       = [for k, v in var.masters : v.ip]
  master_hostnames = sort(keys(var.masters))
}

# ── Network ───────────────────────────────────────────────────────────────────
# nested_type attributes use = { } (single) or = [{ }] (list) syntax in v0.9.x

resource "libvirt_network" "k3s_net" {
  name = var.network_name

  forward = {
    mode = "nat"
  }

  # ips is a list nested_type — one entry sets the gateway; no dhcp block = DHCP disabled
  ips = [{
    address = var.gateway
    prefix  = 24
    family  = "ipv4"
  }]

  dns = {
    enable = "yes"
  }
}

# ── Base image (downloaded once, shared as backing file) ──────────────────────

resource "libvirt_volume" "base_image" {
  name = "debian-13-k3s-base.qcow2"
  pool = var.storage_pool

  create = {
    content = {
      url = var.base_image_url
    }
  }

  target = {
    format = {
      type = "qcow2"
    }
  }
}

# ── Per-VM disks (thin-provisioned qcow2, backed by base image) ───────────────

resource "libvirt_volume" "vm_disk" {
  for_each = local.all_vms

  name = "${each.key}.qcow2"
  pool = var.storage_pool

  capacity      = 50
  capacity_unit = "GiB"

  backing_store = {
    path = libvirt_volume.base_image.path
    format = {
      type = "qcow2"
    }
  }

  target = {
    format = {
      type = "qcow2"
    }
  }
}

# ── Cloud-init ISO per VM ─────────────────────────────────────────────────────

resource "libvirt_cloudinit_disk" "vm_ci" {
  for_each = local.all_vms

  name = "${each.key}-ci.iso"

  user_data = (
    each.key == local.init_master_key
    ? templatefile("${path.module}/templates/user_data_init_master.yaml.tpl", {
        hostname         = each.key
        ssh_public_key   = var.ssh_public_key
        k3s_version      = var.k3s_version
        k3s_token        = var.k3s_token
        kube_vip_ip      = var.kube_vip_ip
        kube_vip_version = var.kube_vip_version
        master_ips       = local.master_ips
        master_hostnames = local.master_hostnames
      })
    : each.value.role == "master"
    ? templatefile("${path.module}/templates/user_data_join_master.yaml.tpl", {
        hostname         = each.key
        ssh_public_key   = var.ssh_public_key
        k3s_version      = var.k3s_version
        k3s_token        = var.k3s_token
        kube_vip_ip      = var.kube_vip_ip
        kube_vip_version = var.kube_vip_version
        init_master_ip   = local.init_master_ip
        master_ips       = local.master_ips
        master_hostnames = local.master_hostnames
      })
    : templatefile("${path.module}/templates/user_data_worker.yaml.tpl", {
        hostname       = each.key
        ssh_public_key = var.ssh_public_key
        k3s_version    = var.k3s_version
        k3s_token      = var.k3s_token
        kube_vip_ip    = var.kube_vip_ip
      })
  )

  meta_data = templatefile("${path.module}/templates/meta_data.yaml.tpl", {
    hostname = each.key
  })

  network_config = templatefile("${path.module}/templates/network_config.yaml.tpl", {
    ip_address  = each.value.ip
    gateway     = var.gateway
    dns_servers = var.dns_servers
  })
}

# ── Virtual machines ──────────────────────────────────────────────────────────

resource "libvirt_domain" "vm" {
  for_each = local.all_vms

  name        = each.key
  type        = "kvm"
  running     = true
  on_crash    = "restart"
  memory      = each.value.memory
  memory_unit = "MiB"
  vcpu        = each.value.vcpu

  cpu = {
    mode = "host-passthrough"
  }

  os = {
    type = "hvm"
    boot_devices = [{
      dev = "hd"
    }]
  }

  devices = {
    disks = [
      {
        # Main OS disk — thin-provisioned qcow2 via backing file
        source = {
          volume = {
            pool   = var.storage_pool
            volume = libvirt_volume.vm_disk[each.key].name
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
        # Cloud-init ISO — read-only, detached after first boot
        source = {
          file = {
            file = libvirt_cloudinit_disk.vm_ci[each.key].path
          }
        }
        target = {
          dev = "vdb"
          bus = "virtio"
        }
        read_only = true
      }
    ]

    interfaces = [{
      source = {
        network = {
          network = libvirt_network.k3s_net.name
        }
      }
      model = {
        type = "virtio"
      }
    }]

    graphics = [{
      spice = {
        auto_port = true
        listen    = "0.0.0.0"
      }
    }]

    consoles = [{
      type = "pty"
      target = {
        type = "serial"
        port = "0"
      }
    }]
  }

  lifecycle {
    replace_triggered_by = [
      libvirt_cloudinit_disk.vm_ci[each.key],
    ]
  }
}

# ── Ansible provisioning ──────────────────────────────────────────────────────
# Runs after all VMs are created. Re-runs if any VM is replaced.

resource "null_resource" "ansible" {
  depends_on = [libvirt_domain.vm]

  triggers = {
    vm_ids = join(",", sort([for vm in libvirt_domain.vm : vm.id]))
  }

  provisioner "local-exec" {
    working_dir = "${path.module}/../ansible"
    command     = "ansible-playbook site.yml && ansible-playbook addons.yml"
  }
}
