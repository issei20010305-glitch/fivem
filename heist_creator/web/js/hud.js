// Heist HUD (player UI). Everything shown here is informational: the server
// validates every requirement again when a heist is started.
const Hud = {
    data: null,
    fetchedAt: 0,
    selected: null,
    nearby: null, // list of nearby players (null = not requested yet)
    poll: null,
    tick: null,
    signature: '',
    partySignature: '',
    busy: false,
};

function cooldownLeft(seconds) {
    return Math.max(0, num(seconds) - (Date.now() - Hud.fetchedAt) / 1000);
}

function heistById(id) {
    return arr(Hud.data && Hud.data.heists).find((heist) => heist.id === id);
}

/** Why the selected heist cannot be started right now (null = can start). */
function blockReason(heist) {
    const d = Hud.data;
    const party = d.party;
    const size = party ? arr(party.members).length : 1;

    if (d.activeHeist) return 'ヘイスト進行中です';
    if (heist.locked) return `ヘイストXPが不足しています (必要 ${heist.requiredXp} XP)`;
    if (party && party.leader !== d.player.id) return 'パーティーリーダーのみ開始できます';
    if (heist.active) return '他のクルーが進行中です';
    if (cooldownLeft(heist.cooldownGlobal) > 0) return 'サーバー全体のクールダウン中です';
    if (cooldownLeft(heist.cooldownPlayer) > 0) return 'あなたはクールダウン中です';
    if (d.police < heist.minPolice) return `警察官が不足しています (${d.police} / ${heist.minPolice})`;
    if (size < heist.minPlayers) return `最低 ${heist.minPlayers} 人のパーティーが必要です`;
    if (size > heist.maxPlayers) return `このヘイストは最大 ${heist.maxPlayers} 人までです`;
    return null;
}

function heistStatus(heist) {
    if (heist.locked) return { cls: 'locked', text: `🔒 ${heist.requiredXp} XP 必要` };
    if (heist.active) return { cls: 'busy', text: '進行中' };
    if (cooldownLeft(heist.cooldownGlobal) > 0 || cooldownLeft(heist.cooldownPlayer) > 0) {
        return { cls: 'cooldown', text: 'クールダウン中' };
    }
    if (Hud.data.police < heist.minPolice) return { cls: 'cooldown', text: '警察官不足' };
    return { cls: 'ready', text: '受注可能' };
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------
function renderPlayer() {
    const p = Hud.data.player;
    const span = p.nextXp ? p.nextXp - p.rankXp : 1;
    const progress = p.nextXp ? Math.min(100, ((p.xp - p.rankXp) / span) * 100) : 100;
    $('#hud-player').innerHTML = `
        <div class="player-name">${esc(p.name)} <span class="mute">ID ${p.id}</span></div>
        <div class="player-rank">${esc(p.rank)}</div>
        <div class="xp-row"><span class="xp-value">${p.xp.toLocaleString()} XP</span>
            <span class="mute">${p.nextXp ? `次のランクまで ${(p.nextXp - p.xp).toLocaleString()} XP` : '最高ランク'}</span></div>
        <div class="bar"><div class="bar-fill" style="width:${progress}%"></div></div>`;
    $('#hud-police').innerHTML = `<span class="chip-dot"></span>警察官オンライン <b>${Hud.data.police}</b>人`;
}

function renderParty() {
    const d = Hud.data;
    const party = d.party;
    const invites = arr(d.invites);
    let html = '<div class="section-title">パーティー</div>';

    if (invites.length > 0 && !party) {
        html += invites.map((invite) => `<div class="invite">
            <div><b>${esc(invite.from)}</b> からの招待</div>
            <div class="invite-actions">
                <button class="btn small primary" data-act="party-accept" data-arg="${invite.partyId}">参加する</button>
                <button class="btn small ghost" data-act="party-decline" data-arg="${invite.partyId}">拒否</button>
            </div>
        </div>`).join('');
    }

    if (!party) {
        html += `<div class="mute small-text">パーティーを作成すると、近くのプレイヤーやサーバーIDで仲間を招待できます。ソロでも挑戦可能です。</div>
            <button class="btn primary block" data-act="party-create">パーティーを作成</button>`;
    } else {
        const members = arr(party.members);
        const isLeader = party.leader === d.player.id;
        const bonus = arr(d.bonus).filter((entry) => members.length >= entry.size).pop();

        html += `<div class="members">${members.map((member) => `<div class="member">
                <span class="member-name">${member.leader ? '<span class="crown">★</span>' : ''}${esc(member.name)} <span class="mute">ID ${member.id}</span></span>
                ${isLeader && !member.leader && !party.inHeist ? `<button class="btn small danger" data-act="party-kick" data-arg="${member.id}">追放</button>` : ''}
            </div>`).join('')}</div>
            <div class="bonus-line">メンバー ${members.length} / ${party.max} ・ XPボーナス <b>+${bonus ? bonus.percent : 0}%</b></div>`;

        if (isLeader && !party.inHeist && members.length < party.max) {
            html += `<div class="invite-row">
                    <input type="number" id="invite-id" min="1" placeholder="サーバーID">
                    <button class="btn small primary" data-act="party-invite-id">招待</button>
                </div>
                <button class="btn small block" data-act="party-nearby">近くのプレイヤーを表示</button>`;
            if (Hud.nearby) {
                html += Hud.nearby.length === 0
                    ? '<div class="mute small-text">近くに招待できるプレイヤーがいません。</div>'
                    : `<div class="members">${Hud.nearby.map((player) => `<div class="member">
                        <span class="member-name">${esc(player.name)} <span class="mute">ID ${player.id}</span></span>
                        <button class="btn small" data-act="party-invite" data-arg="${player.id}">招待</button>
                    </div>`).join('')}</div>`;
            }
        }

        html += party.inHeist
            ? `<button class="btn danger block push" data-act="heist-cancel">${isLeader ? 'ヘイストを中止する' : 'ヘイストから離脱する'}</button>`
            : `<button class="btn ghost block push" data-act="party-leave">パーティーを抜ける</button>`;
    }

    const input = $('#invite-id');
    const typed = input ? input.value : '';
    $('#hud-party').innerHTML = html;
    if (typed && $('#invite-id')) $('#invite-id').value = typed;
}

function renderHeists() {
    const heists = arr(Hud.data.heists);
    if (heists.length === 0) {
        $('#hud-heists').innerHTML = '<div class="empty">現在受注できるヘイストはありません。</div>';
        return;
    }
    $('#hud-heists').innerHTML = heists.map((heist) => {
        const status = heistStatus(heist);
        return `<button class="heist-card${heist.id === Hud.selected ? ' active' : ''}${heist.locked ? ' is-locked' : ''}" data-act="select" data-arg="${heist.id}">
            <div class="heist-image">
                ${heist.image ? `<img src="${esc(heist.image)}" alt="" onerror="this.remove()">` : ''}
                <span class="badge ${status.cls}">${status.text}</span>
            </div>
            <div class="heist-info">
                <div class="heist-name">${esc(heist.name)}</div>
                <div class="heist-meta"><span class="stars">${stars(heist.difficulty)}</span><span>+${heist.xpReward} XP</span></div>
            </div>
        </button>`;
    }).join('');
}

function requirement(ok, label, value) {
    return `<div class="req ${ok ? 'ok' : 'ng'}"><span class="req-icon">${ok ? '✓' : '✕'}</span><span class="req-label">${label}</span><span class="req-value">${value}</span></div>`;
}

function renderDetail() {
    const d = Hud.data;
    const heist = heistById(Hud.selected);
    const panel = $('#hud-detail');
    if (!heist) {
        panel.innerHTML = '<div class="empty">ヘイストを選択してください。</div>';
        return;
    }

    const size = d.party ? arr(d.party.members).length : 1;
    const globalLeft = cooldownLeft(heist.cooldownGlobal);
    const playerLeft = cooldownLeft(heist.cooldownPlayer);
    const reason = blockReason(heist);

    const rewards = arr(heist.rewards).map((reward) => `<div class="reward">
        ${itemImage(reward.item)}
        <span class="reward-name">${esc(reward.label)}</span>
        <span class="reward-amount">×${reward.min === reward.max ? reward.min.toLocaleString() : `${reward.min.toLocaleString()}〜${reward.max.toLocaleString()}`}</span>
        <span class="reward-chance${reward.guaranteed ? ' sure' : ''}">${reward.guaranteed ? '確定' : `${reward.chance}%`}</span>
    </div>`).join('');

    panel.innerHTML = `
        <div class="detail-image">${heist.image ? `<img src="${esc(heist.image)}" alt="" onerror="this.remove()">` : ''}
            <div class="detail-heading">
                <div class="detail-name">${esc(heist.name)}</div>
                <div class="stars">${stars(heist.difficulty)} <span class="mute">難易度</span></div>
            </div>
        </div>
        <div class="detail-scroll">
            ${heist.description ? `<p class="detail-desc">${esc(heist.description)}</p>` : ''}
            <div class="stats">
                <div class="stat"><span>${heist.stages}</span>ステージ</div>
                <div class="stat"><span>${heist.loots}</span>物色ポイント</div>
                <div class="stat"><span>${heist.timeLimit > 0 ? `${heist.timeLimit}分` : '∞'}</span>制限時間</div>
                <div class="stat"><span>+${heist.xpReward}</span>獲得XP</div>
            </div>

            <div class="section-title">受注条件</div>
            ${requirement(!heist.locked, '必要ヘイストXP', `${d.player.xp.toLocaleString()} / ${heist.requiredXp.toLocaleString()} XP`)}
            ${requirement(d.police >= heist.minPolice, '警察官', `現在 ${d.police}人 / 必要 ${heist.minPolice}人`)}
            ${requirement(size >= heist.minPlayers && size <= heist.maxPlayers, '参加人数', `現在 ${size}人 / ${heist.minPlayers}〜${heist.maxPlayers}人`)}
            ${requirement(globalLeft <= 0, 'サーバー全体クールダウン', globalLeft > 0 ? `残り <span data-cd="global">${formatTime(globalLeft)}</span>` : `利用可能 (${heist.globalCooldown}分)`)}
            ${requirement(playerLeft <= 0, '個人クールダウン', playerLeft > 0 ? `残り <span data-cd="player">${formatTime(playerLeft)}</span>` : `利用可能 (${heist.playerCooldown}分)`)}

            <div class="section-title">期待できる報酬 <span class="mute">(物色ポイントごとに抽選)</span></div>
            ${rewards || '<div class="mute small-text">アイテム報酬はありません。</div>'}

            <div class="section-title">パーティーXPボーナス</div>
            <div class="bonus-grid">${arr(d.bonus).map((entry, index, list) => `<div class="bonus${size >= entry.size && (index === list.length - 1 || size < list[index + 1].size) ? ' on' : ''}">
                <span>${entry.size}${index === list.length - 1 ? '人以上' : '人'}</span><b>+${entry.percent}%</b></div>`).join('')}</div>
        </div>
        <div class="detail-foot">
            ${reason ? `<div class="block-reason">${esc(reason)}</div>` : ''}
            <button class="btn primary big block" data-act="start" ${reason ? 'disabled' : ''}>このヘイストを開始する</button>
        </div>`;
}

function hudSignature() {
    const d = Hud.data;
    return JSON.stringify([
        d.player, d.police, d.activeHeist, Hud.selected,
        d.party ? [d.party.leader, arr(d.party.members).length] : null,
        arr(d.heists).map((heist) => Object.assign({}, heist, {
            cooldownGlobal: cooldownLeft(heist.cooldownGlobal) > 0,
            cooldownPlayer: cooldownLeft(heist.cooldownPlayer) > 0,
        })),
    ]);
}

function partySignature() {
    return JSON.stringify([Hud.data.party, arr(Hud.data.invites).map((invite) => invite.partyId), Hud.nearby, Hud.data.bonus]);
}

/** Renders only the parts that changed, so typing and scrolling are not interrupted. */
function renderHud(force) {
    if (!Hud.data) return;
    const heists = arr(Hud.data.heists);
    if (!heistById(Hud.selected)) Hud.selected = heists.length > 0 ? heists[0].id : null;

    const signature = hudSignature();
    if (force || signature !== Hud.signature) {
        Hud.signature = signature;
        renderPlayer();
        renderHeists();
        const scroller = $('#hud-detail .detail-scroll');
        const scroll = scroller ? scroller.scrollTop : 0;
        renderDetail();
        if ($('#hud-detail .detail-scroll')) $('#hud-detail .detail-scroll').scrollTop = scroll;
    }

    const party = partySignature();
    if (force || party !== Hud.partySignature) {
        Hud.partySignature = party;
        renderParty();
    }
}

function setHudData(data) {
    Hud.data = data;
    Hud.fetchedAt = Date.now();
}

async function refreshHud() {
    const answer = await post('hud:refresh');
    if (answer && answer.ok && answer.data && App.openPage === 'hud') {
        setHudData(answer.data);
        renderHud();
    }
}

/** Updates the cooldown countdown every second. */
function tickHud() {
    if (!Hud.data) return;
    const heist = heistById(Hud.selected);
    if (heist) {
        const global = $('#hud-detail [data-cd="global"]');
        const player = $('#hud-detail [data-cd="player"]');
        if (global) global.textContent = formatTime(cooldownLeft(heist.cooldownGlobal));
        if (player) player.textContent = formatTime(cooldownLeft(heist.cooldownPlayer));
    }
    renderHud(); // re-renders only when a cooldown just expired
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------
async function partyAction(action, target) {
    if (Hud.busy) return;
    Hud.busy = true;
    const answer = await post('hud:party', { action, target });
    Hud.busy = false;

    if (action === 'nearby') {
        Hud.nearby = answer.ok ? arr(answer.result) : [];
        renderHud();
        return;
    }
    if (typeof answer.result === 'string') toast('hud-toast', answer.result, answer.ok ? 'success' : 'error');
    setTimeout(refreshHud, 300);
}

const HUD_ACTIONS = {
    select(arg) {
        Hud.selected = Number(arg);
        renderHud();
    },
    'party-create': () => partyAction('create'),
    'party-leave'() {
        Hud.nearby = null;
        partyAction('leave');
    },
    'party-accept': (arg) => partyAction('accept', Number(arg)),
    'party-decline': (arg) => partyAction('decline', Number(arg)),
    'party-kick': (arg) => partyAction('kick', Number(arg)),
    'party-invite': (arg) => partyAction('invite', Number(arg)),
    'party-invite-id'() {
        const input = $('#invite-id');
        const id = Number(input.value);
        if (!id) return;
        input.value = '';
        partyAction('invite', id);
    },
    'party-nearby': () => partyAction('nearby'),
    async start() {
        if (Hud.busy || !Hud.selected) return;
        Hud.busy = true;
        const answer = await post('hud:start', { id: Hud.selected });
        Hud.busy = false;
        if (!answer.ok) {
            toast('hud-toast', answer.result || '開始できませんでした', 'error');
            refreshHud();
        }
    },
    async 'heist-cancel'() {
        if (Hud.busy) return;
        Hud.busy = true;
        const answer = await post('hud:cancel');
        Hud.busy = false;
        if (!answer.ok && answer.result) toast('hud-toast', answer.result, 'error');
        setTimeout(refreshHud, 300);
    },
};

$('#hud').addEventListener('click', (event) => {
    const button = event.target.closest('[data-act]');
    if (!button || button.disabled) return;
    const action = HUD_ACTIONS[button.dataset.act];
    if (action) action(button.dataset.arg);
});

on('hud:open', (data) => {
    setHudData(data);
    Hud.nearby = null;
    Hud.busy = false;
    renderHud(true);
    showPage('hud', true);
    clearInterval(Hud.poll);
    clearInterval(Hud.tick);
    Hud.poll = setInterval(refreshHud, 5000);
    Hud.tick = setInterval(tickHud, 1000);
});

on('hud:close', () => {
    showPage('hud', false);
    clearInterval(Hud.poll);
    clearInterval(Hud.tick);
});

// Party changed on the server (someone joined, left, was kicked...).
on('hud:party', (party) => {
    if (App.openPage !== 'hud' || !Hud.data) return;
    Hud.data.party = party || null;
    renderHud();
});

on('hud:invited', () => {
    if (App.openPage === 'hud') refreshHud();
});
