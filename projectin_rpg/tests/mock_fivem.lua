--[[
    簡易 FiveM / Qbox / ox_inventory / oxmysql モック (サーバー側ロジック検証用)
    実際のゲームエンジンは再現しません。サーバースクリプトの分岐・状態遷移を確認する目的のものです。
]]
MOCK = { now_ms = 0, epoch = 0, threads = {}, clientEvents = {}, netHandlers = {}, handlers = {}, callbacks = {},
    players = {}, entities = {}, nextEntity = 1000, buckets = {}, states = {}, inventories = {}, stashes = {}, hooks = {}, db = {} }

---------------------------------------------------------------------------
-- JSON (最小実装)
---------------------------------------------------------------------------
json = {}
local function isArray(t)
    local n = 0
    for k in pairs(t) do
        if type(k) ~= 'number' then return false end
        n = n + 1
    end
    for i = 1, n do if t[i] == nil then return false end end
    return true, n
end
local function enc(v)
    local t = type(v)
    if t == 'nil' then return 'null' end
    if t == 'boolean' then return tostring(v) end
    if t == 'number' then
        if v ~= v then return 'null' end
        if math.type(v) == 'integer' or v == math.floor(v) and math.abs(v) < 1e15 then return string.format('%d', v) end
        return string.format('%.6f', v)
    end
    if t == 'string' then return '"' .. v:gsub('[%c"\\]', function(c) return string.format('\\u%04x', c:byte()) end) .. '"' end
    if t == 'table' then
        local arr, n = isArray(v)
        if arr and n > 0 then
            local out = {}
            for i = 1, n do out[i] = enc(v[i]) end
            return '[' .. table.concat(out, ',') .. ']'
        end
        if next(v) == nil then return '[]' end
        local out = {}
        for k, val in pairs(v) do out[#out + 1] = enc(tostring(k)) .. ':' .. enc(val) end
        return '{' .. table.concat(out, ',') .. '}'
    end
    return 'null'
end
json.encode = enc
function json.decode(s)
    local pos = 1
    local function ws() pos = s:find('[^%s]', pos) or #s + 1 end
    local val
    local function str()
        local out = {}
        pos = pos + 1
        while true do
            local c = s:sub(pos, pos)
            if c == '"' then pos = pos + 1 break end
            if c == '\\' then
                local n = s:sub(pos + 1, pos + 1)
                if n == 'u' then out[#out + 1] = utf8.char(tonumber(s:sub(pos + 2, pos + 5), 16)) pos = pos + 6
                else out[#out + 1] = ({ n = '\n', t = '\t', r = '\r' })[n] or n pos = pos + 2 end
            else out[#out + 1] = c pos = pos + 1 end
        end
        return table.concat(out)
    end
    function val()
        ws()
        local c = s:sub(pos, pos)
        if c == '{' then
            local t = {}
            pos = pos + 1 ws()
            if s:sub(pos, pos) == '}' then pos = pos + 1 return t end
            while true do
                ws() local k = str() ws() pos = pos + 1
                t[k] = val() ws()
                local d = s:sub(pos, pos) pos = pos + 1
                if d == '}' then break end
            end
            return t
        elseif c == '[' then
            local t = {}
            pos = pos + 1 ws()
            if s:sub(pos, pos) == ']' then pos = pos + 1 return t end
            while true do
                t[#t + 1] = val() ws()
                local d = s:sub(pos, pos) pos = pos + 1
                if d == ']' then break end
            end
            return t
        elseif c == '"' then return str()
        elseif s:sub(pos, pos + 3) == 'true' then pos = pos + 4 return true
        elseif s:sub(pos, pos + 4) == 'false' then pos = pos + 5 return false
        elseif s:sub(pos, pos + 3) == 'null' then pos = pos + 4 return nil
        else
            local num = s:match('^-?%d+%.?%d*[eE]?[-+]?%d*', pos)
            pos = pos + #num
            return math.tointeger(tonumber(num)) or tonumber(num)
        end
    end
    return val()
end

---------------------------------------------------------------------------
-- ベクトル
---------------------------------------------------------------------------
local vmt = {}
vmt.__index = vmt
vmt.__sub = function(a, b) return vector3(a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)) end
vmt.__add = function(a, b) return vector3(a.x + b.x, a.y + b.y, (a.z or 0) + (b.z or 0)) end
vmt.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + (a.z or 0) * (a.z or 0)) end
function vector3(x, y, z) return setmetatable({ x = x, y = y, z = z or 0 }, vmt) end
function vector2(x, y) return setmetatable({ x = x, y = y, z = 0 }, vmt) end

---------------------------------------------------------------------------
-- スケジューラー (仮想時間)
---------------------------------------------------------------------------
local realTime = os.time
MOCK.epoch = realTime({ year = 2026, month = 11, day = 14, hour = 3, min = 0, sec = 0, isdst = false }) -- おおよそ JST 12:00 前後
os.time = function(t) if t then return realTime(t) end return MOCK.epoch + MOCK.now_ms // 1000 end
function GetGameTimer() return MOCK.now_ms end
function CreateThread(fn)
    local co = coroutine.create(fn)
    table.insert(MOCK.threads, { co = co, wake = MOCK.now_ms })
end
Citizen = { CreateThread = CreateThread }
function Wait(ms)
    local co, main = coroutine.running()
    if main then error('Wait() called outside thread') end
    coroutine.yield(ms or 0)
end
function SetTimeout(ms, fn) CreateThread(function() Wait(ms) fn() end) end

function MOCK.step()
    local ran = false
    local list = MOCK.threads
    MOCK.threads = {}
    local keep = {}
    for _, t in ipairs(list) do
        if t.wake <= MOCK.now_ms then
            ran = true
            local ok, res = coroutine.resume(t.co)
            if not ok then error('thread error: ' .. tostring(res) .. '\n' .. debug.traceback(t.co)) end
            if coroutine.status(t.co) ~= 'dead' then t.wake = MOCK.now_ms + math.max(0, res or 0) keep[#keep + 1] = t end
        else
            keep[#keep + 1] = t
        end
    end
    for _, t in ipairs(MOCK.threads) do keep[#keep + 1] = t end
    MOCK.threads = keep
    return ran
end
function MOCK.advance(ms)
    local target = MOCK.now_ms + ms
    local guard = 0
    while true do
        while MOCK.step() do guard = guard + 1 if guard > 200000 then error('scheduler runaway') end end
        local nextWake
        for _, t in ipairs(MOCK.threads) do if not nextWake or t.wake < nextWake then nextWake = t.wake end end
        if not nextWake or nextWake > target then break end
        MOCK.now_ms = math.max(MOCK.now_ms, nextWake)
    end
    MOCK.now_ms = target
    while MOCK.step() do end
end
-- 現在のコルーチン外から await を伴う処理を同期的に実行
function MOCK.run(fn, ...)
    local args = table.pack(...)
    local result
    local done = false
    CreateThread(function() result = table.pack(fn(table.unpack(args, 1, args.n))) done = true end)
    local guard = 0
    while not done do
        MOCK.advance(10)
        guard = guard + 1
        if guard > 100000 then error('MOCK.run timeout') end
    end
    return table.unpack(result, 1, result.n)
end

---------------------------------------------------------------------------
-- イベント
---------------------------------------------------------------------------
source = nil
function RegisterNetEvent(name, fn) if fn then MOCK.netHandlers[name] = MOCK.netHandlers[name] or {} table.insert(MOCK.netHandlers[name], fn) end end
function AddEventHandler(name, fn) MOCK.handlers[name] = MOCK.handlers[name] or {} table.insert(MOCK.handlers[name], fn) end
function TriggerEvent(name, ...)
    for _, fn in ipairs(MOCK.handlers[name] or {}) do fn(...) end
    for _, fn in ipairs(MOCK.netHandlers[name] or {}) do fn(...) end
end
function MOCK.serverEvent(src, name, ...)
    local args = table.pack(...)
    local fns = MOCK.netHandlers[name] or {}
    for _, fn in ipairs(fns) do
        CreateThread(function() source = src fn(table.unpack(args, 1, args.n)) end)
    end
    MOCK.advance(0)
end
function MOCK.drop(src)
    for _, fn in ipairs(MOCK.handlers['playerDropped'] or {}) do
        CreateThread(function() source = src fn('disconnect') end)
    end
    MOCK.advance(0)
    MOCK.players[src] = nil
end
function TriggerClientEvent(name, target, ...)
    table.insert(MOCK.clientEvents, { name = name, target = target, args = table.pack(...) })
end
function MOCK.eventsFor(name, target)
    local out = {}
    for _, e in ipairs(MOCK.clientEvents) do
        if e.name == name and (target == nil or e.target == target or e.target == -1) then out[#out + 1] = e end
    end
    return out
end
function RegisterCommand() end
function GetCurrentResourceName() return 'projectin_rpg' end
function GetResourceState() return 'started' end
function print(...) local t = {} for i = 1, select('#', ...) do t[#t + 1] = tostring(select(i, ...)) end io.write((table.concat(t, '\t'):gsub('%^%d', '')), '\n') end

---------------------------------------------------------------------------
-- ハッシュ
---------------------------------------------------------------------------
function GetHashKey(s)
    s = s:lower()
    local h = 0
    for i = 1, #s do
        h = (h + s:byte(i)) & 0xFFFFFFFF
        h = (h + (h << 10)) & 0xFFFFFFFF
        h = h ~ (h >> 6)
    end
    h = (h + (h << 3)) & 0xFFFFFFFF
    h = h ~ (h >> 11)
    h = (h + (h << 15)) & 0xFFFFFFFF
    if h >= 0x80000000 then h = h - 0x100000000 end
    return h
end

---------------------------------------------------------------------------
-- プレイヤー / エンティティ / バケット
---------------------------------------------------------------------------
local function stateBag(key)
    MOCK.states[key] = MOCK.states[key] or {}
    local data = MOCK.states[key]
    return setmetatable({ set = function(self, k, v) data[k] = v end }, { __index = function(_, k) return data[k] end })
end
function Player(src) return { state = stateBag('player:' .. src) } end
function Entity(e) return { state = stateBag('entity:' .. e) } end

function MOCK.addPlayer(src, cid, pos, items)
    MOCK.players[src] = { src = src, cid = cid, pos = pos, health = 200, armour = 50, weapon = GetHashKey('WEAPON_UNARMED'),
        ped = 500 + src, firstname = '太郎' .. src, lastname = 'テスト' }
    MOCK.buckets[src] = 0
    MOCK.inventories[src] = {}
    for i, it in ipairs(items or {}) do MOCK.inventories[src][i] = { name = it[1], count = it[2], slot = i, metadata = it[3] or {} } end
end
function GetPlayers() local t = {} for s in pairs(MOCK.players) do t[#t + 1] = tostring(s) end return t end
function GetPlayerName(src) return MOCK.players[src] and ('player' .. src) or nil end
function GetPlayerPed(src) return MOCK.players[src] and MOCK.players[src].ped or 0 end
local function pedOwner(ped) for _, p in pairs(MOCK.players) do if p.ped == ped then return p end end end
function GetEntityCoords(e)
    local p = pedOwner(e)
    if p then return vector3(p.pos.x, p.pos.y, p.pos.z) end
    local ent = MOCK.entities[e]
    if ent then return vector3(ent.x, ent.y, ent.z) end
    return vector3(0, 0, 0)
end
function GetEntityHealth(e)
    local p = pedOwner(e)
    if p then return p.health end
    local ent = MOCK.entities[e]
    return ent and ent.health or 0
end
function GetPedArmour(e) local p = pedOwner(e) return p and p.armour or 0 end
function GetEntityHeading() return 0.0 end
function GetSelectedPedWeapon(e) local p = pedOwner(e) return p and p.weapon or 0 end
function GetVehiclePedIsIn() return 0 end
function SetEntityCoords(e, x, y, z) local p = pedOwner(e) if p then p.pos = { x = x, y = y, z = z } end end
function SetPlayerRoutingBucket(src, b) MOCK.buckets[src] = b end
function GetPlayerRoutingBucket(src) return MOCK.buckets[src] or 0 end
function SetRoutingBucketPopulationEnabled() end
function SetRoutingBucketEntityLockdownMode() end
function IsPlayerAceAllowed(src, ace) return src == 1 and ace == 'projectin_rpg.admin' end
local function newEntity(kind, model, x, y, z)
    MOCK.nextEntity = MOCK.nextEntity + 1
    MOCK.entities[MOCK.nextEntity] = { kind = kind, model = model, x = x, y = y, z = z, health = 200, netId = MOCK.nextEntity + 50000 }
    return MOCK.nextEntity
end
function CreatePed(_, model, x, y, z) return newEntity('ped', model, x, y, z) end
function CreateObjectNoOffset(model, x, y, z) return newEntity('obj', model, x, y, z) end
function DoesEntityExist(e) return MOCK.entities[e] ~= nil or pedOwner(e) ~= nil end
function DeleteEntity(e) MOCK.entities[e] = nil end
function SetEntityRoutingBucket(e, b) if MOCK.entities[e] then MOCK.entities[e].bucket = b end end
function NetworkGetNetworkIdFromEntity(e) return MOCK.entities[e] and MOCK.entities[e].netId or 0 end
function GiveWeaponToPed() end
function SetPedArmour() end
function SetEntityHeading() end
function FreezeEntityPosition() end

---------------------------------------------------------------------------
-- ox_lib
---------------------------------------------------------------------------
lib = { callback = {} }
function lib.callback.register(name, fn) MOCK.callbacks[name] = fn end
function MOCK.call(src, name, ...)
    MOCK.advance(2100) -- コールバックのレート制限を回避するため時間を進める
    return MOCK.run(MOCK.callbacks['projectin_rpg:' .. name], src, ...)
end

---------------------------------------------------------------------------
-- exports (qbx_core / ox_inventory)
---------------------------------------------------------------------------
local qbx = {}
function qbx:GetPlayer(src)
    local p = MOCK.players[src]
    if not p then return nil end
    return { PlayerData = { source = src, citizenid = p.cid, charinfo = { firstname = p.firstname, lastname = p.lastname }, metadata = {} } }
end
function qbx:GetPlayerByCitizenId(cid)
    for s, p in pairs(MOCK.players) do if p.cid == cid then return qbx:GetPlayer(s) end end
end

local ox = {}
local function invOf(inv)
    if type(inv) == 'number' then return MOCK.inventories[inv] end
    MOCK.stashes[inv] = MOCK.stashes[inv] or {}
    return MOCK.stashes[inv]
end
function ox:GetInventoryItems(inv) return invOf(inv) end
function ox:GetInventory(inv) return invOf(inv) end
function ox:RegisterStash(id) MOCK.stashes[id] = MOCK.stashes[id] or {} end
function ox:AddItem(inv, name, count, metadata)
    local items = invOf(inv)
    if not items then return false end
    if MOCK.failAdd and MOCK.failAdd(inv, name) then return false end
    local slot = 1
    while items[slot] do slot = slot + 1 end
    local meta = {}
    for k, v in pairs(metadata or {}) do meta[k] = v end
    items[slot] = { name = name, count = count, slot = slot, metadata = meta }
    return true
end
function ox:RemoveItem(inv, name, count, metadata, slot)
    local items = invOf(inv)
    if not items then return false end
    if slot then
        local it = items[slot]
        if it and it.name == name and it.count >= count then
            it.count = it.count - count
            if it.count == 0 then items[slot] = nil end
            return true
        end
        return false
    end
    for s, it in pairs(items) do
        if it.name == name and it.count >= count then
            it.count = it.count - count
            if it.count == 0 then items[s] = nil end
            return true
        end
    end
    return false
end
function ox:registerHook(event, fn) MOCK.hooks[event] = fn return #MOCK.hooks + 1 end
function ox:removeHooks() end

exports = setmetatable({ qbx_core = qbx, ox_inventory = ox }, { __index = function(_, k) return {} end })
