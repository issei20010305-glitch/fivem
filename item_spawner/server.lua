-- Admin item spawner. The client only asks; the permission, the item and the
-- amount are all checked here before anything is given.
local ACE = ('command.%s'):format(Config.Commands[1])

local function isAdmin(src)
    return IsPlayerAceAllowed(tostring(src), ACE)
end

---Names of the items made with item_creator (empty when it is not installed).
local function createdItems()
    local names = {}
    local ok, created = pcall(function() return exports.ox_inventory:CreatorList() end)
    if ok and type(created) == 'table' then
        for name in pairs(created) do names[#names + 1] = name end
    end
    return names
end

local function discordLog(src, target, name, label, amount)
    local webhook = GetConvar('itemspawner:webhook', '')
    if webhook == '' then webhook = Config.Webhook end
    if webhook == '' then return end

    local license = GetPlayerIdentifierByType(tostring(src), 'license2') or GetPlayerIdentifierByType(tostring(src), 'license') or '?'
    PerformHttpRequest(webhook, function() end, 'POST', json.encode({
        username = 'Item Spawner',
        embeds = { {
            title = 'アイテムがスポーンされました',
            color = 0x8fb8ea,
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
            fields = {
                { name = 'アイテム', value = ('%s (`%s`)'):format(label, name), inline = true },
                { name = '数量', value = tostring(amount), inline = true },
                { name = '付与先', value = ('%s (ID %s)'):format(GetPlayerName(target) or '?', target), inline = true },
                { name = '管理者', value = ('%s (ID %s)\n`%s`'):format(GetPlayerName(src) or '?', src, license), inline = false },
            },
        } },
    }), { ['Content-Type'] = 'application/json' })
end

lib.callback.register('item_spawner:getData', function(src)
    if not isAdmin(src) then return false end
    return {
        created = createdItems(),
        maxAmount = Config.MaxAmount,
        quickAmounts = Config.QuickAmounts,
        allowOthers = Config.AllowGiveToOthers,
        selfId = src,
    }
end)

lib.callback.register('item_spawner:give', function(src, name, amount, target)
    if not isAdmin(src) then
        print(('^3[item_spawner]^0 player %s tried to spawn an item without permission'):format(src))
        return false, 'この操作を行う権限がありません。'
    end

    if type(name) ~= 'string' or #name > 80 then return false, 'アイテムが正しくありません。' end
    local item = exports.ox_inventory:Items(name)
    if not item then return false, 'そのアイテムは存在しません。' end

    amount = math.floor(tonumber(amount) or 0)
    if amount < 1 then return false, '数量は1以上にしてください。' end
    if amount > Config.MaxAmount then amount = Config.MaxAmount end

    target = tonumber(target) or src
    if target ~= src then
        if not Config.AllowGiveToOthers then return false, '他のプレイヤーへの付与は無効になっています。' end
        if not GetPlayerName(target) then return false, ('ID %s のプレイヤーはオンラインではありません。'):format(target) end
    end

    if not exports.ox_inventory:CanCarryItem(target, item.name, amount) then
        return false, 'インベントリに空きがありません (重量またはスロット)。'
    end

    local success, response = exports.ox_inventory:AddItem(target, item.name, amount)
    if not success then
        return false, ('付与できませんでした (%s)。'):format(tostring(response))
    end

    print(('^3[item_spawner]^0 %s (ID %s) gave %dx %s to ID %s'):format(GetPlayerName(src), src, amount, item.name, target))
    discordLog(src, target, item.name, item.label or item.name, amount)

    return true, target == src
        and ('%s を %d 個入手しました。'):format(item.label or item.name, amount)
        or ('%s を %d 個、ID %s に付与しました。'):format(item.label or item.name, amount, target)
end)

lib.addCommand(Config.Commands, {
    help = 'アイテムスポナーを開く (管理者)',
    restricted = Config.AdminGroups,
}, function(source)
    if source == 0 then return end
    TriggerClientEvent('item_spawner:open', source)
end)
