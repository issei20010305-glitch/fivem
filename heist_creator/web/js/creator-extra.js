// Creator extensions: genres / tags, props (picker with live preview, ghost
// placement) and placing stages / loot points on props or world objects.
Creator.propPicker = null; // { mode: 'add'|'change', index, tab, query, selected, valid, size }
Creator.allProps = null;   // every object name of the game, loaded on first use
Creator.taxonomy = null;   // working copy while the ジャンル・タグ page is open
Creator.showProps = true;  // show the heist's props in the game world while editing
Creator.shownSignature = '';

// ---------------------------------------------------------------------------
// Genres and tags
// ---------------------------------------------------------------------------
function tagToggles() {
    const tags = arr(Creator.meta.tags);
    if (tags.length === 0) return '<span class="coords-value dim">タグがまだありません</span>';
    const selected = arr(Creator.draft.tags);
    return `<div class="tag-row">${tags.map((tag) =>
        `<button class="tag-toggle${selected.includes(tag) ? ' on' : ''}" data-act="tag-toggle" data-arg="${esc(tag)}">${esc(tag)}</button>`).join('')}</div>`;
}

function renderTaxonomy() {
    const t = Creator.taxonomy;
    const genres = t.genres.map((genre, i) => `<div class="tax-row">
        <span class="list-index">${i + 1}</span>
        <span class="tax-name">${esc(genre)}</span>
        <button class="btn small ghost" data-act="genre-up" data-arg="${i}"${i === 0 ? ' disabled' : ''}>↑</button>
        <button class="btn small ghost" data-act="genre-down" data-arg="${i}"${i === t.genres.length - 1 ? ' disabled' : ''}>↓</button>
        <button class="btn small danger" data-act="genre-remove" data-arg="${i}">削除</button>
    </div>`).join('');
    const tags = t.tags.map((tag, i) =>
        `<span class="door-chip">${esc(tag)}<button data-act="tag-remove" data-arg="${i}" title="削除">×</button></span>`).join('');

    return `<div class="hint-box">ジャンルは大きな分類 (例: 小型犯罪、中型犯罪)、タグは細かい分類 (例: コンビニ、フリーカ) です。Heist HUD でプレイヤーが並べ替え・絞り込みに使えます。ジャンルはここで並べた順に表示されます。変更後は「ジャンル・タグを保存」を押してください。</div>
        <div class="tax-grid">
            <div>
                <div class="sub-title flat">ジャンル</div>
                ${genres || emptyState('ジャンルがありません。')}
                <div class="tax-add"><input type="text" id="genre-input" maxlength="24" placeholder="新しいジャンル名"><button class="btn primary" data-act="genre-add">追加</button></div>
            </div>
            <div>
                <div class="sub-title flat">タグ</div>
                <div class="tag-row">${tags || '<span class="coords-value dim">タグがありません。</span>'}</div>
                <div class="tax-add"><input type="text" id="tag-input" maxlength="24" placeholder="新しいタグ名"><button class="btn primary" data-act="tag-add">追加</button></div>
            </div>
        </div>`;
}

function addTaxonomy(kind, inputId) {
    const input = $(`#${inputId}`);
    const name = input.value.trim();
    const list = Creator.taxonomy[kind];
    const limit = (Creator.meta.limits || {})[kind];
    if (!name || list.includes(name)) return;
    if (limit && list.length >= limit) {
        toast('creator-toast', `これ以上追加できません (最大 ${limit})`, 'error');
        return;
    }
    list.push(name);
    renderCreator();
    $(`#${inputId}`).focus();
}

Object.assign(CREATOR_ACTIONS, {
    'view-taxonomy'() {
        Creator.view = 'taxonomy';
        Creator.taxonomy = { genres: arr(Creator.meta.genres).slice(), tags: arr(Creator.meta.tags).slice() };
        renderCreator();
    },
    'tag-toggle'(arg) {
        const tags = arr(Creator.draft.tags);
        Creator.draft.tags = tags.includes(arg) ? tags.filter((tag) => tag !== arg) : tags.concat(arg);
        renderCreator();
    },
    'genre-add': () => addTaxonomy('genres', 'genre-input'),
    'tag-add': () => addTaxonomy('tags', 'tag-input'),
    'genre-remove'(arg) {
        Creator.taxonomy.genres.splice(Number(arg), 1);
        renderCreator();
    },
    'tag-remove'(arg) {
        Creator.taxonomy.tags.splice(Number(arg), 1);
        renderCreator();
    },
    'genre-up'(arg) {
        const list = Creator.taxonomy.genres;
        const i = Number(arg);
        if (i > 0) [list[i - 1], list[i]] = [list[i], list[i - 1]];
        renderCreator();
    },
    'genre-down'(arg) {
        const list = Creator.taxonomy.genres;
        const i = Number(arg);
        if (i < list.length - 1) [list[i + 1], list[i]] = [list[i], list[i + 1]];
        renderCreator();
    },
    async 'taxonomy-save'() {
        const answer = await post('creator:saveTaxonomy', Creator.taxonomy);
        if (answer.ok) {
            Creator.meta.genres = arr(answer.result.genres);
            Creator.meta.tags = arr(answer.result.tags);
            Creator.taxonomy = { genres: Creator.meta.genres.slice(), tags: Creator.meta.tags.slice() };
        }
        toast('creator-toast', answer.ok ? 'ジャンル・タグを保存しました' : (answer.result || '保存に失敗しました'), answer.ok ? 'success' : 'error');
        renderCreator();
    },
});

$('#creator-content').addEventListener('keydown', (event) => {
    if (event.key !== 'Enter') return;
    if (event.target.id === 'genre-input') addTaxonomy('genres', 'genre-input');
    if (event.target.id === 'tag-input') addTaxonomy('tags', 'tag-input');
});

// ---------------------------------------------------------------------------
// Placement of a stage / loot point: free coordinates, a world object, or
// one of the heist's props
// ---------------------------------------------------------------------------
function propTitle(prop, index) {
    return `プロップ ${index + 1}: ${prop.label || prop.model}`;
}

function placementFields(kind, index) {
    const entry = Creator.draft[kind][index];
    const props = arr(Creator.draft.props);
    const linked = props[num(entry.prop, 0) - 1];
    const options = [{ id: 0, label: '座標・オブジェクトを指定する' }]
        .concat(props.map((prop, i) => ({ id: i + 1, label: propTitle(prop, i) })));

    const select = `<select data-path="${kind}.${index}.prop" data-type="number" data-rerender>${options.map((option) =>
        `<option value="${option.id}"${option.id === num(entry.prop, 0) ? ' selected' : ''}>${esc(option.label)}</option>`).join('')}</select>`;
    const position = linked
        ? `<div class="coords"><span class="coords-value">${linked.coords
            ? `プロップの位置を使用 (${num(linked.coords.x).toFixed(2)}, ${num(linked.coords.y).toFixed(2)}, ${num(linked.coords.z).toFixed(2)})`
            : 'プロップの位置を使用'}</span></div>`
        : coordsControl(`${kind}.${index}.coords`, false, false, true);

    return `${field('配置方法', select, props.length === 0 ? '「プロップ」タブで追加したプロップに設置することもできます' : 'プロップを選ぶと、そのプロップの位置が自動的に使われます', true)}
        ${field('位置', position, linked ? '' : '「オブジェクトを選択」でゲーム内に既にある金庫やATMなどを直接指定できます', true)}`;
}

// ---------------------------------------------------------------------------
// Props tab
// ---------------------------------------------------------------------------
function propUsage(index) {
    const d = Creator.draft;
    const uses = [];
    d.stages.forEach((stage, i) => { if (num(stage.prop) === index + 1) uses.push(`ステージ ${i + 1}`); });
    d.loots.forEach((loot, i) => { if (num(loot.prop) === index + 1) uses.push(`物色ポイント ${i + 1}`); });
    return uses;
}

TAB_RENDERERS.props = function () {
    const cards = Creator.draft.props.map((prop, i) => {
        const c = prop.coords;
        const uses = propUsage(i);
        return `<div class="list-card">
            <div class="list-card-head">
                <span class="list-index">${i + 1}</span>
                <span class="list-title">${esc(prop.label || prop.model)}</span>
                <span class="list-actions">
                    <button class="btn small" data-act="prop-duplicate" data-arg="${i}" title="同じモデルをもう1つ配置します">複製</button>
                    <button class="btn small danger" data-act="prop-remove" data-arg="${i}">削除</button>
                </span>
            </div>
            <div class="form-grid">
                ${field('モデル', `<button class="picker-button" data-act="prop-model" data-arg="${i}"><span>${esc(prop.model)}</span><small>変更 ▸</small></button>`)}
                ${field('メモ (任意)', textInput(`props.${i}.label`, { max: 40, placeholder: '例: 金庫室の金庫' }))}
                ${field('位置と向き', `<div class="coords">
                    <span class="coords-value${c ? '' : ' unset'}">${c ? `${num(c.x).toFixed(2)}, ${num(c.y).toFixed(2)}, ${num(c.z).toFixed(2)} / ${num(c.w).toFixed(0)}°` : '未設定'}</span>
                    <button class="btn small" data-act="prop-place" data-arg="${i}" title="半透明のプレビューを動かして配置し直します">配置し直す</button>
                    <button class="btn small ghost" data-act="prop-tp" data-arg="${i}"${c ? '' : ' disabled'}>TP</button>
                </div>`, uses.length > 0 ? `使用中: ${uses.join('、')}` : 'ステージや物色ポイントの「配置方法」でこのプロップを選べます', true)}
            </div>
        </div>`;
    }).join('');

    return `<div class="row-actions top"><label class="check"><input type="checkbox" id="show-props"${Creator.showProps ? ' checked' : ''}><span>配置済みのプロップをゲーム内に表示する (番号付き・重ならないよう確認できます)</span></label></div>
        <div class="hint-box">プロップはヘイスト中だけ出現するオブジェクトです。クルーが近づくと出現し、ヘイストが完了・失敗・中止されると (エリア離脱や切断を含む) 自動的に消えます。追加するとプレビューを見ながらモデルを選び、半透明の見本を動かして配置できます。</div>
        ${cards || emptyState('プロップがありません。金庫・現金・ノートパソコンなどをヘイスト用に配置できます。')}
        <div class="row-actions"><button class="btn primary" data-act="prop-add">＋ プロップを追加</button></div>`;
};

/** Props of the draft that have a position, as the game needs them. */
function placedProps() {
    return arr(Creator.draft && Creator.draft.props).map((prop) => ({ model: prop.model, coords: prop.coords || null }));
}

/** Shows the draft's props in the game world (only sends when something changed). */
function syncWorldProps() {
    const payload = { show: Creator.showProps && Creator.view === 'heist', props: placedProps() };
    const signature = JSON.stringify(payload);
    if (signature === Creator.shownSignature) return;
    Creator.shownSignature = signature;
    post('creator:showProps', payload);
}

/** Keeps stage / loot links correct when a prop is removed. */
function unlinkProp(index) {
    const d = Creator.draft;
    d.stages.concat(d.loots).forEach((entry) => {
        const linked = num(entry.prop, 0);
        if (linked === index + 1) entry.prop = 0;
        else if (linked > index + 1) entry.prop = linked - 1;
    });
}

/**
 * @param moving index of the prop that is being re-placed (it is hidden meanwhile), or -1
 */
async function placeNewProp(model, label, previous, moving) {
    const answer = await post('creator:placeProp', {
        model,
        coords: previous || null,
        props: Creator.showProps ? placedProps() : [],
        moving: moving >= 0 ? moving + 1 : null,
    });
    Creator.shownSignature = ''; // the game changed what it shows; send the list again

    if (!answer.ok || !answer.coords) return null;
    return { model, label: label || '', coords: answer.coords };
}

// ---------------------------------------------------------------------------
// Prop picker: search + list on the left, the real model turning in the
// game world as the preview
// ---------------------------------------------------------------------------
const PROP_LIST_LIMIT = 300;

function favouriteLabel(model) {
    const favourite = arr(Creator.meta.propFavourites).find((entry) => entry.model === model);
    return favourite ? favourite.label : '';
}

function propResults() {
    const picker = Creator.propPicker;
    const words = picker.query.toLowerCase().split(/\s+/).filter(Boolean);
    const favourites = arr(Creator.meta.propFavourites);
    const matches = (text) => words.every((word) => text.includes(word));

    if (words.length === 0) {
        if (picker.tab === 'fav') return { rows: favourites.map((entry) => ({ model: entry.model, label: entry.label })), total: favourites.length };
        const all = Creator.allProps || [];
        return { rows: all.slice(0, PROP_LIST_LIMIT).map((model) => ({ model, label: '' })), total: all.length };
    }

    const rows = favourites.filter((entry) => matches(`${entry.model} ${entry.label.toLowerCase()}`))
        .map((entry) => ({ model: entry.model, label: entry.label }));
    const known = new Set(rows.map((row) => row.model));
    const all = (Creator.allProps || []).filter((model) => !known.has(model) && matches(model));
    return { rows: rows.concat(all.slice(0, PROP_LIST_LIMIT - rows.length).map((model) => ({ model, label: '' }))), total: rows.length + all.length };
}

function updatePropList() {
    const picker = Creator.propPicker;
    const { rows, total } = propResults();
    const loading = !Creator.allProps && (picker.tab === 'all' || picker.query.trim() !== '');

    $('#prop-tabs').innerHTML = `
        <button class="tab${picker.tab === 'fav' ? ' active' : ''}" data-act="prop-tab" data-arg="fav">よく使う<span class="tab-count">${arr(Creator.meta.propFavourites).length}</span></button>
        <button class="tab${picker.tab === 'all' ? ' active' : ''}" data-act="prop-tab" data-arg="all">すべて<span class="tab-count">${Creator.allProps ? Creator.allProps.length.toLocaleString() : '…'}</span></button>`;

    $('#prop-list').innerHTML = (rows.length === 0
        ? `<div class="prop-empty">${loading ? '読み込み中…' : '該当するプロップがありません。'}</div>`
        : rows.map((row) => `<button class="prop-row${row.model === picker.selected ? ' active' : ''}" data-act="prop-select" data-arg="${esc(row.model)}">
            ${row.label ? `<span class="prop-label">${esc(row.label)}</span>` : ''}<span class="prop-model">${esc(row.model)}</span>
        </button>`).join(''))
        + (total > rows.length ? `<div class="prop-empty">${total.toLocaleString()} 件中 ${rows.length} 件を表示。検索で絞り込んでください。</div>` : '');
}

function updatePropFoot() {
    const picker = Creator.propPicker;
    $('#prop-foot').innerHTML = `
        <div class="prop-selected">${picker.selected
            ? `${esc(picker.selected)}${picker.valid === false ? '<b class="bad">このモデルは読み込めません</b>' : picker.size ? `<small>大きさ 約 ${picker.size}m</small>` : ''}`
            : '<small>リストから選ぶと、ゲーム画面にプレビューが表示されます (↑↓キーでも移動できます)</small>'}</div>
        <div class="prop-buttons">
            <button class="btn ghost" data-act="prop-cancel">キャンセル</button>
            <button class="btn primary" data-act="prop-confirm"${picker.selected && picker.valid !== false ? '' : ' disabled'}>${picker.mode === 'change' ? 'このモデルに変更' : 'このプロップを配置する'}</button>
        </div>`;
}

function renderPropPicker() {
    const root = $('#creator-props');
    const picker = Creator.propPicker;
    $('#creator').classList.toggle('previewing', picker !== null);

    if (!picker) {
        root.classList.add('hidden');
        root.innerHTML = '';
        return;
    }
    if (root.innerHTML === '') {
        root.innerHTML = `<div class="prop-panel">
            <div class="picker-head">
                <div class="main-title">プロップを選択</div>
                <button class="btn icon" data-act="prop-cancel">✕</button>
            </div>
            <div class="prop-search"><input type="text" id="prop-search" placeholder="モデル名・名前で検索 (例: safe, cash, 金庫)" spellcheck="false" autocomplete="off"></div>
            <nav class="tabs" id="prop-tabs"></nav>
            <div class="prop-list" id="prop-list"></div>
            <div class="prop-foot" id="prop-foot"></div>
        </div>`;
        root.classList.remove('hidden');
        $('#prop-search').value = picker.query;
        $('#prop-search').focus();
    }
    updatePropList();
    updatePropFoot();
}

async function loadAllProps() {
    if (Creator.allProps) return;
    try {
        const text = await (await fetch('props.txt')).text();
        Creator.allProps = text.split('\n').map((line) => line.trim()).filter(Boolean);
    } catch (error) {
        Creator.allProps = [];
    }
    if (Creator.propPicker) updatePropList();
}

function openPropPicker(mode, index) {
    const current = mode === 'change' ? Creator.draft.props[index].model : null;
    Creator.propPicker = { mode, index, tab: 'fav', query: '', selected: null, valid: null, size: null };
    renderPropPicker();
    loadAllProps();
    if (current) selectProp(current);
}

async function selectProp(model) {
    const picker = Creator.propPicker;
    if (!picker) return;
    picker.selected = model;
    picker.valid = null;
    picker.size = null;
    document.querySelectorAll('.prop-row').forEach((row) => row.classList.toggle('active', row.dataset.arg === model));
    updatePropFoot();

    const answer = await post('creator:propPreview', { model });
    if (Creator.propPicker !== picker || picker.selected !== model) return; // another one was chosen meanwhile
    picker.valid = answer.ok === true;
    picker.size = answer.size || null;
    updatePropFoot();
}

function closePropPicker() {
    Creator.propPicker = null;
    post('creator:propPreviewStop');
    renderPropPicker();
}

Object.assign(CREATOR_ACTIONS, {
    'prop-add'() {
        const limit = (Creator.meta.limits || {}).props;
        if (limit && Creator.draft.props.length >= limit) {
            toast('creator-toast', `これ以上追加できません (最大 ${limit})`, 'error');
            return;
        }
        openPropPicker('add', -1);
    },
    'prop-model': (arg) => openPropPicker('change', Number(arg)),
    'prop-tab'(arg) {
        Creator.propPicker.tab = arg;
        updatePropList();
    },
    'prop-select': (arg) => selectProp(arg),
    'prop-cancel': closePropPicker,
    async 'prop-confirm'() {
        const picker = Creator.propPicker;
        if (!picker || !picker.selected || picker.valid === false) return;
        const model = picker.selected;
        closePropPicker();

        if (picker.mode === 'change') {
            const prop = Creator.draft.props[picker.index];
            prop.model = model;
            if (!prop.label) prop.label = favouriteLabel(model);
        } else {
            const prop = await placeNewProp(model, favouriteLabel(model));
            if (prop) Creator.draft.props.push(prop);
        }
        renderCreator();
    },
    async 'prop-place'(arg) {
        const prop = Creator.draft.props[Number(arg)];
        const placed = await placeNewProp(prop.model, prop.label, prop.coords, Number(arg));
        if (placed) prop.coords = placed.coords;
        renderCreator();
    },
    async 'prop-duplicate'(arg) {
        const limit = (Creator.meta.limits || {}).props;
        if (limit && Creator.draft.props.length >= limit) {
            toast('creator-toast', `これ以上追加できません (最大 ${limit})`, 'error');
            return;
        }
        const prop = Creator.draft.props[Number(arg)];
        const placed = await placeNewProp(prop.model, prop.label, prop.coords);
        if (placed) Creator.draft.props.push(placed);
        renderCreator();
    },
    'prop-tp'(arg) {
        const c = Creator.draft.props[Number(arg)].coords;
        if (c) post('creator:teleport', { x: c.x, y: c.y, z: c.z + 1.0, w: c.w });
    },
    'prop-remove'(arg) {
        const index = Number(arg);
        Creator.draft.props.splice(index, 1);
        unlinkProp(index);
        renderCreator();
    },
    async 'pos-object'(arg) {
        const answer = await post('creator:pickObject');
        if (answer.ok && answer.coords) {
            setPath(Creator.draft, arg, answer.coords);
            renderCreator();
        }
    },
});

$('#creator-content').addEventListener('change', (event) => {
    if (event.target.id !== 'show-props') return;
    Creator.showProps = event.target.checked;
    syncWorldProps();
});

$('#creator-props').addEventListener('input', (event) => {
    if (event.target.id !== 'prop-search' || !Creator.propPicker) return;
    Creator.propPicker.query = event.target.value;
    updatePropList();
    $('#prop-list').scrollTop = 0;
});

// ↑ / ↓ walk through the list (each step shows the preview), Enter confirms.
$('#creator-props').addEventListener('keydown', (event) => {
    if (!Creator.propPicker || !['ArrowDown', 'ArrowUp', 'Enter'].includes(event.key)) return;
    event.preventDefault();
    if (event.key === 'Enter') {
        CREATOR_ACTIONS['prop-confirm']();
        return;
    }
    const rows = Array.from(document.querySelectorAll('.prop-row'));
    if (rows.length === 0) return;
    const current = rows.findIndex((row) => row.classList.contains('active'));
    const next = Math.min(rows.length - 1, Math.max(0, current + (event.key === 'ArrowDown' ? 1 : -1)));
    rows[next].scrollIntoView({ block: 'nearest' });
    selectProp(rows[next].dataset.arg);
});
