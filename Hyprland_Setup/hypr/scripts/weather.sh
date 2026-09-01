#!/bin/bash

case $1 in
--openWeather)
  TERMINAL=$(sed -n "s/^[[:space:]]*config\.terminal[[:space:]]*=[[:space:]]*['\"]\([^'\"]*\)['\"].*/\1/p" "$HOME/.config/hypr/modules/config.lua" 2>/dev/null)
  rm -f "$HOME/.cache/weathr/location.json"
  "${TERMINAL:-kitty}" --class weathr-float -e weathr
  ;;
esac
