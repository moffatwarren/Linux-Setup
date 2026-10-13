# Package management (pacman)

## Stop a package from being upgraded

Use this to keep `pacman -Syu` from immediately upgrading a package back to a
broken version.

1. Open the config:

   ```sh
   sudo nvim /etc/pacman.conf
   ```

2. Find the `[options]` section.
3. Uncomment or add the `IgnorePkg` line, naming the package (here `tzdata`):

   ```ini
   IgnorePkg = tzdata
   ```

## Go back to a previous version of a package

1. Find the old version in the package cache:

   ```sh
   ls /var/cache/pacman/pkg/ | grep package_name
   ```

2. Install it from the cache:

   ```sh
   sudo pacman -U /var/cache/pacman/pkg/package_name-old_version-x86_64.pkg.tar.zst
   ```
