output "master_ips" {
  description = "IP addresses of master nodes"
  value       = { for k, v in var.masters : k => v.ip }
}

output "worker_ips" {
  description = "IP addresses of worker nodes"
  value       = { for k, v in var.workers : k => v.ip }
}

output "api_server" {
  description = "Kubernetes API server address (kube-vip VIP)"
  value       = "https://192.168.100.100:6443"
}

output "kubeconfig" {
  description = "Export kubeconfig fetched by Ansible"
  value       = "export KUBECONFIG=~/.kube/k3s-config"
}

output "argocd_hosts_entry" {
  description = "Add this line to /etc/hosts for ArgoCD access"
  value       = "192.168.100.200  argocd.local"
}

output "argocd_url" {
  description = "ArgoCD UI address"
  value       = "https://argocd.local"
}

output "argocd_password" {
  description = "Retrieve the initial ArgoCD admin password"
  value       = "kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d"
}
