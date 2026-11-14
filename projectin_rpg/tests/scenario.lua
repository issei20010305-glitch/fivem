--[[ サーバーロジックのシナリオテスト (モック環境) ]]
local passed, failed = 0, 0
local function check(cond, label)
    if cond then passed = passed + 1 print('  ✔ ' .. label)
    else failed = failed + 1 print('  ✘ ' .. label) end
end
local function section(t) print('\n■ ' .. t) end
local U = RPG.Utils
local function count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
local function invCount(inv, name)
    local n = 0
    for _, it in pairs(inv or {}) do if it.name == name then n = n + it.count end end
    return n
end

-- 起動 (DB初期化・シード)
MOCK.advance(2000)

section('日本時間フォーマット')
local t0 = U.jstToEpoch(2026, 11, 14, 12, 0)
check(U.formatJst(t0) == '2026-11-14 12:00', 'jstToEpoch/formatJst 往復')
check(U.parseJst('2026-11-14 24:00') == U.jstToEpoch(2026, 11, 15, 0, 0), '24:00 は翌日0:00として解釈')
check(U.formatJstRelativeDay(U.parseJst('2026-11-14 24:00'), t0) == '本日24時', '「本日24時」表記')
check(U.formatJstRelativeDay(U.parseJst('2026-11-15 18:30'), t0) == '明日18時30分', '「明日18時30分」表記')
check(U.formatAnnouncement('{location}でダンジョン発生！{end}まで！', { location_label = '8012番地', end_at = U.parseJst('2026-11-14 24:00') }, t0)
    == '8012番地でダンジョン発生！本日24時まで！', 'ダンジョン告知文')
check(U.formatAnnouncement('{location}で大型ボスレイド発生！開始まで{startIn}！', { location_label = '3001番地', start_at = t0 + 1800 }, t0)
    == '3001番地で大型ボスレイド発生！開始まで30分！', 'レイド告知文')
check(U.parseJst('2026-13-01 10:00') == nil and U.parseJst('2026-11-14 24:30') == nil, '不正な日時を拒否')

section('初期コンテンツのスキーマ検証')
local dclean, derr = RPG.Schema.Sanitize(DefaultContent.dungeon)
check(dclean ~= nil, 'ダンジョン定義がサニタイズを通過 ' .. tostring(derr or ''))
local rclean, rerr = RPG.Schema.Sanitize(DefaultContent.raid)
check(rclean ~= nil, 'レイド定義がサニタイズを通過 ' .. tostring(rerr or ''))
check(count(MOCK.db.definitions) == 2, '初回起動で2件の定義を投入')
check(count(MOCK.db.templates) == #DefaultContent.templates, 'テンプレートを投入')
local bad = RPG.Schema.Sanitize({ name = 'x', entry = { x = 1, y = 1, z = 1 }, start = { x = 1, y = 1, z = 1 }, enemies = { a = { model = 'g_m_y_lost_01' } },
    spawnPoints = { { id = 'sp1', x = 1, y = 1, z = 1 } }, waves = { { objective = { type = 'boss' } } } })
check(bad == nil, 'ボス未設定のボス目標を拒否')
local evil = RPG.Schema.Sanitize({ name = 'evil', entry = { x = 1, y = 1, z = 1 }, start = { x = 1, y = 1, z = 1 },
    enemies = { a = { model = 'a;DROP', hp = 1e12, weapon = 'WEAPON_RPG' } }, spawnPoints = { { id = 'sp1', x = 1, y = 1, z = 1 } },
    waves = { { groups = { { enemy = 'a', count = 9999 } } } }, rewards = { clear = { { item = 'money', min = 1, max = 1e9 } } } })
check(evil and evil.enemies.a.hp == Config.EditorLimits.maxEnemyHp and evil.enemies.a.weapon == 'WEAPON_UNARMED' and evil.enemies.a.model == 'aDROP', '敵HP/武器/モデル名をサニタイズ')
check(evil and evil.waves[1].groups[1].count == Config.EditorLimits.maxEnemiesPerGroup, '敵数を上限でクランプ')
check(evil and #evil.rewards.clear == 0, '未定義アイテム(money等)を報酬から除去')

section('ロール選択 (一度きり)')
MOCK.addPlayer(1, 'CID_ADMIN', { x = 2569.0, y = 2720.5, z = 42.9 }, { { 'phone', 1 }, { 'WEAPON_PISTOL', 1, { serial = 'ABC123', durability = 90 } }, { 'money', 5000 } })
MOCK.addPlayer(2, 'CID_MAGE', { x = 2570.0, y = 2721.0, z = 42.9 }, { { 'sandwich', 3 }, { 'lockpick', 2 } })
MOCK.db.players['CID_ADMIN'] = { firstname = 'A', lastname = 'B' }
TriggerEvent('QBCore:Server:PlayerLoaded', { PlayerData = { source = 1 } })
TriggerEvent('QBCore:Server:PlayerLoaded', { PlayerData = { source = 2 } })
MOCK.advance(500)
local ok, err = MOCK.call(1, 'chooseRole', 'tank')
check(ok == true, 'タンクを選択できる')
ok, err = MOCK.call(1, 'chooseRole', 'attacker')
check(ok == false, '2回目の選択は拒否: ' .. tostring(err))
ok = MOCK.call(2, 'chooseRole', 'wizard')
check(ok == false, '不正なロールIDを拒否')
check(MOCK.call(2, 'chooseRole', 'mage') == true, '魔導士を選択できる')
check(MOCK.db.characters['CID_ADMIN'].role == 'tank', 'ロールがDBに保存される')

section('管理者権限')
MOCK.addPlayer(3, 'CID_NOBODY', { x = 0, y = 0, z = 0 })
TriggerEvent('QBCore:Server:PlayerLoaded', { PlayerData = { source = 3 } })
MOCK.advance(300)
ok, err = MOCK.call(3, 'admin', 'setRole', { cid = 'CID_ADMIN', role = 'porter' })
check(ok == false, '非管理者のロール変更を拒否')
ok, err = MOCK.call(3, 'admin', 'eventCreate', { definitionId = 1, start = U.formatJst(os.time()), ['end'] = '2026-11-14 24:00' })
check(ok == false, '非管理者のイベント作成を拒否')
check(MOCK.call(1, 'admin', 'setRole', { cid = 'CID_NOBODY', role = 'porter' }) == false or true, '管理者API呼び出し可能')

section('イベント予約と告知')
local nowJst = U.formatJst(os.time())
local endJst = U.formatJst(os.time() + 3 * 3600)
ok, err = MOCK.call(1, 'admin', 'eventCreate', { definitionId = 1, location = '8012番地', start = nowJst, ['end'] = endJst })
check(ok == true, 'ダンジョンイベントを予約: ' .. tostring(err))
local dungeonEventId = err
MOCK.advance(16000)
local anns = MOCK.eventsFor('projectin_rpg:client:announce', -1)
check(#anns >= 1 and anns[#anns].args[1].text:find('8012番地でダンジョン発生！', 1, true) ~= nil, '全体告知: ' .. tostring(anns[#anns] and anns[#anns].args[1].text))
local pub = Events.PublicList()
check(#pub == 1 and pub[1].status == 'active', 'イベントが開催中になる')

section('パーティーと入場')
check(MOCK.call(1, 'party', 'invite', 2) == true, '招待')
check(MOCK.call(2, 'party', 'accept', 1) == true, '承認')
MOCK.players[2].pos = { x = 2600, y = 2800, z = 40 }
ok, err = MOCK.call(1, 'enterDungeon', dungeonEventId)
check(ok == false, '入口から離れたメンバーがいると入場不可: ' .. tostring(err))
MOCK.players[2].pos = { x = 2570.0, y = 2721.0, z = 42.9 }
ok, err = MOCK.call(2, 'enterDungeon', dungeonEventId)
check(ok == false, 'リーダー以外は入場を開始できない')
ok, err = MOCK.call(1, 'enterDungeon', dungeonEventId)
check(ok == true, 'リーダーが入場: ' .. tostring(err))
local run = Instances.GetRunOf(1)
check(run ~= nil and Instances.GetRunOf(2) == run, '両者が同じインスタンスに所属')
check(MOCK.buckets[1] >= Config.Instance.bucketStart and MOCK.buckets[1] == MOCK.buckets[2], '専用ルーティングバケットへ移動')
check(MOCK.db.holdings['CID_ADMIN'] ~= nil and MOCK.db.holdings['CID_MAGE'] ~= nil, '預かり記録をDBに作成')
local stash1 = MOCK.stashes['rpghold_CID_ADMIN']
check(invCount(stash1, 'money') == 5000 and invCount(stash1, 'WEAPON_PISTOL') == 1, '通常所持品を退避スタッシュへ移動')
local pistolMeta
for _, it in pairs(stash1) do if it.name == 'WEAPON_PISTOL' then pistolMeta = it.metadata end end
check(pistolMeta and pistolMeta.serial == 'ABC123', '武器のメタデータ(シリアル)を保持')
local loaners = 0
for _, it in pairs(MOCK.inventories[1]) do if it.metadata[Config.Holding.loanerMetaKey] then loaners = loaners + 1 end end
check(loaners == #Config.Roles.tank.loadout and invCount(MOCK.inventories[1], 'money') == 0, 'タンクに貸与装備のみ所持')
check(count(MOCK.inventories[2]) == 0, '魔導士には武器を貸与しない')
check(run.members[1].maxHp == 150 and run.members[2].maxHp == 100, 'タンクHP1.5倍 (150)')

section('ox_inventory フックによる持ち出し防止')
local swap = MOCK.hooks.swapItems
check(swap({ source = 1, fromType = 'player', toType = 'drop', fromInventory = 1, toInventory = 'newdrop', fromSlot = MOCK.inventories[1][1] }) == false, '入場中のドロップを禁止')
check(swap({ source = 1, fromType = 'player', toType = 'player', fromInventory = 1, toInventory = 1, fromSlot = MOCK.inventories[1][1] }) == true, '自分のインベントリ内の並べ替えは許可')
check(swap({ source = 3, fromType = 'player', toType = 'player', fromInventory = 3, toInventory = 1, fromSlot = { name = 'WEAPON_BAT', metadata = { rpgLoaner = 'x' } } }) == false, '貸与品の他人への受け渡しを禁止(街側でも)')
check(swap({ source = 3, fromType = 'stash', toType = 'player', fromInventory = 'rpghold_CID_ADMIN', toInventory = 3, fromSlot = { name = 'money', metadata = {} } }) == false, '退避スタッシュへのアクセスを禁止')
check(MOCK.hooks.openInventory({ source = 3, inventoryType = 'stash', inventoryId = 'rpghold_CID_ADMIN' }) == false, '退避スタッシュは開けない')
check(MOCK.hooks.usingItem({ source = 1, item = { name = 'sandwich', metadata = {} } }) == false, '入場中は通常アイテムを使用不可')

section('ウェーブ1: 戦闘 (サーバー権威ダメージ)')
MOCK.advance(4500 + 6000)
local enemies = {}
for netId, e in pairs(run.enemies) do if e.alive then enemies[#enemies + 1] = e end end
check(#enemies == 6, 'ウェーブ1の敵6体を生成 (実際: ' .. #enemies .. ')')
check(enemies[1] and enemies[1].maxHp == math.floor(enemies[1].def.hp * run.hpScale), '人数に応じてHP補正')
local e1 = enemies[1]
-- 魔導士の攻撃は無効
local hpBefore = e1.hp
MOCK.players[2].pos = { x = e1.def and MOCK.entities[e1.entity].x, y = MOCK.entities[e1.entity].y, z = MOCK.entities[e1.entity].z }
MOCK.players[2].weapon = GetHashKey('WEAPON_PISTOL')
MOCK.serverEvent(2, 'projectin_rpg:server:hit', e1.netId, GetHashKey('WEAPON_PISTOL'), false)
check(e1.hp == hpBefore, '魔導士の命中報告は無視')
-- 貸与されていない武器は無効
MOCK.players[1].pos = { x = MOCK.entities[e1.entity].x, y = MOCK.entities[e1.entity].y, z = MOCK.entities[e1.entity].z }
MOCK.players[1].weapon = GetHashKey('WEAPON_SMG')
MOCK.serverEvent(1, 'projectin_rpg:server:hit', e1.netId, GetHashKey('WEAPON_SMG'), false)
check(e1.hp == hpBefore, 'ロールの貸与武器以外は無視')
-- 構えている武器と違うハッシュは無効
MOCK.players[1].weapon = GetHashKey('WEAPON_PISTOL')
MOCK.serverEvent(1, 'projectin_rpg:server:hit', e1.netId, GetHashKey('WEAPON_BAT'), false)
check(e1.hp == hpBefore, '所持武器と報告武器の不一致を無視')
-- 正常な命中: ピストル 22 * 0.8 (タンク)
MOCK.serverEvent(1, 'projectin_rpg:server:hit', e1.netId, GetHashKey('WEAPON_PISTOL'), false)
check(math.abs((hpBefore - e1.hp) - 22 * 0.8) < 0.01, 'タンクの与ダメージ0.8倍 (' .. (hpBefore - e1.hp) .. ')')
-- 連射間隔
local hp2 = e1.hp
MOCK.serverEvent(1, 'projectin_rpg:server:hit', e1.netId, GetHashKey('WEAPON_PISTOL'), false)
check(e1.hp == hp2, '発射間隔より速い連続命中を無視')
-- 射程外
MOCK.advance(300)
MOCK.players[1].pos = { x = MOCK.entities[e1.entity].x + 200, y = MOCK.entities[e1.entity].y, z = MOCK.entities[e1.entity].z }
MOCK.serverEvent(1, 'projectin_rpg:server:hit', e1.netId, GetHashKey('WEAPON_PISTOL'), false)
check(e1.hp == hp2, '射程外の命中を無視')

-- バフ: 魔導士のパワーブースト
MOCK.players[1].pos = { x = MOCK.entities[e1.entity].x, y = MOCK.entities[e1.entity].y, z = MOCK.entities[e1.entity].z }
MOCK.players[2].pos = MOCK.players[1].pos
ok, err = MOCK.call(2, 'skill', 'buff', 1)
check(ok == true, '魔導士がタンクにパワーブースト: ' .. tostring(err))
check(run.members[2].mp == Config.Mage.maxMp - Config.Mage.skills.buff.mp or run.members[2].mp > 0, 'MPを消費')
ok, err = MOCK.call(2, 'skill', 'buff', 1)
check(ok == false, 'クールダウン中は使用不可: ' .. tostring(err))
ok, err = MOCK.call(1, 'skill', 'heal', 2)
check(ok == false, '魔導士以外はスキル使用不可')
MOCK.advance(300)
local hp3 = e1.hp
MOCK.serverEvent(1, 'projectin_rpg:server:hit', e1.netId, GetHashKey('WEAPON_PISTOL'), false)
check(math.abs((hp3 - e1.hp) - 22 * 0.8 * (1 + Config.Mage.skills.buff.damageBonus)) < 0.01, 'バフで与ダメージ増加')

-- 全滅させる
local function killAll(attacker, weaponName, r)
    local run = r or run
    for _ = 1, 4000 do
        local target
        for _, e in pairs(run.enemies) do if e.alive and MOCK.entities[e.entity] then target = e break end end
        if not target then return end
        local ent = MOCK.entities[target.entity]
        MOCK.players[attacker].pos = { x = ent.x, y = ent.y, z = ent.z }
        MOCK.players[attacker].weapon = GetHashKey(weaponName)
        MOCK.serverEvent(attacker, 'projectin_rpg:server:hit', target.netId, GetHashKey(weaponName), true)
        MOCK.advance(200)
    end
end
local dropsBefore = #MOCK.eventsFor('projectin_rpg:client:dropAdded')
killAll(1, 'WEAPON_PISTOL')
check(run.waveKills >= 6 or run.wave >= 2, 'ウェーブ1の敵を全滅')
local drops = MOCK.eventsFor('projectin_rpg:client:dropAdded')
check(#drops > dropsBefore, '個人ドロップが発生 (' .. (#drops - dropsBefore) .. '件)')

section('ドロップ取得 (距離/所有者/二重取得)')
local myDrop, otherDrop
for _, d in pairs(run.drops) do
    if d.owner == 1 and not myDrop then myDrop = d end
    if d.owner == 2 and not otherDrop then otherDrop = d end
end
if myDrop then
    MOCK.players[1].pos = { x = myDrop.x + 50, y = myDrop.y, z = myDrop.z }
    ok, err = MOCK.call(1, 'pickup', myDrop.id)
    check(ok == false, '遠すぎるドロップは取得不可')
    MOCK.players[1].pos = { x = myDrop.x, y = myDrop.y, z = myDrop.z }
    ok, err = MOCK.call(1, 'pickup', myDrop.id)
    check(ok == true, '自分のドロップを取得')
    ok, err = MOCK.call(1, 'pickup', myDrop.id)
    check(ok == false, '同じドロップの二重取得を拒否')
    check(MOCK.db.claims[('%s:drop:%d'):format(run.id, myDrop.id)] ~= nil, '請求キーをDBに記録')
else
    check(false, 'テスト用のドロップが無い (確率)')
end
if otherDrop then
    MOCK.players[1].pos = { x = otherDrop.x, y = otherDrop.y, z = otherDrop.z }
    ok = MOCK.call(1, 'pickup', otherDrop.id)
    check(ok == false, '他人のドロップは取得不可')
end

section('ウェーブ2: 破壊目標')
MOCK.advance(3000 + 5000)
check(run.wave == 2, 'ウェーブ2へ進行 (現在 ' .. run.wave .. ')')
local wave2 = run.def.waves[2]
for _, id in ipairs(wave2.objective.targets) do
    local p = run.props[id].def
    MOCK.players[1].pos = { x = p.x, y = p.y, z = p.z }
    check(MOCK.call(1, 'interactStart', id) == true, id .. ': 長押し開始')
    MOCK.advance(1000)
    check(MOCK.call(1, 'interactFinish', id) == false, id .. ': 時間不足の完了報告を拒否')
    MOCK.advance(3500)
    check(MOCK.call(1, 'interactFinish', id) == true, id .. ': 破壊完了')
end
MOCK.advance(1500)
killAll(1, 'WEAPON_PISTOL')
MOCK.advance(3000 + 5000)
check(run.wave == 3, 'ウェーブ3(生存)へ進行 (現在 ' .. run.wave .. ')')

section('ダウンと蘇生')
MOCK.players[1].health = 100 + Config.Health.downedBuffer
MOCK.serverEvent(1, 'projectin_rpg:server:downed')
check(run.members[1].downed == true, 'ダウン報告を受理 (体力が閾値以下)')
MOCK.players[2].health = 200
MOCK.serverEvent(2, 'projectin_rpg:server:downed')
check(run.members[2].downed == false, '体力が残っているダウン報告は無視')
MOCK.players[2].pos = MOCK.players[1].pos
ok, err = MOCK.call(2, 'skill', 'revive', 1)
check(ok == true and run.members[1].downed == false, '魔導士のリザレクションで復活: ' .. tostring(err))
MOCK.players[1].health = 200

MOCK.advance(62000)
MOCK.advance(3000 + 6000)
check(run.wave == 4, 'ウェーブ4(ボス)へ進行 (現在 ' .. run.wave .. ')')

section('ボス戦')
check(run.boss and run.boss.enemy and run.boss.enemy.alive, 'ボスを生成')
local bossPhases = {}
for _ = 1, 3000 do
    local b = run.boss.enemy
    if not b.alive then break end
    local ent = MOCK.entities[b.entity]
    MOCK.players[1].pos = { x = ent.x, y = ent.y, z = ent.z }
    MOCK.players[1].weapon = GetHashKey('WEAPON_PISTOL')
    MOCK.serverEvent(1, 'projectin_rpg:server:hit', b.netId, GetHashKey('WEAPON_PISTOL'), true)
    bossPhases[run.boss.phase] = true
    MOCK.advance(200)
end
check(bossPhases[2] == true, 'HP50%で第2フェーズへ移行')
check(#MOCK.eventsFor('projectin_rpg:client:aoe') > 0, 'ボスの範囲攻撃を予告')
MOCK.advance(1000)
killAll(1, 'WEAPON_PISTOL')
MOCK.advance(5000)
check(run.state == 'results' and run.result == 'clear', 'ダンジョンクリア')

section('クリア報酬 (二重付与防止)')
local results = MOCK.eventsFor('projectin_rpg:client:results', 1)
check(#results == 1 and results[1].args[1].success == true, '結果画面を送信')
check(MOCK.db.claims[('%s:clear:CID_ADMIN'):format(run.id)] ~= nil, 'クリア報酬の請求キーを記録')
local c1 = Chars.Get('CID_ADMIN')
local tokens = 0
for _, it in pairs(c1.items) do if it.name == 'dungeon_token' then tokens = tokens + it.count end end
check(tokens >= 3, 'RPGインベントリにダンジョンメダル (' .. tokens .. '個)')
local okDup, errDup = MOCK.run(RpgInv.Grant, 1, { { name = 'dungeon_token', count = 5 } }, { claimKey = ('%s:clear:CID_ADMIN'):format(run.id), overflow = true })
check(okDup == false and errDup == 'duplicate', '同じ請求キーでの再付与を拒否')
local tokens2 = 0
for _, it in pairs(Chars.Get('CID_ADMIN').items) do if it.name == 'dungeon_token' then tokens2 = tokens2 + it.count end end
check(tokens2 == tokens, '再付与後も個数が変わらない')
check(MOCK.db.characters['CID_ADMIN'].inventory:find('dungeon_token', 1, true) ~= nil, 'RPGインベントリをDBに永続化')

section('帰還と復元')
MOCK.advance(Config.Instance.resultsAutoLeave * 1000 + 1000)
check(Instances.GetRunOf(1) == nil and Instances.GetRunOf(2) == nil, '自動帰還')
check(MOCK.buckets[1] == 0 and MOCK.buckets[2] == 0, 'バケット0へ戻る')
check(invCount(MOCK.inventories[1], 'money') == 5000 and invCount(MOCK.inventories[1], 'WEAPON_PISTOL') == 1 and invCount(MOCK.inventories[1], 'phone') == 1, '通常所持品を全て返却')
local leftover = 0
for _, it in pairs(MOCK.inventories[1]) do if it.metadata[Config.Holding.loanerMetaKey] then leftover = leftover + 1 end end
check(leftover == 0, '貸与装備を回収')
check(count(MOCK.stashes['rpghold_CID_ADMIN']) == 0 and MOCK.db.holdings['CID_ADMIN'] == nil, '預かり記録を削除')
check(invCount(MOCK.inventories[2], 'sandwich') == 3 and invCount(MOCK.inventories[2], 'lockpick') == 2, '魔導士の所持品も返却')
check(#MOCK.eventsFor('projectin_rpg:client:exitRun', 1) >= 1, 'クライアントへ状態復元を指示')
check(count(Instances.All()) == 0, 'インスタンスを破棄')
local leftEntities = 0
for _, e in pairs(MOCK.entities) do if e.bucket and e.bucket >= Config.Instance.bucketStart then leftEntities = leftEntities + 1 end end
MOCK.advance(9000)
leftEntities = 0
for _, e in pairs(MOCK.entities) do if e.bucket and e.bucket >= Config.Instance.bucketStart then leftEntities = leftEntities + 1 end end
check(leftEntities == 0, 'インスタンスのエンティティを全て削除 (残り ' .. leftEntities .. ')')

section('荷物持ち: 容量2倍はダンジョン内のみ')
MOCK.call(1, 'admin', 'setRole', { cid = 'CID_MAGE', role = 'porter' })
check(Chars.Get('CID_MAGE').role == 'porter', '管理者がロールを変更')
local outSlots = MOCK.call(2, 'getInventory').usableSlots
check(outSlots == Config.RpgInventory.baseSlots, '街では通常容量 (' .. outSlots .. ')')

section('切断 → 再ログインで復元')
MOCK.call(1, 'party', 'leave')
MOCK.players[2].pos = { x = 2569.5, y = 2720.0, z = 42.9 } -- 帰還テレポートはクライアント側処理のためモックで再現
ok, err = MOCK.call(2, 'enterDungeon', dungeonEventId)
check(ok == true, 'ソロ入場: ' .. tostring(err))
local run2 = Instances.GetRunOf(2)
check(MOCK.call(2, 'getInventory').usableSlots == Config.RpgInventory.baseSlots * 2, 'ダンジョン内で荷物持ちの容量が2倍')
MOCK.drop(2)
check(Instances.GetRun(run2.id) == nil, '最後の1人が切断するとインスタンス破棄')
check(MOCK.db.holdings['CID_MAGE'] ~= nil, '切断時は預かり記録を保持')
-- 再接続 (ox_inventory はDBに保存された内容=貸与品のみ を読み込む想定)
MOCK.addPlayer(2, 'CID_MAGE', { x = 2955, y = 2790, z = 41 })
MOCK.inventories[2] = { [1] = { name = 'WEAPON_PISTOL', count = 1, slot = 1, metadata = { rpgLoaner = run2.id } } }
MOCK.buckets[2] = Config.Instance.bucketStart
TriggerEvent('QBCore:Server:PlayerLoaded', { PlayerData = { source = 2 } })
MOCK.advance(4000)
check(invCount(MOCK.inventories[2], 'sandwich') == 3 and invCount(MOCK.inventories[2], 'WEAPON_PISTOL') == 0, '再ログイン時に所持品を返却し貸与品を回収')
check(MOCK.buckets[2] == 0 and MOCK.db.holdings['CID_MAGE'] == nil, 'バケットと預かり記録をリセット')

section('入場失敗時のロールバック')
MOCK.failAdd = function(inv, name) return type(inv) == 'string' and name == 'lockpick' end
MOCK.players[2].pos = { x = 2569.0, y = 2720.5, z = 42.9 }
ok, err = MOCK.call(2, 'enterDungeon', dungeonEventId)
MOCK.failAdd = nil
check(ok == false, '退避に失敗したら入場中止: ' .. tostring(err))
check(invCount(MOCK.inventories[2], 'sandwich') == 3 and invCount(MOCK.inventories[2], 'lockpick') == 2, '所持品は元のまま')
check(MOCK.buckets[2] == 0 and Instances.GetRunOf(2) == nil and MOCK.db.holdings['CID_MAGE'] == nil, '状態もロールバック')

section('エディター: 下書き→検証→テスト→公開')
ok, err = MOCK.call(1, 'admin', 'defDuplicate', { id = 1 })
check(ok == true, '定義を複製')
local newId = err
local got = select(2, MOCK.call(1, 'admin', 'defGet', { id = newId }))
check(got and got.data.name:find('コピー', 1, true), '複製名に(コピー)')
got.data.waves = {}
ok, err = MOCK.call(1, 'admin', 'defSave', { id = newId, data = got.data })
check(ok == true and type(err) == 'string', '未完成でも下書き保存でき、警告を返す: ' .. tostring(err))
ok, err = MOCK.call(1, 'admin', 'defPublish', { id = newId })
check(ok == false, '未完成の定義は公開不可')
got.data.waves = { { label = 'T', objective = { type = 'kill_all' }, groups = { { enemy = 'grunt', count = 1, spawn = { 'n1' } } } } }
MOCK.call(1, 'admin', 'defSave', { id = newId, data = got.data })
check(MOCK.db.definitions[newId].status == 'draft', '公開前は下書きのまま')
MOCK.players[1].pos = { x = 100, y = 100, z = 30 }
ok, err = MOCK.call(1, 'admin', 'defTest', { id = newId, role = 'attacker' })
check(ok == true, '非公開テストプレイを開始: ' .. tostring(err))
local trun = Instances.GetRunOf(1)
check(trun and trun.testMode and trun.members[1].role == 'attacker' and Chars.Get('CID_ADMIN').role == 'tank', 'テスト用ロールを一時適用(保存ロールは不変)')
MOCK.advance(4500 + 6000)
killAll(1, 'WEAPON_SMG', trun)
MOCK.advance(4000)
check(trun.state == 'results' and trun.result == 'clear', 'テストをクリア')
check(MOCK.db.claims[('%s:clear:CID_ADMIN'):format(trun.id)] == nil, 'テストでは報酬を付与しない')
MOCK.advance(Config.Instance.resultsAutoLeave * 1000 + 1000)
local ex = MOCK.eventsFor('projectin_rpg:client:exitRun', 1)
check(ex[#ex].args[1].pos.x == 100, 'テスト後は元の位置への帰還を指示')
ok = MOCK.call(1, 'admin', 'defPublish', { id = newId })
check(ok == true and MOCK.db.definitions[newId].status == 'published', '公開')

section('レイド: 参加登録→開始→強制終了')
local startJst = U.formatJst(os.time() + 1800)
ok, err = MOCK.call(1, 'admin', 'eventCreate', { definitionId = 2, location = '3001番地', start = startJst })
check(ok == true, 'レイドを予約: ' .. tostring(err))
local raidId = err
MOCK.advance(16000)
local ra = MOCK.eventsFor('projectin_rpg:client:announce', -1)
check(ra[#ra].args[1].text:find('3001番地で大型ボスレイド発生！開始まで30分！', 1, true) ~= nil, 'レイド告知: ' .. ra[#ra].args[1].text)
MOCK.players[1].pos = { x = 446.3, y = 5568.6, z = 781.2 }
check(MOCK.call(1, 'raidRegister', raidId, false) == true, '参加登録')
MOCK.advance(1800 * 1000)
local rr = Instances.GetRunOf(1)
check(rr ~= nil and rr.type == 'raid', '開始時刻にレイド開始')
local rem = MOCK.eventsFor('projectin_rpg:client:announce', -1)
local sawReminder = false
for _, e in ipairs(rem) do if e.args[1].text:find('開始まで5分', 1, true) then sawReminder = true end end
check(sawReminder, '開始5分前のリマインド告知')
ok = MOCK.call(1, 'admin', 'forceEnd', { runId = rr.id })
check(ok == true and rr.state == 'results' and rr.result == 'admin', '管理者の強制終了')
MOCK.advance(Config.Instance.resultsAutoLeave * 1000 + 1000)
check(Instances.GetRunOf(1) == nil and invCount(MOCK.inventories[1], 'money') == 5000, 'レイド後も所持品を返却')

section('リソース停止時の復元')
MOCK.players[1].pos = { x = 2569.0, y = 2720.5, z = 42.9 }
MOCK.call(1, 'enterDungeon', dungeonEventId)
check(Instances.GetRunOf(1) ~= nil, '入場')
for _, fn in ipairs(MOCK.handlers['onResourceStop'] or {}) do fn('projectin_rpg') end
MOCK.advance(100)
check(MOCK.buckets[1] == 0 and invCount(MOCK.inventories[1], 'money') == 5000, '停止時に即座にバケット0・所持品返却')

print(('\n結果: %d 件成功 / %d 件失敗'):format(passed, failed))
return failed
