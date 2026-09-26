/* ============================================================================
   Farmable v1 — shared screen scaffolding.
   Loaded by every screens-*.html page. Depends on farmable.js (icon, hydrate,
   initCarousels, initShell, SCENES).
   ========================================================================== */

const I = icon;

function statusbar(extra) {
  return '<div class="statusbar"><span>09:42</span><span class="sb-right">' +
    (extra || '') +
    '<svg width="15" height="11" viewBox="0 0 18 13" fill="currentColor"><rect x="0" y="8" width="3" height="5" rx="1"/>' +
    '<rect x="5" y="5" width="3" height="8" rx="1"/><rect x="10" y="2" width="3" height="11" rx="1" opacity=".4"/>' +
    '<rect x="15" y="0" width="3" height="13" rx="1" opacity=".4"/></svg>' +
    '<svg width="22" height="11" viewBox="0 0 26 13" fill="none" stroke="currentColor" stroke-width="1.4">' +
    '<rect x="0.7" y="0.7" width="21" height="11.6" rx="3"/><rect x="2.6" y="2.6" width="12" height="7.8" rx="1.5" fill="currentColor" stroke="none"/>' +
    '<path d="M24 4.5v4" stroke-linecap="round"/></svg></span></div>';
}

function navbar(active) {
  const items = [
    ['home', 'Home', 'home'], ['farm', 'Farm', 'map'],
    ['insights', 'Insights', 'chart'], ['profile', 'Profile', 'user'],
  ];
  let h = '<nav class="navbar" aria-label="Main">';
  h += navItem(items[0], active) + navItem(items[1], active) + '<span></span>' +
       navItem(items[2], active) + navItem(items[3], active);
  h += '</nav>';
  return h;
}
function navItem(it, active) {
  return '<button class="nav-item"' + (it[0] === active ? ' aria-current="page"' : '') + '>' +
    I(it[2]) + '<span>' + it[1] + '</span></button>';
}
function aiDock(state, label) {
  return '<div class="ai-dock" data-ai="' + (state || 'idle') + '">' +
    '<button class="ai-btn" data-sheet-toggle aria-label="Farm assistant. Hold to speak, or tap to start and stop.">' +
    '<span class="ring"></span><span class="ring"></span><span class="ring"></span>' +
    (state === 'listening' ? I('mic') : state === 'speaking' ? I('volume')
      : '<span class="brand-mark" aria-hidden="true"></span>') + '</button>' +
    '<span class="ai-label">' + (label === undefined ? 'Speak' : label) + '</span></div>';
}
function badge(kind, ico, text) { return '<span class="badge badge-' + kind + '">' + I(ico) + text + '</span>'; }
function chip(kind, ico, text) { return '<span class="chip' + (kind ? ' chip-' + kind : '') + '">' + I(ico) + text + '</span>'; }
function sync(kind, ico, text, spin) {
  return '<span class="sync sync-' + kind + '">' + I(ico).replace('<svg', '<svg' + (spin ? ' class="spin"' : '')) + text + '</span>';
}
function sectionHeader(title, sub, action) {
  return '<div class="section-header"><div><h2>' + title + '</h2>' +
    (sub ? '<span class="sh-sub">' + sub + '</span>' : '') + '</div>' +
    (action ? '<a href="#">' + action + I('chevronRight') + '</a>' : '') + '</div>';
}

/* --------------------------------------------------------------- ZoneCard */
const ZONES = [
  { key: 'cabbage', name: 'Cabbage Field', crop: 'Cabbage', scene: 'cabbage', st: 'on-track',
    stText: 'On track', k: 'Expected profit', v: 'R17,400', area: '0.6 ha' },
  { key: 'tomato', name: 'Tomato Section', crop: 'Tomatoes', scene: 'tomato', st: 'attention',
    stText: 'Needs attention', k: 'Expected profit', v: 'R22,100', area: '0.5 ha' },
  { key: 'north', name: 'North Plot', crop: 'Empty', scene: 'north', st: 'idle',
    stText: 'Not planted', k: 'Available to plant', v: '0.7 ha', area: '0.7 ha' },
  { key: 'spinach', name: 'Spinach Beds', crop: 'Spinach', scene: 'spinach', st: 'on-track',
    stText: 'On track', k: 'Expected profit', v: 'R8,600', area: '0.6 ha' },
];
function zoneCard(z) {
  return '<div class="zone-card">' +
    '<div class="zc-media"><div data-scene="' + z.scene + '" style="display:contents"></div><div class="zc-scrim"></div>' +
    '<div class="zc-top"><span class="badge badge-scrim">' + I(z.st === 'idle' ? 'circleDash' : 'leaf') + z.crop + '</span>' +
    (z.st === 'attention' ? badge('attention', 'alert', 'Attention') : '') + '</div>' +
    '<div class="zc-figures"><div class="zf-k">' + z.k + '</div><div class="zf-v">' + z.v + '</div></div></div>' +
    '<div class="zc-label"><span class="dot dot-' + z.st + '"></span>' + z.name + '</div></div>';
}


function hbar(name, pct, tone, label) {
  return '<div class="hbar"><span class="hb-name">' + name + '</span>' +
    badge(tone === 'on-track' ? 'on-track' : 'attention', tone === 'on-track' ? 'checkCircle' : 'alert', label) +
    '<div class="hb-track"><div class="hb-fill" style="width:' + pct + '%;background:var(--status-' + tone + ')"></div></div></div>';
}
function qa(ico, label) {
  return '<button class="qa-tile"><span class="qa-ico">' + I(ico) + '</span><span>' + label + '</span></button>';
}
function rowItem(ico, tone, title, sub, tag) {
  const bg = tone === 'action-required' ? 'var(--status-action-required-container)'
          : tone === 'needs-attention' ? 'var(--status-needs-attention-container)'
          : 'var(--primary-container)';
  const fg = tone === 'action-required' ? 'var(--on-status-action-required-container)'
          : tone === 'needs-attention' ? 'var(--on-status-needs-attention-container)'
          : 'var(--on-primary-container)';
  return '<div class="row-item"><span class="row-ico" style="background:' + bg + ';color:' + fg + '">' + I(ico) + '</span>' +
    '<div><div class="row-t">' + title + '</div><div class="row-s">' + sub + '</div></div>' +
    (tag ? badge('action', 'alert', tag) : I('chevronRight')) + '</div>';
}


function recCard(o) {
  return '<div class="card rec-card card-mat">' +
    '<div class="rec-media"><div data-scene="' + o.scene + '" style="display:contents"></div>' +
    (o.fit === 'strong' ? badge('on-track', 'checkCircle', 'Strong fit') : badge('attention', 'alert', 'Weak fit'))
      .replace('class="badge', 'class="rm-badge badge') + '</div>' +
    '<div class="card-body" style="padding:var(--sp-4) var(--sp-3) var(--sp-3)">' +
    '<div class="rec-head"><h3>' + o.crop + '</h3><span class="muted" style="font:var(--type-label-s)">' + o.variety + '</span></div>' +
    '<div class="rec-figs">' +
    '<div><div class="rf-k">Expected profit</div><div class="rf-v" style="color:var(--status-on-track)">' + o.profit + '</div></div>' +
    '<div><div class="rf-k">Expected cost</div><div class="rf-v">' + o.cost + '</div></div></div>' +
    '<div class="chip-row">' + o.chips.map(function (c) { return chip(c[0], c[1], c[2]); }).join('') + '</div>' +
    '<button class="btn btn-secondary btn-block" style="margin-top:var(--sp-4)">View details</button>' +
    '</div></div>';
}


function metric(ico, k, v, sub, cls) {
  return '<div class="metric"><div class="m-label">' + I(ico) + k + '</div>' +
    '<div class="m-value ' + cls + '">' + v + '</div><div class="m-sub">' + sub + '</div></div>';
}
function detailRow(k, v) {
  return '<div class="detail-row"><span class="dk">' + k + '</span><span class="dv">' + v + '</span></div>';
}
function timeline() {
  return '<div class="timeline">' +
    tlItem('completed', 'check', 'Soil preparation', 'Completed · 10 Sep', '', 'R1,200 spent') +
    tlItem('completed', 'check', 'Planting', 'Completed · 8 Aug', '', 'R2,400 spent') +
    tlItem('current', 'circle', 'Fertiliser application', 'This week · by Fri 26 Sep',
           'LAN 28 at 2 bags. Apply after the next rain so it washes in.', 'About R680') +
    tlItem('overdue', 'alert', 'Weed second row', 'Overdue · was due 16 Sep', '', '') +
    tlItem('upcoming', '', 'Health check', 'In 7 days · 27 Sep', '', '') +
    tlItem('upcoming', '', 'Expected harvest', '21 Dec · about 92 days', '', '', true) +
    '</div>';
}
function tlItem(state, ico, title, when, note, cost, last) {
  return '<div class="tl-item tl-' + state + '"' + (last ? ' style="padding-bottom:0"' : '') + '>' +
    '<div class="tl-node">' + (ico ? I(ico) : '') + '</div>' +
    '<div class="tl-head"><div><div class="tl-title">' + title + '</div>' +
    '<div class="tl-when"' + (state === 'overdue' ? ' style="color:var(--status-action-required)"' : '') + '>' + when + '</div></div>' +
    '<button class="tl-edit" aria-label="Edit ' + title + '">' + I('edit') + '</button></div>' +
    (note ? '<div class="tl-note">' + note + '</div>' : '') +
    (cost ? '<div class="tl-cost">' + I('wallet') + cost + '</div>' : '') +
    '</div>';
}
function observations(withoutFirst) {
  let h = '';
  h += obsRow('thumbCabbage', 'Leaf yellowing', 'Today, 09:42',
    'Yellowing leaves on the southern side. Watered this morning.',
    [chip('', 'mic', 'By voice'), chip('warn', 'scan', 'CV: 81%'), sync('pending', 'upload', 'Waiting')]);
  h += obsRow('thumbCabbage', 'Routine check', '14 Sep',
    'Heads forming well on the top rows. No pests seen.',
    [sync('synced', 'checkCircle', 'Synced')]);
  h += obsRow('thumbCabbage', 'Pest check', '2 Sep',
    'A few holes in outer leaves. Sprayed with soap solution.',
    [chip('', 'receipt', 'R85 expense'), sync('synced', 'checkCircle', 'Synced')]);
  return h;
}
function obsRow(scene, type, date, note, tags) {
  return '<div class="obs"><div class="o-thumb"><div data-scene="' + scene + '" style="display:contents"></div></div>' +
    '<div><div class="o-head"><span class="o-type">' + type + '</span><span class="o-date">' + date + '</span></div>' +
    '<div class="o-note">' + note + '</div>' +
    '<div class="o-tags">' + tags.join('') + '</div></div></div>';
}


function whyRow(ico, tone, k, v) {
  const col = tone === 'ok' ? 'var(--status-on-track)' : 'var(--status-needs-attention)';
  return '<div class="why-row"><span style="color:' + col + '">' + I(ico) + '</span>' +
    '<div><div class="row-t">' + k + '</div><div class="row-s">' + v + '</div></div>' +
    (tone === 'ok' ? badge('on-track', 'checkCircle', 'Good') : badge('attention', 'alert', 'Watch')) + '</div>';
}


/* ------------------------------------------------------- render harness --
   Every screen is written once and rendered into a light frame and a dark
   frame from the same source, so the two themes cannot drift apart.
-------------------------------------------------------------------------- */
function renderScreens(list, hostId) {
  const host = document.getElementById(hostId || 'screens');
  host.innerHTML = list.map(function (s) {
    const frame = function (theme) {
      return '<div class="frame-wrap"><div class="frame-label"><b>' +
        (theme === 'light' ? 'Light' : 'Dark') + '</b></div>' +
        '<div class="device" data-theme="' + theme + '">' + s.render() + '</div></div>';
    };
    return '<section class="grp" id="' + s.id + '"><h2>' + s.title + '</h2>' +
      (s.note ? '<p>' + s.note + '</p>' : '') +
      '<div class="frames">' + frame('light') + frame('dark') + '</div></section>';
  }).join('');
  hydrate();
  initCarousels();
  initShell();
  buildIndex(list);
}

/* a jump-list so a 30-frame page stays navigable */
function buildIndex(list) {
  const nav = document.getElementById('screen-index');
  if (!nav) return;
  nav.innerHTML = list.map(function (s) {
    return '<a class="chip" href="#' + s.id + '">' + s.title.replace(/^[\d.ab]+\s*·\s*/, '') + '</a>';
  }).join('');
}
