-- Item Creator: validation, image download, registration through the
-- ox_inventory bridge and Discord logging. Every request is admin-checked here.
local ACE = ('command.%s'):format(Config.Commands[1])
local pending = {} -- image downloads waiting for the JS side
local requestId = 0
local busy = {}    -- [src] = true while a request is processed

local ERRORS = {
    no_permission      = 'この操作を行う権限がありません。',
    not_ready          = 'ox_inventory にブリッジがまだ読み込まれていません。サーバーを一度再起動してください。',
    busy               = '処理中です。少しお待ちください。',
    invalid_data       = '入力内容が正しくありません。',
    name               = 'スポーン名は半角の小文字英数字とアンダースコア (a-z, 0-9, _) で入力してください。',
    label              = '表示名を入力してください。',
    exists             = 'そのスポーン名は ox_inventory に既に存在します。',
    export             = 'エクスポートは「リソース名.関数名」の形式で入力してください。',
    image_required     = '画像URLを入力してください。',
    invalid_url        = '画像URLが正しくありません (http / https のみ)。',
    not_image          = 'URLの内容が画像ではありません (PNG / JPEG / WebP / GIF)。',
    too_large          = '画像が大きすぎます。',
    timeout            = '画像のダウンロードがタイムアウトしました。',
    too_many_redirects = '画像URLのリダイレクトが多すぎます。',
    download           = '画像をダウンロードできませんでした (%s)。',
    save               = 'アイテムを登録できませんでした (%s)。',
}

local function isAdmin(src)
    return IsPlayerAceAllowed(tostring(src), ACE)
end

local function bridgeReady()
    return GetResourceState('ox_inventory') == 'started' and GlobalState['ox_inventory:creator'] ~= nil
end

---------------------------------------------------------------------------
-- Input validation
---------------------------------------------------------------------------
local function cleanText(value, maxLength)
    if type(value) ~= 'string' then return '' end
    value = value:gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    local length = utf8.len(value)
    if not length then return '' end
    if length > maxLength then
        value = value:sub(1, utf8.offset(value, maxLength + 1) - 1)
    end
    return value
end

local function cleanNumber(value, max)
    value = tonumber(value)
    if not value or value ~= value or value < 0 then return 0 end
    return math.min(max, math.floor(value + 0.5))
end

---Turns the form into an ox_inventory item definition.
---@return string? name, table|string definition or error key
local function buildItem(input)
    if type(input) ~= 'table' then return nil, 'invalid_data' end

    local name = type(input.name) == 'string' and input.name or ''
    if #name < 1 or #name > Config.Limits.name or not name:match('^[a-z0-9_]+$') then return nil, 'name' end

    local label = cleanText(input.label, Config.Limits.label)
    if label == '' then return nil, 'label' end

    local description = cleanText(input.description, Config.Limits.description)
    local heal = input.healEnabled and cleanNumber(input.heal, 100) or 0
    local hunger = input.hungerEnabled and cleanNumber(input.hunger, 100) or 0
    local thirst = input.thirstEnabled and cleanNumber(input.thirst, 100) or 0
    local stress = input.stressEnabled and cleanNumber(input.stress, 100) or 0

    local definition = {
        label = label,
        weight = cleanNumber(input.weight, Config.Limits.weight),
        stack = input.stack == true,
        close = true,
        description = description ~= '' and description or nil,
        heal = heal > 0 and heal or nil,
    }

    -- Qbox reads these as percentages of the hunger / thirst / stress bars.
    local status = {}
    if hunger > 0 then status.hunger = hunger end
    if thirst > 0 then status.thirst = thirst end
    if stress > 0 then status.stress = -stress end

    if heal > 0 or next(status) then
        local client = { usetime = Config.UseTime, cancel = true }
        if next(status) then client.status = status end
        if hunger > 0 then
            client.anim = 'eating'
        elseif thirst > 0 then
            client.anim = { dict = 'mp_player_intdrink', clip = 'loop_bottle' }
        end
        definition.client = client
    end

    if input.exportEnabled then
        local export = type(input.export) == 'string' and input.export:gsub('%s', '') or ''
        if #export > 120 or not export:match('^[%w_%-]+%.[%w_]+$') then return nil, 'export' end
        if input.exportSide == 'server' then
            definition.server = { export = export }
        else
            definition.client = definition.client or {}
            definition.client.export = export
        end
    end

    return name, definition
end

---------------------------------------------------------------------------
-- Image download (done by server/files.js)
---------------------------------------------------------------------------
AddEventHandler('item_creator:internal:downloaded', function(id, ok, result)
    local waiting = pending[id]
    if waiting then
        pending[id] = nil
        waiting:resolve({ ok, result })
    end
end)

---@return boolean ok, string result data URI or error key
local function downloadImage(url, name)
    requestId = requestId + 1
    local waiting = promise.new()
    pending[requestId] = waiting
    TriggerEvent('item_creator:internal:download', requestId, url, name, Config.Image.maxBytes, Config.Image.timeoutMs)
    local result = Citizen.Await(waiting)
    return result[1] == true, result[2]
end

---------------------------------------------------------------------------
-- Discord
---------------------------------------------------------------------------
local function setting(convar, fallback)
    local value = GetConvar(convar, '')
    return value ~= '' and value or fallback or ''
end

local function yesNo(value)
    return value and 'はい' or 'いいえ'
end

local function discordLog(src, name, definition, imageUrl, edited)
    local webhook = setting('itemcreator:webhook', Config.Discord.webhook)
    local token = setting('itemcreator:botToken', Config.Discord.botToken)
    local channel = setting('itemcreator:channelId', Config.Discord.channelId)
    if webhook == '' and (token == '' or channel == '') then return end

    local client, server = definition.client or {}, definition.server or {}
    local status = client.status or {}
    local export = client.export and ('クライアント: `%s`'):format(client.export)
        or server.export and ('サーバー: `%s`'):format(server.export) or 'なし'

    local discordId = GetPlayerIdentifierByType(tostring(src), 'discord')
    local license = GetPlayerIdentifierByType(tostring(src), 'license2') or GetPlayerIdentifierByType(tostring(src), 'license')
    local admin = ('%s (ID %s)%s\n`%s`'):format(GetPlayerName(src) or '?', src,
        discordId and (' <@%s>'):format(discordId:gsub('discord:', '')) or '', license or 'license: ?')

    local embed = {
        title = edited and 'アイテムが編集されました' or 'アイテムが作成されました',
        color = Config.Discord.colour,
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        fields = {
            { name = 'スポーン名', value = ('`%s`'):format(name), inline = true },
            { name = '表示名', value = definition.label, inline = true },
            { name = '重さ', value = ('%d g'):format(definition.weight), inline = true },
            { name = 'スタック', value = yesNo(definition.stack), inline = true },
            { name = 'エクスポート', value = export, inline = true },
            { name = '体力回復', value = definition.heal and ('%d%%'):format(definition.heal) or 'なし', inline = true },
            { name = '空腹回復', value = status.hunger and ('%d%%'):format(status.hunger) or 'なし', inline = true },
            { name = '喉の渇き回復', value = status.thirst and ('%d%%'):format(status.thirst) or 'なし', inline = true },
            { name = 'ストレス軽減', value = status.stress and ('%d%%'):format(-status.stress) or 'なし', inline = true },
            { name = '説明', value = definition.description or 'なし', inline = false },
            { name = '作成者', value = admin, inline = false },
        },
    }
    if imageUrl and imageUrl ~= '' then
        embed.thumbnail = { url = imageUrl }
        embed.fields[#embed.fields + 1] = { name = '画像URL', value = imageUrl:sub(1, 1000), inline = false }
    end

    local function done(status)
        if status < 200 or status >= 300 then
            print(('^3[item_creator]^0 Discord log failed (HTTP %s)'):format(status))
        end
    end

    if token ~= '' and channel ~= '' then
        PerformHttpRequest(('https://discord.com/api/v10/channels/%s/messages'):format(channel), done, 'POST',
            json.encode({ embeds = { embed } }),
            { ['Content-Type'] = 'application/json', ['Authorization'] = ('Bot %s'):format(token) })
    else
        PerformHttpRequest(webhook, done, 'POST',
            json.encode({ username = Config.Discord.username, embeds = { embed } }),
            { ['Content-Type'] = 'application/json' })
    end
end

---------------------------------------------------------------------------
-- Callbacks
---------------------------------------------------------------------------
local function createdList()
    local list = {}
    for name, definition in pairs(exports.ox_inventory:CreatorList() or {}) do
        list[#list + 1] = { name = name, definition = definition }
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

lib.callback.register('item_creator:getData', function(src)
    if not isAdmin(src) then return false, ERRORS.no_permission end
    if not bridgeReady() then return false, ERRORS.not_ready end
    return { items = createdList(), limits = Config.Limits, maxImageKb = math.floor(Config.Image.maxBytes / 1024) }
end)

local function create(src, input)
    if not bridgeReady() then return false, ERRORS.not_ready end

    local name, definition = buildItem(input)
    if not name then return false, ERRORS[definition] or ERRORS.invalid_data end

    local state = exports.ox_inventory:CreatorCheck(name)
    if state == 'base' then return false, ERRORS.exists end
    local edited = state == 'created'

    -- A new item needs an image; an edited item keeps its image when the field is empty.
    local imageUrl = type(input.image) == 'string' and input.image:gsub('^%s+', ''):gsub('%s+$', '') or ''
    local image
    if imageUrl ~= '' then
        local ok, result = downloadImage(imageUrl, name)
        if not ok then return false, ERRORS[result] or ERRORS.download:format(result) end
        image = result
    elseif not edited then
        return false, ERRORS.image_required
    end

    local ok, err = exports.ox_inventory:CreatorSave(name, definition, image)
    if not ok then return false, err == 'exists' and ERRORS.exists or ERRORS.save:format(err) end

    TriggerEvent('item_creator:internal:backup')
    discordLog(src, name, definition, imageUrl, edited)
    print(('^3[item_creator]^0 %s (ID %s) %s item "%s"'):format(GetPlayerName(src), src, edited and 'edited' or 'created', name))

    return true, { name = name, edited = edited, items = createdList() }
end

lib.callback.register('item_creator:create', function(src, input)
    if not isAdmin(src) then
        print(('^3[item_creator]^0 player %s tried to create an item without permission'):format(src))
        return false, ERRORS.no_permission
    end
    if busy[src] then return false, ERRORS.busy end

    busy[src] = true
    local ok, success, result = pcall(create, src, input)
    busy[src] = nil

    if not ok then
        print(('^1[item_creator] error: %s^0'):format(success))
        return false, ERRORS.invalid_data
    end
    return success, result
end)

AddEventHandler('playerDropped', function()
    busy[source] = nil
end)

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------
local function open(source)
    if source == 0 then return end
    TriggerClientEvent('item_creator:open', source)
end

lib.addCommand(Config.Commands, {
    help = 'ox_inventory のアイテムを作成する (管理者)',
    restricted = Config.AdminGroups,
}, open)

if Config.CreateSubcommand then
    lib.addCommand('create', {
        help = '/create item - アイテムを作成する (管理者)',
        restricted = Config.AdminGroups,
        params = { { name = 'type', type = 'string', help = 'item' } },
    }, function(source, args)
        if args.type == 'item' then open(source) end
    end)
end

CreateThread(function()
    if Config.AutoInstall then
        TriggerEvent('item_creator:internal:install')
    end
    Wait(3000)
    if not bridgeReady() then
        print('^3[item_creator]^0 ox_inventory is not running the bridge yet. '
            .. (Config.AutoInstall and 'Restart the server once.' or 'Install the bridge manually (see README).'))
    end
end)
