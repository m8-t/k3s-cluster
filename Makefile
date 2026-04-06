.PHONY: deploy infra cluster addons destroy

# Full one-shot deploy (same as tofu apply — null_resource runs Ansible automatically)
deploy:
	TF_VAR_k3s_token=$$(python3 -c "import secrets; print(secrets.token_hex(32))") tofu -chdir=tofu apply -auto-approve

# Re-run only Ansible site.yml (fetch kubeconfig)
cluster:
	cd ansible && ansible-playbook site.yml

# Re-run only addons (useful after template or config changes without re-deploying VMs)
addons:
	cd ansible && ansible-playbook addons.yml

destroy:
	tofu -chdir=tofu destroy -auto-approve
