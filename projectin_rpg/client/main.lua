--[[ クライアント: /rpg、イベントの入口・ブリップ、告知 ]]
RPGClient = { events = {}, inRun = false, loaded = false }
local blips = {}

---------------------------------------------------------------------------
-- /rpg メイン画面
---------------------------------------------------------------------------
local function openMain(tab)
    local profile = lib.callback.await('projectin_rpg:getProfile', false)
    if not profile then return NUI.Toast('キャラクター情報を取得できません', 'error') end
    NUI.Open(profile.role and 'hub' or 'role', { profile = profile, tab = tab })
end

RegisterCommand('rpg', function() openMain() end, false)
RegisterNetEvent('projectin_rpg:client:openAdmin', function() openMain('admin') end)
TriggerEvent('chat:addSuggestion', '/rpg', 'ダンジョン/レイドのメニューを開く (ロール・イベント・パーティー・RPGインベントリ)')
TriggerEvent('chat:addSuggestion', '/rpgadmin', 'RPG管理画面 (管理者のみ)')

RegisterNetEvent('projectin_rpg:client:profileChanged', function()
    if NUI.open then NUI.Send('refresh', { what = 'profile' }) end
end)
RegisterNetEvent('projectin_rpg:client:inventoryChanged', function()
    NUI.Send('refresh', { what = 'inventory' })
end)
RegisterNetEvent('projectin_rpg:client:partyChanged', function()
    NUI.Send('refresh', { what = 'party' })
end)

RegisterNetEvent('projectin_rpg:client:partyInvite', function(data)
    NUI.Send('partyInvite', data)
    PlaySoundFrontend(-1, 'Text_Arrive_Tone', 'Phone_SoundSet_Default', false)
end)

---------------------------------------------------------------------------
-- イベント一覧 / ブリップ
---------------------------------------------------------------------------
local function clearBlips()
    for _, b in pairs(blips) do if DoesBlipExist(b) then RemoveBlip(b) end end
    blips = {}
end

local function refreshBlips()
    clearBlips()
    if RPGClient.inRun then return end
    for _, ev in ipairs(RPGClient.events) do
        local e = ev.entry
        if e then
            local b = AddBlipForCoord(e.x, e.y, e.z)
            SetBlipSprite(b, ev.type == 'raid' and 303 or 630)
            SetBlipColour(b, ev.type == 'raid' and 1 or 27)
            SetBlipScale(b, ev.type == 'raid' and 1.1 or 0.95)
            SetBlipAsShortRange(b, false)
            if ev.status == 'active' or ev.type == 'raid' then SetBlipFlashes(b, true) SetBlipFlashTimer(b, 8000) end
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName((ev.type == 'raid' and '[レイド] ' or '[ダンジョン] ') .. ev.name)
            EndTextCommandSetBlipName(b)
            blips[ev.id] = b
        end
    end
end

RegisterNetEvent('projectin_rpg:client:events', function(list)
    RPGClient.events = list or {}
    refreshBlips()
    NUI.Send('events', RPGClient.events)
end)

RegisterNetEvent('projectin_rpg:client:announce', function(data)
    NUI.Send('announce', data)
    PlaySoundFrontend(-1, 'CHALLENGE_UNLOCKED', 'HUD_AWARDS', false)
end)

RegisterNUICallback('setWaypoint', function(body, cb)
    for _, ev in ipairs(RPGClient.events) do
        if ev.id == body.id and ev.entry then
            SetNewWaypoint(ev.entry.x + 0.0, ev.entry.y + 0.0)
            NUI.Toast(('%s をGPSに設定しました'):format(ev.name), 'success')
        end
    end
    cb({})
end)

---------------------------------------------------------------------------
-- 入口マーカー (街側 / バケット0)
---------------------------------------------------------------------------
CreateThread(function()
    while true do
        local sleep = 1000
        if not RPGClient.inRun and not NUI.open and #RPGClient.events > 0 then
            local ped = PlayerPedId()
            local pc = GetEntityCoords(ped)
            for _, ev in ipairs(RPGClient.events) do
                local e = ev.entry
                if e then
                    local d = #(pc - vector3(e.x, e.y, e.z))
                    if d < 60.0 then
                        sleep = 0
                        local r, g, b = 180, 90, 255
                        if ev.type == 'raid' then r, g, b = 255, 60, 60 end
                        DrawMarker(1, e.x, e.y, e.z - 1.0, 0, 0, 0, 0, 0, 0, 3.0, 3.0, 1.2, r, g, b, 120, false, false, 2, false, nil, nil, false)
                        DrawMarker(21, e.x, e.y, e.z + 1.0, 0, 0, 0, 0, 180.0, 0, 0.8, 0.8, 0.8, r, g, b, 200, true, true, 2, false, nil, nil, false)
                        if d < 2.5 then
                            local label = ev.type == 'raid' and '参加登録 / 詳細' or '入場'
                            BeginTextCommandDisplayHelp('STRING')
                            AddTextComponentSubstringPlayerName(('~INPUT_CONTEXT~ %s: %s'):format(ev.name, label))
                            EndTextCommandDisplayHelp(0, false, true, -1)
                            if IsControlJustReleased(0, 38) then
                                local info, err = lib.callback.await('projectin_rpg:entryCheck', false, ev.id)
                                if info then NUI.Open('entry', info) else NUI.Toast(err or '情報を取得できません', 'error') end
                            end
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

---------------------------------------------------------------------------
-- 起動時
---------------------------------------------------------------------------
local function ready()
    if RPGClient.loaded then return end
    RPGClient.loaded = true
    TriggerServerEvent('projectin_rpg:server:clientReady')
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() RPGClient.loaded = false ready() end)
RegisterNetEvent('qbx_core:client:playerLoggedOut', function()
    RPGClient.loaded = false
    clearBlips()
    if RPGClient.inRun then TriggerEvent('projectin_rpg:client:forceCleanup') end
end)

CreateThread(function()
    Wait(2000)
    if LocalPlayer.state.isLoggedIn then ready() end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then clearBlips() end
end)
