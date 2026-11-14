--[[ パーティー (メモリ上で管理。再起動でリセット) ]]
Parties = {}
local byId, ofPlayer, invites = {}, {}, {}
local nextId = 1

local function memberInfo(src)
    local cid = Bridge.GetCitizenId(src)
    local c = cid and Chars.Get(cid)
    local role = c and c.role
    return {
        id = src, name = Bridge.GetName(src),
        role = role, roleLabel = role and Config.Roles[role].label or '未選択',
        roleColor = role and Config.Roles[role].color or '#888',
    }
end

function Parties.Get(src)
    local id = ofPlayer[src]
    return id and byId[id] or nil
end

function Parties.Members(party)
    local out = {}
    for _, s in ipairs(party.members) do out[#out + 1] = s end
    return out
end

function Parties.Push(party)
    if not party then return end
    for _, s in ipairs(party.members) do
        TriggerClientEvent('projectin_rpg:client:partyChanged', s)
    end
end

function Parties.Payload(src)
    local party = Parties.Get(src)
    local pending = {}
    for pid, exp in pairs(invites[src] or {}) do
        local p = byId[pid]
        if p and exp > os.time() then
            pending[#pending + 1] = { partyId = pid, leaderName = Bridge.GetName(p.leader), size = #p.members }
        end
    end
    if not party then return { party = nil, invites = pending, maxSize = Config.Party.maxSize } end
    local members = {}
    for _, s in ipairs(party.members) do
        local m = memberInfo(s)
        m.leader = s == party.leader
        members[#members + 1] = m
    end
    return {
        party = { id = party.id, leader = party.leader, isLeader = party.leader == src, members = members },
        invites = pending, maxSize = Config.Party.maxSize,
    }
end

function Parties.Create(src)
    if ofPlayer[src] then return Parties.Get(src) end
    local id = nextId
    nextId = nextId + 1
    local party = { id = id, leader = src, members = { src } }
    byId[id] = party
    ofPlayer[src] = id
    Parties.Push(party)
    return party
end

local function busy(src)
    return Instances.GetRunOf(src) ~= nil
end

function Parties.Invite(src, target)
    target = tonumber(target)
    if not target or target == src or not GetPlayerName(target) then return false, 'プレイヤーが見つかりません' end
    if not Bridge.GetCitizenId(target) then return false, '相手はキャラクター選択中です' end
    if busy(src) then return false, 'ダンジョン中はパーティーを変更できません' end
    local party = Parties.Get(src) or Parties.Create(src)
    if party.leader ~= src then return false, 'リーダーのみ招待できます' end
    if #party.members >= Config.Party.maxSize then return false, 'パーティーが満員です' end
    if ofPlayer[target] then return false, '相手は既に別のパーティーに所属しています' end
    invites[target] = invites[target] or {}
    invites[target][party.id] = os.time() + Config.Party.inviteTimeout
    TriggerClientEvent('projectin_rpg:client:partyInvite', target, { partyId = party.id, leaderName = Bridge.GetName(src), timeout = Config.Party.inviteTimeout })
    return true, ('%s を招待しました'):format(Bridge.GetName(target))
end

function Parties.Accept(src, partyId)
    partyId = tonumber(partyId)
    local exp = invites[src] and invites[src][partyId]
    if not exp or exp < os.time() then return false, '招待の有効期限が切れています' end
    invites[src][partyId] = nil
    if ofPlayer[src] then return false, '既にパーティーに所属しています' end
    if busy(src) then return false, 'ダンジョン中は参加できません' end
    local party = byId[partyId]
    if not party then return false, 'パーティーが解散しました' end
    if busy(party.leader) then return false, 'パーティーはダンジョン攻略中です' end
    if #party.members >= Config.Party.maxSize then return false, 'パーティーが満員です' end
    party.members[#party.members + 1] = src
    ofPlayer[src] = party.id
    Parties.Push(party)
    return true, 'パーティーに参加しました'
end

function Parties.Decline(src, partyId)
    if invites[src] then invites[src][tonumber(partyId) or -1] = nil end
    return true
end

local function removeMember(party, src)
    for i, s in ipairs(party.members) do
        if s == src then table.remove(party.members, i) break end
    end
    ofPlayer[src] = nil
    TriggerClientEvent('projectin_rpg:client:partyChanged', src)
    if #party.members == 0 then
        byId[party.id] = nil
        return
    end
    if party.leader == src then party.leader = party.members[1] end
    Parties.Push(party)
end

function Parties.Leave(src, force)
    local party = Parties.Get(src)
    if not party then return false, 'パーティーに所属していません' end
    if busy(src) and not force then return false, 'ダンジョン中は脱退できません(先に離脱してください)' end
    removeMember(party, src)
    return true, 'パーティーを脱退しました'
end

function Parties.Kick(src, target)
    target = tonumber(target)
    local party = Parties.Get(src)
    if not party or party.leader ~= src then return false, 'リーダーのみ実行できます' end
    if target == src then return false, '自分はキックできません' end
    if ofPlayer[target] ~= party.id then return false, 'メンバーではありません' end
    if busy(src) then return false, 'ダンジョン中は変更できません' end
    removeMember(party, target)
    Bridge.Notify(target, 'パーティーから外されました', 'warning')
    return true
end

function Parties.Promote(src, target)
    target = tonumber(target)
    local party = Parties.Get(src)
    if not party or party.leader ~= src then return false, 'リーダーのみ実行できます' end
    if ofPlayer[target] ~= party.id then return false, 'メンバーではありません' end
    party.leader = target
    Parties.Push(party)
    return true
end

-- 近くのプレイヤー一覧 (招待UI用)
function Parties.Nearby(src)
    local out = {}
    local myPed = GetPlayerPed(src)
    if myPed == 0 then return out end
    local my = GetEntityCoords(myPed)
    local myBucket = GetPlayerRoutingBucket(src)
    for _, sid in ipairs(GetPlayers()) do
        local s = tonumber(sid)
        if s ~= src and GetPlayerRoutingBucket(s) == myBucket and Bridge.GetCitizenId(s) then
            local ped = GetPlayerPed(s)
            if ped ~= 0 and #(GetEntityCoords(ped) - my) < 30.0 then
                out[#out + 1] = { id = s, name = Bridge.GetName(s), inParty = ofPlayer[s] ~= nil }
            end
        end
    end
    return out
end

AddEventHandler('playerDropped', function()
    local src = source
    invites[src] = nil
    local party = Parties.Get(src)
    if party then removeMember(party, src) end
end)
