-- item_creator bridge (server). This file lives INSIDE ox_inventory and is
-- installed by the item_creator resource. It adds items to the running
-- inventory without a restart and stores them in data/created_items.lua.
if not lib then return end

local loaded, Items = pcall(require, 'modules.items.server')

if not loaded or type(Items) ~= 'table' then
    return warn('[item_creator] could not access the ox_inventory item list - bridge disabled')
end

local ItemList = Items()
local RESOURCE = GetCurrentResourceName()
local FILE = 'data/created_items.lua'

local created = {} -- [name] = item definition exactly as stored in the file
local session = {} -- [name] = image (data URI) of items created since the last start

local function useExport(resource, export)
    return function(...)
        return exports[resource][export](nil, ...)
    end
end

---Same rules as newItem() in modules/items/shared.lua (server side).
local function register(name, definition)
    local data = lib.table.deepclone(definition)
    data.name = name
    data.weight = data.weight or 0

    if data.close == nil then data.close = true end
    if data.stack == nil then data.stack = true end

    local clientData, serverData = data.client, data.server

    if not data.consume and ((clientData and (clientData.status or clientData.usetime or clientData.export))
        or (serverData and serverData.export)) then
        data.consume = 1
    end

    data.client = nil

    if serverData and serverData.export then
        data.cb = useExport(string.strsplit('.', serverData.export))
    end

    ItemList[name] = data
end

---------------------------------------------------------------------------
-- Persistence (data/created_items.lua)
---------------------------------------------------------------------------
local function serialize(value, depth)
    local kind = type(value)

    if kind == 'string' then return ('%q'):format(value) end
    if kind == 'number' then return tostring(math.tointeger(value) or value) end
    if kind == 'boolean' then return tostring(value) end
    if kind ~= 'table' then return 'nil' end

    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

    local pad = ('\t'):rep(depth + 1)
    local lines = {}

    for i = 1, #keys do
        local key = keys[i]
        local label = type(key) == 'string' and key:match('^[%a_][%w_]*$') and depth > 0 and key
            or ('[%s]'):format(serialize(key, 0))
        lines[i] = ('%s%s = %s,'):format(pad, label, serialize(value[key], depth + 1))
    end

    if #lines == 0 then return '{}' end
    return ('{\n%s\n%s}'):format(table.concat(lines, '\n'), ('\t'):rep(depth))
end

local function save()
    local content = ('-- Items created in-game with item_creator. This file is generated: it is\n'
        .. '-- rewritten every time an item is created or edited.\nreturn %s\n'):format(serialize(created, 0))
    SaveResourceFile(RESOURCE, FILE, content, -1)
end

do
    local content = LoadResourceFile(RESOURCE, FILE)
    local chunk = content and load(content, ('@@%s/%s'):format(RESOURCE, FILE), 't', {})
    local ok, result = pcall(chunk or function() return {} end)

    if not ok or type(result) ~= 'table' then
        warn(('[item_creator] %s could not be read: %s'):format(FILE, result))
        result = {}
    end

    local count = 0
    for name, definition in pairs(result) do
        if type(name) == 'string' and type(definition) == 'table' then
            created[name] = definition
            local success, err = pcall(register, name, definition)
            if success then count = count + 1 else warn(('[item_creator] item "%s": %s'):format(name, err)) end
        end
    end

    if count > 0 then
        print(('[item_creator] loaded %d created item(s)'):format(count))
    end
end

---------------------------------------------------------------------------
-- API used by the item_creator resource
---------------------------------------------------------------------------
---@return 'free'|'created'|'base'
exports('CreatorCheck', function(name)
    if created[name] then return 'created' end
    if ItemList[name] then return 'base' end
    return 'free'
end)

exports('CreatorList', function()
    return created
end)

---Adds or updates an item. It is usable immediately on the server and on every client.
---@param name string
---@param definition table ox_inventory item definition (plain data only)
---@param image? string data URI shown until the next restart (after that web/images/<name>.png is used)
---@return boolean ok, string? error
exports('CreatorSave', function(name, definition, image)
    if type(name) ~= 'string' or not name:match('^[a-z0-9_]+$') then return false, 'invalid_name' end
    if type(definition) ~= 'table' or type(definition.label) ~= 'string' then return false, 'invalid_definition' end
    if ItemList[name] and not created[name] then return false, 'exists' end

    local ok, err = pcall(register, name, definition)
    if not ok then return false, tostring(err) end

    created[name] = definition
    if type(image) == 'string' then
        session[name] = image
    elseif session[name] == nil then
        session[name] = false -- edited without a new image: clients still need the new definition
    end
    save()

    TriggerLatentClientEvent('ox_inventory:creator:items', -1, 1000000, {
        { name = name, definition = definition, image = session[name] or nil },
    })
    return true
end)

---Saves an item picture as web/images/<name>.png. Done here because some servers
---only let a resource write inside its own folder.
---@param name string
---@param bytes string raw image data
---@return boolean saved
exports('CreatorSaveImage', function(name, bytes)
    if type(name) ~= 'string' or not name:match('^[a-z0-9_]+$') or type(bytes) ~= 'string' then return false end
    local file = ('web/images/%s.png'):format(name)
    if not SaveResourceFile(RESOURCE, file, bytes, #bytes) then return false end
    return LoadResourceFile(RESOURCE, file) == bytes
end)

-- A client that just loaded asks for everything created since the server started
-- (its downloaded data/created_items.lua is the version from server start).
RegisterNetEvent('ox_inventory:creator:request', function()
    local source = source
    local list = {}

    for name, image in pairs(session) do
        list[#list + 1] = { name = name, definition = created[name], image = image or nil }
    end

    if #list > 0 then
        TriggerLatentClientEvent('ox_inventory:creator:items', source, 1000000, list)
    end
end)

-- "heal" is a custom property: restore health once the item was really used.
AddEventHandler('ox_inventory:usedItem', function(playerId, name)
    local definition = created[name]

    if definition and type(definition.heal) == 'number' and definition.heal > 0 then
        TriggerClientEvent('ox_inventory:creator:heal', playerId, definition.heal)
    end
end)

GlobalState['ox_inventory:creator'] = 1
