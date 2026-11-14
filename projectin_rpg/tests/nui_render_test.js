const { chromium } = require('playwright');
const path = require('path');
// 使い方: node tests/nui_render_test.js [スクリーンショット出力先]
// Playwright と Chromium が必要です。
const fs = require('fs');
const SHOTS = path.resolve(process.argv[2] || path.join(__dirname, 'shots'));
fs.mkdirSync(SHOTS, { recursive: true });
const WEB = 'file://' + path.join(__dirname, '..', 'web', 'index.html');
const roles = [
  { id: 'tank', label: 'タンク', description: '高い耐久力で仲間を守る盾。HP1.5倍 / 与ダメージ0.8倍。', color: '#4aa3ff', icon: '🛡', hpMult: 1.5, damageMult: 0.8, inventoryMult: 1, canAttack: true },
  { id: 'attacker', label: 'アタッカー', description: '圧倒的な火力で敵を殲滅。HP0.8倍 / 与ダメージ1.5倍。', color: '#ff5a5a', icon: '⚔', hpMult: 0.8, damageMult: 1.5, inventoryMult: 1, canAttack: true },
  { id: 'porter', label: '荷物持ち', description: '戦利品を大量に持ち帰る運び屋。RPGインベントリのスロット数・重量上限が2倍。', color: '#ffc24a', icon: '🎒', hpMult: 1, damageMult: 1, inventoryMult: 2, canAttack: true },
  { id: 'mage', label: '魔導士', description: 'MPを使い仲間を回復・強化する支援職。攻撃はできません。', color: '#b57bff', icon: '✦', hpMult: 1, damageMult: 0, inventoryMult: 1, canAttack: false },
];
const events = [
  { id: 1, name: '採石場の魔窟', type: 'dungeon', status: 'active', location: '8012番地', entry: { x: 1, y: 2, z: 3 }, minPlayers: 1, maxPlayers: 4, timeLimit: 1200, startIn: -60, endIn: 40000, startLabel: '本日12時', endLabel: '本日24時', registered: 0, recommended: '1〜4人 / 初心者向け' },
  { id: 2, name: 'チリアド山頂決戦', type: 'raid', status: 'announced', location: '3001番地', entry: { x: 1, y: 2, z: 3 }, minPlayers: 1, maxPlayers: 12, timeLimit: 1800, startIn: 1800, endIn: 5000, startLabel: '本日12時30分', endLabel: '本日13時10分', registered: 3, recommended: '6〜12人 / 上級者向け' },
];
const profile = (role) => ({ cid: 'ABC123', name: 'テスト 太郎', role, roles, isAdmin: true, stats: { runs: 5, dungeonClears: 3, raidClears: 1, kills: 87 }, events, party: {}, nowJst: '2026-11-14 12:00',
  mage: { maxMp: 100, skills: { heal: { key: 1, label: 'ヒール', mp: 25, cooldown: 6, range: 30 }, buff: { key: 2, label: 'パワーブースト', mp: 35, cooldown: 18, range: 30 }, areaHeal: { key: 3, label: 'サンクチュアリ', mp: 55, cooldown: 30, range: 15 }, revive: { key: 4, label: 'リザレクション', mp: 70, cooldown: 45, range: 6 } } } });
const draft = require('./fixture_draft.json');
const responses = {
  getProfile: () => profile('tank'),
  getInventory: () => ({ slots: 30, usableSlots: 30, baseSlots: 30, maxWeight: 60000, weight: 8400, inRun: false, overflow: [{ index: 1, name: 'titan_core', count: 1, label: 'タイタンコア', icon: '🟠', rarity: 'epic' }],
    items: [{ slot: 1, name: 'dungeon_token', count: 12, label: 'ダンジョンメダル', icon: '🏅', rarity: 'uncommon', rarityLabel: 'アンコモン', weight: 10, description: 'ダンジョン踏破の証。', usable: false },
            { slot: 2, name: 'potion_small', count: 4, label: '回復薬(小)', icon: '🧪', rarity: 'common', rarityLabel: 'コモン', weight: 150, description: 'HPを25%回復。', usable: true },
            { slot: 5, name: 'summit_crown', count: 1, label: '山頂の王冠', icon: '👑', rarity: 'legendary', rarityLabel: 'レジェンダリー', weight: 2000, description: '最高報酬。', usable: false }] }),
  party: (a) => a[0] === 'nearby' ? [{ id: 7, name: '山田 花子', inParty: false }] : ({ party: { id: 1, leader: 1, isLeader: true, members: [{ id: 1, name: 'テスト 太郎', role: 'tank', roleLabel: 'タンク', roleColor: '#4aa3ff', leader: true }, { id: 4, name: '佐藤 次郎', role: 'mage', roleLabel: '魔導士', roleColor: '#b57bff' }] }, invites: [], maxSize: 4 }),
  admin: (a) => {
    const act = a[0];
    if (act === 'nowJst') return '2026-11-14 12:00';
    if (act === 'defs') return [{ id: 1, name: '採石場の魔窟', type: 'dungeon', status: 'published', version: 2, hasUnpublished: true, valid: true, summary: { waves: 4, enemies: 15, hasBoss: true } }, { id: 3, name: '新しいダンジョン', type: 'dungeon', status: 'draft', version: 0, valid: false, error: 'スポーン地点を1つ以上配置してください', summary: {} }];
    if (act === 'events') return [{ id: 1, name: '採石場の魔窟', type: 'dungeon', status: 'active', location_label: '8012番地', announceJst: '2026-11-14 12:00', startJst: '2026-11-14 12:00', endJst: '2026-11-15 00:00', registered: 0 }];
    if (act === 'templates') return [{ id: 1, name: '基本ダンジョン', kind: 'definition', data: {} }, { id: 3, name: '近接ザコ(バット)', kind: 'enemy', data: { label: 'x', model: 'g_m_y_lost_01' } }];
    if (act === 'defGet') return { id: 1, status: 'published', version: 2, data: draft };
    if (act === 'items') return [{ id: 'dungeon_token', label: 'ダンジョンメダル', icon: '🏅' }, { id: 'quartz_shard', label: '石英の欠片', icon: '🔹' }];
    if (act === 'preview') return [{ key: 'dungeon_open', at: '2026-11-14 12:00', text: '8012番地でダンジョン発生！本日24時まで！' }, { key: 'dungeon_reminder', at: '2026-11-14 23:00', text: '8012番地のダンジョンは本日24時で消滅します！' }];
    if (act === 'players') return [{ id: 1, cid: 'ABC123', name: 'テスト 太郎', role: 'tank', roleLabel: 'タンク' }];
    if (act === 'runs') return [];
    if (act === 'logs') return [];
    return true;
  },
};
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1600, height: 900 }, deviceScaleFactor: 1 });
  const errors = [];
  page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
  page.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); });
  await page.route('https://projectin_rpg/**', async (route) => {
    const ep = route.request().url().split('/').pop();
    const body = route.request().postDataJSON() || {};
    let out = {};
    if (ep === 'request') {
      const fn = responses[body.name];
      let r = fn ? fn(body.args || []) : true;
      out = { ok: true, data: r };
    }
    if (ep === 'checkModel') out = { valid: true };
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(out) });
  });
  await page.goto(WEB);
  await page.evaluate(() => { document.body.style.background = 'linear-gradient(135deg,#3b4a5a,#6b7a5a)'; });
  const send = (action, data) => page.evaluate(([a, d]) => window.postMessage({ action: a, data: d }, '*'), [action, data]);
  const shot = async (n) => { await page.waitForTimeout(350); await page.screenshot({ path: path.join(SHOTS, n + '.png') }); };

  await send('open', { screen: 'role', data: { profile: profile(null) } });
  await page.click('[data-id="mage"]');
  await shot('01_role');
  await send('open', { screen: 'hub', data: { profile: profile('tank') } });
  await shot('02_home');
  await page.click('[data-act="tab"][data-id="events"]'); await shot('03_events');
  await page.click('[data-act="tab"][data-id="party"]'); await shot('04_party');
  await page.click('[data-act="tab"][data-id="inventory"]'); await page.waitForTimeout(200); await page.click('.slot[data-slot="2"]'); await shot('05_inventory');
  await page.click('[data-act="tab"][data-id="admin"]'); await shot('06_admin_events');
  await page.click('[data-act="evPreview"]', {timeout: 3000}); await shot('07_admin_preview');
  await page.click('[data-act="adSub"][data-id="editor"]'); await shot('08_admin_editor_list');
  await page.click('[data-act="defEdit"][data-id="1"]'); await page.waitForTimeout(300); await shot('09_editor_basic');
  for (const sec of ['location', 'enemies', 'waves', 'boss', 'rewards', 'announce', 'publish']) {
    await page.click(`[data-act="edSec"][data-id="${sec}"]`); await shot('10_editor_' + sec);
  }
  // 入力バインド確認
  await page.click('[data-act="edSec"][data-id="basic"]');
  await page.fill('[data-bind="name"]', '編集テスト'); await page.dispatchEvent('[data-bind="name"]', 'change');
  const dirty = await page.isVisible('#ed-dirty');
  await page.click('[data-act="edBack"]'); await page.waitForTimeout(200);
  const modalShown = await page.isVisible('.modal');
  await page.click('.modal .btn-danger');
  await page.keyboard.press('Escape');
  // エントリー画面
  await send('open', { screen: 'entry', data: { event: { id: 2, name: 'チリアド山頂決戦', type: 'raid', status: 'announced', location: '3001番地', description: '装甲巨兵を討伐せよ。', recommended: '', minPlayers: 1, maxPlayers: 12, timeLimit: 1800, startIn: 1800, endLabel: '', waves: 2, hasBoss: true, registered: 3 },
    members: [{ id: 1, name: 'テスト 太郎', ok: true, role: 'tank', roleLabel: 'タンク' }, { id: 4, name: '佐藤 次郎', ok: false, reason: '入口から離れすぎています', role: 'mage', roleLabel: '魔導士' }], isLeader: true, registered: false } });
  await shot('11_entry_raid');
  await page.keyboard.press('Escape');
  // HUD
  await send('hud', { show: true, name: 'チリアド山頂決戦', type: 'raid', test: false, role: 'mage', roleLabel: '魔導士', maxMp: 100, timeLimit: 1500,
    skills: [{ id: 'heal', key: 1, label: 'ヒール', mp: 25, cooldown: 6 }, { id: 'buff', key: 2, label: 'パワーブースト', mp: 35, cooldown: 18 }, { id: 'areaHeal', key: 3, label: 'サンクチュアリ', mp: 55, cooldown: 30 }, { id: 'revive', key: 4, label: 'リザレクション', mp: 70, cooldown: 45 }] });
  await send('party', { members: [{ id: 1, name: 'テスト 太郎', role: 'tank', roleLabel: 'タンク', color: '#4aa3ff', hp: 120, maxHp: 150, downed: false, buff: 12 }, { id: 4, name: '佐藤 次郎', role: 'mage', roleLabel: '魔導士', color: '#b57bff', hp: 64, maxHp: 100, mp: 40, maxMp: 100 }, { id: 5, name: '鈴木 三郎', role: 'attacker', roleLabel: 'アタッカー', color: '#ff5a5a', hp: 0, maxHp: 80, downed: true }],
    me: { mp: 40, cooldowns: { buff: 9 } } });
  await send('objective', { wave: 2, waveCount: 2, waveLabel: '決戦: タイタン・ジャガーノート', state: 'running', title: 'ボスを討伐する', progress: '', timeLeft: 1432, boss: { label: 'タイタン・ジャガーノート', hp: 90231, maxHp: 163400, phase: '増援要請', alive: true } });
  await send('selfHp', { hp: 64, maxHp: 100 });
  await send('announce', { title: '大型ボスレイド', text: '3001番地で大型ボスレイド発生！開始まで30分！', kind: 'raid', eventId: 2 });
  await send('banner', { title: '増援要請', text: 'タイタンが増援を呼んだ！', kind: 'boss' });
  await send('toast', { message: '佐藤 次郎 からパワーブーストを受けた！(15秒)', type: 'buff' });
  await shot('12_hud');
  await send('downed', { show: true }); await send('progress', { show: true, label: '汚染コアを破壊', duration: 4000 }); await shot('13_downed');
  await send('downed', { show: false }); await send('progress', { show: false });
  await send('open', { screen: 'results', data: { success: true, result: 'clear', resultLabel: 'クリア', name: '採石場の魔窟', type: 'dungeon', duration: 612, mvp: 1, testMode: false, autoLeave: 45,
    players: [{ id: 1, name: 'テスト 太郎', role: 'tank', roleLabel: 'タンク', kills: 9, damage: 5321, healing: 0, downs: 1, rewards: [{ label: 'ダンジョンメダル', icon: '🏅', count: 4, rarity: 'uncommon' }, { label: '呪われた結晶', icon: '🔮', count: 1, rarity: 'rare' }] },
              { id: 4, name: '佐藤 次郎', role: 'mage', roleLabel: '魔導士', kills: 0, damage: 0, healing: 830, downs: 0, rewards: [{ label: 'ダンジョンメダル', icon: '🏅', count: 3, rarity: 'uncommon' }] }] } });
  await shot('14_results');
  console.log(JSON.stringify({ errors, dirty, modalShown }, null, 1));
  if (errors.length || !dirty || !modalShown) process.exitCode = 1;
  await browser.close();
})();
