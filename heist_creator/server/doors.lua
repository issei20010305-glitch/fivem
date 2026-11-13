-- ox_doorlock integration (optional). Stages can list doors that are unlocked
-- when the stage is completed; they are locked again when the heist ends.
Doors = {}

local held = {} -- [doorId] = session id that keeps the door open

function Doors.Available()
    return Config.Doors.enabled and GetResourceState('ox_doorlock') == 'started'
end

local function setState(id, locked)
    local ok, result = pcall(function()
        return exports.ox_doorlock:setDoorState(id, locked and 1 or 0)
    end)
    if not ok then
        print(('[Heist Creator] ox_doorlock: could not change door %s (%s)'):format(id, result))
    end
    return ok and result
end

---@param id number
function Doors.Exists(id)
    local ok, door = pcall(function() return exports.ox_doorlock:getDoor(id) end)
    return ok and type(door) == 'table'
end

---Every door, nearest first, for the creator.
---@param src number
function Doors.List(src)
    local list = {}
    if not Doors.Available() then return list end

    local ok, doors = pcall(function() return exports.ox_doorlock:getAllDoors() end)
    if not ok or type(doors) ~= 'table' then return list end

    local ped = GetPlayerPed(src)
    local origin = ped and ped ~= 0 and GetEntityCoords(ped) or nil

    for i = 1, #doors do
        local door = doors[i]
        local coords = door.coords
        local distance = origin and coords and #(origin - vector3(coords.x, coords.y, coords.z)) or 99999.0
        list[#list + 1] = {
            id = door.id,
            name = door.name or ('#%s'):format(door.id),
            distance = math.floor(distance + 0.5),
        }
    end

    table.sort(list, function(a, b) return a.distance < b.distance end)
    return list
end

---Cleans the door list of a stage sent by the creator.
---@return number[]? doors, number? invalidId
function Doors.Sanitize(input)
    local doors, seen = {}, {}
    if type(input) ~= 'table' then return doors end
    local available = Doors.Available()

    for i = 1, math.min(#input, Config.Limits.stageDoors) do
        local id = math.tointeger(tonumber(input[i]))
        if id and id > 0 and not seen[id] then
            if available and not Doors.Exists(id) then return nil, id end
            seen[id] = true
            doors[#doors + 1] = id
        end
    end
    return doors
end

---Crew arrived: make sure every door of the heist starts locked.
---@param session table
function Doors.Prepare(session)
    session.openDoors = {}
    if not Doors.Available() or not Config.Doors.lockOnStart then return end
    for _, stage in ipairs(session.heist.stages) do
        for _, id in ipairs(stage.doors or {}) do
            if not held[id] then setState(id, true) end
        end
    end
end

---Unlocks the doors of a completed stage and keeps them open for the session.
---@param session table
---@param doors number[]?
---@return boolean unlocked whether at least one door was unlocked
function Doors.Unlock(session, doors)
    if not doors or #doors == 0 or not Doors.Available() then return false end
    session.openDoors = session.openDoors or {}
    local unlocked = false
    for _, id in ipairs(doors) do
        held[id] = session.id
        session.openDoors[id] = true
        if setState(id, false) then unlocked = true end
    end
    return unlocked
end

---Heist ended: lock the doors again.
---@param session table
---@param immediate? boolean skip the configured delay (resource stop)
function Doors.Release(session, immediate)
    local doors = session.openDoors
    session.openDoors = {}
    if not doors or not next(doors) then return end

    local function relock()
        if not Doors.Available() then return end
        for id in pairs(doors) do
            -- Another crew may have taken over the door in the meantime.
            if held[id] == session.id then
                held[id] = nil
                if Config.Doors.relockOnEnd then setState(id, true) end
            end
        end
    end

    if immediate or Config.Doors.relockDelay <= 0 then
        relock()
    else
        SetTimeout(Config.Doors.relockDelay * 1000, relock)
    end
end

-- A door with "autolock" locks itself again after a few seconds. While a heist
-- holds it open, unlock it again so the crew is not trapped inside.
AddEventHandler('ox_doorlock:stateChanged', function(source, doorId, locked)
    if source or not locked or not held[doorId] then return end
    SetTimeout(250, function()
        if held[doorId] then setState(doorId, false) end
    end)
end)
