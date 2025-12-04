#!/bin/sh

echo ""
echo "//////////////////////////////////"
echo "/////// INSTALLING APPS //////////"
echo "//////////////////////////////////"
echo ""

. ~/Omarchy-Setup/install-kate.sh
. ~/Omarchy-Setup/install-copyq.sh
. ~/Omarchy-Setup/install-frog.sh
. ~/Omarchy-Setup/install-gimp.sh
. ~/Omarchy-Setup/install-obs.sh
. ~/Omarchy-Setup/install-parsec.sh
. ~/Omarchy-Setup/install-teamviewer.sh
. ~/Omarchy-Setup/install-nordvpn.sh
. ~/Omarchy-Setup/install-tailscale.sh

echo ""
echo "//////////////////////////////////"
echo "///////// MOVING FILES ///////////"
echo "//////////////////////////////////"
echo ""

. ~/Omarchy-Setup/move-config-files.sh

echo ""
echo "//////////////////////////////////"
echo "///// EVERYTHING IS DONE!!! //////"
echo "//////////////////////////////////"
echo ""
