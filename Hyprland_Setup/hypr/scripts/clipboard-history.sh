#!/bin/bash
# Clipboard history backend for the SUPER+V picker (quickshell/ClipboardMenu.qml).
#
# It replaced clipboard-menu.sh, which drew its own `rofi -dmenu` list. The
# picker is a quickshell overlay now, sharing a window with the app launcher
# and the wallpaper picker, so this script no longer renders anything -- it
# prints the history as JSON and performs the copy/delete the QML asks for.
# (install.sh's ORPHANS list deletes the old clipboard-menu.sh from a machine
# upgrading from the rofi layout.)
#
#   --list            the history as a JSON array, newest first
#   --copy   <id>     put that entry back on the clipboard
#   --delete <id>     drop that entry from the history
#
# Image entries get a real thumbnail rather than cliphist's
# "[[ binary data 547 KiB png 998x608 ]]" placeholder. Thumbnails are cached
# under ~/.cache/cliphist-thumbs keyed by the cliphist id; ids are never
# reused, so a cached file cannot go stale, and entries that have fallen out of
# the history are pruned on each --list.
set -uo pipefail

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/cliphist-thumbs"
THUMB_SIZE=256      # px, the cached thumbnail

# cliphist renders images as: [[ binary data <n> <unit> <fmt> <WxH> ]]
BINARY_RE='^\[\[ binary data ([0-9.]+ [A-Za-z]+) (png|jpe?g|gif|bmp|webp|tiff|ico) ([0-9]+x[0-9]+)'

# The one entry whose id is $1, as cliphist's own "<id>\t<preview>" line.
entry_line() {
    cliphist list | grep -am1 -P "^$1\t"
}

do_list() {
    mkdir -p "$CACHE_DIR"

    # Thumbnails first: jq below derives each path from the id, so all it needs
    # back is which ids actually have one. Ids are decimal, so a space-joined
    # list needs no quoting.
    #
    # Only the binary lines are read into a shell variable. Clipboard text is
    # arbitrary bytes and bash strings cannot hold a NUL, so slurping the whole
    # history into one would truncate entries and warn about it on every run;
    # cliphist's placeholder for an image contains nothing but ASCII. The text
    # entries only ever travel down the pipe into jq, which keeps them intact.
    local thumbed=()
    local -A live=()
    local line id thumb
    while IFS= read -r line; do
        id=${line%%$'\t'*}
        thumb="$CACHE_DIR/$id.png"
        if [[ ! -s $thumb ]]; then
            if ! cliphist decode "$id" 2>/dev/null |
                 magick - -thumbnail "${THUMB_SIZE}x${THUMB_SIZE}" "$thumb" 2>/dev/null; then
                rm -f "$thumb"
                continue
            fi
        fi
        thumbed+=("$id")
        live[$id.png]=1
    done < <(cliphist list | grep -aP '^[0-9]+\t\[\[ binary data ')

    # Drop thumbnails for entries cliphist has since evicted.
    # ${f##*/} rather than basename: a cache of a few dozen thumbnails is a
    # few dozen forks otherwise, and that was the whole cost of a --list.
    local f
    for f in "$CACHE_DIR"/*.png; do
        [[ -e $f ]] || continue
        [[ -v live[${f##*/}] ]] || rm -f "$f"
    done

    # One jq pass over cliphist's raw output rather than a jq per row: the
    # preview is arbitrary clipboard text, so it is never interpolated into a
    # shell word or split on a separator it might itself contain.
    cliphist list | jq -Rc --slurp \
       --arg dir "$CACHE_DIR" \
       --arg thumbed "${thumbed[*]:-}" \
       --arg binre "$BINARY_RE" '
        ($thumbed | split(" ") | map(select(length > 0))) as $ids
        | split("\n")
        | map(select(length > 0))
        | map(
            (index("\t")) as $i
            | { id: .[:$i], preview: .[$i+1:] }
          )
        | map(
            # match, not capture: the regex is shared with the bash [[ =~ ]]
            # below, and bash EREs have no named groups for capture to key on.
            # Wrapping in [] makes "no match" a null rather than an empty
            # stream, which `as` cannot bind.
            .id as $id
            # `$ids | index(.id)` would not work: the pipe rebinds `.` to the
            # array, so the argument has to be hoisted out first.
            | ([.preview | match($binre)] | first) as $b
            | if $b == null then
                { id, kind: "text", label: .preview, detail: "" , thumb: "" }
              else
                { id,
                  kind: "image",
                  label: ($b.captures[2].string + "  " + $b.captures[1].string),
                  detail: $b.captures[0].string,
                  thumb: (if ($ids | index($id)) != null then $dir + "/" + $id + ".png" else "" end) }
              end
          )
    '
}

do_copy() {
    # tr -d '\0': only the format matters here, and a command substitution
    # cannot hold a NUL -- it drops it and warns on stderr for every text entry
    # that happens to contain one. do_delete pipes instead, so the line it hands
    # cliphist stays byte-for-byte what cliphist printed.
    local line preview
    line=$(entry_line "$1" | tr -d '\0') || return 1
    preview=${line#*$'\t'}

    if [[ $preview =~ $BINARY_RE ]]; then
        local fmt=${BASH_REMATCH[2]}
        [[ $fmt == jpg ]] && fmt=jpeg
        cliphist decode "$1" | wl-copy --type "image/$fmt"
    else
        cliphist decode "$1" | wl-copy
    fi
}

# cliphist deletes by being fed the same "<id>\t<preview>" line it printed.
do_delete() {
    entry_line "$1" | cliphist delete
}

case "${1:---list}" in
    --list)   do_list ;;
    --copy)   [[ $# -ge 2 ]] || { echo "usage: $0 --copy <id>" >&2; exit 2; }
              do_copy "$2" ;;
    --delete) [[ $# -ge 2 ]] || { echo "usage: $0 --delete <id>" >&2; exit 2; }
              do_delete "$2" ;;
    *)        echo "usage: $0 [--list | --copy <id> | --delete <id>]" >&2; exit 2 ;;
esac
