#cloud-config
hostname: ${hostname}
fqdn: ${hostname}.local
manage_etc_hosts: true

users:
  - name: debian
    gecos: Debian User
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: true
    ssh_authorized_keys:
      - ${ssh_public_key}

packages:
  - qemu-guest-agent
  - curl
  - ca-certificates

package_update: true
package_upgrade: true

runcmd:
  - systemctl enable --now qemu-guest-agent
