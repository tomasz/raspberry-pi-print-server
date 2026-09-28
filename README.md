# raspberry-pi-print-server

Declarative AirPrint print server for a USB-connected HP LaserJet Pro P1102w on a Raspberry Pi 3 A+.

- **Bootstrap (cloud-init):** hostname, user, SSH key, Wi-Fi. Applied once on first boot.
- **Configuration (Ansible):** CUPS + Avahi (AirPrint), open-source `foo2zjs` driver, LAN-only firewall, SSH hardening, automatic security updates. Idempotent; re-run anytime.

## Prerequisites (on your Mac)

```bash
brew install ansible             # only for `make apply` later; not needed to build the image
ssh-keygen -t ed25519            # skip if ~/.ssh/id_ed25519.pub exists
```

Fill in the two bootstrap files. They are git-ignored.

```bash
cp bootstrap/user-data.example bootstrap/user-data              # paste your key: cat ~/.ssh/id_ed25519.pub
cp bootstrap/network-config.example bootstrap/network-config    # Wi-Fi SSID and password
```

## 1. Build and flash the image

```bash
make image    # ~5 min; needs Docker on Apple Silicon
```

1. Raspberry Pi Imager → Device **Raspberry Pi 3** → OS **Use custom** → `build/printsrv.img` → your SD card.
2. When asked about OS customisation, choose **No**. Your settings are already in the image.
3. Insert into the Pi, plug in the printer, power on.

First boot configures everything by itself (a few minutes). If the printer is off or unplugged, it retries every 5 minutes and also as soon as the printer is plugged in. Check progress with `ssh printsrv.local journalctl -fu printsrv-firstboot`.

`build/printsrv.img` contains your Wi-Fi password: don't share it.

<details>
<summary>Without the image (stock Raspberry Pi OS)</summary>

1. Raspberry Pi Imager → **Raspberry Pi OS Lite (64-bit)** (Trixie), OS customisation **No**.
2. Copy `bootstrap/user-data` and `bootstrap/network-config` onto the card's `bootfs` volume, replacing the ones there.
3. Boot the Pi, wait 2–5 minutes, then `make deps` (once) and `make apply`.

</details>

## 2. Change settings later

```bash
make deps     # once
make ping     # SSH reachable?
make plan     # dry run, shows diffs
make apply    # configure everything
```

Edit `ansible/group_vars/all.yml` (LAN range, printer name, print defaults) and `make apply` again for any change.

### Print defaults

Set in `printer_options`: A4, print density 5 (darkest), quality `normal` (1200×600 dpi, the driver's maximum). All choices: `ssh printsrv.local lpoptions -p LaserJet -l`.

Not available with this driver:

- **Jam recovery:** the driver turns it off in every job; reprinting jammed pages needs HP's Windows driver.
- **Auto-Off:** stored in the printer, not the queue. Set it once from a Windows PC with HP's driver (Printer properties → Device Settings).
- **Double-sided:** the printer has no duplexer. On a Mac: Print → Paper Handling → **Odd Only**, flip the stack, then **Even Only**. Test with a 4-page document first; if the backs come out in the wrong order, also set Page Order → **Reverse** for the second pass.

## 3. Use it

- **iPhone/iPad:** Share → Print → `LaserJet`.
- **Mac:** System Settings → Printers & Scanners → Add → `LaserJet` → Use: **AirPrint**.
- **Windows:** Add printer → by address `http://printsrv.local:631/printers/LaserJet`, driver **Microsoft IPP Class Driver**.
- **Status page (read-only):** `http://printsrv.local:631`.

## Router

- Give the Pi a **DHCP reservation**.
- No port forwarding and UPnP off. The Pi needs **outbound** internet for security updates; don't block it the way you would the printer.
