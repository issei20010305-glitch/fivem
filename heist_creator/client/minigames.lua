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
