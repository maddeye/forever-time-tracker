-- Run from the repository root: lua5.1 tests/run.lua [output directory for UI renders]
package.path = "tests/?.lua;" .. package.path
local Harness = require("harness")

local failures, count = 0, 0
local function test(name, fn)
    count = count + 1
    local ok, message = xpcall(fn, debug.traceback)
    if not ok then
        failures = failures + 1
        print("FAIL " .. name .. "\n  " .. tostring(message))
    end
end
local function equal(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label or "value", tostring(expected), tostring(actual)), 2)
    end
end

local function Login(savedVariables)
    local world = Harness.New(savedVariables)
    world.Fire("PLAYER_ENTERING_WORLD", true, false)
    return world
end

local function DayTotals(world)
    return (world.ns.Store.Totals("today", "character"))
end

test("classifier applies priorities", function()
    local Classify = Harness.New().ns.Classify
    equal(Classify({}), "idle")
    equal(Classify({ combat = true, afk = true, dead = true, moving = true }), "fighting")
    equal(Classify({ afk = true, dead = true }), "afk")
    equal(Classify({ dead = true, moving = true }), "dead")
    equal(Classify({ gatherCast = true, craftCast = true }), "gathering")
    equal(Classify({ craftCast = true, moving = true }), "crafting")
    equal(Classify({ moving = true, npcWindow = true }), "traveling")
    equal(Classify({ taxi = true }), "traveling")
    equal(Classify({ craftWindow = true, npcWindow = true }), "crafting")
    equal(Classify({ npcWindow = true, eating = true }), "npcs")
    equal(Classify({ eating = true }), "resting")
end)

test("every sampled second lands in the right category", function()
    local world = Login()
    local game = world.game
    world.Run(5)
    game.speed = 7; world.Run(10); game.speed = 0
    game.combat = true; world.Run(20); game.combat = false
    game.taxi = true; world.Run(30); game.taxi = false
    game.cast = { name = "Smelt Copper", tradeSkill = true }; world.Run(4); game.cast = nil
    game.channel = { name = "Fishing", tradeSkill = false }; world.Run(6); game.channel = nil
    game.auras = { { name = "Well Fed" }, { name = "Food" } }; world.Run(8); game.auras = {}
    game.dead = true; world.Run(3); game.dead = false

    local totals, total = world.ns.Store.Totals("session")
    equal(totals.idle, 5, "idle")
    equal(totals.traveling, 40, "traveling")
    equal(totals.fighting, 20, "fighting")
    equal(totals.crafting, 4, "crafting")
    equal(totals.gathering, 6, "gathering")
    equal(totals.resting, 8, "resting")
    equal(totals.dead, 3, "dead")
    equal(total, 86, "total conserved")
end)

test("the idle stretch before an AFK flag becomes AFK", function()
    local world = Login()
    local game = world.game
    game.speed = 7; world.Run(10); game.speed = 0
    world.Run(300)
    game.afk = true; world.Run(60)
    local totals = DayTotals(world)
    equal(totals.idle, 0, "idle day")
    equal(totals.afk, 360, "afk day")
    equal(totals.traveling, 10, "traveling untouched")
    local session = world.ns.Store.Totals("session")
    equal(session.idle, 0, "idle session")
    equal(session.afk, 360, "afk session")
end)

test("fractional frame times are carried, so no time is lost", function()
    local world = Login()
    for _ = 1, 40 do
        world.game.now = world.game.now + 1.25
        world.ns.Tracker.Sample(world.game.now)
    end
    equal(select(2, world.ns.Store.Totals("session")), 50, "total")
end)

test("loading screens are counted, without double counting", function()
    local world = Login()
    world.Run(10)
    world.Fire("PLAYER_LEAVING_WORLD")
    world.game.now = world.game.now + 25
    world.Fire("PLAYER_ENTERING_WORLD", false, false)
    world.Run(5)
    local totals, total = world.ns.Store.Totals("session")
    equal(totals.loading, 25, "loading")
    equal(totals.idle, 15, "idle")
    equal(total, 40, "total")
end)

test("a hitch is capped instead of inflating the total", function()
    local world = Login()
    world.game.now = world.game.now + 5000
    world.Run(1)
    local _, total = world.ns.Store.Totals("session")
    assert(total <= 61, "gap should be capped, got " .. total)
end)

test("window events feed the NPC and crafting categories, and stale flags clear", function()
    local world = Login()
    local game = world.game
    world.Fire("MERCHANT_SHOW"); world.Run(4); world.Fire("MERCHANT_CLOSED")
    world.Fire("TRADE_SKILL_SHOW"); world.Run(3); world.Fire("TRADE_SKILL_CLOSE")
    world.Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 17); world.Run(2)
    world.Fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 17)
    world.Fire("QUEST_DETAIL"); world.Run(2)
    game.speed = 7; world.Run(1); game.speed = 0
    world.Run(2)
    local totals = world.ns.Store.Totals("session")
    equal(totals.npcs, 8, "npcs")
    equal(totals.crafting, 3, "crafting")
    equal(totals.traveling, 1, "traveling")
    equal(totals.idle, 2, "idle after stale flag cleared")
end)

test("secret values never break sampling", function()
    local world = Login()
    local env, game = world.env, world.game
    local secret = Harness.Secret()
    env.UnitAffectingCombat = function() return secret end
    env.UnitIsAFK = function() return secret end
    env.UnitIsDeadOrGhost = function() return secret end
    env.UnitOnTaxi = function() return secret end
    env.GetUnitSpeed = function() return secret end
    env.UnitCastingInfo = function() return secret, secret, secret, secret, secret, secret end
    env.C_UnitAuras.GetAuraDataByIndex = function() return { name = secret } end
    world.Run(3)
    equal(world.ns.Store.Totals("session").idle, 3, "falls back to idle")
    -- With the combat API hidden, the events still detect a fight.
    world.Fire("PLAYER_REGEN_DISABLED"); world.Run(2); world.Fire("PLAYER_REGEN_ENABLED")
    equal(world.ns.Store.Totals("session").fighting, 2, "combat from events")
    world.Fire("PLAYER_STARTED_MOVING"); world.Run(2); world.Fire("PLAYER_STOPPED_MOVING")
    equal(world.ns.Store.Totals("session").traveling, 2, "moving from events")
    assert(game)
end)

test("erroring or missing APIs never break sampling", function()
    local world = Login()
    local env = world.env
    env.UnitIsAFK = function() error("removed") end
    env.GetUnitSpeed = nil
    env.UnitChannelInfo = nil
    env.C_UnitAuras = nil
    env.C_Spell = nil
    world.Run(2)
    equal(world.ns.Store.Totals("session").idle, 2, "still samples")
end)

test("events missing from the client do not stop registration", function()
    local world = Login()
    world.Fire("MAIL_SHOW"); world.Run(1)
    equal(world.ns.Store.Totals("session").npcs, 1, "later events still registered")
end)

test("data survives reload; login starts a new session but keeps history", function()
    local world = Login()
    world.Run(50)
    local saved = world.env.ForeverTimeTrackerDB

    local reloaded = Harness.New(saved)
    reloaded.Fire("PLAYER_ENTERING_WORLD", false, true)
    reloaded.Run(10)
    equal(select(2, reloaded.ns.Store.Totals("session")), 60, "reload keeps session")

    local relogged = Harness.New(saved)
    relogged.game.clock = world.game.clock + 20
    relogged.Fire("PLAYER_ENTERING_WORLD", true, false)
    relogged.Run(5)
    equal(select(2, relogged.ns.Store.Totals("session")), 5, "login resets session")
    equal(select(2, relogged.ns.Store.Totals("all", "character")), 65, "history kept")
end)

test("day rollover splits time and ranges respect it", function()
    local world = Login()
    world.Run(100)
    world.game.clock = world.game.clock + 86400
    world.Run(10)
    local Store = world.ns.Store
    equal(select(2, Store.Totals("today", "character")), 10, "today")
    equal(select(2, Store.Totals("week", "character")), 110, "week")
    local history = Store.DailyHistory(7, "character")
    equal(#history, 7, "history length")
    equal(history[7].total, 10, "newest")
    equal(history[6].total, 100, "previous")
    equal(history[1].total, 0, "empty day")
end)

test("all-characters scope sums every character", function()
    local world = Login()
    world.Run(10)
    local saved = world.env.ForeverTimeTrackerDB
    saved.chars["Alt-Forever"] = { days = { [os.date("%Y-%m-%d", world.game.clock)] = { fighting = 40 } } }
    local Store = world.ns.Store
    equal(select(2, Store.Totals("today", "character")), 10, "character")
    equal(select(2, Store.Totals("today", "all")), 50, "all")
    equal(select(2, Store.Totals("all", "all")), 50, "all time")
end)

test("session bins cover the session and pick the dominant activity", function()
    local world = Login()
    local game = world.game
    game.speed = 7; world.Run(450); game.speed = 0
    game.combat = true; world.Run(450); game.combat = false
    local bins, total = world.ns.Store.SessionBins(90)
    equal(total, 900, "total")
    equal(#bins, 90, "bins")
    equal(bins[1].id, "traveling", "first")
    equal(bins[45].id, "traveling", "middle")
    equal(bins[46].id, "fighting", "after middle")
    equal(bins[90].id, "fighting", "last")
end)

test("session bins handle sessions shorter than the bin count", function()
    local world = Login()
    world.Run(3)
    local bins = world.ns.Store.SessionBins(90)
    equal(#bins, 90, "bins")
    equal(bins[90].id, "idle", "last bin filled")
    equal(#(world.ns.Store.SessionBins(90)), 90, "repeatable")
end)

test("durations and percentages format as shown in the UI", function()
    local ns = Harness.New().ns
    equal(ns.FormatDuration(0), "0s")
    equal(ns.FormatDuration(59), "59s")
    equal(ns.FormatDuration(61), "1m 1s")
    equal(ns.FormatDuration(3600), "1h 0m")
    equal(ns.FormatDuration(360000), "100h 0m")
    equal(ns.FormatPercent(1, 0), "0%")
    equal(ns.FormatPercent(1, 1000), "<1%")
    equal(ns.FormatPercent(1, 2), "50%")
end)

test("slash commands work and reset needs confirmation", function()
    local world = Login()
    world.Run(10)
    local slash = world.env.SlashCmdList.FOREVERTIMETRACKER
    slash("debug")
    assert(world.printed[#world.printed]:find("now idle"), "debug line")
    slash("reset")
    equal(select(2, world.ns.Store.Totals("all", "character")), 10, "reset alone keeps data")
    slash("reset confirm")
    equal(select(2, world.ns.Store.Totals("all", "character")), 0, "confirmed reset")
    slash("minimap"); slash("minimap"); slash("nonsense")
    slash(""); slash("")
end)

-- Plays a varied week so every UI state has realistic data to draw.
local function SeedHistory(world)
    local game = world.game
    local saved = world.env.ForeverTimeTrackerDB
    local char = saved.chars["Tester-Forever"]
    local shape = { traveling = 0.27, fighting = 0.31, gathering = 0.07, crafting = 0.06, resting = 0.08,
        npcs = 0.08, dead = 0.02, idle = 0.06, afk = 0.04, loading = 0.01 }
    for offset = 1, 29 do
        if offset % 6 ~= 0 then
            local key = os.date("%Y-%m-%d", game.clock - offset * 86400)
            local hours = 1 + (offset * 7 % 5)
            local day = {}
            for id, share in pairs(shape) do
                day[id] = math.floor(hours * 3600 * share * (0.7 + (offset * #id % 7) / 10))
            end
            char.days[key] = day
        end
    end
    saved.chars["Altchar-Forever"] = { days = { [os.date("%Y-%m-%d", game.clock - 3 * 86400)] = { crafting = 7200, npcs = 3000 } } }

    local function Act(field, value, seconds)
        game[field] = value; world.Run(seconds); game[field] = (field == "speed") and 0 or (field == "auras" and {} or false)
    end
    for _ = 1, 3 do
        Act("speed", 7, 420); Act("combat", true, 300); Act("auras", { { name = "Food" } }, 60)
        Act("speed", 7, 120); Act("combat", true, 240); world.Run(30)
    end
    world.Fire("MERCHANT_SHOW"); world.Run(180); world.Fire("MERCHANT_CLOSED")
    Act("taxi", true, 240)
    game.cast = { name = "Smelt Copper", tradeSkill = true }; world.Run(300); game.cast = nil
    game.channel = { name = "Fishing" }; world.Run(240); game.channel = nil
    Act("dead", true, 90)
    world.Fire("PLAYER_LEAVING_WORLD"); game.now = game.now + 20; world.Fire("PLAYER_ENTERING_WORLD", false, false)
    world.Run(300); game.afk = true; world.Run(200); game.afk = false
    game.speed = 7; world.Run(5)
end

test("UI: every range and scope renders without layout problems", function()
    local world = Login()
    SeedHistory(world)
    local env, UI = world.env, world.ns.UI
    local slash = env.SlashCmdList.FOREVERTIMETRACKER
    slash("")
    local window = env.ForeverTimeTrackerFrame
    assert(window:IsShown(), "window opens")
    local outDir = arg and arg[1]
    for _, range in ipairs({ "session", "today", "week", "month", "all" }) do
        for _, scope in ipairs({ "character", "all" }) do
            local settings = world.ns.Store.Settings()
            settings.range, settings.scope = range, scope
            UI.Refresh()
            local problems = Harness.LayoutProblems(window)
            if #problems > 0 then
                error(range .. "/" .. scope .. ":\n  " .. table.concat(problems, "\n  "))
            end
            if outDir and scope == "character" then
                local file = assert(io.open(outDir .. "/ui-" .. range .. ".html", "w"))
                file:write(Harness.RenderHTML(window))
                file:close()
            end
        end
    end
    world.Run(3)
    window:Hide()
    world.Run(1)
end)

test("UI: a brand new character renders without errors", function()
    local world = Login()
    local env = world.env
    env.SlashCmdList.FOREVERTIMETRACKER("")
    local window = env.ForeverTimeTrackerFrame
    for _, range in ipairs({ "session", "today", "week", "month", "all" }) do
        world.ns.Store.Settings().range = range
        world.ns.UI.Refresh()
        local problems = Harness.LayoutProblems(window)
        if #problems > 0 then error(range .. ":\n  " .. table.concat(problems, "\n  ")) end
    end
end)

test("UI: hover and click handlers run on every interactive frame", function()
    local world = Login()
    SeedHistory(world)
    local env = world.env
    env.SlashCmdList.FOREVERTIMETRACKER("")
    local window = env.ForeverTimeTrackerFrame
    local function Walk(frame)
        for _, script in ipairs({ "OnEnter", "OnLeave" }) do
            if frame.scripts[script] then frame.scripts[script](frame) end
        end
        for _, child in ipairs(frame.children) do Walk(child) end
    end
    for _, range in ipairs({ "session", "month" }) do
        world.ns.Store.Settings().range = range
        world.ns.UI.Refresh()
        Walk(window)
    end
    local minimapButton = env.ForeverTimeTrackerMinimapButton
    minimapButton.scripts.OnEnter(minimapButton)
    minimapButton.scripts.OnDragStart(minimapButton)
    minimapButton.scripts.OnUpdate(minimapButton)
    minimapButton.scripts.OnDragStop(minimapButton)
    minimapButton.scripts.OnClick(minimapButton)
    equal(window:IsShown(), false, "minimap click toggles the window")
end)

test("minimap button: dragging moves it, unless a collector has taken it over", function()
    local world = Login()
    local env = world.env
    local button = env.ForeverTimeTrackerMinimapButton
    assert(button.icon, "collectors find the icon through this field")
    local settings = world.ns.Store.Settings()
    local before = settings.minimapAngle

    button.scripts.OnDragStart(button)
    assert(button.scripts.OnUpdate, "drag starts on the minimap")
    button.scripts.OnUpdate(button)
    button.scripts.OnDragStop(button)
    assert(settings.minimapAngle ~= before, "angle saved")

    local flyout = env.CreateFrame("Frame", "CollectorFlyout", env.UIParent)
    button:SetParent(flyout)
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", flyout, "TOPLEFT", 4, -4)
    local angle = settings.minimapAngle
    button.scripts.OnDragStart(button)
    equal(button.scripts.OnUpdate, nil, "no drag once collected")
    equal(settings.minimapAngle, angle, "angle untouched")
    equal(button.points.TOPLEFT.relative, flyout, "collector's anchor kept")
end)

print(string.format("%d tests, %d failed", count, failures))
os.exit(failures == 0 and 0 or 1)
