<p align="center"><img src="docs/logo.png" alt="Ladrok TV" width="420"></p>

# Ladrok TV

Android TV (AOSP 17) for the **Raspberry Pi 5**, based on [raspberry-vanilla](https://github.com/raspberry-vanilla) (KonstaKANG's AOSP device trees), with:

- **First-boot setup**: language, country and time zone, using the TV remote. The country sets the Wi-Fi regulatory domain, so 5 GHz channels work. Nothing is hard-coded to a region.
- **Over-the-air updates (A/B)**: the system updates in the background while you keep watching. A signed package is installed into the inactive slot by `update_engine`, then the TV restarts into it. If the new version doesn't start, the Pi firmware boots the previous one again.
- **A quiet home screen**: [Ladrok Launcher](https://github.com/Kordal/ladrok-start).
  - On the left: a large Continue card for the last thing you watched, then Watch Next and the Channels you pick.
  - On the right: your apps as a phone-style keypad. The digits 1–9 open them.
  - Every release ships the newest Launcher, and Ladrok Store keeps it up to date between system updates.
- **An app store**: [Ladrok Store](https://github.com/Kordal/ladrok-store). A short, curated list of TV apps (such as Nuvio, Stremio, Jellyfin and Tailscale) from their GitHub releases, F-Droid or the vendor's download page. A separate *FOSS apps* screen adds every app from the community list [Awesome Android TV FOSS Apps](https://github.com/Generator/Awesome-Android-TV-FOSS-Apps) that passes the same checks, refreshed daily; those aren't curated or tested here. It is built in as a privileged system app, so it installs and updates apps without prompts. It is the TV's only app updater: it also updates itself and the Launcher. Automatic updates can be switched off in the Store.
- **A phone as the remote**: [Ladrok Remote](https://github.com/Kordal/ladrok-remote) on an Android phone pairs as a Bluetooth keyboard. The TV's HID host only accepts devices it has connected to itself, so a small built-in helper (`LadrokRemoteHelper`) makes that first connection after pairing.
- **/data fills the card**: on first boot, the user data partition grows to the end of the SD card.
- **Hardened**: SELinux enforcing, and everything is signed with this project's own release keys rather than the public AOSP test keys.

This is a hobby project. It is tested on a Pi 5 (8 GB) booting from an SD card into a 1080p TV over HDMI.

## Install

You need an SD card of **32 GB or more**. The image holds two copies of the system (A/B), about 16.5 GB.

1. From the [latest release](../../releases/latest), download `ladrok-tv-<version>-user.img.xz`. Optionally, check it against the `.sha256` file next to it.
2. Write it with [Raspberry Pi Imager](https://www.raspberrypi.com/software/): *Choose OS → Use custom*. Choose **No** when it offers OS customisation. This erases the card.
3. Boot the Pi. Pick your language, country and time zone, then connect to Wi-Fi in Settings.

After that, updates arrive through **Settings → Device Preferences → About → System update**. The TV checks once a day, downloads in the background, and asks before installing and before restarting.

Releases come in two variants:
- **`user`** is for everyone.
- **`userdebug`** is for development: it has root over adb, and on it `setenforce 0` relaxes SELinux until the next restart.

A TV only installs updates of its own variant.

**Upgrading from a release before v20261015.1718:** those used a smaller partition layout (system 3 GB per slot), which an update can't change. Write the new card image instead; this erases the TV's apps and settings.

## How updates work

```
 SD card (GPT)
 p1  bootsel     FAT: only autoboot.txt (which slot the firmware boots)
 p2  rpiboot_a   FAT: kernel, ramdisk, config.txt, cmdline_a/b.txt   ┐ slot A
 p5  system_a    p7 vendor_a       (6 GB + 1 GB per slot: layout 2)  ┘
 p3  rpiboot_b   p6 system_b   p8 vendor_b                             slot B
 p4  misc        slot metadata
 p9  metadata    p10 userdata
```

- The Pi firmware reads `autoboot.txt` on p1. `[all] boot_partition=` names the normal slot. `[tryboot] boot_partition=` names the slot to try once after the one-shot *tryboot* flag is set.
  The same boot files serve both slots. `config.txt` uses `[boot_partition=2|3]` to choose `cmdline_a.txt` or `cmdline_b.txt`, which pass `androidboot.slot_suffix`.
- The boot control HAL (`device/brcm/rpi5/boot_control`) works as follows:
  - `setActiveBootSlot(other)` writes the `[tryboot]` entry and sets the tryboot flag through the VideoCore mailbox.
  - `markBootSuccessful()` runs after a good boot of the new slot and makes that slot the `[all]` default.
  - A crash, a panic (`panic=10`), or a power cut before that point leaves the old slot as the default.
  - `autoboot.txt` has a fixed size of 512 bytes and is rewritten in place, one sector at a time, so the FAT itself never changes.
- **Update packages** are normal AOSP A/B OTA zips (`ota_from_target_files`).
  - They are published as GitHub release assets, together with one `update-<variant>.json` per variant: version, layout, Launcher and Store versions, SHA-256, and the payload offset, size and properties.
  - The updater app (`LadrokUpdater`) reads the file for its own variant, downloads the package and hands the payload to `update_engine`.
  - It refuses a release with a different partition `layout`, because that needs a new card image.
- **Signing**:
  - The device only trusts `device/brcm/rpi5/security/ota.x509.pem`. The stock `otacerts.zip`, which also contains the public AOSP test key, is replaced with a bind mount at boot.
  - Apps and APEX modules are re-signed with release keys by `tools/sign-target-files.sh`.
  - None of the private keys are in this repository.
- **Launcher and Store**:
  - Ladrok Launcher and Ladrok Store are built in their own repositories and included as prebuilt APKs. The Store is a privileged app (`priv-app`), so its installs need no confirmation.
  - `scripts/fetch-prebuilts.sh` downloads the newest release of each at build time. It only accepts APKs signed with their pinned certificate.
  - Between system updates, Ladrok Store installs newer releases of the Launcher and of itself, from its catalog, only when they carry the same certificate. `LadrokUpdater` handles system updates only.

## Build from source

You need Linux, or WSL2 on Windows, with Ubuntu 24.04, about 400 GB of free disk, 32 GB of RAM or more, and the [AOSP build dependencies](https://source.android.com/docs/setup/start/requirements). You also need `repo`, `sgdisk`, `mtools` and `dosfstools`.

```bash
git clone https://github.com/Kordal/ladrok-tv && cd ladrok-tv
bash scripts/sync.sh            # AOSP 17 + raspberry-vanilla manifests into ~/aosp-rpi (shallow)
bash scripts/apply-patches.sh   # our changes, from patches/, plus the newest Launcher and Store APKs
bash scripts/build.sh           # userdebug images + ladrok-tv-<date>.img (GPT, A/B) in the repo root
```

`build.sh` is for development: it isn't signed with release keys. Releases come from `scripts/make-ota.sh` (below). Use `scripts/build-images.sh` to build only the boot, system and vendor images.

Flash it with Raspberry Pi Imager. On Windows you can also run `scripts\flash-sd.ps1` from an elevated PowerShell. It backs up the card, writes the image and verifies it.

### Publishing your own updates

If you build your own images, use **your own** update key and release repository. Otherwise devices running your build would accept updates from this project.

1. Create the keys:
   ```bash
   mkdir -p ~/ladrok-keys && cd ~/ladrok-keys
   openssl genrsa -out ota.key 4096
   openssl req -new -x509 -sha256 -key ota.key -out ota.x509.pem -days 10950 -subj '/CN=my OTA key'
   openssl pkcs8 -in ota.key -topk8 -outform DER -out ota.pk8 -nocrypt
   cp ota.x509.pem ~/aosp-rpi/device/brcm/rpi5/security/ota.x509.pem
   bash tools/make-release-keys.sh   # app and APEX release keys into ~/ladrok-keys/release
   ```
   Back up `~/ladrok-keys`. Without it, devices running your build can only be updated by reflashing.
2. Set `release_repo` in `device/brcm/rpi5/LadrokUpdater/res/values/strings.xml` to your `owner/repo`.
3. Build both variants of a release:
   ```bash
   export BUILD_NUMBER=$(date +%Y%m%d.%H%M)
   VARIANT=userdebug bash scripts/make-ota.sh --image
   VARIANT=user bash scripts/make-ota.sh --image
   ```
   For each variant this writes the OTA zip, `update-<variant>.json` and, with `--image`, the `.img.xz` card image with its `.sha256`.
   Attach all of them to one GitHub release, and devices will pick it up within a day.

The official images are built the same way, on a local machine (WSL2). GitHub Actions doesn't build images.

## Repository layout

| Path | What |
|---|---|
| `patches/` | Changes to the AOSP tree, one patch per project (`device/brcm/rpi5`, `device/google/atv`, `build/make`, `system/sepolicy`) |
| `.github/` | Claude BugBot review on pull requests (`bugbot.yml`, needs the `CLAUDE_SETUP_TOKEN` secret), release announcements on Discord, and the Discord server's settings (`discord/server.json`, applied by `discord-admin.yml`) |
| `scripts/` | sync, apply/export patches, `fetch-prebuilts.sh` (Launcher and Store APKs), build, `mkimg-ab.sh` (card image), `make-ota.sh` (signed release: OTA, update config, card image), flash scripts |
| `tools/` | `make-release-keys.sh` and `sign-target-files.sh` (release signing), `connect.ps1` (wireless adb via mDNS; if the TV isn't found, use `adb connect <ip>:<port>` from Developer options → Wireless debugging), `ab-status.sh` (slot and tryboot state on the device), `test-fallback.sh` (rollback test), `ota-sideload.ps1` (install an OTA over adb), `make-logo-assets.py` (boot animation and icons from the logo) |
| `docs/` | The logo (`ladrok-logo-source.png` is the original artwork) and, in `docs/agents/`, notes for coding agents on issues, triage labels and domain docs (see `AGENTS.md`) |

## Credits and license

Built on the [Android Open Source Project](https://source.android.com/) and the [raspberry-vanilla](https://github.com/raspberry-vanilla) Raspberry Pi device trees by KonstaKANG.
Our own code and the patches are released under the Apache License 2.0 (see `LICENSE`), the same license as the projects they modify.
