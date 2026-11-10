-- In-game configurable settings (Heist HUD NPC locations).
Settings = {
    npcs = {},
}

local function sanitizeNpc(raw)
    if type(raw) ~= 'table' then return nil end
    local x, y, z = tonumber(raw.x), tonumber(raw.y), tonumber(raw.z)
    if not x or not y or not z then return nil end
    local model = type(raw.model) == 'string' and raw.model:match('^[%w_%-]+$') and raw.model:sub(1, 64)
        or Config.Npc.defaultModel
    return {
        model = model,
        x = Utils.Round(x, 2),
        y = Utils.Round(y, 2),
        z = Utils.Round(z, 2),
        w = Utils.Round(tonumber(raw.w) or 0.0, 1),
    }
end

function Settings.Load()
    local saved = DB.GetSetting('npcs')
    local source = type(saved) == 'table' and saved or Config.Npc.defaults
    local npcs = {}
    for i = 1, #source do
        local npc = sanitizeNpc(source[i])
        if npc then npcs[#npcs + 1] = npc end
    end
    Settings.npcs = npcs
end

---@param list table
---@return boolean ok, string? error
function Settings.SaveNpcs(list)
    if type(list) ~= 'table' then return false, L('invalid_data') end
    if #list > Config.Limits.npcs then return false, L('err_too_many', 'NPC', Config.Limits.npcs) end
    local npcs = {}
    for i = 1, #list do
        local npc = sanitizeNpc(list[i])
        if not npc then return false, L('invalid_data') end
        npcs[i] = npc
    end
    Settings.npcs = npcs
    DB.SetSetting('npcs', npcs)
    TriggerClientEvent('heist_creator:client:setNpcs', -1, npcs)
    return true
end

---@param src number
---@param distance number
function Settings.IsNearNpc(src, distance)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local coords = GetEntityCoords(ped)
    for i = 1, #Settings.npcs do
        local npc = Settings.npcs[i]
        if #(coords - vector3(npc.x, npc.y, npc.z)) <= distance then
            return true
        end
    end
    return false
end
