#!/usr/bin/env bash
# Builds build/printsrv.img: Raspberry Pi OS Lite + packages + playbook + your bootstrap files.
# Runs inside a privileged linux/arm64 Debian container (see `make image`); arm64 on Apple
# Silicon is native, so the chroot needs no emulation.
set -euo pipefail

SRC=/src
OUT=/build
ROOT=/mnt/root
IMG="$OUT/printsrv.img"
PIOS_URL="${PIOS_URL:-https://downloads.raspberrypi.com/raspios_lite_arm64_latest}"
GROW_ROOT_MB="${GROW_ROOT_MB:-1536}"

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ---------- Inputs ----------
for f in user-data network-config; do
  [[ -f "$SRC/bootstrap/$f" ]] || die "bootstrap/$f missing. Copy it from bootstrap/$f.example and fill it in."
done
grep -q AAAA_REPLACE "$SRC/bootstrap/user-data" && die "bootstrap/user-data still has the placeholder SSH key."

# Lockout guards: sshd will only accept admin_user, and the firewall only lan_cidr. Neither can be
# fixed remotely if wrong, so refuse to build an image that would strand you.
yaml_scalar() { awk -v k="$2" '$1 == k":" { sub(/[[:space:]]*#.*$/, ""); print $2; exit }' "$1"; }
admin=$(yaml_scalar "$SRC/ansible/group_vars/all.yml" admin_user)
grep -Eq "^[[:space:]]*-[[:space:]]*name:[[:space:]]*${admin}([[:space:]]|$)" "$SRC/bootstrap/user-data" \
  || die "bootstrap/user-data must create user '$admin' (admin_user in ansible/group_vars/all.yml); sshd only admits that user."
lan=$(yaml_scalar "$SRC/ansible/group_vars/all.yml" lan_cidr)
[[ "$lan" =~ ^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)[0-9.]+/[0-9]+$ ]] \
  || die "lan_cidr '$lan' is not a private (RFC 1918) range; the firewall would lock you out."

log "Installing build tools"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends ca-certificates curl xz-utils fdisk e2fsprogs >/dev/null

# ---------- Base image (cached in build/cache, checksum-verified) ----------
mkdir -p "$OUT/cache"
url=$(curl -fsSIL -o /dev/null -w '%{url_effective}' "$PIOS_URL")
base="$OUT/cache/$(basename "$url")"
if [[ ! -f "$base" ]]; then
  log "Downloading $(basename "$url")"
  curl -fL --progress-bar -o "$base.part" "$url"
  mv "$base.part" "$base"
fi
expected=$(curl -fsSL "$url.sha256" | awk '{print $1}')
echo "$expected  $base" | sha256sum -c --quiet || { rm -f "$base"; die "Checksum mismatch; deleted $base, re-run."; }

log "Unpacking and growing the root partition by ${GROW_ROOT_MB} MB"
xz -dc "$base" > "$IMG"
truncate -s "+${GROW_ROOT_MB}M" "$IMG"
echo ", +" | sfdisk -q -N 2 "$IMG"

part() {  # prints "<offset bytes> <size bytes>" of partition $1
  sfdisk -d "$IMG" | awk -F'[=,]' -v p="$IMG$1 " 'index($0, p) == 1 { print $2 * 512, $4 * 512 }'
}

# ---------- Mount ----------
cleanup() {
  set +e
  for m in dev/pts dev proc sys boot/firmware ""; do mountpoint -q "$ROOT/$m" && umount "$ROOT/$m"; done
  [[ -n "${BOOT_LOOP:-}" ]] && losetup -d "$BOOT_LOOP"
  [[ -n "${ROOT_LOOP:-}" ]] && losetup -d "$ROOT_LOOP"
}
trap cleanup EXIT

read -r off size < <(part 2)
ROOT_LOOP=$(losetup -f --show -o "$off" --sizelimit "$size" "$IMG")
e2fsck -pf "$ROOT_LOOP" >/dev/null
resize2fs "$ROOT_LOOP" >/dev/null
read -r off size < <(part 1)
BOOT_LOOP=$(losetup -f --show -o "$off" --sizelimit "$size" "$IMG")

mkdir -p "$ROOT"
mount "$ROOT_LOOP" "$ROOT"
mount "$BOOT_LOOP" "$ROOT/boot/firmware"
mount --bind /dev "$ROOT/dev"
mount --bind /dev/pts "$ROOT/dev/pts"
mount -t proc proc "$ROOT/proc"
mount -t sysfs sys "$ROOT/sys"

in_root() { chroot "$ROOT" env DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8 "$@"; }

# ---------- Bootstrap files (what you'd otherwise copy to bootfs by hand) ----------
log "Writing bootstrap files to bootfs"
cp "$SRC/bootstrap/user-data" "$SRC/bootstrap/network-config" "$ROOT/boot/firmware/"

# ---------- Packages ----------
log "Installing Ansible, the playbook's packages and boot config"
mv "$ROOT/etc/resolv.conf" "$ROOT/etc/resolv.conf.orig" 2>/dev/null || true
cp /etc/resolv.conf "$ROOT/etc/resolv.conf"
printf '#!/bin/sh\nexit 101\n' > "$ROOT/usr/sbin/policy-rc.d"   # no service starts inside the chroot
chmod +x "$ROOT/usr/sbin/policy-rc.d"

in_root apt-get update -qq
in_root apt-get install -y -qq --no-install-recommends ansible-core python3-apt >/dev/null
rm -rf "$ROOT/opt/printsrv"
mkdir -p "$ROOT/opt/printsrv"
cp -r "$SRC/ansible" "$ROOT/opt/printsrv/ansible"
rm -rf "$ROOT/opt/printsrv/ansible/.ansible"
in_root ansible-galaxy collection install -r /opt/printsrv/ansible/requirements.yml -p /usr/share/ansible/collections
in_root sh -c 'cd /opt/printsrv/ansible && ansible-playbook site.yml -i printsrv, -c local -e ansible_become=false --tags packages,bootconfig -e image_build=true'

# ---------- First-boot converge ----------
log "Enabling first-boot configuration"
install -m 0644 "$SRC/image/printsrv-firstboot.service" "$ROOT/etc/systemd/system/"
install -m 0644 "$SRC/image/90-printsrv-firstboot.rules" "$ROOT/etc/udev/rules.d/"
in_root systemctl enable printsrv-firstboot.service

# ---------- Clean up ----------
log "Cleaning up"
in_root apt-get clean
rm -rf "$ROOT/usr/sbin/policy-rc.d" "$ROOT/root/.ansible" "$ROOT/opt/printsrv/ansible/.ansible"
rm -f "$ROOT/etc/resolv.conf"
mv "$ROOT/etc/resolv.conf.orig" "$ROOT/etc/resolv.conf" 2>/dev/null || true
cleanup
trap - EXIT

log "Done: build/printsrv.img ($(du -h "$IMG" | cut -f1)). It contains your SSH public key and settings; no secrets."
