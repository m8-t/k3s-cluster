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

# bootcmd runs on every boot before write_files/packages/runcmd — ensures
# modules are loaded before any sysctl settings referencing them are applied
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
    cluster-init: true
    token: "${k3s_token}"
    tls-san:
      - "${kube_vip_ip}"
%{ for ip in master_ips ~}
      - "${ip}"
%{ endfor ~}
%{ for name in master_hostnames ~}
      - "${name}"
%{ endfor ~}
    write-kubeconfig-mode: "0644"
    disable:
      - servicelb
    disable-cloud-controller: true
    EOF
  - mkdir -p /var/lib/rancher/k3s/agent/pod-manifests
  - |
    IFACE=$(ip route get ${kube_vip_ip} | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -1)
    cat > /var/lib/rancher/k3s/agent/pod-manifests/kube-vip.yaml << KVEOF
    apiVersion: v1
    kind: Pod
    metadata:
      name: kube-vip
      namespace: kube-system
    spec:
      containers:
        - name: kube-vip
          image: ghcr.io/kube-vip/kube-vip:${kube_vip_version}
          imagePullPolicy: IfNotPresent
          args:
            - manager
          env:
            - name: vip_arp
              value: "true"
            - name: port
              value: "6443"
            - name: vip_interface
              value: "$IFACE"
            - name: vip_cidr
              value: "32"
            - name: cp_enable
              value: "true"
            - name: cp_namespace
              value: kube-system
            - name: vip_ddns
              value: "false"
            - name: address
              value: "${kube_vip_ip}"
          securityContext:
            capabilities:
              add:
                - NET_ADMIN
                - NET_RAW
          volumeMounts:
            - mountPath: /etc/kubernetes/admin.conf
              name: kubeconfig
      hostAliases:
        - ip: 127.0.0.1
          hostnames:
            - kubernetes
      hostNetwork: true
      volumes:
        - name: kubeconfig
          hostPath:
            path: /etc/rancher/k3s/k3s.yaml
            type: FileOrCreate
    KVEOF
  - curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${k3s_version}" sh -
  - systemctl start qemu-guest-agent
