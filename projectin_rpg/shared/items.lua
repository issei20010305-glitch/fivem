--[[
    RPGアイテム定義
    これらは ox_inventory のアイテムではありません。RPGインベントリ専用で、
    街の通常インベントリ/経済には一切出入りしません。
    rarity: common / uncommon / rare / epic / legendary
    use: ダンジョン内でのみ使用可能な効果 (サーバーで処理)
]]

RPG = RPG or {}
RPG.Items = {
    -- 素材
    slime_gel       = { label = 'スライムジェル',   weight = 100,  stack = 99, rarity = 'common',   icon = '💧', description = 'ぷるぷるした粘液。' },
    iron_scrap      = { label = '鉄くず',           weight = 300,  stack = 99, rarity = 'common',   icon = '🔩', description = '採石場の機械から剥がれた鉄片。' },
    quartz_shard    = { label = '石英の欠片',       weight = 200,  stack = 99, rarity = 'uncommon', icon = '🔹', description = 'ほのかに光る結晶片。' },
    cursed_crystal  = { label = '呪われた結晶',     weight = 400,  stack = 50, rarity = 'rare',     icon = '🔮', description = '魔窟の核から採れる不吉な結晶。' },
    beast_fang      = { label = '巨獣の牙',         weight = 800,  stack = 20, rarity = 'rare',     icon = '🦷', description = '山頂の巨獣から得られる鋭い牙。' },
    titan_core      = { label = 'タイタンコア',     weight = 1500, stack = 10, rarity = 'epic',     icon = '🟠', description = '大型ボスの心臓部。強大な力を秘める。' },
    summit_crown    = { label = '山頂の王冠',       weight = 2000, stack = 1,  rarity = 'legendary',icon = '👑', description = '大型ボスレイドの最高報酬。' },
    -- 消耗品 (ダンジョン内でのみ使用可能)
    potion_small    = { label = '回復薬(小)',       weight = 150,  stack = 20, rarity = 'common',   icon = '🧪', description = 'HPを25%回復。', use = { type = 'heal', pct = 0.25, cooldown = 5 } },
    potion_large    = { label = '回復薬(大)',       weight = 300,  stack = 10, rarity = 'uncommon', icon = '⚗', description = 'HPを60%回復。', use = { type = 'heal', pct = 0.60, cooldown = 10 } },
    ether           = { label = 'エーテル',         weight = 150,  stack = 20, rarity = 'uncommon', icon = '🔷', description = 'MPを50回復(魔導士専用)。', use = { type = 'mp', amount = 50, cooldown = 8 } },
    -- 記念品
    dungeon_token   = { label = 'ダンジョンメダル', weight = 10,   stack = 999, rarity = 'uncommon', icon = '🏅', description = 'ダンジョン踏破の証。' },
    raid_token      = { label = 'レイドメダル',     weight = 10,   stack = 999, rarity = 'rare',     icon = '🎖', description = 'レイド討伐の証。' },
}

RPG.RarityLabel = {
    common = 'コモン', uncommon = 'アンコモン', rare = 'レア', epic = 'エピック', legendary = 'レジェンダリー',
}
