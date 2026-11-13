(() => {
    'use strict';

    const config = window.LOADSCREEN || {};
    const rainConfig = Object.assign({ density: 1, wind: 0.12 }, config.rain);
    const soundConfig = Object.assign({ enabled: true, volume: 0.22 }, config.sound);
    const statuses = (config.statuses || []).slice().sort((a, b) => a.from - b.from);

    const $ = (id) => document.getElementById(id);
    $('tagline').textContent = config.tagline || '';
    $('vertical').textContent = config.vertical || '';

    // -----------------------------------------------------------------------
    // Loading progress (sent by FiveM as "loadProgress" messages)
    // -----------------------------------------------------------------------
    let target = 0;
    let shown = 0;
    let statusIndex = -1;

    window.addEventListener('message', (event) => {
        const data = event.data || {};
        if (data.eventName === 'loadProgress' && typeof data.loadFraction === 'number') {
            target = Math.max(target, Math.min(1, data.loadFraction));
        }
    });

    // Opened in a normal browser (not FiveM): play a demo so the screen can be previewed.
    const inGame = 'invokeNative' in window || 'nuiHandoverData' in window;
    if (!inGame) {
        const started = performance.now();
        setInterval(() => { target = Math.min(1, (performance.now() - started) / 20000); }, 200);
    }

    function setStatus(index) {
        if (index === statusIndex || !statuses[index]) return;
        statusIndex = index;
        const element = $('status');
        element.classList.add('swap');
        setTimeout(() => {
            element.textContent = statuses[index].text;
            element.classList.remove('swap');
        }, element.textContent ? 500 : 0);
    }

    function updateProgress() {
        shown += (target - shown) * 0.05;
        if (target - shown < 0.0005) shown = target;
        $('bar').style.width = `${(shown * 100).toFixed(2)}%`;
        $('percent').textContent = Math.round(shown * 100);

        let index = 0;
        for (let i = 0; i < statuses.length; i++) {
            if (shown >= statuses[i].from) index = i;
        }
        setStatus(index);
    }

    // -----------------------------------------------------------------------
    // Rain. The umbrella in the logo really shelters what is below it:
    // drops that hit the canopy splash and run off its edge.
    // -----------------------------------------------------------------------
    const canvas = $('rain');
    const ctx = canvas.getContext('2d');
    const logo = $('logo');

    let width = 0;
    let height = 0;
    let drops = [];
    let splashes = [];
    let drips = [];
    let canopy = null; // { cx, rx, rimY, ry }
    let nextDrip = 0;

    // Position of the umbrella canopy inside logo.png (fractions of the image).
    const CANOPY = { cx: 0.56, rx: 0.205, top: 0.105, rim: 0.318 };

    function measureCanopy() {
        const rect = logo.getBoundingClientRect();
        if (rect.width < 10) { canopy = null; return; }
        canopy = {
            cx: rect.left + rect.width * CANOPY.cx,
            rx: rect.width * CANOPY.rx,
            rimY: rect.top + rect.height * CANOPY.rim,
            ry: rect.height * (CANOPY.rim - CANOPY.top),
        };
    }

    /** Height of the canopy surface at x, or null when x is not under the umbrella. */
    function canopyY(x) {
        if (!canopy) return null;
        const t = (x - canopy.cx) / canopy.rx;
        if (t <= -1 || t >= 1) return null;
        return canopy.rimY - canopy.ry * Math.sqrt(1 - t * t);
    }

    function newDrop(anywhere) {
        const depth = 0.25 + Math.random() * 0.75; // 1 = close to the camera
        return {
            x: Math.random() * (width + height * rainConfig.wind) - height * rainConfig.wind,
            y: anywhere ? Math.random() * height : -40 - Math.random() * 200,
            depth,
            speed: (0.55 + depth * 0.75) * height * 1.05, // px per second
            length: 10 + depth * 26,
            alpha: 0.06 + depth * 0.2,
        };
    }

    function resize() {
        const ratio = Math.min(window.devicePixelRatio || 1, 2);
        width = window.innerWidth;
        height = window.innerHeight;
        canvas.width = width * ratio;
        canvas.height = height * ratio;
        ctx.setTransform(ratio, 0, 0, ratio, 0, 0);

        const count = Math.round((width * height) / 5200 * rainConfig.density);
        drops = Array.from({ length: count }, () => newDrop(true));
        // Do not start with drops already underneath the umbrella.
        measureCanopy();
        drops.forEach((drop) => {
            const surface = canopyY(drop.x);
            if (surface !== null && drop.y > surface) drop.y = -Math.random() * height;
        });
    }

    function splash(x, y, strength) {
        const parts = 2 + Math.floor(Math.random() * 2);
        for (let i = 0; i < parts; i++) {
            splashes.push({
                x, y,
                vx: (Math.random() - 0.5) * 90,
                vy: -(40 + Math.random() * 80) * strength,
                life: 0.25 + Math.random() * 0.2,
                age: 0,
            });
        }
    }

    function frame(now) {
        const delta = Math.min(0.05, (now - (frame.last || now)) / 1000);
        frame.last = now;
        const wind = rainConfig.wind;

        ctx.clearRect(0, 0, width, height);
        ctx.lineCap = 'round';

        // Falling rain
        for (let i = 0; i < drops.length; i++) {
            const drop = drops[i];
            const step = drop.speed * delta;
            drop.y += step;
            drop.x += step * wind;

            const surface = canopyY(drop.x);
            if (surface !== null && drop.y >= surface && drop.y - step - drop.length <= surface + 6) {
                if (drop.depth > 0.45) splash(drop.x, surface, drop.depth);
                drops[i] = newDrop(false);
                continue;
            }
            if (drop.y - drop.length > height) {
                drops[i] = newDrop(false);
                continue;
            }

            ctx.strokeStyle = `rgba(214, 226, 242, ${drop.alpha})`;
            ctx.lineWidth = 0.6 + drop.depth * 0.9;
            ctx.beginPath();
            ctx.moveTo(drop.x, drop.y);
            ctx.lineTo(drop.x - drop.length * wind, drop.y - drop.length);
            ctx.stroke();
        }

        // Splashes on the canopy
        ctx.fillStyle = 'rgba(226, 235, 248, 0.7)';
        for (let i = splashes.length - 1; i >= 0; i--) {
            const part = splashes[i];
            part.age += delta;
            if (part.age >= part.life) { splashes.splice(i, 1); continue; }
            part.vy += 520 * delta;
            part.x += part.vx * delta;
            part.y += part.vy * delta;
            ctx.globalAlpha = 1 - part.age / part.life;
            ctx.beginPath();
            ctx.arc(part.x, part.y, 1.1, 0, Math.PI * 2);
            ctx.fill();
        }
        ctx.globalAlpha = 1;

        // Water running off the tips of the umbrella
        if (canopy && now >= nextDrip) {
            nextDrip = now + 180 + Math.random() * 420;
            const tip = [-0.97, -0.5, 0.5, 0.97][Math.floor(Math.random() * 4)];
            drips.push({ x: canopy.cx + canopy.rx * tip, y: canopy.rimY + 2, vy: 20 });
        }
        ctx.fillStyle = 'rgba(226, 235, 248, 0.55)';
        for (let i = drips.length - 1; i >= 0; i--) {
            const drip = drips[i];
            drip.vy += 900 * delta;
            drip.y += drip.vy * delta;
            drip.x += drip.vy * delta * wind * 0.4;
            if (drip.y > height) { drips.splice(i, 1); continue; }
            ctx.beginPath();
            ctx.ellipse(drip.x, drip.y, 1.3, 1.3 + Math.min(6, drip.vy / 160), 0, 0, Math.PI * 2);
            ctx.fill();
        }

        updateProgress();
        requestAnimationFrame(frame);
    }

    window.addEventListener('resize', resize);
    logo.addEventListener('load', measureCanopy);
    setInterval(measureCanopy, 1000); // follows the logo's entrance animation
    resize();
    requestAnimationFrame(frame);

    // -----------------------------------------------------------------------
    // Rain sound, generated with Web Audio (no audio file needed)
    // -----------------------------------------------------------------------
    const button = $('sound');
    let audio = null;
    let master = null;
    let soundOn = soundConfig.enabled;

    function label() {
        button.textContent = soundOn ? '雨音　ON' : '雨音　OFF';
    }

    function startAudio() {
        if (audio) return;
        const AudioContext = window.AudioContext || window.webkitAudioContext;
        if (!AudioContext) { button.classList.add('hidden'); return; }
        audio = new AudioContext();

        const seconds = 4;
        const buffer = audio.createBuffer(2, audio.sampleRate * seconds, audio.sampleRate);
        for (let channel = 0; channel < 2; channel++) {
            const data = buffer.getChannelData(channel);
            for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;
        }

        master = audio.createGain();
        master.gain.value = 0;
        master.connect(audio.destination);

        // [filter type, frequency, gain] - hiss of the rain + a soft low rumble
        [['highpass', 1800, 0.5], ['bandpass', 700, 0.35], ['lowpass', 220, 0.6]].forEach(([type, frequency, gain]) => {
            const source = audio.createBufferSource();
            source.buffer = buffer;
            source.loop = true;
            const filter = audio.createBiquadFilter();
            filter.type = type;
            filter.frequency.value = frequency;
            const level = audio.createGain();
            level.gain.value = gain;
            source.connect(filter).connect(level).connect(master);
            source.start(0, Math.random() * seconds);
        });

        master.gain.linearRampToValueAtTime(soundOn ? soundConfig.volume : 0, audio.currentTime + 3);
    }

    function applySound() {
        label();
        if (!audio) { if (soundOn) startAudio(); return; }
        if (audio.state === 'suspended') audio.resume();
        master.gain.cancelScheduledValues(audio.currentTime);
        master.gain.linearRampToValueAtTime(soundOn ? soundConfig.volume : 0, audio.currentTime + 0.6);
    }

    button.addEventListener('click', (event) => {
        event.stopPropagation();
        soundOn = !soundOn;
        applySound();
    });

    // Browsers only allow sound after a click; FiveM allows it straight away.
    document.addEventListener('click', () => {
        if (soundOn && audio && audio.state === 'suspended') audio.resume();
    });

    label();
    if (soundOn) startAudio();
})();
