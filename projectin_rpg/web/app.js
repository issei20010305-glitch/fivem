/* Project IN RPG - NUI (依存ライブラリなし) */
'use strict';

const RES = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'projectin_rpg';
const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const clamp = (n, a, b) => Math.max(a, Math.min(b, n));
const fmtTime = (s) => { s = Math.max(0, Math.floor(s)); return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`; };
const fmtDur = (s) => {
    s = Math.max(0, Math.floor(s));
    if (s >= 3600) { const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60); return m ? `${h}時間${m}分` : `${h}時間`; }
    if (s >= 60) return `${Math.ceil(s / 60)}分`;
    return `${s}秒`;
};
const ROLE_COLORS = { tank: '#4aa3ff', attacker: '#ff5a5a', porter: '#ffc24a', mage: '#b57bff' };

async function post(endpoint, body = {}) {
    try {
        const r = await fetch(`https://${RES}/${endpoint}`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(body) });
        return await r.json();
    } catch (e) { return null; }
}
async function req(name, ...args) {
    const r = await post('request', { name, args });
    if (!r) return { ok: false, error: '通信に失敗しました' };
    return r;
}
async function admin(action, payload = {}) { return req('admin', action, payload); }

/* ===================== トースト / モーダル ===================== */
function toast(message, type = 'info', duration = 5000) {
    const el = document.createElement('div');
    el.className = `toast ${type}`;
    el.textContent = message;
    $('#toasts').appendChild(el);
    while ($('#toasts').children.length > 6) $('#toasts').firstChild.remove();
    setTimeout(() => { el.classList.add('fadeout'); setTimeout(() => el.remove(), 500); }, duration);
}
function modal({ title, body, html, buttons }) {
    return new Promise((resolve) => {
        const back = document.createElement('div');
        back.className = 'modal-back';
        back.innerHTML = `<div class="modal"><h3>${esc(title)}</h3><div class="mbody">${html ?? esc(body ?? '')}</div><div class="mfoot"></div></div>`;
        const foot = $('.mfoot', back);
        (buttons || [{ label: 'OK', value: true, cls: 'btn-primary' }]).forEach((b) => {
            const bt = document.createElement('button');
            bt.className = `btn ${b.cls || ''}`;
            bt.textContent = b.label;
            bt.onclick = () => { const v = typeof b.value === 'function' ? b.value(back) : b.value; back.remove(); resolve(v); };
            foot.appendChild(bt);
        });
        $('#modal-root').appendChild(back);
        const first = $('input,select,textarea', back);
        if (first) first.focus();
    });
}
const confirmBox = (title, body, okLabel = '実行', danger = false) => modal({ title, body, buttons: [
    { label: 'キャンセル', value: false }, { label: okLabel, value: true, cls: danger ? 'btn-danger' : 'btn-primary' }] });
async function promptBox(title, label, def = '') {
    return modal({ title, html: `<label class="f">${esc(label)}<input id="pr-in" value="${esc(def)}"></label>`, buttons: [
        { label: 'キャンセル', value: null }, { label: 'OK', cls: 'btn-primary', value: (b) => $('#pr-in', b).value }] });
}
async function act(promise, okMsg) {
    const r = await promise;
    if (!r.ok) { toast(r.error || '失敗しました', 'error'); return null; }
    if (r.message) toast(r.message, 'success'); else if (okMsg) toast(okMsg, 'success');
    return r;
}

/* ===================== 告知 / バナー ===================== */
function announce(d) {
    const el = document.createElement('div');
    el.className = `announce ${d.kind === 'raid' ? 'raid' : ''}`;
    el.innerHTML = `<div class="a-title">${esc(d.title || 'お知らせ')}</div><div class="a-text">${esc(d.text)}</div>${d.eventId ? '<div class="a-sub">/rpg → イベント でGPSを設定できます</div>' : ''}`;
    $('#announce-stack').appendChild(el);
    while ($('#announce-stack').children.length > 3) $('#announce-stack').firstChild.remove();
    setTimeout(() => { el.classList.add('fadeout'); setTimeout(() => el.remove(), 500); }, 10000);
}
let bannerTimer = null;
function banner(d) {
    const b = $('#banner');
    b.className = d.kind || '';
    $('.banner-title', b).textContent = d.title || '';
    $('.banner-text', b).textContent = d.text || '';
    b.classList.remove('hidden');
    b.style.animation = 'none'; void b.offsetWidth; b.style.animation = '';
    clearTimeout(bannerTimer);
    bannerTimer = setTimeout(() => b.classList.add('hidden'), 4200);
}

/* ===================== 戦闘HUD ===================== */
const H = { skills: [], cooldowns: {}, mp: 0, maxMp: 100, timeLeft: 0, target: null, members: [], role: null };
setInterval(() => {
    if ($('#hud').classList.contains('hidden')) return;
    H.timeLeft = Math.max(0, H.timeLeft - 1);
    const t = $('#hud-timer');
    t.textContent = fmtTime(H.timeLeft);
    t.classList.toggle('danger', H.timeLeft <= 60);
    for (const k in H.cooldowns) H.cooldowns[k] = Math.max(0, H.cooldowns[k] - 1);
    renderSkills();
}, 1000);

function hudShow(d) {
    if (!d.show) { $('#hud').classList.add('hidden'); $('#hud-boss').classList.add('hidden'); return; }
    $('#hud').classList.remove('hidden');
    $('#hud-name').textContent = d.name;
    $('#hud-test').classList.toggle('hidden', !d.test);
    H.role = d.role; H.skills = d.skills || []; H.maxMp = d.maxMp || 100; H.timeLeft = d.timeLimit || 0; H.cooldowns = {};
    $('#self-role').innerHTML = `<span style="color:${ROLE_COLORS[d.role]}">${esc(d.roleLabel)}</span>`;
    $('#self-mp').classList.toggle('hidden', d.role !== 'mage');
    $('#hud-skills').classList.toggle('hidden', !(d.skills && d.skills.length));
    $('#hud-obj-title').textContent = '準備中…';
    $('#hud-obj-progress').textContent = '';
    $('#hud-wave').textContent = d.type === 'raid' ? 'RAID' : 'DUNGEON';
    renderSkills();
}
function renderSkills() {
    if (!H.skills.length) return;
    $('#hud-skills').innerHTML = H.skills.map((s) => {
        const cd = H.cooldowns[s.id] || 0;
        const pct = cd > 0 ? (cd / s.cooldown) * 100 : 0;
        return `<div class="skill ${H.mp < s.mp ? 'nomp' : ''}" data-skill="${esc(s.id)}"><span class="k">${s.key}</span>
            <span class="nm">${esc(s.label)}</span><span class="mp">MP ${s.mp}</span>
            <div class="cd" style="height:${pct}%"></div>${cd > 0 ? `<div class="cdn">${cd}</div>` : ''}</div>`;
    }).join('');
}
function hudParty(d) {
    H.members = d.members || [];
    if (d.me) {
        if (typeof d.me.mp === 'number') H.mp = d.me.mp;
        H.cooldowns = Object.assign({}, d.me.cooldowns || {});
    }
    $('#hud-party').innerHTML = H.members.map((m) => {
        const hp = m.maxHp ? clamp(m.hp / m.maxHp * 100, 0, 100) : 0;
        const mp = m.maxMp ? clamp(m.mp / m.maxMp * 100, 0, 100) : 0;
        return `<div class="pm ${m.downed ? 'downed' : ''} ${H.target === m.id ? 'target' : ''}" style="--rc:${esc(m.color)}">
            <div class="pm-top"><span>${m.downed ? '💀 ' : ''}${esc(m.name)}</span><span class="pm-role">${esc(m.roleLabel)}${m.buff ? ` 🔥${m.buff}s` : ''}</span></div>
            <div class="bar bar-hp"><div class="fill" style="width:${hp}%"></div></div>
            ${m.maxMp ? `<div class="bar bar-mp"><div class="fill" style="width:${mp}%"></div></div>` : ''}</div>`;
    }).join('');
    if (H.role === 'mage') {
        $('#self-mp-fill').style.width = `${clamp(H.mp / H.maxMp * 100, 0, 100)}%`;
        $('#self-mp-text').textContent = `MP ${Math.floor(H.mp)} / ${H.maxMp}`;
    }
    renderSkills();
}
function hudObjective(d) {
    H.timeLeft = d.timeLeft;
    $('#hud-wave').textContent = d.wave > 0 ? `WAVE ${d.wave} / ${d.waveCount}　${d.waveLabel}` : '';
    $('#hud-obj-title').textContent = d.state === 'delay' ? '次のウェーブに備えろ…' : (d.state === 'cleared' ? 'ウェーブクリア！' : d.title);
    $('#hud-obj-progress').textContent = d.state === 'running' ? d.progress : '';
    const b = d.boss;
    if (b && b.alive) {
        $('#hud-boss').classList.remove('hidden');
        $('#boss-name').textContent = b.label;
        $('#boss-phase').textContent = b.phase;
        $('#boss-fill').style.width = `${clamp(b.hp / b.maxHp * 100, 0, 100)}%`;
        $('#boss-num').textContent = `${b.hp.toLocaleString()} / ${b.maxHp.toLocaleString()}`;
    } else {
        $('#hud-boss').classList.add('hidden');
    }
}
function selfHp(d) {
    $('#self-hp-fill').style.width = `${d.maxHp ? clamp(d.hp / d.maxHp * 100, 0, 100) : 0}%`;
    $('#self-hp-text').textContent = `HP ${d.hp} / ${d.maxHp}`;
}
let progressTimer = null;
function progress(d) {
    clearInterval(progressTimer);
    if (!d.show) { $('#progress').classList.add('hidden'); return; }
    $('#progress').classList.remove('hidden');
    $('#progress-label').textContent = d.label;
    const start = Date.now();
    progressTimer = setInterval(() => {
        const p = clamp((Date.now() - start) / d.duration, 0, 1);
        $('#progress-fill').style.width = `${p * 100}%`;
        if (p >= 1) clearInterval(progressTimer);
    }, 50);
}

/* ===================== 画面管理 ===================== */
const S = { screen: null, profile: null, tab: 'home', events: [], inv: null, invSel: null, party: null, entry: null, results: null, items: [] };

function show(html, wide = false) {
    $('#app').classList.remove('hidden');
    $('#screen').innerHTML = html;
    const w = $('.window', $('#screen'));
    if (w && wide) w.classList.add('wide');
}
async function closeUI() {
    if (S.screen === 'editor' && ED.dirty) {
        if (!(await confirmBox('未保存の変更', '保存していない変更があります。破棄して閉じますか？', '破棄して閉じる', true))) return;
    }
    $('#app').classList.add('hidden');
    $('#screen').innerHTML = '';
    $('#modal-root').innerHTML = '';
    S.screen = null;
    ED.dirty = false;
    post('editorPreview', { data: null });
    post('close');
}
document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !$('#app').classList.contains('hidden')) {
        if ($('#modal-root').children.length) { $('#modal-root').lastChild.remove(); return; }
        closeUI();
    }
});

function winHead(sub) {
    const p = S.profile;
    const role = p && p.role && p.roles.find((r) => r.id === p.role);
    return `<div class="win-head"><div class="win-logo">PROJECT <span>IN</span> RPG</div><div class="muted">${esc(sub || '')}</div>
        ${role ? `<span class="role-pill" style="color:${role.color};border-color:${role.color}">${esc(role.icon)} ${esc(role.label)}</span>` : ''}
        <button class="win-close" data-act="close">×</button></div>`;
}

async function reloadProfile() {
    const r = await req('getProfile');
    if (r.ok && r.data) { S.profile = r.data; S.events = r.data.events || S.events; }
    return S.profile;
}

/* ===================== ロール選択 ===================== */
function renderRole(sel) {
    S.screen = 'role';
    const p = S.profile;
    const max = { hpMult: 1.5, damageMult: 1.5, inventoryMult: 2 };
    show(`<div class="window">${winHead('ロール選択')}
      <div class="role-screen">
        <div><h1>あなたの役割を選んでください</h1><div class="muted">ロールの効果はダンジョン/ボスレイドの中でのみ発揮されます。街での通常RPには一切影響しません。</div></div>
        <div class="role-warn">⚠ ロールは <b>キャラクターごとに一度だけ</b> 選択できます。変更は管理者のみが行えます。</div>
        <div class="role-cards">${p.roles.map((r) => `
          <div class="role-card ${sel === r.id ? 'sel' : ''}" style="--rc:${r.color}" data-act="pickRole" data-id="${r.id}">
            <div class="role-icon">${esc(r.icon)}</div><div class="role-name">${esc(r.label)}</div>
            <div class="role-desc">${esc(r.description)}</div>
            <div class="stat-line"><span class="lbl">HP</span><div class="stat-bar"><div style="width:${r.hpMult / max.hpMult * 100}%"></div></div><span>×${r.hpMult}</span></div>
            <div class="stat-line"><span class="lbl">攻撃力</span><div class="stat-bar"><div style="width:${r.damageMult / max.damageMult * 100}%"></div></div><span>${r.canAttack ? '×' + r.damageMult : '不可'}</span></div>
            <div class="stat-line"><span class="lbl">所持容量</span><div class="stat-bar"><div style="width:${r.inventoryMult / max.inventoryMult * 100}%"></div></div><span>×${r.inventoryMult}</span></div>
            ${r.id === 'mage' ? '<div class="small" style="color:var(--mage)">✦ ヒール / パワーブースト / サンクチュアリ / リザレクション</div>' : ''}
          </div>`).join('')}</div>
        <div class="row"><div class="spacer"></div><button class="btn btn-primary" data-act="confirmRole" ${sel ? '' : 'disabled'}>このロールに決定する</button></div>
      </div></div>`);
    S.roleSel = sel;
}

/* ===================== ハブ ===================== */
const TABS = [
    { id: 'home', ico: '🏠', label: 'ホーム' },
    { id: 'events', ico: '📅', label: 'イベント' },
    { id: 'party', ico: '👥', label: 'パーティー' },
    { id: 'inventory', ico: '🎒', label: 'RPGインベントリ' },
    { id: 'admin', ico: '🛠', label: '管理', admin: true },
];
function renderHub(tab) {
    S.screen = 'hub';
    S.tab = tab || S.tab || 'home';
    const p = S.profile;
    const tabs = TABS.filter((t) => !t.admin || p.isAdmin);
    const wide = S.tab === 'admin';
    show(`<div class="window">${winHead(p.name)}
        <div class="win-body"><div class="tabs">${tabs.map((t) => `<div class="tab ${t.id === S.tab ? 'active' : ''}" data-act="tab" data-id="${t.id}"><span class="ico">${t.ico}</span>${t.label}</div>`).join('')}
        <div class="spacer"></div><div class="small muted" style="padding:6px">日本時間 ${esc(p.nowJst)}</div></div>
        <div class="content" id="tab-content"></div></div></div>`, wide);
    renderTab();
}
function renderTab() {
    const c = $('#tab-content');
    if (!c) return;
    ({ home: tabHome, events: tabEvents, party: tabParty, inventory: tabInventory, admin: tabAdmin }[S.tab] || tabHome)(c);
}

function tabHome(c) {
    const p = S.profile;
    const role = p.roles.find((r) => r.id === p.role);
    const st = p.stats || {};
    c.innerHTML = `
      <div class="hero" style="--rc:${role.color}"><div class="hero-icon" style="color:${role.color}">${esc(role.icon)}</div>
        <div><div class="muted small">あなたのロール</div><h2 style="color:${role.color}">${esc(role.label)}</h2><div class="muted">${esc(role.description)}</div></div></div>
      <div class="stats">
        <div class="stat"><div class="n">${st.runs || 0}</div><div class="l">挑戦回数</div></div>
        <div class="stat"><div class="n">${st.dungeonClears || 0}</div><div class="l">ダンジョン踏破</div></div>
        <div class="stat"><div class="n">${st.raidClears || 0}</div><div class="l">レイド討伐</div></div>
        <div class="stat"><div class="n">${st.kills || 0}</div><div class="l">討伐数</div></div>
      </div>
      ${p.inRun ? `<div class="card" style="margin-top:14px;border-color:var(--warn)"><h3>現在 ${esc(p.inRun.name)} に参加中${p.inRun.test ? ' (テスト)' : ''}</h3>
        <div class="muted small">離脱すると報酬は受け取れません。拾ったドロップは既にRPGインベントリに入っています。</div>
        <div class="row" style="margin-top:10px"><button class="btn btn-danger" data-act="leaveRun">ダンジョンから離脱する</button></div></div>` : ''}
      <div class="sec-title">開催中・予定のイベント</div>
      ${eventsHtml(S.events.slice(0, 3))}
      ${role.id === 'mage' ? `<div class="sec-title">魔導士スキル (ダンジョン内でキー1〜4 / 対象切替 G)</div>
        <div class="grid4">${Object.entries(p.mage.skills).sort((a, b) => a[1].key - b[1].key).map(([, s]) => `<div class="card"><b>${s.key}. ${esc(s.label)}</b><div class="small muted">MP ${s.mp} / CT ${s.cooldown}秒 / 射程 ${s.range}m</div></div>`).join('')}</div>` : ''}`;
}

function eventsHtml(list) {
    if (!list.length) return '<div class="empty">現在開催中・予定のイベントはありません</div>';
    return `<div class="list">${list.map((ev) => {
        const live = ev.status === 'active';
        const time = ev.type === 'raid'
            ? (live ? '<span class="live">● 戦闘中</span>' : `開始まで ${fmtDur(ev.startIn)}`)
            : (live ? `<span class="live">● 開催中</span><div class="small muted">${esc(ev.endLabel)}まで</div>` : `${esc(ev.startLabel)} 開始`);
        return `<div class="card ev-card ${ev.type}"><div class="ev-icon">${ev.type === 'raid' ? '🐉' : '🏚'}</div>
          <div class="ev-main"><div class="ev-title"><span class="badge badge-${ev.type}">${ev.type === 'raid' ? '大型ボスレイド' : 'ダンジョン'}</span>${esc(ev.name)}</div>
            <div class="ev-sub">📍 ${esc(ev.location)}　👥 ${ev.minPlayers}〜${ev.maxPlayers}人　⏱ 制限${fmtDur(ev.timeLimit)}${ev.type === 'raid' ? `　登録 ${ev.registered}/${ev.maxPlayers}` : ''}</div>
            ${ev.recommended ? `<div class="ev-sub">${esc(ev.recommended)}</div>` : ''}</div>
          <div class="ev-time">${time}<div style="margin-top:6px"><button class="btn btn-sm" data-act="gps" data-id="${ev.id}">📍 GPS設定</button></div></div></div>`;
    }).join('')}</div>`;
}
function tabEvents(c) {
    c.innerHTML = `<div class="help">イベント地点のマーカーで <b>E</b> を押すと入場(ダンジョン)/参加登録(レイド)ができます。パーティーで入場する場合はリーダーが操作してください。</div>${eventsHtml(S.events)}`;
}

/* ----- パーティー ----- */
async function tabParty(c) {
    const r = await req('party', 'get');
    if (!r.ok) { c.innerHTML = `<div class="empty">${esc(r.error)}</div>`; return; }
    S.party = r.data;
    const near = await req('party', 'nearby');
    const nearby = near.ok ? near.data : [];
    const d = S.party;
    const invites = d.invites.length ? `<div class="sec-title">届いている招待</div><div class="list">${d.invites.map((i) => `
        <div class="member"><span class="nm">${esc(i.leaderName)} のパーティー (${i.size}人)</span>
        <button class="btn btn-sm btn-ok" data-act="partyAccept" data-id="${i.partyId}">参加</button>
        <button class="btn btn-sm" data-act="partyDecline" data-id="${i.partyId}">拒否</button></div>`).join('')}</div>` : '';
    let body;
    if (!d.party) {
        body = `<div class="empty">パーティーに所属していません。ソロでも入場できます。<div style="margin-top:12px"><button class="btn btn-primary" data-act="partyCreate">パーティーを作成</button></div></div>`;
    } else {
        const p = d.party;
        body = `<div class="sec-title">メンバー (${p.members.length}/${d.maxSize})</div><div class="list">${p.members.map((m) => `
          <div class="member"><span style="color:${esc(m.roleColor)};font-weight:800;width:90px">${esc(m.roleLabel)}</span>
            <span class="nm">${m.leader ? '<span class="crown">👑</span> ' : ''}${esc(m.name)} <span class="muted small">ID ${m.id}</span></span>
            ${p.isLeader && !m.leader ? `<button class="btn btn-sm" data-act="partyPromote" data-id="${m.id}">リーダー委任</button><button class="btn btn-sm btn-danger" data-act="partyKick" data-id="${m.id}">キック</button>` : ''}
          </div>`).join('')}</div>
          <div class="row" style="margin-top:12px"><button class="btn btn-danger" data-act="partyLeave">パーティーを抜ける</button></div>`;
    }
    const canInvite = !d.party || d.party.isLeader;
    c.innerHTML = `${invites}${body}
      ${canInvite ? `<div class="sec-title">近くのプレイヤーを招待</div>
      ${nearby.length ? `<div class="list">${nearby.map((n) => `<div class="member"><span class="nm">${esc(n.name)} <span class="muted small">ID ${n.id}</span></span>
        ${n.inParty ? '<span class="muted small">パーティー所属中</span>' : `<button class="btn btn-sm btn-primary" data-act="partyInvite" data-id="${n.id}">招待</button>`}</div>`).join('')}</div>`
        : '<div class="empty">30m以内にプレイヤーがいません</div>'}
      <div class="row" style="margin-top:10px"><input id="invite-id" placeholder="サーバーIDで招待" style="width:200px"><button class="btn" data-act="partyInviteId">招待</button></div>` : ''}`;
}

/* ----- RPGインベントリ ----- */
async function tabInventory(c) {
    const r = await req('getInventory');
    if (!r.ok || !r.data) { c.innerHTML = `<div class="empty">${esc(r.error || '読み込めません')}</div>`; return; }
    S.inv = r.data;
    const inv = S.inv;
    const bySlot = {};
    inv.items.forEach((i) => { bySlot[i.slot] = i; });
    const total = Math.max(inv.slots, inv.baseSlots, inv.usableSlots);
    let cells = '';
    for (let s = 1; s <= total; s++) {
        const it = bySlot[s];
        const locked = s > inv.usableSlots && !it;
        cells += `<div class="slot ${locked ? 'locked' : ''} ${S.invSel === s ? 'sel' : ''}" data-slot="${s}" draggable="${it ? 'true' : 'false'}" data-act="invSel">
          <span class="num">${s}</span>${it ? `<span class="ico">${esc(it.icon)}</span><span class="cnt">${it.count}</span><span class="rar" style="background:var(--${it.rarity})"></span>` : ''}</div>`;
    }
    const sel = bySlot[S.invSel];
    const wpct = clamp(inv.weight / inv.maxWeight * 100, 0, 100);
    c.innerHTML = `<div class="help">RPGインベントリはダンジョン/レイド専用の倉庫です。ここのアイテムは街の通常インベントリには移動できません。
        ${inv.usableSlots > inv.baseSlots ? '<br>🎒 荷物持ちボーナス適用中 (スロット・重量2倍)' : (S.profile.role === 'porter' ? '<br>🎒 荷物持ちの容量2倍はダンジョン/レイド内で有効になります' : '')}</div>
      <div class="inv-wrap"><div>
        <div class="row"><b>スロット ${inv.items.length} / ${inv.usableSlots}</b><div class="spacer"></div><span class="small muted">重量 ${(inv.weight / 1000).toFixed(1)} / ${(inv.maxWeight / 1000).toFixed(1)} kg</span></div>
        <div class="weight"><div style="width:${wpct}%"></div></div>
        <div class="inv-grid" style="margin-top:10px">${cells}</div>
        ${inv.overflow.length ? `<div class="sec-title">受取箱 (容量不足で保留中の報酬)</div><div class="card"><div class="reward-list">${inv.overflow.map((o) => `<span class="reward"><span>${esc(o.icon)}</span><span class="r-${o.rarity}">${esc(o.label)}</span> x${o.count}</span>`).join('')}</div>
          <div class="row" style="margin-top:10px"><button class="btn btn-primary btn-sm" data-act="invOverflow">インベントリへ受け取る</button></div></div>` : ''}
      </div>
      <div class="card detail">${sel ? `<div class="big-ico">${esc(sel.icon)}</div><h3 class="r-${sel.rarity}" style="text-align:center">${esc(sel.label)}</h3>
          <div class="small" style="text-align:center"><span class="badge">${esc(sel.rarityLabel)}</span> 所持 ${sel.count} / 重量 ${sel.weight}g</div>
          <p class="muted" style="margin:12px 0;line-height:1.6">${esc(sel.description)}</p>
          ${sel.usable ? `<button class="btn btn-primary" style="width:100%;margin-bottom:8px" data-act="invUse" data-slot="${sel.slot}" ${inv.inRun ? '' : 'disabled'}>使用する${inv.inRun ? '' : ' (ダンジョン内のみ)'}</button>` : ''}
          <div class="row"><input type="number" id="discard-n" min="1" max="${sel.count}" value="1" style="width:80px"><button class="btn btn-danger" data-act="invDiscard" data-slot="${sel.slot}">捨てる</button></div>`
        : '<div class="empty">アイテムを選択してください<br><span class="small">ドラッグで並べ替えできます</span></div>'}</div></div>`;
    bindInvDrag(c);
}
function bindInvDrag(c) {
    let from = null;
    $$('.slot', c).forEach((el) => {
        el.addEventListener('dragstart', (e) => { from = +el.dataset.slot; e.dataTransfer.effectAllowed = 'move'; });
        el.addEventListener('dragover', (e) => { if (!el.classList.contains('locked')) { e.preventDefault(); el.classList.add('drag-over'); } });
        el.addEventListener('dragleave', () => el.classList.remove('drag-over'));
        el.addEventListener('drop', async (e) => {
            e.preventDefault(); el.classList.remove('drag-over');
            const to = +el.dataset.slot;
            if (from && to && from !== to) {
                const r = await req('invMove', from, to);
                if (!r.ok) toast(r.error, 'error');
                S.invSel = to;
                tabInventory(c);
            }
        });
    });
}

/* ===================== 入場画面 ===================== */
function renderEntry(info) {
    S.screen = 'entry';
    S.entry = info;
    const ev = info.event;
    const allOk = info.members.every((m) => m.ok);
    const isRaid = ev.type === 'raid';
    let action;
    if (isRaid) {
        action = ev.status === 'announced'
            ? (info.registered ? '<button class="btn btn-danger" data-act="raidUnreg">参加登録を取り消す</button>' : '<button class="btn btn-primary" data-act="raidReg">このレイドに参加登録する</button>')
            : '<span class="muted">登録受付は終了しました</span>';
    } else {
        action = ev.status === 'active'
            ? (info.isLeader ? `<button class="btn btn-primary" data-act="enter" ${allOk ? '' : 'disabled'}>入場する (${info.members.length}人)</button>` : '<span class="muted">リーダーが入場を開始するのを待っています</span>')
            : '<span class="muted">まだ開始されていません</span>';
    }
    show(`<div class="window">${winHead(isRaid ? '大型ボスレイド' : 'ダンジョン')}
      <div class="content">
        <div class="entry-head ${isRaid ? 'raid' : ''}"><span class="badge badge-${ev.type}">${isRaid ? '大型ボスレイド' : 'ダンジョン'}</span>
          <h1>${esc(ev.name)}</h1><div class="muted">📍 ${esc(ev.location)}　👥 ${ev.minPlayers}〜${ev.maxPlayers}人　⏱ 制限時間 ${fmtDur(ev.timeLimit)}　🌊 ${ev.waves}ウェーブ${ev.hasBoss ? '　👹 ボスあり' : ''}</div>
          <p style="margin-top:10px;line-height:1.7">${esc(ev.description)}</p>
          <div style="margin-top:8px;font-weight:800">${isRaid ? (ev.status === 'announced' ? `開始まで ${fmtDur(ev.startIn)} ／ 登録 ${ev.registered}/${ev.maxPlayers}人` : '戦闘中') : `${esc(ev.endLabel)}まで開催`}</div></div>
        <div class="sec-title">${isRaid ? '参加条件' : '入場メンバー'}</div>
        <div class="list">${info.members.map((m) => `<div class="member"><span class="${m.ok ? 'ok-mark' : 'ng-mark'}">${m.ok ? '✔' : '✖'}</span>
          <span class="nm">${esc(m.name)}</span><span style="color:${ROLE_COLORS[m.role] || '#888'};font-weight:700">${esc(m.roleLabel)}</span>
          <span class="small ${m.ok ? 'muted' : 'ng-mark'}" style="width:220px;text-align:right">${esc(m.ok ? '準備OK' : m.reason)}</span></div>`).join('')}</div>
        <div class="help" style="margin-top:14px">入場すると通常の所持品は一時的に預けられ、ロールに応じた貸与装備が支給されます。退出・死亡・切断・サーバー再起動時も所持品は自動で返却されます。</div>
        <div class="row" style="margin-top:6px"><div class="spacer"></div>${action}</div>
      </div></div>`);
}

/* ===================== 結果画面 ===================== */
let resultsTimer = null;
function renderResults(d) {
    S.screen = 'results';
    S.results = d;
    const me = d.players;
    const rewardsOf = (p) => p.rewards.length ? `<div class="reward-list">${p.rewards.map((r) => `<span class="reward">${esc(r.icon)} <span class="r-${r.rarity}">${esc(r.label)}</span> x${r.count}</span>`).join('')}</div>` : '<span class="muted small">なし</span>';
    show(`<div class="window">${winHead('リザルト')}
      <div class="content">
        <div class="muted" style="text-align:center">${esc(d.name)}${d.testMode ? ' (テストモード: 報酬は付与されません)' : ''}</div>
        <div class="result-title ${d.success ? 'win' : 'lose'}">${esc(d.resultLabel)}</div>
        <div style="text-align:center" class="muted">攻略時間 ${fmtTime(d.duration)}</div>
        <table class="tbl" style="margin-top:16px"><tr><th>プレイヤー</th><th>ロール</th><th>討伐</th><th>与ダメージ</th><th>回復量</th><th>ダウン</th><th>獲得アイテム</th></tr>
        ${me.map((p) => `<tr><td><b>${p.id === d.mvp ? '🏆 ' : ''}${esc(p.name)}</b></td><td style="color:${ROLE_COLORS[p.role]}">${esc(p.roleLabel)}</td>
          <td>${p.kills}</td><td>${p.damage.toLocaleString()}</td><td>${p.healing.toLocaleString()}</td><td>${p.downs}</td><td>${rewardsOf(p)}</td></tr>`).join('')}</table>
        <div class="row" style="margin-top:18px"><div class="spacer"></div><span class="muted" id="res-count"></span><button class="btn btn-primary" data-act="resultLeave">街へ帰還する</button></div>
      </div></div>`);
    let left = d.autoLeave || 45;
    clearInterval(resultsTimer);
    resultsTimer = setInterval(() => {
        left -= 1;
        const el = $('#res-count');
        if (el) el.textContent = `${left}秒後に自動で帰還します`;
        if (left <= 0) clearInterval(resultsTimer);
    }, 1000);
}

/* ===================== 管理 ===================== */
const AD = { sub: 'events', nowJst: '', defs: [], players: [] };

function jstParse(s) {
    const m = /^(\d{4})-(\d{1,2})-(\d{1,2}) (\d{1,2}):(\d{2})$/.exec(String(s || '').trim());
    if (!m) return null;
    return Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5]);
}
function jstFmt(ms) {
    const d = new Date(ms);
    const p = (n) => String(n).padStart(2, '0');
    return `${d.getUTCFullYear()}-${p(d.getUTCMonth() + 1)}-${p(d.getUTCDate())} ${p(d.getUTCHours())}:${p(d.getUTCMinutes())}`;
}
const jstAdd = (s, min) => { const t = jstParse(s); return t == null ? s : jstFmt(t + min * 60000); };
const jstToday24 = (s) => `${String(s).slice(0, 10)} 24:00`;

async function tabAdmin(c) {
    const subs = [['events', '📅 イベント予約'], ['editor', '🧩 ダンジョンエディター'], ['roles', '🎭 ロール管理'], ['runs', '⚔ 稼働中インスタンス'], ['logs', '📜 ログ']];
    c.innerHTML = `<div class="subtabs">${subs.map(([id, l]) => `<div class="subtab ${AD.sub === id ? 'active' : ''}" data-act="adSub" data-id="${id}">${l}</div>`).join('')}</div><div id="ad-body"><div class="muted">読み込み中…</div></div>`;
    const b = $('#ad-body');
    const nr = await admin('nowJst');
    AD.nowJst = nr.ok ? nr.data : '';
    if (AD.sub === 'events') return adEvents(b);
    if (AD.sub === 'editor') return adEditorList(b);
    if (AD.sub === 'roles') return adRoles(b);
    if (AD.sub === 'runs') return adRuns(b);
    if (AD.sub === 'logs') return adLogs(b);
}

async function adEvents(b) {
    const [dr, er] = await Promise.all([admin('defs'), admin('events')]);
    AD.defs = dr.ok ? dr.data : [];
    const pubs = AD.defs.filter((d) => d.status === 'published');
    const evs = er.ok ? er.data : [];
    const now = AD.nowJst;
    const statusLabel = { scheduled: ['予約済み', 'badge'], announced: ['告知中', 'badge-warn'], active: ['開催中', 'badge-ok'], ended: ['終了', 'badge'], cancelled: ['中止', 'badge-err'] };
    b.innerHTML = `<div class="grid2" style="align-items:start">
      <div class="card"><h3>新しいイベントを予約 (日本時間)</h3>
        <div class="list">
          <label class="f">ダンジョン / レイド (公開済みのみ)<select id="ev-def">${pubs.map((d) => `<option value="${d.id}" data-type="${d.type}">[${d.type === 'raid' ? 'レイド' : 'ダンジョン'}] ${esc(d.name)} v${d.version}</option>`).join('')}</select></label>
          <label class="f">場所の表示名 (告知の「XXX番地」部分)<input id="ev-loc" placeholder="例: 8012番地"></label>
          <label class="f">開始日時<div class="row"><input id="ev-start" value="${esc(now)}" style="flex:1"><button class="btn btn-sm" data-act="evQuick" data-t="start" data-v="0">今</button><button class="btn btn-sm" data-act="evQuick" data-t="start" data-v="30">+30分</button><button class="btn btn-sm" data-act="evQuick" data-t="start" data-v="60">+1時間</button></div></label>
          <label class="f" id="ev-end-wrap">終了日時 (ダンジョンのみ)<div class="row"><input id="ev-end" value="${esc(jstToday24(now))}" style="flex:1"><button class="btn btn-sm" data-act="evQuick" data-t="end" data-v="today24">本日24時</button><button class="btn btn-sm" data-act="evQuick" data-t="end" data-v="120">開始+2時間</button></div></label>
          <label class="f">告知日時 (空欄: ダンジョン=開始時 / レイド=開始30分前)<input id="ev-ann" placeholder="例: ${esc(now)}"></label>
          <label class="f">告知文 (空欄でテンプレート。{location} {end} {startIn} {start} {name} が使えます)<input id="ev-text" placeholder="例: {location}でダンジョン発生！{end}まで！"></label>
          <div class="row"><button class="btn" data-act="evPreview">告知をプレビュー</button><div class="spacer"></div><button class="btn btn-primary" data-act="evCreate">予約する</button></div>
          <div id="ev-preview"></div>
        </div></div>
      <div class="card"><h3>イベント一覧</h3><div class="list">${evs.length ? evs.map((e) => {
            const [sl, sc] = statusLabel[e.status] || [e.status, 'badge'];
            const live = ['scheduled', 'announced', 'active'].includes(e.status);
            return `<div class="item-box" style="margin:0"><div class="row"><span class="badge badge-${e.type}">${e.type === 'raid' ? 'レイド' : 'ダンジョン'}</span><b>${esc(e.name)}</b><span class="badge ${sc}">${sl}</span><div class="spacer"></div><span class="small muted">#${e.id}</span></div>
              <div class="small muted" style="margin-top:6px">📍 ${esc(e.location_label)}　告知 ${esc(e.announceJst)}<br>開始 ${esc(e.startJst)} 〜 終了 ${esc(e.endJst)}${e.type === 'raid' ? `　登録 ${e.registered}人` : ''}</div>
              ${live ? `<div class="row" style="margin-top:8px"><button class="btn btn-xs" data-act="evAnnounce" data-id="${e.id}">再告知</button><button class="btn btn-xs" data-act="evEnd" data-id="${e.id}">今すぐ終了</button><button class="btn btn-xs btn-danger" data-act="evCancel" data-id="${e.id}">中止</button></div>` : ''}</div>`;
        }).join('') : '<div class="empty">イベントはありません</div>'}</div></div></div>`;
    const sync = () => {
        const opt = $('#ev-def').selectedOptions[0];
        $('#ev-end-wrap').classList.toggle('hidden', !opt || opt.dataset.type === 'raid');
    };
    $('#ev-def') && $('#ev-def').addEventListener('change', sync);
    if ($('#ev-def')) sync();
}
function evForm() {
    const opt = $('#ev-def').selectedOptions[0];
    return {
        definitionId: opt ? +opt.value : null, type: opt ? opt.dataset.type : 'dungeon', name: opt ? opt.textContent.replace(/^\[.*?\] /, '').replace(/ v\d+$/, '') : '',
        location: $('#ev-loc').value.trim(), start: $('#ev-start').value.trim(), end: $('#ev-end').value.trim(),
        announce: $('#ev-ann').value.trim(), announcement: $('#ev-text').value.trim(),
    };
}

async function adEditorList(b) {
    const [dr, tr] = await Promise.all([admin('defs'), admin('templates', { kind: 'definition' })]);
    AD.defs = dr.ok ? dr.data : [];
    const tpls = tr.ok ? tr.data : [];
    const st = { draft: ['下書き', 'badge-warn'], published: ['公開中', 'badge-ok'] };
    b.innerHTML = `<div class="row" style="margin-bottom:12px"><button class="btn btn-primary" data-act="defNew" data-type="dungeon">＋ 新規ダンジョン</button><button class="btn btn-primary" data-act="defNew" data-type="raid">＋ 新規レイド</button>
        <div class="spacer"></div><select id="tpl-sel" style="width:280px">${tpls.map((t) => `<option value="${t.id}">${esc(t.name)}</option>`).join('')}</select><button class="btn" data-act="tplUse">テンプレートから作成</button><button class="btn btn-danger btn-sm" data-act="tplDel">テンプレート削除</button></div>
      <div class="list">${AD.defs.length ? AD.defs.map((d) => {
            const [sl, sc] = st[d.status] || [d.status, 'badge'];
            return `<div class="card"><div class="row"><span class="badge badge-${d.type}">${d.type === 'raid' ? 'レイド' : 'ダンジョン'}</span><b style="font-size:15px">${esc(d.name)}</b>
              <span class="badge ${sc}">${sl}${d.version ? ' v' + d.version : ''}</span>${d.hasUnpublished && d.status === 'published' ? '<span class="badge badge-warn">未公開の変更あり</span>' : ''}
              ${d.valid ? '<span class="small valid-ok">✔ 公開可能</span>' : `<span class="small valid-ng">⚠ ${esc(d.error)}</span>`}
              <div class="spacer"></div><span class="small muted">${d.summary.waves || 0}ウェーブ / 敵${d.summary.enemies || 0}体${d.summary.hasBoss ? ' / ボス' : ''}</span></div>
              <div class="row" style="margin-top:10px"><button class="btn btn-sm btn-primary" data-act="defEdit" data-id="${d.id}">編集</button><button class="btn btn-sm" data-act="defDup" data-id="${d.id}">複製</button>
                <button class="btn btn-sm" data-act="defPublish" data-id="${d.id}" ${d.valid ? '' : 'disabled'}>公開</button><div class="spacer"></div><button class="btn btn-sm btn-danger" data-act="defArchive" data-id="${d.id}">アーカイブ</button></div></div>`;
        }).join('') : '<div class="empty">定義がありません</div>'}</div>`;
}

async function adRoles(b) {
    const r = await admin('players');
    AD.players = r.ok ? r.data : [];
    const roleOpts = (cur) => `<option value="">(未選択にリセット)</option>${S.profile.roles.map((x) => `<option value="${x.id}" ${cur === x.id ? 'selected' : ''}>${esc(x.label)}</option>`).join('')}`;
    b.innerHTML = `<div class="help">ロールはプレイヤー自身が一度だけ選択できます。ここでは管理者が変更・リセットできます(全て監査ログに記録)。ダンジョン参加中のキャラクターは変更できません。</div>
      <div class="card" style="margin-bottom:12px"><h3>CitizenIDで検索 (オフライン可)</h3><div class="row"><input id="cid-in" placeholder="例: ABC12345" style="width:240px"><button class="btn" data-act="cidLookup">検索</button></div><div id="cid-res" style="margin-top:10px"></div></div>
      <table class="tbl"><tr><th>ID</th><th>名前</th><th>CitizenID</th><th>現在のロール</th><th>状態</th><th>変更</th></tr>
      ${AD.players.map((p) => `<tr><td>${p.id}</td><td>${esc(p.name)}</td><td class="coord">${esc(p.cid)}</td><td style="color:${ROLE_COLORS[p.role] || '#888'}">${esc(p.roleLabel)}</td><td class="small">${p.inRun ? '⚔ ' + esc(p.inRun) : '—'}</td>
        <td><div class="row"><select style="width:150px" id="role-${esc(p.cid)}">${roleOpts(p.role)}</select><button class="btn btn-sm" data-act="setRole" data-cid="${esc(p.cid)}">変更</button></div></td></tr>`).join('')}</table>`;
}

async function adRuns(b) {
    const r = await admin('runs');
    const runs = r.ok ? r.data : [];
    b.innerHTML = `<div class="row" style="margin-bottom:10px"><button class="btn btn-sm" data-act="adSub" data-id="runs">🔄 更新</button></div>
      ${runs.length ? `<table class="tbl"><tr><th>名前</th><th>状態</th><th>ウェーブ</th><th>メンバー</th><th>敵</th><th>残り</th><th>バケット</th><th></th></tr>
      ${runs.map((x) => `<tr><td>${esc(x.name)}${x.test ? ' <span class="badge badge-warn">テスト</span>' : ''}</td><td>${esc(x.state)}</td><td>${x.wave}/${x.waves}</td><td class="small">${x.members.map(esc).join('<br>')}</td><td>${x.enemies}</td><td>${fmtTime(x.timeLeft)}</td><td>${x.bucket}</td>
        <td><button class="btn btn-xs btn-danger" data-act="runEnd" data-id="${esc(x.id)}">強制終了</button></td></tr>`).join('')}</table>` : '<div class="empty">稼働中のインスタンスはありません</div>'}`;
}

async function adLogs(b) {
    const r = await admin('logs');
    const logs = r.ok ? r.data : [];
    b.innerHTML = `<table class="tbl"><tr><th>#</th><th>日時</th><th>実行者</th><th>操作</th><th>詳細</th></tr>${logs.map((l) => `<tr><td>${l.id}</td><td class="small">${esc(l.created_at)}</td><td class="coord">${esc(l.actor || '-')}</td><td>${esc(l.action)}</td><td class="small muted" style="max-width:520px;word-break:break-all">${esc(l.detail || '')}</td></tr>`).join('')}</table>`;
}

/* ===================== エディター ===================== */
const ED = { id: null, data: null, status: '', version: 0, section: 'basic', dirty: false, preview: false, items: [], enemyTpls: [], valid: null, tokens: {} };
const WEAPONS = ['WEAPON_UNARMED', 'WEAPON_KNIFE', 'WEAPON_BAT', 'WEAPON_MACHETE', 'WEAPON_PISTOL', 'WEAPON_COMBATPISTOL', 'WEAPON_MICROSMG', 'WEAPON_SMG', 'WEAPON_ASSAULTRIFLE', 'WEAPON_CARBINERIFLE', 'WEAPON_PUMPSHOTGUN', 'WEAPON_MG', 'WEAPON_COMBATMG'];
const OBJ_TYPES = { kill_all: '敵を全滅させる', kill_count: '指定数の敵を倒す', interact: '対象を破壊/起動する', survive: '一定時間生き残る', boss: 'ボスを討伐する' };
const ANN_KEYS = { dungeon_open: 'ダンジョン発生時', dungeon_reminder: 'ダンジョン終了前', raid_announce: 'レイド告知時', raid_reminder: 'レイド開始前リマインド', raid_start: 'レイド開始時' };
const ED_SECTIONS = [['basic', '📝 基本情報'], ['location', '📍 配置・境界'], ['enemies', '👾 敵プリセット'], ['spawns', '🚩 スポーン地点'], ['props', '📦 プロップ'], ['waves', '🌊 ウェーブ'], ['boss', '👹 ボス'], ['rewards', '🎁 報酬'], ['announce', '📢 告知文'], ['publish', '✅ 検証・テスト・公開']];

function getPath(o, path) { return path.split('.').reduce((a, k) => (a == null ? undefined : a[k]), o); }
function setPath(o, path, v) {
    const ks = path.split('.');
    let cur = o;
    for (let i = 0; i < ks.length - 1; i++) {
        const k = ks[i];
        if (cur[k] == null || typeof cur[k] !== 'object') cur[k] = /^\d+$/.test(ks[i + 1]) ? [] : {};
        cur = cur[k];
    }
    cur[ks[ks.length - 1]] = v;
}
function delPath(o, path) {
    const ks = path.split('.');
    const last = ks.pop();
    const parent = ks.length ? getPath(o, ks.join('.')) : o;
    if (Array.isArray(parent)) parent.splice(+last, 1); else if (parent) delete parent[last];
}
const r3 = (n) => Math.round((+n || 0) * 1000) / 1000;

function inp(path, type = 'str', attrs = '') {
    const v = getPath(ED.data, path);
    if (type === 'bool') return `<input type="checkbox" data-bind="${path}" data-type="bool" ${v ? 'checked' : ''} ${attrs}>`;
    if (type === 'text') return `<textarea data-bind="${path}" data-type="str" ${attrs}>${esc(v ?? '')}</textarea>`;
    if (type === 'min') return `<input type="number" data-bind="${path}" data-type="min" value="${v != null ? Math.round(v / 60) : ''}" ${attrs}>`;
    if (type === 'csv') return `<input data-bind="${path}" data-type="csv" value="${esc((v || []).join(', '))}" ${attrs}>`;
    const t = (type === 'num' || type === 'int') ? 'number' : 'text';
    return `<input type="${t}" data-bind="${path}" data-type="${type}" value="${esc(v ?? '')}" ${attrs}>`;
}
function sel(path, options, attrs = '') {
    const v = getPath(ED.data, path);
    return `<select data-bind="${path}" data-type="str" ${attrs}>${options.map(([val, label]) => `<option value="${esc(val)}" ${String(v) === String(val) ? 'selected' : ''}>${esc(label)}</option>`).join('')}</select>`;
}
function fld(label, control) { return `<label class="f">${esc(label)}${control}</label>`; }
function coordCtl(path, label, kind = 'point', model = '') {
    const c = getPath(ED.data, path);
    const txt = c && c.x != null ? `X ${(+c.x).toFixed(2)}  Y ${(+c.y).toFixed(2)}  Z ${(+c.z).toFixed(2)}${c.h != null ? `  H ${(+c.h).toFixed(1)}°` : ''}` : '未設定';
    return `<div class="row"><span class="coord" style="min-width:330px">${txt}</span>
        <button class="btn btn-xs" data-act="edHere" data-path="${path}">現在地</button>
        <button class="btn btn-xs btn-primary" data-act="edPlace" data-path="${path}" data-kind="${kind}" data-model="${esc(model)}" data-label="${esc(label)}">配置モード</button>
        ${c && c.x != null ? `<button class="btn btn-xs" data-act="edTp" data-path="${path}">TP</button>` : ''}</div>`;
}
function enemyOpts() { return Object.entries(ED.data.enemies || {}).map(([k, e]) => [k, `${e.label || k} (${k})`]); }
function spawnChips(path) {
    const cur = getPath(ED.data, path) || [];
    const sps = ED.data.spawnPoints || [];
    if (!sps.length) return '<span class="small muted">スポーン地点がありません</span>';
    return `<div class="chips">${sps.map((s) => `<span class="chip ${cur.includes(s.id) ? 'on' : ''}" data-act="chip" data-path="${path}" data-val="${esc(s.id)}">${esc(s.label || s.id)}</span>`).join('')}</div>`;
}
function lootEditor(path) {
    const list = getPath(ED.data, path) || [];
    return `<div class="list">${list.map((r, i) => `<div class="row">
        <select data-bind="${path}.${i}.item" data-type="str" style="width:200px">${ED.items.map((it) => `<option value="${it.id}" ${r.item === it.id ? 'selected' : ''}>${esc(it.icon)} ${esc(it.label)}</option>`).join('')}</select>
        <span class="small muted">個数</span>${inp(`${path}.${i}.min`, 'int', 'style="width:70px"')}<span>〜</span>${inp(`${path}.${i}.max`, 'int', 'style="width:70px"')}
        <span class="small muted">確率%</span>${inp(`${path}.${i}.chance`, 'num', 'style="width:80px"')}
        <button class="btn btn-xs btn-danger" data-act="edDel" data-path="${path}.${i}">削除</button></div>`).join('')}
        <div><button class="btn btn-xs" data-act="edAddLoot" data-path="${path}">＋ アイテム追加</button></div></div>`;
}
function uid(prefix, existing) { let i = 1; while (existing.includes(`${prefix}${i}`)) i++; return `${prefix}${i}`; }

async function openEditor(id) {
    const [r, ir, tr] = await Promise.all([admin('defGet', { id }), admin('items'), admin('templates', { kind: 'enemy' })]);
    if (!r.ok || !r.data) return toast(r.error || '読み込めません', 'error');
    ED.id = r.data.id; ED.status = r.data.status; ED.version = r.data.version;
    ED.data = r.data.data || {};
    const d = ED.data;
    d.enemies = d.enemies && !Array.isArray(d.enemies) ? d.enemies : {};
    ['spawnPoints', 'props', 'waves', 'ipls'].forEach((k) => { if (!Array.isArray(d[k])) d[k] = []; });
    d.boundary = d.boundary || { radius: 80, height: 60 };
    d.rewards = d.rewards || { clear: [] };
    if (!Array.isArray(d.rewards.clear)) d.rewards.clear = [];
    d.announcements = d.announcements || {};
    ED.items = ir.ok ? ir.data : [];
    ED.enemyTpls = tr.ok ? tr.data : [];
    ED.section = 'basic'; ED.dirty = false; ED.valid = null;
    renderEditor();
}

function renderEditor() {
    S.screen = 'editor';
    const d = ED.data;
    show(`<div class="window wide">
      <div class="win-head"><div class="win-logo">🧩 エディター</div><b>${esc(d.name || '無題')}</b><span class="badge badge-${d.type}">${d.type === 'raid' ? 'レイド' : 'ダンジョン'}</span>
        <span class="badge ${ED.status === 'published' ? 'badge-ok' : 'badge-warn'}">${ED.status === 'published' ? '公開中 v' + ED.version : '下書き'}</span>
        <span id="ed-dirty" class="small valid-ng ${ED.dirty ? '' : 'hidden'}">● 未保存</span>
        <button class="win-close" data-act="edBack" title="一覧へ戻る">←</button></div>
      <div class="ed-bar"><button class="btn btn-primary btn-sm" data-act="edSave">💾 下書き保存</button><button class="btn btn-sm" data-act="edValidate">🔍 検証</button>
        <button class="btn btn-sm" data-act="edPreview">${ED.preview ? '🙈 プレビュー非表示' : '👁 ワールドにプレビュー'}</button>
        <button class="btn btn-sm" data-act="edSaveTpl">📑 テンプレートとして保存</button>
        <div class="spacer"></div><button class="btn btn-sm" data-act="edGoTest">🧪 テストプレイ</button><button class="btn btn-sm btn-ok" data-act="edPublish">🚀 公開</button></div>
      <div class="ed" style="height:calc(100% - 110px)"><div class="ed-nav">${ED_SECTIONS.map(([id, l]) => `<div class="tab ${ED.section === id ? 'active' : ''}" data-act="edSec" data-id="${id}">${l}</div>`).join('')}</div>
        <div class="ed-main" id="ed-main"></div></div></div>`);
    renderSection();
}
function markDirty() { ED.dirty = true; const el = $('#ed-dirty'); if (el) el.classList.remove('hidden'); if (ED.preview) post('editorPreview', { data: ED.data }); }

function renderSection() {
    const m = $('#ed-main');
    if (!m) return;
    const d = ED.data;
    const keep = m.scrollTop;
    const S2 = {
        basic: () => `<div class="help">名前・種類・人数・制限時間などの基本設定です。</div>
          <div class="grid2">${fld('名前', inp('name'))}${fld('種類', sel('type', [['dungeon', 'ダンジョン (パーティー 1〜4人)'], ['raid', '大型ボスレイド (最大24人)']]))}</div>
          ${fld('説明文', inp('description', 'text'))}
          <div class="grid4" style="margin-top:10px">${fld('最少人数', inp('minPlayers', 'int'))}${fld('最大人数', inp('maxPlayers', 'int'))}${fld('制限時間 (分)', inp('timeLimit', 'min'))}${fld('推奨 (表示用)', inp('recommended'))}</div>
          <div class="grid2" style="margin-top:10px">${fld('既定の場所名 (告知用)', inp('locationLabel'))}${fld('読み込むIPL (MLO/インテリア用・カンマ区切り)', inp('ipls', 'csv'))}</div>`,
        location: () => `<div class="help">「配置モード」でカメラの照準先をクリック/Eで設定、「現在地」で自分の立ち位置を設定します。インスタンスはパーティーごとに別空間(ルーティングバケット)なので、街と同じ場所でも干渉しません。</div>
          <div class="item-box"><div class="box-head">🚪 入口 (街側のマーカー位置)</div>${coordCtl('entry', '入口')}</div>
          <div class="item-box"><div class="box-head">🟢 開始地点 (インスタンス内)</div>${coordCtl('start', '開始地点')}</div>
          <div class="item-box"><div class="box-head">🏠 帰還地点 (空欄なら入口)</div>${coordCtl('exit', '帰還地点')}${d.exit ? '<button class="btn btn-xs btn-danger" data-act="edDel" data-path="exit">クリア</button>' : ''}</div>
          <div class="item-box"><div class="box-head">🔵 境界 (この範囲外に出ると警告→開始地点へ戻されます)</div>${coordCtl('boundary.center', '境界中心')}
            <div class="grid3" style="margin-top:8px">${fld('半径 (m)', inp('boundary.radius', 'num'))}${fld('高さ (m)', inp('boundary.height', 'num'))}<div></div></div></div>`,
        enemies: () => `<div class="help">ウェーブやボスで使う敵の種類(プリセット)です。モデル名はGTAのPedモデル名 (例: g_m_y_lost_01, s_m_y_blackops_01, u_m_y_zombie_01)。HPはサーバー側で管理され、人数に応じて自動で補正されます。</div>
          <div class="row" style="margin-bottom:10px"><button class="btn btn-sm btn-primary" data-act="edAddEnemy">＋ 敵を追加</button>
            <select id="etpl" style="width:240px">${ED.enemyTpls.map((t) => `<option value="${t.id}">${esc(t.name)}</option>`).join('')}</select><button class="btn btn-sm" data-act="edAddEnemyTpl">テンプレートから追加</button></div>
          ${Object.entries(d.enemies).map(([k, e]) => `<div class="item-box"><div class="box-head">${e.isBoss ? '👹' : '👾'} ${esc(e.label || k)} <span class="small muted">ID: ${esc(k)}</span><div class="spacer"></div>
              <button class="btn btn-xs" data-act="edEnemyTpl" data-key="${esc(k)}">テンプレート保存</button><button class="btn btn-xs btn-danger" data-act="edDel" data-path="enemies.${esc(k)}">削除</button></div>
            <div class="grid4">${fld('表示名', inp(`enemies.${k}.label`))}${fld('モデル名', inp(`enemies.${k}.model`, 'str', `data-check-model="1"`))}${fld('HP', inp(`enemies.${k}.hp`, 'int'))}${fld('武器', sel(`enemies.${k}.weapon`, WEAPONS.map((w) => [w, w.replace('WEAPON_', '')])))}
              ${fld('命中率 (0-100)', inp(`enemies.${k}.accuracy`, 'int'))}${fld('アーマー (0-100)', inp(`enemies.${k}.armor`, 'int'))}${fld('ダメージ軽減 (0〜0.9)', inp(`enemies.${k}.damageReduction`, 'num'))}<label class="chk" style="margin-top:20px">${inp(`enemies.${k}.isBoss`, 'bool')} ボス扱い</label></div>
            <div class="sec-title">ドロップ (メンバーごとに個別抽選)</div>${lootEditor(`enemies.${k}.loot`)}</div>`).join('') || '<div class="empty">敵がいません</div>'}`,
        spawns: () => `<div class="help">敵が出現する地点です。ウェーブの各グループで使用する地点を選びます。</div>
          <div class="row" style="margin-bottom:10px"><button class="btn btn-sm btn-primary" data-act="edAddSpawn" data-mode="place">＋ 配置モードで追加</button><button class="btn btn-sm" data-act="edAddSpawn" data-mode="here">＋ 現在地に追加</button></div>
          ${d.spawnPoints.map((s, i) => `<div class="item-box"><div class="box-head">🚩 ${esc(s.label || s.id)} <span class="small muted">ID: ${esc(s.id)}</span><div class="spacer"></div><button class="btn btn-xs btn-danger" data-act="edDel" data-path="spawnPoints.${i}">削除</button></div>
            <div class="grid2">${fld('名前', inp(`spawnPoints.${i}.label`))}<div></div></div><div style="margin-top:8px">${coordCtl(`spawnPoints.${i}`, s.label || s.id, 'ped', 'g_m_y_lost_01')}</div></div>`).join('') || '<div class="empty">スポーン地点がありません</div>'}`,
        props: () => `<div class="help">インスタンス内に設置する小道具です。「対象を破壊/起動する」目標のターゲットにもなります (例: prop_rad_waste_barrel_01, prop_worklight_03b, prop_barrier_work05)。</div>
          <div class="row" style="margin-bottom:10px"><input id="prop-model" placeholder="モデル名" value="prop_rad_waste_barrel_01" style="width:260px"><button class="btn btn-sm btn-primary" data-act="edAddProp">＋ 配置モードで追加</button></div>
          ${d.props.map((p, i) => `<div class="item-box"><div class="box-head">📦 ${esc(p.label || p.id)} <span class="small muted">ID: ${esc(p.id)}</span><div class="spacer"></div><button class="btn btn-xs btn-danger" data-act="edDel" data-path="props.${i}">削除</button></div>
            <div class="grid2">${fld('名前', inp(`props.${i}.label`))}${fld('モデル名', inp(`props.${i}.model`, 'str', 'data-check-model="1"'))}</div><div style="margin-top:8px">${coordCtl(`props.${i}`, p.label || p.id, 'prop', p.model)}</div></div>`).join('') || '<div class="empty">プロップはありません</div>'}`,
        waves: () => `<div class="help">ウェーブは上から順に進行します。各ウェーブの目標を達成すると次へ。最後のウェーブをクリアするとダンジョンクリアです。</div>
          ${d.waves.map((w, i) => {
              const o = w.objective || {};
              let extra = '';
              if (o.type === 'kill_count') extra = fld('討伐数', inp(`waves.${i}.objective.count`, 'int'));
              if (o.type === 'survive') extra = fld('生存時間 (秒)', inp(`waves.${i}.objective.duration`, 'int'));
              if (o.type === 'interact') extra = `${fld('目標の表示名', inp(`waves.${i}.objective.label`))}${fld('長押し秒数', inp(`waves.${i}.objective.interactTime`, 'num'))}
                  <div style="grid-column: span 2"><div class="small muted">対象プロップ</div><div class="chips">${d.props.map((p) => `<span class="chip ${(o.targets || []).includes(p.id) ? 'on' : ''}" data-act="chip" data-path="waves.${i}.objective.targets" data-val="${esc(p.id)}">${esc(p.label || p.id)}</span>`).join('') || '<span class="small muted">プロップがありません</span>'}</div></div>`;
              return `<div class="item-box"><div class="box-head">🌊 ${i + 1}. ${esc(w.label || '')}<div class="spacer"></div>
                <button class="btn btn-xs" data-act="edMove" data-path="waves" data-i="${i}" data-d="-1">▲</button><button class="btn btn-xs" data-act="edMove" data-path="waves" data-i="${i}" data-d="1">▼</button>
                <button class="btn btn-xs" data-act="edDupWave" data-i="${i}">複製</button><button class="btn btn-xs btn-danger" data-act="edDel" data-path="waves.${i}">削除</button></div>
                <div class="grid4">${fld('名前', inp(`waves.${i}.label`))}${fld('開始前の待機 (秒)', inp(`waves.${i}.delay`, 'num'))}${fld('目標', sel(`waves.${i}.objective.type`, Object.entries(OBJ_TYPES)))}${extra}</div>
                ${fld('開始メッセージ', inp(`waves.${i}.message`))}
                <div class="sec-title">敵グループ</div>
                ${(w.groups || []).map((g, gi) => `<div class="row" style="margin-bottom:6px;align-items:flex-start;background:rgba(0,0,0,.2);padding:8px;border-radius:9px">
                    <div style="width:220px">${sel(`waves.${i}.groups.${gi}.enemy`, enemyOpts())}</div><span class="small muted">数</span>${inp(`waves.${i}.groups.${gi}.count`, 'int', 'style="width:70px"')}
                    <label class="chk small">${inp(`waves.${i}.groups.${gi}.respawn`, 'bool')} 倒すと再出現</label>
                    <div style="flex:1;min-width:200px">${spawnChips(`waves.${i}.groups.${gi}.spawn`)}</div>
                    <button class="btn btn-xs btn-danger" data-act="edDel" data-path="waves.${i}.groups.${gi}">×</button></div>`).join('')}
                <button class="btn btn-xs" data-act="edAddGroup" data-i="${i}">＋ 敵グループ追加</button></div>`;
          }).join('')}
          <button class="btn btn-primary btn-sm" data-act="edAddWave">＋ ウェーブ追加</button>`,
        boss: () => {
            if (!d.boss) return `<div class="empty">ボスは設定されていません<div style="margin-top:10px"><button class="btn btn-primary" data-act="edBossOn">ボスを設定する</button></div></div>`;
            return `<div class="help">「ボスを討伐する」目標のウェーブで出現します。フェーズはボスのHP割合がしきい値を下回ると移行します (100% = 開始時)。範囲攻撃は地面に赤い円で予告されます。</div>
              <div class="item-box"><div class="grid3">${fld('ボスの敵プリセット', sel('boss.enemy', enemyOpts()))}${fld('出現地点', sel('boss.spawn', (d.spawnPoints || []).map((s) => [s.id, s.label || s.id])))}<div style="padding-top:18px"><button class="btn btn-xs btn-danger" data-act="edBossOff">ボスを削除</button></div></div></div>
              ${(d.boss.phases || []).map((p, i) => `<div class="item-box"><div class="box-head">👹 フェーズ ${i + 1}: ${esc(p.label || '')}<div class="spacer"></div><button class="btn btn-xs btn-danger" data-act="edDel" data-path="boss.phases.${i}">削除</button></div>
                <div class="grid4">${fld('開始HP% (以下で移行)', inp(`boss.phases.${i}.hpPct`, 'int'))}${fld('フェーズ名', inp(`boss.phases.${i}.label`))}${fld('被ダメージ倍率', inp(`boss.phases.${i}.damageTakenMult`, 'num'))}${fld('命中率 (空欄=変更なし)', inp(`boss.phases.${i}.accuracy`, 'int'))}</div>
                ${fld('移行時メッセージ', inp(`boss.phases.${i}.message`))}
                <div class="grid2" style="margin-top:8px">
                  <div class="card"><label class="chk">${`<input type="checkbox" data-act="edToggleObj" data-path="boss.phases.${i}.aoe" ${p.aoe ? 'checked' : ''}>`} 範囲攻撃</label>
                    ${p.aoe ? `<div class="grid2" style="margin-top:8px">${fld('間隔 (秒)', inp(`boss.phases.${i}.aoe.interval`, 'num'))}${fld('半径 (m)', inp(`boss.phases.${i}.aoe.radius`, 'num'))}${fld('予告時間 (秒)', inp(`boss.phases.${i}.aoe.delay`, 'num'))}${fld('ダメージ (基準HP比 0〜1)', inp(`boss.phases.${i}.aoe.damagePct`, 'num'))}</div>` : ''}</div>
                  <div class="card"><label class="chk">${`<input type="checkbox" data-act="edToggleObj" data-path="boss.phases.${i}.adds" ${p.adds ? 'checked' : ''}>`} 増援召喚 (フェーズ開始時)</label>
                    ${p.adds ? `<div class="grid2" style="margin-top:8px">${fld('敵', sel(`boss.phases.${i}.adds.enemy`, enemyOpts()))}${fld('数', inp(`boss.phases.${i}.adds.count`, 'int'))}</div><div style="margin-top:6px">${spawnChips(`boss.phases.${i}.adds.spawn`)}</div>` : ''}</div></div></div>`).join('')}
              <button class="btn btn-primary btn-sm" data-act="edAddPhase">＋ フェーズ追加</button>`;
        },
        rewards: () => `<div class="help">クリア時に参加者全員へ個別に抽選されます。RPGインベントリに直接入り、容量不足分は「受取箱」に保管されます。報酬はUNIQUE制約付きの請求キーで二重付与を防止しています。</div>
          <div class="item-box"><div class="box-head">🎁 クリア報酬</div>${lootEditor('rewards.clear')}</div>`,
        announce: () => `<div class="help">告知文のテンプレートです。<b>{location}</b>=場所名 <b>{end}</b>=終了時刻(例: 本日24時) <b>{startIn}</b>=開始までの時間(例: 30分) <b>{start}</b>=開始時刻 <b>{name}</b>=名前。空欄なら既定文。</div>
          ${Object.entries(ANN_KEYS).filter(([k]) => d.type === 'raid' ? k.startsWith('raid') : k.startsWith('dungeon')).map(([k, l]) => fld(l, inp(`announcements.${k}`, 'str', 'placeholder="(既定)"'))).join('')}
          <div class="row" style="margin-top:10px"><input id="ann-loc" placeholder="プレビュー用の場所名" value="${esc(d.locationLabel || 'XXX番地')}" style="width:220px"><button class="btn btn-sm" data-act="edAnnPreview">プレビュー</button></div><div id="ann-prev" style="margin-top:10px"></div>`,
        publish: () => `<div class="help">「検証」で公開可能かチェックできます。テストプレイはあなた一人だけの非公開インスタンスで行われ、報酬は付与されません (下書きの内容でテストされます)。公開すると以後のイベントで使われます (実行中のインスタンスには影響しません)。</div>
          <div class="item-box"><div class="box-head">🔍 検証結果</div><div id="valid-res">${ED.valid ? (ED.valid.ok ? `<span class="valid-ok">✔ 公開可能です (${ED.valid.summary.waves}ウェーブ / 敵${ED.valid.summary.enemies}体${ED.valid.summary.hasBoss ? ' / ボスあり' : ''})</span>` : `<span class="valid-ng">⚠ ${esc(ED.valid.error)}</span>`) : '<span class="muted">未検証</span>'}</div>
            <div class="row" style="margin-top:8px"><button class="btn btn-sm" data-act="edValidate">検証する</button></div></div>
          <div class="item-box"><div class="box-head">🧪 テストプレイ (非公開)</div><div class="row"><span class="small muted">テスト時のロール</span><select id="test-role" style="width:180px">${S.profile.roles.map((r) => `<option value="${r.id}" ${S.profile.role === r.id ? 'selected' : ''}>${esc(r.label)}</option>`).join('')}</select>
            <button class="btn btn-primary btn-sm" data-act="edTest">保存してテスト開始</button></div></div>
          <div class="item-box"><div class="box-head">🚀 公開</div><div class="row"><button class="btn btn-ok" data-act="edPublish">保存して公開する</button><button class="btn" data-act="edDuplicate">この定義を複製</button></div></div>`,
    };
    m.innerHTML = (S2[ED.section] || S2.basic)();
    m.scrollTop = keep;
}

function bindValue(el) {
    const path = el.dataset.bind;
    const t = el.dataset.type;
    let v;
    if (t === 'bool') v = el.checked;
    else if (t === 'num') v = el.value === '' ? null : parseFloat(el.value);
    else if (t === 'int') v = el.value === '' ? null : parseInt(el.value, 10);
    else if (t === 'min') v = el.value === '' ? null : Math.round(parseFloat(el.value) * 60);
    else if (t === 'csv') v = el.value.split(',').map((s) => s.trim()).filter(Boolean);
    else v = el.value;
    if (v === null || (typeof v === 'number' && isNaN(v))) delPath(ED.data, path); else setPath(ED.data, path, v);
    markDirty();
}

async function placeTo(path, kind, label, model) {
    const token = `t${Date.now()}${Math.random().toString(16).slice(2)}`;
    $('#app').classList.add('hidden');
    const res = await new Promise((resolve) => { ED.tokens[token] = resolve; post('editorPlace', { token, kind, label, model }); });
    $('#app').classList.remove('hidden');
    if (!res) return false;
    const cur = getPath(ED.data, path) || {};
    setPath(ED.data, path, Object.assign(cur, { x: r3(res.x), y: r3(res.y), z: r3(res.z), h: Math.round((res.h || 0) * 10) / 10 }));
    markDirty();
    renderSection();
    return true;
}
async function hereTo(path) {
    const c = await post('editorCurrentPos');
    if (!c) return;
    const cur = getPath(ED.data, path) || {};
    setPath(ED.data, path, Object.assign(cur, { x: r3(c.x), y: r3(c.y), z: r3(c.z), h: Math.round(c.h * 10) / 10 }));
    markDirty();
    renderSection();
}
async function edSave(silent) {
    const r = await admin('defSave', { id: ED.id, data: ED.data });
    if (!r.ok) { toast(r.error, 'error'); return false; }
    ED.dirty = false;
    const el = $('#ed-dirty'); if (el) el.classList.add('hidden');
    if (!silent) toast(r.data && r.data !== true ? `下書きを保存しました (未完成: ${r.data})` : '下書きを保存しました', r.data && r.data !== true ? 'warning' : 'success');
    return true;
}

/* ===================== アクション ===================== */
const ACTIONS = {
    close: () => closeUI(),
    tab: (el) => { S.tab = el.dataset.id; renderHub(S.tab); },
    gps: (el) => post('setWaypoint', { id: +el.dataset.id }),
    pickRole: (el) => renderRole(el.dataset.id),
    confirmRole: async () => {
        const role = S.profile.roles.find((r) => r.id === S.roleSel);
        if (!role) return;
        if (!(await confirmBox('ロールの確定', `「${role.label}」に決定します。\nこの選択は後から自分で変更できません(管理者のみ変更可能)。よろしいですか？`, '決定する'))) return;
        if (await act(req('chooseRole', role.id), `ロール「${role.label}」に決定しました！`)) { await reloadProfile(); renderHub('home'); }
    },
    leaveRun: async () => {
        if (!(await confirmBox('離脱の確認', 'ダンジョンから離脱しますか？クリア報酬は受け取れません。', '離脱する', true))) return;
        closeUI();
        req('leaveRun');
    },
    partyCreate: async () => { await act(req('party', 'create')); renderTab(); },
    partyInvite: async (el) => { await act(req('party', 'invite', +el.dataset.id)); },
    partyInviteId: async () => { const id = +$('#invite-id').value; if (id) await act(req('party', 'invite', id)); },
    partyAccept: async (el) => { await act(req('party', 'accept', +el.dataset.id)); renderTab(); },
    partyDecline: async (el) => { await req('party', 'decline', +el.dataset.id); renderTab(); },
    partyLeave: async () => { await act(req('party', 'leave')); renderTab(); },
    partyKick: async (el) => { if (await confirmBox('キック', 'このメンバーをパーティーから外しますか？', 'キック', true)) { await act(req('party', 'kick', +el.dataset.id)); renderTab(); } },
    partyPromote: async (el) => { await act(req('party', 'promote', +el.dataset.id)); renderTab(); },
    invSel: (el) => { if (el.classList.contains('locked')) return; S.invSel = +el.dataset.slot; tabInventory($('#tab-content')); },
    invUse: async (el) => { await act(req('invUse', +el.dataset.slot)); tabInventory($('#tab-content')); },
    invDiscard: async (el) => {
        const n = +$('#discard-n').value || 1;
        if (!(await confirmBox('アイテムを捨てる', `${n}個捨てます。元に戻せません。`, '捨てる', true))) return;
        await act(req('invDiscard', +el.dataset.slot, n)); tabInventory($('#tab-content'));
    },
    invOverflow: async () => { await act(req('invClaimOverflow'), '受け取りました'); tabInventory($('#tab-content')); },
    enter: async () => {
        const r = await act(req('enterDungeon', S.entry.event.id));
        if (r) closeUI();
    },
    raidReg: async () => { if (await act(req('raidRegister', S.entry.event.id, false))) { const r = await req('entryCheck', S.entry.event.id); if (r.ok) renderEntry(r.data); } },
    raidUnreg: async () => { if (await act(req('raidRegister', S.entry.event.id, true))) { const r = await req('entryCheck', S.entry.event.id); if (r.ok) renderEntry(r.data); } },
    resultLeave: () => { clearInterval(resultsTimer); $('#app').classList.add('hidden'); S.screen = null; post('leaveRun'); },

    /* --- 管理 --- */
    adSub: (el) => { AD.sub = el.dataset.id; tabAdmin($('#tab-content')); },
    evQuick: (el) => {
        const t = el.dataset.t, v = el.dataset.v;
        if (t === 'start') $('#ev-start').value = jstAdd(AD.nowJst, +v);
        else if (v === 'today24') $('#ev-end').value = jstToday24($('#ev-start').value || AD.nowJst);
        else $('#ev-end').value = jstAdd($('#ev-start').value, +v);
    },
    evPreview: async () => {
        const f = evForm();
        const def = AD.defs.find((d) => d.id === f.definitionId);
        const r = await admin('preview', Object.assign({}, f, { type: def ? def.type : f.type }));
        $('#ev-preview').innerHTML = r.ok ? r.data.map((p) => `<div class="small muted">${esc(p.at)} 時点</div><div class="preview-ann">${esc(p.text)}</div>`).join('') : esc(r.error);
    },
    evCreate: async () => {
        const f = evForm();
        if (!f.definitionId) return toast('公開済みの定義を選択してください', 'error');
        if (await act(admin('eventCreate', f), 'イベントを予約しました')) tabAdmin($('#tab-content'));
    },
    evCancel: async (el) => { if (await confirmBox('イベント中止', '中止を全体に告知します。よろしいですか？', '中止する', true)) { await act(admin('eventCancel', { id: +el.dataset.id })); tabAdmin($('#tab-content')); } },
    evEnd: async (el) => { if (await confirmBox('今すぐ終了', '新規入場を締め切ります(実行中のインスタンスは継続)。', '終了する', true)) { await act(admin('eventEnd', { id: +el.dataset.id })); tabAdmin($('#tab-content')); } },
    evAnnounce: async (el) => { await act(admin('eventAnnounce', { id: +el.dataset.id }), '再告知しました'); },
    cidLookup: async () => {
        const cid = $('#cid-in').value.trim();
        const r = await admin('lookup', { cid });
        const box = $('#cid-res');
        if (!r.ok || !r.data) { box.innerHTML = '<span class="ng-mark">見つかりません</span>'; return; }
        const p = r.data;
        box.innerHTML = `<div class="row"><b>${esc(p.name)}</b><span class="coord">${esc(p.cid)}</span><span>現在: ${esc(p.roleLabel)}</span>
          <select id="role-${esc(p.cid)}" style="width:160px"><option value="">(未選択にリセット)</option>${S.profile.roles.map((x) => `<option value="${x.id}" ${p.role === x.id ? 'selected' : ''}>${esc(x.label)}</option>`).join('')}</select>
          <button class="btn btn-sm" data-act="setRole" data-cid="${esc(p.cid)}">変更</button></div>`;
    },
    setRole: async (el) => {
        const cid = el.dataset.cid;
        const s = document.getElementById(`role-${cid}`);
        const role = s ? s.value : '';
        if (!(await confirmBox('ロール変更', `${cid} のロールを「${role ? S.profile.roles.find((r) => r.id === role).label : '未選択'}」に変更します。`, '変更する'))) return;
        if (await act(admin('setRole', { cid, role }), '変更しました')) { if (AD.sub === 'roles' && $('#ad-body')) adRoles($('#ad-body')); }
    },
    runEnd: async (el) => { if (await confirmBox('強制終了', 'このインスタンスを終了し全員を帰還させます。', '終了', true)) { await act(admin('forceEnd', { runId: el.dataset.id })); adRuns($('#ad-body')); } },
    defNew: async (el) => {
        const name = await promptBox('新規作成', '名前', el.dataset.type === 'raid' ? '新しいレイド' : '新しいダンジョン');
        if (!name) return;
        const r = await act(admin('defCreate', { data: { name, type: el.dataset.type, minPlayers: 1, maxPlayers: el.dataset.type === 'raid' ? 12 : 4, timeLimit: el.dataset.type === 'raid' ? 1800 : 1200 } }));
        if (r) openEditor(r.data);
    },
    defEdit: (el) => openEditor(+el.dataset.id),
    defDup: async (el) => { const r = await act(admin('defDuplicate', { id: +el.dataset.id }), '複製しました'); if (r) adEditorList($('#ad-body')); },
    defPublish: async (el) => { if (await confirmBox('公開', '現在の下書きを公開版にします。', '公開する')) { await act(admin('defPublish', { id: +el.dataset.id }), '公開しました'); adEditorList($('#ad-body')); } },
    defArchive: async (el) => { if (await confirmBox('アーカイブ', '一覧から非表示にします(データは残ります)。', 'アーカイブ', true)) { await act(admin('defArchive', { id: +el.dataset.id })); adEditorList($('#ad-body')); } },
    tplUse: async () => { const id = +$('#tpl-sel').value; if (!id) return; const r = await act(admin('templateUse', { id }), 'テンプレートから作成しました'); if (r) openEditor(r.data); },
    tplDel: async () => { const id = +$('#tpl-sel').value; if (id && await confirmBox('テンプレート削除', '選択中のテンプレートを削除します。', '削除', true)) { await act(admin('templateDelete', { id })); adEditorList($('#ad-body')); } },

    /* --- エディター --- */
    edSec: (el) => { ED.section = el.dataset.id; renderEditor(); },
    edBack: async () => {
        if (ED.dirty && !(await confirmBox('未保存の変更', '保存せずに一覧へ戻りますか？', '戻る', true))) return;
        ED.dirty = false; ED.preview = false; post('editorPreview', { data: null });
        S.tab = 'admin'; AD.sub = 'editor'; renderHub('admin');
    },
    edSave: () => edSave(false),
    edValidate: async () => {
        const r = await admin('defValidate', { data: ED.data });
        ED.valid = r.ok ? { ok: true, summary: r.data } : { ok: false, error: r.error };
        if (r.ok) toast('検証OK: 公開できます', 'success'); else toast(`検証NG: ${r.error}`, 'warning', 8000);
        if (ED.section === 'publish') renderSection();
    },
    edPreview: () => { ED.preview = !ED.preview; post('editorPreview', { data: ED.preview ? ED.data : null }); renderEditor(); toast(ED.preview ? 'ワールドにプレビュー表示中 (自分にだけ見えます)' : 'プレビューを非表示にしました'); },
    edSaveTpl: async () => { const name = await promptBox('テンプレートとして保存', 'テンプレート名', ED.data.name); if (name) await act(admin('templateSave', { kind: 'definition', name, data: ED.data }), 'テンプレートを保存しました'); },
    edGoTest: () => { ED.section = 'publish'; renderEditor(); },
    edTest: async () => {
        if (!(await edSave(true))) return;
        const role = $('#test-role').value;
        const r = await act(admin('defTest', { id: ED.id, role }), 'テストを開始します');
        if (r) { ED.preview = false; post('editorPreview', { data: null }); closeUI(); }
    },
    edPublish: async () => {
        if (!(await edSave(true))) return;
        if (!(await confirmBox('公開', '保存した下書きを公開版にします。', '公開する'))) return;
        if (await act(admin('defPublish', { id: ED.id }), '公開しました')) { ED.status = 'published'; ED.version += 1; renderEditor(); }
    },
    edDuplicate: async () => { if (!(await edSave(true))) return; const r = await act(admin('defDuplicate', { id: ED.id }), '複製しました。複製を開きます'); if (r) openEditor(r.data); },
    edHere: (el) => hereTo(el.dataset.path),
    edPlace: (el) => placeTo(el.dataset.path, el.dataset.kind, el.dataset.label, el.dataset.model),
    edTp: (el) => { const c = getPath(ED.data, el.dataset.path); if (c) post('editorTeleport', c); },
    edDel: (el) => { delPath(ED.data, el.dataset.path); markDirty(); renderSection(); },
    edMove: (el) => {
        const arr = getPath(ED.data, el.dataset.path); const i = +el.dataset.i; const j = i + +el.dataset.d;
        if (!arr || j < 0 || j >= arr.length) return;
        [arr[i], arr[j]] = [arr[j], arr[i]]; markDirty(); renderSection();
    },
    chip: (el) => {
        const path = el.dataset.path; const v = el.dataset.val;
        const arr = getPath(ED.data, path) || [];
        const i = arr.indexOf(v);
        if (i >= 0) arr.splice(i, 1); else arr.push(v);
        setPath(ED.data, path, arr); markDirty(); renderSection();
    },
    edAddLoot: (el) => { const list = getPath(ED.data, el.dataset.path) || []; list.push({ item: ED.items[0] ? ED.items[0].id : '', min: 1, max: 1, chance: 100 }); setPath(ED.data, el.dataset.path, list); markDirty(); renderSection(); },
    edAddEnemy: async () => {
        const key = await promptBox('敵を追加', 'ID (半角英数字・_)', uid('enemy', Object.keys(ED.data.enemies)));
        if (!key) return;
        const k = key.replace(/[^\w-]/g, '');
        if (!k || ED.data.enemies[k]) return toast('IDが不正または重複しています', 'error');
        ED.data.enemies[k] = { label: '新しい敵', model: 'g_m_y_lost_01', hp: 250, weapon: 'WEAPON_BAT', accuracy: 30, armor: 0, loot: [] };
        markDirty(); renderSection();
    },
    edAddEnemyTpl: () => {
        const t = ED.enemyTpls.find((x) => x.id === +$('#etpl').value);
        if (!t) return;
        const k = uid('enemy', Object.keys(ED.data.enemies));
        ED.data.enemies[k] = JSON.parse(JSON.stringify(t.data));
        markDirty(); renderSection(); toast(`「${t.name}」を ${k} として追加しました`, 'success');
    },
    edEnemyTpl: async (el) => {
        const e = ED.data.enemies[el.dataset.key];
        const name = await promptBox('敵テンプレート保存', 'テンプレート名', e.label);
        if (name && await act(admin('templateSave', { kind: 'enemy', name, data: e }), '保存しました')) {
            const tr = await admin('templates', { kind: 'enemy' }); if (tr.ok) ED.enemyTpls = tr.data; renderSection();
        }
    },
    edAddSpawn: async (el) => {
        const id = uid('sp', ED.data.spawnPoints.map((s) => s.id));
        ED.data.spawnPoints.push({ id, label: `スポーン${ED.data.spawnPoints.length + 1}` });
        const path = `spawnPoints.${ED.data.spawnPoints.length - 1}`;
        const ok = el.dataset.mode === 'here' ? (await hereTo(path), true) : await placeTo(path, 'ped', id, 'g_m_y_lost_01');
        if (!ok || getPath(ED.data, path).x == null) { ED.data.spawnPoints.pop(); renderSection(); }
    },
    edAddProp: async () => {
        const model = $('#prop-model').value.trim();
        if (!model) return;
        const id = uid('prop', ED.data.props.map((p) => p.id));
        ED.data.props.push({ id, label: id, model });
        const path = `props.${ED.data.props.length - 1}`;
        const ok = await placeTo(path, 'prop', id, model);
        if (!ok) { ED.data.props.pop(); renderSection(); }
    },
    edAddWave: () => {
        const firstEnemy = Object.keys(ED.data.enemies)[0];
        const firstSp = ED.data.spawnPoints[0];
        ED.data.waves.push({ label: `ウェーブ${ED.data.waves.length + 1}`, message: '', delay: 4, objective: { type: 'kill_all' },
            groups: firstEnemy ? [{ enemy: firstEnemy, count: 4, spawn: firstSp ? [firstSp.id] : [] }] : [] });
        markDirty(); renderSection();
    },
    edDupWave: (el) => { const w = ED.data.waves[+el.dataset.i]; ED.data.waves.splice(+el.dataset.i + 1, 0, JSON.parse(JSON.stringify(w))); markDirty(); renderSection(); },
    edAddGroup: (el) => {
        const w = ED.data.waves[+el.dataset.i]; w.groups = w.groups || [];
        const firstEnemy = Object.keys(ED.data.enemies)[0];
        if (!firstEnemy) return toast('先に敵プリセットを作成してください', 'error');
        w.groups.push({ enemy: firstEnemy, count: 3, spawn: ED.data.spawnPoints[0] ? [ED.data.spawnPoints[0].id] : [] });
        markDirty(); renderSection();
    },
    edBossOn: () => {
        const firstEnemy = Object.keys(ED.data.enemies).find((k) => ED.data.enemies[k].isBoss) || Object.keys(ED.data.enemies)[0];
        if (!firstEnemy) return toast('先に敵プリセットを作成してください', 'error');
        ED.data.boss = { enemy: firstEnemy, spawn: ED.data.spawnPoints[0] ? ED.data.spawnPoints[0].id : '', phases: [{ hpPct: 100, label: '第1形態', message: '', damageTakenMult: 1, aoe: { interval: 12, radius: 6, delay: 2.5, damagePct: 0.3 } }] };
        markDirty(); renderSection();
    },
    edBossOff: async () => { if (await confirmBox('ボス削除', 'ボス設定を削除します。', '削除', true)) { delete ED.data.boss; markDirty(); renderSection(); } },
    edAddPhase: () => {
        const ph = ED.data.boss.phases = ED.data.boss.phases || [];
        const last = ph[ph.length - 1];
        ph.push({ hpPct: last ? Math.max(5, last.hpPct - 30) : 100, label: `フェーズ${ph.length + 1}`, message: '', damageTakenMult: 1 });
        markDirty(); renderSection();
    },
    edToggleObj: (el) => {
        const path = el.dataset.path;
        if (getPath(ED.data, path)) delPath(ED.data, path);
        else if (path.endsWith('.aoe')) setPath(ED.data, path, { interval: 12, radius: 6, delay: 2.5, damagePct: 0.3 });
        else setPath(ED.data, path, { enemy: Object.keys(ED.data.enemies)[0], count: 3, spawn: ED.data.spawnPoints[0] ? [ED.data.spawnPoints[0].id] : [] });
        markDirty(); renderSection();
    },
    edAnnPreview: async () => {
        const r = await admin('preview', { type: ED.data.type, name: ED.data.name, location: $('#ann-loc').value, templates: ED.data.announcements });
        $('#ann-prev').innerHTML = r.ok ? r.data.map((p) => `<div class="small muted">${esc(p.at)} 時点の例</div><div class="preview-ann">${esc(p.text)}</div>`).join('') : esc(r.error);
    },
};

document.addEventListener('click', (e) => {
    const el = e.target.closest('[data-act]');
    if (!el || el.tagName === 'INPUT' && el.type !== 'checkbox') return;
    const fn = ACTIONS[el.dataset.act];
    if (fn) { e.preventDefault(); fn(el, e); }
});
document.addEventListener('change', async (e) => {
    const el = e.target;
    if (el.dataset && el.dataset.bind && ED.data && S.screen === 'editor') {
        bindValue(el);
        if (el.dataset.checkModel && el.value) {
            const r = await post('checkModel', { model: el.value });
            el.style.borderColor = r && r.valid ? 'var(--ok)' : 'var(--err)';
            if (r && !r.valid) toast(`モデル「${el.value}」がゲーム内に見つかりません`, 'warning');
        }
        if (el.tagName === 'SELECT' || el.type === 'checkbox') renderSection();
    }
});

/* ===================== Lua からのメッセージ ===================== */
async function openScreen(screen, data) {
    $('#modal-root').innerHTML = '';
    if (screen === 'role' || screen === 'hub') {
        S.profile = data.profile;
        S.events = data.profile.events || [];
        if (screen === 'role') renderRole(null); else renderHub(data.tab || 'home');
    } else if (screen === 'entry') {
        if (!S.profile) await reloadProfile();
        renderEntry(data);
    } else if (screen === 'results') {
        renderResults(data);
    }
}

window.addEventListener('message', (e) => {
    const { action, data } = e.data || {};
    switch (action) {
        case 'open': openScreen(data.screen, data.data); break;
        case 'close': $('#app').classList.add('hidden'); $('#screen').innerHTML = ''; S.screen = null; break;
        case 'toast': toast(data.message, data.type, data.duration); break;
        case 'announce': announce(data); break;
        case 'banner': banner(data); break;
        case 'events':
            S.events = data || [];
            if (S.screen === 'hub' && (S.tab === 'events' || S.tab === 'home')) renderTab();
            break;
        case 'refresh':
            if (S.screen !== 'hub') break;
            if (data.what === 'inventory' && S.tab === 'inventory') renderTab();
            else if (data.what === 'party' && S.tab === 'party') renderTab();
            else if (data.what === 'profile') reloadProfile().then(() => S.profile.role ? renderHub(S.tab) : renderRole(null));
            break;
        case 'partyInvite': toast(`${data.leaderName} からパーティー招待が届きました。/rpg → パーティー で参加できます (${data.timeout}秒)`, 'info', 10000); break;
        case 'hud': hudShow(data); break;
        case 'party': hudParty(data); break;
        case 'objective': hudObjective(data); break;
        case 'selfHp': selfHp(data); break;
        case 'boundary':
            $('#boundary').classList.toggle('hidden', !data.show);
            if (data.show) $('#boundary-sec').textContent = data.seconds;
            break;
        case 'downed': $('#downed').classList.toggle('hidden', !data.show); break;
        case 'progress': progress(data); break;
        case 'skillUsed': { const el = $(`.skill[data-skill="${data.id}"]`); if (el) { el.classList.remove('flash'); void el.offsetWidth; el.classList.add('flash'); } break; }
        case 'target': H.target = data.id; hudParty({ members: H.members }); break;
        case 'placementResult': { const fn = ED.tokens[data.token]; delete ED.tokens[data.token]; if (fn) fn(data.result); break; }
        default: break;
    }
});

/* ===================== カスタムドロップダウン =====================
   FiveM の CEF ではネイティブ <select> のポップアップが描画されないため、
   全ての <select> を自前のドロップダウンで置き換える (値と change イベントは元の select に反映) */
let ddOpen = null;
function ddClose() {
    if (!ddOpen) return;
    ddOpen.list.parentNode && ddOpen.list.parentNode.removeChild(ddOpen.list);
    ddOpen.wrap.classList.toggle('open', false);
    ddOpen = null;
}
function ddSync(sel, wrap) {
    const opt = sel.options[sel.selectedIndex];
    const label = $('.dd-label', wrap);
    if (opt) { label.textContent = opt.textContent; label.classList.toggle('ph', false); }
    else { label.textContent = sel.options.length ? '選択してください' : '(選択肢がありません)'; label.classList.add('ph'); }
}
function ddOpenFor(sel, wrap) {
    ddClose();
    const btn = $('.dd-btn', wrap);
    const r = btn.getBoundingClientRect();
    const list = document.createElement('div');
    list.className = 'dd-list';
    const opts = Array.from(sel.options);
    list.innerHTML = opts.length
        ? opts.map((o, i) => `<div class="dd-opt ${i === sel.selectedIndex ? 'sel' : ''}" data-i="${i}">${esc(o.textContent)}</div>`).join('')
        : '<div class="dd-empty">選択肢がありません</div>';
    document.body.appendChild(list);
    const h = Math.min(list.scrollHeight, 280);
    const below = window.innerHeight - r.bottom - 8;
    list.style.left = `${r.left}px`;
    list.style.minWidth = `${r.width}px`;
    list.style.maxWidth = `${Math.max(r.width, 360)}px`;
    list.style.top = (below < h && r.top > below) ? `${Math.max(8, r.top - h - 4)}px` : `${r.bottom + 4}px`;
    list.addEventListener('mousedown', (e) => {
        const o = e.target.closest('.dd-opt');
        if (!o) return;
        e.preventDefault();
        sel.selectedIndex = +o.dataset.i;
        ddSync(sel, wrap);
        ddClose();
        sel.dispatchEvent(new Event('change', { bubbles: true }));
    });
    wrap.classList.add('open');
    ddOpen = { list, wrap, sel };
    const cur = $('.dd-opt.sel', list);
    if (cur) cur.scrollIntoView({ block: 'nearest' });
}
function enhanceSelects(root) {
    $$('select:not(.dd-native)', root).forEach((sel) => {
        sel.classList.add('dd-native');
        const wrap = document.createElement('div');
        wrap.className = 'dd';
        if (sel.getAttribute('style')) wrap.setAttribute('style', sel.getAttribute('style'));
        wrap.innerHTML = '<button type="button" class="dd-btn"><span class="dd-label"></span><span class="dd-arrow">▼</span></button>';
        sel.parentNode.insertBefore(wrap, sel);
        wrap.appendChild(sel);
        ddSync(sel, wrap);
        $('.dd-btn', wrap).addEventListener('click', (e) => {
            e.preventDefault(); e.stopPropagation();
            if (ddOpen && ddOpen.sel === sel) ddClose(); else ddOpenFor(sel, wrap);
        });
        sel.addEventListener('change', () => ddSync(sel, wrap));
    });
}
document.addEventListener('mousedown', (e) => { if (ddOpen && !e.target.closest('.dd-list') && !e.target.closest('.dd.open')) ddClose(); }, true);
document.addEventListener('scroll', (e) => { if (ddOpen && !(e.target.closest && e.target.closest('.dd-list'))) ddClose(); }, true);
document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && ddOpen) { ddClose(); e.stopImmediatePropagation(); } }, true);
new MutationObserver((muts) => {
    if (muts.every((m) => Array.from(m.addedNodes).every((n) => n.nodeType !== 1 || !(n.matches('select') || n.querySelector('select'))))) return;
    ddClose();
    enhanceSelects(document);
}).observe(document.body, { childList: true, subtree: true });
enhanceSelects(document);
