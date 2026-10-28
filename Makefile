.RECIPEPREFIX = >
ANSIBLE_DIR := ansible
HOST        ?= $(shell awk '$$1 == "ansible_host:" {print $$2}' $(ANSIBLE_DIR)/inventory.yml)
# Base image. Release URLs are immutable, so a dated URL pins the build; `_latest` floats.
# Pattern: https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-<DATE>/<DATE>-raspios-trixie-arm64-lite.img.xz
PIOS_URL    ?= https://downloads.raspberrypi.com/raspios_lite_arm64_latest
# Build container. Pin by digest for a fully reproducible build, e.g. BUILD_IMAGE=debian@sha256:...
BUILD_IMAGE ?= debian:trixie

.PHONY: help deps ping plan apply upgrade status logs unjam testpage usb-cycle reboot forget image lint

help:   ## List targets
> @awk -F':.*## ' '/^[a-z-]+:.*## / {printf "  make %-10s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# ---------- Configure ----------
deps:   ## Install Ansible collections (once)
> cd $(ANSIBLE_DIR) && ansible-galaxy collection install -r requirements.yml

ping:   ## Check SSH connectivity to the Pi
> cd $(ANSIBLE_DIR) && ansible printsrv -m ping

plan:   ## Dry run: show what would change
> cd $(ANSIBLE_DIR) && ansible-playbook site.yml --check --diff

apply:  ## Converge the Pi to the declared state
> cd $(ANSIBLE_DIR) && ansible-playbook site.yml --diff

upgrade: ## Upgrade all packages now (unattended-upgrades does this nightly anyway)
> cd $(ANSIBLE_DIR) && ansible-playbook site.yml --tags upgrade --diff

# ---------- Operate ----------
status: ## Queue, jobs, services, firewall, temperature, uptime
> cd $(ANSIBLE_DIR) && ansible printsrv -b -m shell -a 'lpstat -t; echo; echo "services: $$(systemctl is-active cups avahi-daemon | paste -sd,)"; ufw status | head -1; echo "cpu $$(( $$(cat /sys/class/thermal/thermal_zone0/temp) / 1000 )) C"; uptime'

logs:   ## Last 100 lines from CUPS, first boot and automatic updates
> cd $(ANSIBLE_DIR) && ansible printsrv -b -m shell -a 'journalctl -u cups -u printsrv-firstboot -u apt-daily-upgrade -n 100 --no-pager'

unjam:  ## Cancel every job and re-enable the queue
> cd $(ANSIBLE_DIR) && ansible printsrv -b -m shell -a 'cancel -a {{ printer_name }}; cupsenable {{ printer_name }}; cupsaccept {{ printer_name }}; lpstat -p {{ printer_name }}'

testpage: ## Print the CUPS test page
> cd $(ANSIBLE_DIR) && ansible printsrv -b -m shell -a 'lp -d {{ printer_name }} /usr/share/cups/data/testprint'

usb-cycle: ## Power-cycle the Pi's USB ports (resets the printer's USB link; see README before using remotely)
> cd $(ANSIBLE_DIR) && ansible printsrv -b -m shell -a 'uhubctl -l 1-1 -a cycle'

reboot: ## Reboot the Pi and wait for it to come back
> cd $(ANSIBLE_DIR) && ansible printsrv -b -m reboot

forget: ## Forget the Pi's SSH host key (after every reflash)
> ssh-keygen -R $(HOST)

# ---------- Build ----------
image:  ## Build a ready-to-flash SD card image: build/printsrv.img (needs Docker)
> mkdir -p build
> docker run --rm --privileged --platform linux/arm64 \
>   -v "$(CURDIR)":/src:ro -v "$(CURDIR)/build":/build -e PIOS_URL=$(PIOS_URL) \
>   $(BUILD_IMAGE) bash /src/image/build.sh

lint:   ## ansible-lint (includes a syntax check) and shellcheck, same as CI
> cd $(ANSIBLE_DIR) && ansible-lint site.yml
> shellcheck image/build.sh
