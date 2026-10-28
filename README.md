# raspberry-pi-print-server

Declarative AirPrint print server for a USB-connected HP LaserJet Pro P1102w on a Raspberry Pi 3B+ powered over Ethernet (PoE).

- **Bootstrap (cloud-init):** hostname, user, SSH key, wired network. Applied once on first boot.
- **Configuration (Ansible):** CUPS + Avahi (AirPrint), open-source `foo2zjs` driver, LAN-only firewall, SSH hardening, automatic security updates, hardware watchdog, persistent logs. Idempotent; re-run anytime.

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

Fill in the two bootstrap files and commit them: they hold only your SSH public key and a DHCP setting, and with them in git this repository is everything needed to rebuild the Pi. (Add them to `.gitignore` instead if you intend to publish this repository as a template.)

```bash
cp bootstrap/user-data.example bootstrap/user-data              # paste your key: cat ~/.ssh/id_ed25519.pub
cp bootstrap/network-config.example bootstrap/network-config    # wired DHCP; edit only for a static IP
```

The user in `bootstrap/user-data` must match `admin_user` in `ansible/group_vars/all.yml`; `make image` refuses to build otherwise, because sshd will only admit that user.

## 1. Build and flash the image

```bash
make image    # ~5 min; needs Docker. Native on Apple Silicon; on x86 first run:
              #   docker run --privileged --rm tonistiigi/binfmt --install arm64
```

1. Raspberry Pi Imager → Device **Raspberry Pi 3** → OS **Use custom** → `build/printsrv.img` → your SD card.
2. When asked about OS customisation, choose **No**. Your settings are already in the image.
3. Insert into the Pi, plug in the printer, connect the PoE cable.
4. `make forget` so your Mac accepts the Pi's new SSH host key (needed after every reflash).

First boot configures everything by itself (a few minutes). If the printer is off or unplugged, it retries every 5 minutes and also as soon as the printer is plugged in. Check progress with `ssh printsrv.local journalctl -fu printsrv-firstboot`.

`build/printsrv.img` contains your SSH public key and settings, no secrets.

`make image-lock` records the exact Raspberry Pi OS release and checksum in `image/base-image.lock`; commit it so every `make image` builds from the same base. Without the lock, `make image` warns and uses the newest release. Re-run `make image-lock` when you decide to move to a newer release.

<details>
<summary>Without the image (stock Raspberry Pi OS)</summary>

1. Raspberry Pi Imager → **Raspberry Pi OS Lite (64-bit)** (Trixie), OS customisation **No**.
2. Copy `bootstrap/user-data` and `bootstrap/network-config` onto the card's `bootfs` volume, replacing the ones there.
3. Boot the Pi, wait 2–5 minutes, then `make deps` (once) and `make apply`. The first run reboots the Pi once to apply the boot configuration.

</details>

## 2. Change settings later

```bash
make deps     # once
make ping     # SSH reachable?
make plan     # dry run, shows diffs
make apply    # configure everything
```

Edit `ansible/group_vars/all.yml` (LAN range, printer name, driver, print defaults) and `make apply` again for any change. `make apply` does not upgrade packages; unattended-upgrades does that nightly. `make upgrade` upgrades everything right now.

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

## 4. When something is wrong

Work down the list. Everything up to `make reboot` works from anywhere on the LAN; `make help` lists all targets.

| Command         | What it does                                                                 |
|-----------------|------------------------------------------------------------------------------|
| `make status`   | Queue state, pending jobs, services, firewall, CPU temperature, uptime.       |
| `make logs`     | Last 100 lines from CUPS, first boot and automatic updates.                   |
| `make unjam`    | Cancels every job and re-enables the queue. Use after clearing a paper jam if the job that jammed should not be reprinted. |
| `make testpage` | Prints the CUPS test page.                                                    |
| `make usb-cycle`| Power-cycles the Pi's USB ports to reset the printer's USB link. **Test this once while standing next to the Pi:** on the 3B+ the Ethernet port shares the same USB hub chip, so confirm the network link survives before relying on it remotely. |
| `make reboot`   | Reboots the Pi and waits for it to come back.                                 |

What the Pi already does on its own:

- **A failed print job retries instead of pausing the queue.** CUPS's default would disable the queue after one USB hiccup and show "Printer paused" on every device until someone intervened. Here a job retries every minute, up to ten times, then only that job is aborted.
- **A hung kernel reboots itself** via the hardware watchdog within about 15 seconds.
- **Security updates install nightly.** The Pi reboots at 04:00 only when a kernel or libc update requires it; `make logs` shows when that happened.
- **Logs survive reboots**, capped at 64 MB so they can never fill the card.

Beyond software:

1. **Paper jam:** clear it. The queue resumes on its own; `make unjam` if the jammed job should be discarded.
2. **Printer unresponsive:** `make usb-cycle`. If that does not help, the printer needs a mains power cycle. A smart plug (Shelly, Tasmota) makes that possible remotely and can also schedule the printer off overnight, which this driver cannot do.
3. **Pi unreachable:** with a managed PoE switch, toggle the port to power-cycle the Pi from anywhere. Otherwise unplug and replug the Ethernet cable.
4. **Starting over:** `make image`, flash, `make forget`. Everything the Pi needs is in this repository and your two bootstrap files.

If your Mac is not at hand, the Pi carries a copy of the playbook from the image build: `ssh printsrv.local sudo ansible-playbook /opt/printsrv/ansible/site.yml -i printsrv, -c local`. It reflects the repository as of the last `make image`, not later `make apply` runs.

## Router

- Give the Pi a **DHCP reservation**.
- No port forwarding and UPnP off. The Pi needs **outbound** internet for security updates; don't block it the way you would the printer.
