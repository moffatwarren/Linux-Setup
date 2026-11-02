#!/usr/bin/env python3
"""Generate the aquarium's pixel art into sprites/. Standard library only.

The PNGs are committed, so this only needs running after editing the art here.
Everything is drawn facing right; Aquarium.qml mirrors a sprite to swim left.
The output is deterministic: re-running it changes nothing unless the art does.
"""
import math
import random
import struct
import zlib
from pathlib import Path

OUT = Path(__file__).resolve().parent / "sprites"


# --- PNG and colour helpers -------------------------------------------------

def write_png(path, rows):
    h = len(rows)
    w = len(rows[0])
    raw = bytearray()
    for row in rows:
        raw.append(0)
        for px in row:
            raw.extend(px)

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )


def rgb(hex_colour):
    h = hex_colour.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def shade(c, f):
    return tuple(min(255, round(v * f)) for v in c)


CLEAR = (0, 0, 0, 0)


def blank(w, h):
    return [[CLEAR for _ in range(w)] for _ in range(h)]


def put(img, x, y, c, a=255):
    if 0 <= y < len(img) and 0 <= x < len(img[0]):
        img[y][x] = (*c, a)


def outline(img, c):
    """Add a one-pixel outline around everything opaque, inside the canvas."""
    h, w = len(img), len(img[0])
    out = [row[:] for row in img]
    for y in range(h):
        for x in range(w):
            if img[y][x][3]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and img[ny][nx][3]:
                    out[y][x] = (*c, 255)
                    break
    return out


def glow(img, colour, near=80, far=28):
    """Surround a sprite with a two-step halo. Grows the canvas by 2 on every side.

    Stepped alpha rather than a blur, so the glow is still made of whole tank pixels.
    """
    h, w = len(img), len(img[0])
    out = blank(w + 4, h + 4)
    for y in range(h + 4):
        for x in range(w + 4):
            sx, sy = x - 2, y - 2
            if 0 <= sx < w and 0 <= sy < h and img[sy][sx][3]:
                out[y][x] = img[sy][sx]
                continue
            nearest = 3
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (2, 0), (-2, 0), (0, 2), (0, -2),
                           (1, 1), (1, -1), (-1, 1), (-1, -1)):
                nx, ny = sx + dx, sy + dy
                if 0 <= nx < w and 0 <= ny < h and img[ny][nx][3]:
                    nearest = min(nearest, abs(dx) + abs(dy))
            if nearest == 1:
                out[y][x] = (*colour, near)
            elif nearest == 2 and far:
                out[y][x] = (*colour, far)
    return out


# --- Palette-mapped ASCII art -----------------------------------------------

WHITE = rgb("#ffffff")
INK = rgb("#0a0a12")


def palette(body, stripe, fin, belly=None):
    body, stripe, fin = rgb(body), rgb(stripe), rgb(fin)
    return {
        "B": body,
        "L": rgb(belly) if belly else mix(body, WHITE, 0.38),
        "D": shade(body, 0.7),
        "S": stripe,
        "T": shade(stripe, 0.7),
        "F": fin,
        "G": shade(fin, 0.7),
        # A coloured rim, not a dark line: on black water a dark outline disappears
        # and takes a pixel off every edge of the fish.
        "O": shade(body, 0.55),
        "W": WHITE,
        "K": INK,
    }


def from_ascii(art, pal):
    width = max(len(row) for row in art)
    img = blank(width, len(art))
    for y, row in enumerate(art):
        for x, ch in enumerate(row):
            if ch != ".":
                put(img, x, y, pal[ch])
    return img


def wiggle(img, tail, shift, amp):
    """Shear the tail columns vertically. Padding of `amp` rows keeps them on canvas."""
    h, w = len(img), len(img[0])
    out = blank(w, h + amp * 2)
    for x in range(w):
        offset = amp
        if x < tail:
            offset += round(shift * amp * (tail - x) / tail)
        for y in range(h):
            if img[y][x][3]:
                out[y + offset][x] = img[y][x]
    return out


FISH = {
    "clown": dict(tail=6, amp=1, art=[
        "..........OOOOO.........",
        ".........OFFGFFOO.......",
        "........OFFFGFFFFOO.....",
        ".OOO..OOBBSSBBBBSSBOO...",
        "OFFFO.OBBBSSSBBBSSBBBOO.",
        "OFGFFOBBBBSSSBBBSSBWWBBO",
        ".OGFFOBBBBSSSBBBSSBWKBBO",
        ".OGFFOBBBBSSSBBBSSBBBBBO",
        "OFGFFOLLBBSSSBBBSSBBBLLO",
        "OFFFO.OLLLSSSLLLSSLLLOO.",
        ".OOO..OOLLSSLLLLSSLOO...",
        "........OFFGOOOFFGO.....",
        ".........OOO...OOO......",
    ]),
    "tang": dict(tail=6, amp=1, art=[
        ".......OOOOOOOOOOO......",
        ".....OOFFFFFFFFFFFOO....",
        ".OO.OFFFKKKKKKKKKKFFOO..",
        "OSSOOBBKKKKKKKKKKKKBBOO.",
        "OSSSOBBBKKBBBBBBKKKKBBBO",
        ".OSSOBBBBBBBBBBBBBKBWWBO",
        ".OTSOBBBBBBBBBBBBBBBWKBO",
        ".OSSOBBBBBBBBBBBBBBBBBBO",
        "OSSSOBBBBBBBBBBBBBBBBBO.",
        "OSSOOLLLLLLLLLLLLLLLLO..",
        ".OO.OFFLLLLLLLLLLLFFO...",
        ".....OOFFFFFFFFFFFOO....",
        ".......OOOOOOOOOOO......",
    ]),
    "angel": dict(tail=5, amp=1, art=[
        "...........OO.......",
        "..........OFO.......",
        ".........OFFO.......",
        "........OFGFO.......",
        ".......OFFGFOO......",
        "......OFFGFFFFO.....",
        ".....OOBSBBSBBOO....",
        "....OBBBSBBSBBBBO...",
        "OO.OBBBBSBBSBBBWWO..",
        "OFOOBBBBSBBSBBBWKBO.",
        "OGFOBBBBSBBSBBBBBBBO",
        "OGFOBBBBSBBSBBBBBBO.",
        "OFOOLLLLSLLSLLLLLO..",
        "OO.OLLLLSLLSLLLOO...",
        "....OOLLSLLSLOO.....",
        "......OFGFFGOO......",
        ".......OFGFFO.......",
        "........OFGFO.......",
        ".........OFFO.......",
        "..........OFO.......",
        "...........OO.......",
    ]),
    "tetra": dict(tail=3, amp=1, art=[
        "....OOOOO....",
        "O..OBBBBBOOO.",
        "OOOSSSSSSSWKO",
        "OFOTTTSSSSWWO",
        "OOOLLLFFFFFLO",
        "O..OLLLFFFOO.",
        "....OOOOOO...",
    ]),
    "gold": dict(tail=9, amp=2, art=[
        "............OOOO.......",
        "OOO........OFFFFOO.....",
        "OFFOO.....OFFGFFFFOO...",
        ".OFFFOO.OOBBBBBBBBBBOO.",
        "..OGFFFOBBBBDBBBBBWWBBO",
        "...OGFFOBBBDBBBDBBWKBBO",
        "...OGGFOBBBBBBDBBBBBBBO",
        "..OGFFFOBBDBBBBBBBBBBO.",
        ".OFFFOO.OLLLLLLLLLLOO..",
        "OFFOO....OOLLLLLLOO....",
        "OOO.......OFFOOFFO.....",
        "...........OO..OO......",
    ]),
    "puffer": dict(tail=4, amp=1, art=[
        "......S...S...S....",
        ".......OOOOOOO.....",
        "....SOOBBBBBBBOOS..",
        "....OBBDBBBDBBBBO..",
        "...OBBBBBBBBBBWWBO.",
        "OO.OBBDBBBBDBBWKBO.",
        "OFOOBBBBBBBBBBWWBBO",
        "OGFOBBBDBBBBBBBBBSO",
        "OGFOLLLLLLLLLLLLBBO",
        "OFOOLLLLLLLLLLLLLO.",
        "OO.OLLLLLLLLLLLLLO.",
        "....OLLLLLLLLLLLO..",
        "...SOOLLLLLLLLOOS..",
        ".......OOOOOOO.....",
        "......S...S...S....",
    ]),
    "betta": dict(tail=12, amp=2, art=[
        "...............OOOO.........",
        "OO.............OFFFOOO......",
        "OFOO..........OFFGFFFFOO....",
        "OFFFOO.......OFFFGFFGFFFO...",
        ".OGFFFOO...OOBBBBBBBBBOOOO..",
        ".OFGFFFFOOOBBBBBBBBBBBBBBBO.",
        "..OFGGFFFFOBBDBBDBBBBBWWBBBO",
        "..OFFGFGFFOBBBBDBBDBBBWKBBBO",
        "..OFGFFGFFOBBDBBBBBBBBBBBBO.",
        ".OFGFFGFFOOLLLLLLLLLLLLOOO..",
        ".OGFFFGOO.OOFFFFFFLLLOOO....",
        "OFFFOOOO..OFFGFFGFFOO.......",
        "OFOO.....OFFGFFFGFO.........",
        "OO.......OFFFOOOFO..........",
        ".........OOO...OO...........",
    ]),
}

VARIANTS = {
    "clown": {
        "orange": palette("#ff6a00", "#ffffff", "#ffb000", "#ff9d3d"),
        "red": palette("#ff1744", "#00f0ff", "#ff6d00", "#ff6680"),
    },
    "tang": {
        "blue": palette("#1f7bff", "#fff200", "#0048ff", "#66b0ff"),
        "teal": palette("#00ffc8", "#ff2bd6", "#00b894", "#8cffe8"),
    },
    "angel": {
        "yellow": palette("#fff200", "#5a00c8", "#ff9100", "#fff98a"),
        "violet": palette("#b026ff", "#ffffff", "#7a00ff", "#dd99ff"),
    },
    "tetra": {
        "neon": palette("#00b8ff", "#00ffff", "#ff1744", "#ffffff"),
        "lime": palette("#76ff03", "#eaff00", "#ff6d00", "#f4ffcc"),
    },
    "gold": {
        "gold": palette("#ffab00", "#ffd600", "#ffd600", "#ffe57f"),
        "pearl": palette("#ff2d7a", "#ffffff", "#ffb3d1", "#ff99c2"),
    },
    "puffer": {
        "yellow": palette("#ffea00", "#fff9c4", "#ff9100", "#fffde7"),
        "green": palette("#00ff66", "#ccff90", "#00c853", "#e8ffe8"),
    },
    "betta": {
        "magenta": palette("#ff00c8", "#ffb3f0", "#a100ff", "#ff80e0"),
        "royal": palette("#2979ff", "#c7d2ff", "#ff1744", "#82b1ff"),
    },
}


def make_fish():
    for species, spec in FISH.items():
        for variant, pal in VARIANTS[species].items():
            base = from_ascii(spec["art"], pal)
            for frame, shift in enumerate((0, 1, -1)):
                img = wiggle(base, spec["tail"], shift, spec["amp"])
                write_png(OUT / f"fish_{species}_{variant}_{frame}.png", glow(img, pal["B"]))


JELLY_PAL = {
    "pink": {"B": rgb("#ff2bd6"), "L": rgb("#ffb3f0"), "D": rgb("#c4009c"), "O": rgb("#a80a8c")},
    "aqua": {"B": rgb("#00e5ff"), "L": rgb("#b3f7ff"), "D": rgb("#0091c9"), "O": rgb("#0079a8")},
}

JELLY = [
    [
        "....OOOOOOO....",
        "..OOLLLBBBBOO..",
        ".OLLBBBBBBBBBO.",
        "OLBBBDBBBDBBBBO",
        "OBBBBBBBBBBBBBO",
        "OBBDBBBDBBBDBBO",
        ".OOOOOOOOOOOOO.",
        "..D.B.D.B.D.B..",
        "..D.B.D.B.D.B..",
        ".D..B..D.B..D..",
        ".D.B...D.B..D..",
        "..D.B.D...B.D..",
        "..D.B.D...B..D.",
        "..D..B....B..D.",
    ],
    [
        "...............",
        "....OOOOOOO....",
        "..OOLLLBBBBOO..",
        ".OLBBBBBBBBBBO.",
        ".OBBBDBBBDBBBO.",
        ".OBDBBBDBBBDBO.",
        "..OOOOOOOOOOO..",
        "...D.B.D.B.D...",
        "...D.B.D.B.D...",
        "..D..B.D.B..D..",
        "..D.B..D..B.D..",
        "...D.B.D.B.D...",
        "...D.B...B.D...",
        "...............",
    ],
    [
        "...............",
        "...............",
        ".....OOOOO.....",
        "...OOLLBBBOO...",
        "..OLBBBBBBBBO..",
        "..OBBDBBBDBBO..",
        "..OBDBBDBBDBO..",
        "...OOOOOOOOO...",
        "....D.B.B.D....",
        "....D.B.B.D....",
        "....D.B.B.D....",
        "...D.B...B.D...",
        "...D.B...B.D...",
        "...............",
    ],
]

CRAB_PAL = {
    "O": rgb("#8f0020"), "B": rgb("#ff1744"), "L": rgb("#ff6e7f"),
    "D": rgb("#d4002f"), "W": WHITE, "K": INK,
}
CRAB = [
    [
        "...W......W...",
        "...K......K...",
        "OO..O....O..OO",
        "OBO.OOOOOO.OBO",
        "OLBOBLLLLBOBBO",
        ".OOBBBBBBBBOO.",
        "...OBDBBDBO...",
        "..D.OOOOOO.D..",
        ".D.D......D.D.",
    ],
    [
        "...W......W...",
        "...K......K...",
        ".OO.O....O.OO.",
        "OBBOOOOOOOOBBO",
        "OLBOBLLLLBOBBO",
        ".OOBBBBBBBBOO.",
        "...OBDBBDBO...",
        "...DOOOOOOD...",
        "..D.D....D.D..",
    ],
]

CHEST_PAL = {
    "O": rgb("#7a2a00"), "B": rgb("#c2410c"), "D": rgb("#8f2f08"), "L": rgb("#ff6a1a"),
    "S": rgb("#fff200"), "T": rgb("#ffb300"), "K": INK,
}
CHEST = [
    "...OOOOOOOOOOOOOOOO...",
    "..OLLLLSLLLLLLSLLLLO..",
    ".OLBBBBSBBBBBBSBBBBBO.",
    ".OBBBBBSBBBBBBSBBBBBO.",
    "OOSSSSSSSSSSSSSSSSSSOO",
    "OTTTTTTTTTSSTTTTTTTTTO",
    "OBBBBBBSBBSKSBSBBBBBBO",
    "OBDBBBBSBBSSSBSBBDBBBO",
    "OBBBDBBSBBBBBBSBBBBDBO",
    "ODDDDDDTDDDDDDTDDDDDDO",
    "OOOOOOOOOOOOOOOOOOOOOO",
]

BUBBLES = {
    "bubble_0": ["OO", "OO"],
    "bubble_1": [".OO.", "OL.O", "O..O", ".OO."],
    "bubble_2": ["..OOO..", ".O...O.", "OLL...O", "OL....O", "O.....O", ".O...O.", "..OOO.."],
}


def make_creatures():
    for colour, pal in JELLY_PAL.items():
        for frame, art in enumerate(JELLY):
            write_png(OUT / f"jelly_{colour}_{frame}.png", glow(from_ascii(art, pal), pal["B"]))
    for frame, art in enumerate(CRAB):
        write_png(OUT / f"crab_{frame}.png", glow(from_ascii(art, CRAB_PAL), CRAB_PAL["B"]))
    write_png(OUT / "chest.png", glow(from_ascii(CHEST, CHEST_PAL), CHEST_PAL["S"], 50, 18))
    cyan = rgb("#00e5ff")
    bubble_pal = {"O": cyan, "L": WHITE}
    for name, art in BUBBLES.items():
        write_png(OUT / f"{name}.png", glow(from_ascii(art, bubble_pal), cyan, 50, 14))


# --- Procedural scenery -----------------------------------------------------
#
# The water itself is not drawn at all: it is black, and Aquarium.qml's background
# already is. Everything here is dark or transparent except for what is meant to glow.

def make_surface():
    light = rgb("#00e5ff")
    w, h = 64, 8
    for frame in range(3):
        img = blank(w, h)
        for x in range(w):
            phase = 2 * math.pi * (x / w + frame / 3)
            y = round(3 + 1.4 * math.sin(phase) + 0.6 * math.sin(phase * 2 + 1))
            put(img, x, y - 1, light, 60)
            put(img, x, y, light)
            put(img, x, y + 1, light, 60)
            put(img, x, y + 2, light, 20)
        write_png(OUT / f"surface_{frame}.png", img)


def make_sand():
    rng = random.Random(7)
    w, h = 128, 40
    line, upper, lower = rgb("#ff2bd6"), rgb("#1c0a33"), rgb("#0b0416")
    specks = [rgb("#00e5ff"), rgb("#ff2bd6"), rgb("#b026ff"), rgb("#76ff03")]
    img = blank(w, h)
    for x in range(w):
        t = 2 * math.pi * x / w
        top = round(7 + 3 * math.sin(t) + 1.6 * math.sin(t * 3 + 0.8))
        put(img, x, top - 2, line, 22)
        put(img, x, top - 1, line, 70)
        for y in range(top, h):
            depth = y - top
            put(img, x, y, line if depth == 0 else upper if depth < 12 else lower)
    # Glints in the sand, dimmer the deeper they are.
    for _ in range(46):
        x, y = rng.randrange(w), rng.randrange(h)
        if img[y][x][3] == 255 and img[y][x][:3] != line:
            put(img, x, y, shade(rng.choice(specks), 0.75 if y < 20 else 0.45))
    write_png(OUT / "sand.png", img)


def make_far_rocks():
    # An outline only, filled with black: a dim neon skyline that leaves the water
    # black, and in which the nearer range still hides the one behind it.
    for name, col, peak, freq in (("far_0", "#3a1a8c", 58, 2), ("far_1", "#0f4a8c", 40, 3)):
        w, h = 256, 66
        colour = rgb(col)
        tops = []
        for x in range(w):
            t = 2 * math.pi * x / w
            v = (math.sin(t * freq) + 0.5 * math.sin(t * freq * 2 + 1)
                 + 0.25 * math.sin(t * freq * 5 + 2) + 1.75) / 3.5
            top = h - round(v * peak) - 2
            # Stepped rather than smooth, so the skyline reads as pixels.
            tops.append(max(0, top - top % 2))
        img = blank(w, h)
        for x in range(w):
            for y in range(tops[x], h):
                edge = y == tops[x] or y < tops[(x - 1) % w] or y < tops[(x + 1) % w]
                put(img, x, y, colour if edge else (0, 0, 0))
        write_png(OUT / f"{name}.png", img)


def make_weed():
    specs = {
        "weed_green": ("#39ff14", "#1fb30a", "#0c5204", 72, 2.2),
        "weed_teal": ("#00ffd5", "#00b396", "#005244", 52, 1.8),
        "weed_lime": ("#d4ff00", "#93b300", "#465200", 96, 2.6),
    }
    for name, (hi, lo, edge, h, amp) in specs.items():
        hi, lo, edge = rgb(hi), rgb(lo), rgb(edge)
        w = 27
        cx = w // 2
        for frame in range(4):
            img = blank(w, h)
            phase = frame * math.pi / 2
            for y in range(h):
                up = (h - 1 - y) / h
                x = cx + round(math.sin(up * 7 + phase) * amp * up * 1.6)
                put(img, x, y, hi)
                put(img, x + 1, y, lo)
                # A frond every few rows, alternating sides: two rows deep at the
                # stem and rising to a tip, so it reads as a leaf and not a thorn.
                if y % 5 == 0 and y < h - 3:
                    side = 1 if (y // 5) % 2 == 0 else -1
                    for i in range(1, 6):
                        lx = x + (i + 1 if side > 0 else -i)
                        rise = i // 2
                        put(img, lx, y - rise, hi if i < 4 else lo)
                        if i < 4:
                            put(img, lx, y - rise + 1, lo)
            write_png(OUT / f"{name}_{frame}.png", glow(outline(img, edge), hi, 45, 14))


def branch(img, rng, x, y, angle, length, width, hi, lo):
    px, py = x, y
    for i in range(length):
        px += math.cos(angle)
        py -= math.sin(angle)
        angle += rng.uniform(-0.1, 0.1)
        for off in range(width):
            put(img, round(px) + off, round(py), hi if off == 0 else lo)
    if length > 3:
        for delta in (-0.75, 0.1, 0.8):
            branch(img, rng, px, py, angle + delta + rng.uniform(-0.15, 0.15),
                   int(length * 0.68), max(2, width - 1), hi, lo)
    else:
        # A rounded tip, so the branches end in polyps rather than points.
        for off_x, off_y in ((0, -1), (1, -1), (-1, 0), (0, 0), (1, 0), (2, 0)):
            put(img, round(px) + off_x, round(py) + off_y, hi)


def make_coral():
    for name, hi, lo, edge, seed in (
        ("coral_pink", "#ff1fa8", "#c4107c", "#5c0a3b", 3),
        ("coral_orange", "#ff7a00", "#c45c00", "#5c2b00", 11),
        ("coral_violet", "#bf40ff", "#8a1fcc", "#40105c", 21),
    ):
        hi, lo, edge = rgb(hi), rgb(lo), rgb(edge)
        rng = random.Random(seed)
        img = blank(60, 44)
        branch(img, rng, 29, 43, math.pi / 2, 13, 4, hi, lo)
        write_png(OUT / f"{name}.png", glow(outline(img, edge), hi, 60, 20))

    # Brain coral: a dome with a squiggle through it.
    w, h = 30, 17
    hi, lo, edge = rgb("#fff200"), rgb("#c98a00"), rgb("#5c4d00")
    img = blank(w, h)
    for y in range(h):
        for x in range(w):
            dx, dy = (x - 14.5) / 13.5, (h - 1 - y) / 15
            if dx * dx + dy * dy <= 1:
                wave = math.sin(x * 0.9 + 2.2 * math.sin(y * 0.8))
                put(img, x, y, lo if wave > 0.35 else hi)
    write_png(OUT / "coral_brain.png", glow(outline(img, edge), hi, 60, 20))

    # Tube sponges: a cluster of open-topped columns.
    w, h = 26, 30
    hi, lo, edge, inner = rgb("#00e5ff"), rgb("#0099cc"), rgb("#004459"), rgb("#00222c")
    img = blank(w, h)
    for cx, top in ((5, 12), (12, 2), (19, 8)):
        for y in range(top, h):
            for x in range(cx - 2, cx + 3):
                put(img, x, y, hi if x <= cx - 1 else lo)
        for x in range(cx - 1, cx + 2):
            put(img, x, top, inner)
    write_png(OUT / "coral_tube.png", glow(outline(img, edge), hi, 60, 20))


def make_rocks():
    # Dark, with a lit rim: the one thing in the tank that should not compete.
    rim = rgb("#7c4dff")
    for name, w, h, base, seed in (
        ("rock_0", 46, 24, "#1e1a45", 5),
        ("rock_1", 30, 17, "#261d4d", 9),
    ):
        rng = random.Random(seed)
        c = rgb(base)
        img = blank(w, h)
        cx, rx = (w - 1) / 2, (w - 2) / 2
        for y in range(h):
            for x in range(w):
                dx, dy = (x - cx) / rx, (h - 1 - y) / (h - 2)
                bump = 0.08 * math.sin(x * 0.7 + seed)
                if dx * dx + dy * dy <= 1 + bump:
                    lit = -dx * 0.5 + dy * 0.8
                    col = mix(c, WHITE, 0.2) if lit > 0.55 else c if lit > 0.05 else shade(c, 0.72)
                    if rng.random() < 0.05:
                        col = shade(col, 0.85)
                    put(img, x, y, col)
        write_png(OUT / f"{name}.png", glow(outline(img, rim), rim, 40, 14))


# --- The lock screen's clock --------------------------------------------------

GLYPHS = {
    "0": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    "3": ["11111", "00010", "00100", "00010", "00001", "10001", "01110"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
    "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
    "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
    "colon": ["0", "1", "1", "0", "1", "1", "0"],
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
}


def make_clock_glyphs():
    # A 5x7 arcade font at 3 tank pixels per dot, cyan fading down to magenta.
    scale = 3
    top, bottom, halo = rgb("#00f0ff"), rgb("#ff2bd6"), rgb("#b026ff")
    for name, rows in GLYPHS.items():
        img = blank(len(rows[0]) * scale, len(rows) * scale)
        for row, bits in enumerate(rows):
            colour = mix(top, bottom, row / (len(rows) - 1))
            for col, bit in enumerate(bits):
                if bit == "1":
                    for dy in range(scale):
                        for dx in range(scale):
                            put(img, col * scale + dx, row * scale + dy, colour)
        write_png(OUT / f"glyph_{name}.png", glow(img, halo, 70, 24))


def main():
    OUT.mkdir(exist_ok=True)
    # Start clean, so a sprite dropped from this file does not live on in sprites/.
    for old in OUT.glob("*.png"):
        old.unlink()
    make_fish()
    make_creatures()
    make_surface()
    make_sand()
    make_far_rocks()
    make_weed()
    make_coral()
    make_rocks()
    make_clock_glyphs()
    print(f"{len(list(OUT.glob('*.png')))} sprites in {OUT}")


if __name__ == "__main__":
    main()
