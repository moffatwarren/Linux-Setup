# Brother HL-2270DW driver (patched brlaser)

Driver and print-queue setup for the Brother HL-2270DW on CachyOS / Arch.

It fixes two problems:

1. **Duplex back pages printed upside down.** brlaser always sends the PCL
   short-edge code (`ESC&l2S`), so the printer flips every sheet on its short
   edge. For a long-edge job the back page therefore has to arrive rotated
   180°. Two changes make that happen for every app:

   - **The PPD says `Duplex normal`** (set in the PKGBUILD). `cupsBackSide`
     describes what the *printer* does to back pages. Stock brlaser says
     `Rotated` ("the printer already rotates them"), so CUPS never rotated
     them. With `Normal`, CUPS's `pdftopdf` rotates them, but **only when the
     job carries the IPP `sides` attribute** (LibreOffice sends
     `sides=two-sided-long-edge`).
   - **`long-edge-duplex.patch`** covers the jobs that don't. Chrome asks for
     duplex with the PPD's `Duplex=DuplexNoTumble` option alone, so
     `pdftopdf` leaves its back pages unrotated. The filter reads the same
     job options, and rotates every second page itself when it sees no
     `sides=two-sided-long-edge`, so the two never both rotate a page.

   Two things that do **not** work: sending the long-edge code `ESC&l1S` (the
   printer honours it, so with CUPS's rotation the back is upside down again),
   and rotating in the filter unconditionally (that undoes CUPS's rotation for
   LibreOffice jobs).

2. **Printing from a browser failed or paused the queue.** The printer only
   speaks very old IPP. The queue below uses raw port 9100
   (`_pdl-datastream`) instead, and retries rather than pausing on an error.

## Files

| File | What it is |
|---|---|
| `PKGBUILD` | The AUR `brlaser-git` package, with a `prepare()` step that applies the patch and sets the HL-2270DW to `Duplex normal` |
| `long-edge-duplex.patch` | Rotates long-edge back pages in `src/main.cc` for jobs CUPS did not rotate |

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

That clones brlaser, applies the duplex fix, builds it, and installs `brlaser-git`.
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

Run this:
```
sudo sed -i '/^Devel$/a IgnoreDevel = brlaser-git' /etc/paru.conf
```
And check that it is intalled here:
```
grep -A1 '^Devel$' /etc/paru.conf
```
You should see this:
```
Devel
IgnoreDevel = brlaser-git
```

Without it, `paru -Syu` would eventually rebuild `brlaser-git` from the AUR
without the duplex fix, and the back pages would be upside down again.

## Test

Print any 2-page document from **both** LibreOffice and Chrome. They take
different paths through CUPS (see above), so one working says nothing about
the other. Choose the
`Brother-HL-2270DW-series` printer and **Long edge** duplex. The back page
should be the same way up as the front.

## Updating the driver later

Run `makepkg -si` in this directory again. It pulls the latest brlaser and
re-applies the duplex fix. If the patch no longer applies, upstream has
changed the page loop in `src/main.cc`; the rule it implements is above. Then
re-add the printer (step 3), because a queue
keeps a copy of the PPD from when it was created. Check it took with
`curl -s http://localhost:631/printers/Brother-HL-2270DW-series.ppd | grep cupsBackSide`,
which should print `Normal`.
