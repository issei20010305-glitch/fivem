// Built-in Heist HUD minigames: "pattern" (memory) and "sequence" (click in order).
const Minigame = {
    active: false,
    timers: [],

    clear() {
        this.timers.forEach((timer) => { clearTimeout(timer); clearInterval(timer); });
        this.timers = [];
    },

    finish(success) {
        if (!this.active) return;
        this.active = false;
        this.clear();
        const grid = $('#mg-grid');
        grid.classList.add(success ? 'won' : 'lost');
        setTimeout(() => {
            showPage('minigame', false);
            post('minigame:result', { success });
        }, 550);
    },

    /** Starts the countdown bar; fails the minigame when it runs out. */
    countdown(ms) {
        const bar = $('#mg-timer-bar');
        bar.style.transition = 'none';
        bar.style.width = '100%';
        void bar.offsetWidth;
        bar.style.transition = `width ${ms}ms linear`;
        bar.style.width = '0%';
        this.timers.push(setTimeout(() => this.finish(false), ms));
    },

    start(kind, settings) {
        this.clear();
        this.active = true;
        const grid = $('#mg-grid');
        grid.className = 'mg-grid';
        grid.innerHTML = '';
        $('#mg-timer-bar').style.transition = 'none';
        $('#mg-timer-bar').style.width = '100%';
        showPage('minigame', true);

        if (kind === 'sequence') this.sequence(settings || {});
        else this.pattern(settings || {});
    },

    pattern(settings) {
        const size = num(settings.grid, 5);
        const count = Math.min(num(settings.cells, 6), size * size - 1);
        const grid = $('#mg-grid');
        $('#mg-title').textContent = 'パターン記憶';
        $('#mg-hint').textContent = '光ったマスを覚えろ';
        grid.style.gridTemplateColumns = `repeat(${size}, 1fr)`;

        const targets = new Set();
        while (targets.size < count) targets.add(Math.floor(Math.random() * size * size));

        const cells = [];
        for (let i = 0; i < size * size; i++) {
            const cell = document.createElement('button');
            cell.className = 'mg-cell';
            if (targets.has(i)) cell.classList.add('show');
            grid.appendChild(cell);
            cells.push(cell);
        }

        let found = 0;
        let playing = false;

        this.timers.push(setTimeout(() => {
            cells.forEach((cell) => cell.classList.remove('show'));
            $('#mg-hint').textContent = '覚えたマスをすべてクリックしろ';
            playing = true;
            this.countdown(num(settings.timeMs, 9000));
        }, num(settings.showMs, 2500)));

        cells.forEach((cell, index) => {
            cell.addEventListener('click', () => {
                if (!playing || !this.active || cell.classList.contains('hit')) return;
                if (targets.has(index)) {
                    cell.classList.add('hit');
                    found++;
                    if (found === targets.size) this.finish(true);
                } else {
                    cell.classList.add('miss');
                    cells.forEach((other, i) => { if (targets.has(i)) other.classList.add('show'); });
                    this.finish(false);
                }
            });
        });
    },

    sequence(settings) {
        const count = num(settings.count, 12);
        const columns = Math.ceil(Math.sqrt(count));
        const grid = $('#mg-grid');
        $('#mg-title').textContent = 'ナンバーシーケンス';
        $('#mg-hint').textContent = '1 から順番に数字をクリックしろ';
        grid.style.gridTemplateColumns = `repeat(${columns}, 1fr)`;

        const numbers = Array.from({ length: count }, (_, i) => i + 1);
        for (let i = numbers.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [numbers[i], numbers[j]] = [numbers[j], numbers[i]];
        }

        let next = 1;
        numbers.forEach((value) => {
            const cell = document.createElement('button');
            cell.className = 'mg-cell number';
            cell.textContent = value;
            cell.addEventListener('click', () => {
                if (!this.active || cell.classList.contains('hit')) return;
                if (value === next) {
                    cell.classList.add('hit');
                    next++;
                    if (next > count) this.finish(true);
                } else {
                    cell.classList.add('miss');
                    this.finish(false);
                }
            });
            grid.appendChild(cell);
        });

        this.countdown(num(settings.timeMs, 12000));
    },
};

on('minigame:start', (data) => Minigame.start(data.kind, data.settings));

on('minigame:stop', () => {
    Minigame.active = false;
    Minigame.clear();
    showPage('minigame', false);
});
