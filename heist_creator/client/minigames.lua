-- Minigame runner. The list of minigames lives in shared/config.lua (Config.Minigames).
local pending = nil -- promise of the running Heist HUD minigame

---Starts one of the built-in Heist HUD (NUI) minigames.
---@param kind 'pattern'|'sequence'
---@param difficulty string
---@return boolean success
function StartNuiMinigame(kind, difficulty)
    if pending or NUI.open then return false end
    local presets = Config.NuiMinigames[kind]
    if not presets then return false end

    pending = promise.new()
    NUI.Focus('minigame')
    NUI.Send('minigame:start', {
        kind = kind,
        settings = presets[difficulty] or presets.medium,
    })

    local result = Citizen.Await(pending)
    pending = nil
    NUI.Focus(nil)
    return result == true
end

RegisterNUICallback('minigame:result', function(data, cb)
    cb({})
    if pending then pending:resolve(data and data.success == true) end
end)

---Runs a ps-ui minigame. ps-ui reports the result through a callback.
---@param export string e.g. 'Circle'
---@param args any[] values passed after the callback
---@return boolean success
function RunPsUi(export, args)
    local result = promise.new()
    exports['ps-ui'][export](nil, function(success)
        result:resolve(success == true)
    end, table.unpack(args))
    return Citizen.Await(result)
end

---Runs an Awoken minigame. The game itself is configured in
---awoken_minigames/config/games; the difficulty sets how many rounds in a row
---have to be cleared (Config.Awoken.rounds).
---@param key string game key, e.g. 'skillCheck'
---@param difficulty string
---@param title string
---@param subtitle string
---@return boolean success
function RunAwoken(key, difficulty, title, subtitle)
    local options = { title = title, subtitle = subtitle }

    local rounds = Config.Awoken.rounds[difficulty]
    if rounds and rounds > 1 then options.stages = rounds end

    local extra = Config.Awoken.options[key]
    extra = extra and extra[difficulty]
    if extra then
        for name, value in pairs(extra) do options[name] = value end
    end

    local export = key:sub(1, 1):upper() .. key:sub(2)
    return exports.awoken_minigames[export](nil, options) == true
end

---Runs the minigame configured for a stage.
---@param id string
---@param difficulty string
---@return boolean success
function RunMinigame(id, difficulty)
    local minigame = Config.Minigames[id]
    if not minigame then
        print(('[Heist Creator] unknown minigame "%s"'):format(id))
        return false
    end
    if minigame.resource and GetResourceState(minigame.resource) ~= 'started' then
        Notify(L('minigame_missing', minigame.label or id), 'error')
        return false
    end
    local ok, result = pcall(minigame.run, difficulty)
    if not ok then
        print(('[Heist Creator] minigame "%s" failed: %s'):format(id, result))
        return false
    end
    return result == true
end

---Force-closes a running Heist HUD minigame (heist ended, resource stopped).
function CancelNuiMinigame()
    if pending then
        NUI.Send('minigame:stop')
        pending:resolve(false)
    end
end
