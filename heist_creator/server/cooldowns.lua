-- Server-wide and per-player cooldowns. Cached in memory, persisted in the database.
Cooldowns = {}

local cache = {} -- [heistId][owner] = unix expiry

function Cooldowns.Load()
    cache = {}
    for _, row in ipairs(DB.LoadCooldowns()) do
        cache[row.heist_id] = cache[row.heist_id] or {}
        cache[row.heist_id][row.owner] = row.expires_at
    end
end

---@param heistId number
---@param owner string citizenid or DB.GLOBAL_OWNER
---@return number seconds remaining (0 when not on cooldown)
function Cooldowns.Remaining(heistId, owner)
    local entry = cache[heistId]
    local expires = entry and entry[owner]
    if not expires then return 0 end
    local left = expires - os.time()
    if left <= 0 then
        entry[owner] = nil
        return 0
    end
    return left
end

---@param heistId number
---@param owner string
---@param minutes number
function Cooldowns.Set(heistId, owner, minutes)
    if not minutes or minutes <= 0 then return end
    local expires = os.time() + math.floor(minutes * 60)
    cache[heistId] = cache[heistId] or {}
    cache[heistId][owner] = expires
    DB.SetCooldown(heistId, owner, expires)
end

---@param heistId number
function Cooldowns.Clear(heistId)
    cache[heistId] = nil
    DB.ClearCooldowns(heistId)
end
