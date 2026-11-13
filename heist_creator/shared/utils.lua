Utils = {}

---@param value number
---@param decimals? number
function Utils.Round(value, decimals)
    local mult = 10 ^ (decimals or 0)
    return math.floor(value * mult + 0.5) / mult
end

---Returns the XP bonus multiplier (0.10 = +10%) for a crew size.
---@param count number
---@return number
function Utils.PartyBonus(count)
    local bonus, best = 0.0, 0
    for size, value in pairs(Config.XP.partyBonus) do
        if count >= size and size > best then
            best, bonus = size, value
        end
    end
    return bonus
end

---Returns the current rank label and the XP needed for the next rank (nil when maxed).
---@param xp number
---@return string label, number? nextXp, number currentXp
function Utils.GetRank(xp)
    local label, current, nextXp = '', 0, nil
    for i = 1, #Config.XP.ranks do
        local rank = Config.XP.ranks[i]
        if xp >= rank.xp then
            label, current = rank.label, rank.xp
        else
            nextXp = rank.xp
            break
        end
    end
    return label, nextXp, current
end

---@param list table
---@param value any
function Utils.Contains(list, value)
    for i = 1, #list do
        if list[i] == value then return true end
    end
    return false
end

---@param list table
---@param value any
function Utils.RemoveValue(list, value)
    for i = #list, 1, -1 do
        if list[i] == value then
            table.remove(list, i)
            return true
        end
    end
    return false
end

---Formats seconds as a short Japanese duration.
---@param seconds number
function Utils.FormatTime(seconds)
    seconds = math.max(0, math.floor(seconds))
    local h = seconds // 3600
    local m = (seconds % 3600) // 60
    local s = seconds % 60
    if h > 0 then return ('%d時間%d分'):format(h, m) end
    if m > 0 then return ('%d分%d秒'):format(m, s) end
    return ('%d秒'):format(s)
end

function Utils.Debug(...)
    if Config.Debug then
        print('[Heist Creator]', ...)
    end
end
