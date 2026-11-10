-- Item Creator: validation, image download, registration through the
-- ox_inventory bridge and Discord logging. Every request is admin-checked here.
local ACE = ('command.%s'):format(Config.Commands[1])
local pending = {} -- image downloads waiting for the JS side
local requestId = 0
local busy = {}    -- [src] = true while a request is processed

local ERRORS = {
    no_permission      = 'この操作を行う権限がありません。',
    pending            = 'ブリッジは ox_inventory にインストール済みですが、まだ読み込まれていません。サーバーをもう一度再起動するか、サーバーコンソールで「refresh」→「ensure ox_inventory」を実行してください。',
    missing            = 'ブリッジを ox_inventory にインストールできませんでした。サーバーコンソールの [item_creator] のエラーを確認してください。',
    crashed            = 'ブリッジは読み込まれましたが起動に失敗しました。ox_inventory 起動時のコンソールエラーを確認してください。',
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
    image_save         = '画像をサーバーに保存できませんでした。ox_inventory/web/images フォルダの書き込み権限を確認してください。',
    save               = 'アイテムを登録できませんでした (%s)。',
}

local function isAdmin(src)
    return IsPlayerAceAllowed(tostring(src), ACE)
end

local function bridgeReady()
    return GetResourceState('ox_inventory') == 'started' and GlobalState['ox_inventory:creator'] ~= nil
end

---------------------------------------------------------------------------
-- Bridge installation (all file access goes through FiveM natives)
---------------------------------------------------------------------------
local OX = 'ox_inventory'
local SELF = GetCurrentResourceName()
local MARKER = '-- item_creator bridge'
local DATA_FILE = 'data/created_items.lua'

local function log(text)
    print(('^3[item_creator]^0 %s'):format(text))
end

---Where the bridge scripts live inside ox_inventory. Installs made by hand
---into "creator/" keep working; new installs use an existing folder, because
---SaveResourceFile cannot create folders.
---@return string serverPath, string clientPath, string manifest
local function bridgePaths()
    local manifest = LoadResourceFile(OX, 'fxmanifest.lua') or ''
    if manifest:find('creator/server.lua', 1, true) then
        return 'creator/server.lua', 'creator/client.lua', manifest
    end
    return 'modules/items/creator_server.lua', 'modules/items/creator_client.lua', manifest
end

local function write(resource, file, content, binary)
    return SaveResourceFile(resource, file, content, binary and #content or -1) and true or false
end

---@return boolean changed, string? error
local function install()
    local serverPath, clientPath, manifest = bridgePaths()
    if manifest == '' then return false, 'ox_inventory/fxmanifest.lua could not be read' end

    local changed = false

    for source, target in pairs({ ['bridge/server.lua'] = serverPath, ['bridge/client.lua'] = clientPath }) do
        local content = LoadResourceFile(SELF, source)
        if not content then return false, ('%s is missing from item_creator'):format(source) end
        if LoadResourceFile(OX, target) ~= content then
            if not write(OX, target, content) then return false, ('could not write ox_inventory/%s'):format(target) end
            changed = true
        end
    end

    -- Data file. Restored from the backup when ox_inventory was replaced by an update.
    if not LoadResourceFile(OX, DATA_FILE) then
        local backup = LoadResourceFile(SELF, 'backup/created_items.lua')
        if not write(OX, DATA_FILE, backup or 'return {}\n') then
            return false, ('could not write ox_inventory/%s'):format(DATA_FILE)
        end
        if backup then
            local chunk = load(backup, 'backup', 't', {})
            local ok, items = pcall(chunk or function() return {} end)
            for name in pairs(ok and type(items) == 'table' and items or {}) do
                local image = LoadResourceFile(SELF, ('backup/img_%s.png'):format(name))
                local target = ('web/images/%s.png'):format(name)
                if image and not LoadResourceFile(OX, target) then write(OX, target, image, true) end
            end
            log('restored created items and images from the backup.')
        end
        changed = true
    end

    if not manifest:find(MARKER, 1, true) then
        local block = ("\n%s (added automatically by the item_creator resource)\nserver_script '%s'\nclient_script '%s'\n")
            :format(MARKER, serverPath, clientPath)
        if not write(OX, 'fxmanifest.lua', manifest:gsub('%s*$', '\n') .. block) then
            return false, 'could not write ox_inventory/fxmanifest.lua'
        end
        changed = true
    end

    return changed
end

---Why the bridge is not running: 'pending' (installed, ox_inventory not reloaded
---since), 'missing' (files are not in ox_inventory) or 'crashed' (loaded but failed).
---@return string key of ERRORS, string english text for the console
local function bridgeProblem()
    local serverPath, clientPath, manifest = bridgePaths()

    if not manifest:find(MARKER, 1, true) or not LoadResourceFile(OX, serverPath) or not LoadResourceFile(OX, clientPath) then
        return 'missing', 'the bridge files are NOT in the ox_inventory folder (see the error above, or install them by hand - README).'
    end

    local running = false
    for i = 0, GetNumResourceMetadata(OX, 'server_script') - 1 do
        if GetResourceMetadata(OX, 'server_script', i) == serverPath then running = true end
    end

    if GetConvar('itemcreator:pendingRestart', 'false') == 'true' or not running then
        return 'pending', 'the bridge is installed, but ox_inventory has not been reloaded since. '
            .. 'Restart the server, or type: refresh  then  ensure ox_inventory'
    end
    return 'crashed', 'ox_inventory loaded the bridge but it did not start. Look for a script error / '
        .. '"[item_creator]" warning printed when ox_inventory started.'
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
-- Image download (HTTP in server/files.js, saving here)
---------------------------------------------------------------------------
local BASE64 = {}
do
    local alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    for i = 1, 64 do BASE64[alphabet:byte(i)] = i - 1 end
end

---@param data string base64
---@return string bytes
local function decodeBase64(data)
    data = data:gsub('[^%w%+/]', '')
    local out, n, length = {}, 0, #data

    for i = 1, length - 3, 4 do
        local a, b, c, d = data:byte(i, i + 3)
        local value = (BASE64[a] << 18) | (BASE64[b] << 12) | (BASE64[c] << 6) | BASE64[d]
        n = n + 1
        out[n] = string.char((value >> 16) & 255, (value >> 8) & 255, value & 255)
    end

    local rest = length % 4
    if rest == 3 then
        local a, b, c = data:byte(length - 2, length)
        local value = (BASE64[a] << 18) | (BASE64[b] << 12) | (BASE64[c] << 6)
        out[n + 1] = string.char((value >> 16) & 255, (value >> 8) & 255)
    elseif rest == 2 then
        local a, b = data:byte(length - 1, length)
        out[n + 1] = string.char((((BASE64[a] << 18) | (BASE64[b] << 12)) >> 16) & 255)
    end

    return table.concat(out)
end

AddEventHandler('item_creator:internal:downloaded', function(id, ok, result, base64)
    local waiting = pending[id]
    if waiting then
        pending[id] = nil
        waiting:resolve({ ok, result, base64 })
    end
end)

---Downloads the image and stores it as ox_inventory/web/images/<name>.png.
---ox_inventory only ships *.png, so every format gets that name; browsers
---detect the real format from the content.
---@return boolean ok, string result data URI or error key
local function downloadImage(url, name)
    requestId = requestId + 1
    local waiting = promise.new()
    pending[requestId] = waiting
    TriggerEvent('item_creator:internal:download', requestId, url, Config.Image.maxBytes, Config.Image.timeoutMs)

    local result = Citizen.Await(waiting)
    if result[1] ~= true then return false, result[2] end

    local mime, base64 = result[2], result[3]
    local bytes = decodeBase64(base64)

    if not write(OX, ('web/images/%s.png'):format(name), bytes, true) then return false, 'image_save' end
    write(SELF, ('backup/img_%s.png'):format(name), bytes, true)

    return true, ('data:%s;base64,%s'):format(mime, base64)
end

---Copy of the created items inside this resource (survives an ox_inventory update).
local function backupItems()
    local content = LoadResourceFile(OX, DATA_FILE)
    if content then write(SELF, 'backup/created_items.lua', content) end
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
    if not bridgeReady() then return false, ERRORS[(bridgeProblem())] end
    return { items = createdList(), limits = Config.Limits, maxImageKb = math.floor(Config.Image.maxBytes / 1024) }
end)

local function create(src, input)
    if not bridgeReady() then return false, ERRORS[(bridgeProblem())] end

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

    backupItems()
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
        local ok, changed, err = pcall(install)
        if not ok or err then
            log(('^1bridge installation failed: %s^0'):format(not ok and changed or err))
        elseif changed then
            -- Remembered for as long as this server process lives: ox_inventory was
            -- already running when its files were changed, so it has not loaded them.
            SetConvar('itemcreator:pendingRestart', 'true')
            log('^2The bridge was installed / updated in ox_inventory.^0')
            log('^1ox_inventory was already running, so it has not loaded it yet.^0')
            log('^1Restart the server now, or type: refresh  then  ensure ox_inventory^0')
            log('^1(今すぐサーバーを再起動するか、コンソールで refresh → ensure ox_inventory を実行してください)^0')
        end
    end

    Wait(3000)
    if bridgeReady() then
        log('^2ready^0 - the ox_inventory bridge is running.')
    else
        local _, text = bridgeProblem()
        log(('^1not active:^0 %s'):format(text))
    end
end)
