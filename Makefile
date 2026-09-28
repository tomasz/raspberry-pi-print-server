.RECIPEPREFIX = >
ANSIBLE_DIR := ansible

.PHONY: deps ping plan apply image

deps:   ## Install Ansible collections
> cd $(ANSIBLE_DIR) && ansible-galaxy collection install -r requirements.yml

ping:   ## Check SSH connectivity to the Pi
> cd $(ANSIBLE_DIR) && ansible printsrv -m ping

plan:   ## Dry run: show what would change
> cd $(ANSIBLE_DIR) && ansible-playbook site.yml --check --diff

apply:  ## Converge the Pi to the declared state
> cd $(ANSIBLE_DIR) && ansible-playbook site.yml --diff

image:  ## Build a ready-to-flash SD card image: build/printsrv.img (needs Docker, Apple Silicon)
> mkdir -p build
> docker run --rm --privileged --platform linux/arm64 \
>   -v "$(CURDIR)":/src:ro -v "$(CURDIR)/build":/build \
>   debian:trixie bash /src/image/build.sh
