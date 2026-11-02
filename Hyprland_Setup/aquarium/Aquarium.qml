import QtQuick

// A pixel-art fish tank. Self-contained: give it a size and it fills it.
//
// The scene is laid out in "tank pixels" and scaled up by a whole number, so every
// tank pixel is the same size on screen and nothing is ever resampled. Each sprite
// is a texture the scene graph moves around; the only per-frame work on the CPU is
// tick() writing positions, one 15 Hz timer's worth.
Item {
    id: root

    // Stops the whole simulation; nothing else in here runs on its own.
    property bool running: true

    // 270 tank pixels tall, near enough: 1080p scales by 4, 1440p by 5, 4K by 8.
    readonly property int pixelSize: Math.max(1, Math.floor(height / 270))
    readonly property int tankWidth: Math.ceil(width / pixelSize)
    readonly property int tankHeight: Math.ceil(height / pixelSize)
    readonly property int floorTop: tankHeight - 30

    readonly property real dt: 1 / 15
    readonly property int surfaceFrame: Math.floor(clock / 0.4) % 3
    property real clock: 0
    property bool built: false

    // What the Repeaters draw. Assigned once, in build().
    property var backFishModel: []
    property var frontFishModel: []
    property var jellyModel: []
    property var crabModel: []
    property var backWeedModel: []
    property var frontWeedModel: []
    property var decorModel: []
    property int bubbleCount: 0

    // Simulation state, parallel to the Repeaters above. Plain JS rather than
    // properties, so a tick only notifies for what actually moved on screen.
    property var fish: []
    property var jellies: []
    property var crabs: []
    property var bubbles: []
    property var vents: []

    clip: true

    function rand(a, b) { return a + Math.random() * (b - a); }
    function randInt(a, b) { return Math.floor(rand(a, b + 1)); }
    function pick(list) { return list[randInt(0, list.length - 1)]; }
    function sprite(name) { return Qt.resolvedUrl("sprites/" + name + ".png"); }

    // Roster per 480 tank pixels of width, so a wider tank is not an emptier one.
    readonly property var species: [
        { id: "clown", colours: ["orange", "red"], count: 3, speed: [12, 20], band: [0.5, 1], back: 1 },
        { id: "tang", colours: ["blue", "teal"], count: 3, speed: [14, 24], band: [0.15, 0.8], back: 1 },
        { id: "angel", colours: ["yellow", "violet"], count: 2, speed: [7, 12], band: [0.2, 0.75], back: 1 },
        { id: "gold", colours: ["gold", "pearl"], count: 3, speed: [10, 18], band: [0.1, 0.8], back: 1 },
        { id: "puffer", colours: ["yellow", "green"], count: 2, speed: [5, 9], band: [0.55, 1], back: 0 },
        { id: "betta", colours: ["magenta", "royal"], count: 2, speed: [8, 14], band: [0.1, 0.7], back: 0 },
    ]
    readonly property var schools: [
        { colour: "neon", size: 9 },
        { colour: "lime", size: 7 },
    ]

    function newFish(name, speed, band, opacity) {
        return {
            name: name, opacity: opacity, leader: null,
            base: rand(speed[0], speed[1]) * (opacity < 1 ? 0.7 : 1),
            band: band, x: 0, y: 0, v: 0, tv: 0, ty: 0, dir: Math.random() < 0.5 ? 1 : -1,
            turning: false, timer: rand(1, 6), phase: rand(0, 4), bob: rand(0, 6.28),
            offX: 0, offY: 0, w: 0, h: 0,
        };
    }

    function build() {
        const density = Math.max(0.6, tankWidth / 480);
        const roster = [];

        for (const s of species) {
            const total = Math.max(1, Math.round(s.count * density));
            for (let i = 0; i < total; i++)
                roster.push(newFish("fish_" + s.id + "_" + s.colours[i % s.colours.length],
                                    s.speed, s.band, 1));
            for (let i = 0; i < Math.round(s.back * density); i++)
                roster.push(newFish("fish_" + s.id + "_" + pick(s.colours), s.speed, s.band, 0.6));
        }

        for (const school of schools) {
            const lead = newFish("fish_tetra_" + school.colour, [16, 24], [0.1, 0.7], 1);
            roster.push(lead);
            for (let i = 1; i < school.size; i++) {
                const f = newFish(lead.name, [16, 24], lead.band, 1);
                f.leader = lead;
                f.offX = rand(-34, 8);
                f.offY = rand(-13, 13);
                roster.push(f);
            }
        }

        const back = roster.filter(f => f.opacity < 1);
        const front = roster.filter(f => f.opacity === 1);
        fish = back.concat(front);
        backFishModel = back;
        frontFishModel = front;

        jellies = [];
        for (let i = 0; i < Math.max(1, Math.round(2 * density)); i++)
            jellies.push({ name: "jelly_" + (i % 2 ? "aqua" : "pink"), x: 0, y: 0, vx: rand(-2, 2),
                           phase: rand(0, 3), rising: Math.random() < 0.5 });
        jellyModel = jellies;

        crabs = [];
        for (let i = 0; i < Math.max(1, Math.round(density)); i++)
            crabs.push({ x: rand(20, tankWidth - 40), dir: 1, timer: rand(1, 5), walking: false,
                         phase: 0 });
        crabModel = crabs;

        layoutScenery(density);

        bubbles = [];
        bubbleCount = Math.round(16 * density);
        for (let i = 0; i < bubbleCount; i++)
            bubbles.push({ alive: false, x: 0, y: 0, vy: 0, seed: rand(0, 6.28), timer: rand(0, 8) });

        built = true;
        Qt.callLater(place);
    }

    function layoutScenery(density) {
        const weeds = ["weed_green", "weed_teal", "weed_lime"];
        const scatter = (count, make) => {
            const out = [];
            for (let i = 0; i < count; i++)
                out.push(make((i + rand(0.15, 0.85)) / count));
            return out;
        };
        // The chest goes somewhere near the middle and vents bubbles. It is chosen
        // first so that nothing tall in front of it can hide it.
        const chestX = rand(0.3, 0.7);
        const clearOfChest = x => Math.abs(x - chestX) < 0.08 ? (x + 0.16) % 1 : x;

        backWeedModel = scatter(Math.round(5 * density), x => ({
            name: pick(weeds), x: x, sink: randInt(3, 9), offset: randInt(0, 3), rate: rand(0.45, 0.8),
        }));
        frontWeedModel = scatter(Math.round(2 * density), x => ({
            name: pick(weeds), x: clearOfChest(x), sink: randInt(-4, 2), offset: randInt(0, 3),
            rate: rand(0.45, 0.8),
        }));

        const props = ["coral_pink", "coral_orange", "coral_violet", "coral_brain", "coral_tube",
                       "rock_0", "rock_1"];
        // Dealt from a shuffled deck rather than picked, so a tank cannot draw five
        // of the same thing and miss the rest.
        const deck = [];
        const decor = scatter(Math.round(8 * density), x => {
            if (deck.length === 0) {
                deck.push(...props);
                for (let i = deck.length - 1; i > 0; i--) {
                    const j = randInt(0, i);
                    [deck[i], deck[j]] = [deck[j], deck[i]];
                }
            }
            return { name: deck.pop(), x: clearOfChest(x), sink: randInt(2, 11) };
        });
        decor.push({ name: "chest", x: chestX, sink: 1 });
        decorModel = decor;

        vents = [chestX * tankWidth + 11];
        for (let i = 0; i < Math.round(2 * density); i++)
            vents.push(rand(0.05, 0.95) * tankWidth);
    }

    // Scatter everything once sizes are known. Delegates exist by now, since a
    // Repeater instantiates synchronously when its model is assigned.
    function place() {
        const items = allFishItems();
        for (let i = 0; i < fish.length; i++) {
            const f = fish[i], item = items[i];
            f.w = item.width;
            f.h = item.height;
            // A leader is always earlier in the list than its followers, so a school
            // starts out together instead of spending a minute assembling itself.
            f.x = f.leader ? f.leader.x + f.offX : rand(0, Math.max(1, tankWidth - f.w));
            f.y = f.leader ? f.leader.y + f.offY : rand(bandTop(f), bandBottom(f));
            f.ty = f.y;
            f.tv = f.base;
            f.v = f.base;
        }
        for (const j of jellies) {
            j.x = rand(10, tankWidth - 30);
            j.y = rand(20, floorTop - 60);
        }
    }

    function allFishItems() {
        const out = [];
        for (let i = 0; i < backFish.count; i++) out.push(backFish.itemAt(i));
        for (let i = 0; i < frontFish.count; i++) out.push(frontFish.itemAt(i));
        return out;
    }

    function bandTop(f) { return 10 + f.band[0] * Math.max(1, floorTop - f.h - 10); }
    function bandBottom(f) { return 10 + f.band[1] * Math.max(1, floorTop - f.h - 10); }

    function stepLeader(f) {
        f.timer -= dt;
        if (f.timer <= 0) {
            f.timer = rand(2, 7);
            const mood = Math.random();
            f.tv = f.base * (mood < 0.15 ? 2.4 : mood < 0.35 ? 0.35 : 1);
            f.ty = rand(bandTop(f), bandBottom(f));
            if (Math.random() < 0.18) f.turning = true;
        }

        // Turn at the glass, letting part of the fish go past it first.
        if ((f.dir > 0 && f.x > tankWidth - f.w * 0.7) || (f.dir < 0 && f.x < -f.w * 0.3))
            f.turning = true;

        // A turn is a slow-down, a flip, and then speeding up again.
        if (f.turning && f.v < 1.5) {
            f.dir = -f.dir;
            f.turning = false;
        }

        f.v += ((f.turning ? 0 : f.tv) - f.v) * 0.1;
        f.x += f.dir * f.v * dt;
        f.y += (f.ty - f.y) * 0.012;
    }

    function stepFollower(f) {
        const l = f.leader;
        const tx = l.x - l.dir * (f.offX + 6) + (l.dir < 0 ? l.w - f.w : 0);
        const ty = l.y + f.offY;
        const gap = tx - f.x;

        f.dir = Math.abs(gap) > 7 ? Math.sign(gap) : l.dir;
        const move = Math.max(-40, Math.min(40, gap * 0.9)) * dt;
        f.x += move;
        f.y += (ty - f.y) * 0.05;
        f.v = Math.abs(move) / dt;
    }

    function stepFish(f, item) {
        if (f.leader) stepFollower(f); else stepLeader(f);

        // Tail speed follows swimming speed; the sequence is rest, up, rest, down.
        f.phase += dt * (1.6 + f.v * 0.42);
        item.frame = [0, 1, 0, 2][Math.floor(f.phase) % 4];
        item.flip = f.dir < 0;
        item.x = Math.round(f.x);
        item.y = Math.round(f.y + Math.sin(clock * 1.3 + f.bob) * 1.2);
    }

    function stepJelly(j, item) {
        // Contract and thrust upward, relax and sink. A beat lifts more than the rest
        // of the cycle sinks while rising, and less while falling; with one fixed
        // strength a jellyfish only ever goes one way and ends up pinned to an edge.
        if (j.y < 40) j.rising = false;
        if (j.y > floorTop - item.height - 30) j.rising = true;

        j.phase += dt * 0.9;
        const beat = j.phase % 3;
        item.frame = beat < 1.5 ? 0 : beat < 2 ? 1 : beat < 2.6 ? 2 : 1;
        if (beat >= 2 && beat < 2.6) j.y -= (j.rising ? 24 : 6) * dt; else j.y += 3 * dt;

        j.x += j.vx * dt;
        if (j.x < -4) j.vx = Math.abs(j.vx);
        if (j.x > tankWidth - item.width + 4) j.vx = -Math.abs(j.vx);
        item.x = Math.round(j.x);
        item.y = Math.round(j.y);
    }

    function stepCrab(c, item) {
        c.timer -= dt;
        if (c.timer <= 0) {
            c.walking = !c.walking;
            c.timer = c.walking ? rand(1.5, 5) : rand(2, 9);
            if (Math.random() < 0.5) c.dir = -c.dir;
        }
        if (c.walking) {
            c.x += c.dir * 9 * dt;
            c.phase += dt * 7;
            if (c.x < 2) { c.x = 2; c.dir = 1; }
            if (c.x > tankWidth - item.width - 2) { c.x = tankWidth - item.width - 2; c.dir = -1; }
        }
        item.frame = Math.floor(c.phase) % 2;
        item.x = Math.round(c.x);
        item.y = tankHeight - 17 - item.height;
    }

    function stepBubble(b, item) {
        if (!b.alive) {
            b.timer -= dt;
            if (b.timer > 0) return;
            b.alive = true;
            b.x = pick(vents) + rand(-3, 3);
            b.y = floorTop + rand(-4, 6);
            b.vy = rand(14, 30);
            item.visible = true;
        }
        b.y -= b.vy * dt;
        item.x = Math.round(b.x + Math.sin(clock * 2.2 + b.seed) * 2.4);
        item.y = Math.round(b.y);
        if (b.y < 5) {
            b.alive = false;
            // Mostly short gaps, sometimes a long one, so they come in strings.
            b.timer = Math.random() < 0.7 ? rand(0.2, 1.2) : rand(3, 11);
            item.visible = false;
        }
    }

    function tick() {
        clock += dt;
        const items = allFishItems();
        for (let i = 0; i < fish.length; i++) stepFish(fish[i], items[i]);
        for (let i = 0; i < jellies.length; i++) stepJelly(jellies[i], jellyView.itemAt(i));
        for (let i = 0; i < crabs.length; i++) stepCrab(crabs[i], crabView.itemAt(i));
        for (let i = 0; i < bubbles.length; i++) stepBubble(bubbles[i], bubbleView.itemAt(i));
    }

    // Built on the first real size rather than at construction, when a surface can
    // still be 0x0. A later resize re-reads the bounds in tick() and needs no rebuild.
    onTankWidthChanged: if (!built && tankWidth > 0 && tankHeight > 30) build()
    Component.onCompleted: if (!built && tankWidth > 0 && tankHeight > 30) build()

    Timer {
        interval: 66
        repeat: true
        running: root.running && root.built
        onTriggered: root.tick()
    }

    Item {
        id: tank
        width: root.tankWidth
        height: root.tankHeight
        scale: root.pixelSize
        transformOrigin: Item.TopLeft

        // The water is pure black, and nothing is drawn over it but the scenery itself.
        Rectangle {
            width: parent.width
            height: parent.height
            color: "black"
        }

        Image {
            width: parent.width
            height: 66
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 24
            source: root.sprite("far_0")
            fillMode: Image.Tile
            smooth: false
        }
        // Shifted so the two ranges' peaks do not line up, and wider by the same
        // amount so the tile still reaches the right-hand edge.
        Image {
            width: parent.width + 60
            height: 66
            x: -60
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 18
            source: root.sprite("far_1")
            fillMode: Image.Tile
            smooth: false
        }

        Repeater {
            id: backFish
            model: root.backFishModel
            PixelSprite {
                required property var modelData
                name: modelData.name
                frames: 3
                opacity: modelData.opacity
            }
        }

        Repeater {
            model: root.backWeedModel
            PixelSprite {
                required property var modelData
                name: modelData.name
                frames: 4
                frame: Math.floor(root.clock * modelData.rate * 4 + modelData.offset) % 4
                x: Math.round(modelData.x * root.tankWidth) - 15
                y: root.tankHeight - height - modelData.sink - 22
            }
        }

        Image {
            width: parent.width
            height: 40
            anchors.bottom: parent.bottom
            source: root.sprite("sand")
            fillMode: Image.Tile
            smooth: false
        }

        Repeater {
            model: root.decorModel
            Image {
                required property var modelData
                x: Math.round(modelData.x * root.tankWidth - implicitWidth / 2)
                y: root.tankHeight - implicitHeight - modelData.sink - 12
                source: root.sprite(modelData.name)
                smooth: false
            }
        }

        Repeater {
            id: crabView
            model: root.crabModel
            PixelSprite {
                name: "crab"
                frames: 2
            }
        }

        Repeater {
            id: jellyView
            model: root.jellyModel
            PixelSprite {
                required property var modelData
                name: modelData.name
                frames: 3
            }
        }

        Repeater {
            id: frontFish
            model: root.frontFishModel
            PixelSprite {
                required property var modelData
                name: modelData.name
                frames: 3
            }
        }

        Repeater {
            model: root.frontWeedModel
            PixelSprite {
                required property var modelData
                name: modelData.name
                frames: 4
                frame: Math.floor(root.clock * modelData.rate * 4 + modelData.offset) % 4
                x: Math.round(modelData.x * root.tankWidth) - 15
                y: root.tankHeight - height - modelData.sink - 4
            }
        }

        Repeater {
            id: bubbleView
            model: root.bubbleCount
            Image {
                required property int index
                source: root.sprite("bubble_" + (index % 3))
                visible: false
                smooth: false
            }
        }

        Image {
            width: parent.width
            height: 8
            source: root.sprite("surface_" + root.surfaceFrame)
            fillMode: Image.Tile
            smooth: false
        }
    }
}
