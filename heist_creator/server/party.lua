-- Party management. Parties only exist in memory.
Party = {
    list = {},     -- [partyId] = { id, leader, members = { src, ... }, session = sessionId? }
    byPlayer = {}, -- [src] = partyId
    invites = {},  -- [targetSrc][partyId] = { from = name, expires = unix }
}

local nextId = 0

local function notify(src, message, kind)
    TriggerClientEvent('heist_creator:client:notify', src, message, kind or 'info')
end

---@param src number
function Party.Get(src)
    local id = Party.byPlayer[src]
    return id and Party.list[id] or nil
end

---@param party table
function Party.Snapshot(party)
    local members = {}
    for i = 1, #party.members do
        local src = party.members[i]
        members[i] = { id = src, name = Framework.GetName(src), leader = src == party.leader }
    end
    return {
        id = party.id,
        leader = party.leader,
        members = members,
        inHeist = party.session ~= nil,
        max = Config.Party.maxSize,
    }
end

---@param party table
function Party.Broadcast(party)
    local snapshot = Party.Snapshot(party)
    for i = 1, #party.members do
        TriggerClientEvent('heist_creator:client:partyUpdate', party.members[i], snapshot)
    end
end

---@param src number
---@return table? party, string? error
function Party.Create(src)
    if Party.Get(src) then return nil, L('party_already_in') end
    if not Framework.GetIdentifier(src) then return nil, L('not_loaded') end
    nextId = nextId + 1
    local party = { id = nextId, leader = src, members = { src } }
    Party.list[party.id] = party
    Party.byPlayer[src] = party.id
    Party.invites[src] = nil
    Party.Broadcast(party)
    return party
end

---Valid (not expired) invites of a player.
---@param src number
function Party.GetInvites(src)
    local result = {}
    local invites = Party.invites[src]
    if not invites then return result end
    local now = os.time()
    for partyId, invite in pairs(invites) do
        if invite.expires <= now or not Party.list[partyId] then
            invites[partyId] = nil
        else
            result[#result + 1] = { partyId = partyId, from = invite.from, expires = invite.expires - now }
        end
    end
    return result
end

local function countInvites(partyId)
    local count, now = 0, os.time()
    for _, invites in pairs(Party.invites) do
        local invite = invites[partyId]
        if invite and invite.expires > now then count = count + 1 end
    end
    return count
end

---@param src number leader
---@param target number
---@return boolean ok, string message
function Party.Invite(src, target)
    target = tonumber(target)
    if not target or target == src then return false, L('party_invalid_target') end
    if not Framework.GetIdentifier(target) then return false, L('party_invalid_target') end

    local party = Party.Get(src)
    if not party then
        local err
        party, err = Party.Create(src)
        if not party then return false, err end
    end
    if party.leader ~= src then return false, L('party_not_leader') end
    if party.session then return false, L('party_in_heist') end
    if Party.Get(target) then return false, L('party_target_busy') end
    if #party.members + countInvites(party.id) >= Config.Party.maxSize then return false, L('party_full') end

    Party.invites[target] = Party.invites[target] or {}
    if Party.invites[target][party.id] and Party.invites[target][party.id].expires > os.time() then
        return false, L('party_already_invited')
    end

    local name = Framework.GetName(src)
    Party.invites[target][party.id] = { from = name, expires = os.time() + Config.Party.inviteTimeout }
    TriggerClientEvent('heist_creator:client:invited', target, name, Config.Commands.accept, Config.Commands.decline)
    return true, L('party_invite_sent', Framework.GetName(target))
end

local function latestInvite(src)
    local best, bestExpiry
    for _, invite in ipairs(Party.GetInvites(src)) do
        if not bestExpiry or invite.expires > bestExpiry then
            best, bestExpiry = invite.partyId, invite.expires
        end
    end
    return best
end

---@param src number
---@param partyId? number defaults to the latest invite
function Party.Accept(src, partyId)
    partyId = tonumber(partyId) or latestInvite(src)
    local invites = Party.invites[src]
    local invite = partyId and invites and invites[partyId]
    if not invite or invite.expires <= os.time() then return false, L('party_no_invite') end
    invites[partyId] = nil

    local party = Party.list[partyId]
    if not party then return false, L('party_no_invite') end
    if Party.Get(src) then return false, L('party_already_in') end
    if party.session then return false, L('party_in_heist') end
    if #party.members >= Config.Party.maxSize then return false, L('party_full') end

    party.members[#party.members + 1] = src
    Party.byPlayer[src] = party.id
    Party.invites[src] = nil

    local name = Framework.GetName(src)
    for i = 1, #party.members do
        if party.members[i] ~= src then
            notify(party.members[i], L('party_joined', name), 'success')
        end
    end
    Party.Broadcast(party)
    return true, L('party_you_joined')
end

---@param src number
---@param partyId? number
function Party.Decline(src, partyId)
    partyId = tonumber(partyId) or latestInvite(src)
    local invites = Party.invites[src]
    if not partyId or not invites or not invites[partyId] then return false, L('party_no_invite') end
    invites[partyId] = nil
    local party = Party.list[partyId]
    if party then
        notify(party.leader, L('party_declined', Framework.GetName(src)), 'error')
    end
    return true, L('party_you_declined')
end

---Removes a player from their party (leave, kick, disconnect).
---@param src number
---@param silent? boolean do not notify the leaving player (disconnect)
function Party.Leave(src, silent)
    local party = Party.Get(src)
    if not party then return false, L('party_none') end

    local name = Framework.GetName(src)
    Utils.RemoveValue(party.members, src)
    Party.byPlayer[src] = nil

    if party.leader == src and #party.members > 0 then
        party.leader = party.members[1]
        notify(party.leader, L('party_new_leader'), 'info')
    end

    if party.session then
        Sessions.RemoveMember(party.session, src, silent)
    end

    if #party.members == 0 then
        Party.list[party.id] = nil
    else
        for i = 1, #party.members do
            notify(party.members[i], L('party_left', name), 'info')
        end
        Party.Broadcast(party)
        if party.session then Sessions.Sync(party.session) end
    end

    if not silent then
        TriggerClientEvent('heist_creator:client:partyUpdate', src, nil)
    end
    return true, L('party_you_left')
end

---@param src number leader
---@param target number
function Party.Kick(src, target)
    target = tonumber(target)
    local party = Party.Get(src)
    if not party then return false, L('party_none') end
    if party.leader ~= src then return false, L('party_not_leader') end
    if party.session then return false, L('party_in_heist') end
    if not target or target == src or Party.byPlayer[target] ~= party.id then
        return false, L('party_invalid_target')
    end
    Party.Leave(target)
    notify(target, L('party_kicked'), 'error')
    return true, L('party_kick_done')
end

---Players close to the caller that can be invited.
---@param src number
function Party.Nearby(src)
    local result = {}
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return result end
    local coords = GetEntityCoords(ped)

    for _, id in ipairs(GetPlayers()) do
        local target = tonumber(id)
        if target and target ~= src and not Party.byPlayer[target] then
            local targetPed = GetPlayerPed(target)
            if targetPed and targetPed ~= 0
                and #(coords - GetEntityCoords(targetPed)) <= Config.Party.nearbyDistance
                and Framework.GetIdentifier(target) then
                result[#result + 1] = { id = target, name = Framework.GetName(target) }
            end
        end
    end
    return result
end

---Cleanup when a player disconnects or logs out of their character.
---@param src number
function Party.PlayerDropped(src)
    Party.invites[src] = nil
    if Party.Get(src) then
        Party.Leave(src, true)
    end
end
