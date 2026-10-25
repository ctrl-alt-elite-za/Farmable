import { SpeechController } from './speech.mjs';

const document = globalThis.document;
const ids = [
  'open',
  'reset',
  'farm',
  'section',
  'section-info',
  'approved',
  'budget',
  'share',
  'spinach-share',
  'date',
  'compare',
  'consent',
  'mic',
  'stop',
  'speak',
  'voice-state',
  'interim',
  'transcript',
  'send',
  'status',
  'reply',
  'result',
  'save',
  'approve',
  'saved',
];
const ui = Object.fromEntries(ids.map((id) => [id, document.getElementById(id)]));
const storageKey = 'farmable.local-voice-demo.v1';
let token = null;
let board = null;
let preview = null;
let saved = null;
let parentId = null;
let saveAttempt = null;
let approvalKey = null;
let resetKey = null;
let busy = false;
let controls = {
  planting_date: '2026-09-18',
  budget_cents: 300000,
  crops: ['cabbage', 'spinach'],
  block_count: 4,
  min_crop_shares: [],
  max_results: 3,
};

function status(message) {
  ui.status.textContent = message;
}
function remember() {
  try {
    if (token) globalThis.localStorage.setItem(storageKey, token);
    else globalThis.localStorage.removeItem(storageKey);
  } catch {
    status('Browser storage is unavailable; keep this tab open for the demo.');
  }
}
function money(cents) {
  return `R${(cents / 100).toFixed(2)}`;
}
function node(tag, text, className) {
  const element = document.createElement(tag);
  if (text !== undefined) element.textContent = text;
  if (className) element.className = className;
  return element;
}
function buttons() {
  const ready = Boolean(board && ui.section.value);
  const listening = speech.state === 'listening';
  ui.open.disabled = busy;
  ui.reset.disabled = busy || !board || listening;
  ui.section.disabled = busy || !ready || listening;
  for (const id of ['budget', 'share', 'spinach-share', 'date', 'transcript'])
    ui[id].disabled = busy;
  ui.compare.disabled = busy || !ready || listening;
  ui.send.disabled = busy || !ready || listening;
  ui.mic.disabled = busy || !ready || !ui.consent.checked || !speech.supported();
  ui.speak.disabled = busy || !ui.reply.textContent || !ui.consent.checked;
  ui.save.disabled = busy || !preview?.feasible || Boolean(saved) || listening;
  ui.approve.disabled = busy || !saved || saved.status === 'approved' || listening;
}
const speech = new SpeechController({
  onState(state) {
    ui['voice-state'].textContent = state;
    buttons();
  },
  onTranscript(text, final) {
    ui.interim.textContent = final ? '' : text;
    if (final) {
      ui.transcript.value = text;
      status('Review the transcript, then choose Use reviewed message.');
    }
  },
  onError: status,
});

async function api(path, body, key) {
  const abort = new globalThis.AbortController();
  const timer = globalThis.setTimeout(() => abort.abort(), 10000);
  try {
    const response = await globalThis.fetch(path, {
      method: body === undefined ? 'GET' : 'POST',
      headers: {
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}),
        ...(key ? { 'Idempotency-Key': key } : {}),
      },
      ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
      signal: abort.signal,
      cache: 'no-store',
    });
    const result = await response.json();
    if (!response.ok) {
      if (response.status === 401) {
        speech.stop();
        token = null;
        board = null;
        parentId = null;
        remember();
        clearDraft();
        ui.section.replaceChildren();
        ui.farm.textContent = 'Session unavailable. Open a new synthetic farm.';
        ui.approved.textContent = '';
        ui['section-info'].textContent = '';
      }
      throw new Error(result.error?.message || 'Demo request failed.');
    }
    return result;
  } finally {
    globalThis.clearTimeout(timer);
  }
}
async function run(action) {
  if (busy) return;
  busy = true;
  buttons();
  status('');
  try {
    await action();
  } catch (error) {
    status(
      error.name === 'AbortError'
        ? 'Request timed out. Nothing is confirmed; retry the same action.'
        : error.message === 'Failed to fetch'
          ? 'API unavailable. Start the local demo server and retry.'
          : error.message,
    );
  } finally {
    busy = false;
    buttons();
  }
}
function coreControls(request) {
  return Object.fromEntries(
    ['planting_date', 'budget_cents', 'crops', 'block_count', 'min_crop_shares', 'max_results'].map(
      (key) => [key, request[key]],
    ),
  );
}
function showControls() {
  ui.budget.value = (controls.budget_cents / 100).toFixed(2);
  ui.date.value = controls.planting_date;
  ui.share.value = controls.min_crop_shares.find((item) => item.crop === 'cabbage')?.percent || 0;
  ui['spinach-share'].value =
    controls.min_crop_shares.find((item) => item.crop === 'spinach')?.percent || 0;
}
function readControls() {
  if (
    !/^\d+(?:\.\d{1,2})?$/.test(ui.budget.value) ||
    !ui.budget.checkValidity() ||
    !ui.share.checkValidity() ||
    !ui['spinach-share'].checkValidity() ||
    !ui.date.value
  )
    throw new Error('Enter a valid budget, whole-number crop shares and date.');
  const [rand, cents = ''] = ui.budget.value.split('.');
  return {
    ...controls,
    planting_date: ui.date.value,
    budget_cents: Number(rand) * 100 + Number(cents.padEnd(2, '0')),
    min_crop_shares: [
      { crop: 'cabbage', percent: Number(ui.share.value) },
      { crop: 'spinach', percent: Number(ui['spinach-share'].value) },
    ].filter((item) => item.percent > 0),
  };
}
function clearDraft() {
  preview = null;
  saved = null;
  saveAttempt = null;
  approvalKey = null;
  ui.result.replaceChildren(node('p', 'Controls changed. Recalculate before saving.'));
  ui.saved.textContent = '';
  ui.reply.textContent = '';
  buttons();
}
function renderResult() {
  ui.result.replaceChildren();
  if (!preview) return;
  if (!preview.feasible) {
    ui.result.append(node('p', preview.reason.message));
    return;
  }
  const best = preview.plans[0];
  const strip = node('div', undefined, 'allocation');
  for (const crop of best.blocks) strip.append(node('div', crop || 'Unplanted', 'block'));
  ui.result.append(
    strip,
    node(
      'p',
      `Listed costs: ${money(best.total_cost_cents)} · Estimated sales: ${money(best.sales_cents)} · Estimated margin after listed costs: ${money(best.margin_cents)}`,
    ),
  );
  const table = node('table');
  const header = node('tr');
  for (const title of ['Crop', 'Area', 'Harvest window', 'Listed costs'])
    header.append(node('th', title));
  table.append(header);
  for (const allocation of best.allocations) {
    const estimate = allocation.estimate;
    const row = node('tr');
    for (const value of [
      allocation.crop,
      `${estimate.area_m2} m²`,
      `${estimate.harvest_start} – ${estimate.harvest_end}`,
      money(estimate.total_cost_cents),
    ])
      row.append(node('td', value));
    table.append(row);
    ui.result.append(
      node(
        'p',
        `${allocation.crop} costs: ${estimate.costs.map((item) => `${item.category.replaceAll('_', ' ')} ${money(item.cost_cents)}`).join(', ')}`,
      ),
    );
  }
  ui.result.append(table);
  for (const item of preview.comparisons)
    ui.result.append(
      node(
        'p',
        `Whole-section ${item.crop}: sales ${money(item.sales_cents)}, listed costs ${money(item.total_cost_cents)}, margin ${money(item.margin_cents)}.`,
      ),
    );
}
function chooseSection() {
  speech.stop();
  clearDraft();
  const section = board.sections.find((item) => item.id === ui.section.value);
  parentId = section.planned_plan_id;
  ui['section-info'].textContent =
    `${section.area_m2} m² · ${section.area_source.replaceAll('_', ' ')} · Soil unknown · No health assessment yet`;
  const active = board.approved_plans.find((item) => item.id === parentId);
  ui.approved.textContent = active
    ? `Planned planting saved: version ${active.version}. Not physically planted.`
    : 'No approved planting plan for this section.';
  if (active) {
    controls = coreControls(active.result.request);
    preview = active.result;
    // The browser saves only allocation 0; show the approved selection on reopen, even if another client saved a different one.
    preview = {
      ...preview,
      plans: [
        preview.plans[active.selection_index],
        ...preview.plans.filter((_, index) => index !== active.selection_index),
      ],
    };
    saved = active;
    ui.saved.textContent = `Reopened approved plan, version ${active.version}.`;
    renderResult();
  }
  showControls();
  buttons();
}
function showFarm(newBoard) {
  board = newBoard;
  ui.farm.textContent = `${board.name} · ${board.sections.length} sections · ${board.approved_plans.length} active planned plantings`;
  const selected = ui.section.value;
  ui.section.replaceChildren(
    ...board.sections.map((section) => {
      const option = node('option', section.name);
      option.value = section.id;
      return option;
    }),
  );
  ui.section.value = board.sections.some((item) => item.id === selected)
    ? selected
    : board.sections.find((item) => item.current_crop === null)?.id || board.sections[0]?.id || '';
  if (ui.section.value) chooseSection();
  else {
    clearDraft();
    ui['section-info'].textContent = 'No sections; reset this example to restore them.';
  }
  buttons();
}

ui.open.onclick = () =>
  run(async () => {
    speech.stop();
    if (token) {
      showFarm(await api('/demo/farm'));
      return;
    }
    const session = await api('/demo/sessions', {});
    token = session.access_token;
    remember();
    showFarm(session.dashboard);
  });
ui.compare.onclick = () =>
  run(async () => {
    speech.stop();
    clearDraft();
    controls = readControls();
    preview = await api(`/demo/sections/${ui.section.value}/preview`, controls);
    renderResult();
  });
ui.send.onclick = () =>
  run(async () => {
    speech.stop();
    const message = await api(`/demo/sections/${ui.section.value}/voice-preview`, {
      transcript: ui.transcript.value,
      controls: readControls(),
    });
    if (message.understood) {
      clearDraft();
      controls = message.controls;
      preview = message.preview;
      showControls();
      renderResult();
    }
    ui.reply.textContent = message.reply;
    if (ui.consent.checked) speech.speak(message.reply, true);
  });
ui.save.onclick = () =>
  run(async () => {
    speech.stop();
    if (!preview?.feasible) return;
    saveAttempt ||= {
      path: parentId
        ? `/demo/plans/${parentId}/constraints`
        : `/demo/sections/${ui.section.value}/plans`,
      key: globalThis.crypto.randomUUID(),
      body: { ...coreControls(preview.request), selection_index: 0 },
    };
    saved = await api(saveAttempt.path, saveAttempt.body, saveAttempt.key);
    parentId = saved.id;
    preview = saved.result;
    controls = coreControls(saved.result.request);
    showControls();
    renderResult();
    ui.saved.textContent = `Proposal saved, version ${saved.version}. Not approved yet.`;
  });
ui.approve.onclick = () =>
  run(async () => {
    speech.stop();
    if (!saved) return;
    approvalKey ||= globalThis.crypto.randomUUID();
    saved = await api(`/demo/plans/${saved.id}/approve`, {}, approvalKey);
    ui.saved.textContent = 'Approval saved. Refresh to reopen your planned planting.';
    showFarm(await api('/demo/farm'));
  });
ui.reset.onclick = () => {
  if (!globalThis.confirm('Reset this fictional farm and its saved plans?')) return;
  run(async () => {
    speech.stop();
    resetKey ||= globalThis.crypto.randomUUID();
    const reset = await api('/demo/reset', {}, resetKey);
    resetKey = null;
    parentId = null;
    ui.transcript.value = '';
    ui.interim.textContent = '';
    controls = {
      ...controls,
      budget_cents: 300000,
      planting_date: '2026-09-18',
      min_crop_shares: [],
    };
    showFarm(reset);
  });
};
ui.section.onchange = chooseSection;
for (const id of ['budget', 'share', 'spinach-share', 'date'])
  ui[id].oninput = () => {
    speech.stop();
    clearDraft();
  };
ui.mic.onclick = () => {
  ui.interim.textContent = '';
  speech.listen(ui.consent.checked);
};
ui.stop.onclick = () => speech.stop();
ui.speak.onclick = () => speech.speak(ui.reply.textContent, ui.consent.checked);
ui.consent.onchange = () => {
  speech.stop();
  buttons();
};
globalThis.addEventListener('pagehide', () => speech.stop());
document.addEventListener('visibilitychange', () => {
  if (document.hidden) speech.stop();
});
try {
  token = globalThis.localStorage.getItem(storageKey);
} catch {
  /* Typing and tab-local state still work. */
}
buttons();
if (!speech.supported())
  status('Speech recognition is unavailable in this browser. Typing still works.');
if (token) run(async () => showFarm(await api('/demo/farm')));
