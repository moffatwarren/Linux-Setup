# Writing an ISO or image to a USB drive

> **`dd` overwrites the target drive without asking.** Check the device name
> with `lsblk` first — the examples assume the USB stick is `sda`.

## Write an ISO

1. See which drives are connected and find the USB stick:

   ```sh
   lsblk
   ```

2. Unmount its partition if it is mounted (replace `#` with the partition number):

   ```sh
   sudo umount /dev/sda#
   ```

3. Write the image and flush it to the drive:

   ```sh
   sudo dd bs=4M if=/path/to/archlinux.iso of=/dev/sda status=progress conv=fdatasync
   sudo sync
   ```

## Compressed `.bz2` images

Either unzip it first (`-k` keeps the original), then run the `dd` command above:

```sh
bunzip2 -k "file path"
```

Or decompress and pipe straight to the USB drive (`sdX`) in one go:

```sh
bzcat steamdeck-recovery-4.img.bz2 | sudo dd if=/dev/stdin of=/dev/sdX oflag=sync status=progress bs=4M
```
