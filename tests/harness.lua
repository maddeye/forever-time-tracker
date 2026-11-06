-- A strict fake of the WoW client. Unknown frame methods raise instead of doing
-- nothing, and the addon runs in a sandbox without os or io, as it does in-game.
local Harness = {}

local POINT_FRACTIONS = {
    TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 },
    LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
    BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}
local LAYER_ORDER = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }

local function NewObject(kind, parent, name)
    local object = {
        kind = kind, parent = parent, name = name, shown = true, points = {},
        children = {}, regions = {}, scripts = {},
    }
    if parent then
        local list = (kind == "Texture" or kind == "FontString") and parent.regions or parent.children
        list[#list + 1] = object
    end
    return object
end

local Methods = {}

function Methods:SetSize(w, h)
    assert(type(w) == "number" and type(h) == "number", "SetSize needs numbers")
    self.w, self.h = w, h
end
function Methods:SetWidth(w) assert(type(w) == "number"); self.w = w end
function Methods:SetHeight(h) assert(type(h) == "number"); self.h = h end
function Methods:GetWidth() return self.w or 0 end
function Methods:SetPoint(point, a, b, c, d)
    assert(POINT_FRACTIONS[point], "bad anchor point " .. tostring(point))
    local relative, relativePoint, x, y
    if type(a) == "table" then
        relative, relativePoint, x, y = a, b or point, c or 0, d or 0
    elseif type(a) == "string" then
        relative, relativePoint, x, y = self.parent, a, b or 0, c or 0
    else
        relative, relativePoint, x, y = self.parent, point, a or 0, b or 0
    end
    assert(POINT_FRACTIONS[relativePoint], "bad relative point " .. tostring(relativePoint))
    self.points[point] = { relative = relative, relativePoint = relativePoint, x = x, y = y }
end
function Methods:GetPoint()
    for point, anchor in pairs(self.points) do
        return point, anchor.relative, anchor.relativePoint, anchor.x, anchor.y
    end
end
function Methods:SetAllPoints()
    self:SetPoint("TOPLEFT", self.parent, "TOPLEFT", 0, 0)
    self:SetPoint("BOTTOMRIGHT", self.parent, "BOTTOMRIGHT", 0, 0)
end
function Methods:ClearAllPoints() self.points = {} end
function Methods:Show() self.shown = true end
function Methods:Hide()
    if self.shown and self.scripts.OnHide then self.scripts.OnHide(self) end
    self.shown = false
end
function Methods:IsShown() return self.shown end
function Methods:IsVisible()
    local object = self
    while object do
        if not object.shown then return false end
        object = object.parent
    end
    return true
end

local FrameMethods = {}
function FrameMethods:CreateTexture(_, layer)
    assert(layer == nil or LAYER_ORDER[layer], "bad layer")
    local texture = NewObject("Texture", self)
    texture.layer = layer or "ARTWORK"
    return Harness.Wrap(texture)
end
function FrameMethods:CreateFontString(_, layer)
    local text = NewObject("FontString", self)
    text.layer = layer or "ARTWORK"
    return Harness.Wrap(text)
end
function FrameMethods:Show()
    local wasShown = self.shown
    self.shown = true
    if not wasShown and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function FrameMethods:SetScript(script, handler)
    local allowed = { OnEvent = 1, OnUpdate = 1, OnShow = 1, OnHide = 1, OnClick = 1, OnEnter = 1,
        OnLeave = 1, OnDragStart = 1, OnDragStop = 1 }
    assert(allowed[script], "bad script " .. tostring(script))
    if script == "OnClick" then assert(self.kind == "Button", "OnClick needs a Button") end
    self.scripts[script] = handler
end
function FrameMethods:RegisterEvent(event)
    if Harness.unknownEvents[event] then error("unknown event " .. event) end
    self.events = self.events or {}
    self.events[event] = true
    Harness.eventFrames[self] = true
end
for _, method in ipairs({ "EnableMouse", "SetFrameStrata", "SetFrameLevel", "SetClampedToScreen", "SetMovable",
    "RegisterForDrag", "StartMoving", "StopMovingOrSizing", "RegisterForClicks", "SetHighlightTexture",
    "SetBackdrop", "SetBackdropBorderColor", "SetEnabled" }) do
    FrameMethods[method] = function() end
end
function FrameMethods:SetBackdropColor(r, g, b, a) self.backdrop = { r, g, b, a } end
function FrameMethods:GetCenter() return 100, 100 end
function FrameMethods:GetParent() return self.parent end
function FrameMethods:SetParent(parent) self.parent = parent end
function FrameMethods:GetEffectiveScale() return 1 end

local TextureMethods = {}
function TextureMethods:SetColorTexture(r, g, b, a)
    assert(type(r) == "number" and type(g) == "number" and type(b) == "number", "color needs numbers")
    self.color = { r, g, b, a or 1 }
end
function TextureMethods:SetTexture(path) self.path = path end
function TextureMethods:SetTexCoord() end

local TextMethods = {}
function TextMethods:SetFont(path, size, flags)
    assert(path and size and flags, "SetFont needs path, size and flags")
    self.size = size
end
function TextMethods:SetTextColor(r, g, b) self.textColor = { r, g, b } end
function TextMethods:SetJustifyH(justify) self.justify = justify end
function TextMethods:SetWordWrap() end
function TextMethods:SetText(text)
    assert(self.size, "SetText before SetFont raises in-game")
    assert(type(text) == "string" or type(text) == "number" or text == nil, "SetText got " .. type(text))
    self.text = text and tostring(text) or ""
    assert(not self.text:find("|[^cr]"), "stray | is an escape sequence in-game: " .. self.text)
end

function Harness.Wrap(object)
    local specific = object.kind == "Texture" and TextureMethods
        or object.kind == "FontString" and TextMethods or FrameMethods
    return setmetatable(object, {
        __index = function(_, key)
            local method = specific[key] or Methods[key]
            if method then return method end
            -- Plain data fields live on the object, so missing ones are read as nil,
            -- while anything called as a method fails on the nil call with its name.
            return nil
        end,
    })
end

local function CreateFrame(kind, name, parent)
    assert(kind == "Frame" or kind == "Button", "unexpected frame type " .. tostring(kind))
    local frame = Harness.Wrap(NewObject(kind, parent or Harness.env.UIParent, name))
    if name then Harness.env[name] = frame end
    return frame
end

-- Secret values: opaque objects that raise on comparison and use as table keys,
-- matching how the client treats them.
local SECRET_MT = {
    __eq = function() error("attempt to compare secret value") end,
    __lt = function() error("attempt to compare secret value") end,
    __le = function() error("attempt to compare secret value") end,
    __tostring = function() error("attempt to use secret value") end,
}
function Harness.Secret()
    return setmetatable({ secret = true }, SECRET_MT)
end

function Harness.New(savedVariables)
    Harness.eventFrames = {}
    Harness.unknownEvents = { CRAFT_SHOW = true, CRAFT_CLOSE = true, TRAINER_SHOW = true, TRAINER_CLOSED = true }
    local game = {
        now = 1000, clock = 1794038400, afk = false, combat = false, dead = false, taxi = false,
        speed = 0, cast = nil, channel = nil, auras = {},
    }
    local printed = {}
    local env = {
        pairs = pairs, ipairs = ipairs, next = next, type = type, tostring = tostring, tonumber = tonumber,
        select = select, unpack = unpack, pcall = pcall, error = error, assert = assert, math = math,
        string = string, table = table, setmetatable = setmetatable, getmetatable = getmetatable,
        print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end,
        date = function(format, timestamp) return os.date(format, timestamp or game.clock) end,
        time = function(parts) return parts and os.time(parts) or game.clock end,
        wipe = function(target) for key in pairs(target) do target[key] = nil end return target end,
        tinsert = table.insert,
        strtrim = function(text) return (text:gsub("^%s+", ""):gsub("%s+$", "")) end,
        issecretvalue = function(value) return type(value) == "table" and value.secret == true end,
        GetTime = function() return game.now end,
        UnitName = function() return "Tester" end,
        GetRealmName = function() return "Forever" end,
        UnitAffectingCombat = function() return game.combat end,
        UnitIsAFK = function() return game.afk end,
        UnitIsDeadOrGhost = function() return game.dead end,
        UnitOnTaxi = function() return game.taxi end,
        GetUnitSpeed = function() return game.speed end,
        UnitCastingInfo = function()
            if game.cast then return game.cast.name, game.cast.name, 1, 0, 0, game.cast.tradeSkill end
        end,
        UnitChannelInfo = function()
            if game.channel then return game.channel.name, game.channel.name, 1, 0, 0, game.channel.tradeSkill end
        end,
        C_Spell = { GetSpellName = function() return nil end },
        C_UnitAuras = { GetAuraDataByIndex = function(_, index) return game.auras[index] end },
        Enum = { PlayerInteractionType = { Merchant = 5, Banker = 8, MailInfo = 17 } },
        GameFontNormal = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end },
        GetCursorPosition = function() return 150, 150 end,
        UISpecialFrames = {},
        SlashCmdList = {},
        ForeverTimeTrackerDB = savedVariables,
        CreateFrame = CreateFrame,
    }
    env._G = env
    Harness.env = env
    env.UIParent = Harness.Wrap(NewObject("Frame", nil, "UIParent"))
    env.UIParent.w, env.UIParent.h = 1600, 900
    env.UIParent:SetPoint("BOTTOMLEFT", env.UIParent, "BOTTOMLEFT", 0, 0)
    env.UIParent.points = {}
    env.Minimap = CreateFrame("Frame", "Minimap", env.UIParent)
    env.Minimap:SetSize(140, 140)
    env.Minimap:SetPoint("TOPRIGHT", -20, -20)
    env.Minimap.shown = false
    local tooltip = { lines = {} }
    function tooltip:SetOwner() self.lines = {} end
    function tooltip:AddLine(text) self.lines[#self.lines + 1] = text end
    function tooltip:AddDoubleLine(left, right) self.lines[#self.lines + 1] = left .. " | " .. right end
    function tooltip:Show() self.shown = true end
    function tooltip:Hide() self.shown = false end
    env.GameTooltip = tooltip

    local ns = {}
    local toc = assert(io.open("ForeverTimeTracker/ForeverTimeTracker.toc"))
    for line in toc:lines() do
        -- Packaged files have CRLF line endings, which the client accepts.
        line = line:gsub("\r$", "")
        if line:match("%.lua$") then
            local chunk = assert(loadfile("ForeverTimeTracker/" .. line))
            setfenv(chunk, env)
            chunk("ForeverTimeTracker", ns)
        end
    end
    toc:close()

    local world = { ns = ns, env = env, game = game, printed = printed }
    function world.Fire(event, ...)
        for frame in pairs(Harness.eventFrames) do
            if frame.events[event] and frame.scripts.OnEvent then
                frame.scripts.OnEvent(frame, event, ...)
            end
        end
    end
    -- Advances the clock, sampling once per second like the real OnUpdate.
    function world.Run(seconds)
        for _ = 1, seconds do
            game.now = game.now + 1
            game.clock = game.clock + 1
            for frame in pairs(Harness.eventFrames) do
                if frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, 1) end
            end
        end
    end
    return world
end

-- Resolves anchors to screen rectangles, top-down as the client does.
local function Rect(object, memo)
    memo = memo or {}
    if memo[object] then return memo[object] end
    if not object.parent and not next(object.points) then
        return { left = 0, right = object.w, bottom = 0, top = object.h }
    end
    local left, right, top, bottom, centerX, centerY
    local width, height = object.w, object.h
    if object.kind == "FontString" then
        width = #(object.text or "") * object.size * 0.52
        height = object.size * 1.2
    end
    for point, anchor in pairs(object.points) do
        local relativeRect = Rect(anchor.relative, memo)
        local rf = POINT_FRACTIONS[anchor.relativePoint]
        local x = relativeRect.left + rf[1] * (relativeRect.right - relativeRect.left) + anchor.x
        local y = relativeRect.bottom + rf[2] * (relativeRect.top - relativeRect.bottom) + anchor.y
        local f = POINT_FRACTIONS[point]
        if f[1] == 0 then left = x elseif f[1] == 1 then right = x else centerX = x end
        if f[2] == 0 then bottom = y elseif f[2] == 1 then top = y else centerY = y end
    end
    width, height = width or 0, height or 0
    if not left and not right then left = (centerX or 0) - width / 2; right = left + width end
    if not left then left = right - width elseif not right then right = left + width end
    if not bottom and not top then bottom = (centerY or 0) - height / 2; top = bottom + height end
    if not bottom then bottom = top - height elseif not top then top = bottom + height end
    local rect = { left = left, right = right, top = top, bottom = bottom }
    memo[object] = rect
    return rect
end

local function Visit(frame, visitor)
    if not frame.shown then return end
    visitor(frame)
    local regions = {}
    for index, region in ipairs(frame.regions) do
        if region.shown then regions[#regions + 1] = { region, index } end
    end
    table.sort(regions, function(a, b)
        local la, lb = LAYER_ORDER[a[1].layer], LAYER_ORDER[b[1].layer]
        if la ~= lb then return la < lb end
        return a[2] < b[2]
    end)
    for _, entry in ipairs(regions) do visitor(entry[1]) end
    for _, child in ipairs(frame.children) do Visit(child, visitor) end
end

-- Finds visible text that overlaps other text or leaves the window.
function Harness.LayoutProblems(root)
    local memo, texts, problems = {}, {}, {}
    local rootRect = Rect(root, memo)
    Visit(root, function(object)
        if object.kind == "FontString" and object.text and object.text ~= "" then
            texts[#texts + 1] = { text = object.text, rect = Rect(object, memo) }
        end
    end)
    for i, a in ipairs(texts) do
        local r = a.rect
        if r.left < rootRect.left or r.right > rootRect.right or r.top > rootRect.top or r.bottom < rootRect.bottom then
            problems[#problems + 1] = "outside window: " .. a.text
        end
        for j = i + 1, #texts do
            local s = texts[j].rect
            if r.left < s.right and s.left < r.right and r.bottom < s.top and s.bottom < r.top then
                problems[#problems + 1] = "overlap: '" .. a.text .. "' and '" .. texts[j].text .. "'"
            end
        end
    end
    return problems
end

local function CssColor(color, alpha)
    return string.format("rgba(%d,%d,%d,%.3f)", color[1] * 255, color[2] * 255, color[3] * 255, alpha or color[4] or 1)
end

local function Escape(text)
    return (text:gsub("&", "&amp;"):gsub("<", "&lt;"))
end

-- Draws the real frame tree as absolutely positioned HTML.
function Harness.RenderHTML(root)
    local memo, out = {}, {}
    local rootRect = Rect(root, memo)
    local width, height = rootRect.right - rootRect.left, rootRect.top - rootRect.bottom
    local function Box(rect)
        return string.format("left:%.1fpx;top:%.1fpx;width:%.1fpx;height:%.1fpx;",
            rect.left - rootRect.left, rootRect.top - rect.top, rect.right - rect.left, rect.top - rect.bottom)
    end
    Visit(root, function(object)
        local rect
        if object.kind == "Texture" and object.color then
            rect = Rect(object, memo)
            out[#out + 1] = string.format('<div style="position:absolute;%sbackground:%s"></div>', Box(rect), CssColor(object.color))
        elseif object.kind == "FontString" and object.text and object.text ~= "" then
            rect = Rect(object, memo)
            local cssLeft = rect.left - rootRect.left
            local cssTop = rootRect.top - rect.top
            local boxWidth = rect.right - rect.left
            out[#out + 1] = string.format(
                '<div style="position:absolute;left:%.1fpx;top:%.1fpx;width:%.1fpx;height:%.1fpx;line-height:%.1fpx;font-size:%dpx;white-space:nowrap;display:flex;justify-content:%s;color:%s">%s</div>',
                cssLeft, cssTop, boxWidth, rect.top - rect.bottom, rect.top - rect.bottom, object.size,
                object.justify == "RIGHT" and "flex-end" or object.justify == "CENTER" and "center" or "flex-start",
                CssColor(object.textColor or { 1, 1, 1 }), Escape(object.text))
        end
    end)
    local backdrop = root.backdrop or { 0, 0, 0, 1 }
    return string.format(
        '<!doctype html><html><body style="margin:0"><div style="position:relative;width:%dpx;height:%dpx;background:%s;border:1px solid rgba(255,255,255,.1);font-family:Georgia,\'Friz Quadrata TT\',serif;overflow:hidden">%s</div></body></html>',
        width, height, CssColor(backdrop, 1), table.concat(out))
end

return Harness
