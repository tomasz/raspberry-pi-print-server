# raspberry-pi-print-server

Declarative AirPrint print server for a USB-connected HP LaserJet Pro P1102w on a Raspberry Pi 3B+ powered over Ethernet (PoE).

- **Bootstrap (cloud-init):** hostname, user, SSH key, wired network. Applied once on first boot.
- **Configuration (Ansible):** CUPS + Avahi (AirPrint), open-source `foo2zjs` driver, automatic security updates, and a hardened baseline (see [Security defaults](#security-defaults)). Idempotent; re-run anytime.

## Hardware

- Raspberry Pi 3B+ with the official **Raspberry Pi PoE+ HAT** (fits the 40-pin header and the 4-pin PoE header).
- An **802.3af/at** PoE injector or PoE switch port. Not passive PoE.
- One Ethernet cable from the injector to the Pi; no USB power supply (never both).
- microSD card, 16 GB or larger, and the printer's USB cable.

Wi-Fi and Bluetooth are switched off; the PoE+ HAT fan only spins up above 65 °C.

## Prerequisites (on your Mac)

```bash
brew install ansible             # only for `make apply` later; not needed to build the image
ssh-keygen -t ed25519            # skip if ~/.ssh/id_ed25519.pub exists
```

Fill in the two bootstrap files. They are git-ignored.

```bash
cp bootstrap/user-data.example bootstrap/user-data              # paste your key: cat ~/.ssh/id_ed25519.pub
cp bootstrap/network-config.example bootstrap/network-config    # wired DHCP; edit only for a static IP
```

## 1. Build and flash the image

```bash
make image    # ~5 min; needs Docker on Apple Silicon
```

1. Raspberry Pi Imager → Device **Raspberry Pi 3** → OS **Use custom** → `build/printsrv.img` → your SD card.
2. When asked about OS customisation, choose **No**. Your settings are already in the image.
3. Insert into the Pi, plug in the printer, connect the PoE cable.

First boot configures everything by itself (a few minutes). If the printer is off or unplugged, it retries every 5 minutes and also as soon as the printer is plugged in. Check progress with `ssh printsrv.local journalctl -fu printsrv-firstboot`.

`build/printsrv.img` contains your SSH public key and settings, no secrets.

<details>
<summary>Without the image (stock Raspberry Pi OS)</summary>

1. Raspberry Pi Imager → **Raspberry Pi OS Lite (64-bit)** (Trixie), OS customisation **No**.
2. Copy `bootstrap/user-data` and `bootstrap/network-config` onto the card's `bootfs` volume, replacing the ones there.
3. To keep the radios off from the very first boot, also append these two lines to `config.txt` on the same volume (otherwise they switch off after the first `make apply`):
   ```
   dtoverlay=disable-wifi
   dtoverlay=disable-bt
   ```
4. Boot the Pi, wait 2–5 minutes, then `make deps` (once), `make apply` and `make verify`.

</details>

## 2. Change settings later

```bash
make deps     # once
make ping     # SSH reachable?
make plan     # dry run, shows diffs
make apply    # configure everything
make verify   # check the security posture and AirPrint advertisement
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

## Security defaults

The printer has no network connection at all; the Pi is the only way to reach it. The Pi is hardened as follows. `make verify` checks each point on the live device.

| Area | Default | Why |
| --- | --- | --- |
| Inbound firewall | Deny all. Allow SSH (rate-limited), IPP 631/tcp and mDNS 5353/udp from `lan_cidr` only. | Nothing else on the Pi needs to be reachable. |
| Outbound firewall | Deny all except DNS, NTP, HTTP(S), DHCP and mDNS (`egress_policy: restricted`). | Updates keep working, but a compromised print service cannot reach arbitrary hosts or ports. |
| CUPS | Answers only to `<hostname>`, `<hostname>.local` and IP addresses. Printing and the status page from `lan_cidr` only; administration from the Pi only. No copies of documents and no job history kept; jobs capped at 100 MB. | Blocks DNS rebinding from malicious web pages and leaves nothing to leak from the SD card. |
| `cups-browsed` | Masked. | It auto-adds remote printers, which a print server never needs, and it was the entry point of the 2024 CUPS remote code execution chain (CVE-2024-47176). |
| SSH | Public key only, one user, no root, no forwarding or tunnels, 3 attempts, 20 s login grace. | Key-only access with nothing to pivot through. |
| Kernel | No forwarding or ICMP redirects, reverse-path filtering, restricted `dmesg` and kernel pointers, unprivileged BPF off, protected links and FIFOs. | Standard network and memory hardening for an appliance. |
| IPv6 | Off (`ipv6_enabled: false`). | The LAN rules, Bonjour and CUPS access are IPv4-only. |
| Radios | Wi-Fi and Bluetooth off in firmware; Bluetooth packages removed; related services masked. | Wired-only device. |
| Packages | Print stack installed without Recommends; Raspberry Pi Connect, ModemManager and triggerhappy removed. | Less code running, no cloud remote-access relay. |
| Bonjour | Wired interface only; advertises the printer and nothing else (no SSH/SFTP, no hardware fingerprint). | Minimal discovery footprint. |
| cloud-init | Disabled after the first configuration. | Files on the SD card's boot partition cannot reconfigure the Pi later. |
| Updates | Debian, Debian Security and Raspberry Pi kernel/firmware updates install nightly; reboot at 04:00 when needed. | Stays patched without attention. |

### Adjusting the defaults

All switches live in `ansible/group_vars/all.yml`:

- **Printing by another name** (for example `printsrv.lan` from your router's DNS) fails with *400 Bad Request*. Add the name to `cups_extra_server_aliases`.
- **Debugging network access** from the Pi: set `egress_policy: open`, `make apply`, and set it back when done.
- **IPv6:** `ipv6_enabled: true` turns the address family back on, but the firewall allow rules, CUPS access and Bonjour stay IPv4-only until you extend them.

### Deliberately not included

- **fail2ban:** SSH is key-only, LAN-only and rate-limited; there are no passwords to guess.
- **Encrypted IPP:** AirPrint clients on a home LAN print over plain IPP. If that matters, put the Pi and the printing clients on their own VLAN.
- **Pruning unknown SSH keys:** the first-boot configuration runs on the Pi itself, where your Mac's public key is not available, so enforcing an exclusive key list there could lock you out.

## Driver lifecycle (CUPS 3)

CUPS has flagged classic printer drivers such as foo2zjs as deprecated since version 2.3, and `lpadmin` prints a warning about it. CUPS 3.0 will remove them in favour of driverless IPP printers and "Printer Applications". Debian 13 ships CUPS 2.4 and CUPS 3 is still in alpha, so the current setup keeps working for years. Clients already print to the Pi driverlessly (AirPrint/IPP Everywhere), so when the back end changes they will not notice. OpenPrinting's replacement for foo2zjs is the `ghostscript-printer-app`, which wraps the same foo2zjs code; switch to it once it is packaged in Debian or CUPS 3 reaches Debian stable.

## Router

- Give the Pi a **DHCP reservation**.
- No port forwarding and UPnP off. The Pi makes only DNS, NTP and HTTP(S) update connections outbound; leave those open on the router.
