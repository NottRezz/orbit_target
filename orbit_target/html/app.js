'use strict';

// ── Element cache ─────────────────────────────────────────────────────────────
const el = {
  crosshair:  document.getElementById('crosshair'),
  softMarker: document.getElementById('soft-marker'),
  softInfo:   document.getElementById('soft-info'),
  sBarFill:   document.getElementById('s-bar-fill'),
  sDist:      document.getElementById('s-dist'),
  sThreat:    document.getElementById('s-threat'),
  ringLayer:  document.getElementById('ring-layer'),
};

// ── Slot pool — each slot has an X marker + a floating HP bar ────────────────
const MAX_SLOTS = 5;
const pool = [];

for (let i = 0; i < MAX_SLOTS; i++) {
  // X marker
  const x = document.createElement('div');
  x.className = 'lock-x';
  x.innerHTML = '<div class="lx-cross"></div><div class="lx-pulse"></div><div class="lx-pulse2"></div>';

  // Floating HP bar + distance label (positioned above the X)
  const hp   = document.createElement('div');
  hp.className = 'lock-hp';
  const fill = document.createElement('div');
  fill.className = 'lock-hp-fill';
  const track = document.createElement('div');
  track.className = 'lock-hp-track';
  track.appendChild(fill);
  const dist = document.createElement('span');
  dist.className = 'lock-hp-dist';
  hp.appendChild(track);
  hp.appendChild(dist);

  el.ringLayer.appendChild(x);
  el.ringLayer.appendChild(hp);
  pool.push({ x, hp, fill, dist });
}

// ── State ─────────────────────────────────────────────────────────────────────
let prevAction  = null;
let departTimer = null;

// ── Helpers ───────────────────────────────────────────────────────────────────
function setText(node, val) {
  const s = val != null ? String(val) : '';
  if (node.textContent !== s) node.textContent = s;
}

function setBar(fill, pct, overflow) {
  const w = pct + '%';
  if (fill.style.width !== w) fill.style.width = w;
  fill.classList.toggle('overflow', !!overflow);
}

function setThreat(span, lvl) {
  if (span.dataset.l === String(lvl)) return;
  span.dataset.l = lvl;
  setText(span, ['', 'LOW THREAT', 'ARMED', 'HOSTILE'][lvl] ?? '');
}

function placeX(node, sx, sy) {
  const x = (sx * 100).toFixed(2) + 'vw';
  const y = (sy * 100).toFixed(2) + 'vh';
  if (node.style.left !== x) node.style.left = x;
  if (node.style.top  !== y) node.style.top  = y;
}

// HP bar positioned slightly above the X (offset in vh)
const HP_OFFSET_VH = 3;  // below the X, same gap as soft-lock strip
function placeHp(node, sx, sy) {
  const x = (sx * 100).toFixed(2) + 'vw';
  const y = (sy * 100 + HP_OFFSET_VH).toFixed(2) + 'vh';
  if (node.style.left !== x) node.style.left = x;
  if (node.style.top  !== y) node.style.top  = y;
}

function departBracket() {
  if (departTimer) clearTimeout(departTimer);
  el.softMarker.classList.add('to-x');
  el.softInfo.classList.remove('show');
  departTimer = setTimeout(() => {
    el.softMarker.classList.remove('show', 'to-x');
    departTimer = null;
  }, 260);
}

function hideAllSlots() {
  pool.forEach(s => {
    s.x.classList.remove('show', 'primary');
    s.hp.classList.remove('show');
  });
}

// ── Render functions ──────────────────────────────────────────────────────────

function renderHide() {
  el.crosshair.classList.remove('show', 'dim', 'targeting');
  el.softMarker.classList.remove('show', 'to-x');
  el.softInfo.classList.remove('show');
  hideAllSlots();
  prevAction = 'hide';
}

function renderIdle() {
  el.crosshair.classList.add('show');
  el.crosshair.classList.remove('dim', 'targeting');
  el.softMarker.classList.remove('show');
  el.softInfo.classList.remove('show');
  hideAllSlots();
  prevAction = 'idle';
}

function renderNormal(d) {
  hideAllSlots();

  if (!d.onScreen) { renderIdle(); return; }

  el.crosshair.classList.add('show', 'dim', 'targeting');

  placeX(el.softMarker, d.sx, d.sy);
  el.softMarker.classList.remove('departing');
  el.softMarker.classList.add('show');

  // Info strip: offset below the bracket
  el.softInfo.style.left = (d.sx * 100).toFixed(2) + 'vw';
  el.softInfo.style.top  = ((d.sy * 100) + 3).toFixed(2) + 'vh';
  el.softInfo.classList.add('show');

  setText(el.sDist, d.distance != null ? d.distance + 'M' : '');
  if (d.health != null) setBar(el.sBarFill, d.health, d.overflow);
  if (d.threat != null) setThreat(el.sThreat, d.threat);

  prevAction = 'normal';
}

function renderLockOn(d) {
  el.crosshair.classList.remove('show', 'dim', 'targeting');
  el.softInfo.classList.remove('show');

  if (prevAction === 'normal') {
    departBracket();
  } else {
    el.softMarker.classList.remove('show', 'to-x');
  }

  const slots = d.slots;

  for (let i = 0; i < pool.length; i++) {
    const s    = pool[i];
    const slot = slots[i];

    if (!slot) {
      s.x.classList.remove('show', 'primary');
      s.hp.classList.remove('show');
      continue;
    }

    const isPrimary   = slot.primary;
    const isSecondary = !isPrimary;
    const offscreen   = !slot.onScreen;

    // X marker
    s.x.classList.toggle('primary',   isPrimary);
    s.x.classList.toggle('secondary', isSecondary);
    s.x.classList.toggle('offscreen', offscreen);
    s.x.classList.add('show');

    // HP bar (hide when off-screen — no world position to anchor to)
    s.hp.classList.toggle('secondary', isSecondary);
    s.hp.classList.toggle('offscreen', offscreen);
    s.hp.classList.toggle('show', !offscreen);

    const sx = slot.onScreen ? slot.sx : Math.max(0.02, Math.min(0.98, slot.sx ?? 0.5));
    const sy = slot.onScreen ? slot.sy : Math.max(0.02, Math.min(0.98, slot.sy ?? 0.5));

    placeX(s.x,  sx, sy);
    placeHp(s.hp, sx, sy);

    if (slot.health   != null) setBar(s.fill, slot.health, slot.overflow);
    setText(s.dist, slot.distance != null ? slot.distance + 'M' : '');
  }

  prevAction = 'lockon';
}

// ── Message handler ───────────────────────────────────────────────────────────
window.addEventListener('message', function(e) {
  const d = e.data;
  if (!d?.action) return;
  switch (d.action) {
    case 'hide':   renderHide();    break;
    case 'idle':   renderIdle();    break;
    case 'normal': renderNormal(d); break;
    case 'lockon': renderLockOn(d); break;
  }
});
