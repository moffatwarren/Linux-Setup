# Powerline prompt in Catppuccin Mocha: a rounded blue user@host segment, a teal
# directory segment, and a mauve git branch segment inside a repository.
#
# A file here overrides fish-pure-prompt's fish_prompt in vendor_functions.d,
# which is what drew the prompt before. Glyphs are \uXXXX escapes, never pasted:
# they are private-use codepoints and a literal one is easily lost in an edit.
function fish_prompt
    set -l crust 11111b
    set -l colors 89b4fa 94e2d5
    # \uf385 is nf-linux-cachyos
    set -l texts " "\uf385" $USER@$hostname " " "(prompt_pwd --dir-length=0)" "

    set -l branch (command git branch --show-current 2>/dev/null)
    if test -n "$branch"
        set -a colors cba6f7
        set -a texts " "\ue725" $branch "
    end

    # rounded left cap, then each segment closed by an arrow drawn in its own
    # colour on the next segment's background
    set_color $colors[1]
    echo -n \ue0b6
    set -l n (count $colors)
    for i in (seq $n)
        set_color -b $colors[$i] $crust
        echo -n $texts[$i]
        set_color normal
        if test $i -lt $n
            set_color -b $colors[(math $i + 1)] $colors[$i]
        else
            set_color $colors[$i]
        end
        echo -n \ue0b0
    end
    set_color normal
    echo -n " "
end
