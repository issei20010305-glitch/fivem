// Admin item spawner UI. The server checks permission, item and amount.
const resourceName = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'item_spawner';
const $ = (id) => document.getElementById(id);

const FILTERS = [
    { id: 'all', label: 'すべて', test: () => true },
    { id: 'item', label: 'アイテム', test: (item) => item.kind === 'item' },
    { id: 'weapon', label: '武器', test: (item) => item.kind === 'weapon' },
    { id: 'ammo', label: '弾薬', test: (item) => item.kind === 'ammo' },
    { id: 'part', label: '武器パーツ', test: (item) => item.kind === 'part' },
    { id: 'created', label: '作成アイテム', test: (item) => item.created },
];

const state = { items: [], filter: 'all', query: '', selected: null, maxAmount: 1000, busy: false };

async function post(name, data) {
    try {
        const response = await fetch(`https://${resourceName}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {}),
        });
        return await response.json();
    } catch (error) {
        return { ok: false };
    }
}

function esc(value) {
    return String(value == null ? '' : value).replace(/[&<>"']/g, (c) => (
        { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

function formatWeight(grams) {
    return grams >= 1000 ? `${(grams / 1000).toFixed(grams % 1000 === 0 ? 0 : 1)}kg` : `${grams}g`;
}

function message(text, kind) {
    $('message').textContent = text || '';
    $('message').className = `message ${kind || ''}`;
}

function visibleItems() {
    const filter = FILTERS.find((entry) => entry.id === state.filter) || FILTERS[0];
    const words = state.query.toLowerCase().split(/\s+/).filter(Boolean);
    return state.items.filter((item) => filter.test(item) && words.every((word) => item.search.includes(word)));
}

function renderFilters() {
    $('filters').innerHTML = FILTERS.map((filter) => {
        const count = state.items.filter(filter.test).length;
        if (count === 0 && filter.id !== 'all') return '';
        return `<button class="chip${filter.id === state.filter ? ' active' : ''}" data-filter="${filter.id}">${filter.label}<b>${count}</b></button>`;
    }).join('');
}

function renderGrid() {
    const items = visibleItems();
    $('total').textContent = `${items.length} / ${state.items.length} 件`;
    $('grid').innerHTML = items.length === 0
        ? '<div class="empty">該当するアイテムがありません。</div>'
        : items.map((item) => `<button class="card${item.name === state.selected ? ' active' : ''}" data-name="${esc(item.name)}" title="${esc(item.label)}">
            ${item.created ? '<span class="badge">作成</span>' : ''}
            <img src="${esc(item.image)}" alt="" loading="lazy" draggable="false">
            <span class="card-label">${esc(item.label)}</span>
            <span class="card-name">${esc(item.name)}</span>
        </button>`).join('');
}

function renderSelected() {
    const item = state.items.find((entry) => entry.name === state.selected);
    $('give').disabled = !item || state.busy;
    if (!item) {
        $('selected').innerHTML = '<span class="placeholder">アイテムを選択してください</span>';
        return;
    }
    $('selected').innerHTML = `
        <img src="${esc(item.image)}" alt="" draggable="false">
        <div class="sel-label">${esc(item.label)}</div>
        <div class="sel-name">${esc(item.name)}</div>
        <div class="sel-meta">${formatWeight(item.weight)} ・ ${item.stack ? 'スタック可' : 'スタック不可'}</div>
        ${item.description ? `<div class="sel-desc">${esc(item.description)}</div>` : ''}`;
}

function amount() {
    const value = Math.round(Number($('amount').value) || 1);
    return Math.min(state.maxAmount, Math.max(1, value));
}

function select(name) {
    state.selected = name;
    document.querySelectorAll('.card.active').forEach((card) => card.classList.remove('active'));
    const card = document.querySelector(`.card[data-name="${CSS.escape(name)}"]`);
    if (card) card.classList.add('active');
    renderSelected();
}

async function give() {
    if (state.busy || !state.selected) return;
    state.busy = true;
    $('give').disabled = true;
    $('amount').value = amount();

    const answer = await post('give', { name: state.selected, amount: amount(), target: $('target').value || null });

    state.busy = false;
    $('give').disabled = false;
    message(answer.message || (answer.ok ? '付与しました。' : '付与できませんでした。'), answer.ok ? 'success' : 'error');
}

// A picture that fails to load is replaced by a neutral placeholder.
document.addEventListener('error', (event) => {
    const image = event.target;
    if (image.tagName !== 'IMG') return;
    const placeholder = document.createElement('span');
    placeholder.className = 'noimg';
    placeholder.textContent = '?';
    image.replaceWith(placeholder);
}, true);

$('search').addEventListener('input', () => {
    state.query = $('search').value;
    $('search-clear').classList.toggle('hidden', state.query === '');
    renderGrid();
    $('grid').scrollTop = 0;
});

$('search-clear').addEventListener('click', () => {
    $('search').value = '';
    $('search').dispatchEvent(new Event('input'));
    $('search').focus();
});

$('filters').addEventListener('click', (event) => {
    const chip = event.target.closest('[data-filter]');
    if (!chip) return;
    state.filter = chip.dataset.filter;
    renderFilters();
    renderGrid();
    $('grid').scrollTop = 0;
});

$('grid').addEventListener('click', (event) => {
    const card = event.target.closest('.card');
    if (card) select(card.dataset.name);
});

$('grid').addEventListener('dblclick', (event) => {
    const card = event.target.closest('.card');
    if (card) { select(card.dataset.name); give(); }
});

document.querySelectorAll('.step').forEach((button) => {
    button.addEventListener('click', () => {
        $('amount').value = Math.min(state.maxAmount, Math.max(1, amount() + Number(button.dataset.step)));
    });
});

$('quick').addEventListener('click', (event) => {
    const button = event.target.closest('[data-amount]');
    if (button) $('amount').value = button.dataset.amount;
});

$('amount').addEventListener('change', () => { $('amount').value = amount(); });
$('give').addEventListener('click', give);
$('close').addEventListener('click', () => post('close'));

document.addEventListener('keydown', (event) => {
    if ($('app').classList.contains('hidden')) return;
    if (event.key === 'Escape') post('close');
    if (event.key === 'Enter' && document.activeElement !== $('search')) give();
});

window.addEventListener('message', (event) => {
    const { action, data } = event.data || {};
    if (action === 'open') {
        state.items = (Array.isArray(data.items) ? data.items : []).map((item) => Object.assign(item, {
            search: `${item.name} ${item.label}`.toLowerCase(),
        }));
        state.maxAmount = data.maxAmount || 1000;
        if (!state.items.some((item) => item.name === state.selected)) state.selected = null;
        $('amount').max = state.maxAmount;
        $('quick').innerHTML = (Array.isArray(data.quickAmounts) ? data.quickAmounts : [])
            .map((value) => `<button data-amount="${Number(value)}">${Number(value)}</button>`).join('');
        $('target-box').classList.toggle('hidden', !data.allowOthers);
        message('');
        renderFilters();
        renderGrid();
        renderSelected();
        $('app').classList.remove('hidden');
        $('search').focus();
    } else if (action === 'close') {
        $('app').classList.add('hidden');
    }
});
