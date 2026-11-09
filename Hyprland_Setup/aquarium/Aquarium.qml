import QtQuick

// One screen's window into the tank. Give it a size and an Ocean and it fills itself:
// its own sand, scenery and bubbles, and whichever of the Ocean's fish, jellyfish, crabs
// and visitors are in its stretch of the water at the moment.
//
// The scene is laid out in "tank pixels" and scaled up by a whole number, so every
// tank pixel is the same size on screen and nothing is ever resampled. Each sprite
// is a texture the scene graph moves around; the only per-frame work on the CPU is
// the Ocean's tick and render() here copying positions onto sprites.
Item {
    id: root

    required property Ocean ocean

    // The ShellScreen this is on, if any. Only its position is read, to put this
    // screen's stretch of water in the right place among the others.
    property var screen: null
    readonly property int screenX: screen ? screen.x : 0
    readonly property int screenY: screen ? screen.y : 0

    // 270 tank pixels tall, near enough: 1080p scales by 4, 1440p by 5, 4K by 8.
    readonly property int pixelSize: Math.max(1, Math.floor(height / 270))
    readonly property int tankWidth: Math.ceil(width / pixelSize)
    readonly property int tankHeight: Math.ceil(height / pixelSize)
    readonly property int floorTop: tankHeight - 30
    readonly property bool ready: tankWidth > 0 && tankHeight > 30

    // Where this screen's water starts in the Ocean, and how much its depth is stretched,
    // if this screen is taller than the shortest. Both set by Ocean.layout().
    property int worldX: 0
    property real yScale: 1

    readonly property int surfaceFrame: Math.floor(ocean.clock / 0.4) % 3
    property bool built: false
    property bool attached: false

    // What the scenery Repeaters draw. Assigned once, in build().
    property var backWeedModel: []
    property var frontWeedModel: []
    property var decorModel: []
    property int bubbleCount: 0

    // Bubbles rise straight up, so they are this screen's own.
    property var bubbles: []
    property var vents: []

    clip: true

    function rand(a, b) { return a + Math.random() * (b - a); }
    function randInt(a, b) { return Math.floor(rand(a, b + 1)); }
    function pick(list) { return list[randInt(0, list.length - 1)]; }
    function sprite(name) { return Qt.resolvedUrl("sprites/" + name + ".png"); }

    // For Ocean.place(), which measures the sprites here.
    function fishItems() {
        const out = [];
        for (let i = 0; i < backFish.count; i++) out.push(backFish.itemAt(i));
        for (let i = 0; i < frontFish.count; i++) out.push(frontFish.itemAt(i));
        return out;
    }
    function jellyItem(i) { return jellyView.itemAt(i); }
    function crabItem(i) { return crabView.itemAt(i); }
    function sharkItem() { return sharkSprite; }
    function diverItem(pose) { return pose === "swim" ? diverSwim : diverRise; }

    function build() {
        const density = Math.max(0.6, tankWidth / 480);
        layoutScenery(density);

        bubbles = [];
        bubbleCount = Math.round(16 * density);
        for (let i = 0; i < bubbleCount; i++)
            bubbles.push({ alive: false, x: 0, y: 0, vy: 0, seed: rand(0, 6.28), timer: rand(0, 8) });

        built = true;
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

    function stepBubble(b, item) {
        const dt = ocean.dt;
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
        item.x = Math.round(b.x + Math.sin(ocean.clock * 2.2 + b.seed) * 2.4);
        item.y = Math.round(b.y);
        if (b.y < 5) {
            b.alive = false;
            // Mostly short gaps, sometimes a long one, so they come in strings.
            b.timer = Math.random() < 0.7 ? rand(0.2, 1.2) : rand(3, 11);
            item.visible = false;
        }
    }

    // Puts a creature from the Ocean on this screen, or hides it if it is elsewhere.
    // Rounded in world pixels before the offset, so a fish straddling two screens is
    // drawn on the same column by both.
    function show(c, item, y) {
        const x = Math.round(c.x) - worldX;
        const here = x + c.w > 0 && x < tankWidth;
        item.visible = here;
        if (!here)
            return;
        item.x = x;
        item.y = y;
        item.frame = c.frame;
    }

    function render() {
        if (!built || !ocean.built)
            return;
        const fish = ocean.fish;
        const back = backFish.count;
        for (let i = 0; i < fish.length; i++) {
            const f = fish[i];
            const item = i < back ? backFish.itemAt(i) : frontFish.itemAt(i - back);
            if (!item) continue;
            show(f, item, Math.round(f.drawY * yScale));
            item.flip = f.dir < 0;
        }
        for (let i = 0; i < ocean.jellies.length; i++) {
            const j = ocean.jellies[i], item = jellyView.itemAt(i);
            if (item) show(j, item, Math.round(j.y * yScale));
        }
        // The crabs walk on this screen's own sand, wherever the Ocean's floor is.
        for (let i = 0; i < ocean.crabs.length; i++) {
            const item = crabView.itemAt(i);
            if (item) show(ocean.crabs[i], item, tankHeight - 17 - item.height);
        }

        const s = ocean.shark;
        if (s.active) {
            show(s, sharkSprite, Math.round(s.drawY * yScale));
            sharkSprite.flip = s.dir < 0;
        } else {
            sharkSprite.visible = false;
        }

        // One sprite per pose; only the one it is in is shown.
        const d = ocean.diver;
        const pose = diverItem(d.pose), other = diverItem(d.pose === "swim" ? "rise" : "swim");
        other.visible = false;
        if (d.active) {
            show(d, pose, Math.round(d.drawY * yScale));
            pose.flip = d.dir < 0;
        } else {
            pose.visible = false;
        }
        for (let i = 0; i < ocean.breath.length; i++) {
            const b = ocean.breath[i], item = breathView.itemAt(i);
            if (!item) continue;
            const x = Math.round(b.x + Math.sin(ocean.clock * 2.4 + b.seed) * 1.5) - worldX;
            item.visible = b.alive && x + item.width > 0 && x < tankWidth;
            if (!item.visible) continue;
            item.x = x;
            item.y = Math.round(b.y * yScale);
        }

        for (let i = 0; i < bubbles.length; i++) stepBubble(bubbles[i], bubbleView.itemAt(i));
    }

    // Built and attached on the first real size rather than at construction, when a
    // surface can still be 0x0. A later resize just lays the Ocean out again.
    function settle() {
        if (!ready)
            return;
        if (!built)
            build();
        if (!attached) {
            attached = true;
            ocean.attach(root);
        } else {
            ocean.layout();
        }
    }

    onTankWidthChanged: settle()
    onTankHeightChanged: settle()
    onScreenXChanged: if (attached) ocean.layout()
    onScreenYChanged: if (attached) ocean.layout()
    Component.onCompleted: settle()
    Component.onDestruction: if (attached && ocean) ocean.detach(root)

    Connections {
        target: root.ocean
        function onStepped() { root.render(); }
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
            model: root.ocean.backFishModel
            PixelSprite {
                required property var modelData
                name: modelData.name
                frames: 3
                visible: false
            }
        }

        Repeater {
            model: root.backWeedModel
            PixelSprite {
                required property var modelData
                name: modelData.name
                frames: 4
                frame: Math.floor(root.ocean.clock * modelData.rate * 4 + modelData.offset) % 4
                x: Math.round(modelData.x * root.tankWidth) - 13
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
            model: root.ocean.crabModel
            PixelSprite {
                name: "crab"
                frames: 2
                visible: false
            }
        }

        Repeater {
            id: jellyView
            model: root.ocean.jellyModel
            PixelSprite {
                required property var modelData
                name: modelData.name
                frames: 3
                visible: false
            }
        }

        Repeater {
            id: frontFish
            model: root.ocean.frontFishModel
            PixelSprite {
                required property var modelData
                name: modelData.name
                frames: 3
                visible: false
            }
        }

        // The visitors: in front of every fish, behind the near weeds and the bubbles.
        PixelSprite {
            id: diverSwim
            name: "diver_swim"
            frames: 3
            visible: false
        }
        PixelSprite {
            id: diverRise
            name: "diver_rise"
            frames: 3
            visible: false
        }

        PixelSprite {
            id: sharkSprite
            name: "shark"
            frames: 3
            visible: false
        }

        Repeater {
            model: root.frontWeedModel
            PixelSprite {
                required property var modelData
                name: modelData.name
                frames: 4
                frame: Math.floor(root.ocean.clock * modelData.rate * 4 + modelData.offset) % 4
                x: Math.round(modelData.x * root.tankWidth) - 13
                y: root.tankHeight - height - modelData.sink - 4
            }
        }

        Repeater {
            id: breathView
            model: root.ocean.breathModel
            Image {
                required property var modelData
                source: root.sprite("bubble_" + modelData.size)
                visible: false
                smooth: false
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
