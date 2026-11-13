// Item Creator UI. The server validates everything again.
const resourceName = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'item_creator';
const $ = (id) => document.getElementById(id);

const EFFECTS = ['heal', 'hunger', 'thirst', 'stress'];
const EFFECT_LABELS = { heal: '体力', hunger: '空腹', thirst: '喉の渇き', stress: 'ストレス' };
const BLANK_IMAGE = 'data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==';

const state = { items: [], editing: null, busy: false, maxImageKb: 512 };

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

function message(text, kind) {
    const element = $('message');
    element.textContent = text || '';
    element.className = `message ${kind || ''}`;
}

function formatWeight(grams) {
    return grams >= 1000 ? `${(grams / 1000).toFixed(grams % 1000 === 0 ? 0 : 1)}kg` : `${grams}g`;
}

// ---------------------------------------------------------------------------
// Form
// ---------------------------------------------------------------------------
function readForm() {
    const data = {
        name: $('name').value.trim(),
        label: $('label').value.trim(),
        description: $('description').value.trim(),
        weight: Math.max(0, Math.round(Number($('weight').value) || 0)),
        stack: $('stack').checked,
        image: $('image').value.trim(),
        exportEnabled: $('exportEnabled').checked,
        exportSide: $('exportSide').value,
        export: $('export').value.trim(),
    };
    EFFECTS.forEach((effect) => {
        data[`${effect}Enabled`] = $(`${effect}Enabled`).checked;
        data[effect] = Math.min(100, Math.max(0, Math.round(Number($(effect).value) || 0)));
    });
    return data;
}

function writeForm(data) {
    $('name').value = data.name || '';
    $('label').value = data.label || '';
    $('description').value = data.description || '';
    $('weight').value = data.weight == null ? 100 : data.weight;
    $('stack').checked = data.stack !== false;
    $('image').value = data.image || '';
    $('exportEnabled').checked = !!data.exportEnabled;
    $('exportSide').value = data.exportSide || 'client';
    $('export').value = data.export || '';
    EFFECTS.forEach((effect) => {
        $(`${effect}Enabled`).checked = !!data[`${effect}Enabled`];
        $(effect).value = data[effect] || 25;
    });
}

/** Converts a stored ox_inventory definition back into form values. */
function definitionToForm(name, definition) {
    const client = definition.client || {};
    const server = definition.server || {};
    const status = client.status || {};
    const exportName = client.export || server.export || '';
    return {
        name,
        label: definition.label,
        description: definition.description || '',
        weight: definition.weight,
        stack: definition.stack !== false,
        image: '',
        exportEnabled: exportName !== '',
        exportSide: server.export ? 'server' : 'client',
        export: exportName,
        healEnabled: definition.heal > 0, heal: definition.heal,
        hungerEnabled: status.hunger > 0, hunger: status.hunger,
        thirstEnabled: status.thirst > 0, thirst: status.thirst,
        stressEnabled: status.stress < 0, stress: -status.stress,
    };
}

function setEditing(name) {
    state.editing = name;
    $('name').readOnly = name !== null;
    $('submit').textContent = name ? '変更を保存' : 'アイテムを作成';
    $('image-required').classList.toggle('hidden', name !== null);
    $('image-hint').textContent = name
        ? '空欄のままにすると現在の画像をそのまま使います。'
        : `PNG / JPEG / WebP / GIF (最大 ${state.maxImageKb}KB)。サーバーに保存されるので、元のURLが消えても表示されます。`;
}

function refresh() {
    const data = readForm();

    $('name').classList.toggle('invalid', data.name !== '' && !/^[a-z0-9_]+$/.test(data.name));
    $('export-fields').classList.toggle('hidden', !data.exportEnabled);
    document.querySelectorAll('.effect').forEach((element) => {
        element.classList.toggle('on', $(`${element.dataset.effect}Enabled`).checked);
    });

    // Preview
    const image = $('preview-image');
    const source = data.image || (state.editing ? `nui://ox_inventory/web/images/${state.editing}.png` : BLANK_IMAGE);
    if (image.dataset.source !== source) {
        image.dataset.source = source;
        image.style.visibility = 'visible';
        image.src = source;
    }
    $('preview-label').textContent = data.label || '表示名';
    $('preview-weight').textContent = formatWeight(data.weight);
    $('preview-name').textContent = data.name || 'spawn_name';

    const tags = [data.stack ? 'スタック可' : 'スタック不可'];
    EFFECTS.forEach((effect) => {
        if (data[`${effect}Enabled`] && data[effect] > 0) tags.push(`${EFFECT_LABELS[effect]} ${effect === 'stress' ? '-' : '+'}${data[effect]}%`);
    });
    if (data.exportEnabled && data.export) tags.push(`export: ${data.export}`);
    $('preview-effects').innerHTML = tags.map((tag) => `<span class="tag">${esc(tag)}</span>`).join('');
}

function renderList() {
    $('count').textContent = state.items.length;
    $('list').innerHTML = state.items.length === 0
        ? '<div class="list-empty">まだアイテムがありません。</div>'
        : state.items.map((item) => `<button type="button" class="item${item.name === state.editing ? ' active' : ''}" data-name="${esc(item.name)}">
            <span class="item-text"><span class="item-label">${esc(item.definition.label)}</span><span class="item-name">${esc(item.name)}</span></span>
        </button>`).join('');
}

function resetForm() {
    setEditing(null);
    writeForm({});
    renderList();
    refresh();
}

/** Returns an error text when something obvious is missing. */
function check(data) {
    if (!/^[a-z0-9_]+$/.test(data.name)) return 'スポーン名は半角の小文字英数字と _ で入力してください。';
    if (!data.label) return '表示名を入力してください。';
    if (!state.editing && !data.image) return '画像URLを入力してください。';
    if (data.image && !/^https?:\/\//i.test(data.image)) return '画像URLは http:// または https:// で始めてください。';
    if (data.exportEnabled && !/^[\w-]+\.\w+$/.test(data.export)) return 'エクスポートは「リソース名.関数名」の形式で入力してください。';
    return null;
}

async function submit() {
    if (state.busy) return;
    const data = readForm();
    const problem = check(data);
    if (problem) return message(problem, 'error');

    state.busy = true;
    $('submit').disabled = true;
    message('画像を保存してアイテムを登録しています…');

    const answer = await post('create', data);

    state.busy = false;
    $('submit').disabled = false;

    if (!answer.ok) return message(typeof answer.result === 'string' ? answer.result : '作成できませんでした。', 'error');

    state.items = Array.isArray(answer.result.items) ? answer.result.items : state.items;
    resetForm();
    message(answer.result.edited
        ? `「${answer.result.name}」を更新しました。`
        : `「${answer.result.name}」を作成しました。すぐに /giveitem やスクリプトで使えます。`, 'success');
}

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------
$('form').addEventListener('input', refresh);
$('form').addEventListener('submit', (event) => event.preventDefault());
$('submit').addEventListener('click', submit);
$('reset').addEventListener('click', () => { resetForm(); message(''); });
$('close').addEventListener('click', () => post('close'));
$('preview-image').addEventListener('error', (event) => { event.target.style.visibility = 'hidden'; });

$('name').addEventListener('input', () => {
    const input = $('name');
    const cleaned = input.value.toLowerCase().replace(/[\s-]/g, '_');
    if (cleaned !== input.value) input.value = cleaned;
});

$('list').addEventListener('click', (event) => {
    const button = event.target.closest('.item');
    if (!button) return;
    const item = state.items.find((entry) => entry.name === button.dataset.name);
    if (!item) return;
    setEditing(item.name);
    writeForm(definitionToForm(item.name, item.definition));
    renderList();
    refresh();
    message(`「${item.name}」を編集中です。`);
});

document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && !$('app').classList.contains('hidden')) post('close');
});

window.addEventListener('message', (event) => {
    const { action, data } = event.data || {};
    if (action === 'open') {
        state.items = Array.isArray(data.items) ? data.items : [];
        state.maxImageKb = data.maxImageKb || 512;
        if (!state.editing) setEditing(null);
        renderList();
        refresh();
        message('');
        $('app').classList.remove('hidden');
    } else if (action === 'close') {
        $('app').classList.add('hidden');
    }
});

setEditing(null);
refresh();
