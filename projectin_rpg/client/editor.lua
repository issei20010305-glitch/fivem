--[[ クライアント: エディターの配置モード / プレビュー表示 ]]
local placing = nil
local preview = nil

local function rotToDir(rot)
    local z, x = math.rad(rot.z), math.rad(rot.x)
    local n = math.abs(math.cos(x))
    return vector3(-math.sin(z) * n, math.cos(z) * n, math.sin(x))
end

local function raycast(dist)
    local cam = GetGameplayCamCoord()
    local dir = rotToDir(GetGameplayCamRot(2))
    local to = cam + dir * dist
    local h = StartExpensiveSynchronousShapeTestLosProbe(cam.x, cam.y, cam.z, to.x, to.y, to.z, 1 + 16, PlayerPedId(), 0)
    local _, hit, coords = GetShapeTestResult(h)
    if hit == 1 then return coords end
    return nil
end

local function loadModel(model)
    local hash = GetHashKey(model)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil end
    RequestModel(hash)
    local t = GetGameTimer()
    while not HasModelLoaded(hash) and GetGameTimer() - t < 3000 do Wait(10) end
    return HasModelLoaded(hash) and hash or nil
end

local function instructional(lines)
    for i, l in ipairs(lines) do
        SetTextScale(0.0, 0.34)
        SetTextFont(0)
        SetTextOutline()
        SetTextColour(255, 255, 255, 235)
        BeginTextCommandDisplayText('STRING')
        AddTextComponentSubstringPlayerName(l)
        EndTextCommandDisplayText(0.015, 0.30 + i * 0.028)
    end
end

local function finishPlacement(result)
    local p = placing
    placing = nil
    if p and p.ghost and DoesEntityExist(p.ghost) then DeleteEntity(p.ghost) end
    if p and p.hash then SetModelAsNoLongerNeeded(p.hash) end
    NUI.Send('placementResult', { token = p and p.token, result = result })
    SetNuiFocus(true, true)
    NUI.open = true
end

RegisterNUICallback('editorPlace', function(body, cb)
    cb({})
    if placing then return end
    SetNuiFocus(false, false)
    NUI.open = false
    placing = { token = body.token, kind = body.kind or 'point', label = body.label or '地点', heading = GetEntityHeading(PlayerPedId()) }
    if (body.kind == 'prop' or body.kind == 'ped') and type(body.model) == 'string' and body.model ~= '' then
        local hash = loadModel(body.model)
        if hash then
            placing.hash = hash
            local c = GetEntityCoords(PlayerPedId())
            if body.kind == 'prop' then
                placing.ghost = CreateObjectNoOffset(hash, c.x, c.y, c.z - 5.0, false, false, false)
            else
                placing.ghost = CreatePed(4, hash, c.x, c.y, c.z - 5.0, 0.0, false, false)
                FreezeEntityPosition(placing.ghost, true)
                SetBlockingOfNonTemporaryEvents(placing.ghost, true)
            end
            SetEntityAlpha(placing.ghost, 160, false)
            SetEntityCollision(placing.ghost, false, false)
            SetEntityInvincible(placing.ghost, true)
        else
            NUI.Toast(('モデル「%s」が見つかりません。マーカーのみで配置します'):format(body.model), 'warning')
        end
    end
    CreateThread(function()
        while placing do
            Wait(0)
            DisableControlAction(0, 24, true) DisableControlAction(0, 25, true)
            DisableControlAction(0, 14, true) DisableControlAction(0, 15, true)
            DisableControlAction(0, 16, true) DisableControlAction(0, 17, true)
            DisableControlAction(0, 200, true)
            local hit = raycast(80.0)
            local fine = IsDisabledControlPressed(0, 21) or IsControlPressed(0, 21)
            local step = fine and 1.0 or 7.5
            if IsDisabledControlJustPressed(0, 14) or IsDisabledControlJustPressed(0, 16) then placing.heading = (placing.heading - step) % 360 end
            if IsDisabledControlJustPressed(0, 15) or IsDisabledControlJustPressed(0, 17) then placing.heading = (placing.heading + step) % 360 end
            if hit then
                placing.pos = hit
                if placing.ghost then
                    SetEntityCoordsNoOffset(placing.ghost, hit.x, hit.y, hit.z + (placing.kind == 'ped' and 1.0 or 0.0), false, false, false)
                    SetEntityHeading(placing.ghost, placing.heading)
                end
                DrawMarker(28, hit.x, hit.y, hit.z, 0, 0, 0, 0, 0, 0, 0.25, 0.25, 0.25, 80, 200, 255, 200, false, false, 2, false, nil, nil, false)
                local f = vector3(-math.sin(math.rad(placing.heading)), math.cos(math.rad(placing.heading)), 0.0)
                DrawLine(hit.x, hit.y, hit.z + 0.1, hit.x + f.x * 1.5, hit.y + f.y * 1.5, hit.z + 0.1, 255, 200, 40, 255)
            end
            instructional({
                ('~b~配置モード~s~: %s'):format(placing.label),
                '~g~E~s~ / 左クリック: この位置に配置',
                '~y~G~s~: 自分の現在地に配置',
                'マウスホイール: 向きを回転 (Shiftで微調整)',
                ('向き: %.1f°'):format(placing.heading),
                '~r~Backspace~s~ / 右クリック: キャンセル',
            })
            if (IsControlJustReleased(0, 38) or IsDisabledControlJustReleased(0, 24)) and placing.pos then
                local p = placing.pos
                finishPlacement({ x = p.x, y = p.y, z = p.z, h = placing.heading })
            elseif IsControlJustReleased(0, 47) then
                local c = GetEntityCoords(PlayerPedId())
                finishPlacement({ x = c.x, y = c.y, z = c.z, h = GetEntityHeading(PlayerPedId()) })
            elseif IsControlJustReleased(0, 177) or IsDisabledControlJustReleased(0, 25) or IsDisabledControlJustReleased(0, 200) then
                finishPlacement(nil)
            end
        end
    end)
end)

RegisterNUICallback('editorCurrentPos', function(_, cb)
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    cb({ x = c.x, y = c.y, z = c.z, h = GetEntityHeading(ped) })
end)

RegisterNUICallback('editorTeleport', function(body, cb)
    cb({})
    if not body or not tonumber(body.x) then return end
    local ped = PlayerPedId()
    SetEntityCoords(ped, body.x + 0.0, body.y + 0.0, body.z + 0.0, false, false, false, false)
end)

RegisterNUICallback('checkModel', function(body, cb)
    local hash = GetHashKey(tostring(body.model or ''))
    cb({ valid = IsModelInCdimage(hash) and IsModelValid(hash) })
end)

RegisterNUICallback('editorPreview', function(body, cb)
    preview = body and body.data or nil
    cb({})
end)

-- プレビュー描画 (エディターで編集中の定義を街に表示。本人にのみ見える)
CreateThread(function()
    while true do
        if preview and not Run then
            Wait(0)
            local d = preview
            local function mark(c, r, g, b, label, kind)
                if not c or not tonumber(c.x) then return end
                DrawMarker(kind or 2, c.x, c.y, c.z + 0.8, 0, 0, 0, 0, 180.0, 0, 0.5, 0.5, 0.5, r, g, b, 200, true, true, 2, false, nil, nil, false)
                local on, sx, sy = GetScreenCoordFromWorldCoord(c.x, c.y, c.z + 1.4)
                if on then
                    SetTextScale(0.0, 0.3) SetTextFont(0) SetTextCentre(true) SetTextOutline()
                    SetTextColour(r, g, b, 255)
                    BeginTextCommandDisplayText('STRING')
                    AddTextComponentSubstringPlayerName(label)
                    EndTextCommandDisplayText(sx, sy)
                end
            end
            mark(d.entry, 180, 90, 255, '入口(街側)')
            mark(d.start, 80, 255, 120, '開始地点')
            mark(d.exit, 255, 255, 255, '帰還地点')
            for _, sp in ipairs(d.spawnPoints or {}) do mark(sp, 255, 80, 80, 'スポーン: ' .. tostring(sp.label or sp.id)) end
            for _, p in ipairs(d.props or {}) do mark(p, 255, 200, 40, 'プロップ: ' .. tostring(p.label or p.id) .. ' [' .. tostring(p.model) .. ']', 0) end
            local b = d.boundary
            if b and b.center and tonumber(b.center.x) then
                local r, h = tonumber(b.radius) or 80, tonumber(b.height) or 60
                DrawMarker(1, b.center.x, b.center.y, b.center.z - h / 2, 0, 0, 0, 0, 0, 0, r * 2.0, r * 2.0, h, 80, 160, 255, 40, false, false, 2, false, nil, nil, false)
                mark(b.center, 80, 160, 255, ('境界中心 (半径%dm)'):format(math.floor(r)))
            end
        else
            Wait(500)
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and placing and placing.ghost and DoesEntityExist(placing.ghost) then DeleteEntity(placing.ghost) end
end)
