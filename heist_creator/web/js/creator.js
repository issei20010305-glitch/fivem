// Heist Creator (admin UI). All input is validated again by the server on save.
const Creator = {
    heists: [],
    npcs: [],
    doors: [], // ox_doorlock doors, nearest first
    meta: {},
    draft: null,
    view: 'heist', // 'heist' | 'npcs'
    tab: 'basic',
    confirmDelete: false,
    picker: null, // { stage, group } while the minigame picker is open
};

const CREATOR_TABS = [
    { id: 'basic', label: '基本情報' },
    { id: 'conditions', label: '参加条件・クールダウン' },
    { id: 'locations', label: '開始地点' },
    { id: 'stages', label: 'ステージ' },
    { id: 'guards', label: 'ガード' },
    { id: 'loots', label: '物色ポイント' },
];

const INTERACTIONS = [
    { id: 'key', label: 'Eキーを押す' },
    { id: 'target', label: 'ox_target (ターゲット)' },
];

function newDraft() {
    return {
        id: null, enabled: true, name: '', description: '', image: '', difficulty: 1,
        requiredXp: 0, xpReward: 100, minPolice: 0, minPlayers: 1,
        maxPlayers: Creator.meta.maxParty || 4, globalCooldown: 60, playerCooldown: 120,
        timeLimit: 30, startRadius: 15, start: null,
        stages: [], guards: [], loots: [],
    };
}

function normalizeHeist(heist) {
    const copy = JSON.parse(JSON.stringify(heist));
    ['stages', 'guards', 'loots'].forEach((key) => { copy[key] = arr(copy[key]); });
    copy.loots.forEach((loot) => { loot.rewards = arr(loot.rewards); });
    delete copy.rewards;
    delete copy.extraction;
    copy.stages.forEach((stage) => { stage.doors = arr(stage.doors); });
    return Object.assign(newDraft(), copy);
}

function getPath(object, path) {
    return path.split('.').reduce((value, key) => (value == null ? value : value[key]), object);
}

function setPath(object, path, value) {
    const keys = path.split('.');
    const last = keys.pop();
    const target = keys.reduce((current, key) => current[key], object);
    target[last] = value;
}

// ---------------------------------------------------------------------------
// Field builders
// ---------------------------------------------------------------------------
function field(label, control, hint, wide) {
    return `<label class="field${wide ? ' wide' : ''}"><span class="field-label">${esc(label)}</span>${control}${hint ? `<span class="field-hint">${esc(hint)}</span>` : ''}</label>`;
}

function textInput(path, options) {
    const o = options || {};
    return `<input type="text" data-path="${path}" value="${esc(getPath(Creator.draft, path) || '')}" maxlength="${o.max || 80}" placeholder="${esc(o.placeholder || '')}"${o.list ? ` list="${o.list}"` : ''} autocomplete="off" spellcheck="false">`;
}

function numberInput(path, options) {
    const o = options || {};
    const value = getPath(Creator.draft, path);
    return `<input type="number" data-path="${path}" data-type="number" value="${esc(value == null ? '' : value)}" min="${o.min == null ? 0 : o.min}"${o.max != null ? ` max="${o.max}"` : ''} step="${o.step || 1}"${o.disabled ? ' disabled' : ''}>`;
}

function selectInput(path, options) {
    const current = getPath(Creator.draft, path);
    const html = options.map((option) =>
        `<option value="${esc(option.id)}"${String(option.id) === String(current) ? ' selected' : ''}>${esc(option.label)}</option>`).join('');
    return `<select data-path="${path}">${html}</select>`;
}

function checkbox(path, label, rerender) {
    return `<label class="check"><input type="checkbox" data-path="${path}" data-type="bool"${rerender ? ' data-rerender' : ''}${getPath(Creator.draft, path) ? ' checked' : ''}><span>${esc(label)}</span></label>`;
}

function coordsControl(path, withHeading) {
    const c = getPath(Creator.draft, path);
    const text = c
        ? `${num(c.x).toFixed(2)}, ${num(c.y).toFixed(2)}, ${num(c.z).toFixed(2)}${withHeading ? ` / ${num(c.w).toFixed(0)}°` : ''}`
        : '未設定';
    return `<div class="coords">
        <span class="coords-value${c ? '' : ' unset'}">${text}</span>
        <button class="btn small" data-act="pos-current" data-arg="${path}" title="今立っている場所を設定">現在位置</button>
        <button class="btn small" data-act="pos-pick" data-arg="${path}" title="カメラで狙った場所を設定">照準で指定</button>
        <button class="btn small ghost" data-act="pos-tp" data-arg="${path}"${c ? '' : ' disabled'} title="この場所へテレポート">TP</button>
    </div>`;
}

/** Doors (ox_doorlock) unlocked when a stage is completed. */
function doorsControl(stageIndex) {
    if (!Creator.meta.doorsAvailable) {
        return '<div class="doors"><span class="coords-value unset">ox_doorlock が起動していないため使用できません</span></div>';
    }
    const selected = arr(Creator.draft.stages[stageIndex].doors);
    const chips = selected.map((id) => {
        const door = Creator.doors.find((entry) => entry.id === id);
        return `<span class="door-chip">${esc(door ? door.name : '不明なドア')} <small>#${id}</small><button data-act="door-remove" data-arg="${stageIndex}.${id}" title="外す">×</button></span>`;
    }).join('');
    const options = Creator.doors.filter((door) => !selected.includes(door.id)).slice(0, 60).map((door) =>
        `<option value="${door.id}">${esc(door.name)} (#${door.id}) ・ ${door.distance}m</option>`).join('');
    return `<div class="doors">
        ${chips}
        <select data-door-add="${stageIndex}"><option value="">＋ ドアを追加 (近い順)</option>${options}</select>
        <button class="btn small" data-act="doors-refresh" title="現在位置から近い順に並べ直す">一覧を更新</button>
    </div>`;
}

function listCard(kind, index, title, body, extraButtons) {
    const total = Creator.draft[kind].length;
    return `<div class="list-card">
        <div class="list-card-head">
            <span class="list-index">${index + 1}</span>
            <span class="list-title">${esc(title)}</span>
            <span class="list-actions">
                ${extraButtons || ''}
                <button class="btn small ghost" data-act="move-up" data-arg="${kind}.${index}"${index === 0 ? ' disabled' : ''}>↑</button>
                <button class="btn small ghost" data-act="move-down" data-arg="${kind}.${index}"${index === total - 1 ? ' disabled' : ''}>↓</button>
                <button class="btn small danger" data-act="remove" data-arg="${kind}.${index}">削除</button>
            </span>
        </div>
        <div class="form-grid">${body}</div>
    </div>`;
}

function emptyState(text) {
    return `<div class="empty">${esc(text)}</div>`;
}

// ---------------------------------------------------------------------------
// Tabs
// ---------------------------------------------------------------------------
const TAB_RENDERERS = {
    basic() {
        const d = Creator.draft;
        const difficulties = [1, 2, 3, 4, 5].map((value) => ({ id: value, label: `${'★'.repeat(value)}${'☆'.repeat(5 - value)}` }));
        return `<div class="form-grid">
            ${field('ヘイスト名', textInput('name', { max: 48, placeholder: '例: フリーサ銀行強盗' }))}
            ${field('難易度 (表示用)', `<select data-path="difficulty" data-type="number">${difficulties.map((o) => `<option value="${o.id}"${o.id === num(d.difficulty, 1) ? ' selected' : ''}>${o.label}</option>`).join('')}</select>`)}
            ${field('説明', `<textarea data-path="description" maxlength="400" rows="4" placeholder="Heist HUDに表示される説明文">${esc(d.description)}</textarea>`, '', true)}
            ${field('画像URL', textInput('image', { max: 300, placeholder: 'https://...' }), 'Heist HUDのカードに表示されます (空欄可)', true)}
            ${field('必要ヘイストXP', numberInput('requiredXp'), 'このXP以上のプレイヤーのみ受注できます')}
            ${field('成功時の獲得XP', numberInput('xpReward'), 'パーティーボーナスはこの値に加算されます')}
            <div class="field wide">${checkbox('enabled', 'このヘイストを有効にする (Heist HUDに表示)')}</div>
        </div>
        ${d.image ? `<div class="image-preview"><img src="${esc(d.image)}" alt="" onerror="this.parentElement.style.display='none'"></div>` : ''}`;
    },

    conditions() {
        const maxParty = Creator.meta.maxParty || 4;
        return `<div class="form-grid">
            ${field('必要な警察官の人数', numberInput('minPolice'), 'オンラインの警察官がこの人数以上のときのみ開始できます')}
            ${field('制限時間 (分)', numberInput('timeLimit'), '開始地点に到着してからの制限時間。0 = 無制限')}
            ${field('最少参加人数', numberInput('minPlayers', { min: 1, max: maxParty }))}
            ${field('最大参加人数', numberInput('maxPlayers', { min: 1, max: maxParty }))}
            ${field('サーバー全体クールダウン (分)', numberInput('globalCooldown'), '終了後、誰もこのヘイストを開始できなくなる時間')}
            ${field('個人クールダウン (分)', numberInput('playerCooldown'), '参加したプレイヤーが再挑戦できるまでの時間')}
        </div>
        ${Creator.draft.id ? `<div class="row-actions"><button class="btn" data-act="reset-cooldown">このヘイストのクールダウンをリセット</button></div>` : ''}`;
    },

    locations() {
        return `<div class="form-grid">
            ${field('開始地点', coordsControl('start'), 'クルーが最初に向かう場所。到着するとステージが開始されます', true)}
            ${field('開始地点の半径 (m)', numberInput('startRadius', { min: 3, max: 100 }))}
        </div>
        <div class="hint-box">ヘイストの完了: すべて終わったら、ヘイストを受注した受付NPCに話しかけると完了になり、XPが付与されます (脱出地点の設定は不要です)。</div>
        <div class="hint-box">位置の設定方法: 「現在位置」は今立っている場所、「照準で指定」は画面を閉じてカメラで狙った場所を E キーで決定します。</div>`;
    },

    stages() {
        const d = Creator.draft;
        const cards = d.stages.map((stage, i) => listCard('stages', i, stage.label || `ステージ ${i + 1}`, `
            ${field('目標テキスト', textInput(`stages.${i}.label`, { placeholder: '例: ハッキングデバイスでセキュリティを解除せよ' }), '空欄の場合は標準の文言が表示されます', true)}
            ${field('位置', coordsControl(`stages.${i}.coords`), '', true)}
            ${field('インタラクション方式', selectInput(`stages.${i}.interaction`, INTERACTIONS))}
            ${field('ミニゲーム', minigameButton(i))}
            ${field('ミニゲーム難易度', selectInput(`stages.${i}.difficulty`, arr(Creator.meta.difficulties)))}
            ${field('必要アイテム', textInput(`stages.${i}.item`, { list: 'dl-items', max: 64, placeholder: '空欄 = 不要' }), 'アイテム名 (例: lockpick)')}
            ${field('必要数', numberInput(`stages.${i}.itemCount`, { min: 1, max: 100 }))}
            <div class="field">${checkbox(`stages.${i}.consume`, '成功時にアイテムを消費する')}</div>
            ${field('突破時に解錠するドア (ox_doorlock)', doorsControl(i), 'このステージを突破するとドアが解錠され、ヘイスト終了後に再び施錠されます。ドアの近くで「一覧を更新」を押すと探しやすくなります。', true)}
        `)).join('');
        return `${cards || emptyState('ステージがありません。ハッキングやミニゲームのステージを1つ以上追加してください。')}
            <div class="row-actions"><button class="btn primary" data-act="add" data-arg="stages">＋ ステージを追加</button></div>`;
    },

    guards() {
        const d = Creator.draft;
        const cards = d.guards.map((guard, i) => listCard('guards', i, guard.model || `ガード ${i + 1}`, `
            ${field('モデル', textInput(`guards.${i}.model`, { list: 'dl-models', max: 64 }))}
            ${field('武器', textInput(`guards.${i}.weapon`, { list: 'dl-weapons', max: 64 }))}
            ${field('体力', numberInput(`guards.${i}.health`, { min: 1, max: 2000 }), '100 = 通常のNPC')}
            ${field('アーマー', numberInput(`guards.${i}.armour`, { max: 100 }))}
            ${field('命中率 (%)', numberInput(`guards.${i}.accuracy`, { max: 100 }))}
            ${field('行動パターン', selectInput(`guards.${i}.behavior`, arr(Creator.meta.behaviors)))}
            ${field('配置位置と向き', coordsControl(`guards.${i}.coords`, true), '', true)}
        `, `<button class="btn small" data-act="duplicate" data-arg="guards.${i}">複製</button>`)).join('');
        return `${cards || emptyState('ガードはいません。必要に応じてNPCガードを追加してください。')}
            <div class="row-actions"><button class="btn primary" data-act="add" data-arg="guards">＋ ガードを追加 (現在位置)</button></div>`;
    },

    loots() {
        const d = Creator.draft;
        const cards = d.loots.map((loot, i) => listCard('loots', i, loot.label || `物色ポイント ${i + 1}`, `
            ${field('表示名', textInput(`loots.${i}.label`, { max: 48, placeholder: '例: 金庫を物色する' }))}
            ${field('インタラクション方式', selectInput(`loots.${i}.interaction`, INTERACTIONS))}
            ${field('物色にかかる時間 (秒)', numberInput(`loots.${i}.duration`, { min: 1, max: 120 }))}
            <div class="field"></div>
            ${field('位置', coordsControl(`loots.${i}.coords`), '', true)}
            <div class="field wide">
                <span class="field-label">この物色ポイントの報酬テーブル</span>
                ${rewardTable(i)}
            </div>
        `, `<button class="btn small" data-act="duplicate" data-arg="loots.${i}" title="報酬テーブルごと複製します">複製</button>`)).join('');
        return `<div class="hint-box">物色ポイントごとに報酬テーブルを設定します。物色すると各行が個別に抽選され、複数の報酬が同時に出ることがあります。「確定」は必ず入手できます。「複製」で同じ報酬のポイントを増やせます。</div>
            ${cards || emptyState('物色ポイントがありません。追加すると、全ステージ突破後にプレイヤーが物色できます。')}
            <div class="row-actions"><button class="btn primary" data-act="add" data-arg="loots">＋ 物色ポイントを追加 (現在位置)</button></div>`;
    },
};

/** Loot table of one loot point. */
function rewardTable(lootIndex) {
    const rewards = arr(Creator.draft.loots[lootIndex].rewards);
    const base = `loots.${lootIndex}.rewards`;
    const rows = rewards.map((reward, j) => `<tr>
        <td>${textInput(`${base}.${j}.item`, { list: 'dl-items', max: 64, placeholder: 'アイテム名' })}</td>
        <td class="center">${checkbox(`${base}.${j}.guaranteed`, '確定', true)}</td>
        <td>${numberInput(`${base}.${j}.chance`, { max: 100, step: 0.1, disabled: reward.guaranteed })}</td>
        <td>${numberInput(`${base}.${j}.min`, { min: 1 })}</td>
        <td>${numberInput(`${base}.${j}.max`, { min: 1 })}</td>
        <td class="center"><button class="btn small danger" data-act="reward-remove" data-arg="${lootIndex}.${j}">削除</button></td>
    </tr>`).join('');
    return `<div class="reward-box">
        ${rows ? `<table class="table">
            <thead><tr><th>アイテム</th><th>確定</th><th>確率 (%)</th><th>最小数</th><th>最大数</th><th></th></tr></thead>
            <tbody>${rows}</tbody>
        </table>` : '<div class="reward-empty">報酬がありません。1つ以上追加してください。</div>'}
        <button class="btn small" data-act="reward-add" data-arg="${lootIndex}">＋ 報酬を追加</button>
    </div>`;
}

// ---------------------------------------------------------------------------
// Minigame picker (one tab per group, so the long list stays readable)
// ---------------------------------------------------------------------------
function minigameById(id) {
    return arr(Creator.meta.minigames).find((game) => game.id === id);
}

function minigameButton(stageIndex) {
    const game = minigameById(Creator.draft.stages[stageIndex].minigame);
    const group = game && arr(Creator.meta.minigameGroups).find((entry) => entry.id === game.group);
    return `<button class="picker-button" data-act="picker-open" data-arg="${stageIndex}">
        <span>${esc(game ? game.label : '未選択')}</span>
        <small>${esc(group ? group.label : '')}　変更 ▸</small>
    </button>`;
}

function renderPicker() {
    const root = $('#creator-picker');
    if (!Creator.picker) {
        root.classList.add('hidden');
        root.innerHTML = '';
        return;
    }
    const groups = arr(Creator.meta.minigameGroups);
    const current = Creator.draft.stages[Creator.picker.stage].minigame;
    const active = groups.find((group) => group.id === Creator.picker.group) || groups[0];
    const games = arr(Creator.meta.minigames).filter((game) => game.group === active.id);

    root.classList.remove('hidden');
    root.innerHTML = `<div class="picker">
        <div class="picker-head">
            <div class="main-title">ミニゲームを選択 <span class="mute">ステージ ${Creator.picker.stage + 1}</span></div>
            <button class="btn icon" data-act="picker-close">✕</button>
        </div>
        <nav class="tabs">${groups.map((group) => {
            const count = arr(Creator.meta.minigames).filter((game) => game.group === group.id).length;
            return `<button class="tab${group.id === active.id ? ' active' : ''}${group.available ? '' : ' off'}" data-act="picker-tab" data-arg="${group.id}">${esc(group.label)}<span class="tab-count">${count}</span></button>`;
        }).join('')}</nav>
        ${active.available ? '' : `<div class="hint-box warn">リソース「${esc(active.resource)}」が起動していません。起動するとこのタブのミニゲームを使用できます。</div>`}
        <div class="picker-grid">${games.map((game) => `
            <button class="picker-card${game.id === current ? ' active' : ''}" data-act="picker-select" data-arg="${esc(game.id)}"${active.available ? '' : ' disabled'}>
                <span class="picker-name">${esc(game.label)}</span>
                <span class="picker-desc">${esc(game.desc)}</span>
            </button>`).join('')}</div>
    </div>`;
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------
function renderCreatorList() {
    const list = Creator.heists.map((heist) => `
        <button class="side-item${Creator.view === 'heist' && Creator.draft && Creator.draft.id === heist.id ? ' active' : ''}" data-act="select-heist" data-arg="${heist.id}">
            <span class="side-item-name">${esc(heist.name)}</span>
            <span class="side-item-meta">
                <span class="dot ${heist.enabled ? 'on' : 'off'}"></span>${heist.enabled ? '有効' : '無効'}
                ・ステージ ${arr(heist.stages).length} ・XP ${num(heist.requiredXp)}
            </span>
        </button>`).join('');
    $('#creator-list').innerHTML = list || '<div class="side-empty">まだヘイストがありません</div>';
}

function renderNpcs() {
    const rows = Creator.npcs.map((npc, i) => `<tr>
        <td><input type="text" data-npc="${i}" value="${esc(npc.model)}" maxlength="64" list="dl-models" spellcheck="false"></td>
        <td>${num(npc.x).toFixed(2)}, ${num(npc.y).toFixed(2)}, ${num(npc.z).toFixed(2)} / ${num(npc.w).toFixed(0)}°</td>
        <td class="center">
            <button class="btn small" data-act="npc-move" data-arg="${i}">現在位置に移動</button>
            <button class="btn small ghost" data-act="npc-tp" data-arg="${i}">TP</button>
            <button class="btn small danger" data-act="npc-remove" data-arg="${i}">削除</button>
        </td>
    </tr>`).join('');
    return `<div class="hint-box">プレイヤーはこのNPCに ox_target で話しかけて Heist HUD を開きます。変更後は「NPCを保存」を押してください。</div>
        ${rows ? `<table class="table">
            <thead><tr><th>モデル</th><th>位置 / 向き</th><th></th></tr></thead>
            <tbody>${rows}</tbody>
        </table>` : emptyState('NPCが配置されていません。')}
        <div class="row-actions"><button class="btn primary" data-act="npc-add">＋ 現在位置にNPCを追加</button></div>`;
}

function renderCreator() {
    renderCreatorList();
    const content = $('#creator-content');
    const scroll = content.scrollTop;

    if (Creator.view === 'npcs') {
        $('#creator-title').textContent = '受付NPCの設定';
        $('#creator-tabs').innerHTML = '';
        $('#creator-actions').innerHTML = '<button class="btn primary" data-act="npc-save">NPCを保存</button>';
        content.innerHTML = renderNpcs();
    } else {
        const d = Creator.draft;
        $('#creator-title').textContent = d.id ? `編集: ${d.name || `#${d.id}`}` : '新しいヘイスト';
        $('#creator-tabs').innerHTML = CREATOR_TABS.map((tab) => {
            const count = Array.isArray(d[tab.id]) ? `<span class="tab-count">${d[tab.id].length}</span>` : '';
            return `<button class="tab${Creator.tab === tab.id ? ' active' : ''}" data-act="tab" data-arg="${tab.id}">${tab.label}${count}</button>`;
        }).join('');
        $('#creator-actions').innerHTML = `
            ${d.id ? `<button class="btn danger" data-act="delete-heist">${Creator.confirmDelete ? '本当に削除する' : '削除'}</button>` : ''}
            <button class="btn primary" data-act="save-heist">保存</button>`;
        if (!TAB_RENDERERS[Creator.tab]) Creator.tab = 'basic';
        content.innerHTML = TAB_RENDERERS[Creator.tab]();
    }
    content.scrollTop = scroll;
    renderPicker();
}

function fillDatalists() {
    $('#dl-items').innerHTML = arr(Creator.meta.items).map((item) =>
        `<option value="${esc(item.name)}">${esc(item.label)}</option>`).join('');
    $('#dl-models').innerHTML = arr(Creator.meta.models).map((model) => `<option value="${esc(model)}">`).join('');
    $('#dl-weapons').innerHTML = arr(Creator.meta.weapons).map((weapon) => `<option value="${esc(weapon)}">`).join('');
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------
async function addEntry(kind) {
    const d = Creator.draft;
    const limits = Creator.meta.limits || {};
    if (limits[kind] && d[kind].length >= limits[kind]) {
        toast('creator-toast', `これ以上追加できません (最大 ${limits[kind]})`, 'error');
        return;
    }

    if (kind === 'stages') {
        const first = arr(Creator.meta.minigames).find((game) => game.group === 'basic') || arr(Creator.meta.minigames)[0];
        d.stages.push({
            label: '', coords: await post('creator:getPosition'), interaction: 'key', item: '', itemCount: 1,
            consume: false, minigame: first ? first.id : '', difficulty: 'medium', doors: [],
        });
    } else if (kind === 'guards') {
        d.guards.push({
            model: arr(Creator.meta.models)[0] || 's_m_m_security_01',
            weapon: arr(Creator.meta.weapons)[0] || 'WEAPON_PISTOL',
            health: 100, armour: 0, accuracy: 40, behavior: 'aggressive',
            coords: await post('creator:getPosition'),
        });
    } else if (kind === 'loots') {
        d.loots.push({ label: '', coords: await post('creator:getPosition'), interaction: 'key', duration: 8, rewards: [] });
    }
    renderCreator();
    const content = $('#creator-content');
    content.scrollTop = content.scrollHeight;
}

async function saveHeist() {
    const answer = await post('creator:save', { heist: Creator.draft });
    if (!answer.ok) {
        toast('creator-toast', answer.result || '保存に失敗しました', 'error');
        return;
    }
    Creator.heists = arr(answer.result.heists);
    const saved = Creator.heists.find((heist) => heist.id === answer.result.id);
    if (saved) Creator.draft = normalizeHeist(saved);
    Creator.confirmDelete = false;
    toast('creator-toast', 'ヘイストを保存しました', 'success');
    renderCreator();
}

async function deleteHeist() {
    if (!Creator.confirmDelete) {
        Creator.confirmDelete = true;
        renderCreator();
        return;
    }
    const answer = await post('creator:delete', { id: Creator.draft.id });
    Creator.confirmDelete = false;
    if (!answer.ok) {
        toast('creator-toast', answer.result || '削除に失敗しました', 'error');
        renderCreator();
        return;
    }
    Creator.heists = arr(answer.result.heists);
    Creator.draft = newDraft();
    Creator.tab = 'basic';
    toast('creator-toast', 'ヘイストを削除しました', 'success');
    renderCreator();
}

const CREATOR_ACTIONS = {
    'new-heist'() {
        Creator.view = 'heist';
        Creator.draft = newDraft();
        Creator.tab = 'basic';
        Creator.confirmDelete = false;
        renderCreator();
    },
    'select-heist'(arg) {
        const heist = Creator.heists.find((entry) => String(entry.id) === arg);
        if (!heist) return;
        Creator.view = 'heist';
        Creator.draft = normalizeHeist(heist);
        Creator.confirmDelete = false;
        renderCreator();
    },
    'view-npcs'() {
        Creator.view = 'npcs';
        renderCreator();
    },
    tab(arg) {
        Creator.tab = arg;
        $('#creator-content').scrollTop = 0;
        renderCreator();
    },
    add: addEntry,
    remove(arg) {
        const [kind, index] = arg.split('.');
        Creator.draft[kind].splice(Number(index), 1);
        renderCreator();
    },
    duplicate(arg) {
        const [kind, index] = arg.split('.');
        const list = Creator.draft[kind];
        list.splice(Number(index) + 1, 0, JSON.parse(JSON.stringify(list[Number(index)])));
        renderCreator();
    },
    'move-up'(arg) {
        const [kind, index] = arg.split('.');
        const list = Creator.draft[kind];
        const i = Number(index);
        if (i > 0) [list[i - 1], list[i]] = [list[i], list[i - 1]];
        renderCreator();
    },
    'move-down'(arg) {
        const [kind, index] = arg.split('.');
        const list = Creator.draft[kind];
        const i = Number(index);
        if (i < list.length - 1) [list[i + 1], list[i]] = [list[i], list[i + 1]];
        renderCreator();
    },
    async 'pos-current'(arg) {
        setPath(Creator.draft, arg, await post('creator:getPosition'));
        renderCreator();
    },
    async 'pos-pick'(arg) {
        const answer = await post('creator:pickPosition');
        if (answer.ok && answer.coords) {
            setPath(Creator.draft, arg, answer.coords);
            renderCreator();
        }
    },
    'pos-tp'(arg) {
        const coords = getPath(Creator.draft, arg);
        if (coords) post('creator:teleport', coords);
    },
    'reward-add'(arg) {
        const loot = Creator.draft.loots[Number(arg)];
        const limit = (Creator.meta.limits || {}).rewards;
        loot.rewards = arr(loot.rewards);
        if (limit && loot.rewards.length >= limit) {
            toast('creator-toast', `これ以上追加できません (最大 ${limit})`, 'error');
            return;
        }
        loot.rewards.push({ item: '', guaranteed: false, chance: 50, min: 1, max: 1 });
        renderCreator();
    },
    'reward-remove'(arg) {
        const [loot, index] = arg.split('.').map(Number);
        Creator.draft.loots[loot].rewards.splice(index, 1);
        renderCreator();
    },
    'picker-open'(arg) {
        const stage = Number(arg);
        const game = minigameById(Creator.draft.stages[stage].minigame);
        Creator.picker = { stage, group: game ? game.group : null };
        renderPicker();
    },
    'picker-close'() {
        Creator.picker = null;
        renderPicker();
    },
    'picker-tab'(arg) {
        Creator.picker.group = arg;
        renderPicker();
    },
    'picker-select'(arg) {
        Creator.draft.stages[Creator.picker.stage].minigame = arg;
        Creator.picker = null;
        renderCreator();
    },
    'door-remove'(arg) {
        const [stage, id] = arg.split('.').map(Number);
        const stageData = Creator.draft.stages[stage];
        stageData.doors = arr(stageData.doors).filter((door) => door !== id);
        renderCreator();
    },
    async 'doors-refresh'() {
        const answer = await post('creator:getDoors');
        if (answer.ok) Creator.doors = arr(answer.result);
        renderCreator();
    },
    'save-heist': saveHeist,
    'delete-heist': deleteHeist,
    async 'reset-cooldown'() {
        const answer = await post('creator:resetCooldown', { id: Creator.draft.id });
        toast('creator-toast', answer.result || (answer.ok ? '完了' : '失敗しました'), answer.ok ? 'success' : 'error');
    },
    async 'npc-add'() {
        const limits = Creator.meta.limits || {};
        if (limits.npcs && Creator.npcs.length >= limits.npcs) {
            toast('creator-toast', `これ以上追加できません (最大 ${limits.npcs})`, 'error');
            return;
        }
        const position = await post('creator:getPosition');
        Creator.npcs.push(Object.assign({ model: Creator.meta.defaultNpcModel || '' }, position));
        renderCreator();
    },
    async 'npc-move'(arg) {
        Object.assign(Creator.npcs[Number(arg)], await post('creator:getPosition'));
        renderCreator();
    },
    'npc-tp'(arg) {
        post('creator:teleport', Creator.npcs[Number(arg)]);
    },
    'npc-remove'(arg) {
        Creator.npcs.splice(Number(arg), 1);
        renderCreator();
    },
    async 'npc-save'() {
        const answer = await post('creator:saveNpcs', { npcs: Creator.npcs });
        if (answer.ok) Creator.npcs = arr(answer.result.npcs);
        toast('creator-toast', answer.ok ? 'NPCを保存しました' : (answer.result || '保存に失敗しました'), answer.ok ? 'success' : 'error');
        renderCreator();
    },
};

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------
$('#creator').addEventListener('click', (event) => {
    const button = event.target.closest('[data-act]');
    if (!button || button.disabled) return;
    const action = CREATOR_ACTIONS[button.dataset.act];
    if (action) action(button.dataset.arg);
});

$('#creator-content').addEventListener('input', (event) => {
    const input = event.target;

    if (input.dataset.doorAdd != null) {
        const stage = Creator.draft.stages[Number(input.dataset.doorAdd)];
        const id = Number(input.value);
        if (id && !arr(stage.doors).includes(id)) stage.doors = arr(stage.doors).concat(id);
        renderCreator();
        return;
    }
    if (input.dataset.npc != null) {
        Creator.npcs[Number(input.dataset.npc)].model = input.value.trim();
        return;
    }
    if (!input.dataset.path || !Creator.draft) return;

    let value;
    if (input.dataset.type === 'bool') value = input.checked;
    else if (input.dataset.type === 'number') value = input.value === '' ? 0 : Number(input.value);
    else value = input.value;

    setPath(Creator.draft, input.dataset.path, value);
    if (input.dataset.rerender != null) renderCreator();
});

on('creator:open', (data) => {
    const firstOpen = !Creator.draft;
    Creator.heists = arr(data.heists);
    Creator.npcs = arr(data.npcs).map((npc) => Object.assign({}, npc));
    Creator.meta = data.meta || {};
    Creator.doors = arr(data.doors);
    // The unsaved draft is kept between openings so an admin can walk around
    // and continue where they left off.
    if (firstOpen) Creator.draft = newDraft();
    fillDatalists();
    renderCreator();
    showPage('creator', true);
});

on('creator:hide', () => $('#creator').classList.add('hidden'));
on('creator:show', () => $('#creator').classList.remove('hidden'));
on('creator:close', () => {
    Creator.picker = null;
    renderPicker();
    showPage('creator', false);
});
