#cloud-config
hostname: ${hostname}
fqdn: ${hostname}.local
manage_etc_hosts: true

users:
  - name: opensuse
    gecos: openSUSE User
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: true
    ssh_authorized_keys:
      - ${ssh_public_key}

# bootcmd runs on every boot before write_files/runcmd — ensures
# modules are loaded before any sysctl settings referencing them are applied
bootcmd:
  - systemctl mask health-checker.service || true
  - systemctl daemon-reload
  - systemctl start --no-block cloud-final.service || true
  - modprobe br_netfilter
  - modprobe overlay
  - mkdir -p /var/lib/rancher/k3s/server/manifests

write_files:
  - path: /etc/profile.d/aliases.sh
    content: |
      alias k='kubectl'

  - path: /var/lib/rancher/k3s/server/manifests/upgrade-plans.yaml
    content: |
      apiVersion: upgrade.cattle.io/v1
      kind: Plan
      metadata:
        name: server-plan
        namespace: system-upgrade
      spec:
        concurrency: 1
        cordon: true
        nodeSelector:
          matchExpressions:
            - key: node-role.kubernetes.io/control-plane
              operator: Exists
        serviceAccountName: system-upgrade
        upgrade:
          image: rancher/k3s-upgrade
        channel: https://update.k3s.io/v1-release/channels/latest
      ---
      apiVersion: upgrade.cattle.io/v1
      kind: Plan
      metadata:
        name: agent-plan
        namespace: system-upgrade
      spec:
        concurrency: 1
        cordon: true
        nodeSelector:
          matchExpressions:
            - key: node-role.kubernetes.io/worker
              operator: Exists
        prepare:
          image: rancher/k3s-upgrade
          args:
            - prepare
            - server-plan
        serviceAccountName: system-upgrade
        upgrade:
          image: rancher/k3s-upgrade
        channel: https://update.k3s.io/v1-release/channels/latest

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
  - sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
  - grub2-mkconfig -o /boot/grub2/grub.cfg
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
    write-kubeconfig-mode: "0600"
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
  - curl -sfL "https://github.com/rancher/system-upgrade-controller/releases/download/${suc_version}/system-upgrade-controller.yaml" -o /var/lib/rancher/k3s/server/manifests/system-upgrade-controller.yaml
  - curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${k3s_version}" INSTALL_K3S_EXEC="--cluster-init --write-kubeconfig-mode=0644" sh -
  - systemctl start k3s || true
