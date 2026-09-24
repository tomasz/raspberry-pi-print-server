# raspberry-pi-print-server

Declarative AirPrint print server for a USB-connected HP LaserJet Pro P1102w on a Raspberry Pi 3 A+.

- **Bootstrap (cloud-init):** hostname, user, SSH key, Wi-Fi. Applied once on first boot.
- **Configuration (Ansible):** CUPS + Avahi (AirPrint), open-source `foo2xqx` driver, LAN-only firewall, SSH hardening, automatic security updates. Idempotent; re-run anytime.

## Prerequisites (on your Mac)

```bash
brew install ansible
ssh-keygen -t ed25519            # skip if ~/.ssh/id_ed25519.pub exists
```

## 1. Flash the SD card

1. Raspberry Pi Imager → Device **Raspberry Pi 3** → OS **Raspberry Pi OS Lite (64-bit)** (Trixie) → your SD card.
2. When asked about OS customisation, choose **No**. The files below replace it.
3. Re-insert the card. Open the `bootfs` volume and overwrite:
   - `user-data`: from `bootstrap/user-data.example`, with your public key (`cat ~/.ssh/id_ed25519.pub`).
   - `network-config`: from `bootstrap/network-config.example`, with your Wi-Fi SSID and password.

   Tip: `cp bootstrap/user-data.example bootstrap/user-data` (and the same for `network-config`) to keep filled-in copies locally. They are git-ignored.
4. Eject, insert into the Pi, plug the printer into the Pi's USB port, power on. First boot takes 2–5 minutes.

## 2. Converge

```bash
make deps     # once
make ping     # SSH reachable?
make plan     # dry run, shows diffs
make apply    # configure everything
```

Edit `ansible/group_vars/all.yml` (LAN range, printer name, paper size) and `make apply` again for any change.

## 3. Use it

- **iPhone/iPad:** Share → Print → `LaserJet`.
- **Mac:** System Settings → Printers & Scanners → Add → `LaserJet` → Use: **AirPrint**.
- **Windows:** Add printer → by address `http://printsrv.local:631/printers/LaserJet`, driver **Microsoft IPP Class Driver**.
- **Status page (read-only):** `http://printsrv.local:631`.

## Router

- Give the Pi a **DHCP reservation**.
- No port forwarding and UPnP off. The Pi needs **outbound** internet for security updates; don't block it the way you would the printer.
