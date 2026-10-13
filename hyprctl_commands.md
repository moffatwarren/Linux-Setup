# hyprctl commands

```sh
hyprctl monitors
hyprctl devices
```

## Get the class of a window

Run this, then focus the window within three seconds. Read the `class:` line.

```sh
sleep 3 && hyprctl activewindow
```
