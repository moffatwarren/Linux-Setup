// The `haakonlife` fish command: play time and leaderboard stats from Haakon Life's live database.
// It only reads, and sends nothing. The list of boards comes from js/game.js in the repo, so a new
// game's board turns up here on its own. Set HAAKONLIFE_REPO if the repo moves.
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import vm from 'node:vm';

const DB = 'https://haakonlife-d4ef2-default-rtdb.firebaseio.com';
const REPO = process.env.HAAKONLIFE_REPO || homedir() + '/haakonlife';
const COLS = Math.max(60, process.stdout.columns || 100);
const tty = process.stdout.isTTY;
const bold = (s) => (tty ? '\x1b[1m' + s + '\x1b[0m' : s);
const dim = (s) => (tty ? '\x1b[2m' + s + '\x1b[0m' : s);
let first = true;
const heading = (title, note) => {
  console.log((first ? '' : '\n') + bold(title) + (note ? '  ' + dim(note) : ''));
  first = false;
};
// Names come from the database, which anybody can write to, so keep them to plain text.
const clean = (s) => String(s ?? '?').replace(/[\x00-\x1f\x7f-\x9f]/g, '').slice(0, 16);
const ordinal = (n) => {
  const s = ['th', 'st', 'nd', 'rd'], v = n % 100;
  return n + (s[(v - 20) % 10] || s[v] || s[0]);
};
const hours = (s) => `${Math.floor(s / 3600)}h ${String(Math.floor(s / 60) % 60).padStart(2, '0')}m`;
const ago = (t) => {
  const s = (Date.now() - t) / 1000;
  return s < 60 ? 'just now' : s < 3600 ? Math.floor(s / 60) + 'm ago' : s < 86400 ? Math.floor(s / 3600) + 'h ago' : Math.floor(s / 86400) + 'd ago';
};
// Local times come from `date`, not from Node. Node takes its timezone rules from ICU's own copy
// of the tz database, which lags the system's: ICU's still had BC on Pacific time after it moved
// to permanent UTC-7 in November 2026, so every time read an hour behind the clock. `date` reads
// /etc/localtime (or $TZ), so these agree with the rest of the desktop. One process answers for
// all of them, and the last line asked is today's midnight, for "Today" below.
function localClock(times) {
  const asked = [...times.map((t) => '@' + Math.floor(t / 1000)), '00:00 today'];
  const r = spawnSync('date', ['-f', '-', '+%s %z'], { input: asked.join('\n') + '\n', encoding: 'utf8' });
  const got = (r.stdout || '').trim().split('\n').map((l) => l.match(/^(-?\d+) ([+-])(\d\d)(\d\d)$/));
  if (r.status !== 0 || got.length !== asked.length || got.some((m) => !m)) {
    return { show: (t) => new Date(t).toLocaleString(), midnight: new Date().setHours(0, 0, 0, 0) };
  }
  const offset = new Map(times.map((t, i) => [t, (got[i][2] === '-' ? -1 : 1) * (got[i][3] * 60 + +got[i][4]) * 60e3]));
  return {
    show: (t) => new Date(t + offset.get(t)).toLocaleString(undefined, { timeZone: 'UTC' }),
    midnight: got.at(-1)[1] * 1000,
  };
}
// A list of words wrapped to the terminal, with the lines after the first indented.
function wrap(words, indent) {
  const lines = [];
  let cur = '';
  for (const w of words) {
    if (cur && indent + cur.length + 2 + w.length > COLS) { lines.push(cur + ','); cur = w; }
    else cur = cur ? cur + ', ' + w : w;
  }
  if (cur) lines.push(cur);
  return lines.join('\n' + ' '.repeat(indent));
}

async function get(path) {
  const r = await fetch(DB + '/' + path + '.json', { signal: AbortSignal.timeout(15000) });
  if (!r.ok) throw new Error(path + ' (' + r.status + ')');
  return (await r.json()) || {};
}

// BOARDS in js/game.js, one { key, title, unit, low, net, unlisted, early } each
function readBoards() {
  const src = readFileSync(REPO + '/js/game.js', 'utf8');
  const start = src.indexOf('const BOARDS = {');
  if (start < 0) throw new Error('no BOARDS in js/game.js');
  const block = src.slice(start, src.indexOf('\n  };', start));
  const early = earlyBoards(src);
  return [...block.matchAll(/(\w+): \{ title: '((?:[^'\\]|\\.)*)'([^}]*)\}/g)].map(([, key, title, rest]) => ({
    key,
    title: title.replace(/\\'/g, "'"),
    unit: (rest.match(/unit: ('(?:[^'\\]|\\.)*'|\w+)/) || [])[1],
    low: /\blow: true/.test(rest),
    net: /\bnet: true/.test(rest),
    unlisted: /\bunlisted: true/.test(rest),
    early: early.has(key),
  }));
}

// A holiday's games stay out of the Hall of Fame (their boards, the points and the latest scores)
// until the day that holiday first came round, so scores put in while trying them out don't count:
// SEASON_FROM in js/game.js, with FAME_GROUPS saying which boards are whose. Today is `date`'s, for
// the reason in localClock. If either can't be read, nothing is left out.
function earlyBoards(src) {
  try {
    const from = src.match(/const SEASON_FROM = \{([^}]*)\}/), at = src.indexOf('const FAME_GROUPS = [');
    if (!from || at < 0) return new Set();
    const start = src.indexOf('[', at);
    const groups = vm.runInNewContext(src.slice(start, src.indexOf('\n  ];', start) + 4));
    const r = spawnSync('date', ['+%F'], { encoding: 'utf8' });
    const today = r.status === 0 ? r.stdout.trim() : new Date().toLocaleDateString('en-CA');
    const early = [...from[1].matchAll(/(\w+): new Date\((\d+), (\d+), (\d+)\)/g)]
      .filter(([, , y, m, d]) => today < y + '-' + String(+m + 1).padStart(2, '0') + '-' + d.padStart(2, '0'))
      .map(([, g]) => g);
    return new Set(groups.filter(([g]) => early.includes(g)).flatMap(([, keys]) => keys));
  } catch { return new Set(); }
}

// how many cards there are to win: WINNABLE in js/game.js, which is what the board counts. That leaves
// out the starters (S), the ones only other cards bring in (T) and the versions of your own legendary
// (own), so it is smaller than the whole list.
function cardTotal() {
  try {
    const w = {};
    vm.runInNewContext(readFileSync(REPO + '/js/cardlist.js', 'utf8'), { window: w });
    return w.CARD_LIST.filter((c) => c.rarity !== 'T' && c.rarity !== 'S' && !c.own).length;
  } catch { return 0; }
}

// the same units the game shows (tenths, racetime, times and goals in js/game.js)
const UNITS = {
  tenths: (n) => (n / 10).toFixed(1) + 's',
  racetime: (n) => Math.floor(n / 600) + ':' + ((n % 600) / 10).toFixed(1).padStart(4, '0'),
  times: (n) => n + (n === 1 ? ' time' : ' times'),
  goals: (n) => n + (n === 1 ? ' goal' : ' goals'),
};
function show(b, score) {
  const n = b.low ? -score : score; // lowest-wins boards are kept as negative numbers
  if (b.unit && b.unit[0] === "'") return n + b.unit.slice(1, -1).replace(/\\'/g, "'");
  return UNITS[b.unit] ? UNITS[b.unit](n) : String(n);
}
// best first, and the earlier of two equal scores, as the Hall of Fame does (byScore)
const byScore = (a, b) => b.score - a.score || a.t - b.t;

// A board's rows. Live Hold'em keeps what each name won and lost as two boards, and the
// game shows the difference, so this does too.
async function rowsOf(b) {
  // (as the game reads a row, boardRows: one with no time still counts, as the oldest)
  const rows = (d) => Object.entries(d)
    .filter(([, r]) => r && typeof r.score === 'number')
    .map(([id, r]) => ({ id, name: clean(r.name), score: r.score, t: +r.t || 0 }));
  if (!b.net) return rows(await get('scores/' + b.key));
  const [won, lost] = await Promise.all([get('scores/' + b.key + 'won'), get('scores/' + b.key + 'lost')]);
  const by = new Map();
  for (const [sign, list] of [[1, rows(won)], [-1, rows(lost)]]) {
    for (const r of list) {
      const o = by.get(r.id) || { id: r.id, name: r.name, score: 0, t: 0 };
      o.score += sign * r.score;
      o.t = Math.max(o.t, r.t);
      by.set(r.id, o);
    }
  }
  return [...by.values()];
}

let boards = [];
try { boards = readBoards().filter((b) => !b.unlisted && !b.early); } // the Christmas Cup isn't in the Hall of Fame
catch (e) { console.error('Couldn\'t read the boards from ' + REPO + '/js/game.js: ' + e.message); }
const [pt, ...res] = await Promise.allSettled([get('playtime/live'), ...boards.map(rowsOf)]);

// ---------- play time ----------
heading('PLAY TIME');
const people = pt.status === 'fulfilled'
  ? Object.values(pt.value).filter((p) => p && typeof p.s === 'number' && typeof p.t === 'number').sort((a, b) => b.s - a.s)
  : [];
if (pt.status === 'rejected') console.log('  Couldn\'t read it: ' + pt.reason.message);
else {
  const total = people.reduce((a, p) => a + p.s, 0) || 1;
  const clock = localClock(people.map((p) => p.t));
  for (const p of people) {
    console.log(' ', clean(p.name).padEnd(14), hours(p.s).padStart(8), (Math.round((100 * p.s) / total) + '%').padStart(4), ' last', clock.show(p.t));
  }
  console.log(' ', 'TOTAL'.padEnd(14), hours(people.reduce((a, p) => a + p.s, 0)).padStart(8), '    ', ' (' + people.length + ' names)');

  // ---------- who's been on ----------
  // A browser sends its play time every minute while somebody's playing, so a send in the
  // last 3 minutes means they're on now.
  heading('WHO\'S BEEN ON');
  const now = Date.now(), midnight = clock.midnight;
  const since = (t0) => people.filter((p) => p.t >= t0).sort((a, b) => b.t - a.t);
  const names = (list) => (list.length ? wrap(list.map((p) => clean(p.name)), 20) : dim('nobody'));
  const onNow = since(now - 3 * 60e3), today = since(midnight), week = since(now - 7 * 864e5);
  console.log('  ' + 'Right now'.padEnd(13) + String(onNow.length).padStart(3) + '  ' + names(onNow));
  console.log('  ' + 'Today'.padEnd(13) + String(today.length).padStart(3) + '  ' + names(today));
  console.log('  ' + 'Last 7 days'.padEnd(13) + String(week.length).padStart(3) + '  ' + dim('of ' + people.length + ' names'));
}

const read = boards.map((b, i) => ({ b, rows: res[i].status === 'fulfilled' ? res[i].value : null }));
const failed = read.filter((x) => !x.rows);
const boardsRead = read.filter((x) => x.rows);

if (boards.length) {
  // ---------- Office Champion ----------
  // The Hall of Fame's standings, worked out as the game does (fameStandings in js/game.js): every
  // board's top ten earn points, 10 for 1st down to 1 for 10th, and 1st is a crown. Points decide
  // it, then crowns, then the name.
  const champ = new Map();
  let empty = 0;
  for (const { rows } of boardsRead) {
    if (!rows.length) { empty++; continue; }
    [...rows].sort(byScore).slice(0, 10).forEach((r, i) => {
      const s = champ.get(r.id) || { name: r.name, points: 0, crowns: 0 };
      s.points += 10 - i;
      if (!i) s.crowns++;
      champ.set(r.id, s);
    });
  }
  const standings = [...champ.values()].sort((a, b) => b.points - a.points || b.crowns - a.crowns || a.name.localeCompare(b.name));
  heading('OFFICE CHAMPION', 'Hall of Fame points: 10 for 1st on a board, down to 1 for 10th');
  standings.slice(0, 10).forEach((s, i) => {
    const crowns = s.crowns ? String(s.crowns).padStart(5) + (s.crowns === 1 ? ' crown' : ' crowns') : '';
    console.log('  ' + String(i + 1).padStart(2) + ' ' + s.name.padEnd(13) + String(s.points).padStart(4) + ' pts' + crowns);
  });
  if (standings.length > 10) console.log('  ' + dim(standings.length - 10 + ' more with points'));
  if (empty) console.log('  ' + dim(empty + (empty === 1 ? ' board' : ' boards') + ' with no scores yet'));

  // ---------- most played ----------
  heading('MOST-PLAYED GAMES', 'names with a score');
  for (const { b, rows } of boardsRead.filter((x) => x.rows.length).sort((a, b) => b.rows.length - a.rows.length).slice(0, 10)) {
    console.log('  ' + b.title.padEnd(24) + String(rows.length).padStart(3));
  }

  // ---------- latest ----------
  // A row's time is when it last went up, so this is new bests (and every win, on the boards that count them).
  // The place is where that row stands on its board now, ranked as the Hall of Fame ranks it.
  heading('LATEST SCORES', 'new bests, and every win on the boards that count them');
  const all = boardsRead.flatMap(({ b, rows }) => [...rows].sort(byScore).map((r, i) => ({ ...r, b, place: i + 1, of: rows.length })));
  const latest = all.sort((a, b) => b.t - a.t).slice(0, 10).map((r) => ({ ...r, shown: show(r.b, r.score) }));
  const scoreW = Math.max(0, ...latest.map((r) => r.shown.length)) + 3;
  for (const r of latest) {
    console.log('  ' + ago(r.t).padEnd(10) + r.name.padEnd(13) + r.b.title.padEnd(24) + r.shown.padEnd(scoreW) + ordinal(r.place).padStart(4) + ' ' + dim('of ' + r.of));
  }

  // ---------- Morale Madness ----------
  const top10 = (key) => {
    const x = boardsRead.find((y) => y.b.key === key);
    return x ? [...x.rows].sort(byScore).slice(0, 10) : [];
  };
  const cards = top10('cards'), wins = top10('cardwins'), of = cardTotal();
  heading('MORALE MADNESS');
  console.log('  ' + ('Most cards' + (of ? ' (of ' + of + ')' : '')).padEnd(26) + 'Most wins');
  const cell = (r, i) => (r ? String(i + 1).padStart(2) + ' ' + r.name.padEnd(13) + String(r.score).padStart(4) : '');
  for (let i = 0; i < Math.max(cards.length, wins.length); i++) console.log(('  ' + cell(cards[i], i).padEnd(26) + cell(wins[i], i)).trimEnd());

  if (failed.length) console.log('\n' + dim('Couldn\'t read ' + failed.length + ' boards: ' + failed.map((x) => x.b.key).join(', ')));
}
