# k3s Cluster

A local k3s cluster running on KVM/libvirt VMs, provisioned with OpenTofu and configured with Ansible.

> This project was developed with the assistance of [Claude Code](https://claude.ai/code) (Anthropic). All architecture decisions, configuration, and code were reviewed and validated by the author.

## Architecture

```
                        Host Machine (KVM/libvirt)
                        NAT Network: 192.168.100.0/24
┌───────────────────────────────────────────────────────────────┐
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │                  Control Plane (HA)                     │  │
│  │                                                         │  │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐       │  │
│  │  │ k3s-master-1│ │ k3s-master-2│ │ k3s-master-3│       │  │
│  │  │ .11         │ │ .12         │ │ .13         │       │  │
│  │  │ etcd        │ │ etcd        │ │ etcd        │       │  │
│  │  │ API server  │ │ API server  │ │ API server  │       │  │
│  │  │ kube-vip    │ │ kube-vip    │ │ kube-vip    │       │  │
│  │  └─────────────┘ └─────────────┘ └─────────────┘       │  │
│  │          │               │               │              │  │
│  │          └───────────────┴───────────────┘              │  │
│  │                    kube-vip VIP                         │  │
│  │               192.168.100.100:6443                      │  │
│  └─────────────────────────────────────────────────────────┘  │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │                      Workers                            │  │
│  │                                                         │  │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐       │  │
│  │  │ k3s-worker-1│ │ k3s-worker-2│ │ k3s-worker-3│       │  │
│  │  │ .21         │ │ .22         │ │ .23         │       │  │
│  │  └─────────────┘ └─────────────┘ └─────────────┘       │  │
│  └─────────────────────────────────────────────────────────┘  │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │                   Addon Stack                           │  │
│  │                                                         │  │
│  │  MetalLB (L2)          IP pool: 192.168.100.200-220     │  │
│  │  Traefik               LoadBalancer: 192.168.100.200    │  │
│  │  cert-manager          self-signed CA (ca-issuer)       │  │
│  │  ArgoCD                https://argocd.local             │  │
│  └─────────────────────────────────────────────────────────┘  │
│                                                               │
└───────────────────────────────────────────────────────────────┘

Inbound traffic flow:
  Browser → 192.168.100.200 (Traefik) → Ingress → Service → Pod
  kubectl  → 192.168.100.100 (kube-vip VIP) → API server
```

### Components

| Component | Role |
|-----------|------|
| kube-vip | ARP-based VIP for the API server — survives single master failure |
| k3s embedded etcd | Distributed state store across all 3 masters |
| MetalLB (L2 mode) | Assigns real IPs from the NAT subnet to LoadBalancer services |
| Traefik | Ingress controller — single entry point for all HTTP/S traffic |
| cert-manager | Issues TLS certificates from a self-signed internal CA |
| ArgoCD | GitOps continuous delivery |

### Network

| Role | Hostname | IP |
|------|----------|----|
| API server VIP (kube-vip) | — | 192.168.100.100 |
| Ingress (Traefik / MetalLB) | — | 192.168.100.200 |
| Master | k3s-master-1 | 192.168.100.11 |
| Master | k3s-master-2 | 192.168.100.12 |
| Master | k3s-master-3 | 192.168.100.13 |
| Worker | k3s-worker-1 | 192.168.100.21 |
| Worker | k3s-worker-2 | 192.168.100.22 |
| Worker | k3s-worker-3 | 192.168.100.23 |

All VMs are on a NAT network (`192.168.100.0/24`, gateway `192.168.100.1`) managed by libvirt. The MetalLB pool covers `192.168.100.200-220`.

### VM Sizing

| Role | vCPU | RAM | Disk |
|------|------|-----|------|
| Master | 2 | 2 GB | 50 GB thin |
| Worker | 1 | 1.5 GB | 50 GB thin |

Disks are thin-provisioned qcow2 volumes backed by a shared base image.

## Prerequisites

### Host requirements

- libvirt and QEMU/KVM installed and running
- Your user in the `libvirt` group (or run commands with `sudo`)
- At least 16 GB RAM and 6 vCPUs available for VMs

### Tools required

| Tool | Purpose |
|------|---------|
| OpenTofu >= 1.6 | VM provisioning |
| Ansible >= 2.14 | Cluster deployment |
| kubectl | Cluster access |
| virsh | VM management |

### Ansible collections

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
```

## Deployment

### 1. Configure and apply

```bash
cd tofu
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and set your SSH public key:

```hcl
ssh_public_key = "ssh-ed25519 AAAA... your-comment"
```

Then initialise and apply:

```bash
tofu init
tofu apply
```

This single command does everything:

1. Downloads the Debian 13 base image and creates the libvirt network
2. Provisions all 6 VMs with cloud-init (static IPs, SSH key, full apt upgrade)
3. Runs `ansible-playbook site.yml` — deploys k3s HA cluster with kube-vip
4. Runs `ansible-playbook addons.yml` — deploys cert-manager, MetalLB, and ArgoCD

The kubeconfig is written to `~/.kube/k3s-config` pointing at the kube-vip VIP. At the end, `tofu output` shows all access details.

### 2. Access the cluster

```bash
export KUBECONFIG=~/.kube/k3s-config
kubectl get nodes
```

All 6 nodes should be in `Ready` state. The API server is reachable via `192.168.100.100:6443` regardless of which master is the current kube-vip leader.

Add to your shell rc file to make it permanent:

```bash
echo 'export KUBECONFIG=~/.kube/k3s-config' >> ~/.zshrc
```

### 3. Access ArgoCD

Add ArgoCD to your local hosts file:

```bash
echo "192.168.100.200  argocd.local" | sudo tee -a /etc/hosts
```

Retrieve the initial admin password:

```bash
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d
```

Open `https://argocd.local` in your browser. You will get a certificate warning because the CA is self-signed. Log in with username `admin` and the password retrieved above.

## Configuration

### Cluster token

`ansible/group_vars/all.yml` is excluded from version control. Copy the example and set your token:

```bash
cp ansible/group_vars/all.yml.example ansible/group_vars/all.yml
export K3S_TOKEN=$(openssl rand -hex 32)
```

The token is read from the `K3S_TOKEN` environment variable at deploy time.

### Versions

Versions are defined in two places:

- `ansible/group_vars/all.yml` -- k3s version (`k3s_version`)
- `ansible/roles/addons/defaults/main.yml` -- cert-manager, ArgoCD, and MetalLB chart versions; MetalLB IP pool; ArgoCD IP

### VM sizing

Node counts, IPs, CPU, and memory are all defined in `tofu/variables.tf`. Override any value in `tofu/terraform.tfvars` without editing the variable definitions.

## Day 2 operations

### Tear down and redeploy

```bash
cd tofu
tofu destroy
tofu apply
cd ../ansible
ansible-playbook site.yml
ansible-playbook addons.yml
```

### Check VM status

```bash
virsh -c qemu:///system list --all
```

### Start a stopped VM

```bash
virsh -c qemu:///system start k3s-master-1
```

### SSH into a node

```bash
ssh -i ~/.ssh/id_ed25519 debian@192.168.100.11
```

### Issuing certificates for other services

Use the `ca-issuer` ClusterIssuer in your Ingress annotations:

```yaml
annotations:
  cert-manager.io/cluster-issuer: "ca-issuer"
```

## Notes

- The cluster token in `group_vars/all.yml` is shared across all nodes. Treat it as a secret and do not commit it to version control.
- The self-signed CA certificate is valid for 10 years. Import `k3s-ca-secret` from the `cert-manager` namespace into your system trust store to avoid browser warnings.
