RPG = RPG or {}
local U = {}
RPG.Utils = U

function U.deepcopy(v, seen)
    if type(v) ~= 'table' then return v end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local out = {}
    seen[v] = out
    for k, val in pairs(v) do out[U.deepcopy(k, seen)] = U.deepcopy(val, seen) end
    return out
end

function U.clamp(n, lo, hi)
    n = tonumber(n) or lo
    if n ~= n then n = lo end -- NaN
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end

function U.round(n, d)
    local m = 10 ^ (d or 0)
    return math.floor(n * m + 0.5) / m
end

function U.dist(a, b)
    local dx, dy, dz = (a.x - b.x), (a.y - b.y), ((a.z or 0) - (b.z or 0))
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function U.dist2d(a, b)
    local dx, dy = (a.x - b.x), (a.y - b.y)
    return math.sqrt(dx * dx + dy * dy)
end

function U.tcount(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

---------------------------------------------------------------------------
-- 日本時間 (エポック秒はUTC基準。表示のみJSTへ変換)
---------------------------------------------------------------------------
function U.jst(ts)
    return os.date('!*t', math.floor(ts) + Config.TimezoneOffset)
end

-- JSTの年月日時分 -> エポック秒 (24:00 も翌日0:00として許容)
function U.jstToEpoch(y, mo, d, h, mi)
    -- os.time は環境のローカルTZを使うため、UTC基準で計算する
    local days = U.daysFromCivil(y, mo, d)
    return days * 86400 + (h or 0) * 3600 + (mi or 0) * 60 - Config.TimezoneOffset
end

-- Howard Hinnant のアルゴリズム (1970-01-01 からの日数)
function U.daysFromCivil(y, m, d)
    y = (m <= 2) and (y - 1) or y
    local era = (y >= 0 and y or y - 399) // 400
    local yoe = y - era * 400
    local mp = (m + 9) % 12
    local doy = (153 * mp + 2) // 5 + d - 1
    local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
    return era * 146097 + doe - 719468
end

-- "2026-11-14 24:00" / "2026/11/14 21:30" をパース
function U.parseJst(str)
    if type(str) ~= 'string' then return nil end
    local y, mo, d, h, mi = str:match('^%s*(%d%d%d%d)[-/](%d%d?)[-/](%d%d?)[ T](%d%d?):(%d%d)%s*$')
    if not y then return nil end
    y, mo, d, h, mi = tonumber(y), tonumber(mo), tonumber(d), tonumber(h), tonumber(mi)
    if mo < 1 or mo > 12 or d < 1 or d > 31 or h < 0 or h > 24 or mi < 0 or mi > 59 then return nil end
    if h == 24 and mi ~= 0 then return nil end
    return U.jstToEpoch(y, mo, d, h, mi)
end

function U.formatJst(ts)
    local t = U.jst(ts)
    return string.format('%04d-%02d-%02d %02d:%02d', t.year, t.month, t.day, t.hour, t.min)
end

local function jstDayIndex(ts) return (math.floor(ts) + Config.TimezoneOffset) // 86400 end

-- 「本日24時」「明日18時30分」「11月20日 21:00」 のような自然な日本語
function U.formatJstRelativeDay(ts, now)
    now = now or os.time()
    local dayNow, dayTs = jstDayIndex(now), jstDayIndex(ts)
    local t = U.jst(ts)
    local function hm(hour, min)
        if min == 0 then return string.format('%d時', hour) end
        return string.format('%d時%d分', hour, min)
    end
    -- 0:00ちょうどは「前日の24時」と表現する
    if t.hour == 0 and t.min == 0 then
        if dayTs - 1 == dayNow then return '本日24時' end
        if dayTs - 1 == dayNow + 1 then return '明日24時' end
    end
    if dayTs == dayNow then return '本日' .. hm(t.hour, t.min) end
    if dayTs == dayNow + 1 then return '明日' .. hm(t.hour, t.min) end
    return string.format('%d月%d日%s', t.month, t.day, hm(t.hour, t.min))
end

function U.formatDuration(sec)
    sec = math.max(0, math.floor(sec))
    if sec >= 3600 then
        local h, m = sec // 3600, (sec % 3600) // 60
        if m == 0 then return string.format('%d時間', h) end
        return string.format('%d時間%d分', h, m)
    end
    if sec >= 60 then return string.format('%d分', math.ceil(sec / 60)) end
    return string.format('%d秒', sec)
end

-- {key} 形式の置換
function U.template(str, vars)
    return (tostring(str or ''):gsub('{(%w+)}', function(k)
        local v = vars[k]
        if v == nil then return '{' .. k .. '}' end
        return tostring(v)
    end))
end

function U.formatAnnouncement(templateStr, ev, now)
    now = now or os.time()
    local vars = {
        location = ev.location_label or ev.location or '???',
        name = ev.name or '',
        ['end'] = ev.end_at and U.formatJstRelativeDay(ev.end_at, now) or '',
        start = ev.start_at and U.formatJstRelativeDay(ev.start_at, now) or '',
        startIn = ev.start_at and U.formatDuration(ev.start_at - now) or '',
    }
    return U.template(templateStr, vars)
end

function U.vec(t)
    if not t then return nil end
    return vector3(tonumber(t.x) or 0.0, tonumber(t.y) or 0.0, tonumber(t.z) or 0.0)
end

function U.randomInt(lo, hi)
    lo, hi = math.floor(lo), math.floor(hi)
    if hi <= lo then return lo end
    return math.random(lo, hi)
end
