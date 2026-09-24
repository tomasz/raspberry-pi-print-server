.RECIPEPREFIX = >
ANSIBLE_DIR := ansible

.PHONY: deps ping plan apply

deps:   ## Install Ansible collections
> cd $(ANSIBLE_DIR) && ansible-galaxy collection install -r requirements.yml

ping:   ## Check SSH connectivity to the Pi
> cd $(ANSIBLE_DIR) && ansible printsrv -m ping

plan:   ## Dry run: show what would change
> cd $(ANSIBLE_DIR) && ansible-playbook site.yml --check --diff

apply:  ## Converge the Pi to the declared state
> cd $(ANSIBLE_DIR) && ansible-playbook site.yml --diff
