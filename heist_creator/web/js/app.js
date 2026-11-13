// Shared helpers and the message router between Lua and the page.
const App = {
    handlers: {},
    settings: { keyLabel: 'E', cancelCommand: 'cancelheist' },
    openPage: null, // 'creator' | 'hud' | 'minigame' | null
};

const resourceName = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'heist_creator';

/** Calls a NUI callback registered in Lua and resolves with its JSON answer. */
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

/** Registers a handler for a message sent with NUI.Send(action, data). */
function on(action, handler) {
    App.handlers[action] = handler;
}

window.addEventListener('message', (event) => {
    const message = event.data || {};
    const handler = App.handlers[message.action];
    if (handler) handler(message.data);
});

const $ = (selector, root) => (root || document).querySelector(selector);

/** Escapes text before it is placed into HTML. */
function esc(value) {
    return String(value == null ? '' : value)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

/** Lua sends empty tables as {} - always work with real arrays. */
function arr(value) {
    return Array.isArray(value) ? value : [];
}

function num(value, fallback) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : (fallback || 0);
}

/** 3725 -> "1時間2分" */
function formatTime(seconds) {
    seconds = Math.max(0, Math.floor(seconds));
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    const s = seconds % 60;
    if (h > 0) return `${h}時間${m}分`;
    if (m > 0) return `${m}分${s}秒`;
    return `${s}秒`;
}

/** 95 -> "1:35" */
function formatClock(seconds) {
    seconds = Math.max(0, Math.floor(seconds));
    const m = Math.floor(seconds / 60);
    const s = seconds % 60;
    return `${m}:${String(s).padStart(2, '0')}`;
}

function showPage(id, visible) {
    $(`#${id}`).classList.toggle('hidden', !visible);
    if (visible) App.openPage = id;
    else if (App.openPage === id) App.openPage = null;
}

/** Small message shown at the bottom of the creator / Heist HUD window. */
function toast(id, text, kind) {
    const element = $(`#${id}`);
    if (!text) return;
    element.textContent = text;
    element.className = `toast ${kind || 'info'}`;
    clearTimeout(element._timer);
    element._timer = setTimeout(() => element.classList.add('hidden'), 4000);
}

function itemImage(name) {
    return `<img class="item-img" src="nui://ox_inventory/web/images/${esc(name)}.png" alt="" onerror="this.style.visibility='hidden'">`;
}

function stars(count, max) {
    let html = '';
    for (let i = 1; i <= (max || 5); i++) {
        html += `<span class="star${i <= count ? ' on' : ''}">★</span>`;
    }
    return html;
}

document.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape') return;
    if (App.openPage === 'minigame') {
        Minigame.finish(false);
    } else if (App.openPage === 'creator' || App.openPage === 'hud') {
        post('close');
    }
});

document.addEventListener('click', (event) => {
    const button = event.target.closest('[data-act="close"]');
    if (button) post('close');
});

post('ready').then((settings) => {
    if (settings && settings.keyLabel) App.settings = settings;
});
