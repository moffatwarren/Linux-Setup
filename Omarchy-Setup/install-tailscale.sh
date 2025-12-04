#!/bin/sh

yay -S --noconfirm --needed tailscale

# tailscale up --exit-node="my-linux-server-name" --exit-node-allow-lan-access=true
# tailscale up --exit-node=100.x.x.x         --------> or use the tailnet ip of the exit node
# tailscale up --exit-node=""         --------> this is to stop going through the exit node


# tailscale up --accept-routes --exit-node-allow-lan-access --exit-node=100.96.181.13 --operator=warren