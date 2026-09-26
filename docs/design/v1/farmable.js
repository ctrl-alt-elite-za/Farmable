/* ============================================================================
   Farmable v1 — icons, generated farm imagery, and live mockup behaviour.
   No build step, no network dependency, no framework.

   Icons: Lucide (ISC licence) — paths inlined rather than CDN-loaded so the
   mockup opens from file:// with no network, matching the product's own
   offline-first constraint.
   ========================================================================== */

/* ----------------------------------------------------------------- icons -- */
const ICONS = {
  home:        '<path d="M3 10.5 12 3l9 7.5"/><path d="M5 9.5V21h14V9.5"/>',
  map:         '<path d="m3 6 6-3 6 3 6-3v15l-6 3-6-3-6 3z"/><path d="M9 3v15"/><path d="M15 6v15"/>',
  sprout:      '<path d="M7 20h10"/><path d="M12 20c0-6 0-8 0-8"/><path d="M12 12C12 7 9 5 4 5c0 5 3 7 8 7Z"/><path d="M12 12c0-4 2.5-6 7-6 0 4-2.5 6-7 6Z"/>',
  chart:       '<path d="M3 3v18h18"/><path d="M7 15l4-5 3 3 5-7"/>',
  user:        '<circle cx="12" cy="8" r="4"/><path d="M4 21v-1a7 7 0 0 1 16 0v1"/>',
  camera:      '<path d="M3 8h3l2-3h8l2 3h3v12H3z"/><circle cx="12" cy="13" r="4"/>',
  mic:         '<rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 11a7 7 0 0 0 14 0"/><path d="M12 18v4"/>',
  notebook:    '<path d="M5 3h13a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H5z"/><path d="M9 3v18"/><path d="M13 8h3"/><path d="M13 12h3"/>',
  receipt:     '<path d="M5 3h14v18l-2.5-1.5L14 21l-2-1.5L10 21l-2.5-1.5L5 21z"/><path d="M9 8h6"/><path d="M9 12h6"/>',
  tag:         '<path d="M3 12V4a1 1 0 0 1 1-1h8l9 9-9 9z"/><circle cx="7.5" cy="7.5" r="1.4"/>',
  check:       '<path d="M20 6 9 17l-5-5"/>',
  checkCircle: '<circle cx="12" cy="12" r="9"/><path d="m8.5 12 2.5 2.5 4.5-5"/>',
  alert:       '<path d="M12 3 2 20h20z"/><path d="M12 10v4"/><path d="M12 17.5h.01"/>',
  info:        '<circle cx="12" cy="12" r="9"/><path d="M12 11v5"/><path d="M12 8h.01"/>',
  clock:       '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  calendar:    '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18"/><path d="M8 3v4"/><path d="M16 3v4"/>',
  droplet:     '<path d="M12 3c3.5 4.2 6 7 6 10a6 6 0 0 1-12 0c0-3 2.5-5.8 6-10Z"/>',
  sun:         '<circle cx="12" cy="12" r="4"/><path d="M12 2v2"/><path d="M12 20v2"/><path d="M4 12H2"/><path d="M22 12h-2"/><path d="m5 5 1.5 1.5"/><path d="M17.5 17.5 19 19"/><path d="M19 5l-1.5 1.5"/><path d="M6.5 17.5 5 19"/>',
  coins:       '<ellipse cx="12" cy="6" rx="8" ry="3"/><path d="M4 6v6c0 1.7 3.6 3 8 3s8-1.3 8-3V6"/><path d="M4 12v6c0 1.7 3.6 3 8 3s8-1.3 8-3v-6"/>',
  trendUp:     '<path d="m3 17 6-6 4 4 8-8"/><path d="M15 7h6v6"/>',
  wallet:      '<path d="M3 7a2 2 0 0 1 2-2h12v4"/><path d="M3 7v11a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V9H5a2 2 0 0 1-2-2Z"/><circle cx="17" cy="14" r="1.3"/>',
  scale:       '<path d="M12 3v18"/><path d="M5 21h14"/><path d="m3 9 4-4 4 4a4 4 0 0 1-8 0Z"/><path d="m13 9 4-4 4 4a4 4 0 0 1-8 0Z"/>',
  ruler:       '<rect x="2" y="8" width="20" height="8" rx="1.5"/><path d="M7 8v3"/><path d="M12 8v4"/><path d="M17 8v3"/>',
  pin:         '<path d="M12 21s7-6.2 7-11a7 7 0 1 0-14 0c0 4.8 7 11 7 11Z"/><circle cx="12" cy="10" r="2.5"/>',
  edit:        '<path d="M13 21h8"/><path d="M17.5 4.5a2.1 2.1 0 0 1 3 3L8 20l-4 1 1-4z"/>',
  x:           '<path d="M18 6 6 18"/><path d="m6 6 12 12"/>',
  arrowLeft:   '<path d="M19 12H5"/><path d="m11 18-6-6 6-6"/>',
  arrowRight:  '<path d="M5 12h14"/><path d="m13 6 6 6-6 6"/>',
  chevronRight:'<path d="m9 6 6 6-6 6"/>',
  chevronDown: '<path d="m6 9 6 6 6-6"/>',
  plus:        '<path d="M5 12h14"/><path d="M12 5v14"/>',
  wifiOff:     '<path d="M2 2l20 20"/><path d="M8.5 16.5a5 5 0 0 1 7 0"/><path d="M5 12.9a10 10 0 0 1 4-2.5"/><path d="M15 10.4a10 10 0 0 1 4 2.5"/><path d="M2 8.8A15 15 0 0 1 7 6"/><path d="M17 6a15 15 0 0 1 5 2.8"/><path d="M12 20h.01"/>',
  cloudOff:    '<path d="M2 2l20 20"/><path d="M6.3 7.3A5 5 0 0 0 7 17h9"/><path d="M11.4 5.1A5.5 5.5 0 0 1 20 9.5a3.8 3.8 0 0 1 .9 7"/>',
  refresh:     '<path d="M21 12a9 9 0 1 1-2.6-6.4"/><path d="M21 4v5h-5"/>',
  upload:      '<path d="M12 16V4"/><path d="m8 8 4-4 4 4"/><path d="M4 16v3a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-3"/>',
  layers:      '<path d="m12 3 9 5-9 5-9-5z"/><path d="m3 13 9 5 9-5"/>',
  scan:        '<path d="M3 8V5a2 2 0 0 1 2-2h3"/><path d="M16 3h3a2 2 0 0 1 2 2v3"/><path d="M21 16v3a2 2 0 0 1-2 2h-3"/><path d="M8 21H5a2 2 0 0 1-2-2v-3"/><path d="M7 12h10"/>',
  leaf:        '<path d="M4 20c0-9 6-14 16-14 0 10-5 15-13 15H4z"/><path d="M4 20c4-5 7-7 11-9"/>',
  flask:       '<path d="M9 3h6"/><path d="M10 3v6L5 19a1.5 1.5 0 0 0 1.3 2h11.4A1.5 1.5 0 0 0 19 19l-5-10V3"/><path d="M7.5 15h9"/>',
  sparkles:    '<path d="M12 3 13.6 8 19 9.5 13.6 11 12 16l-1.6-5L5 9.5 10.4 8z"/><path d="M18.5 15.5 19 17.5l2 .5-2 .5-.5 2-.5-2-2-.5 2-.5z"/>',
  shield:      '<path d="M12 3 5 6v6c0 4.5 3 7.5 7 9 4-1.5 7-4.5 7-9V6z"/><path d="m9 12 2 2 4-4"/>',
  bell:        '<path d="M10 20a2 2 0 0 0 4 0"/><path d="M5 17h14c-1.3-1.4-2-2.9-2-7a5 5 0 0 0-10 0c0 4.1-.7 5.6-2 7Z"/>',
  history:     '<path d="M3 12a9 9 0 1 0 3-6.7"/><path d="M3 4v5h5"/><path d="M12 8v4.5l3 1.8"/>',
  target:      '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1.4"/>',
  truck:       '<path d="M3 7h11v9H3z"/><path d="M14 10h4l3 3v3h-7z"/><circle cx="7" cy="18" r="2"/><circle cx="17.5" cy="18" r="2"/>',
  seedling:    '<path d="M12 21v-8"/><path d="M12 13C12 8 8.5 6 4 6c0 5 3.5 7 8 7Z"/><path d="M8 21h8"/>',
  circle:      '<circle cx="12" cy="12" r="9"/>',
  circleDash:  '<path d="M10.1 3.2a9 9 0 0 1 3.8 0"/><path d="M13.9 20.8a9 9 0 0 1-3.8 0"/><path d="M17.6 4.7a9 9 0 0 1 2.7 2.7"/><path d="M3.2 13.9a9 9 0 0 1 0-3.8"/><path d="M20.3 16.6a9 9 0 0 1-2.7 2.7"/><path d="M20.8 10.1a9 9 0 0 1 0 3.8"/><path d="M3.7 6.4a9 9 0 0 1 2.7-2.7"/><path d="M6.4 20.3a9 9 0 0 1-2.7-2.7"/>',
  more:        '<circle cx="12" cy="12" r="1.3"/><circle cx="19" cy="12" r="1.3"/><circle cx="5" cy="12" r="1.3"/>',
  volume:      '<path d="M11 5 6 9H3v6h3l5 4z"/><path d="M15.5 8.5a5 5 0 0 1 0 7"/><path d="M18.5 5.5a9 9 0 0 1 0 13"/>',
  moon:        '<path d="M20 14.5A8.5 8.5 0 0 1 9.5 4a8.5 8.5 0 1 0 10.5 10.5Z"/>',
  eye:         '<path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7-10-7-10-7Z"/><circle cx="12" cy="12" r="3"/>',
  eyeOff:      '<path d="m2 2 20 20"/><path d="M6.7 6.8A12.5 12.5 0 0 0 2 12s3.6 7 10 7a10.8 10.8 0 0 0 5.3-1.3"/><path d="M9.9 5.2A11.6 11.6 0 0 1 12 5c6.4 0 10 7 10 7a15 15 0 0 1-3.3 4"/><path d="M9.9 9.9a3 3 0 0 0 4.2 4.2"/>',
  lock:        '<rect x="4" y="10" width="16" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/>',
  mail:        '<rect x="2.5" y="5" width="19" height="14" rx="2"/><path d="m3 7 9 6 9-6"/>',
  phone:       '<rect x="6" y="2" width="12" height="20" rx="2.5"/><path d="M11 18.5h2"/>',
  globe:       '<circle cx="12" cy="12" r="9"/><path d="M3 12h18"/><path d="M12 3a15 15 0 0 1 0 18a15 15 0 0 1 0-18"/>',
  download:    '<path d="M12 4v12"/><path d="m8 12 4 4 4-4"/><path d="M4 18v1a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-1"/>',
  trash:       '<path d="M4 7h16"/><path d="M9 7V5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2"/><path d="M6 7l1 13a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1l1-13"/>',
  logOut:      '<path d="M15 4h3a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-3"/><path d="M10 17l-5-5 5-5"/><path d="M5 12h11"/>',
  fileText:    '<path d="M14 3H7a1 1 0 0 0-1 1v16a1 1 0 0 0 1 1h10a1 1 0 0 0 1-1V7z"/><path d="M14 3v4h4"/><path d="M9 12h6"/><path d="M9 16h4"/>',
  helpCircle:  '<circle cx="12" cy="12" r="9"/><path d="M9.5 9.5a2.6 2.6 0 0 1 5 .9c0 1.7-2.5 2-2.5 3.6"/><path d="M12 17.5h.01"/>',
  message:     '<path d="M21 12a8 8 0 0 1-8 8H7l-4 3V12a8 8 0 0 1 8-8h2a8 8 0 0 1 8 8Z"/>',
  key:         '<circle cx="8" cy="15" r="4"/><path d="m11 12 8-8"/><path d="m17 6 2 2"/><path d="m14.5 8.5 2 2"/>',
  crosshair:   '<circle cx="12" cy="12" r="8"/><path d="M12 2v3"/><path d="M12 19v3"/><path d="M2 12h3"/><path d="M19 12h3"/>',
  save:        '<path d="M5 3h11l3 3v15H5z"/><path d="M8 3v6h7V3"/><path d="M8 14h8"/>',
  image:       '<rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="8.5" cy="9.5" r="1.8"/><path d="m4 18 5-5 4 4 3-3 4 4"/>',
  search:      '<circle cx="11" cy="11" r="7"/><path d="m20 20-4-4"/>',
  star:        '<path d="m12 3 2.7 5.7 6.3.8-4.6 4.3 1.2 6.2L12 17l-5.6 3 1.2-6.2L3 9.5l6.3-.8z"/>',
  chevronLeft: '<path d="m15 6-6 6 6 6"/>',
  send:        '<path d="M22 2 11 13"/><path d="M22 2 15 22l-4-9-9-4z"/>',
  users:       '<circle cx="9" cy="8" r="4"/><path d="M2 21v-1a7 7 0 0 1 14 0v1"/><path d="M17 4.5a4 4 0 0 1 0 7"/><path d="M19 21v-1a5 5 0 0 0-3-4.6"/>',
  fingerprint: '<path d="M12 11v3a7 7 0 0 1-1.5 4.3"/><path d="M8 12a4 4 0 0 1 8 0v2a11 11 0 0 1-.8 4"/><path d="M5 12a7 7 0 0 1 12-5"/><path d="M18.5 10.5A7 7 0 0 1 19 13v1"/><path d="M5 16v-2"/>',
  sliders:     '<path d="M4 7h10"/><path d="M18 7h2"/><circle cx="16" cy="7" r="2"/><path d="M4 17h4"/><path d="M12 17h8"/><circle cx="10" cy="17" r="2"/>',
  bookOpen:    '<path d="M12 6c-2-1.6-4.3-2-8-2v14c3.7 0 6 .4 8 2 2-1.6 4.3-2 8-2V4c-3.7 0-6 .4-8 2Z"/><path d="M12 6v14"/>',
  checkSquare: '<rect x="3.5" y="3.5" width="17" height="17" rx="3"/><path d="m8 12 2.5 2.5L16 9"/>',
  square:      '<rect x="3.5" y="3.5" width="17" height="17" rx="3"/>',
  external:    '<path d="M14 4h6v6"/><path d="M20 4 10 14"/><path d="M19 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1h5"/>',
  undo:        '<path d="M4 8h10a5 5 0 0 1 0 10h-4"/><path d="m4 8 4-4"/><path d="m4 8 4 4"/>',
  cloud:       '<path d="M6.5 18a4.5 4.5 0 0 1 .4-9A6 6 0 0 1 18 10.5a3.8 3.8 0 0 1-.5 7.5z"/>',
  gauge:       '<path d="M12 14 16 9"/><path d="M4 18a9 9 0 1 1 16 0"/><circle cx="12" cy="14" r="1.4"/>',
};

function icon(name, cls) {
  const d = ICONS[name] || ICONS.circle;
  /* Intrinsic 20px so an icon in a container with no sizing rule renders at a
     sane size instead of stretching to fill it. Any CSS rule still wins. */
  return '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" ' +
         'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"' +
         (cls ? ' class="' + cls + '"' : '') + '>' + d + '</svg>';
}

/* --------------------------------------------------- deterministic imagery --
   Generated SVG "photography": every farm scene below is drawn, not fetched,
   so the mockup renders identically offline. Production swaps real photographs
   behind the same scrim tokens.
---------------------------------------------------------------------------- */
function rng(seed) {
  let a = seed >>> 0;
  return function () {
    a += 0x6D2B79F5;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const CROPS = {
  cabbage: { leafA: '#7FAE60', leafB: '#5B8C48', head: '#BBD495', soil: '#97714A' },
  tomato:  { leafA: '#5C8B45', leafB: '#3F6B38', head: '#CE4A2E', soil: '#9A7148' },
  spinach: { leafA: '#57964F', leafB: '#3A7340', head: '#79B564', soil: '#8D6B45' },
  bare:    { leafA: '#9AA36C', leafB: '#7C8755', head: '#A8AE74', soil: '#A07B52' },
  beans:   { leafA: '#79A757', leafB: '#4E7F41', head: '#C6DC9C', soil: '#97714A' },
};

function skyAndLand(W, H, seed, o) {
  const r = rng(seed);
  const hz = H * (o.horizon || 0.3);
  let s = '';
  s += '<defs>' +
    '<linearGradient id="sky' + seed + '" x1="0" y1="0" x2="0" y2="1">' +
      '<stop offset="0" stop-color="#8FB4CE"/><stop offset="0.65" stop-color="#C6D8DF"/>' +
      '<stop offset="1" stop-color="#E7E5D3"/></linearGradient>' +
    '<linearGradient id="soil' + seed + '" x1="0" y1="0" x2="0" y2="1">' +
      '<stop offset="0" stop-color="#B99C74"/>' +
      '<stop offset="0.45" stop-color="' + o.pal.soil + '"/>' +
      '<stop offset="1" stop-color="' + o.pal.soil + '"/></linearGradient>' +
    '<radialGradient id="sun' + seed + '" cx="0.78" cy="0.08" r="0.55">' +
      '<stop offset="0" stop-color="#FFF6DC" stop-opacity="0.85"/>' +
      '<stop offset="1" stop-color="#FFF6DC" stop-opacity="0"/></radialGradient>' +
    '</defs>';
  s += '<rect width="' + W + '" height="' + H + '" fill="url(#sky' + seed + ')"/>';
  // distant hills
  let hills = 'M0 ' + hz;
  for (let x = 0; x <= W; x += W / 6) {
    hills += ' Q ' + (x + W / 12) + ' ' + (hz - 16 - r() * 26) + ' ' + (x + W / 6) + ' ' + (hz - 2 - r() * 8);
  }
  hills += ' L' + W + ' ' + H + ' L0 ' + H + 'Z';
  s += '<path d="' + hills + '" fill="#93A587" opacity="0.85"/>';
  // treeline
  for (let i = 0; i < 16; i++) {
    const x = r() * W, th = 8 + r() * 14;
    s += '<ellipse cx="' + x.toFixed(1) + '" cy="' + (hz - th * 0.4).toFixed(1) + '" rx="' +
         (th * 0.7).toFixed(1) + '" ry="' + th.toFixed(1) + '" fill="#43603F" opacity="0.7"/>';
  }
  s += '<rect y="' + hz + '" width="' + W + '" height="' + (H - hz) + '" fill="url(#soil' + seed + ')"/>';
  return { svg: s, hz: hz, r: r };
}

function drawPlant(type, x, y, sc, r, pal) {
  const j = () => (r() - 0.5);
  if (type === 'cabbage') {
    let p = '';
    for (let k = 0; k < 7; k++) {
      const a = (k / 7) * Math.PI * 2 + j() * 0.3;
      p += '<ellipse cx="' + (x + Math.cos(a) * sc * 0.75).toFixed(1) + '" cy="' + (y + Math.sin(a) * sc * 0.42).toFixed(1) +
           '" rx="' + (sc * 0.72).toFixed(1) + '" ry="' + (sc * 0.52).toFixed(1) +
           '" fill="' + (k % 2 ? pal.leafA : pal.leafB) + '" transform="rotate(' + (a * 57).toFixed(0) + ' ' + x.toFixed(1) + ' ' + y.toFixed(1) + ')"/>';
    }
    p += '<circle cx="' + x.toFixed(1) + '" cy="' + (y - sc * 0.12).toFixed(1) + '" r="' + (sc * 0.6).toFixed(1) + '" fill="' + pal.head + '"/>';
    p += '<circle cx="' + (x - sc * 0.15).toFixed(1) + '" cy="' + (y - sc * 0.25).toFixed(1) + '" r="' + (sc * 0.3).toFixed(1) + '" fill="#C2D9A4" opacity="0.65"/>';
    return p;
  }
  if (type === 'tomato') {
    let p = '<path d="M' + x.toFixed(1) + ' ' + y.toFixed(1) + ' v-' + (sc * 2.1).toFixed(1) + '" stroke="#4A6B33" stroke-width="' + Math.max(1, sc * 0.16).toFixed(1) + '" fill="none"/>';
    for (let k = 0; k < 8; k++) {
      const ly = y - sc * 0.3 - (k / 8) * sc * 1.9, side = k % 2 ? 1 : -1;
      p += '<ellipse cx="' + (x + side * sc * (0.55 + j() * 0.2)).toFixed(1) + '" cy="' + ly.toFixed(1) +
           '" rx="' + (sc * 0.58).toFixed(1) + '" ry="' + (sc * 0.26).toFixed(1) +
           '" fill="' + (k % 2 ? pal.leafA : pal.leafB) + '" transform="rotate(' + (side * 22) + ' ' + x.toFixed(1) + ' ' + ly.toFixed(1) + ')"/>';
    }
    for (let k = 0; k < 3; k++) {
      if (r() > 0.45) {
        p += '<circle cx="' + (x + j() * sc * 1.3).toFixed(1) + '" cy="' + (y - sc * (0.6 + r() * 1.2)).toFixed(1) +
             '" r="' + (sc * 0.24).toFixed(1) + '" fill="' + pal.head + '"/>';
      }
    }
    return p;
  }
  if (type === 'spinach') {
    let p = '';
    for (let k = 0; k < 9; k++) {
      const a = (k / 9) * Math.PI * 2 + j() * 0.4;
      p += '<ellipse cx="' + (x + Math.cos(a) * sc * 0.6).toFixed(1) + '" cy="' + (y + Math.sin(a) * sc * 0.3).toFixed(1) +
           '" rx="' + (sc * 0.55).toFixed(1) + '" ry="' + (sc * 0.26).toFixed(1) +
           '" fill="' + (k % 2 ? pal.leafA : pal.leafB) + '" transform="rotate(' + (a * 57).toFixed(0) + ' ' + x.toFixed(1) + ' ' + y.toFixed(1) + ')"/>';
    }
    return p;
  }
  if (type === 'beans') {
    let p = '<path d="M' + x.toFixed(1) + ' ' + y.toFixed(1) + ' v-' + (sc * 1.5).toFixed(1) + '" stroke="#4E7038" stroke-width="' + Math.max(1, sc * 0.14).toFixed(1) + '" fill="none"/>';
    for (let k = 0; k < 6; k++) {
      const ly = y - (k / 6) * sc * 1.4, side = k % 2 ? 1 : -1;
      p += '<ellipse cx="' + (x + side * sc * 0.45).toFixed(1) + '" cy="' + ly.toFixed(1) + '" rx="' + (sc * 0.42).toFixed(1) +
           '" ry="' + (sc * 0.22).toFixed(1) + '" fill="' + (k % 2 ? pal.leafA : pal.leafB) + '"/>';
    }
    return p;
  }
  // bare: weeds / stubble
  let p = '';
  for (let k = 0; k < 4; k++) {
    p += '<path d="M' + x.toFixed(1) + ' ' + y.toFixed(1) + ' q' + (j() * sc).toFixed(1) + ' -' + (sc * 0.6).toFixed(1) +
         ' ' + (j() * sc * 1.4).toFixed(1) + ' -' + (sc * 0.9).toFixed(1) + '" stroke="' + pal.leafB +
         '" stroke-width="' + Math.max(0.8, sc * 0.12).toFixed(1) + '" fill="none" opacity="0.8"/>';
  }
  return p;
}

/* A planted plot in perspective: furrows receding to the horizon. */
function scenePlot(type, seed, W, H) {
  W = W || 400; H = H || 500;
  const pal = CROPS[type] || CROPS.cabbage;
  const base = skyAndLand(W, H, seed, { pal: pal, horizon: 0.26 });
  const r = base.r, hz = base.hz;
  let s = base.svg;

  const ROWS = 11;
  for (let i = 0; i < ROWS; i++) {
    const t = i / (ROWS - 1);
    const y = hz + Math.pow(t, 1.6) * (H - hz) * 1.06;
    const sc = 4 + Math.pow(t, 1.75) * 52;
    // furrow shadow under the row
    s += '<ellipse cx="' + (W / 2) + '" cy="' + (y + sc * 0.42).toFixed(1) + '" rx="' + (W * (0.6 + t * 0.4)).toFixed(1) +
         '" ry="' + (sc * 0.38 + 2).toFixed(1) + '" fill="#50381F" opacity="' + (0.10 + t * 0.14).toFixed(2) + '"/>';
    const n = Math.max(3, Math.round(11 - t * 6));
    for (let k = 0; k < n; k++) {
      const spread = W * (0.66 + t * 0.78);
      const x = W / 2 + ((k + 0.5) / n - 0.5) * spread + (r() - 0.5) * sc * 0.5;
      s += drawPlant(type, x, y, sc, r, pal);
    }
  }
  // sun haze + vignette
  s += '<rect width="' + W + '" height="' + H + '" fill="url(#sun' + seed + ')"/>';
  s += '<rect width="' + W + '" height="' + H + '" fill="none"/>';
  return svgWrap(s, W, H);
}

/* Bare, tilled, available land — North Plot. */
function sceneBarePlot(seed, W, H) {
  W = W || 400; H = H || 500;
  const pal = CROPS.bare;
  const base = skyAndLand(W, H, seed, { pal: pal, horizon: 0.32 });
  const r = base.r, hz = base.hz;
  let s = base.svg;
  for (let i = 0; i < 11; i++) {
    const t = i / 10;
    const y = hz + Math.pow(t, 1.8) * (H - hz) * 1.02;
    const w = W * (0.5 + t * 0.7);
    s += '<path d="M' + (W / 2 - w / 2) + ' ' + y.toFixed(1) + ' Q' + (W / 2) + ' ' + (y - 3 - t * 5).toFixed(1) +
         ' ' + (W / 2 + w / 2) + ' ' + y.toFixed(1) + '" stroke="#5B482F" stroke-width="' + (1 + t * 5).toFixed(1) +
         '" fill="none" opacity="0.5"/>';
    s += '<path d="M' + (W / 2 - w / 2) + ' ' + (y + 2 + t * 4).toFixed(1) + ' Q' + (W / 2) + ' ' + (y - 1 + t * 2).toFixed(1) +
         ' ' + (W / 2 + w / 2) + ' ' + (y + 2 + t * 4).toFixed(1) + '" stroke="#96794F" stroke-width="' + (1 + t * 3).toFixed(1) +
         '" fill="none" opacity="0.45"/>';
    if (t > 0.35) {
      for (let k = 0; k < 3; k++) {
        if (r() > 0.55) s += drawPlant('bare', W / 2 + (r() - 0.5) * w, y, 4 + t * 12, r, pal);
      }
    }
  }
  // fence posts on the left edge + water tank at the corner
  for (let i = 0; i < 4; i++) {
    const t = 0.25 + i * 0.22;
    const y = hz + Math.pow(t, 1.8) * (H - hz), h = 14 + t * 46, x = 18 + t * 8;
    s += '<rect x="' + x.toFixed(1) + '" y="' + (y - h).toFixed(1) + '" width="' + (2 + t * 4).toFixed(1) +
         '" height="' + h.toFixed(1) + '" fill="#4A3C28" opacity="0.85"/>';
  }
  s += '<g opacity="0.95"><ellipse cx="' + (W * 0.78) + '" cy="' + (hz + 4) + '" rx="26" ry="7" fill="#7E8C93"/>' +
       '<rect x="' + (W * 0.78 - 26) + '" y="' + (hz - 30) + '" width="52" height="34" rx="4" fill="#98A6AC"/>' +
       '<ellipse cx="' + (W * 0.78) + '" cy="' + (hz - 30) + '" rx="26" ry="7" fill="#B4C0C5"/>' +
       '<path d="M' + (W * 0.78 - 20) + ' ' + (hz - 24) + ' h40" stroke="#7E8C93" stroke-width="2"/></g>';
  s += '<rect width="' + W + '" height="' + H + '" fill="url(#sun' + seed + ')"/>';
  return svgWrap(s, W, H);
}

/* Wide landscape across Siyakhula Farm — hero card. */
function sceneFarm(seed, W, H) {
  W = W || 640; H = H || 440;
  const pal = CROPS.cabbage;
  const base = skyAndLand(W, H, seed, { pal: pal, horizon: 0.42 });
  const r = base.r, hz = base.hz;
  let s = base.svg;
  // strip fields receding
  const strips = [
    { c1: '#6E9A57', c2: '#557F45' }, { c1: '#7E8C4F', c2: '#5F6E3C' },
    { c1: '#8A7A50', c2: '#6E603D' }, { c1: '#5F8A4C', c2: '#47693A' },
  ];
  for (let i = 0; i < 5; i++) {
    const t = i / 4;
    const y0 = hz + Math.pow(t, 1.6) * (H - hz) * 0.9;
    const y1 = hz + Math.pow((i + 1) / 4, 1.6) * (H - hz) * 0.9;
    const c = strips[i % strips.length];
    s += '<path d="M' + (-W * t * 0.4) + ' ' + y0 + ' L' + (W + W * t * 0.4) + ' ' + y0 + ' L' + (W + W * 0.5) + ' ' + y1 +
         ' L' + (-W * 0.5) + ' ' + y1 + 'Z" fill="' + c.c1 + '"/>';
    for (let k = 0; k < 22; k++) {
      const x = (k / 22) * W * 1.6 - W * 0.3;
      s += '<path d="M' + x.toFixed(0) + ' ' + y0 + ' L' + (x - 22).toFixed(0) + ' ' + y1 + '" stroke="' + c.c2 +
           '" stroke-width="' + (1.5 + t * 4).toFixed(1) + '" opacity="0.55"/>';
    }
  }
  // farmhouse + tank + trees on the horizon
  s += '<g><rect x="' + (W * 0.12) + '" y="' + (hz - 34) + '" width="66" height="34" fill="#C9BFAA"/>' +
       '<path d="M' + (W * 0.12 - 8) + ' ' + (hz - 34) + ' L' + (W * 0.12 + 33) + ' ' + (hz - 52) + ' L' + (W * 0.12 + 74) + ' ' + (hz - 34) + 'Z" fill="#8C5A3C"/>' +
       '<rect x="' + (W * 0.12 + 24) + '" y="' + (hz - 20) + '" width="14" height="20" fill="#5E4B33"/></g>';
  s += '<g><rect x="' + (W * 0.72) + '" y="' + (hz - 26) + '" width="34" height="26" rx="3" fill="#9AA8AE"/>' +
       '<ellipse cx="' + (W * 0.72 + 17) + '" cy="' + (hz - 26) + '" rx="17" ry="5" fill="#B8C4C9"/></g>';
  for (let i = 0; i < 6; i++) {
    const x = W * 0.3 + r() * W * 0.55, th = 16 + r() * 16;
    s += '<ellipse cx="' + x.toFixed(0) + '" cy="' + (hz - th * 0.5) + '" rx="' + (th * 0.65).toFixed(0) + '" ry="' + th.toFixed(0) + '" fill="#3F5C3B" opacity="0.8"/>';
  }
  s += '<rect width="' + W + '" height="' + H + '" fill="url(#sun' + seed + ')"/>';
  return svgWrap(s, W, H);
}

/* Top-down plot map of Siyakhula Farm. */
function sceneMap(W, H, opts) {
  W = W || 400; H = H || 240;
  opts = opts || {};
  const zones = [
    { d: 'M42 46 L176 38 L188 116 L52 126 Z', fill: '#6E9A57', name: 'Cabbage Field', st: 'on-track' },
    { d: 'M196 36 L330 30 L338 104 L206 114 Z', fill: '#B4763F', name: 'Tomato Section', st: 'attention' },
    { d: 'M48 136 L186 126 L196 200 L58 208 Z', fill: '#9A9068', name: 'North Plot', st: 'idle' },
    { d: 'M206 124 L336 114 L344 196 L214 206 Z', fill: '#4E8A4C', name: 'Spinach Beds', st: 'on-track' },
  ];
  const stColor = { 'on-track': '#1B7A45', attention: '#B57A12', idle: '#6F6B5F', action: '#B4261A' };
  /* The farm block is authored at 400x240. For a taller canvas we keep that
     block intact and grow the surrounding land around it, rather than
     stretching the plots out of proportion. */
  const FARM_H = 240;
  const dy = Math.max(0, (H - FARM_H) / 2);
  let s = '<rect width="' + W + '" height="' + H + '" fill="#DED7C6"/>';
  for (let i = 0; i * 10 < H; i++) {
    s += '<rect y="' + (i * 10) + '" width="' + W + '" height="4" fill="#D5CDBA" opacity="0.5"/>';
  }
  // neighbouring plots above and below, so a tall map is not empty paper
  if (dy > 20) {
    for (let k = 0; k < 6; k++) {
      const by = (k < 3 ? 8 + k * (dy / 3.4) : dy + FARM_H + (k - 3) * ((H - dy - FARM_H) / 3.2));
      if (by > H - 24) continue;
      s += '<rect x="' + (18 + (k % 3) * 122) + '" y="' + by.toFixed(0) + '" width="104" height="' +
           Math.min(62, Math.max(24, dy / 3.8)).toFixed(0) + '" rx="4" fill="' +
           ['#C7C0AA', '#BFCAAE', '#CBBFA6'][k % 3] + '" opacity="0.75"/>';
    }
  }
  s += '<g transform="translate(0 ' + dy.toFixed(0) + ')">';
  s += '<path d="M0 224 Q120 214 210 226 T400 218 L400 240 L0 240Z" fill="#C3BCA9"/>';
  // dirt access track
  s += '<path d="M8 236 C80 190 60 120 26 20" stroke="#BFA57C" stroke-width="13" fill="none" stroke-linecap="round"/>';
  s += '<path d="M8 236 C80 190 60 120 26 20" stroke="#D8C6A6" stroke-width="7" fill="none" stroke-linecap="round" stroke-dasharray="1 9"/>';
  // farm boundary
  s += '<path d="M32 26 L348 18 L356 210 L44 220 Z" fill="none" stroke="#1C1B16" stroke-width="2.5" stroke-dasharray="9 5" opacity="0.65"/>';
  zones.forEach(function (z) {
    s += '<path d="' + z.d + '" fill="' + z.fill + '" fill-opacity="0.85" stroke="#FBFAF6" stroke-width="2"/>';
  });
  // furrow hatching inside planted zones
  s += '<g opacity="0.3" stroke="#2C3B22" stroke-width="1.5">';
  for (let x = 46; x < 186; x += 9) s += '<path d="M' + x + ' 44 L' + (x + 4) + ' 122"/>';
  for (let x = 200; x < 336; x += 9) s += '<path d="M' + x + ' 36 L' + (x + 4) + ' 110"/>';
  for (let x = 210; x < 342; x += 7) s += '<path d="M' + x + ' 122 L' + (x + 4) + ' 202"/>';
  s += '</g>';
  // water tank + house pins
  s += '<circle cx="352" cy="120" r="9" fill="#8FB8CC" stroke="#FBFAF6" stroke-width="2"/>';
  s += '<rect x="20" y="18" width="20" height="16" rx="2" fill="#8C5A3C" stroke="#FBFAF6" stroke-width="2"/>';
  if (opts.labels !== false) {
    zones.forEach(function (z) {
      const m = z.d.match(/M(\d+) (\d+)/);
      const x = parseInt(m[1], 10) + 8, y = parseInt(m[2], 10) + 22;
      const wpx = z.name.length * 6.1 + 26;
      s += '<g><rect x="' + x + '" y="' + y + '" width="' + wpx + '" height="22" rx="11" fill="#FBFAF6" opacity="0.94"/>' +
           '<circle cx="' + (x + 13) + '" cy="' + (y + 11) + '" r="4.5" fill="' + stColor[z.st] + '"/>' +
           '<text x="' + (x + 22) + '" y="' + (y + 15) + '" font-family="Inter, sans-serif" font-size="13" font-weight="600" fill="#1C1B16">' +
           z.name + '</text></g>';
    });
  }
  if (opts.me !== false) {
    s += '<circle cx="120" cy="188" r="16" fill="#1A4E72" opacity="0.18"/>' +
         '<circle cx="120" cy="188" r="7" fill="#1A4E72" stroke="#FBFAF6" stroke-width="2.5"/>';
  }
  s += '</g>';
  return svgWrap(s, W, H);
}

/* Live camera frame: close-up cabbage heads, as the CV sees them. */
function sceneCamera(W, H) {
  W = W || 390; H = H || 844;
  const r = rng(77);
  let s = '<defs><radialGradient id="camv" cx="0.5" cy="0.45" r="0.78">' +
    '<stop offset="0.5" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity="0.45"/></radialGradient>' +
    '<linearGradient id="camsoil" x1="0" y1="0" x2="0" y2="1">' +
    '<stop offset="0" stop-color="#4E3E28"/><stop offset="1" stop-color="#6B563A"/></linearGradient>' +
    '<filter id="camgrain"><feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="3" stitchTiles="stitch"/>' +
    '<feColorMatrix type="saturate" values="0"/></filter></defs>';
  s += '<rect width="' + W + '" height="' + H + '" fill="url(#camsoil)"/>';
  // soil speckle
  for (let i = 0; i < 260; i++) {
    s += '<circle cx="' + (r() * W).toFixed(0) + '" cy="' + (r() * H).toFixed(0) + '" r="' + (0.6 + r() * 2.2).toFixed(1) +
         '" fill="#3B2F1F" opacity="' + (0.15 + r() * 0.3).toFixed(2) + '"/>';
  }
  // cabbage heads, near ones larger; loose rows with overlap
  const heads = [
    { x: 0.30, y: 0.72, s: 78, yellow: true },
    { x: 0.74, y: 0.66, s: 70 },
    { x: 0.14, y: 0.52, s: 56 },
    { x: 0.52, y: 0.50, s: 60 },
    { x: 0.88, y: 0.45, s: 48 },
    { x: 0.30, y: 0.36, s: 44 },
    { x: 0.66, y: 0.33, s: 42 },
    { x: 0.10, y: 0.26, s: 34 },
    { x: 0.45, y: 0.22, s: 32 },
    { x: 0.82, y: 0.19, s: 30 },
  ].map(function (h) { return { x: h.x * W, y: h.y * H, s: h.s, yellow: h.yellow }; });

  heads.sort(function (a, b) { return a.y - b.y; }).forEach(function (h, idx) {
    s += '<ellipse cx="' + h.x.toFixed(0) + '" cy="' + (h.y + h.s * 0.55).toFixed(0) + '" rx="' + (h.s * 1.1).toFixed(0) +
         '" ry="' + (h.s * 0.34).toFixed(0) + '" fill="#241B0F" opacity="0.35"/>';
    // outer wrapper leaves
    for (let k = 0; k < 10; k++) {
      const a = (k / 10) * Math.PI * 2 + idx * 0.7;
      const rx = h.s * (0.82 + r() * 0.16), ry = h.s * (0.42 + r() * 0.12);
      s += '<ellipse cx="' + (h.x + Math.cos(a) * h.s * 0.6).toFixed(1) + '" cy="' + (h.y + Math.sin(a) * h.s * 0.36).toFixed(1) +
           '" rx="' + rx.toFixed(1) + '" ry="' + ry.toFixed(1) + '" fill="' + (k % 3 === 0 ? '#3F6B34' : k % 2 ? '#5B8C48' : '#4C7A3D') +
           '" transform="rotate(' + (a * 57).toFixed(0) + ' ' + h.x.toFixed(1) + ' ' + h.y.toFixed(1) + ')"/>';
    }
    // head
    s += '<circle cx="' + h.x.toFixed(1) + '" cy="' + (h.y - h.s * 0.08).toFixed(1) + '" r="' + (h.s * 0.54).toFixed(1) + '" fill="#8FB26A"/>';
    s += '<circle cx="' + (h.x - h.s * 0.14).toFixed(1) + '" cy="' + (h.y - h.s * 0.22).toFixed(1) + '" r="' + (h.s * 0.34).toFixed(1) +
         '" fill="#B3CE8C" opacity="0.8"/>';
    // vein detail
    for (let k = 0; k < 5; k++) {
      const a = (k / 5) * Math.PI * 2 + 0.4;
      s += '<path d="M' + h.x.toFixed(1) + ' ' + (h.y - h.s * 0.08).toFixed(1) + ' l' + (Math.cos(a) * h.s * 0.5).toFixed(1) +
           ' ' + (Math.sin(a) * h.s * 0.32).toFixed(1) + '" stroke="#6D9450" stroke-width="' + (h.s * 0.035).toFixed(1) +
           '" opacity="0.6" fill="none"/>';
    }
    if (h.yellow) {
      s += '<ellipse cx="' + (h.x + h.s * 0.62).toFixed(1) + '" cy="' + (h.y + h.s * 0.14).toFixed(1) + '" rx="' + (h.s * 0.44).toFixed(1) +
           '" ry="' + (h.s * 0.22).toFixed(1) + '" fill="#C6BC4E" opacity="0.8" transform="rotate(22 ' + h.x.toFixed(1) + ' ' + h.y.toFixed(1) + ')"/>';
      s += '<ellipse cx="' + (h.x - h.s * 0.66).toFixed(1) + '" cy="' + (h.y + h.s * 0.24).toFixed(1) + '" rx="' + (h.s * 0.36).toFixed(1) +
           '" ry="' + (h.s * 0.18).toFixed(1) + '" fill="#BCAF46" opacity="0.7" transform="rotate(-14 ' + h.x.toFixed(1) + ' ' + h.y.toFixed(1) + ')"/>';
    }
  });
  // sensor grain + vignette: the difference between a lens and a vector drawing
  s += '<rect width="' + W + '" height="' + H + '" filter="url(#camgrain)" opacity="0.2" ' +
       'style="mix-blend-mode:overlay"/>';
  s += '<rect width="' + W + '" height="' + H + '" fill="url(#camv)"/>';

  /* CV detections drawn in the same coordinate space as the plants, so the
     boxes actually track objects instead of floating over the frame. */
  const dets = [
    { h: heads.filter(function (x) { return x.yellow; })[0], label: 'CABBAGE · 96%', tone: 'ok' },
    { h: heads[4], label: 'CABBAGE · 91%', tone: 'ok' },
  ];
  dets.forEach(function (d) {
    if (!d.h) return;
    s += detBox(d.h.x - d.h.s * 1.15, d.h.y - d.h.s * 0.75, d.h.s * 2.3, d.h.s * 1.5, d.label, '#A8F0C0', '#05250F');
  });
  const yh = heads.filter(function (x) { return x.yellow; })[0];
  if (yh) s += detBox(yh.x + yh.s * 0.16, yh.y - yh.s * 0.16, yh.s * 0.95, yh.s * 0.62,
                      'LEAF YELLOWING · 81%', '#FFD79A', '#3A2400');
  return svgWrap(s, W, H);
}

/* Small square crop portraits for recommendation cards and thumbnails. */
function sceneCrop(type, seed, W, H) {
  W = W || 320; H = H || 200;
  const pal = CROPS[type] || CROPS.cabbage;
  const r = rng(seed);
  let s = '<defs><linearGradient id="cg' + seed + '" x1="0" y1="0" x2="0" y2="1">' +
    '<stop offset="0" stop-color="#B99C74"/><stop offset="1" stop-color="' + pal.soil + '"/></linearGradient></defs>';
  s += '<rect width="' + W + '" height="' + H + '" fill="url(#cg' + seed + ')"/>';
  for (let row = 0; row < 4; row++) {
    const y = H * (0.22 + row * 0.27), sc = 13 + row * 13;
    const n = 6 - row;
    for (let k = 0; k < n; k++) {
      const x = ((k + 0.5) / n) * W + (r() - 0.5) * 18;
      s += drawPlant(type, x, y, sc, r, pal);
    }
  }
  return svgWrap(s, W, H);
}

/* One CV detection box with its label, in SVG user units. */
function detBox(x, y, w, h, label, stroke, ink) {
  const lw = label.length * 7.3 + 16;
  return '<g>' +
    '<rect x="' + x.toFixed(0) + '" y="' + y.toFixed(0) + '" width="' + w.toFixed(0) + '" height="' + h.toFixed(0) +
    '" rx="7" fill="none" stroke="' + stroke + '" stroke-width="2.5"/>' +
    '<rect x="' + x.toFixed(0) + '" y="' + (y - 21).toFixed(0) + '" width="' + lw.toFixed(0) +
    '" height="21" rx="5" fill="' + stroke + '"/>' +
    '<text x="' + (x + 8).toFixed(0) + '" y="' + (y - 6).toFixed(0) + '" font-family="Inter, sans-serif" ' +
    'font-size="13" font-weight="600" fill="' + ink + '">' + label + '</text></g>';
}


/* ---------------------------------------------------- onboarding artwork --
   Flat illustration rather than photography: these four cards explain a
   concept, and a photograph of a farm cannot show "your sections stay linked
   to the land". Drawn in token-adjacent colours so they sit in either theme.
-------------------------------------------------------------------------- */
function artZones(W, H) {
  W = W || 340; H = H || 300;
  let s = '<rect width="' + W + '" height="' + H + '" fill="#DED7C6"/>';
  s += '<path d="M0 ' + (H - 40) + ' Q' + (W / 2) + ' ' + (H - 64) + ' ' + W + ' ' + (H - 44) + ' L' + W + ' ' + H + ' L0 ' + H + 'Z" fill="#CFC7B3"/>';
  const zones = [
    ['M38 54 L164 44 L172 132 L46 142Z', '#6E9A57', '#1B7A45'],
    ['M184 42 L300 34 L308 120 L192 130Z', '#B4763F', '#B57A12'],
    ['M44 152 L170 142 L178 226 L52 234Z', '#9A9068', '#6F6B5F'],
    ['M190 140 L306 130 L314 220 L198 230Z', '#4E8A4C', '#1B7A45'],
  ];
  zones.forEach(function (z) {
    s += '<path d="' + z[0] + '" fill="' + z[1] + '" fill-opacity="0.9" stroke="#FBFAF6" stroke-width="2.5"/>';
  });
  s += '<g opacity="0.28" stroke="#2C3B22" stroke-width="1.6">';
  for (let x = 44; x < 168; x += 10) s += '<path d="M' + x + ' 52 L' + (x + 4) + ' 138"/>';
  for (let x = 196; x < 306; x += 10) s += '<path d="M' + x + ' 138 L' + (x + 4) + ' 226"/>';
  s += '</g>';
  s += '<path d="M28 34 L318 24 L326 240 L36 250Z" fill="none" stroke="#1C1B16" stroke-width="2.5" stroke-dasharray="9 5" opacity="0.55"/>';
  zones.forEach(function (z, i) {
    const m = z[0].match(/M(\d+) (\d+)/);
    const x = parseInt(m[1], 10) + 10, y = parseInt(m[2], 10) + 20;
    s += '<circle cx="' + x + '" cy="' + y + '" r="6" fill="' + z[2] + '" stroke="#FBFAF6" stroke-width="2"/>';
  });
  return svgWrap(s, W, H);
}

function artScan(W, H) {
  W = W || 340; H = H || 300;
  let s = '<rect width="' + W + '" height="' + H + '" fill="#E3E7DA"/>';
  s += '<circle cx="' + (W * 0.5) + '" cy="' + (H * 0.5) + '" r="118" fill="#D2DCC6"/>';
  // phone
  s += '<rect x="' + (W / 2 - 62) + '" y="34" width="124" height="232" rx="20" fill="#1E1F1A"/>';
  s += '<rect x="' + (W / 2 - 54) + '" y="46" width="108" height="208" rx="14" fill="#8FB26A"/>';
  // plant inside the screen
  const cx = W / 2, cy = 168;
  for (let k = 0; k < 8; k++) {
    const a = (k / 8) * Math.PI * 2;
    s += '<ellipse cx="' + (cx + Math.cos(a) * 26).toFixed(1) + '" cy="' + (cy + Math.sin(a) * 17).toFixed(1) +
         '" rx="30" ry="18" fill="' + (k % 2 ? '#5B8C48' : '#4C7A3D') + '" transform="rotate(' + (a * 57).toFixed(0) + ' ' + cx + ' ' + cy + ')"/>';
  }
  s += '<circle cx="' + cx + '" cy="' + (cy - 4) + '" r="22" fill="#BBD495"/>';
  // scan brackets
  const bx = cx - 52, by = cy - 46, bw = 104, bh = 92;
  [[0, 0, 1, 1], [1, 0, -1, 1], [0, 1, 1, -1], [1, 1, -1, -1]].forEach(function (c) {
    const px = bx + c[0] * bw, py = by + c[1] * bh;
    s += '<path d="M' + (px + c[2] * 22) + ' ' + py + ' H' + px + ' V' + (py + c[3] * 22) +
         '" stroke="#FBFAF6" stroke-width="3.5" fill="none" stroke-linecap="round"/>';
  });
  s += '<rect x="' + (cx - 52) + '" y="' + (cy - 8) + '" width="104" height="3" fill="#FBFAF6" opacity="0.85"/>';
  // result chip
  s += '<g><rect x="' + (cx - 46) + '" y="216" width="92" height="24" rx="12" fill="#FBFAF6"/>' +
       '<circle cx="' + (cx - 32) + '" cy="228" r="5" fill="#1B7A45"/>' +
       '<text x="' + (cx - 22) + '" y="233" font-family="Inter, sans-serif" font-size="13" font-weight="600" fill="#1C1B16">Healthy</text></g>';
  return svgWrap(s, W, H);
}

function artCompare(W, H) {
  W = W || 340; H = H || 300;
  let s = '<rect width="' + W + '" height="' + H + '" fill="#E7E3D6"/>';
  const cards = [
    { x: 26, y: 54, h: 196, crop: '#7FAE60', name: 'Cabbage', v: 'R17,400', bar: 0.78, tone: '#1B7A45' },
    { x: 182, y: 78, h: 172, crop: '#CE4A2E', name: 'Tomatoes', v: 'R22,100', bar: 0.95, tone: '#B57A12' },
  ];
  cards.forEach(function (c) {
    s += '<rect x="' + c.x + '" y="' + c.y + '" width="132" height="' + c.h + '" rx="20" fill="#FBFAF6"/>';
    s += '<rect x="' + (c.x + 10) + '" y="' + (c.y + 10) + '" width="112" height="72" rx="14" fill="' + c.crop + '"/>';
    for (let k = 0; k < 5; k++) {
      s += '<circle cx="' + (c.x + 24 + k * 22) + '" cy="' + (c.y + 56) + '" r="11" fill="#FBFAF6" opacity="0.32"/>';
    }
    s += '<text x="' + (c.x + 12) + '" y="' + (c.y + 104) + '" font-family="Inter, sans-serif" font-size="14" font-weight="600" fill="#1C1B16">' + c.name + '</text>';
    s += '<text x="' + (c.x + 12) + '" y="' + (c.y + 128) + '" font-family="Inter, sans-serif" font-size="17" font-weight="700" fill="' + c.tone + '">' + c.v + '</text>';
    s += '<rect x="' + (c.x + 12) + '" y="' + (c.y + 140) + '" width="108" height="7" rx="4" fill="#E4DFD2"/>';
    s += '<rect x="' + (c.x + 12) + '" y="' + (c.y + 140) + '" width="' + (108 * c.bar).toFixed(0) + '" height="7" rx="4" fill="' + c.tone + '"/>';
    s += '<rect x="' + (c.x + 12) + '" y="' + (c.y + 158) + '" width="62" height="18" rx="9" fill="#C7E7D1"/>';
    s += '<rect x="' + (c.x + 12) + '" y="' + (c.y + 182) + '" width="84" height="18" rx="9" fill="#EDE9DF"/>';
  });
  return svgWrap(s, W, H);
}

function artVoice(W, H) {
  W = W || 340; H = H || 300;
  let s = '<rect width="' + W + '" height="' + H + '" fill="#DDE6D6"/>';
  s += '<circle cx="' + (W / 2) + '" cy="' + (H / 2) + '" r="112" fill="#CBDCC2"/>';
  // farmer silhouette
  s += '<circle cx="' + (W / 2 - 66) + '" cy="126" r="27" fill="#5A4630"/>';
  s += '<path d="M' + (W / 2 - 110) + ' 232 a44 44 0 0 1 88 0Z" fill="#5A4630"/>';
  s += '<path d="M' + (W / 2 - 92) + ' 108 a26 26 0 0 1 52 0 z" fill="#8C5A3C"/>';
  s += '<ellipse cx="' + (W / 2 - 66) + '" cy="108" rx="40" ry="7" fill="#8C5A3C"/>';
  // waveform
  const bars = [16, 30, 48, 26, 58, 34, 20, 42, 24];
  bars.forEach(function (b, i) {
    s += '<rect x="' + (W / 2 - 6 + i * 13) + '" y="' + (168 - b / 2) + '" width="6" height="' + b + '" rx="3" fill="#1D5233" opacity="' + (0.45 + (i % 3) * 0.2).toFixed(2) + '"/>';
  });
  // logo button — the real app mark
  s += '<circle cx="' + (W / 2 + 54) + '" cy="236" r="30" fill="#012120"/>';
  s += '<image href="assets/brand/mark.svg" x="' + (W / 2 + 54 - 13) + '" y="221" width="26" height="30"/>';
  s += '<circle cx="' + (W / 2 + 54) + '" cy="236" r="38" fill="none" stroke="#1D5233" stroke-width="2" opacity="0.4"/>';
  s += '<circle cx="' + (W / 2 + 54) + '" cy="236" r="46" fill="none" stroke="#1D5233" stroke-width="2" opacity="0.18"/>';
  return svgWrap(s, W, H);
}

function svgWrap(inner, W, H) {
  return '<svg viewBox="0 0 ' + W + ' ' + H + '" preserveAspectRatio="xMidYMid slice" ' +
         'xmlns="http://www.w3.org/2000/svg" role="img" aria-hidden="true">' + inner + '</svg>';
}

const SCENES = {
  cabbage:  function () { return scenePlot('cabbage', 11); },
  tomato:   function () { return scenePlot('tomato', 23); },
  spinach:  function () { return scenePlot('spinach', 41); },
  north:    function () { return sceneBarePlot(59); },
  /* landscape variants for hero crops, so a 4:5 plot is not sliced to a
     close-up when it sits in a 38%-height hero */
  cabbageWide: function () { return scenePlot('cabbage', 11, 460, 330); },
  tomatoWide:  function () { return scenePlot('tomato', 23, 460, 330); },
  farm:     function () { return sceneFarm(7); },
  farmWide: function () { return sceneFarm(7, 1000, 300); },
  map:      function () { return sceneMap(400, 240, {}); },
  mapTall:  function () { return sceneMap(400, 300, {}); },
  camera:   function () { return sceneCamera(390, 844); },
  cropCabbage: function () { return scenePlot('cabbage', 91, 440, 260); },
  cropTomato:  function () { return scenePlot('tomato', 93, 440, 260); },
  cropBeans:   function () { return scenePlot('beans', 95, 440, 260); },
  thumbCabbage: function () { return sceneCrop('cabbage', 97, 120, 120); },
  thumbTomato:  function () { return sceneCrop('tomato', 99, 120, 120); },
  thumbSpinach: function () { return sceneCrop('spinach', 101, 120, 120); },
  artZones:   function () { return artZones(); },
  artScan:    function () { return artScan(); },
  artCompare: function () { return artCompare(); },
  artVoice:   function () { return artVoice(); },
  mapFull:    function () { return sceneMap(390, 620, {}); },
  mapSetup:   function () { return sceneMap(390, 560, { labels: false }); },
};

/* -------------------------------------------------------------- hydration -- */
const SCENE_CACHE = {};
function hydrate(root) {
  root = root || document;
  root.querySelectorAll('[data-icon]').forEach(function (el) {
    if (el.dataset.done) return;
    el.innerHTML = icon(el.dataset.icon);
    el.dataset.done = '1';
  });
  root.querySelectorAll('[data-scene]').forEach(function (el) {
    if (el.dataset.done) return;
    const key = el.dataset.scene;
    const f = SCENES[key];
    if (f) {
      if (!(key in SCENE_CACHE)) SCENE_CACHE[key] = f();
      el.innerHTML = SCENE_CACHE[key];
    }
    el.dataset.done = '1';
  });
}

/* ------------------------------------------------------- carousel scaling --
   Centre card scale 1.0, neighbours ~0.88, driven continuously by scroll
   position rather than snapping after the page changes.
---------------------------------------------------------------------------- */
function initCarousels(root) {
  (root || document).querySelectorAll('.carousel').forEach(function (car) {
    if (car.dataset.bound) return;
    car.dataset.bound = '1';
    const items = Array.prototype.slice.call(car.children);
    function update() {
      const mid = car.scrollLeft + car.clientWidth / 2;
      items.forEach(function (it) {
        const c = it.offsetLeft + it.offsetWidth / 2;
        const d = Math.min(1, Math.abs(c - mid) / (it.offsetWidth * 1.05));
        it.style.setProperty('--s', (1 - 0.12 * d).toFixed(3));
        it.style.setProperty('--o', (1 - 0.22 * d).toFixed(3));
      });
    }
    car.addEventListener('scroll', function () {
      if (car._raf) return;
      car._raf = requestAnimationFrame(function () { car._raf = null; update(); });
    }, { passive: true });
    // start centred on the first card
    requestAnimationFrame(function () {
      const first = items[0];
      if (first) car.scrollLeft = first.offsetLeft + first.offsetWidth / 2 - car.clientWidth / 2;
      update();
    });
    window.addEventListener('resize', update);
  });
}

/* ------------------------------------------------------------ shell wiring */
function initShell() {
  const body = document.body;
  const saved = localStorage.getItem('farmable-theme');
  if (saved) body.dataset.theme = saved;

  document.querySelectorAll('[data-toggle-theme]').forEach(function (btn) {
    btn.addEventListener('click', function () {
      const next = body.dataset.theme === 'dark' ? 'light' : 'dark';
      body.dataset.theme = next;
      try { localStorage.setItem('farmable-theme', next); } catch (e) {}
      syncToggles();
    });
  });
  const FONT_MODES = ['system', 'android'];
  const savedFont = localStorage.getItem('farmable-font');
  /* ignore values written by an earlier font scheme */
  body.dataset.font = FONT_MODES.indexOf(savedFont) >= 0 ? savedFont : 'system';
  document.querySelectorAll('[data-font-set]').forEach(function (btn) {
    btn.addEventListener('click', function () {
      body.dataset.font = btn.dataset.fontSet;
      try { localStorage.setItem('farmable-font', btn.dataset.fontSet); } catch (e) {}
      syncToggles();
    });
  });
  document.querySelectorAll('[data-size-set]').forEach(function (btn) {
    btn.addEventListener('click', function () {
      body.dataset.size = btn.dataset.sizeSet;
      syncToggles();
    });
  });
  function syncToggles() {
    document.querySelectorAll('[data-size-set]').forEach(function (b) {
      b.setAttribute('aria-pressed', String(b.dataset.sizeSet === (body.dataset.size || 'standard')));
    });
    document.querySelectorAll('[data-font-set]').forEach(function (b) {
      b.setAttribute('aria-pressed', String(b.dataset.fontSet === (body.dataset.font || 'system')));
    });
    document.querySelectorAll('[data-theme-label]').forEach(function (el) {
      el.textContent = body.dataset.theme === 'dark' ? 'Dark' : 'Light';
    });
  }
  syncToggles();

  // Sheets / panels inside device frames
  document.querySelectorAll('[data-sheet-toggle]').forEach(function (btn) {
    btn.addEventListener('click', function () {
      const screen = btn.closest('.device-screen');
      if (screen) screen.classList.toggle('sheet-open');
    });
  });
  // AI state cycling demo
  document.querySelectorAll('[data-ai-cycle]').forEach(function (btn) {
    const states = ['idle', 'listening', 'understanding', 'speaking'];
    btn.addEventListener('click', function () {
      const host = btn.closest('[data-ai]') || btn;
      const i = states.indexOf(host.dataset.ai || 'idle');
      host.dataset.ai = states[(i + 1) % states.length];
      const lbl = host.querySelector('[data-ai-label]');
      if (lbl) lbl.textContent = { idle: 'Hold to speak', listening: 'Listening…', understanding: 'Working…', speaking: 'Speaking' }[host.dataset.ai];
    });
  });
}

document.addEventListener('DOMContentLoaded', function () {
  hydrate();
  initCarousels();
  initShell();
});
