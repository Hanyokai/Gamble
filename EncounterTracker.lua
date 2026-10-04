GambleEncounterTracker = GambleEncounterTracker or {}
local Tracker = GambleEncounterTracker

Tracker.HP_MAX_AGE = 3.0

local function Readable(value)
    if canaccessvalue then
        local ok, allowed = pcall(canaccessvalue, value)
        if ok and not allowed then return false end
    end
    return true
end

Tracker.options = {
    BOSS_HP_WIPE = {
        { key = "HP_75_100", label = "75–100 %", min = 75, max = 100 },
        { key = "HP_50_75", label = "50–74.99 %", min = 50, max = 75 },
        { key = "HP_25_50", label = "25–49.99 %", min = 25, max = 50 },
        { key = "HP_10_25", label = "10–24.99 %", min = 10, max = 25 },
        { key = "HP_1_10", label = "1–9.99 %", min = 1, max = 10 },
        { key = "HP_LT_1", label = "below 1%", min = 0, max = 1 },
    },
    PULL_TIMER_DEATH = {
        { key = "TIME_0_15", label = "0–15 seconds", min = 0, max = 16 },
        { key = "TIME_16_30", label = "16–30 seconds", min = 16, max = 31 },
        { key = "TIME_31_60", label = "31–60 seconds", min = 31, max = 61 },
        { key = "TIME_61_120", label = "61–120 seconds", min = 61, max = 121 },
        { key = "TIME_GT_120", label = "over 120 seconds", min = 121, max = math.huge },
        { key = "NO_DEATH", label = "No Death", noDeath = true },
    },
    TOTAL_DEATHS = {
        { key = "DEATHS_0", label = "0", min = 0, max = 1 },
        { key = "DEATHS_1", label = "1", min = 1, max = 2 },
        { key = "DEATHS_2", label = "2", min = 2, max = 3 },
        { key = "DEATHS_3", label = "3", min = 3, max = 4 },
        { key = "DEATHS_4", label = "4", min = 4, max = 5 },
        { key = "DEATHS_5_PLUS", label = "5+", min = 5, max = math.huge },
    },
}

function Tracker:IsMode(mode)
    return self.options[mode] ~= nil
end

function Tracker:GetOptions(mode)
    return self.options[mode] or {}
end

function Tracker:GetOption(mode, key)
    key = tostring(key or ""):gsub("^OPT:", "")
    for _, option in ipairs(self:GetOptions(mode)) do
        if option.key == key then return option end
    end
end

function Tracker:OptionForValue(mode, value)
    value = tonumber(value)
    if not value then return nil end
    for _, option in ipairs(self:GetOptions(mode)) do
        if not option.noDeath and value >= option.min and (value < option.max or (mode == "BOSS_HP_WIPE" and option.max == 100 and value <= 100)) then return option end
    end
end

local function Now()
    return GetTime and GetTime() or time()
end

function Tracker:Start(wager, encounterID, encounterName)
    wager.encounterTracker = {
        active = true,
        encounterID = tonumber(encounterID),
        encounterName = encounterName,
        startedAt = Now(),
        deaths = {},
        totalDeaths = 0,
        deadUnits = {},
    }
    for _, member in ipairs(wager.units or {}) do
        local ok, dead = pcall(UnitIsDeadOrGhost, member.unit)
        if ok and Readable(dead) and type(dead) == "boolean" and dead then wager.encounterTracker.deadUnits[member.unit] = true end
    end
end

function Tracker:RecordDeath(wager, guid, name, unit)
    local tracker = wager and wager.encounterTracker
    if not tracker or not tracker.active or not guid then return nil end
    tracker.totalDeaths = (tracker.totalDeaths or 0) + 1
    local stamp = Now()
    local death = { guid = guid, name = name, stamp = stamp, elapsed = math.max(0, stamp - (tracker.startedAt or stamp)), order = tracker.totalDeaths, unit = unit }
    tracker.deaths[#tracker.deaths + 1] = death
    tracker.firstDeath = tracker.firstDeath or death
    return death
end

function Tracker:RefreshAliveUnits(wager)
    local tracker = wager and wager.encounterTracker
    if not tracker or not tracker.active then return end
    for _, member in ipairs(wager.units or {}) do
        local ok, dead = pcall(UnitIsDeadOrGhost, member.unit)
        if ok and Readable(dead) and type(dead) == "boolean" and not dead then tracker.deadUnits[member.unit] = nil end
    end
end

function Tracker:FindNewDeaths(wager, eventGUID)
    local tracker = wager and wager.encounterTracker
    local found = {}
    if not tracker or not tracker.active then return found end
    self:RefreshAliveUnits(wager)
    for _, member in ipairs(wager.units or {}) do
        local ok, dead = pcall(UnitIsDeadOrGhost, member.unit)
        local feigning = false
        if UnitIsFeignDeath then
            local feignOK, feignValue = pcall(UnitIsFeignDeath, member.unit)
            feigning = feignOK and Readable(feignValue) and feignValue and true or false
        end
        if ok and Readable(dead) and type(dead) == "boolean" and dead and not feigning and not tracker.deadUnits[member.unit] then
            tracker.deadUnits[member.unit] = true
            found[#found + 1] = { guid = member.guid, name = member.name, unit = member.unit }
        end
    end
    return found
end

function Tracker:SampleBossHealth(wager, preferredUnit)
    local tracker = wager and wager.encounterTracker
    if not tracker or not tracker.active then return nil end
    local units = preferredUnit and { preferredUnit } or { "boss1", "boss2", "boss3", "boss4", "boss5", "target" }
    for _, unit in ipairs(units) do
        local okExists, exists = pcall(UnitExists, unit)
        if okExists and exists then
            local okName, name = pcall(UnitName, unit)
            local bossToken = type(unit) == "string" and unit:match("^boss%d+$")
            local matches = okName and Readable(name) and name and (bossToken or not wager.encounterName or name == wager.encounterName or not wager.bossName or wager.bossName == "" or name == wager.bossName)
            if matches then
                local okHealth, health = pcall(UnitHealth, unit)
                local okMax, maximum = pcall(UnitHealthMax, unit)
                if okHealth and okMax and Readable(health) and Readable(maximum) and type(health) == "number" and type(maximum) == "number" and maximum > 0 then
                    tracker.bossHP = math.max(0, math.min(100, health / maximum * 100))
                    tracker.lastBossHP = tracker.bossHP
                    tracker.lastBossHPAt = Now()
                    local okGUID, guid = pcall(UnitGUID, unit)
                    if okGUID and type(guid) == "string" then tracker.bossGUID = guid end
                    return tracker.bossHP
                end
            end
        end
    end
end

function Tracker:FreshBossHealth(wager)
    local tracker = wager and wager.encounterTracker
    if not tracker or tracker.lastBossHP == nil or not tracker.lastBossHPAt then return nil end
    if Now() - tracker.lastBossHPAt > self.HP_MAX_AGE then return nil end
    return tracker.lastBossHP
end

function Tracker:Stop(wager, success)
    local tracker = wager and wager.encounterTracker
    if not tracker then return end
    tracker.active = false
    tracker.endedAt = Now()
    tracker.success = tonumber(success) == 1
end
