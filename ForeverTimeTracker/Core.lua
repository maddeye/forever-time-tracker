local _, ns = ...

-- Order is fixed: stacked bars draw in this order and hues never follow rank.
-- Colored categories are play; grey ones are time spent not really playing.
ns.CATEGORIES = {
    { id = "traveling", label = "Traveling", color = { 0.224, 0.529, 0.898 }, playing = true,
      desc = "Moving on foot, mounted, swimming or on a flight path." },
    { id = "fighting", label = "Fighting", color = { 0.851, 0.349, 0.149 }, playing = true,
      desc = "The game has you flagged as in combat." },
    { id = "gathering", label = "Gathering", color = { 0.098, 0.620, 0.439 }, playing = true,
      desc = "Mining, herbing, skinning and fishing casts." },
    { id = "crafting", label = "Crafting", color = { 0.788, 0.522, 0.000 }, playing = true,
      desc = "Tradeskill casts, or standing with a profession window open." },
    { id = "resting", label = "Eating & Drinking", color = { 0.835, 0.318, 0.506 }, playing = true,
      desc = "Standing with a food or drink buff." },
    { id = "npcs", label = "NPCs & Trade", color = { 0.000, 0.514, 0.000 }, playing = true,
      desc = "Quest dialogs, vendors, trainers, mail, bank, auction house and trades." },
    { id = "dead", label = "Dead", color = { 0.565, 0.522, 0.914 }, playing = true,
      desc = "Dead or running back as a ghost." },
    { id = "idle", label = "Idle", color = { 0.560, 0.555, 0.520 }, playing = false,
      desc = "In game and not moving: chatting, reading the map, deciding what to do." },
    { id = "afk", label = "AFK", color = { 0.400, 0.396, 0.372 }, playing = false,
      desc = "Flagged AFK, plus the idle stretch that led up to the flag." },
    { id = "loading", label = "Loading", color = { 0.290, 0.288, 0.270 }, playing = false,
      desc = "Loading screens between zones and instances." },
}

ns.CATEGORY = {}
for index, category in ipairs(ns.CATEGORIES) do
    category.order = index
    ns.CATEGORY[category.id] = category
end

-- Midnight's secret values raise an error when compared or used as table keys,
-- so anything read from the game passes through here first.
function ns.Clean(value)
    if issecretvalue and issecretvalue(value) then
        return nil
    end
    return value
end

function ns.FormatDuration(seconds)
    seconds = math.floor(seconds or 0)
    if seconds < 60 then
        return seconds .. "s"
    elseif seconds < 3600 then
        return string.format("%dm %ds", math.floor(seconds / 60), seconds % 60)
    end
    return string.format("%dh %dm", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
end

function ns.FormatPercent(part, total)
    if not total or total <= 0 then
        return "0%"
    end
    local percent = part / total * 100
    if percent > 0 and percent < 1 then
        return "<1%"
    end
    return string.format("%d%%", math.floor(percent + 0.5))
end
