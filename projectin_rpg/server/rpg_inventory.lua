--[[
    RPG専用インベントリ
    - ox_inventory とは完全に独立 (アイテムは街に一切出ない)
    - 追加は常に「請求キー(claim_key)」付きのDBトランザクションで行い、二重付与を防止
]]
RpgInv = {}
local Items = RPG.Items

function RpgInv.Capacity(src, c)
    local mult = 1.0
    local run = src and Instances.GetRunOf(src)
    if run and run.state ~= 'ended' then
        local role = c and c.role and Config.Roles[c.role]
        mult = role and role.inventoryMult or 1.0
    end
    return math.floor(Config.RpgInventory.baseSlots * mult), math.floor(Config.RpgInventory.baseWeight * mult)
end

local function totalWeight(items)
    local w = 0
    for _, it in pairs(items) do
        local def = Items[it.name]
        if def then w = w + def.weight * it.count end
    end
    return w
end

-- items のコピーへ list を詰める。入りきらない分を返す
local function fit(items, list, slots, maxWeight)
    local copy = {}
    for s, it in pairs(items) do copy[s] = { name = it.name, count = it.count, meta = it.meta } end
    local weight = totalWeight(copy)
    local rest = {}
    for _, entry in ipairs(list) do
        local def = Items[entry.name]
        local remaining = math.floor(entry.count or 0)
        if def and remaining > 0 then
            -- 重量で入る最大数
            local byWeight = def.weight > 0 and math.floor((maxWeight - weight) / def.weight) or remaining
            local canAdd = math.max(0, math.min(remaining, byWeight))
            local added = 0
            -- 既存スタック
            for s = 1, slots do
                if added >= canAdd then break end
                local it = copy[s]
                if it and it.name == entry.name and not it.meta and it.count < def.stack then
                    local n = math.min(def.stack - it.count, canAdd - added)
                    it.count = it.count + n
                    added = added + n
                end
            end
            -- 空きスロット
            for s = 1, slots do
                if added >= canAdd then break end
                if not copy[s] then
                    local n = math.min(def.stack, canAdd - added)
                    copy[s] = { name = entry.name, count = n }
                    added = added + n
                end
            end
            weight = weight + added * def.weight
            if added < remaining then rest[#rest + 1] = { name = entry.name, count = remaining - added } end
        end
    end
    return copy, rest
end

--- アイテム付与
--- @param opts table { claimKey = string(必須), overflow = boolean (入りきらない分を受取箱へ), reason = string }
--- @return boolean ok, string|table errOrResult
function RpgInv.Grant(src, list, opts)
    local cid = Bridge.GetCitizenId(src)
    if not cid then return false, 'no_player' end
    if type(opts) ~= 'table' or type(opts.claimKey) ~= 'string' then return false, 'no_claim' end
    return Chars.WithLock(cid, function()
        local c = Chars.Load(cid)
        local slots, maxWeight = RpgInv.Capacity(src, c)
        local newItems, rest = fit(c.items, list, slots, maxWeight)
        if #rest > 0 and not opts.overflow then return false, 'full' end
        local newOverflow = c.overflow
        if #rest > 0 then
            newOverflow = {}
            for _, o in ipairs(c.overflow) do newOverflow[#newOverflow + 1] = o end
            for _, r in ipairs(rest) do newOverflow[#newOverflow + 1] = r end
        end
        local list2 = {}
        for s, it in pairs(newItems) do list2[#list2 + 1] = { slot = s, name = it.name, count = it.count, meta = it.meta } end
        table.sort(list2, function(a, b) return a.slot < b.slot end)
        local ok = MySQL.transaction.await({
            { query = 'INSERT INTO rpg_claims (claim_key, citizenid, items) VALUES (?, ?, ?)', values = { opts.claimKey, cid, json.encode(list) } },
            { query = 'UPDATE rpg_characters SET inventory = ?, overflow = ? WHERE citizenid = ?', values = { json.encode(list2), json.encode(newOverflow), cid } },
        })
        if not ok then return false, 'duplicate' end
        c.items = newItems
        c.overflow = newOverflow
        TriggerClientEvent('projectin_rpg:client:inventoryChanged', src)
        return true, { overflowed = rest }
    end)
end

function RpgInv.Payload(src)
    local cid = Bridge.GetCitizenId(src)
    if not cid then return nil end
    local c = Chars.Load(cid)
    local slots, maxWeight = RpgInv.Capacity(src, c)
    local baseSlots = Config.RpgInventory.baseSlots
    local items = {}
    local maxSlotUsed = 0
    for s, it in pairs(c.items) do
        local def = Items[it.name]
        if def then
            items[#items + 1] = {
                slot = s, name = it.name, count = it.count, label = def.label, icon = def.icon,
                rarity = def.rarity, rarityLabel = RPG.RarityLabel[def.rarity], weight = def.weight,
                description = def.description, usable = def.use ~= nil,
            }
            if s > maxSlotUsed then maxSlotUsed = s end
        end
    end
    local overflow = {}
    for i, o in ipairs(c.overflow) do
        local def = Items[o.name]
        if def then overflow[#overflow + 1] = { index = i, name = o.name, count = o.count, label = def.label, icon = def.icon, rarity = def.rarity } end
    end
    return {
        slots = math.max(slots, maxSlotUsed), usableSlots = slots, baseSlots = baseSlots,
        maxWeight = maxWeight, weight = totalWeight(c.items), items = items, overflow = overflow,
        inRun = Instances.GetRunOf(src) ~= nil,
    }
end

function RpgInv.Move(src, from, to)
    local cid = Bridge.GetCitizenId(src)
    if not cid then return false end
    from, to = math.floor(tonumber(from) or 0), math.floor(tonumber(to) or 0)
    return Chars.WithLock(cid, function()
        local c = Chars.Load(cid)
        local slots = RpgInv.Capacity(src, c)
        if from < 1 or to < 1 or from == to then return false, '不正なスロット' end
        local a = c.items[from]
        if not a then return false, '移動元が空です' end
        if to > slots and not c.items[to] then return false, 'そのスロットは使用できません' end
        local b = c.items[to]
        if b and b.name == a.name and not a.meta and not b.meta then
            local def = Items[a.name]
            local n = math.min(def.stack - b.count, a.count)
            if n <= 0 then c.items[from], c.items[to] = b, a
            else
                b.count = b.count + n
                a.count = a.count - n
                if a.count <= 0 then c.items[from] = nil end
            end
        else
            c.items[from], c.items[to] = b, a
        end
        Chars.SaveInventory(c)
        return true
    end)
end

local function clampCount(count, max)
    count = tonumber(count) or max
    if count ~= count or count < 1 then count = 1 end
    if count > max then count = max end
    return count
end

function RpgInv.Discard(src, slot, count)
    local cid = Bridge.GetCitizenId(src)
    if not cid then return false end
    slot = math.floor(tonumber(slot) or 0)
    return Chars.WithLock(cid, function()
        local c = Chars.Load(cid)
        local it = c.items[slot]
        if not it then return false, 'アイテムがありません' end
        count = math.floor(clampCount(count, it.count))
        it.count = it.count - count
        if it.count <= 0 then c.items[slot] = nil end
        Chars.SaveInventory(c)
        Bridge.Log(cid, 'rpg_discard', { item = it.name, count = count })
        return true
    end)
end

-- 受取箱からインベントリへ
function RpgInv.ClaimOverflow(src)
    local cid = Bridge.GetCitizenId(src)
    if not cid then return false end
    return Chars.WithLock(cid, function()
        local c = Chars.Load(cid)
        if #c.overflow == 0 then return false, '受取箱は空です' end
        local slots, maxWeight = RpgInv.Capacity(src, c)
        local newItems, rest = fit(c.items, c.overflow, slots, maxWeight)
        c.items = newItems
        c.overflow = rest
        Chars.SaveInventory(c)
        return true, #rest > 0 and '一部のアイテムは容量不足で受け取れませんでした' or nil
    end)
end

-- 消耗品の使用 (ダンジョン内のみ)
local useCooldowns = {}
function RpgInv.Use(src, slot)
    local run = Instances.GetRunOf(src)
    if not run or run.state ~= 'active' then return false, '消耗品はダンジョン/レイド内でのみ使用できます' end
    local member = run.members[src]
    if not member or member.downed then return false, '戦闘不能中は使用できません' end
    local cid = member.cid
    slot = math.floor(tonumber(slot) or 0)
    return Chars.WithLock(cid, function()
        local c = Chars.Load(cid)
        local it = c.items[slot]
        if not it then return false, 'アイテムがありません' end
        local def = Items[it.name]
        if not def or not def.use then return false, 'このアイテムは使用できません' end
        local key = src .. ':' .. def.use.type
        local now = os.time()
        if useCooldowns[key] and useCooldowns[key] > now then
            return false, ('クールダウン中です(残り%d秒)'):format(useCooldowns[key] - now)
        end
        if def.use.type == 'mp' and member.role ~= 'mage' then return false, '魔導士専用のアイテムです' end
        it.count = it.count - 1
        if it.count <= 0 then c.items[slot] = nil end
        Chars.SaveInventory(c)
        useCooldowns[key] = now + (def.use.cooldown or 5)
        if def.use.type == 'heal' then
            Combat.HealMember(run, src, def.use.pct, src)
        elseif def.use.type == 'mp' then
            member.mp = math.min(Config.Mage.maxMp, (member.mp or 0) + def.use.amount)
        end
        Instances.PushParty(run)
        return true, ('%sを使用しました'):format(def.label)
    end)
end

AddEventHandler('playerDropped', function()
    local s = tostring(source)
    for k in pairs(useCooldowns) do
        if k:sub(1, #s + 1) == s .. ':' then useCooldowns[k] = nil end
    end
end)
