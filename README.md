# installer

Rebuilds my laptop from a fresh **Fedora KDE** install. One script installs
the system side: repositories, packages, codecs, tools, Flatpaks, services
and a few machine-specific files. chezmoi, with my private `dotfiles` repo,
brings back everything in the home directory. The script can be rerun at
any time: it only does what is missing, and at the end it tells you what
changed.

It replaces [penguinos](https://github.com/privatepenguinzero/penguinos),
the bootc image that needed a nightly CI build. The design and the plan are
in `docs/superpowers/`.

## Fresh install

1. Install Fedora KDE (current release).
2. Run:

   ```bash
   git clone https://github.com/privatepenguinzero/installer
   cd installer && ./install.sh
   ```

3. If it stops with exit code 2, pass-cli is not logged in yet. chezmoi
   needs it for the SSH key. Log in, then run the script again:

   ```bash
   PROTON_PASS_LINUX_KEYRING=dbus pass-cli login
   ./install.sh
   ```

## Adding a program

Add one line to the right list, then rerun `./install.sh`:

| List | What goes in it |
|---|---|
| `lists/dnf.txt` | Fedora / RPM Fusion / Terra / COPR packages |
| `lists/brew.txt` | Homebrew formulae |
| `lists/flatpak.txt` | Flathub app IDs |

A misspelled or renamed dnf package stops the script with its name. `tests/run`
checks every name in `dnf.txt` against the real repositories.

## Tests

`tests/run` runs shellcheck and the bats suite in containers. It needs only
podman.

## Laptop migration (one-off, 2026-10)

Moving the T480s from penguinos to Fedora KDE without losing the home:

1. Rehearse on a throwaway Proxmox VM (plan, Task 9).
2. `install/backup-home <dest>`. Do not go on unless it prints `backup verified`.
3. `install/render-ks`, then serve the file over HTTP, then
   `install/netboot-hook enable <mac> <url>`.
4. `sudo efibootmgr --bootnext 001C && sudo systemctl reboot`. The installer
   runs unattended: it keeps the `home` subvolume and renames the old system
   to `ostree-old`.
5. `install/netboot-hook disable`. Then on the new system, `./install.sh`,
   `pass-cli login`, and `./install.sh` again.
6. Restore the Wi-Fi profiles and the NetBird state from the backup.
7. Change the temporary passwords (`passwd`, `sudo passwd root`).
8. After two weeks, delete `ostree-old`.
