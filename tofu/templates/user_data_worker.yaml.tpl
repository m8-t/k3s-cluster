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

bootcmd:
  - modprobe br_netfilter
  - modprobe overlay

write_files:
  - path: /etc/modules-load.d/k3s.conf
    content: |
      br_netfilter
      overlay

  - path: /etc/sysctl.d/99-k3s.conf
    content: |
      net.bridge.bridge-nf-call-iptables = 1
      net.bridge.bridge-nf-call-ip6tables = 1
      net.ipv4.ip_forward = 1
      net.ipv6.conf.all.forwarding = 1

runcmd:
  - sysctl --system
  - swapoff -a
  - sed -i '/\sswap\s/d' /etc/fstab
  - mkdir -p /etc/rancher/k3s
  - |
    cat > /etc/rancher/k3s/config.yaml << 'EOF'
    server: "https://${kube_vip_ip}:6443"
    token: "${k3s_token}"
    EOF
  # Wait for kube-vip VIP to be available (confirms at least one master is up and kube-vip is running)
  - until curl -sk -o /dev/null -w "%%{http_code}" https://${kube_vip_ip}:6443/healthz | grep -qE "200|401"; do sleep 5; done
  - curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${k3s_version}" sh -s - agent
  - systemctl start k3s-agent || true
  - systemctl start qemu-guest-agent || true
