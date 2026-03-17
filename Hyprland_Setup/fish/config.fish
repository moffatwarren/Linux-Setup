source /usr/share/cachyos-fish-config/cachyos-config.fish

# overwrite greeting
# potentially disabling fastfetch
function fish_greeting
    # fastfetch
    fastfetch --data-raw "$(pokemon-colorscripts -r)"
end

alias i "sudo pacman -S"
alias r "sudo pacman -R"
alias p "paru -S"
alias ff "fastfetch"
alias pk "pokemon-colorscripts -r"
