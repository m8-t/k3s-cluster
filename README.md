# k3s Cluster

A local k3s cluster running on KVM/libvirt VMs, provisioned with OpenTofu and configured with Ansible.

> This project was developed with the assistance of [Claude Code](https://claude.ai/code) (Anthropic). All architecture decisions, configuration, and code were reviewed and validated by the author.

## Architecture

```text
                        Host Machine (KVM/libvirt)
                        NAT Network: 192.168.100.0/24
┌───────────────────────────────────────────────────────────────┐
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │                  Control Plane (HA)                     │  │
│  │                                                         │  │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐        │  │
│  │  │ k3s-master-1│ │ k3s-master-2│ │ k3s-master-3│        │  │
│  │  │ .11         │ │ .12         │ │ .13         │        │  │
│  │  │ etcd        │ │ etcd        │ │ etcd        │        │  │
│  │  │ API server  │ │ API server  │ │ API server  │        │  │
│  │  │ kube-vip    │ │ kube-vip    │ │ kube-vip    │        │  │
│  │  └─────────────┘ └─────────────┘ └─────────────┘        │  │
│  │          │               │               │              │  │
│  │          └───────────────┴───────────────┘              │  │
│  │                    kube-vip VIP                         │  │
│  │               192.168.100.100:6443                      │  │
│  └─────────────────────────────────────────────────────────┘  │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │                      Workers                            │  │
│  │                                                         │  │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐        │  │
│  │  │ k3s-worker-1│ │ k3s-worker-2│ │ k3s-worker-3│        │  │
│  │  │ .21         │ │ .22         │ │ .23         │        │  │
│  │  └─────────────┘ └─────────────┘ └─────────────┘        │  │
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

### Ansible collections and dependencies

```bash
# Arch Linux
sudo pacman -S python-kubernetes

# Other distros
pip install kubernetes

cd ansible
ansible-galaxy collection install -r requirements.yml
```

## Deployment

### 1. Configure and apply

Set your SSH public key in `terraform.tfvars`:

```bash
cd tofu
echo 'ssh_public_key = "ssh-ed25519 AAAA... your-comment"' > terraform.tfvars
```

Generate a cluster token and export it so OpenTofu can read it, then initialise and apply:

```bash
tofu init
make deploy
```

`make deploy` generates a fresh token automatically and passes it to tofu inline.

This single command does everything:

1. Downloads the openSUSE MicroOS base image and creates the libvirt network
2. Provisions all 6 VMs -- cloud-init installs k3s, configures kube-vip, and joins nodes
3. Runs `ansible-playbook site.yml` -- waits for the cluster to be Ready and fetches kubeconfig
4. Runs `ansible-playbook addons.yml` -- deploys cert-manager, MetalLB, Traefik, and ArgoCD

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

After setting a permanent password, delete the initial secret:

```bash
kubectl delete secret argocd-initial-admin-secret -n argocd
```

Open `https://argocd.local` in your browser. You will get a certificate warning because the CA is self-signed. Log in with username `admin` and the password retrieved above.

## Configuration

### Cluster token

`make deploy` generates a fresh token automatically via `openssl rand -hex 32` and passes it inline to tofu. The token is never stored in version control or on disk.

### Versions

Versions are defined in two places:

- `tofu/variables.tf` -- k3s version (`k3s_version`) and kube-vip version (`kube_vip_version`)
- `ansible/roles/addons/defaults/main.yml` -- cert-manager, ArgoCD, and MetalLB chart versions; MetalLB IP pool; ArgoCD IP

### VM sizing

Node counts, IPs, CPU, and memory are all defined in `tofu/variables.tf`. Override any value in `tofu/terraform.tfvars` without editing the variable definitions.

## Day 2 operations

### Makefile targets

| Target | What it does |
|--------|-------------|
| `make deploy` | Full one-shot deploy — runs `tofu apply` which triggers Ansible automatically |
| `make addons` | Re-run only `addons.yml` — useful after changing addon templates or config without re-deploying VMs |
| `make cluster` | Re-run only `site.yml` — re-fetches kubeconfig from init master |
| `make destroy` | Tear down all VMs and infrastructure |

### Tear down and redeploy

```bash
make destroy
make deploy
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
ssh -i ~/.ssh/id_ed25519 opensuse@192.168.100.11
```

### Upgrades

Two independent upgrade paths are managed by [system-upgrade-controller](https://github.com/rancher/system-upgrade-controller), which is deployed automatically on first boot via cloud-init.

#### k3s (automatic)

Two SUC plans (`server-plan`, `agent-plan`) track the k3s `latest` release channel. Masters are upgraded one at a time; workers wait for all masters to finish.

No manual action required -- SUC will roll out new k3s versions automatically as they are published.

#### MicroOS OS packages (manual trigger)

Two SUC plans (`microos-server`, `microos-agent`) run `transactional-update --continue cleanup dup` on each node and reboot if needed. Workers wait for all masters to finish.

These plans do **not** trigger automatically. Annotate all nodes when you want to roll out OS updates:

```bash
kubectl annotate node \
  k3s-master-1 k3s-master-2 k3s-master-3 \
  k3s-worker-1 k3s-worker-2 k3s-worker-3 \
  plan.upgrade.cattle.io/microos=microos
```

SUC will drain each node, run the update, reboot if needed, and uncordon before moving to the next.

### Issuing certificates for other services

Use the `ca-issuer` ClusterIssuer in your Ingress annotations:

```yaml
annotations:
  cert-manager.io/cluster-issuer: "ca-issuer"
```

## Notes

- The cluster token is generated fresh on each `make deploy` and passed inline to tofu. It is never written to disk on the host or committed to version control.
- Nodes run openSUSE MicroOS (immutable root filesystem). OS-level updates are handled via `transactional-update`; k3s upgrades are managed by system-upgrade-controller.
- The self-signed CA certificate is valid for 10 years. Import `k3s-ca-secret` from the `cert-manager` namespace into your system trust store to avoid browser warnings.
