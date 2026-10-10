# Brother HL-2270DW driver (patched brlaser)

Driver and print-queue setup for the Brother HL-2270DW on CachyOS / Arch.

It fixes two problems:

1. **Duplex back pages printed upside down.** Stock `brlaser` sends the PCL
   short-edge code (`ESC&l2S`) for long-edge duplex as well, and relies on CUPS
   to rotate the back pages. Current cups-filters does not do that rotation, so
   every long-edge back side came out upside down. `long-edge-duplex.patch` sends
   `ESC&l1S` for long edge and `ESC&l2S` for short edge, so the printer flips the
   pages itself.
2. **Printing from a browser failed or paused the queue.** The printer only
   speaks very old IPP. The queue below uses raw port 9100
   (`_pdl-datastream`) instead, and retries rather than pausing on an error.

## Files

| File | What it is |
|---|---|
| `PKGBUILD` | The AUR `brlaser-git` package, with a `prepare()` step that applies the patch |
| `long-edge-duplex.patch` | The one-line duplex fix in `src/job.cc` |

## Install

### 1. Printing services

```
sudo pacman -S --needed cups avahi base-devel git cmake
sudo systemctl enable --now cups avahi-daemon
```

### 2. Build and install the driver

From this directory:

```
makepkg -si
```

That clones brlaser, applies the patch, builds it, and installs `brlaser-git`.
If `brlaser` or an unpatched `brlaser-git` is already installed, it replaces
that package.

### 3. Add the printer

The printer must be on and on the same network.

```
sudo lpadmin -p Brother-HL-2270DW-series -E \
  -v 'dnssd://Brother%20HL-2270DW%20series._pdl-datastream._tcp.local/' \
  -m drv:///brlaser.drv/br2270d.ppd \
  -o printer-error-policy=retry-job
```

Do **not** let the system or the printer-settings app add the printer
automatically. That picks the `_ipp._tcp` address, which is what caused the
browser printing failures. If an auto-added queue already exists, remove it
(`sudo lpadmin -x <name>`; list queue names with `lpstat -v`).

If the `dnssd://` address doesn't work, use the printer's IP address instead:
`-v socket://<printer-ip>:9100`. This only keeps working while the printer
keeps that IP.

### 4. Stop paru from replacing the patched driver

If `/etc/paru.conf` has `Devel` enabled, add this line under `[options]`:

```
IgnoreDevel = brlaser-git
```

Without it, `paru -Syu` would eventually rebuild `brlaser-git` from the AUR
without the patch, and the back pages would be upside down again.

## Test

Print any 2-page document from LibreOffice or a browser. Choose the
`Brother-HL-2270DW-series` printer and **Long edge** duplex. The back page
should be the same way up as the front.

## Updating the driver later

Run `makepkg -si` in this directory again. It pulls the latest brlaser and
re-applies the patch. If the patch no longer applies, upstream has changed
`src/job.cc`. Open that file and find where it writes `\033&l2S`. Long edge
(duplex without tumble) must send `\033&l1S`, and short edge (duplex with
tumble) must send `\033&l2S`.
