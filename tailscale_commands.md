# Tailscale commands

## Setup

```sh
curl -fsSL https://tailscale.com/install.sh | sh
```

## Status

```sh
tailscale status
tailscale ip
```

## Exit nodes

Route through an exit node, by name:

```sh
sudo tailscale up --exit-node="my-linux-server-name" --exit-node-allow-lan-access=true
```

Or by the exit node's tailnet IP:

```sh
sudo tailscale up --exit-node=100.x.x.x
```

Stop going through the exit node:

```sh
sudo tailscale set --exit-node=""
```

The full command used on this setup (accept routes, keep LAN access, and make
this user the operator so later commands need no `sudo`):

```sh
sudo tailscale up --accept-routes --exit-node-allow-lan-access --exit-node=100.96.181.13 --operator=$USER
```

## Taildrop

Send files to another device (the trailing `:` is required):

```sh
tailscale file cp <files> <name-or-ip>:
```

Receive waiting files into the current directory:

```sh
sudo tailscale file get .
```
