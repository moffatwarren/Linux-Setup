// Pip: a little pixel critter living under the agents list, keeping an eye on them.
//
//   an agent needs you     comes to the glass and knocks, saying who
//   an agent is done       dances under confetti until you look at it
//   anything working       potters about
//   nothing going on       wanders, blinks, watches you
//   you are away           naps (screen locked, or no input for 5 minutes),
//                          and says hello when you are back
//
// Click it to go to the agent that wants you; otherwise clicking pets it.
// `herdr-app do pip.demo-knock` (demo-party, demo-sleep, demo-off) shows a mood
// without waiting for an agent.
//
// Herdr's own agent status drives all of it (`agents()`; "done" turns "idle"
// once you look), so nothing has to tell Pip anything. It is drawn from
// rectangles in the theme's colours, so it follows the theme, and every motion
// is native (.loop / .transition): the timers below only make decisions.

import { View, div } from "gpui-kit";
import { h_flex, v_flex } from "gpui-base";
import { agents, run, theme, exec, readTextFile, nextCommand } from "herdr";

// ---- the sprite --------------------------------------------------------------
// '.' empty, 'b' body, 'c' cheek / inner ear. The face is carved in as 'o'
// (empty too), so the eyes show whatever is behind Pip.
const BODY = [
  "..bb......bb..",
  "..bcb....bcb..",
  "..bbbbbbbbbb..",
  ".bbbbbbbbbbbb.",
  ".bbbbbbbbbbbb.",
  ".bbbbbbbbbbbb.",
  ".bbbbbbbbbbbb.",
  ".bbbbbbbbbbbb.",
  "..bbbbbbbbbb..",
  "...bb....bb...",
];
const PAW = ["b.b.b", ".....", ".bbb.", ".bbb."];
const SW = BODY[0].length;
const SH = BODY.length;

function sprite({ eyes = "open", mouth = "small", look = 0, facing = 1, wag = false, lying = false }) {
  const g = BODY.map((r) => r.split(""));
  const hole = (r, c) => {
    if (g[r] && g[r][c] && g[r][c] !== ".") g[r][c] = "o";
  };
  const er = 4, mr = 6, m0 = 6 + look, m1 = m0 + 1;
  for (const c of [2 + look, 3 + look, 10 + look, 11 + look]) if (g[mr][c] === "b") g[mr][c] = "c";
  for (const c of [4 + look, 9 + look]) {
    if (eyes === "open") { hole(er, c); hole(er + 1, c); }
    else if (eyes === "blink") hole(er + 1, c);
    else if (eyes === "closed") { hole(er + 1, c - 1); hole(er + 1, c); hole(er + 1, c + 1); }
    else if (eyes === "happy") { hole(er, c); hole(er + 1, c - 1); hole(er + 1, c + 1); }
    else if (eyes === "wide") { hole(er - 1, c); hole(er, c); hole(er + 1, c); }
  }
  if (mouth === "small") { hole(mr, m0); hole(mr, m1); }
  else if (mouth === "smile") { hole(mr, m0 - 1); hole(mr, m1 + 1); hole(mr + 1, m0); hole(mr + 1, m1); }
  else if (mouth === "open") { hole(mr, m0); hole(mr, m1); hole(mr + 1, m0); hole(mr + 1, m1); }
  const tail = facing > 0 ? 0 : SW - 1;
  for (const r of wag ? [4, 5] : [5, 6]) g[r][tail] = "b";
  return lying ? g.slice(0, -1) : g;
}

// A grid as rectangles: one per run of a colour in a row, not one per pixel.
function pixels(grid, colors, px, key) {
  const out = [];
  grid.forEach((row, r) => {
    let c = 0;
    while (c < row.length) {
      const ch = row[c];
      if (ch === "." || ch === "o") { c++; continue; }
      let e = c;
      while (e < row.length && row[e] === ch) e++;
      out.push(div().id(`${key}-${r}-${c}`).absolute().left(c * px).top(r * px).w((e - c) * px).h(px).bg(colors[ch]));
      c = e;
    }
  });
  return out;
}

// ---- small helpers -------------------------------------------------------------
const rand = (a, b) => a + Math.random() * (b - a);
const pick = (list) => list[Math.floor(Math.random() * list.length)];
const hex2 = (n) => Number(n).toString(16).padStart(2, "0");
// "Claude Code" -> "Claude": the bubble is narrow.
const who = (a) => (a.program?.name ?? "agent").split(" ")[0];
const unique = (list) => [...new Set(list)];

const BLOCK_H = 112;   // keep in step with the "pip" block's px in the layout

export default class Pip extends View {
  init(_props, cx) {
    this.w = 268;
    this.h = BLOCK_H;
    this.x = null;               // left edge of the critter, in px
    this.facing = 1;
    this.walkUntil = 0;
    this.walkMs = 0;
    this.nextMove = Date.now() + 2500;
    this.blink = false;
    this.nextBlink = Date.now() + 3000;
    this.bubble = null;          // { title, sub, color, until }
    this.petUntil = 0;
    this.hearts = [];            // one-shot particles: { id, x, y, phase }
    this.confetti = [];
    this.burstAt = 0;
    this.ids = 0;
    this.mode = null;
    this.away = false;
    this.awaySince = 0;
    this.watch = null;           // { idle, guard, key } once known

    if (!localStorage.getItem("met")) {
      localStorage.setItem("met", "1");
      this.say("hi! I'm Pip", "I'll keep an eye on your agents", null, 5000);
    }
    cx.timer.every(500, (cx) => this.tick(cx));
    cx.spawn(async (cx) => this.setupAway(cx));
    cx.spawn(async (cx) => {
      for (;;) {
        const c = await nextCommand();
        if (c.startsWith("demo-")) {
          this.demo = c === "demo-off" ? null : c.slice(5);
          cx.notify();
        }
      }
    });
  }

  say(title, sub = null, color = null, ms = 3000) {
    this.bubble = { title, sub, color, until: Date.now() + ms };
  }

  // ---- away: screen locked, or no input for 5 minutes ----------------------------

  async setupAway(cx) {
    try {
      const r = await exec("sh", ["-c", 'printf "%s\\n%s" "$XDG_RUNTIME_DIR" "$WAYLAND_DISPLAY"']);
      const [rt, wd] = r.stdout.split("\n");
      if (!rt) return;
      // hypridle.conf keeps this marker while you have not touched anything for 5 minutes.
      // lock.sh holds an flock on the guard for the whole of a lock (its hyprlock
      // fallback too); the kernel drops it if the script dies, so nothing goes stale.
      this.watch = { idle: `${rt}/pip.idle`, guard: `${rt}/aquarium-lock-${wd || "wayland"}.guard`, key: null, keyAt: 0 };
    } catch {
      return;
    }
    cx.timer.every(2000, (cx) => cx.spawn(async (cx) => this.checkAway(cx)));
  }

  // Locked is read from /proc/locks -- NEVER by taking the flock. A probe holding
  // it at the instant lock.sh starts makes lock.sh believe a lock is already up,
  // and it exits without locking the screen.
  async locked() {
    const w = this.watch;
    const now = Date.now();
    if (!w.key || now - w.keyAt > 60000) {
      w.keyAt = now;
      try {
        const s = await exec("stat", ["-c", "%Hd %Ld %i", w.guard]);
        const [maj, min, ino] = s.stdout.trim().split(" ");
        w.key = s.code === 0 ? `${hex2(maj)}:${hex2(min)}:${ino} ` : null;
      } catch {
        w.key = null;
      }
    }
    if (!w.key) return false;
    let locks = await readTextFile("/proc/locks");
    if (!locks) locks = (await exec("cat", ["/proc/locks"])).stdout;
    return locks.split("\n").some((l) => l.includes(" FLOCK ") && l.includes(w.key));
  }

  async checkAway(cx) {
    let away;
    try {
      away = (await readTextFile(this.watch.idle)) !== null || (await this.locked());
    } catch {
      return;
    }
    if (away === this.away) return;
    this.away = away;
    const now = Date.now();
    if (away) {
      this.awaySince = now;
      this.bubble = null;
    } else {
      // Back. Anything an agent did meanwhile is still on show (done stays done
      // until you look), so this is only the hello.
      const gone = now - this.awaySince;
      if (gone > 5000) this.say(gone > 15 * 60000 ? "missed you!" : pick(["welcome back!", "hi again!"]));
      this.hop(now);
    }
    cx.notify();
  }

  // ---- decisions ------------------------------------------------------------------

  hop(now) {
    this.petUntil = Math.max(this.petUntil, now + 700);
  }

  tick(cx) {
    const now = Date.now();
    let dirty = false;
    const sw = SW * this.px();

    if (this.bubble && now > this.bubble.until) { this.bubble = null; dirty = true; }
    if (this.petUntil && now > this.petUntil) { this.petUntil = 0; dirty = true; }
    if (this.walkUntil && now > this.walkUntil) { this.walkUntil = 0; dirty = true; }

    const before = this.hearts.length + this.confetti.length;
    this.hearts = this.hearts.filter((p) => now - p.born < 1600);
    this.confetti = this.confetti.filter((p) => now - p.born < 7000);
    if (this.hearts.length + this.confetti.length !== before) dirty = true;

    if (this.mode === "party") {
      // A burst of confetti every few seconds, and a turn on the spot each second.
      if (now >= this.burstAt) {
        this.burst(cx, now, this.confetti.length ? 14 : 34);
        this.burstAt = now + 3500;
      }
      if (now >= (this.turnAt ?? 0)) {
        this.facing = -this.facing;
        this.turnAt = now + 1000;
      }
      dirty = true;
    } else if ((this.mode === "work" || this.mode === "idle") && now >= this.nextMove && this.x !== null) {
      // Wander: walk somewhere else, or turn and stand.
      const room = Math.max(0, this.w - sw - 8);
      if (Math.random() < 0.7 && room > 20) {
        let tx = rand(4, 4 + room);
        if (Math.abs(tx - this.x) < 24) tx = (tx + room / 2) % room + 4;
        const speed = this.mode === "work" ? 55 : 32;
        this.walkMs = Math.max(400, (Math.abs(tx - this.x) / speed) * 1000);
        this.facing = tx > this.x ? 1 : -1;
        this.x = tx;
        this.walkUntil = now + this.walkMs;
        this.nextMove = this.walkUntil + rand(1500, this.mode === "work" ? 4000 : 7000);
      } else {
        this.facing = -this.facing;
        this.nextMove = now + rand(2000, 5000);
      }
      dirty = true;
    }

    if (now >= this.nextBlink && this.mode !== "sleep") {
      this.blink = true;
      this.nextBlink = now + rand(2500, 6500);
      cx.timer.after(140, (cx) => { this.blink = false; cx.notify(); });
      dirty = true;
    }
    if (dirty) cx.notify();
  }

  burst(cx, now, n) {
    const t = theme();
    const colors = [t.ansi1, t.ansi2, t.ansi3, t.ansi4, t.ansi5, t.ansi6].filter(Boolean);
    const ground = this.ground();
    const fresh = [];
    for (let i = 0; i < n; i++) {
      const x = rand(0, this.w);
      fresh.push({
        id: ++this.ids, born: now, phase: 0, color: pick(colors),
        x, y: rand(-30, -4), x2: x + rand(-18, 18), y2: ground - rand(1, 4), ms: rand(1300, 2400),
      });
    }
    this.confetti.push(...fresh);
    // Drawn once where they start, then given their targets: .transition does the fall.
    cx.timer.after(40, (cx) => { fresh.forEach((p) => (p.phase = 1)); cx.notify(); });
  }

  pet(cx, now) {
    this.petUntil = now + 1400;
    const cx0 = (this.x ?? 0) + (SW * this.px()) / 2;
    const top = this.baseY() - 6;
    const fresh = [0, 1, 2].map((i) => ({ id: ++this.ids, born: now, phase: 0, x: cx0 + rand(-14, 10), y: top + i * 2 }));
    this.hearts.push(...fresh);
    cx.timer.after(40, (cx) => { fresh.forEach((p) => (p.phase = 1)); cx.notify(); });
    if (Math.random() < 0.5) this.say(pick(["hehe", "♥", "*wiggles*"]), null, null, 1500);
  }

  // ---- geometry --------------------------------------------------------------------

  px() { return this.w < 120 ? 2 : 4; }
  ground() { return this.h - 9; }                   // the grass line
  baseY() { return this.ground() - SH * this.px(); } // the critter's top when standing

  // ---- render ------------------------------------------------------------------------

  render(cx) {
    const t = theme();
    const now = Date.now();
    const px = this.px();
    const sw = SW * px;
    if (this.x === null) this.x = Math.max(0, (this.w - sw) / 2);

    const fake = (status) => [{ status, program: { name: "Claude Code" }, space_name: "demo", address: null }];
    const list = this.demo === "knock" ? fake("blocked") : this.demo === "party" ? fake("done") : agents();
    const needing = list.filter((a) => a.status === "blocked");
    const done = list.filter((a) => a.status === "done");
    const busy = list.some((a) => a.status === "working");
    const away = this.away || this.demo === "sleep";
    const mode = needing.length ? "knock" : done.length ? "party" : away ? "sleep" : busy ? "work" : "idle";
    if (mode !== this.mode) {
      if (mode === "party") this.burstAt = 0;
      this.mode = mode;
    }

    // Knocking and dancing happen in the middle, at the front.
    const center = Math.max(0, (this.w - sw) / 2);
    let x = this.x;
    let walkMs = this.walkMs;
    if (mode === "knock" || mode === "party") {
      walkMs = Math.max(300, (Math.abs(center - this.x) / 90) * 1000);
      x = this.x = center;
    }
    const walking = now < this.walkUntil;
    const petting = now < this.petUntil;

    let face;
    if (mode === "sleep") face = { eyes: "closed", mouth: "none", lying: true };
    else if (mode === "knock") face = { eyes: "wide", mouth: "open" };
    else if (mode === "party" || petting) face = { eyes: "happy", mouth: "smile", wag: true };
    else face = { eyes: this.blink ? "blink" : "open", mouth: mode === "work" ? "small" : "smile" };
    const look = walking ? this.facing : 0;
    const grid = sprite({ ...face, look, facing: this.facing });
    const colors = { b: t.ansi5 ?? "#f5c2e7", c: t.ansi1 ?? "#f38ba8" };

    // body <- hop/bob <- rattle <- pixels
    let shake = div().id("pip-shake").absolute().left(0).top(0).w(sw).h(SH * px).children(pixels(grid, colors, px, "px"));
    if (mode === "knock") shake = shake.loop("left", { from: -1.5, to: 1.5, period: 140, easing: "linear" });

    let bounce = div().id("pip-bounce").absolute().left(0).top(0).w(sw).h(SH * px).child(shake);
    if (mode === "party") bounce = bounce.loop("top", { from: 0, to: -12, period: 520, easing: "ease-out" });
    else if (mode === "knock") bounce = bounce.loop("top", { from: 0, to: -4, period: 560 });
    else if (petting) bounce = bounce.loop("top", { from: 0, to: -6, period: 380, easing: "ease-out" });
    else if (walking) bounce = bounce.loop("top", { from: 0, to: -2, period: 260 });

    const lift = face.lying ? px : 0;
    let body = div().id("pip-body").absolute().left(x).top(this.baseY() + lift).w(sw).h(SH * px)
      .transition("left", { duration: Math.round(walkMs), easing: "ease-in-out" })
      .child(bounce);

    if (mode === "knock") {
      // Paws pressed on the glass, either side of its head.
      for (const side of [-1, 1]) {
        const pawX = sw / 2 - 2.5 * px + side * 8 * px;
        body = body.child(div().id(`paw${side}`).absolute().left(pawX).top(px).w(5 * px).h(4 * px)
          .loop("opacity", { from: 0.15, to: 1, period: side > 0 ? 600 : 760 })
          .children(pixels(PAW, colors, px, `paw${side}`)));
      }
    }
    if (mode === "sleep") {
      body = body.child(div().id("zzz").absolute().left(sw - 2).top(-14).text_size(11).text_color(t.ansi4 ?? t.accent)
        .frames(["z", "z z", "z z Z", "  z Z", "    Z", ""], 520));
    }

    const children = [];
    // grass, with a few tufts that stay put
    children.push(div().id("grass").absolute().left(0).right(0).top(this.ground()).h(3).bg(t.ansi2 ?? "#a6e3a1").opacity(0.85));
    for (let i = 0; i * 37 < this.w; i++) {
      const gx = (i * 37 + 11) % Math.max(1, this.w);
      children.push(div().id(`tuft${i}`).absolute().left(gx).top(this.ground() - 3).w(3).h(3).bg(t.ansi2 ?? "#a6e3a1").opacity(0.85));
    }
    children.push(body);

    for (const p of this.confetti) {
      children.push(div().id(`cf${p.id}`).absolute().w(3).h(3).bg(p.color)
        .left(p.phase ? p.x2 : p.x).top(p.phase ? p.y2 : p.y).opacity(p.phase ? 0 : 1)
        .transition("top", { duration: Math.round(p.ms), easing: "ease-in" })
        .transition("left", { duration: Math.round(p.ms), easing: "ease-out" })
        .transition("opacity", { duration: 700, delay: Math.round(p.ms + 2200) }));
    }
    for (const p of this.hearts) {
      children.push(div().id(`ht${p.id}`).absolute().left(p.x).top(p.phase ? p.y - 30 : p.y)
        .opacity(p.phase ? 0 : 1).text_size(12).text_color(t.ansi1 ?? "#f38ba8").child("♥")
        .transition("top", { duration: 1300, easing: "ease-out" })
        .transition("opacity", { duration: 900, delay: 400 }));
    }

    // The sign over its head.
    let sign = null;
    if (mode === "knock") {
      const spaces = unique(needing.map((a) => a.space_name));
      sign = { title: needing.length === 1 ? `${who(needing[0])} needs you!` : `${needing.length} agents need you!`, sub: spaces.join(", "), color: t.blocked ?? t.ansi3 };
    } else if (mode === "party") {
      const spaces = unique(done.map((a) => a.space_name));
      sign = { title: done.length === 1 ? `${who(done[0])}'s done!` : `${done.length} agents are done!`, sub: spaces.join(", "), color: t.done ?? t.ansi2 };
    } else if (this.bubble) {
      sign = this.bubble;
    }
    if (sign && this.w >= 120) {
      const tone = sign.color ?? t.foreground;
      children.push(h_flex().id("sign").absolute().left(6).right(6).top(4).justify_center()
        .child(v_flex().id("sign-card").max_w(this.w - 12).px(10).py(3).rounded(8).bg(t.raised).border_1().border_color(tone).items_center()
          .child(div().truncate().text_size(12).font_semibold().text_color(tone).child(sign.title))
          .when(Boolean(sign.sub), (el) => el.child(div().truncate().text_size(11).text_color(t.muted).child(sign.sub)))));
    }

    return div().id("pip").relative().size_full().overflow_hidden().cursor_pointer()
      .on_size_change((size, cx) => {
        this.w = size.width;
        this.h = size.height;
        this.x = Math.min(this.x ?? 0, Math.max(0, this.w - SW * this.px()));
        cx.notify();
      })
      .on_click((_event, cx) => {
        // Pip only ever points at an agent; the click takes you there.
        const target = needing[0] ?? done[0];
        if (target?.address) run("agent.focus", { terminal: target.address });
        else this.pet(cx, Date.now());
        cx.notify();
      })
      .children(children);
  }
}
