--[[ クライアント: 命中報告 / 魔導士スキル ]]
local HEAD_BONE = 31086

AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' or not Run or Run.downed or not Run.canAttack then return end
    local victim, attacker, weapon = args[1], args[2], args[7]
    if attacker ~= PlayerPedId() or not DoesEntityExist(victim) or not IsEntityAPed(victim) then return end
    if not NetworkGetEntityIsNetworked(victim) then return end
    local netId = NetworkGetNetworkIdFromEntity(victim)
    if not Run.enemies[netId] then return end
    local hit, bone = GetPedLastDamageBone(victim)
    -- 実際のダメージ量・倒したかどうかはサーバーが決定する
    TriggerServerEvent('projectin_rpg:server:hit', netId, weapon, hit and bone == HEAD_BONE)
end)

---------------------------------------------------------------------------
-- 魔導士スキル
---------------------------------------------------------------------------
local function partyTargets()
    local list = {}
    for _, m in ipairs(Run and Run.party or {}) do list[#list + 1] = m end
    return list
end

local function useSkill(index)
    if not Run or Run.role ~= 'mage' or not Run.skills or NUI.open then return end
    local s = Run.skills[index]
    if not s then return end
    CreateThread(function()
        local ok, msg = lib.callback.await('projectin_rpg:skill', false, s.id, Run and Run.target)
        if ok then
            PlaySoundFrontend(-1, 'Hit_In', 'PLAYER_SWITCH_CUSTOM_SOUNDSET', false)
            NUI.Send('skillUsed', { id = s.id })
        else
            NUI.Toast(msg or 'スキルを使用できません', 'error', 2500)
        end
    end)
end

for i = 1, 4 do
    RegisterCommand('+rpg_skill' .. i, function() useSkill(i) end, false)
    RegisterCommand('-rpg_skill' .. i, function() end, false)
    RegisterKeyMapping('+rpg_skill' .. i, ('[RPG] 魔導士スキル%d'):format(i), 'keyboard', Config.Keys['skill' .. i])
end

RegisterCommand('+rpg_target', function()
    if not Run or Run.role ~= 'mage' then return end
    local list = partyTargets()
    if #list == 0 then return end
    local idx = 0
    for i, m in ipairs(list) do if m.id == Run.target then idx = i end end
    idx = idx + 1
    if idx > #list then
        Run.target = nil
        NUI.Send('target', { id = nil })
        NUI.Toast('対象: 自動選択', 'info', 1500)
        return
    end
    Run.target = list[idx].id
    NUI.Send('target', { id = Run.target })
    NUI.Toast('対象: ' .. list[idx].name, 'info', 1500)
end, false)
RegisterCommand('-rpg_target', function() end, false)
RegisterKeyMapping('+rpg_target', '[RPG] 魔導士スキル対象の切り替え', 'keyboard', Config.Keys.target)
