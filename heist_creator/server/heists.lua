-- Heist storage, validation of creator input and the public (player facing) view.
Heists = {
    list = {}, -- [id] = heist
}

local INTERACTIONS = { key = true, target = true }

---------------------------------------------------------------------------
-- Sanitizing helpers
---------------------------------------------------------------------------
local function cleanString(value, maxLength, default)
    if type(value) ~= 'string' then return default end
    value = value:gsub('^%s+', ''):gsub('%s+$', '')
    local length = utf8.len(value)
    if not length then return default end
    if length > maxLength then
        value = value:sub(1, utf8.offset(value, maxLength + 1) - 1)
    end
    return value
end

local function cleanNumber(value, min, max, default, integer)
    value = tonumber(value)
    if not value or value ~= value then return default end
    if integer then value = math.floor(value + 0.5) end
    if value < min then value = min elseif value > max then value = max end
    return value
end

local function cleanCoords(value, withHeading)
    if type(value) ~= 'table' then return nil end
    local x, y, z = tonumber(value.x), tonumber(value.y), tonumber(value.z)
    if not x or not y or not z then return nil end
    if math.abs(x) > 12000 or math.abs(y) > 12000 or math.abs(z) > 3000 then return nil end
    local coords = { x = Utils.Round(x, 2), y = Utils.Round(y, 2), z = Utils.Round(z, 2) }
    if withHeading then
        coords.w = Utils.Round(cleanNumber(value.w, 0, 360, 0), 1)
    end
    return coords
end

local function cleanIdentifier(value, maxLength)
    value = cleanString(value, maxLength, '')
    if value == '' or not value:match('^[%w_%-]+$') then return nil end
    return value
end

local function cleanImage(value)
    value = cleanString(value, 300, '')
    if value:match('^https?://') or value:match('^nui://') then
        return value
    end
    return ''
end

local function behaviorExists(id)
    for i = 1, #Config.Guards.behaviors do
        if Config.Guards.behaviors[i].id == id then return true end
    end
    return false
end

local function difficultyExists(id)
    for i = 1, #Config.MinigameDifficulties do
        if Config.MinigameDifficulties[i].id == id then return true end
    end
    return false
end

local function cleanReward(raw, limits)
    if type(raw) ~= 'table' then return nil, L('invalid_data') end
    local reward = {
        item       = cleanString(raw.item, 64, ''),
        guaranteed = raw.guaranteed == true,
        chance     = Utils.Round(cleanNumber(raw.chance, 0, 100, 0), 2),
        min        = cleanNumber(raw.min, 1, limits.rewardAmount, 1, true),
        max        = cleanNumber(raw.max, 1, limits.rewardAmount, 1, true),
    }
    if not Framework.ItemExists(reward.item) then return nil, L('err_item', reward.item) end
    if reward.max < reward.min then reward.max = reward.min end
    if reward.guaranteed then reward.chance = 100 end
    return reward
end

---Validates everything an admin sends from the creator.
---@param input table
---@return table? heist, string? error
function Heists.Sanitize(input)
    if type(input) ~= 'table' then return nil, L('invalid_data') end
    local limits = Config.Limits

    local heist = {
        name           = cleanString(input.name, 48, ''),
        description    = cleanString(input.description, 400, ''),
        image          = cleanImage(input.image),
        difficulty     = cleanNumber(input.difficulty, 1, 5, 1, true),
        requiredXp     = cleanNumber(input.requiredXp, 0, limits.xp, 0, true),
        xpReward       = cleanNumber(input.xpReward, 0, limits.xp, 0, true),
        minPolice      = cleanNumber(input.minPolice, 0, 128, 0, true),
        minPlayers     = cleanNumber(input.minPlayers, 1, Config.Party.maxSize, 1, true),
        maxPlayers     = cleanNumber(input.maxPlayers, 1, Config.Party.maxSize, Config.Party.maxSize, true),
        globalCooldown = cleanNumber(input.globalCooldown, 0, limits.cooldown, 0, true),
        playerCooldown = cleanNumber(input.playerCooldown, 0, limits.cooldown, 0, true),
        timeLimit      = cleanNumber(input.timeLimit, 0, 600, 0, true),
        startRadius    = cleanNumber(input.startRadius, 3, 100, 15),
        start          = cleanCoords(input.start),
        stages         = {},
        guards         = {},
        loots          = {},
    }

    if heist.name == '' then return nil, L('err_name') end
    if not heist.start then return nil, L('err_start') end
    if heist.maxPlayers < heist.minPlayers then heist.maxPlayers = heist.minPlayers end

    -- Stages
    if type(input.stages) ~= 'table' or #input.stages < 1 then return nil, L('err_stages') end
    if #input.stages > limits.stages then return nil, L('err_too_many', L('word_stages'), limits.stages) end
    for i = 1, #input.stages do
        local raw = input.stages[i]
        if type(raw) ~= 'table' then return nil, L('invalid_data') end
        local stage = {
            label       = cleanString(raw.label, 80, ''),
            coords      = cleanCoords(raw.coords),
            interaction = INTERACTIONS[raw.interaction] and raw.interaction or 'key',
            item        = cleanString(raw.item, 64, ''),
            itemCount   = cleanNumber(raw.itemCount, 1, 100, 1, true),
            consume     = raw.consume == true,
            minigame    = raw.minigame,
            difficulty  = difficultyExists(raw.difficulty) and raw.difficulty or 'medium',
        }
        if not stage.coords then return nil, L('err_stage_coords', i) end
        if type(stage.minigame) ~= 'string' or not Config.Minigames[stage.minigame] then
            return nil, L('err_stage_minigame', i)
        end
        if stage.item ~= '' and not Framework.ItemExists(stage.item) then
            return nil, L('err_item', stage.item)
        end
        local doors, invalidDoor = Doors.Sanitize(raw.doors)
        if not doors then return nil, L('err_door', i, invalidDoor) end
        stage.doors = doors
        heist.stages[i] = stage
    end

    -- Guards
    if type(input.guards) == 'table' then
        if #input.guards > limits.guards then return nil, L('err_too_many', L('word_guards'), limits.guards) end
        for i = 1, #input.guards do
            local raw = input.guards[i]
            if type(raw) ~= 'table' then return nil, L('invalid_data') end
            local guard = {
                model    = cleanIdentifier(raw.model, 64),
                weapon   = cleanIdentifier(raw.weapon, 64),
                health   = cleanNumber(raw.health, 1, 2000, 100, true),
                armour   = cleanNumber(raw.armour, 0, 100, 0, true),
                accuracy = cleanNumber(raw.accuracy, 0, 100, 40, true),
                behavior = behaviorExists(raw.behavior) and raw.behavior or 'aggressive',
                coords   = cleanCoords(raw.coords, true),
            }
            if not guard.model or not guard.weapon then return nil, L('err_guard_model', i) end
            if not guard.coords then return nil, L('err_guard_coords', i) end
            guard.weapon = guard.weapon:upper()
            heist.guards[i] = guard
        end
    end

    -- Loot points, each with its own loot table
    if type(input.loots) == 'table' then
        if #input.loots > limits.loots then return nil, L('err_too_many', L('word_loots'), limits.loots) end
        for i = 1, #input.loots do
            local raw = input.loots[i]
            if type(raw) ~= 'table' then return nil, L('invalid_data') end
            local loot = {
                label       = cleanString(raw.label, 48, ''),
                coords      = cleanCoords(raw.coords),
                interaction = INTERACTIONS[raw.interaction] and raw.interaction or 'key',
                duration    = cleanNumber(raw.duration, 1, 120, 8, true),
                rewards     = {},
            }
            if not loot.coords then return nil, L('err_loot_coords', i) end

            local rewards = type(raw.rewards) == 'table' and raw.rewards or {}
            if #rewards < 1 then return nil, L('err_rewards', i) end
            if #rewards > limits.rewards then return nil, L('err_too_many', L('word_rewards'), limits.rewards) end
            for j = 1, #rewards do
                local reward, err = cleanReward(rewards[j], limits)
                if not reward then return nil, err end
                loot.rewards[j] = reward
            end
            heist.loots[i] = loot
        end
    end

    return heist
end

---------------------------------------------------------------------------
-- Storage
---------------------------------------------------------------------------
function Heists.Load()
    Heists.list = {}
    for _, row in ipairs(DB.LoadHeists()) do
        local ok, data = pcall(json.decode, row.data)
        if ok and type(data) == 'table' then
            data.id = row.id
            data.name = row.name
            data.enabled = row.enabled == 1 or row.enabled == true
            data.stages = data.stages or {}
            data.guards = data.guards or {}
            data.loots = data.loots or {}
            -- Heists saved before loot tables became per loot point: every
            -- point inherits the old heist-wide table.
            local legacy = data.rewards
            data.rewards = nil
            for _, loot in ipairs(data.loots) do
                loot.rewards = loot.rewards or legacy or {}
            end
            for _, stage in ipairs(data.stages) do
                stage.doors = stage.doors or {}
            end
            Heists.list[row.id] = data
        else
            print(('[Heist Creator] heist #%s has corrupted data and was skipped'):format(row.id))
        end
    end
end

---Creates or updates a heist from creator input.
---@param src number
---@param input table
---@return boolean ok, string|number result error message or the heist id
function Heists.Save(src, input)
    local heist, err = Heists.Sanitize(input)
    if not heist then return false, err end

    local id = tonumber(input.id)
    local enabled = input.enabled ~= false

    if id then
        if not Heists.list[id] then return false, L('heist_not_found') end
        if Sessions.byHeist[id] then return false, L('heist_busy') end
        DB.UpdateHeist(id, heist.name, heist, enabled)
    else
        id = DB.InsertHeist(heist.name, heist, enabled, Framework.GetIdentifier(src))
        if not id then return false, L('db_error') end
    end

    heist.id = id
    heist.enabled = enabled
    Heists.list[id] = heist
    return true, id
end

---@param id number
function Heists.Delete(id)
    if not Heists.list[id] then return false, L('heist_not_found') end
    if Sessions.byHeist[id] then return false, L('heist_busy') end
    DB.DeleteHeist(id)
    Cooldowns.Clear(id)
    Heists.list[id] = nil
    return true
end

---@param id number
---@param enabled boolean
function Heists.SetEnabled(id, enabled)
    local heist = Heists.list[id]
    if not heist then return false, L('heist_not_found') end
    if Sessions.byHeist[id] then return false, L('heist_busy') end
    heist.enabled = enabled == true
    DB.SetHeistEnabled(id, heist.enabled)
    return true
end

---Full list for the creator.
function Heists.AdminList()
    local list = {}
    for _, heist in pairs(Heists.list) do
        list[#list + 1] = heist
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

---Player facing data. Never contains coordinates.
---@param heist table
---@param citizenid string
---@param xp number
function Heists.Public(heist, citizenid, xp)
    -- Expected rewards: one line per item, summarised over every loot point.
    local rewards, byItem = {}, {}
    for _, loot in ipairs(heist.loots) do
        for _, reward in ipairs(loot.rewards or {}) do
            local entry = byItem[reward.item]
            if not entry then
                entry = {
                    item = reward.item,
                    label = Framework.ItemLabel(reward.item),
                    chance = 0,
                    min = reward.min,
                    max = reward.max,
                    guaranteed = false,
                    points = {},
                }
                byItem[reward.item] = entry
                rewards[#rewards + 1] = entry
            end
            entry.min = math.min(entry.min, reward.min)
            entry.max = math.max(entry.max, reward.max)
            entry.chance = math.max(entry.chance, reward.chance)
            entry.guaranteed = entry.guaranteed or reward.guaranteed
            entry.points[loot] = true
        end
    end
    for i = 1, #rewards do
        local count = 0
        for _ in pairs(rewards[i].points) do count = count + 1 end
        rewards[i].points = count
    end

    return {
        id = heist.id,
        name = heist.name,
        description = heist.description,
        image = heist.image,
        difficulty = heist.difficulty,
        requiredXp = heist.requiredXp,
        xpReward = heist.xpReward,
        minPolice = heist.minPolice,
        minPlayers = heist.minPlayers,
        maxPlayers = heist.maxPlayers,
        timeLimit = heist.timeLimit,
        globalCooldown = heist.globalCooldown,
        playerCooldown = heist.playerCooldown,
        stages = #heist.stages,
        loots = #heist.loots,
        guards = #heist.guards,
        rewards = rewards,
        locked = xp < heist.requiredXp,
        active = Sessions.byHeist[heist.id] ~= nil,
        cooldownGlobal = Cooldowns.Remaining(heist.id, DB.GLOBAL_OWNER),
        cooldownPlayer = Cooldowns.Remaining(heist.id, citizenid),
    }
end
