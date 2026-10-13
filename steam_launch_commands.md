# Steam launch options

Paste into a game's **Properties → Launch Options**.

## gamescope at 2560x1440, 240 Hz, fullscreen

```sh
PROTON_NO_NTSYNC=1 gamescope -W 2560 -H 1440 -w 2560 -h 1440 -r 240 -f -- %command%
```

## Show MangoHud

Add `MANGOHUD=1` at the start of the launch options:

```sh
MANGOHUD=1 PROTON_NO_NTSYNC=1 gamescope -W 2560 -H 1440 -w 2560 -h 1440 -r 240 -f -- %command%
```
