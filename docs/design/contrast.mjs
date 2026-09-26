// WCAG 2.1 relative luminance + contrast ratio checker for the Farmable palette.
const srgb = c => { c /= 255; return c <= 0.04045 ? c/12.92 : Math.pow((c+0.055)/1.055, 2.4); };
const lum = hex => { const h = hex.replace('#',''); const r=parseInt(h.slice(0,2),16),g=parseInt(h.slice(2,4),16),b=parseInt(h.slice(4,6),16);
  return 0.2126*srgb(r)+0.7152*srgb(g)+0.0722*srgb(b); };
const ratio = (a,b) => { const l1=lum(a), l2=lum(b); const [hi,lo]=l1>l2?[l1,l2]:[l2,l1]; return (hi+0.05)/(lo+0.05); };

const L = {
  background:'#F4F1EA', surface:'#FBFAF6', surfaceContainer:'#EDE9DF', surfaceContainerHigh:'#E4DFD2',
  onSurface:'#1C1B16', onSurfaceVariant:'#4A473E', outline:'#6F6B5F', outlineVariant:'#CFC9BA',
  primary:'#1D5233', onPrimary:'#FFFFFF', primaryContainer:'#C7E7D1', onPrimaryContainer:'#0A2C18',
  secondary:'#5A4630', onSecondary:'#FFFFFF', secondaryContainer:'#EDDFC8', onSecondaryContainer:'#2B2012',
  tertiary:'#1A4E72', onTertiary:'#FFFFFF', tertiaryContainer:'#CFE4F3', onTertiaryContainer:'#082D44',
  inkSurface:'#1E1F1A', onInkSurface:'#EFECE1', onInkSurfaceVariant:'#B7B2A3',
  statusOnTrack:'#18663A', statusOnTrackContainer:'#C7E7D1', onStatusOnTrackContainer:'#0A2C18',
  statusNeedsAttention:'#8A5300', statusNeedsAttentionContainer:'#FAE3BC', onStatusNeedsAttentionContainer:'#432700',
  statusActionRequired:'#A31C12', statusActionRequiredContainer:'#FBD9D4', onStatusActionRequiredContainer:'#4C0B06',
  connOffline:'#455360', connOfflineContainer:'#DCE3EA', onConnOfflineContainer:'#1C2831',
  connSyncing:'#1A4E72', connSynced:'#18663A',
  scrimText:'#FFFFFF', scrimBase:'#2B2B26',
};
const D = {
  background:'#000000', surface:'#1A1B16', surfaceContainer:'#232420', surfaceContainerHigh:'#2C2E28',
  onSurface:'#ECE9DE', onSurfaceVariant:'#C2BEAF', outline:'#928D7E', outlineVariant:'#4A4840',
  primary:'#8ED3A3', onPrimary:'#032E17', primaryContainer:'#2A5740', onPrimaryContainer:'#CAEFD6',
  secondary:'#DCC49E', onSecondary:'#2E2113', secondaryContainer:'#4C3A25', onSecondaryContainer:'#F0DEC2',
  tertiary:'#8FCBEC', onTertiary:'#032F48', tertiaryContainer:'#22506E', onTertiaryContainer:'#CBE6F7',
  inkSurface:'#23241E', onInkSurface:'#ECE9DE', onInkSurfaceVariant:'#C2BEAF',
  statusOnTrack:'#7ACB95', statusOnTrackContainer:'#22503A', onStatusOnTrackContainer:'#C3EBD1',
  statusNeedsAttention:'#F0B855', statusNeedsAttentionContainer:'#5A3E0B', onStatusNeedsAttentionContainer:'#FBDFAE',
  statusActionRequired:'#FF9186', statusActionRequiredContainer:'#6B1C14', onStatusActionRequiredContainer:'#FFD8D2',
  connOffline:'#A9B7C5', connOfflineContainer:'#333C45', onConnOfflineContainer:'#D5DFE8',
  connSyncing:'#8FCBEC', connSynced:'#7ACB95',
  scrimText:'#FFFFFF', scrimBase:'#000000',
};

const pairs = t => [
  ['onSurface','surface'],['onSurface','background'],['onSurface','surfaceContainer'],['onSurface','surfaceContainerHigh'],
  ['onSurfaceVariant','surface'],['onSurfaceVariant','background'],['onSurfaceVariant','surfaceContainer'],['onSurfaceVariant','surfaceContainerHigh'],
  ['outline','surface'],['outline','background'],
  ['onPrimary','primary'],['onPrimaryContainer','primaryContainer'],['primary','surface'],['primary','background'],
  ['onSecondary','secondary'],['onSecondaryContainer','secondaryContainer'],['secondary','surface'],
  ['onTertiary','tertiary'],['onTertiaryContainer','tertiaryContainer'],['tertiary','surface'],
  ['onInkSurface','inkSurface'],['onInkSurfaceVariant','inkSurface'],
  ['statusOnTrack','surface'],['statusOnTrack','background'],['statusOnTrack','surfaceContainer'],
  ['onStatusOnTrackContainer','statusOnTrackContainer'],
  ['statusNeedsAttention','surface'],['statusNeedsAttention','background'],['statusNeedsAttention','surfaceContainer'],
  ['onStatusNeedsAttentionContainer','statusNeedsAttentionContainer'],
  ['statusActionRequired','surface'],['statusActionRequired','background'],['statusActionRequired','surfaceContainer'],
  ['onStatusActionRequiredContainer','statusActionRequiredContainer'],
  ['connOffline','surface'],['connOffline','background'],['connOffline','surfaceContainer'],
  ['onConnOfflineContainer','connOfflineContainer'],
  ['connSyncing','surface'],['connSynced','surface'],
  ['scrimText','scrimBase'],
];

let fails = 0; const rows = [];
for (const [name, T] of [['LIGHT', L], ['DARK', D]]) {
  for (const [fg, bg] of pairs(T)) {
    const r = ratio(T[fg], T[bg]);
    const ok = r >= 4.5;
    if (!ok) fails++;
    rows.push(`${ok?'  ':'XX'} ${name.padEnd(5)} ${fg.padEnd(34)} on ${bg.padEnd(24)} ${T[fg]} / ${T[bg]}  ${r.toFixed(2)}:1`);
  }
}
/* ---------------------------------------------------------------------------
   GLASS. A backdrop-filtered surface is translucent, so its effective
   background depends on whatever scrolls beneath it. Checking it against the
   nominal surface colour would be a lie. Each glass fill is instead
   composited over BLACK and over WHITE — the two extremes any content can
   reach — and every on* role that sits on it is checked against both. Clear
   4.5:1 at both extremes and it clears over any possible content.
--------------------------------------------------------------------------- */
const over = (rgba, base) => {
  const [r, g, b, a] = rgba;
  const h = base.replace('#', '');
  const br = parseInt(h.slice(0,2),16), bg = parseInt(h.slice(2,4),16), bb = parseInt(h.slice(4,6),16);
  const mix = (f, k) => Math.round(f * a + k * (1 - a));
  return '#' + [mix(r,br), mix(g,bg), mix(b,bb)]
    .map(v => v.toString(16).padStart(2, '0')).join('').toUpperCase();
};

const GLASS = {
  LIGHT: {
    'glass-surface':           [251, 250, 246, 0.90],
    'glass-surface-high':      [237, 233, 223, 0.92],
    'glass-on-imagery':        [18, 17, 14, 0.62],
    'glass-on-imagery-strong': [18, 17, 14, 0.74],
  },
  DARK: {
    'glass-surface':           [26, 27, 22, 0.88],
    'glass-surface-high':      [35, 36, 32, 0.92],
    'glass-on-imagery':        [10, 11, 8, 0.62],
    'glass-on-imagery-strong': [10, 11, 8, 0.74],
  },
};
/* the foreground roles that actually sit on each glass fill in the built UI */
const GLASS_FG = {
  'glass-surface':           ['onSurface','onSurfaceVariant','primary','statusOnTrack','statusNeedsAttention','statusActionRequired','connOffline'],
  'glass-surface-high':      ['onSurface','onSurfaceVariant','primary'],
  'glass-on-imagery':        ['scrimText'],
  'glass-on-imagery-strong': ['scrimText'],
};

const glassRows = [];
let glassFails = 0;
for (const [name, T] of [['LIGHT', L], ['DARK', D]]) {
  for (const [gname, rgba] of Object.entries(GLASS[name])) {
    for (const base of ['#000000', '#FFFFFF']) {
      const composite = over(rgba, base);
      for (const fg of GLASS_FG[gname]) {
        const r = ratio(T[fg], composite);
        const ok = r >= 4.5;
        if (!ok) { fails++; glassFails++; }
        glassRows.push(`${ok?'  ':'XX'} ${name.padEnd(5)} ${fg.padEnd(22)} on ${gname.padEnd(24)} over ${base} -> ${composite}  ${r.toFixed(2)}:1`);
      }
    }
  }
}

console.log(rows.join('\n'));
console.log('\n--- GLASS composites (worst case: over pure black and pure white) ---');
console.log(glassRows.join('\n'));
console.log(`\nSOLID pairs: ${rows.length}   GLASS pairs: ${glassRows.length}   glass failures: ${glassFails}`);
console.log(`FAILURES: ${fails} / ${rows.length + glassRows.length}`);
