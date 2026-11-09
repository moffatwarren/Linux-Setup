import QtQuick

// The water every screen looks into. There is one simulation however many screens there
// are: they are laid side by side in the order they sit on the desk, and each
// Aquarium.qml draws its own stretch of it, so a fish that swims off one screen comes in
// on the next. Only the outermost edges are glass.
//
// Only what travels lives here: the fish, the jellyfish, the crabs, and the two visitors,
// the shark and the diver, with the diver's breath. Scenery and the vents' bubbles stay
// where they are, so each screen keeps its own.
//
// The world is measured in tank pixels, and each screen's tank pixel is its own size. A
// 1080p panel scales by 4 and a 1440p monitor by 5, so a fish grows a little as it
// crosses from one to the other. That is the cost of never resampling. If the screens
// differ in height the world takes the shortest, and a taller one spreads it over its own
// water (yScale), so every screen has fish from the surface to the sand. Equal screens
// draw it one to one.
//
// Mixing heights is not rare. floor(height / 270) gives a 1280x800 laptop a tank 400
// pixels tall, against 270 for a 1080p monitor, so aligning by the sand would leave the
// top third of the laptop empty.
Item {
    id: root

    // Stops everything. Nothing in here or in any Aquarium runs on its own.
    property bool running: true

    // How long, in seconds, before the shark first shows up, and between its visits.
    property var sharkFirst: [20, 60]
    property var sharkGap: [60, 150]
    readonly property real sharkCruise: 22
    readonly property real sharkLunge: 50

    // The same for the diver. The two visitors take turns: neither comes in while the
    // other is in the water, and each leaves the other a quiet spell after it goes.
    property var diverFirst: [45, 120]
    property var diverGap: [150, 300]

    readonly property real dt: 1 / 15
    property real clock: 0
    property bool built: false

    // Set by layout() from the screens attached to it.
    property int worldWidth: 0
    property int worldHeight: 0
    readonly property int floorTop: worldHeight - 30

    // What the Aquariums' Repeaters draw. Reassigned only by build().
    property var backFishModel: []
    property var frontFishModel: []
    property var jellyModel: []
    property var crabModel: []

    // Simulation state, parallel to those models. Plain JS rather than properties, so a
    // tick notifies nothing; each Aquarium copies what it needs onto its sprites.
    property var fish: []
    property var jellies: []
    property var crabs: []
    property var shark: ({ active: false, wait: 0, x: 0, y: 0, ty: 0, dir: 1, v: 0, burst: 0,
                           rest: 0, timer: 0, turns: 0, turning: false, phase: 0, frame: 0,
                           drawY: 0, w: 0, h: 0 })
    // The diver is tracked by its centre, because its two poses are different shapes:
    // x, y, w and h are the current pose's box, worked out from it each tick.
    property var diver: ({ active: false, wait: 0, mode: "", pose: "rise", cx: 0, cy: 0,
                           tx: 0, ty: 0, dir: 1, v: 0, legs: 0, timer: 0, breath: 0, puffs: 0,
                           puffGap: 0, phase: 0, frame: 0, x: 0, y: 0, drawY: 0, w: 0, h: 0,
                           swimW: 0, swimH: 0, riseW: 0, riseH: 0 })
    // The diver's exhaled bubbles: a fixed pool, so no Repeater ever has to grow.
    property var breath: []
    property var breathModel: []

    // The Aquariums drawing this water, and how many there were when the fish were dealt.
    property var views: []
    property int builtFor: 0

    // After every tick, and once after place(). Each Aquarium redraws on it.
    signal stepped()

    function rand(a, b) { return a + Math.random() * (b - a); }
    function randInt(a, b) { return Math.floor(rand(a, b + 1)); }
    function pick(list) { return list[randInt(0, list.length - 1)]; }
    function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }

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

    // --- Screens ------------------------------------------------------------------

    function attach(view) {
        if (views.indexOf(view) < 0)
            views = views.concat([view]);
        layout();
    }

    function detach(view) {
        if (views.indexOf(view) < 0)
            return;
        views = views.filter(v => v !== view);
        layout();
    }

    // Left to right by where the screens are, then top to bottom for a stack, which is
    // treated as if it stood side by side: still one tank, just not a picture of the desk.
    function layout() {
        const order = views.slice().sort((a, b) => a.screenX - b.screenX || a.screenY - b.screenY);
        let width = 0, height = 0;
        for (const v of order) {
            v.worldX = width;
            width += v.tankWidth;
            height = height === 0 ? v.tankHeight : Math.min(height, v.tankHeight);
        }
        // From the surface to the sand, the shortest screen's water onto each one's own.
        for (const v of order)
            v.yScale = (v.tankHeight - 30) / Math.max(1, height - 30);

        const resized = width !== worldWidth || height !== worldHeight;
        worldWidth = width;
        worldHeight = height;
        if (order.length === 0)
            return;

        // A screen coming or going changes how many fish the water should hold, so they
        // are dealt again; a resize with the same screens only moves the glass. Deferred,
        // because the screens of a lock arrive one at a time, a few milliseconds apart.
        if (!built || order.length !== builtFor)
            settle.restart();
        else if (resized)
            keepInside();
    }

    Timer {
        id: settle
        interval: 150
        onTriggered: if (root.views.length > 0 && root.worldHeight > 60) root.build()
    }

    // --- Building -----------------------------------------------------------------

    function newFish(name, speed, band, far) {
        return {
            name: far ? name + "_far" : name, far: far, leader: null,
            base: rand(speed[0], speed[1]) * (far ? 0.7 : 1),
            band: band, x: 0, y: 0, v: 0, tv: 0, ty: 0, dir: Math.random() < 0.5 ? 1 : -1,
            turning: false, timer: rand(1, 6), phase: rand(0, 4), bob: rand(0, 6.28),
            offX: 0, offY: 0, w: 0, h: 0, frame: 0, drawY: 0,
            panic: 0, fleeDir: 0, fleeUp: false,
        };
    }

    function build() {
        built = false;
        builtFor = views.length;
        const density = Math.max(0.6, worldWidth / 480);
        const roster = [];

        for (const s of species) {
            const total = Math.max(1, Math.round(s.count * density));
            for (let i = 0; i < total; i++)
                roster.push(newFish("fish_" + s.id + "_" + s.colours[i % s.colours.length],
                                    s.speed, s.band, false));
            for (let i = 0; i < Math.round(s.back * density); i++)
                roster.push(newFish("fish_" + s.id + "_" + pick(s.colours), s.speed, s.band, true));
        }

        // Two schools per screen's worth of water, as each screen had when it was its own tank.
        for (let round = 0; round < Math.max(1, Math.round(density)); round++) {
            for (const school of schools) {
                const lead = newFish("fish_tetra_" + school.colour, [16, 24], [0.1, 0.7], false);
                roster.push(lead);
                for (let i = 1; i < school.size; i++) {
                    const f = newFish(lead.name, [16, 24], lead.band, false);
                    f.leader = lead;
                    f.offX = rand(-34, 8);
                    f.offY = rand(-13, 13);
                    roster.push(f);
                }
            }
        }

        const back = roster.filter(f => f.far);
        const front = roster.filter(f => !f.far);
        fish = back.concat(front);
        backFishModel = back;
        frontFishModel = front;

        jellies = [];
        for (let i = 0; i < Math.max(1, Math.round(2 * density)); i++)
            jellies.push({ name: "jelly_" + (i % 2 ? "aqua" : "pink"), x: 0, y: 0, vx: rand(-2, 2),
                           phase: rand(0, 3), rising: Math.random() < 0.5, frame: 0, w: 0, h: 0 });
        jellyModel = jellies;

        crabs = [];
        for (let i = 0; i < Math.max(1, Math.round(density)); i++)
            crabs.push({ x: rand(20, worldWidth - 40), dir: 1, timer: rand(1, 5), walking: false,
                         phase: 0, frame: 0, w: 0 });
        crabModel = crabs;

        breath = [];
        // Enough for three breaths on their way up from the bottom at once.
        for (let i = 0; i < 20; i++)
            breath.push({ alive: false, x: 0, y: 0, vy: 0, seed: rand(0, 6.28), size: [0, 1, 0, 1, 2][i % 5] });
        breathModel = breath;

        Qt.callLater(place);
    }

    // Scatter everything once sizes are known. Every screen draws the same sprites, so
    // any one of them can be measured; their Repeaters filled in as the models were set.
    function place() {
        const view = views[0];
        if (!view)
            return;
        const items = view.fishItems();
        for (let i = 0; i < fish.length; i++) {
            const f = fish[i];
            f.w = items[i].width;
            f.h = items[i].height;
            // A leader is always earlier in the list than its followers, so a school
            // starts out together instead of spending a minute assembling itself.
            f.x = f.leader ? f.leader.x + f.offX : rand(0, Math.max(1, worldWidth - f.w));
            f.y = f.leader ? f.leader.y + f.offY : rand(bandTop(f), bandBottom(f));
            f.ty = f.y;
            f.tv = f.base;
            f.v = f.base;
        }
        for (let i = 0; i < jellies.length; i++) {
            const j = jellies[i], item = view.jellyItem(i);
            j.w = item.width;
            j.h = item.height;
            j.x = rand(10, worldWidth - 30);
            j.y = rand(20, floorTop - 60);
        }
        for (let i = 0; i < crabs.length; i++)
            crabs[i].w = view.crabItem(i).width;

        shark.w = view.sharkItem().width;
        shark.h = view.sharkItem().height;
        shark.active = false;
        shark.wait = rand(sharkFirst[0], sharkFirst[1]);

        diver.swimW = view.diverItem("swim").width;
        diver.swimH = view.diverItem("swim").height;
        diver.riseW = view.diverItem("rise").width;
        diver.riseH = view.diverItem("rise").height;
        diver.active = false;
        diver.wait = rand(diverFirst[0], diverFirst[1]);

        built = true;
        stepped();
    }

    // The glass moved under everything: put back anything now outside it.
    function keepInside() {
        for (const f of fish) {
            f.x = clamp(f.x, -f.w * 0.3, worldWidth - f.w * 0.7);
            f.y = clamp(f.y, 8, Math.max(8, floorTop - f.h));
            f.ty = clamp(f.ty, 8, Math.max(8, floorTop - f.h));
        }
        for (const j of jellies) {
            j.x = clamp(j.x, -4, worldWidth - j.w + 4);
            j.y = clamp(j.y, 20, Math.max(20, floorTop - j.h - 30));
        }
        for (const c of crabs)
            c.x = clamp(c.x, 2, worldWidth - c.w - 2);
        if (diver.active) {
            const margin = diver.swimW / 2 + 6;
            diver.cx = clamp(diver.cx, margin, worldWidth - margin);
            diver.tx = clamp(diver.tx, margin, worldWidth - margin);
        }
    }

    // Brings a visitor in now, or as soon as the other one has gone. For the previews.
    function summonShark() {
        if (built && !shark.active)
            shark.wait = 0;
    }
    function summonDiver() {
        if (built && !diver.active)
            diver.wait = 0;
    }

    // --- Fish ---------------------------------------------------------------------

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
        if ((f.dir > 0 && f.x > worldWidth - f.w * 0.7) || (f.dir < 0 && f.x < -f.w * 0.3))
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
        // Kept out of the sand: a leader that fled to the floor has its school below it.
        f.y += (clamp(ty, 8, floorTop - f.h) - f.y) * 0.05;
        f.v = Math.abs(move) / dt;
    }

    // Whether the shark is close enough to frighten this fish, and if so, which way is
    // away. The zone reaches much further in front of the shark than behind it, so fish
    // scatter ahead of it and close up again in its wake.
    function scare(f) {
        const s = shark;
        if (!s.active)
            return;
        const dx = f.x + f.w / 2 - (s.x + s.w / 2);
        const dy = f.y + f.h / 2 - (s.y + s.h / 2);
        const rx = s.w / 2 + (Math.sign(dx) === s.dir ? 70 : 24);
        const ry = s.h / 2 + 30;
        if ((dx * dx) / (rx * rx) + (dy * dy) / (ry * ry) > 1)
            return;

        const away = dx < 0 ? -1 : 1;
        const up = dy < 0;
        // A new target only when the way out changes, or the fish would twitch on the spot.
        if (f.panic <= 0 || away !== f.fleeDir || up !== f.fleeUp) {
            f.fleeDir = away;
            f.fleeUp = up;
            f.ty = clamp(f.y + (up ? -1 : 1) * rand(24, 44), 8, Math.max(8, floorTop - f.h));
        }
        f.panic = rand(1.2, 2.2);
    }

    // The diver frightens nobody, but the fish keep their distance: one that finds itself
    // close turns away at its own pace and moves up or down out of the diver's level. A
    // school goes where its leader goes, and the fish at the back of the tank are further
    // away than they look, so neither is moved directly.
    function shy(f) {
        const d = diver;
        if (!d.active || f.leader || f.far)
            return;
        const dx = f.x + f.w / 2 - d.cx;
        const dy = f.y + f.h / 2 - d.cy;
        const rx = d.w / 2 + 22, ry = d.h / 2 + 16;
        if ((dx * dx) / (rx * rx) + (dy * dy) / (ry * ry) > 1)
            return;
        f.ty = clamp(d.cy + (dy < 0 ? -1 : 1) * (ry + 4) - f.h / 2, 8, Math.max(8, floorTop - f.h));
        // On top of the leader's own slow drift, or a puffer the diver swims up to is
        // still sitting on its head when it arrives.
        f.y += (f.ty - f.y) * 0.04;
        if (f.dir !== (dx < 0 ? -1 : 1))
            f.turning = true;
    }

    // A frightened fish darts: it flips on the spot instead of slowing down to turn,
    // swims faster than it ever does otherwise, and leaves its band and its school. Once
    // the panic wears off a school fish finds its place again by itself.
    function flee(f) {
        f.panic -= dt;
        f.dir = f.fleeDir;
        f.turning = false;
        f.v += (28 + f.base * 1.3 - f.v) * 0.3;
        f.x += f.dir * f.v * dt;
        // Cornered against the glass, it stays in the tank and gets out of the way by depth.
        // The glass also takes its speed, or it would glide off the screen when the panic ends.
        const held = clamp(f.x, -f.w * 0.3, worldWidth - f.w * 0.7);
        if (held !== f.x) {
            f.x = held;
            f.v = Math.min(f.v, 4);
        }
        f.y += (f.ty - f.y) * 0.08;
        if (f.panic <= 0) {
            f.tv = f.base;
            f.timer = rand(0.5, 2);
        }
    }

    function stepFish(f) {
        scare(f);
        if (f.panic <= 0) shy(f);
        if (f.panic > 0) flee(f);
        else if (f.leader) stepFollower(f);
        else stepLeader(f);

        // Tail speed follows swimming speed; the sequence is rest, up, rest, down.
        f.phase += dt * (1.6 + f.v * 0.42);
        f.frame = [0, 1, 0, 2][Math.floor(f.phase) % 4];
        f.drawY = f.y + Math.sin(clock * 1.3 + f.bob) * 1.2;
    }

    // --- Everything else that moves -----------------------------------------------

    function stepJelly(j) {
        // Contract and thrust upward, relax and sink. A beat lifts more than the rest
        // of the cycle sinks while rising, and less while falling; with one fixed
        // strength a jellyfish only ever goes one way and ends up pinned to an edge.
        if (j.y < 40) j.rising = false;
        if (j.y > floorTop - j.h - 30) j.rising = true;

        j.phase += dt * 0.9;
        const beat = j.phase % 3;
        j.frame = beat < 1.5 ? 0 : beat < 2 ? 1 : beat < 2.6 ? 2 : 1;
        if (beat >= 2 && beat < 2.6) j.y -= (j.rising ? 24 : 6) * dt; else j.y += 3 * dt;

        j.x += j.vx * dt;
        if (j.x < -4) j.vx = Math.abs(j.vx);
        if (j.x > worldWidth - j.w + 4) j.vx = -Math.abs(j.vx);
    }

    function stepCrab(c) {
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
            if (c.x > worldWidth - c.w - 2) { c.x = worldWidth - c.w - 2; c.dir = -1; }
        }
        c.frame = Math.floor(c.phase) % 2;
    }

    // --- The shark ----------------------------------------------------------------
    //
    // It is a visitor, not a resident: it waits off to one side, cruises in through the
    // glass, crosses the whole width of every screen, and leaves by the far side. It
    // never catches anything. It does drift towards the nearest fish ahead and now and
    // then lunges, which is what sends them scattering.

    function sharkTop() { return 16; }
    function sharkBottom() { return Math.max(16, floorTop - shark.h - 4); }

    function enterShark(s) {
        s.active = true;
        s.dir = Math.random() < 0.5 ? 1 : -1;
        s.x = s.dir > 0 ? -s.w - 4 : worldWidth + 4;
        s.y = rand(sharkTop(), sharkBottom());
        s.ty = s.y;
        s.v = sharkCruise;
        s.burst = 0;
        s.rest = rand(2, 5);
        s.timer = rand(3, 7);
        s.turns = Math.random() < 0.35 ? 1 : 0;
        s.turning = false;
    }

    // The near fish closest in front of its snout, if any is within reach. Fish at the
    // back of the tank are further away than they look, so it does not go after them;
    // they still flee from it.
    function preyFor(s) {
        const snout = s.x + (s.dir > 0 ? s.w : 0);
        const mid = s.y + s.h / 2;
        let best = null, bestScore = Infinity;
        for (const f of fish) {
            if (f.far)
                continue;
            const ahead = (f.x + f.w / 2 - snout) * s.dir;
            const off = Math.abs(f.y + f.h / 2 - mid);
            if (ahead < 0 || ahead > 110 || off > 50)
                continue;
            if (ahead + off * 2 < bestScore) {
                bestScore = ahead + off * 2;
                best = f;
            }
        }
        return best;
    }

    function stepShark(s) {
        if (!s.active) {
            s.wait -= dt;
            if (s.wait <= 0 && !diver.active)
                enterShark(s);
            return;
        }

        s.timer -= dt;
        if (s.timer <= 0) {
            s.timer = rand(3, 7);
            s.ty = rand(sharkTop(), sharkBottom());
            // At most one change of mind a visit, and only well inside the tank, so it
            // never doubles back out through the glass it came in by.
            const inside = s.x > worldWidth * 0.25 && s.x + s.w < worldWidth * 0.75;
            if (s.turns > 0 && inside && Math.random() < 0.35) {
                s.turning = true;
                s.turns--;
            }
        }

        const prey = s.turning ? null : preyFor(s);
        if (prey) {
            s.ty = clamp(prey.y + prey.h / 2 - s.h / 2, sharkTop(), sharkBottom());
            if (s.burst <= 0 && s.rest <= 0 && Math.random() < 0.04) {
                s.burst = rand(0.7, 1.3);
                s.rest = rand(5, 10);
            }
        }
        s.burst -= dt;
        s.rest -= dt;

        // A turn is a long glide down to a crawl and a flip; a fish's stops dead.
        const target = s.turning ? 0 : s.burst > 0 ? sharkLunge : sharkCruise;
        s.v += (target - s.v) * (s.burst > 0 ? 0.25 : 0.05);
        if (s.turning && s.v < 6) {
            s.dir = -s.dir;
            s.turning = false;
        }
        s.x += s.dir * s.v * dt;
        s.y += (s.ty - s.y) * (s.burst > 0 ? 0.05 : 0.02);

        s.phase += dt * (1 + s.v * 0.12);
        s.frame = [0, 1, 0, 2][Math.floor(s.phase) % 4];
        s.drawY = s.y + Math.sin(clock * 0.7) * 1.5;

        if ((s.dir > 0 && s.x > worldWidth + 8) || (s.dir < 0 && s.x < -s.w - 8))
            leave(s, sharkGap, diver);
    }

    // A visitor going leaves the other one a quiet spell before it can come in. And if the
    // other has been kept waiting, it goes next, or a visitor with the shorter gap could
    // come back every time before the other ever got in.
    function leave(visitor, gap, other) {
        visitor.active = false;
        visitor.wait = rand(gap[0], gap[1]);
        const overdue = other.wait <= 0;
        other.wait = Math.max(other.wait, rand(10, 25));
        if (overdue)
            visitor.wait = Math.max(visitor.wait, other.wait + rand(20, 40));
    }

    // --- The diver ----------------------------------------------------------------
    //
    // The other visitor. It sinks in feet first through the surface somewhere along the
    // tank, swims two or three short legs with a pause to look about after each, then
    // rises straight back out. It breathes out a string of bubbles every few seconds.
    // Upright on the way down and up, flat while it swims.

    function setPose(d, pose) {
        d.pose = pose;
        d.w = pose === "swim" ? d.swimW : d.riseW;
        d.h = pose === "swim" ? d.swimH : d.riseH;
    }

    // The range its centre keeps to while it swims: clear of the surface and of the sand.
    function diverTop() { return 14 + diver.riseH / 2; }
    function diverBottom() { return Math.max(diverTop(), floorTop - diver.swimH / 2 - 6); }

    function enterDiver(d) {
        const margin = d.swimW / 2 + 6;
        d.active = true;
        setPose(d, "rise");
        d.mode = "down";
        d.cx = rand(margin, Math.max(margin, worldWidth - margin));
        d.cy = -d.riseH / 2 - 2;
        d.ty = rand(diverTop(), diverTop() + (diverBottom() - diverTop()) * 0.6);
        d.dir = Math.random() < 0.5 ? 1 : -1;
        d.v = 0;
        d.legs = randInt(2, 3);
        d.breath = rand(1, 3);
        d.puffs = 0;
    }

    function nextLeg(d) {
        const margin = d.swimW / 2 + 6;
        let dir = Math.random() < 0.5 ? 1 : -1;
        // Turned round rather than sent into the glass.
        if (d.cx + dir * 70 > worldWidth - margin || d.cx + dir * 70 < margin)
            dir = -dir;
        d.tx = clamp(d.cx + dir * rand(60, 180), margin, Math.max(margin, worldWidth - margin));
        d.ty = rand(diverTop(), diverBottom());
        d.dir = d.tx === d.cx ? d.dir : Math.sign(d.tx - d.cx);
        d.mode = "swim";
        d.v = 0;
    }

    function exhale(d) {
        const b = breath.find(one => !one.alive);
        if (!b)
            return;
        b.alive = true;
        // From the regulator, which is at the front of the head in either pose.
        b.x = d.cx + d.dir * (d.pose === "swim" ? d.w / 2 - 3 : 4);
        b.y = d.pose === "swim" ? d.cy - 2 : d.cy - d.h / 2 + 6;
        b.vy = rand(16, 26);
    }

    function stepDiver(d) {
        if (!d.active) {
            d.wait -= dt;
            if (d.wait <= 0 && !shark.active)
                enterDiver(d);
            return;
        }

        if (d.mode === "down") {
            // Sinks steadily, and settles gently at the depth it wants.
            d.cy += clamp((d.ty - d.cy) * 0.5, 2, 11) * dt;
            if (d.cy >= d.ty - 0.5) {
                setPose(d, "swim");
                d.mode = "hover";
                d.timer = rand(1, 2.5);
            }
        } else if (d.mode === "swim") {
            const gap = d.tx - d.cx;
            d.v += (Math.min(10, Math.abs(gap) * 0.8 + 1) - d.v) * 0.06;
            d.cx += Math.sign(gap) * Math.min(Math.abs(gap), d.v * dt);
            d.cy += (d.ty - d.cy) * 0.02;
            if (Math.abs(gap) < 1) {
                d.mode = "hover";
                d.timer = rand(2, 5);
            }
        } else if (d.mode === "hover") {
            d.v *= 0.9;
            d.timer -= dt;
            if (d.timer <= 0) {
                if (d.legs > 0) {
                    d.legs--;
                    nextLeg(d);
                } else {
                    setPose(d, "rise");
                    d.mode = "up";
                    d.v = 0;
                }
            }
        } else if (d.mode === "up") {
            d.v += (9 - d.v) * 0.04;
            d.cy -= d.v * dt;
            if (d.cy < -d.h / 2 - 4)
                leave(d, diverGap, shark);
        }

        // A breath every few seconds, let out as a short string of bubbles.
        d.breath -= dt;
        if (d.breath <= 0 && d.cy > 12) {
            d.puffs = randInt(3, 5);
            d.puffGap = 0;
            d.breath = rand(3, 5);
        }
        if (d.puffs > 0) {
            d.puffGap -= dt;
            if (d.puffGap <= 0) {
                exhale(d);
                d.puffs--;
                d.puffGap = rand(0.1, 0.25);
            }
        }

        // The kick is slow drifting down, slower still hovering, and quick swimming or rising.
        d.phase += dt * (d.mode === "down" ? 0.7 : d.mode === "hover" ? 1.1 : 2.4);
        d.frame = [0, 1, 0, 2][Math.floor(d.phase) % 4];
        d.x = d.cx - d.w / 2;
        d.y = d.cy - d.h / 2;
        d.drawY = d.y + (d.mode === "hover" || d.mode === "swim" ? Math.sin(clock * 1.1) * 1.2 : 0);
    }

    function stepBreath(b) {
        if (!b.alive)
            return;
        b.y -= b.vy * dt;
        if (b.y < 6)
            b.alive = false;
    }

    function tick() {
        clock += dt;
        stepShark(shark);
        stepDiver(diver);
        for (const b of breath) stepBreath(b);
        for (const f of fish) stepFish(f);
        for (const j of jellies) stepJelly(j);
        for (const c of crabs) stepCrab(c);
        stepped();
    }

    Timer {
        interval: 66
        repeat: true
        running: root.running && root.built
        onTriggered: root.tick()
    }
}
