-- Objective card, GPS waypoint and blips.
Guidance = {}

local blips = {}       -- [id] = blip handle
local lastObjective = nil
local primary = nil       -- id of the blip the GPS points at

---@param id string
---@param coords table
---@param style { sprite: number, colour: number, scale: number }
---@param label string
function Guidance.SetBlip(id, coords, style, label)
    if blips[id] then return end
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, style.sprite)
    SetBlipColour(blip, style.colour)
    SetBlipScale(blip, style.scale)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandSetBlipName(blip)
    blips[id] = blip
end

---Points the GPS (waypoint and / or blip route) at the blip of the current objective.
---@param id string id previously passed to Guidance.SetBlip
---@param coords table
function Guidance.SetPrimary(id, coords)
    if primary == id then return end
    if primary and blips[primary] and DoesBlipExist(blips[primary]) then
        SetBlipRoute(blips[primary], false)
    end
    primary = id
    if Config.Guidance.route and blips[id] then
        SetBlipRoute(blips[id], true)
    end
    if Config.Guidance.waypoint then
        SetNewWaypoint(coords.x, coords.y)
    end
end

---Removes every blip that is not listed in `keep`.
---@param keep table<string, boolean>
function Guidance.PruneBlips(keep)
    for id, blip in pairs(blips) do
        if not keep[id] then
            if DoesBlipExist(blip) then RemoveBlip(blip) end
            blips[id] = nil
        end
    end
end

---Updates the objective card. A bubble is shown whenever the objective text changes.
---@param data { title: string, text: string, step?: string, timeLeft?: number, members?: table }
function Guidance.SetObjective(data)
    NUI.Send('overlay:objective', data)
    if data.text ~= lastObjective then
        lastObjective = data.text
        Notify(data.text, 'objective')
    end
end

local areaBlip, areaKey = nil, nil

---Draws (or removes) the heist area on the map.
---@param area { x: number, y: number, z: number, radius: number }?
function Guidance.SetArea(area)
    local key = area and ('%s:%s:%s'):format(area.x, area.y, area.radius) or nil
    if key == areaKey then return end
    areaKey = key

    if areaBlip and DoesBlipExist(areaBlip) then RemoveBlip(areaBlip) end
    areaBlip = nil
    if not area then return end

    areaBlip = AddBlipForRadius(area.x, area.y, area.z, area.radius + 0.0)
    SetBlipColour(areaBlip, 1)
    SetBlipAlpha(areaBlip, 90)
end

function Guidance.Clear()
    Guidance.SetArea(nil)
    Guidance.PruneBlips({})
    lastObjective = nil
    primary = nil
    NUI.Send('overlay:objective', nil)
    if Config.Guidance.waypoint and IsWaypointActive() then
        SetWaypointOff()
    end
end
