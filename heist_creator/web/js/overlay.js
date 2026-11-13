// Guidance overlay: objective card and notification bubbles (bottom-right).
const Overlay = {
    deadline: null,
    timer: null,
};

const BUBBLE_ICONS = { info: 'i', success: '✓', error: '!', objective: '➤' };

on('overlay:notify', (data) => {
    if (!data || !data.text) return;
    const container = $('#bubbles');
    const kind = BUBBLE_ICONS[data.kind] ? data.kind : 'info';

    const bubble = document.createElement('div');
    bubble.className = `bubble ${kind}`;
    bubble.innerHTML = `<span class="bubble-icon">${BUBBLE_ICONS[kind]}</span><span class="bubble-text">${esc(data.text)}</span>`;
    container.appendChild(bubble);

    while (container.children.length > 5) container.removeChild(container.firstChild);

    setTimeout(() => {
        bubble.classList.add('out');
        setTimeout(() => bubble.remove(), 350);
    }, data.duration || 6000);
});

function updateObjectiveTimer() {
    const element = $('#objective-timer');
    if (!Overlay.deadline) {
        element.textContent = '';
        return;
    }
    const left = Math.max(0, Math.round((Overlay.deadline - Date.now()) / 1000));
    element.textContent = `⏱ ${formatClock(left)}`;
    element.classList.toggle('low', left <= 60);
}

on('overlay:objective', (data) => {
    const card = $('#objective');
    clearInterval(Overlay.timer);
    Overlay.timer = null;

    if (!data) {
        card.classList.add('hidden');
        Overlay.deadline = null;
        return;
    }

    $('#objective-title').textContent = data.title || '';
    $('#objective-text').textContent = data.text || '';
    $('#objective-step').textContent = data.step || '';

    const members = arr(data.members);
    $('#objective-crew').textContent = members.length > 0 ? `クルー ${members.length}人` : '';

    Overlay.deadline = typeof data.timeLeft === 'number' ? Date.now() + data.timeLeft * 1000 : null;
    updateObjectiveTimer();
    if (Overlay.deadline) Overlay.timer = setInterval(updateObjectiveTimer, 1000);

    card.classList.remove('hidden');
    card.classList.remove('pulse');
    void card.offsetWidth;
    card.classList.add('pulse');
});
