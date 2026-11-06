local _, ns = ...

local Store = {}
ns.Store = Store

local DAY_SECONDS = 86400
local RANGE_DAYS = { today = 1, week = 7, month = 30 }

local db, char, charKey

local function DayKey(timestamp)
    return date("%Y-%m-%d", timestamp)
end

-- Noon keeps the day arithmetic correct across daylight saving changes.
local function NoonToday()
    local parts = date("*t")
    return time({ year = parts.year, month = parts.month, day = parts.day, hour = 12 })
end

local function NewSession()
    return { char = charKey, startedAt = time(), totals = {}, segments = {} }
end

function Store.Init(key, isLogin)
    db = _G.ForeverTimeTrackerDB
    if type(db) ~= "table" then
        db = {}
        _G.ForeverTimeTrackerDB = db
    end
    db.version = db.version or 1
    db.chars = db.chars or {}
    db.settings = db.settings or {}
    local settings = db.settings
    settings.range = settings.range or "session"
    settings.scope = settings.scope or "character"
    settings.minimapAngle = settings.minimapAngle or 215

    charKey = key
    db.chars[key] = db.chars[key] or { days = {}, trackedSince = time() }
    char = db.chars[key]

    -- A /reload continues the session; only a real login starts a new one.
    if isLogin or type(db.session) ~= "table" or db.session.char ~= key then
        db.session = NewSession()
    end
end

function Store.IsReady()
    return db ~= nil
end

function Store.Settings()
    return db.settings
end

function Store.Character()
    return char
end

function Store.Add(categoryId, seconds)
    if seconds <= 0 then
        return
    end
    local key = DayKey()
    local day = char.days[key]
    if not day then
        day = {}
        char.days[key] = day
    end
    day[categoryId] = (day[categoryId] or 0) + seconds

    local session = db.session
    session.totals[categoryId] = (session.totals[categoryId] or 0) + seconds
    local last = session.segments[#session.segments]
    if last and last.id == categoryId then
        last.seconds = last.seconds + seconds
    else
        session.segments[#session.segments + 1] = { id = categoryId, seconds = seconds }
    end
end

-- Rewrites the most recent session segment, used when the AFK flag reveals that
-- the idle stretch before it was really AFK. Returns the seconds moved.
function Store.ReclassifyLastSegment(fromId, toId)
    local session = db.session
    local segments = session.segments
    local index = #segments
    local last = segments[index]
    if not last or last.id ~= fromId then
        return 0
    end
    local seconds = last.seconds

    local previous = segments[index - 1]
    if previous and previous.id == toId then
        previous.seconds = previous.seconds + seconds
        segments[index] = nil
    else
        last.id = toId
    end
    session.totals[fromId] = (session.totals[fromId] or 0) - seconds
    session.totals[toId] = (session.totals[toId] or 0) + seconds

    -- A stretch that began before midnight only moves today's share.
    local day = char.days[DayKey()]
    if day then
        local moved = math.min(day[fromId] or 0, seconds)
        day[fromId] = (day[fromId] or 0) - moved
        day[toId] = (day[toId] or 0) + moved
    end
    return seconds
end

local function AddInto(target, source)
    for id, seconds in pairs(source) do
        target[id] = (target[id] or 0) + seconds
    end
end

local function ScopedChars(scope)
    if scope == "all" then
        return db.chars
    end
    return { [charKey] = char }
end

local function RecentDayKeys(count)
    local noon = NoonToday()
    local keys = {}
    for offset = count - 1, 0, -1 do
        local timestamp = noon - offset * DAY_SECONDS
        keys[#keys + 1] = { key = DayKey(timestamp), timestamp = timestamp }
    end
    return keys
end

-- Returns a categoryId -> seconds map and the grand total.
function Store.Totals(range, scope)
    local totals = {}
    if range == "session" then
        AddInto(totals, db.session.totals)
    elseif range == "all" then
        for _, entry in pairs(ScopedChars(scope)) do
            for _, day in pairs(entry.days) do
                AddInto(totals, day)
            end
        end
    else
        local keys = RecentDayKeys(RANGE_DAYS[range])
        for _, entry in pairs(ScopedChars(scope)) do
            for _, info in ipairs(keys) do
                local day = entry.days[info.key]
                if day then
                    AddInto(totals, day)
                end
            end
        end
    end
    local sum = 0
    for _, seconds in pairs(totals) do
        sum = sum + seconds
    end
    return totals, sum
end

-- One entry per day, oldest first, including days with no play.
function Store.DailyHistory(count, scope)
    local history = {}
    local chars = ScopedChars(scope)
    for _, info in ipairs(RecentDayKeys(count)) do
        local totals, sum = {}, 0
        for _, entry in pairs(chars) do
            local day = entry.days[info.key]
            if day then
                AddInto(totals, day)
            end
        end
        for _, seconds in pairs(totals) do
            sum = sum + seconds
        end
        history[#history + 1] = { timestamp = info.timestamp, totals = totals, total = sum }
    end
    return history
end

-- Splits the session into equal time bins, each showing its dominant activity.
function Store.SessionBins(count)
    local segments = db.session.segments
    local total = 0
    for _, segment in ipairs(segments) do
        total = total + segment.seconds
    end
    if total <= 0 then
        return {}, 0
    end

    local binSeconds = total / count
    local bins = {}
    for index = 1, count do
        bins[index] = { shares = {} }
    end
    local position = 0
    for _, segment in ipairs(segments) do
        local remaining = segment.seconds
        while remaining > 0 do
            local index = math.min(count, math.floor(position / binSeconds) + 1)
            local room = index * binSeconds - position
            local used = (index == count) and remaining or math.min(remaining, math.max(room, 1e-6))
            local shares = bins[index].shares
            shares[segment.id] = (shares[segment.id] or 0) + used
            position = position + used
            remaining = remaining - used
        end
    end
    for index, bin in ipairs(bins) do
        local best, bestShare = nil, -1
        for id, share in pairs(bin.shares) do
            local order = ns.CATEGORY[id] and ns.CATEGORY[id].order or 0
            if share > bestShare or (share == bestShare and order < ns.CATEGORY[best].order) then
                best, bestShare = id, share
            end
        end
        bin.id = best
        bin.from = (index - 1) * binSeconds
        bin.to = index * binSeconds
    end
    return bins, total
end

function Store.SessionSummary()
    local session = db.session
    local longest
    for _, segment in ipairs(session.segments) do
        if not longest or segment.seconds > longest.seconds then
            longest = segment
        end
    end
    return {
        startedAt = session.startedAt,
        switches = math.max(0, #session.segments - 1),
        longest = longest,
    }
end

function Store.ResetCharacter()
    db.chars[charKey] = { days = {}, trackedSince = time() }
    char = db.chars[charKey]
    db.session = NewSession()
end
