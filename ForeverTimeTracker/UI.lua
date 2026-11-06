local _, ns = ...

local Store = ns.Store
local CATEGORIES, CATEGORY = ns.CATEGORIES, ns.CATEGORY
local FormatDuration, FormatPercent = ns.FormatDuration, ns.FormatPercent

local UI = {}
ns.UI = UI

local WIDTH, HEIGHT = 840, 566
local PAD = 18
local CONTENT_WIDTH = WIDTH - PAD * 2
local LEFT_WIDTH = 410
local RIGHT_X = PAD + LEFT_WIDTH + 20
local RIGHT_WIDTH = WIDTH - RIGHT_X - PAD
local ROW_HEIGHT = 28
local CHART_TOP = 214
local AXIS_WIDTH = 34
local PLOT_HEIGHT = 240
local BIN_COUNT = 90

local SURFACE = { 0.102, 0.102, 0.098 }
local RAISED = { 0.145, 0.145, 0.137 }
local LINE = { 0.200, 0.200, 0.184 }
local TEXT_PRIMARY = { 0.941, 0.937, 0.925 }
local TEXT_SECONDARY = { 0.765, 0.761, 0.718 }
local TEXT_MUTED = { 0.561, 0.557, 0.522 }
local ACCENT = { 0.224, 0.529, 0.898 }

local RANGES = {
    { id = "session", label = "Session" },
    { id = "today", label = "Today", days = 7 },
    { id = "week", label = "7 Days", days = 7 },
    { id = "month", label = "30 Days", days = 30 },
    { id = "all", label = "All Time", days = 30 },
}
local RANGE_BY_ID = {}
for _, range in ipairs(RANGES) do
    RANGE_BY_ID[range.id] = range
end
local SCOPES = {
    { id = "character", label = "This Character" },
    { id = "all", label = "All Characters" },
}

-- Candidate gridline spacings; the chart uses the first where three lines fit.
local AXIS_STEPS = { 300, 600, 900, 1800, 3600, 7200, 10800, 18000, 36000, 72000, 180000 }

local window, widgets

local function Texture(parent, color, alpha, layer)
    local texture = parent:CreateTexture(nil, layer or "ARTWORK")
    texture:SetColorTexture(color[1], color[2], color[3], alpha or 1)
    return texture
end

local function Text(parent, size, color, justify)
    local text = parent:CreateFontString(nil, "OVERLAY")
    text:SetFont((GameFontNormal:GetFont()), size, "")
    text:SetTextColor(color[1], color[2], color[3])
    text:SetJustifyH(justify or "LEFT")
    text:SetWordWrap(false)
    return text
end

-- WoW reads a size of 0 as "no explicit size", which stretches the texture to its
-- anchors, so a too-small mark has to be hidden rather than sized down.
local function SetSpan(texture, width, height)
    if width < 1 or height < 1 then
        texture:Hide()
        return false
    end
    texture:SetSize(width, height)
    texture:Show()
    return true
end

local function HideTooltip()
    GameTooltip:Hide()
end

local function ShowBreakdownTooltip(owner, title, totals, total)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddDoubleLine(title, FormatDuration(total), 0.94, 0.94, 0.93, 0.94, 0.94, 0.93)
    for _, category in ipairs(CATEGORIES) do
        local seconds = totals[category.id]
        if seconds and seconds > 0 then
            GameTooltip:AddDoubleLine(category.label,
                FormatDuration(seconds) .. "  " .. FormatPercent(seconds, total),
                category.color[1], category.color[2], category.color[3], 0.77, 0.76, 0.72)
        end
    end
    GameTooltip:Show()
end

local function ShowCategoryTooltip(owner, category, seconds, total)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(category.label, 0.94, 0.94, 0.93)
    GameTooltip:AddLine(category.desc, 0.77, 0.76, 0.72, true)
    if seconds then
        GameTooltip:AddLine(FormatDuration(seconds) .. "  " .. FormatPercent(seconds, total), 0.94, 0.94, 0.93)
    end
    GameTooltip:Show()
end

local function CreateSegmentButton(parent, label, width, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, 26)
    button.background = Texture(button, RAISED, 1, "BACKGROUND")
    button.background:SetAllPoints()
    button.underline = Texture(button, ACCENT)
    button.underline:SetPoint("BOTTOMLEFT")
    button.underline:SetPoint("BOTTOMRIGHT")
    button.underline:SetHeight(2)
    button.text = Text(button, 12, TEXT_SECONDARY, "CENTER")
    button.text:SetPoint("CENTER")
    button.text:SetText(label)
    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", function(self)
        self.text:SetTextColor(TEXT_PRIMARY[1], TEXT_PRIMARY[2], TEXT_PRIMARY[3])
    end)
    button:SetScript("OnLeave", function(self)
        local color = self.selected and TEXT_PRIMARY or TEXT_SECONDARY
        self.text:SetTextColor(color[1], color[2], color[3])
    end)
    return button
end

local function SetSegmentSelected(button, selected, enabled)
    button.selected = selected
    if selected then
        button.underline:Show()
    else
        button.underline:Hide()
    end
    local color = selected and TEXT_PRIMARY or (enabled and TEXT_SECONDARY or TEXT_MUTED)
    button.text:SetTextColor(color[1], color[2], color[3])
    button:SetEnabled(enabled)
end

local function CreateTile(parent, x, width, valueSize)
    local tile = {}
    tile.background = Texture(parent, RAISED, 1, "BACKGROUND")
    tile.background:SetPoint("TOPLEFT", x, -102)
    tile.background:SetSize(width, 62)
    tile.label = Text(parent, 11, TEXT_MUTED)
    tile.label:SetPoint("TOPLEFT", x + 10, -110)
    tile.value = Text(parent, valueSize, TEXT_PRIMARY)
    tile.value:SetPoint("TOPLEFT", x + 10, -125)
    tile.note = Text(parent, 11, TEXT_SECONDARY, "RIGHT")
    tile.note:SetPoint("BOTTOMRIGHT", tile.background, "BOTTOMRIGHT", -10, 11)
    return tile
end

local function CreateStack(parent)
    local stack = { segments = {} }
    for _, category in ipairs(CATEGORIES) do
        local segment = CreateFrame("Frame", nil, parent)
        segment:SetHeight(18)
        segment:EnableMouse(true)
        segment.fill = Texture(segment, category.color)
        segment.fill:SetPoint("TOPLEFT")
        segment.fill:SetPoint("BOTTOMLEFT")
        segment:SetScript("OnEnter", function(self)
            ShowCategoryTooltip(self, category, self.seconds, self.total)
        end)
        segment:SetScript("OnLeave", HideTooltip)
        stack.segments[category.id] = segment
    end
    return stack
end

local function CreateRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(LEFT_WIDTH, ROW_HEIGHT)
    row:EnableMouse(true)
    row.hover = Texture(row, TEXT_PRIMARY, 0.05, "BACKGROUND")
    row.hover:SetAllPoints()
    row.hover:Hide()
    row.swatch = row:CreateTexture(nil, "ARTWORK")
    row.swatch:SetPoint("LEFT", 6, 0)
    row.swatch:SetSize(10, 10)
    row.label = Text(row, 12, TEXT_PRIMARY)
    row.label:SetPoint("LEFT", 24, 0)
    row.track = Texture(row, RAISED, 1, "BORDER")
    row.track:SetPoint("LEFT", 148, 0)
    row.track:SetSize(130, 6)
    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.bar:SetPoint("LEFT", 148, 0)
    row.time = Text(row, 12, TEXT_PRIMARY, "RIGHT")
    row.time:SetPoint("RIGHT", -44, 0)
    row.percent = Text(row, 12, TEXT_MUTED, "RIGHT")
    row.percent:SetPoint("RIGHT", -6, 0)
    row:SetScript("OnEnter", function(self)
        self.hover:Show()
        ShowCategoryTooltip(self, self.category, self.seconds, self.total)
    end)
    row:SetScript("OnLeave", function(self)
        self.hover:Hide()
        HideTooltip()
    end)
    return row
end

local function CreateChart(parent)
    local chart = CreateFrame("Frame", nil, parent)
    chart:SetPoint("TOPLEFT", RIGHT_X, -CHART_TOP)
    chart:SetSize(RIGHT_WIDTH, 300)

    chart.title = Text(chart, 13, TEXT_PRIMARY)
    chart.title:SetPoint("TOPLEFT", 0, 0)
    chart.empty = Text(chart, 12, TEXT_MUTED, "CENTER")
    chart.empty:SetPoint("CENTER", 0, 0)

    local daily = CreateFrame("Frame", nil, chart)
    daily:SetAllPoints()
    chart.daily = daily
    daily.gridLines, daily.gridLabels, daily.columns = {}, {}, {}
    for index = 0, 3 do
        local line = Texture(daily, LINE, 1, "BACKGROUND")
        line:SetHeight(1)
        line:SetPoint("BOTTOMLEFT", AXIS_WIDTH, 28 + index * PLOT_HEIGHT / 3)
        line:SetPoint("BOTTOMRIGHT", 0, 28 + index * PLOT_HEIGHT / 3)
        daily.gridLines[index] = line
        local label = Text(daily, 10, TEXT_MUTED, "RIGHT")
        label:SetPoint("RIGHT", line, "LEFT", -6, 0)
        daily.gridLabels[index] = label
    end
    daily.firstDay = Text(daily, 10, TEXT_MUTED)
    daily.firstDay:SetPoint("BOTTOMLEFT", AXIS_WIDTH, 10)
    daily.lastDay = Text(daily, 10, TEXT_MUTED, "RIGHT")
    daily.lastDay:SetPoint("BOTTOMRIGHT", 0, 10)

    local timeline = CreateFrame("Frame", nil, chart)
    timeline:SetAllPoints()
    chart.timeline = timeline
    timeline.bins = {}
    local binWidth = RIGHT_WIDTH / BIN_COUNT
    for index = 1, BIN_COUNT do
        local bin = CreateFrame("Frame", nil, timeline)
        bin:SetPoint("TOPLEFT", (index - 1) * binWidth, -30)
        bin:SetSize(binWidth + 1, 52) -- overlap hides seams between fractional widths
        bin:EnableMouse(true)
        bin.fill = bin:CreateTexture(nil, "ARTWORK")
        bin.fill:SetAllPoints()
        bin:SetScript("OnEnter", function(self)
            if self.category then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(self.category.label, 0.94, 0.94, 0.93)
                GameTooltip:AddLine(self.span, 0.77, 0.76, 0.72)
                GameTooltip:Show()
            end
        end)
        bin:SetScript("OnLeave", HideTooltip)
        timeline.bins[index] = bin
    end
    timeline.startLabel = Text(timeline, 10, TEXT_MUTED)
    timeline.startLabel:SetPoint("TOPLEFT", 0, -88)
    timeline.endLabel = Text(timeline, 10, TEXT_MUTED, "RIGHT")
    timeline.endLabel:SetPoint("TOPRIGHT", 0, -88)

    timeline.facts = {}
    for index = 1, 3 do
        local y = -120 - (index - 1) * 26
        local label = Text(timeline, 12, TEXT_MUTED)
        label:SetPoint("TOPLEFT", 0, y)
        local value = Text(timeline, 12, TEXT_PRIMARY, "RIGHT")
        value:SetPoint("TOPRIGHT", 0, y)
        timeline.facts[index] = { label = label, value = value }
    end
    return chart
end

local function CreateColumn(daily, index, width, gap)
    local column = CreateFrame("Frame", nil, daily)
    column:SetPoint("BOTTOMLEFT", AXIS_WIDTH + (index - 1) * (width + gap), 28)
    column:SetSize(width + gap, PLOT_HEIGHT)
    column:EnableMouse(true)
    column.hover = Texture(column, TEXT_PRIMARY, 0.05, "BACKGROUND")
    column.hover:SetAllPoints()
    column.hover:Hide()
    column.fills = {}
    for _, category in ipairs(CATEGORIES) do
        column.fills[category.id] = Texture(column, category.color)
    end
    column:SetScript("OnEnter", function(self)
        self.hover:Show()
        if self.day then
            ShowBreakdownTooltip(self, date("%a %b %d", self.day.timestamp), self.day.totals, self.day.total)
        end
    end)
    column:SetScript("OnLeave", function(self)
        self.hover:Hide()
        HideTooltip()
    end)
    return column
end

local function CreateWindow()
    local frame = CreateFrame("Frame", "ForeverTimeTrackerFrame", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint()
        Store.Settings().position = { point, relativePoint, x, y }
    end)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    frame:SetBackdropColor(SURFACE[1], SURFACE[2], SURFACE[3], 0.98)
    frame:SetBackdropBorderColor(LINE[1], LINE[2], LINE[3], 1)
    frame:Hide()
    tinsert(UISpecialFrames, "ForeverTimeTrackerFrame")

    local parts = {}

    local title = Text(frame, 16, TEXT_PRIMARY)
    title:SetPoint("TOPLEFT", PAD, -16)
    title:SetText("Forever Time Tracker")

    parts.statusSwatch = frame:CreateTexture(nil, "ARTWORK")
    parts.statusSwatch:SetSize(8, 8)
    parts.statusSwatch:SetPoint("TOPLEFT", PAD, -43)
    parts.statusText = Text(frame, 12, TEXT_SECONDARY)
    parts.statusText:SetPoint("TOPLEFT", PAD + 14, -40)

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", -10, -10)
    close.text = Text(close, 16, TEXT_SECONDARY, "CENTER")
    close.text:SetPoint("CENTER")
    close.text:SetText("x")
    close:SetScript("OnClick", function() frame:Hide() end)
    close:SetScript("OnEnter", function(self)
        self.text:SetTextColor(TEXT_PRIMARY[1], TEXT_PRIMARY[2], TEXT_PRIMARY[3])
    end)
    close:SetScript("OnLeave", function(self)
        self.text:SetTextColor(TEXT_SECONDARY[1], TEXT_SECONDARY[2], TEXT_SECONDARY[3])
    end)

    parts.rangeButtons = {}
    for index, range in ipairs(RANGES) do
        local button = CreateSegmentButton(frame, range.label, 76, function()
            Store.Settings().range = range.id
            UI.Refresh()
        end)
        button:SetPoint("TOPLEFT", PAD + (index - 1) * 78, -66)
        parts.rangeButtons[range.id] = button
    end
    parts.scopeButtons = {}
    for index, scope in ipairs(SCOPES) do
        local button = CreateSegmentButton(frame, scope.label, 112, function()
            Store.Settings().scope = scope.id
            UI.Refresh()
        end)
        button:SetPoint("TOPRIGHT", -PAD - (#SCOPES - index) * 114, -66)
        parts.scopeButtons[scope.id] = button
    end

    local tileGap = 8
    local tileWidth = (CONTENT_WIDTH - tileGap * 3) / 4
    parts.totalTile = CreateTile(frame, PAD, tileWidth, 20)
    parts.playingTile = CreateTile(frame, PAD + (tileWidth + tileGap), tileWidth, 20)
    parts.awayTile = CreateTile(frame, PAD + (tileWidth + tileGap) * 2, tileWidth, 20)
    parts.topTile = CreateTile(frame, PAD + (tileWidth + tileGap) * 3, tileWidth, 15)
    parts.totalTile.label:SetText("Total time")
    parts.playingTile.label:SetText("Actively playing")
    parts.awayTile.label:SetText("Idle, AFK & loading")
    parts.topTile.label:SetText("Top activity")

    parts.stackHolder = CreateFrame("Frame", nil, frame)
    parts.stackHolder:SetPoint("TOPLEFT", PAD, -176)
    parts.stackHolder:SetSize(CONTENT_WIDTH, 18)
    parts.stack = CreateStack(parts.stackHolder)

    parts.rows = {}
    for index = 1, #CATEGORIES do
        local row = CreateRow(frame)
        row:SetPoint("TOPLEFT", PAD, -CHART_TOP - (index - 1) * ROW_HEIGHT)
        parts.rows[index] = row
    end

    parts.chart = CreateChart(frame)

    parts.footerLine = Texture(frame, LINE, 1, "BACKGROUND")
    parts.footerLine:SetHeight(1)
    parts.footerLine:SetPoint("BOTTOMLEFT", PAD, 34)
    parts.footerLine:SetPoint("BOTTOMRIGHT", -PAD, 34)
    parts.footer = Text(frame, 11, TEXT_MUTED)
    parts.footer:SetPoint("BOTTOMLEFT", PAD, 14)

    frame:SetScript("OnShow", function() UI.Refresh() end)

    local position = Store.Settings().position
    if position then
        frame:SetPoint(position[1], UIParent, position[2], position[3], position[4])
    else
        frame:SetPoint("CENTER")
    end
    return frame, parts
end

local function RefreshStatus()
    local current = ns.Tracker.Current()
    local category = current and CATEGORY[current]
    if category then
        widgets.statusSwatch:SetColorTexture(category.color[1], category.color[2], category.color[3], 1)
        widgets.statusSwatch:Show()
        widgets.statusText:SetText("Right now: " .. category.label)
    else
        widgets.statusSwatch:Hide()
        widgets.statusText:SetText("Waiting for the first sample")
    end
end

local function RefreshControls(rangeId, scopeId)
    for id, button in pairs(widgets.rangeButtons) do
        SetSegmentSelected(button, id == rangeId, true)
    end
    -- A session is one character by definition, so the scope has no effect there.
    local scoped = rangeId ~= "session"
    for id, button in pairs(widgets.scopeButtons) do
        SetSegmentSelected(button, scoped and id == scopeId, scoped)
    end
end

local function RefreshTiles(totals, total)
    local playing, away, top = 0, 0, nil
    for _, category in ipairs(CATEGORIES) do
        local seconds = totals[category.id] or 0
        if category.playing then
            playing = playing + seconds
            if seconds > 0 and (not top or seconds > (totals[top.id] or 0)) then
                top = category
            end
        else
            away = away + seconds
        end
    end
    widgets.totalTile.value:SetText(FormatDuration(total))
    widgets.totalTile.note:SetText("")
    widgets.playingTile.value:SetText(FormatDuration(playing))
    widgets.playingTile.note:SetText(FormatPercent(playing, total))
    widgets.awayTile.value:SetText(FormatDuration(away))
    widgets.awayTile.note:SetText(FormatPercent(away, total))
    if top then
        widgets.topTile.value:SetText(top.label)
        widgets.topTile.note:SetText(FormatPercent(totals[top.id], total))
    else
        widgets.topTile.value:SetText("-")
        widgets.topTile.note:SetText("")
    end
end

local function RefreshStack(totals, total)
    local x = 0
    for _, category in ipairs(CATEGORIES) do
        local segment = widgets.stack.segments[category.id]
        local seconds = totals[category.id] or 0
        local width = total > 0 and seconds / total * CONTENT_WIDTH or 0
        if seconds > 0 and width >= 1 then
            segment.seconds, segment.total = seconds, total
            segment:ClearAllPoints()
            segment:SetPoint("TOPLEFT", x, 0)
            segment:SetWidth(width)
            segment.fill:SetWidth(width >= 4 and width - 2 or width)
            segment:Show()
            x = x + width
        else
            segment:Hide()
        end
    end
end

local function RefreshRows(totals, total)
    local sorted = {}
    for _, category in ipairs(CATEGORIES) do
        sorted[#sorted + 1] = category
    end
    table.sort(sorted, function(a, b)
        local secondsA, secondsB = totals[a.id] or 0, totals[b.id] or 0
        if secondsA ~= secondsB then
            return secondsA > secondsB
        end
        return a.order < b.order
    end)
    local largest = totals[sorted[1].id] or 0
    for index, category in ipairs(sorted) do
        local row = widgets.rows[index]
        local seconds = totals[category.id] or 0
        local color = category.color
        row.category, row.seconds, row.total = category, seconds, total
        row.swatch:SetColorTexture(color[1], color[2], color[3], 1)
        row.label:SetText(category.label)
        row.bar:SetColorTexture(color[1], color[2], color[3], 1)
        SetSpan(row.bar, largest > 0 and seconds / largest * 130 or 0, 6)
        if seconds > 0 then
            row.label:SetTextColor(TEXT_PRIMARY[1], TEXT_PRIMARY[2], TEXT_PRIMARY[3])
            row.time:SetText(FormatDuration(seconds))
            row.percent:SetText(FormatPercent(seconds, total))
        else
            row.label:SetTextColor(TEXT_MUTED[1], TEXT_MUTED[2], TEXT_MUTED[3])
            row.time:SetText("")
            row.percent:SetText("")
        end
    end
end

local function RefreshDaily(rangeInfo, scopeId)
    local chart = widgets.chart
    local daily = chart.daily
    local history = Store.DailyHistory(rangeInfo.days, scopeId)
    chart.title:SetText(string.format("Daily split, last %d days", rangeInfo.days))

    local peak = 0
    for _, day in ipairs(history) do
        peak = math.max(peak, day.total)
    end
    local step = AXIS_STEPS[#AXIS_STEPS]
    for _, candidate in ipairs(AXIS_STEPS) do
        if candidate * 3 >= peak then
            step = candidate
            break
        end
    end
    local axisMax = step * 3
    for index = 0, 3 do
        daily.gridLabels[index]:SetText(index == 0 and "0" or FormatDuration(step * index):gsub(" 0m$", ""):gsub(" 0s$", ""))
    end

    local slot = (RIGHT_WIDTH - AXIS_WIDTH) / #history
    local gap = #history > 14 and 1 or 4
    local barWidth = slot - gap
    for index = 1, math.max(#history, #daily.columns) do
        local column = daily.columns[index]
        local day = history[index]
        if day and not column then
            column = CreateColumn(daily, index, barWidth, gap)
            daily.columns[index] = column
        end
        if column then
            if day then
                column:ClearAllPoints()
                column:SetPoint("BOTTOMLEFT", AXIS_WIDTH + (index - 1) * slot, 28)
                column:SetWidth(slot)
                column.day = day
                column:Show()
                local y = 0
                for _, category in ipairs(CATEGORIES) do
                    local fill = column.fills[category.id]
                    local height = (day.totals[category.id] or 0) / axisMax * PLOT_HEIGHT
                    if SetSpan(fill, barWidth, height) then
                        fill:ClearAllPoints()
                        fill:SetPoint("BOTTOMLEFT", gap / 2, y)
                        fill:SetHeight(height >= 3 and height - 1 or height)
                        y = y + height
                    end
                end
            else
                column:Hide()
            end
        end
    end
    daily.firstDay:SetText(date("%b %d", history[1].timestamp))
    daily.lastDay:SetText(date("%b %d", history[#history].timestamp))
    chart.empty:SetText(peak > 0 and "" or "No time recorded in these days")
end

local function RefreshTimeline()
    local chart = widgets.chart
    local timeline = chart.timeline
    chart.title:SetText("This session, start to now")
    chart.empty:SetText("")

    local bins, total = Store.SessionBins(BIN_COUNT)
    local summary = Store.SessionSummary()
    for index, bin in ipairs(timeline.bins) do
        local info = bins[index]
        local category = info and info.id and CATEGORY[info.id]
        if category then
            bin.category = category
            bin.span = FormatDuration(info.from) .. " to " .. FormatDuration(info.to) .. " into the session"
            bin.fill:SetColorTexture(category.color[1], category.color[2], category.color[3], 1)
            bin:Show()
        else
            bin.category = nil
            bin:Hide()
        end
    end
    timeline.startLabel:SetText(date("%H:%M", summary.startedAt))
    timeline.endLabel:SetText(date("%H:%M", summary.startedAt + total))

    local facts = timeline.facts
    facts[1].label:SetText("Session length")
    facts[1].value:SetText(FormatDuration(total))
    facts[2].label:SetText("Longest stretch")
    if summary.longest and CATEGORY[summary.longest.id] then
        facts[2].value:SetText(CATEGORY[summary.longest.id].label .. ", " .. FormatDuration(summary.longest.seconds))
    else
        facts[2].value:SetText("-")
    end
    facts[3].label:SetText("Activity switches")
    facts[3].value:SetText(tostring(summary.switches))
end

local function RefreshFooter()
    local char = Store.Character()
    local parts = {}
    if char.trackedSince then
        parts[#parts + 1] = "Tracking this character since " .. date("%b %d, %Y", char.trackedSince)
    end
    if char.played and char.playedAt then
        parts[#parts + 1] = "/played was " .. FormatDuration(char.played) .. " on " .. date("%b %d", char.playedAt)
    else
        parts[#parts + 1] = "Type /played once to compare against the game's total"
    end
    widgets.footer:SetText(table.concat(parts, "  ·  "))
end

function UI.Refresh()
    if not (window and window:IsShown()) then
        return
    end
    local settings = Store.Settings()
    local rangeId, scopeId = settings.range, settings.scope
    local rangeInfo = RANGE_BY_ID[rangeId] or RANGES[1]
    local effectiveScope = rangeId == "session" and "character" or scopeId
    local totals, total = Store.Totals(rangeInfo.id, effectiveScope)

    RefreshStatus()
    RefreshControls(rangeInfo.id, scopeId)
    RefreshTiles(totals, total)
    RefreshStack(totals, total)
    RefreshRows(totals, total)
    if rangeInfo.id == "session" then
        widgets.chart.daily:Hide()
        widgets.chart.timeline:Show()
        RefreshTimeline()
    else
        widgets.chart.timeline:Hide()
        widgets.chart.daily:Show()
        RefreshDaily(rangeInfo, effectiveScope)
    end
    RefreshFooter()
end

function UI.Toggle()
    if not Store.IsReady() then
        return
    end
    if not window then
        window, widgets = CreateWindow()
    end
    if window:IsShown() then
        window:Hide()
    else
        window:Show()
    end
end

function UI.OnSample()
    UI.Refresh()
end

local minimapButton

local function PlaceMinimapButton()
    local angle = math.rad(Store.Settings().minimapAngle)
    local radius = Minimap:GetWidth() / 2 + 6
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function DragMinimapButton()
    local centerX, centerY = Minimap:GetCenter()
    local cursorX, cursorY = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    Store.Settings().minimapAngle = math.deg(math.atan2(cursorY / scale - centerY, cursorX / scale - centerX))
    PlaceMinimapButton()
end

local function CreateMinimapButton()
    minimapButton = CreateFrame("Button", "ForeverTimeTrackerMinimapButton", Minimap)
    minimapButton:SetSize(31, 31)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetFrameLevel(8)
    minimapButton:RegisterForDrag("LeftButton")
    minimapButton:RegisterForClicks("LeftButtonUp")
    local icon = minimapButton:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER")
    -- Button collectors such as EllesmereUI's flyout look for this field.
    minimapButton.icon = icon
    local border = minimapButton:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    minimapButton:SetScript("OnClick", UI.Toggle)
    minimapButton:SetScript("OnDragStart", function(self)
        -- Once a button collector has reparented it, the collector owns its position.
        if self:GetParent() == Minimap then
            self:SetScript("OnUpdate", DragMinimapButton)
        end
    end)
    minimapButton:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    minimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Forever Time Tracker", 0.94, 0.94, 0.93)
        local current = ns.Tracker.Current()
        if current then
            GameTooltip:AddLine("Right now: " .. CATEGORY[current].label, 0.77, 0.76, 0.72)
        end
        GameTooltip:AddLine("Click to open, drag to move", 0.56, 0.56, 0.52)
        GameTooltip:Show()
    end)
    minimapButton:SetScript("OnLeave", HideTooltip)
    PlaceMinimapButton()
end

function UI.OnReady()
    if not Store.Settings().minimapHidden then
        CreateMinimapButton()
    end
end

function UI.ToggleMinimapButton()
    local settings = Store.Settings()
    settings.minimapHidden = not settings.minimapHidden
    if settings.minimapHidden then
        if minimapButton then
            minimapButton:Hide()
        end
    elseif minimapButton then
        minimapButton:Show()
    else
        CreateMinimapButton()
    end
end
