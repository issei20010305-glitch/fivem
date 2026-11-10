-- Heist XP. Only ever modified by the server.
XP = {}

local cache = {} -- [citizenid] = xp

---@param citizenid string
---@return number
function XP.Get(citizenid)
    local xp = cache[citizenid]
    if not xp then
        xp = DB.GetXP(citizenid)
        cache[citizenid] = xp
    end
    return xp
end

---@param citizenid string
---@param amount number
---@param completed? number completed heists to add
---@return number newXp
function XP.Add(citizenid, amount, completed)
    amount = math.floor(amount)
    local xp = math.max(0, XP.Get(citizenid) + amount)
    cache[citizenid] = xp
    DB.AddXP(citizenid, amount, completed or 0)
    return xp
end

---@param citizenid string
---@param amount number
function XP.Set(citizenid, amount)
    amount = math.max(0, math.floor(amount))
    cache[citizenid] = amount
    DB.SetXP(citizenid, amount)
end
