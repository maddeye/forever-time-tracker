local _, ns = ...

local Clean = ns.Clean

-- Spell IDs resolve to the client's language; the literal names cover spell IDs
-- that differ on this client. Exact IDs on Forever are unverified.
local GATHER_SPELL_IDS = { 2366, 2575, 8613, 7620, 131474 }
local GATHER_NAMES = {
    ["Herb Gathering"] = true, ["Mining"] = true, ["Skinning"] = true, ["Fishing"] = true,
    ["Kräutersammeln"] = true, ["Bergbau"] = true, ["Kürschnerei"] = true, ["Angeln"] = true,
}

local FOOD_AURA_NAMES = {
    ["Food"] = true, ["Drink"] = true, ["Food & Drink"] = true, ["Refreshment"] = true,
    ["Essen"] = true, ["Trinken"] = true, ["Essen & Trinken"] = true,
    ["Nourriture"] = true, ["Boisson"] = true,
    ["Comida"] = true, ["Bebida"] = true,
}

local CRAFT_WINDOWS = { tradeskill = true, craft = true }

local gatherNamesResolved = false

local function ResolveGatherNames()
    gatherNamesResolved = true
    if not (C_Spell and C_Spell.GetSpellName) then
        return
    end
    for _, spellId in ipairs(GATHER_SPELL_IDS) do
        local ok, name = pcall(C_Spell.GetSpellName, spellId)
        name = ok and Clean(name) or nil
        if name then
            GATHER_NAMES[name] = true
        end
    end
end

local function Flag(fn, ...)
    if not fn then
        return false
    end
    local ok, value = pcall(fn, ...)
    if not ok then
        return false
    end
    return Clean(value) and true or false
end

-- UnitCastingInfo and UnitChannelInfo both return the name first and isTradeSkill sixth.
local function ReadCast(fn)
    if not fn then
        return nil, false
    end
    local ok, name, _, _, _, _, isTradeSkill = pcall(fn, "player")
    if not ok then
        return nil, false
    end
    return Clean(name), Clean(isTradeSkill) and true or false
end

local function ScanForFood()
    for index = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", index, "HELPFUL")
        if not aura then
            return false
        end
        local name = Clean(aura.name)
        if name and FOOD_AURA_NAMES[name] then
            return true
        end
    end
    return false
end

local function HasFoodAura()
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then
        return false
    end
    local ok, found = pcall(ScanForFood)
    return ok and found or false
end

-- Reads what the player is doing right now. context holds what only events can
-- tell us: open windows and the combat and movement flags.
function ns.ReadState(context)
    if not gatherNamesResolved then
        ResolveGatherNames()
    end

    local state = {
        combat = Flag(UnitAffectingCombat, "player") or context.combat,
        afk = Flag(UnitIsAFK, "player"),
        dead = Flag(UnitIsDeadOrGhost, "player"),
        taxi = Flag(UnitOnTaxi, "player"),
    }

    state.moving = context.moving
    if GetUnitSpeed then
        local ok, speed = pcall(GetUnitSpeed, "player")
        speed = ok and Clean(speed) or nil
        if speed then
            state.moving = speed > 0
        end
    end

    local castName, tradeSkill = ReadCast(UnitCastingInfo)
    if not castName then
        castName, tradeSkill = ReadCast(UnitChannelInfo)
    end
    state.gatherCast = castName ~= nil and GATHER_NAMES[castName] == true
    state.craftCast = tradeSkill

    state.craftWindow, state.npcWindow = false, false
    for window in pairs(context.windows) do
        if CRAFT_WINDOWS[window] then
            state.craftWindow = true
        else
            state.npcWindow = true
        end
    end

    -- Auras only matter when nothing else explains standing still.
    state.eating = false
    if not (state.combat or state.afk or state.dead or state.moving or state.taxi
            or state.gatherCast or state.craftCast or state.craftWindow or state.npcWindow) then
        state.eating = HasFoodAura()
    end
    return state
end

-- Exactly one category per sample, highest priority first. Combat beats AFK so
-- being attacked while away counts as a fight; AFK beats dead so a corpse left
-- for half an hour counts as away.
function ns.Classify(state)
    if state.combat then return "fighting" end
    if state.afk then return "afk" end
    if state.dead then return "dead" end
    if state.gatherCast then return "gathering" end
    if state.craftCast then return "crafting" end
    if state.taxi or state.moving then return "traveling" end
    if state.craftWindow then return "crafting" end
    if state.npcWindow then return "npcs" end
    if state.eating then return "resting" end
    return "idle"
end
