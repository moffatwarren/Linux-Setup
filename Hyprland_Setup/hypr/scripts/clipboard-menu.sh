#!/bin/bash
# Clipboard history picker (SUPER + V).
#
# Same job as the old one-liner `cliphist list | rofi -dmenu -display-columns 2
# | cliphist decode | wl-copy`, except image entries get a real thumbnail
# instead of cliphist's "[[ binary data 547 KiB png 998x608 ]]" placeholder.
#
# Thumbnails are cached under ~/.cache/cliphist-thumbs keyed by the cliphist
# id, so an entry is only decoded and scaled once. cliphist ids are never
# reused, so a cached file can't go stale; entries that have fallen out of the
# history are pruned on each run.
set -uo pipefail

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/cliphist-thumbs"
THUMB_SIZE=256      # px, the cached thumbnail
ICON_SIZE=4         # em, how big rofi draws it (theme default is ~40px)

mkdir -p "$CACHE_DIR"

mapfile -t entries < <(cliphist list)
[[ ${#entries[@]} -gt 0 ]] || exit 0

ids=()        # cliphist id per row, indexed the same way rofi indexes rows
types=()      # image mime subtype per row, empty for text
rows=()       # display label per row
icons=()      # thumbnail path per row, empty for text
declare -A live=()

for line in "${entries[@]}"; do
    id=${line%%$'\t'*}
    preview=${line#*$'\t'}
    type=""
    icon=""
    label=$preview

    # cliphist renders images as: [[ binary data <n> <unit> <fmt> <WxH> ]]
    if [[ $preview =~ ^\[\[\ binary\ data\ ([0-9.]+\ [A-Za-z]+)\ (png|jpe?g|gif|bmp|webp|tiff|ico)\ ([0-9]+x[0-9]+) ]]; then
        size=${BASH_REMATCH[1]}
        type=${BASH_REMATCH[2]}
        dims=${BASH_REMATCH[3]}
        label="  ${dims}  ${type}  ${size}"

        icon="$CACHE_DIR/$id.png"
        if [[ ! -s $icon ]]; then
            if ! cliphist decode "$id" 2>/dev/null |
                 magick - -thumbnail "${THUMB_SIZE}x${THUMB_SIZE}" "$icon" 2>/dev/null; then
                rm -f "$icon"
                icon=""
            fi
        fi
        live[$id.png]=1
    fi

    ids+=("$id")
    types+=("$type")
    rows+=("$label")
    icons+=("$icon")
done

# Drop thumbnails for entries cliphist has since evicted.
for f in "$CACHE_DIR"/*.png; do
    [[ -e $f ]] || continue
    [[ -v live[$(basename "$f")] ]] || rm -f "$f"
done

emit_rows() {
    for i in "${!rows[@]}"; do
        if [[ -n ${icons[i]} ]]; then
            printf '%s\0icon\x1f%s\n' "${rows[i]}" "${icons[i]}"
        else
            printf '%s\n' "${rows[i]}"
        fi
    done
}

# -format i returns the row's index in the input, so the label shown never has
# to carry the cliphist id.
index=$(emit_rows | rofi -dmenu -i -no-custom -p "󰅇 clipboard:" \
    -show-icons \
    -format i \
    -theme-str "element-icon { size: ${ICON_SIZE}em; }")

[[ -n ${index:-} && $index -ge 0 ]] || exit 0

id=${ids[index]}
type=${types[index]}

if [[ -n $type ]]; then
    [[ $type == jpg ]] && type=jpeg
    cliphist decode "$id" | wl-copy --type "image/$type"
else
    cliphist decode "$id" | wl-copy
fi
