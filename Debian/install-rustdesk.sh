#!/bin/sh

flatpak --user remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak --user install ./rustdesk-1.4.4-x86_64.flatpak
flatpak run com.rustdesk.RustDesk
