-- Thin wrapper around the NUI page (creator, Heist HUD, overlay, minigames).
NUI = {
    open = nil, -- 'creator' | 'hud' | 'minigame' | nil
}

---@param action string
---@param data? any
function NUI.Send(action, data)
    SendNUIMessage({ action = action, data = data })
end

---@param name? string page that owns the focus, nil releases it
function NUI.Focus(name)
    NUI.open = name
    SetNuiFocus(name ~= nil, name ~= nil)
end

---Shows a notification using the system selected in the config.
---@param message string
---@param kind? 'info'|'success'|'error'
---@param duration? number
function Notify(message, kind, duration)
    if not message or message == '' then return end
    kind = kind or 'info'
    if Config.Notify.system == 'ox' then
        lib.notify({
            title = 'Heist HUD',
            description = message,
            type = (kind == 'success' or kind == 'error') and kind or 'inform',
            duration = duration or Config.Notify.duration,
            position = 'bottom-right',
        })
    else
        NUI.Send('overlay:notify', {
            text = message,
            kind = kind,
            duration = duration or Config.Notify.duration,
        })
        if Config.Notify.sound then
            PlaySoundFrontend(-1, 'INFO', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
        end
    end
end

RegisterNetEvent('heist_creator:client:notify', function(message, kind)
    Notify(message, kind)
end)

-- Static texts used by the page.
RegisterNUICallback('ready', function(_, cb)
    cb({ keyLabel = Config.Interaction.keyLabel, cancelCommand = Config.Commands.cancel })
end)
