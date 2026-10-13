# Mounting a network drive (SMB/CIFS share) under /mnt

The example used throughout is server `192.168.0.218`, share `warrennas`,
mounted at `/mnt/warrennas`. Swap in your own server, share and folder name.

Needs the `cifs-utils` package:

```sh
sudo pacman -S cifs-utils
```

## 1. Create the mount point

```sh
sudo mkdir -p /mnt/warrennas
```

## 2. Store the server login in a root-only file

```sh
sudo mkdir -p /etc/samba
SUDO_EDITOR=nvim sudoedit /etc/samba/creds-nas
```

Put these two lines in it — the account on the **server**, not the Linux login:

```ini
username=YOUR_NAS_USER
password=YOUR_NAS_PASSWORD
```

Then make it readable by root only:

```sh
sudo chmod 600 /etc/samba/creds-nas
```

One credentials file covers every share on the same server.

## 3. Add the share to /etc/fstab

```sh
SUDO_EDITOR=nvim sudoedit /etc/fstab
```

Add this as **one line** at the end of the file. It is text in the file, not a
command. Do not touch the lines already there — they mount the system disks.

```fstab
//192.168.0.218/warrennas  /mnt/warrennas  cifs  credentials=/etc/samba/creds-nas,uid=1000,gid=1000,noauto,x-systemd.automount,_netdev  0  0
```

| Option | What it does |
|---|---|
| `credentials=…` | the login file from step 2 |
| `uid=1000,gid=1000` | files belong to your user, so no `sudo` to write (check yours with `id -u` and `id -g`) |
| `noauto,x-systemd.automount` | mount on first access rather than at boot, so the machine still boots when the server is off |
| `_netdev` | wait for the network before trying |

## 4. Activate it without rebooting

```sh
sudo systemctl daemon-reload
sudo systemctl start mnt-warrennas.automount
ls /mnt/warrennas
```

The `ls` is what triggers the mount; it should list the share's contents.

The unit name is the mount path with `/` turned into `-`: `/mnt/warrennas` is
`mnt-warrennas.automount`, `/mnt/appdata` is `mnt-appdata.automount`.

## Adding another share from the same server

Repeat steps 1, 3 and 4 with the new name. Step 2 is already done.

```sh
sudo mkdir -p /mnt/appdata
```

Line for `/etc/fstab`:

```fstab
//192.168.0.218/appdata  /mnt/appdata  cifs  credentials=/etc/samba/creds-nas,uid=1000,gid=1000,noauto,x-systemd.automount,_netdev  0  0
```

```sh
sudo systemctl daemon-reload
sudo systemctl start mnt-appdata.automount
```

## Pinning it in superfile (spf)

```sh
spf /mnt/warrennas
```

Then press `Shift+P`. Pressing it again inside the folder unpins it.

## Troubleshooting

| Command | Answers |
|---|---|
| `sudo dmesg \| tail` | why a mount failed (a bad login is the usual one) |
| `systemctl status mnt-warrennas.automount` | is the automount armed |
| `findmnt /mnt/warrennas` | is it mounted right now |
| `sudo umount /mnt/warrennas` | unmount by hand |

`sudoedit: /usr/bin/vi: command not found` means no editor is set — prefix the
command with `SUDO_EDITOR=nvim`, as above.

## Removing a share

1. Stop the automount, and unmount the share if it is mounted:

   ```sh
   sudo systemctl stop mnt-warrennas.automount
   sudo umount /mnt/warrennas
   ```

2. Delete its line from `/etc/fstab`.
3. Reload and remove the folder:

   ```sh
   sudo systemctl daemon-reload
   sudo rmdir /mnt/warrennas
   ```
