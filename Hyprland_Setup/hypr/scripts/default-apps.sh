#!/usr/bin/env bash
#
# Backend for the SUPER+D defaults overlay (quickshell/DefaultsMenu.qml).
#
#   --list   every candidate app per category, plus the current default, as JSON
#   --get    just the current defaults, as JSON
#   --resolve <category>
#            the absolute path of the .desktop that category resolves to --
#            what launch-file-manager.sh (SUPER+E) opens
#   --ensure-filemanager [legacy-command]
#            give folders an explicit default when they have none worth keeping
#   --prune  drop the associations an earlier version's globs2 sweep wrote
#   --set <browser|editor|video|image|filemanager> <desktop_id> [name]
#
# Candidates are classified by the .desktop entry's own MimeType= key, never by
# its name -- see the comment above PROBES and the CLAUDE.md section.
#
set -euo pipefail

# ---------------------------------------------------------------------------
# The shared python preamble: scan the XDG applications directories once and
# expose entries() and current_default().
# ---------------------------------------------------------------------------
py_common() {
    cat <<'PY'
import os, sys, json, glob, subprocess, configparser

CONFIG_HOME = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
MIME_FILE = os.path.join(CONFIG_HOME, "mimeapps.list")
DATA_HOME = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")

def app_dirs():
    dirs = [os.path.join(DATA_HOME, "applications")]
    raw = os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
    for d in raw.split(":"):
        if d:
            dirs.append(os.path.join(d, "applications"))
    # Flatpak exports are not in XDG_DATA_DIRS in a bare Hyprland session.
    dirs.append(os.path.join(DATA_HOME, "flatpak/exports/share/applications"))
    dirs.append("/var/lib/flatpak/exports/share/applications")
    seen, out = set(), []
    for d in dirs:
        r = os.path.realpath(d)
        if r not in seen:
            seen.add(r)
            out.append(d)
    return out

def read_ini(path):
    # strict=False: a mimeapps.list or .desktop written by another tool may
    # repeat a key, and strict mode raises rather than taking the first.
    c = configparser.ConfigParser(interpolation=None, strict=False)
    c.optionxform = str
    try:
        c.read(path, encoding="utf-8")
    except Exception:
        return None
    return c

_entries = None
_paths = {}

def entries():
    """{ "firefox.desktop": {Desktop Entry section} }, first directory wins."""
    global _entries
    if _entries is not None:
        return _entries
    _entries = {}
    for d in app_dirs():
        for path in sorted(glob.glob(os.path.join(d, "*.desktop"))):
            eid = os.path.basename(path)
            if eid in _entries:
                continue
            c = read_ini(path)
            if c is None or not c.has_section("Desktop Entry"):
                continue
            _entries[eid] = c["Desktop Entry"]
            _paths[eid] = path
    return _entries

def gio_default(mime):
    """What GIO resolves -- the same answer Thunar/Nautilus/Nemo will give."""
    try:
        out = subprocess.run(["gio", "mime", mime], capture_output=True,
                             text=True, timeout=5).stdout
    except Exception:
        return ""
    for line in out.splitlines():
        # "Default application for "text/plain": codium.desktop"
        if line.startswith("Default application") and ":" in line:
            val = line.split(":", 1)[1].strip()
            if val.endswith(".desktop"):
                return val
        if "No default applications" in line:
            return ""
    return ""

def mimeapps_default(mimes):
    c = read_ini(MIME_FILE)
    if c is None or not c.has_section("Default Applications"):
        return ""
    sec = c["Default Applications"]
    for m in mimes:
        val = (sec.get(m, "") or "").strip().split(";")[0].strip()
        if val:
            return val if val.endswith(".desktop") else val + ".desktop"
    return ""

def current_default(mimes):
    """GIO first (it is the resolver that actually runs), mimeapps as backstop."""
    for m in mimes:
        v = gio_default(m)
        if v:
            return v
    return mimeapps_default(mimes)

# An app is a candidate for a category when its own MimeType= says it can open
# that category's files. That is the authoritative signal and it needs no
# maintenance: it finds NoDisplay tools (swayimg, swappy, imv, satty) that an
# app-menu scanner masks, and Chromium PWAs fall out for free because they
# declare no MimeType at all.
#
# File explorers are the one category where the MIME type is not enough on its
# own. inode/directory is declared by anything that can *open a folder*, which
# on this machine includes VSCodium and kitty-open -- and GIO, with no explicit
# default, resolves folders to codium.desktop. So a file explorer must also say
# it is one: Categories=FileManager, which thunar, dolphin, nautilus, nemo,
# pcmanfm, yazi, lf and ranger all set.
PROBES = {
    "browser":     lambda mimes, cats: "x-scheme-handler/https" in mimes,
    "editor":      lambda mimes, cats: "text/plain" in mimes,
    "video":       lambda mimes, cats: any(m.startswith("video/") for m in mimes),
    "image":       lambda mimes, cats: any(m.startswith("image/") for m in mimes),
    "filemanager": lambda mimes, cats: "inode/directory" in mimes and "FileManager" in cats,
}

CATEGORIES = ("browser", "editor", "video", "image", "filemanager")

DEFAULT_MIMES = {
    "browser":     ["x-scheme-handler/https", "x-scheme-handler/http", "text/html"],
    "editor":      ["text/plain"],
    "video":       ["video/mp4", "video/x-matroska", "video/webm"],
    "image":       ["image/png", "image/jpeg"],
    "filemanager": ["inode/directory"],
}

# Ranked above the rest of a category's list. Not a filter -- GIMP really can
# open a PNG, so it is demoted, not hidden. Hiding a capable app is the mistake
# that lost swayimg in the first place.
ROLE_CATEGORIES = {
    "browser":     {"WebBrowser"},
    "editor":      {"TextEditor", "IDE", "Development"},
    "video":       {"Player", "Video", "AudioVideo"},
    "image":       {"Viewer", "Graphics", "2DGraphics", "RasterGraphics", "Photography"},
    "filemanager": {"FileManager"},
}

def split_list(val):
    return [x for x in (val or "").split(";") if x]

def is_web_app(e):
    """A Chromium PWA. Belt-and-braces: they declare no MimeType anyway."""
    exec_s = (e.get("Exec", "") or "").lower()
    if "--app-id=" in exec_s or "--app=" in exec_s:
        return True
    wm = (e.get("StartupWMClass", "") or "").lower()
    return wm.startswith("crx_") or wm.startswith("crx-")

def candidates(cat):
    probe = PROBES[cat]
    role = ROLE_CATEGORIES[cat]
    out = []
    for eid, e in entries().items():
        if (e.get("Type", "Application") or "Application") != "Application":
            continue
        # Hidden= is the spec's "the user deleted this entry", unlike
        # NoDisplay=, which only means "keep it out of the app menu" -- and
        # NoDisplay is exactly what swayimg/swappy/imv set.
        if (e.get("Hidden", "") or "").strip().lower() == "true":
            continue
        if is_web_app(e):
            continue
        mimes = split_list(e.get("MimeType", ""))
        cats = set(split_list(e.get("Categories", "")))
        if not probe(mimes, cats):
            continue
        if cat != "browser" and "WebBrowser" in cats:
            continue
        out.append({
            "id": eid,
            "name": e.get("Name", "") or eid[:-8],
            "icon": e.get("Icon", "") or "",
            "generic": e.get("GenericName", "") or e.get("Comment", "") or "",
            "_role": 0 if (cats & role) else 1,
        })
    out.sort(key=lambda a: (a["_role"], a["name"].lower()))
    return out

def explicit_default(cat):
    """The user's own mimeapps.list entry, but only if that app still exists --
    GIO ignores an association to an uninstalled .desktop, and so must we."""
    v = mimeapps_default(DEFAULT_MIMES[cat])
    return v if v in entries() else ""

def resolve_default(cat):
    """The one answer the menu's badge and the launcher both use.

    For the MIME categories this is simply what GIO resolves. For file
    explorers GIO's answer is only trusted when it *is* a file explorer:
    with no explicit entry it happily picks VSCodium for folders, and SUPER+E
    opening an IDE is not a default, it is an accident. So: an explicit choice,
    else GIO if it names a real file explorer, else the first one installed."""
    if cat != "filemanager":
        return current_default(DEFAULT_MIMES[cat])
    ids = [a["id"] for a in candidates(cat)]
    v = explicit_default(cat)
    if v:
        return v
    g = gio_default("inode/directory")
    if g in ids:
        return g
    return ids[0] if ids else ""
PY
}

# ---------------------------------------------------------------------------
# --list / --get
# ---------------------------------------------------------------------------
list_apps() {
    local want_apps="$1"   # 1 = full --list, 0 = --get
    {
        py_common
        cat <<PY
WANT_APPS = $want_apps
PY
        cat <<'PY'

result = {}
for cat in CATEGORIES:
    cur = resolve_default(cat)
    entry = {"default": cur}
    if WANT_APPS:
        apps = candidates(cat)
        # Stable sort: role and name are already the order, this lifts the
        # current default to the top without disturbing the rest.
        apps.sort(key=lambda a: a["id"] != cur)
        for a in apps:
            a.pop("_role", None)
        entry["apps"] = apps
    result[cat] = entry

print(json.dumps(result))
PY
    } | python3 -
}

# ---------------------------------------------------------------------------
# --resolve <category>: the absolute path of the resolved .desktop, or nothing
# ---------------------------------------------------------------------------
resolve_path() {
    {
        py_common
        cat <<'PY'

cat = sys.argv[1] if len(sys.argv) > 1 else ""
if cat in CATEGORIES:
    eid = resolve_default(cat)
    entries()
    if eid in _paths:
        print(_paths[eid])
PY
    } | python3 - "$1"
}

# ---------------------------------------------------------------------------
# --ensure-filemanager [legacy-command]: print the .desktop id folders should
# be given as an explicit default, or nothing when they need none.
#
# Two situations, both one-shot:
#
#   * a machine upgrading from config.fileManager. install.sh reads that value
#     out of the live config.lua before deploy_configs overwrites it and hands
#     it in here, and if there is no explicit folder default yet it becomes
#     one -- SUPER+E keeps opening exactly what it opened before. Dropping the
#     line without this would have sent SUPER+E to whichever file explorer
#     sorts first (Dolphin, on this machine, not the Thunar it ran).
#   * no explicit default and GIO resolving folders to something that is not a
#     file explorer -- VSCodium here. That is not a choice anybody made, and
#     leaving it means the badge and SUPER+E say Thunar while every xdg-open of
#     a folder opens an IDE. The first installed file explorer is written.
#
# It never overrides an explicit entry, and never overrides GIO when GIO
# already names a real file explorer. After it has written once there is an
# explicit entry, so every later run is a no-op.
# ---------------------------------------------------------------------------
ensure_filemanager_id() {
    {
        py_common
        cat <<'PY'

import shlex

legacy = (sys.argv[1] if len(sys.argv) > 1 else "").strip()
apps = candidates("filemanager")
ids = [a["id"] for a in apps]

def argv0(value):
    try:
        argv = shlex.split(value or "")
    except ValueError:
        argv = (value or "").split()
    while argv and (argv[0] == "env" or ("=" in argv[0] and not argv[0].startswith("/"))):
        argv = argv[1:]
    return os.path.basename(argv[0]) if argv else ""

def matches(eid, cmd):
    if not cmd:
        return False
    base = eid[:-8]
    if base == cmd or base.split(".")[-1].lower() == cmd.lower():
        return True
    e = entries()[eid]
    return cmd in (argv0(e.get("TryExec", "")), argv0(e.get("Exec", "")))

if not explicit_default("filemanager") and ids:
    want = ""
    cmd = argv0(legacy)
    if cmd:
        want = next((i for i in ids if matches(i, cmd)), "")
    if not want and gio_default("inode/directory") not in ids:
        want = ids[0]
    if want:
        print(want)
PY
    } | python3 - "$1"
}

# ---------------------------------------------------------------------------
# --set: write both [Default Applications] and [Added Associations]
# ---------------------------------------------------------------------------
apply_mime_associations() {
    local desktop="$1"
    shift
    python3 - "$desktop" "$@" <<'PY'
import os, sys, configparser

desktop = sys.argv[1]
if not desktop.endswith(".desktop"):
    desktop += ".desktop"
desktop_base = desktop[:-8]
mimes = [m for m in sys.argv[2:] if m]

CONFIG_HOME = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
mime_file = os.path.join(CONFIG_HOME, "mimeapps.list")
os.makedirs(CONFIG_HOME, exist_ok=True)

config = configparser.ConfigParser(interpolation=None, strict=False)
config.optionxform = str
try:
    config.read(mime_file, encoding="utf-8")
except Exception:
    # A file we cannot parse is better replaced than half-edited.
    config = configparser.ConfigParser(interpolation=None, strict=False)
    config.optionxform = str

for sec in ("Default Applications", "Added Associations"):
    if not config.has_section(sec):
        config.add_section(sec)

# Repair legacy extension-less entries: GIO rejects an association without the
# .desktop suffix, which is what made an earlier version of this appear to set
# a default that silently never took.
for k, v in list(config.items("Default Applications")):
    if v == desktop_base:
        config.set("Default Applications", k, desktop)

for m in mimes:
    config.set("Default Applications", m, desktop)
    existing = config.get("Added Associations", m, fallback="")
    others = [a for a in existing.split(";") if a and a not in (desktop, desktop_base)]
    config.set("Added Associations", m, ";".join([desktop] + others) + ";")

tmp = mime_file + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    config.write(f, space_around_delimiters=False)
os.replace(tmp, mime_file)
PY
}

# Text and every programming language. Deliberately an explicit list rather
# than a sweep of the system MIME database: GIO walks /usr/share/mime/subclasses
# up to text/plain, so a GIO file manager needs only that one line -- but
# `xdg-mime query default` does no inheritance walk at all and answers empty for
# an unlisted type. Naming each type is what makes the setting hold in a
# resolver that does not inherit; text/plain on top catches a language nobody
# listed. Note application/x-desktop is NOT here: it is a text/plain subclass,
# and mapping it to the editor makes a double-clicked .desktop open in the
# editor instead of launching.
EDITOR_MIMES=(
    text/plain text/markdown text/x-markdown text/x-log text/csv
    text/tab-separated-values text/x-ini text/x-env text/x-readme
    text/css text/x-scss text/x-sass text/x-less
    text/javascript application/javascript application/x-javascript
    application/ecmascript text/x-typescript application/typescript
    application/json application/json5 application/ld+json text/x-json
    text/x-c text/x-csrc text/x-chdr text/x-c++ text/x-c++src text/x-c++hdr
    text/x-objcsrc text/x-csharp text/x-vala text/x-d
    text/x-rust text/rust text/x-go text/x-zig text/x-nim text/x-crystal
    text/x-python application/x-python-code text/x-python3
    text/x-lua text/x-ruby application/x-ruby text/x-perl application/x-perl
    text/x-php application/x-php text/x-tcl text/x-awk
    text/x-shellscript application/x-shellscript text/x-sh text/x-bash
    text/x-zsh text/x-fish text/x-nushell
    text/x-java text/x-java-source text/x-kotlin text/x-scala text/x-groovy
    text/x-clojure text/x-lisp text/x-scheme text/x-erlang text/x-elixir
    text/x-haskell text/x-ocaml text/x-fsharp text/x-ml
    text/x-swift text/x-dart text/x-r text/x-julia text/x-matlab
    text/x-sql application/sql text/x-diff text/x-patch
    text/x-yaml application/x-yaml text/yaml text/x-toml application/toml
    application/xml text/xml text/x-vue text/x-svelte text/x-jsx text/x-tsx
    text/x-makefile text/x-cmake text/x-dockerfile text/x-meson
    text/x-nix text/x-terraform text/x-gradle text/x-sass
    text/x-tex text/x-bibtex text/x-rst text/x-asciidoc text/x-org
)

BROWSER_MIMES=(
    x-scheme-handler/http x-scheme-handler/https x-scheme-handler/about
    x-scheme-handler/unknown text/html application/xhtml+xml
)

VIDEO_MIMES=(
    video/mp4 video/mpeg video/webm video/ogg video/quicktime video/avi
    video/vnd.avi video/x-msvideo video/x-matroska video/x-flv video/x-ms-wmv
    video/x-ms-asf video/3gpp video/3gpp2 video/x-m4v video/mp2t video/dv
    video/x-theora video/x-nsv video/x-ogm+ogg
)

IMAGE_MIMES=(
    image/png image/jpeg image/gif image/webp image/bmp image/tiff
    image/svg+xml image/avif image/heif image/heic image/jxl image/qoi
    image/apng image/x-icon image/vnd.microsoft.icon image/x-xpixmap
    image/x-portable-pixmap image/x-portable-bitmap image/x-portable-graymap
    image/x-tga image/x-bmp image/x-png
)

# x-directory/normal is the legacy alias (/usr/share/mime/aliases) -- GIO folds
# it into inode/directory, but a resolver that does not read aliases asks for
# it by name.
FILEMANAGER_MIMES=(
    inode/directory x-directory/normal
)

# ---------------------------------------------------------------------------
# --prune: undo the /usr/share/mime/globs2 sweep an earlier version of this
# script ran for the editor.
#
# That sweep matched 265 MIME types by regex and wrote every one of them into
# both sections, which is how application/x-desktop came to open in the editor
# instead of launching, and application/postscript with it. Dropping the sweep
# stops writing them; it does not remove the ones already on a machine --
# "deleting something from the repo does not delete it from the machine". So
# this reproduces the old regex exactly and removes what it matched and the
# curated list no longer claims. Nothing else writes 265 entries at once, so
# by construction every type it touches is one this repo put there.
#
# Self-limiting: after one run there is nothing left to match, and the new
# EDITOR_MIMES never puts any of them back.
# ---------------------------------------------------------------------------
prune_editor_sweep() {
    python3 - "${EDITOR_MIMES[@]}" <<'PY'
import os, re, sys, configparser

keep = set(sys.argv[1:])

# Types the old *curated* list named and the new one deliberately drops -- the
# sweep regex never matched these, so they need naming. application/x-desktop
# is a text/plain subclass, so GIO reaches the editor by inheritance either
# way; what this removes is the explicit claim, so the deployed state matches
# what the repo now ships.
RETIRED = {"application/x-desktop"}

CONFIG_HOME = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
mime_file = os.path.join(CONFIG_HOME, "mimeapps.list")
if not os.path.exists(mime_file):
    print("0")
    raise SystemExit

# The old sweep, verbatim:
#   awk -F: '$2 ~ /^(text\/|application\/(.*(script|json|xml|yaml|toml|sql|
#            diff|patch|code|source).*))/ { print $2 }' /usr/share/mime/globs2
OLD = re.compile(
    r"^(text/|application/(.*(script|json|xml|yaml|toml|sql|diff|patch|code|source).*))")
swept = set()
try:
    with open("/usr/share/mime/globs2", encoding="utf-8") as f:
        for line in f:
            parts = line.rstrip("\n").split(":")
            if len(parts) > 1 and OLD.match(parts[1]):
                swept.add(parts[1])
except FileNotFoundError:
    pass

stale = (swept | RETIRED) - keep
if not stale:
    print("0")
    raise SystemExit

config = configparser.ConfigParser(interpolation=None, strict=False)
config.optionxform = str
try:
    config.read(mime_file, encoding="utf-8")
except Exception:
    print("0")
    raise SystemExit

removed = 0
for section in ("Default Applications", "Added Associations"):
    if not config.has_section(section):
        continue
    for m in list(config[section]):
        if m in stale:
            config.remove_option(section, m)
            removed += 1

if removed:
    tmp = mime_file + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        config.write(f, space_around_delimiters=False)
    os.replace(tmp, mime_file)

print(removed)
PY
}

set_default() {
    local category="$1" desktop="$2" name="$3"
    [[ "$desktop" == *.desktop ]] || desktop="${desktop}.desktop"
    [ -n "$name" ] || name="${desktop%.desktop}"

    local mimes=() label=""
    case "$category" in
        browser)
            mimes=("${BROWSER_MIMES[@]}"); label="Default Browser"
            # xdg-settings also teaches non-GIO callers (and the browsers'
            # own "am I default?" checks) about the change.
            command -v xdg-settings >/dev/null 2>&1 &&
                xdg-settings set default-web-browser "$desktop" 2>/dev/null || true
            ;;
        editor)
            mimes=("${EDITOR_MIMES[@]}"); label="Default Text Editor"
            prune_editor_sweep >/dev/null
            ;;
        video)  mimes=("${VIDEO_MIMES[@]}");  label="Default Video Player" ;;
        image)  mimes=("${IMAGE_MIMES[@]}");  label="Default Image Viewer" ;;
        filemanager)
            mimes=("${FILEMANAGER_MIMES[@]}"); label="Default File Explorer" ;;
        *) echo "Unknown category: $category" >&2; return 1 ;;
    esac

    apply_mime_associations "$desktop" "${mimes[@]}"

    if command -v notify-send >/dev/null 2>&1; then
        notify-send -a "Default Applications" "$label" "Set to $name" 2>/dev/null || true
    fi
}

case "${1:-}" in
    --list) list_apps 1 ;;
    --get)  list_apps 0 ;;
    --resolve)
        [ -n "${2:-}" ] || { echo "Usage: $0 --resolve <category>" >&2; exit 1; }
        resolve_path "$2"
        ;;
    --ensure-filemanager)
        id=$(ensure_filemanager_id "${2:-}")
        if [ -n "$id" ]; then
            apply_mime_associations "$id" "${FILEMANAGER_MIMES[@]}"
            echo "folders -> $id"
        fi
        ;;
    --prune)
        n=$(prune_editor_sweep)
        echo "removed $n stale association(s) written by the old globs2 sweep"
        ;;
    --set)
        [ -n "${2:-}" ] && [ -n "${3:-}" ] || {
            echo "Usage: $0 --set <browser|editor|video|image|filemanager> <desktop_id> [name]" >&2
            exit 1
        }
        set_default "$2" "$3" "${4:-}"
        ;;
    *)
        echo "Usage: $0 {--list | --get | --resolve <category> | --ensure-filemanager [cmd] | --prune | --set <category> <desktop_id> [name]}" >&2
        exit 1
        ;;
esac
