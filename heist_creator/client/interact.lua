-- "Press E" and ox_target interaction points used during a heist.
Interact = {
    busy = false,
}

local entries = {}  -- [id] = { point, zone }
local textFor = nil -- id of the entry currently showing the text UI

local function hideText(id)
    if textFor and (id == nil or textFor == id) then
        lib.hideTextUI()
        textFor = nil
    end
end

local function use(data)
    if Interact.busy then return end
    Interact.busy = true
    hideText()
    CreateThread(function()
        local ok, err = pcall(data.onUse)
        if not ok then print(('[Heist Creator] interaction error: %s'):format(err)) end
        Interact.busy = false
    end)
end

---@param id string unique id
---@param data { coords: vector3, type: 'key'|'target', label: string, icon?: string, onUse: function }
function Interact.Add(id, data)
    Interact.Remove(id)

    local cfg = Config.Interaction
    local marker = cfg.marker
    local entry = {}
    local isKey = data.type ~= 'target'

    local point = lib.points.new({
        coords = data.coords,
        distance = cfg.markerDistance,
    })

    function point:nearby()
        DrawMarker(marker.type, data.coords.x, data.coords.y, data.coords.z + 0.15, 0.0, 0.0, 0.0, 0.0, 180.0, 0.0,
            marker.scale, marker.scale, marker.scale, marker.r, marker.g, marker.b, marker.a,
            true, true, 2, false, nil, nil, false)

        if not isKey then return end

        if self.currentDistance <= cfg.distance and not Interact.busy then
            if textFor ~= id then
                lib.showTextUI(('[%s] %s'):format(cfg.keyLabel, data.label), { position = 'right-center' })
                textFor = id
            end
            if IsControlJustReleased(0, cfg.key) then
                use(data)
            end
        else
            hideText(id)
        end
    end

    function point:onExit()
        hideText(id)
    end

    entry.point = point

    if not isKey then
        entry.zone = exports.ox_target:addSphereZone({
            coords = data.coords,
            radius = cfg.targetRadius,
            debug = Config.Debug,
            options = {
                {
                    name = ('heist_creator:%s'):format(id),
                    icon = data.icon or 'fa-solid fa-hand',
                    label = data.label,
                    distance = cfg.targetDistance,
                    onSelect = function() use(data) end,
                },
            },
        })
    end

    entries[id] = entry
end

---@param id string
function Interact.Remove(id)
    local entry = entries[id]
    if not entry then return end
    if entry.point then entry.point:remove() end
    if entry.zone then exports.ox_target:removeZone(entry.zone) end
    hideText(id)
    entries[id] = nil
end

---@param id string
function Interact.Exists(id)
    return entries[id] ~= nil
end

---Removes every interaction that is not listed in `keep`.
---@param keep table<string, boolean>
function Interact.Prune(keep)
    for id in pairs(entries) do
        if not keep[id] then Interact.Remove(id) end
    end
end

function Interact.Clear()
    Interact.Prune({})
end
