source /usr/share/cachyos-fish-config/cachyos-config.fish

# overwrite greeting -- cachyos-config.fish defines one that runs fastfetch, so
# an empty function is what makes a new shell open clean
function fish_greeting
end

# bare `fastfetch` gets a random pokemon as its logo; with arguments
# (--help, -c, ...) it is the real thing, untouched
function fastfetch
    if test (count $argv) -eq 0
        command fastfetch --data-raw "$(pokemon-colorscripts -r)"
    else
        command fastfetch $argv
    end
end

alias i "sudo pacman -S"
alias r "sudo pacman -R"
alias p "paru -S"
alias ff "fastfetch"
alias pk "pokemon-colorscripts -r"
function lazyg
    git add --all && git commit -m "Update" && git push
end

# zoxide: `z <part of a path>` jumps to the best match among directories you
# have visited, `zi` picks one interactively. Guarded so a machine without the
# package gets a working shell rather than an error on every prompt.
if status is-interactive; and command -q zoxide
    zoxide init fish | source
end
