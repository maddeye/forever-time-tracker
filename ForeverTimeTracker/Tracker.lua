local addonName, ns = ...

local Store = ns.Store

local Tracker = {}
ns.Tracker = Tracker

local SAMPLE_INTERVAL = 1
local MAX_SAMPLE_GAP = 60
local MAX_LOADING_GAP = 600

local WINDOW_OPEN = {
    TRADE_SKILL_SHOW = "tradeskill", CRAFT_SHOW = "craft",
    MERCHANT_SHOW = "merchant", BANKFRAME_OPENED = "bank", GUILDBANKFRAME_OPENED = "guildbank",
    AUCTION_HOUSE_SHOW = "auction", MAIL_SHOW = "mail", TRADE_SHOW = "trade", TRAINER_SHOW = "trainer",
    GOSSIP_SHOW = "gossip", QUEST_GREETING = "quest", QUEST_DETAIL = "quest",
    QUEST_PROGRESS = "quest", QUEST_COMPLETE = "quest",
}
local WINDOW_CLOSE = {
    TRADE_SKILL_CLOSE = "tradeskill", CRAFT_CLOSE = "craft",
    MERCHANT_CLOSED = "merchant", BANKFRAME_CLOSED = "bank", GUILDBANKFRAME_CLOSED = "guildbank",
    AUCTION_HOUSE_CLOSED = "auction", MAIL_CLOSED = "mail", TRADE_CLOSED = "trade", TRAINER_CLOSED = "trainer",
    GOSSIP_CLOSED = "gossip", QUEST_FINISHED = "quest",
}
local INTERACTION_WINDOWS = {
    Merchant = "merchant", Banker = "bank", GuildBanker = "guildbank", Auctioneer = "auction",
    MailInfo = "mail", TradePartner = "trade", Trainer = "trainer",
}

local context = { combat = false, moving = false, windows = {} }
local interactionWindows = {}

local lastSample, loadingStartedAt, carry = nil, nil, 0
local currentCategory

function Tracker.Current()
    return currentCategory
end

function Tracker.ReadState()
    return ns.ReadState(context)
end

-- Only whole seconds are stored. The fraction carries into the next sample, so
-- no time is lost and SavedVariables stays free of long floats.
local function Record(categoryId, elapsed)
    carry = carry + elapsed
    local seconds = math.floor(carry)
    carry = carry - seconds
    Store.Add(categoryId, seconds)
end

function Tracker.Sample(now)
    if not lastSample then
        lastSample = now
    end
    local elapsed = math.min(now - lastSample, MAX_SAMPLE_GAP)
    lastSample = now

    local state = ns.ReadState(context)
    -- A window flag whose close event never fired must not stick forever.
    if state.moving and next(context.windows) then
        wipe(context.windows)
    end

    local category = ns.Classify(state)
    if category == "afk" and currentCategory == "idle" then
        Store.ReclassifyLastSegment("idle", "afk")
    end
    currentCategory = category
    Record(category, elapsed)
end

local handlers = {}

function handlers.PLAYER_ENTERING_WORLD(isLogin, isReload)
    local now = GetTime()
    if not Store.IsReady() then
        local name, realm = UnitName("player"), GetRealmName()
        Store.Init(tostring(name) .. "-" .. tostring(realm), isLogin and not isReload)
        lastSample = now
        Tracker.frame:SetScript("OnUpdate", Tracker.OnUpdate)
        if ns.UI then
            ns.UI.OnReady()
        end
    elseif loadingStartedAt then
        Record("loading", math.min(now - loadingStartedAt, MAX_LOADING_GAP))
    end
    loadingStartedAt = nil
    lastSample = now
    wipe(context.windows)
end

function handlers.PLAYER_LEAVING_WORLD()
    if Store.IsReady() then
        Tracker.Sample(GetTime())
    end
    loadingStartedAt = GetTime()
end

function handlers.PLAYER_REGEN_DISABLED()
    context.combat = true
end

function handlers.PLAYER_REGEN_ENABLED()
    context.combat = false
end

function handlers.PLAYER_STARTED_MOVING()
    context.moving = true
end

function handlers.PLAYER_STOPPED_MOVING()
    context.moving = false
end

function handlers.PLAYER_INTERACTION_MANAGER_FRAME_SHOW(interactionType)
    local window = interactionWindows[ns.Clean(interactionType) or ""]
    if window then
        context.windows[window] = true
    end
end

function handlers.PLAYER_INTERACTION_MANAGER_FRAME_HIDE(interactionType)
    local window = interactionWindows[ns.Clean(interactionType) or ""]
    if window then
        context.windows[window] = nil
    end
end

function handlers.TIME_PLAYED_MSG(total)
    total = ns.Clean(total)
    if total and Store.IsReady() then
        local char = Store.Character()
        char.played = total
        char.playedAt = time()
    end
end

local function OnEvent(_, event, ...)
    if handlers[event] then
        handlers[event](...)
    elseif WINDOW_OPEN[event] then
        context.windows[WINDOW_OPEN[event]] = true
    elseif WINDOW_CLOSE[event] then
        context.windows[WINDOW_CLOSE[event]] = nil
    end
end

local sinceSample = 0

function Tracker.OnUpdate(_, elapsed)
    sinceSample = sinceSample + elapsed
    if sinceSample >= SAMPLE_INTERVAL then
        sinceSample = 0
        Tracker.Sample(GetTime())
        if ns.UI then
            ns.UI.OnSample()
        end
    end
end

function Tracker.Start()
    local frame = CreateFrame("Frame")
    Tracker.frame = frame

    if Enum and Enum.PlayerInteractionType then
        for key, window in pairs(INTERACTION_WINDOWS) do
            local value = Enum.PlayerInteractionType[key]
            if value then
                interactionWindows[value] = window
            end
        end
    end

    -- RegisterEvent raises on an event this client doesn't have, and Forever's
    -- API isn't a perfect copy of Mainline, so each one is registered on its own.
    local function Register(event)
        pcall(frame.RegisterEvent, frame, event)
    end
    for event in pairs(handlers) do
        Register(event)
    end
    for event in pairs(WINDOW_OPEN) do
        Register(event)
    end
    for event in pairs(WINDOW_CLOSE) do
        Register(event)
    end
    frame:SetScript("OnEvent", OnEvent)
end

Tracker.Start()

SLASH_FOREVERTIMETRACKER1 = "/ftt"
SLASH_FOREVERTIMETRACKER2 = "/timetracker"
SlashCmdList.FOREVERTIMETRACKER = function(message)
    local command = strtrim(message or ""):lower()
    if command == "" then
        ns.UI.Toggle()
    elseif command == "minimap" then
        ns.UI.ToggleMinimapButton()
    elseif command == "debug" then
        Tracker.PrintDebug()
    elseif command == "reset" then
        print("|cff3987e5Forever Time Tracker:|r this deletes all data for the current character. Type /ftt reset confirm to do it.")
    elseif command == "reset confirm" then
        Store.ResetCharacter()
        ns.UI.Refresh()
        print("|cff3987e5Forever Time Tracker:|r character data deleted.")
    else
        print("|cff3987e5Forever Time Tracker:|r /ftt opens the window. Also: /ftt minimap, /ftt debug, /ftt reset")
    end
end

function Tracker.PrintDebug()
    local state = Tracker.ReadState()
    local names = {}
    for key, value in pairs(state) do
        if value then
            names[#names + 1] = key
        end
    end
    table.sort(names)
    print(string.format("|cff3987e5Forever Time Tracker:|r now %s; signals: %s; addon %s",
        ns.Classify(state), #names > 0 and table.concat(names, ", ") or "none", addonName))
end

function ForeverTimeTracker_OnCompartmentClick()
    ns.UI.Toggle()
end
