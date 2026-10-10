local ADDON_NAME, Gamble = ...
local CreateFrame = GambleUIStyle and GambleUIStyle.CreateFrame or CreateFrame
Gamble = Gamble or {}

local PREFIX = "GambleFW1"
local VERSION = 32
local ADDON_VERSION = "0.19.15"
local floor, max = math.floor, math.max
local DEFAULT_MINIMAP_RADIUS = 104 -- Abstand vom Mittelpunkt; kann auch mit /gamble minimap ZAHL gesetzt werden.
local DEFAULT_MINIMAP_ANGLE = 225 -- Winkel in Grad; optional mit /gamble minimap RADIUS WINKEL setzen.
local state = { roster = {}, selectedGUID = nil, selectedName = nil, selectedType = nil, selectedBoss = nil, bosses = {}, lootItems = {}, seriesPicks = {}, seriesStep = 1, seriesIncoming = {}, wagers = {}, active = nil, payments = {}, pendingTrade = nil, pendingJoin = nil, escrowRequests = {}, tradeContext = nil, defeatedBosses = {}, knownVersions = {} }
local BET_TYPES = {
    NEXT_PULL = { label = "Who dies first on the next pull?", search = "pull trash combat death" },
    NEXT_BOSS = { label = "Who dies first on the next boss?", search = "boss dungeon raid instance death" },
    BOSS_SERIES = { label = "Boss Series: Who predicts best?", search = "series all bosses dungeon raid jackpot" },
    ITEM_DROP = { label = "Item Drop: What will the next boss drop?", search = "item loot drop boss jackpot" },
    LAST_MAN_STANDING = { label = "Last Man Standing", search = "last man standing wipe last death boss" },
    BOSS_HP_WIPE = { label = "Boss HP Wipe", search = "boss hp wipe percent remaining health" },
    PULL_TIMER_DEATH = { label = "Pull Timer Death", search = "boss timer first death seconds" },
    TOTAL_DEATHS = { label = "Total Deaths", search = "boss total dead count deaths" },
    DOUBLE_OR_NOTHING = { label = "Double or Nothing", search = "double nothing dice roll multiplayer" },
    ROCK_PAPER_SCISSORS = { label = "Rock Paper Scissors", search = "schere stein papier rock paper scissors best of multiplayer" },
    DAMAGE_RACE = { label = "Damage Race", search = "damage dmg dps timer race" },
    BOSS_DAMAGE_SERIES = { label = "Boss Damage Series: Top 3", search = "damage dps boss series dungeon raid top 3" },
}
local BOSS_FALLBACKS = GambleData and GambleData.instances or {}
local function IsBossSeries(mode) return mode == "BOSS_SERIES" or mode == "BOSS_DAMAGE_SERIES" end
local function ValidPrediction(a, guid)
    if a.mode=="BOSS_DAMAGE_SERIES" and guid=="RANK_PENDING" then return true end
    if GambleDamageBets:IsMode(a.mode) then return GambleDamageBets:Valid(a, guid) end
    return a.snapshot[guid]
end

GambleRules = {
    BOSS_DAMAGE_SERIES = "Predict damage places 1–3 for each remaining boss (two places for two players). Each exact place earns one point. Highest total score wins the paid pot; ties split it in proportion to stakes. No correct place or unreadable damage refunds all stakes. Wipes do not score; only successful boss kills count. Rare bosses are optional. After the endboss and every subsequent boss, the host chooses Finish or Continue. There is no automatic payout, even when all bosses are scored. At the confirmed finish, unplayed bosses give no points and no deductions. Tied damage uses shared competition ranks (1, 1, 3). Requires WoW Damage Meter; do not reset it. Everyone must update to the same version.",
    DAMAGE_RACE = "Predict damage places 1–3 (two places for two players), with a different player at each place. Each exact place earns one point. Highest score wins the pot; ties split it in proportion to stakes. Tied damage uses shared competition ranks (1, 1, 3). Zero points or unreadable damage refunds all stakes. Choose 1–30 minutes. Combat at 00:00 extends measurement until group combat ends. Do not reset the meter. Start outside combat. Death alone does not eliminate a player.",
    NEXT_PULL = "Predict the first group member to die during the next pull. Bets close when combat starts. Correct predictions share the pot in proportion to their stakes. If nobody dies or nobody picked the victim, stakes are refunded.",
    NEXT_BOSS = "Choose a boss and predict the first group member to die in that encounter. Bets close when the encounter starts. Correct predictions share the pot in proportion to their stakes. No death or no correct prediction means a refund.",
    LAST_MAN_STANDING = "Choose a boss and predict the last eligible survivor at a wipe, or the last player to die if everyone dies. Only each player's first death counts. Correct predictions split the paid pot equally. A boss kill or no correct prediction refunds stakes. An unclear result requires host review.",
    BOSS_HP_WIPE = "Choose a boss and predict its remaining-health range at the wipe. Correct predictions split the paid pot equally. A boss kill refunds all stakes. Unreliable health data requires review; no correct prediction means a refund.",
    PULL_TIMER_DEATH = "Choose a boss and predict the time range of the first player death, measured from encounter start. Correct predictions split the paid pot equally. A kill without deaths produces NO DEATH. An unclear result requires review; no correct prediction means a refund.",
    TOTAL_DEATHS = "Choose a boss and predict the total player deaths during the encounter. Deaths after a battle resurrection count again. Correct predictions split the paid pot equally. Unclear data requires review; no correct prediction means a refund.",
    BOSS_SERIES = "Predict the first player death for each listed boss. Each correct prediction earns one point. The highest score wins; tied winners split the prize in proportion to their stakes. Silver-marked rare bosses are optional to fight: unplayed rares are skipped, do not block completion and cause no bank deduction. Played rares count normally. For each counted boss with no correct prediction, the bank retains 20% of that boss's share of the pot. The series ends when completed or finalized by the host.",
    ITEM_DROP = "Choose a boss and predict one of its listed drops. An item can only be assigned to one participant. A correct prediction wins the item jackpot. If nobody wins, the bank retains 20% of the current pot and the remainder rolls over to the next jackpot for this boss.",
    DOUBLE_OR_NOTHING = "All players pay the same stake and must be ready before the host starts. Everyone plays all configured rounds. Roll 1–100: 1–50 = OUT (0 points), 51–100 = SAFE (1 point). OUT does not eliminate you. After the final round, the player with the most points wins the pot. Tied leaders roll a tiebreaker: the highest roll wins; tied highest rolls roll again. No additional stake is charged.",
}
function Gamble:GetRules(mode)
    return "|cffffd100Rules|r\n" .. (GambleRules[mode] or "Select a bet type to view its rules.") .. "\n\nParticipants must be in the same party or raid. Payments and trade acceptance are manual. Only confirmed payments count."
end

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffd8b65cGamble:|r " .. tostring(msg))
end

local function DebugLMS(message)
    if GambleDB and GambleDB.debug then DEFAULT_CHAT_FRAME:AddMessage("|cff8888ffLMS:|r " .. tostring(message)) end
end

local function DebugEncounter(message)
    if GambleDB and GambleDB.debug then DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffEncounter:|r " .. tostring(message)) end
end

local function IsEncounterBetMode(mode)
    return GambleEncounterTracker and GambleEncounterTracker:IsMode(mode)
end

local function EncounterOption(mode, key)
    return GambleEncounterTracker and GambleEncounterTracker:GetOption(mode, key)
end

local function FullName(unit)
    local name, realm = UnitFullName(unit)
    if not name then return nil end
    if realm and realm ~= "" then return name .. "-" .. realm end
    return name
end

local function PlayerName()
    return FullName("player") or UnitName("player") or "?"
end

local function DisplayName(name)
    if not name then return "?" end
    if Ambiguate then
        local ok, short = pcall(Ambiguate, name, "short")
        if ok and short and short ~= "" then return short:match("^([^%- ]+)") or short end
    end
    return name:match("^([^%- ]+)") or name
end

local function Money(copper)
    copper = max(0, tonumber(copper) or 0)
    local gold = floor(copper / 10000)
    local silver = floor((copper % 10000) / 100)
    local coins = copper % 100
    local goldIcon = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:1:0|t"
    local silverIcon = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:1:0|t"
    local copperIcon = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:1:0|t"
    return string.format("%d%s %02d%s %02d%s", gold, goldIcon, silver, silverIcon, coins, copperIcon)
end

local function BetLabel(mode)
    return BET_TYPES[mode] and BET_TYPES[mode].label or BET_TYPES.NEXT_PULL.label
end

local function FindWager(id)
    for _, wager in ipairs(state.wagers) do if wager.id == id then return wager end end
end

local function RemoveWager(wager)
    for i, existing in ipairs(state.wagers) do if existing == wager then table.remove(state.wagers, i); return end end
end

local function CharacterStorageKey()
    return tostring(PlayerName()):lower()
end

local function SessionBelongsToCurrentCharacter(saved)
    local me = CharacterStorageKey()
    for _, wager in ipairs(saved and saved.wagers or {}) do
        if wager.host and tostring(wager.host):lower() == me then return true end
        for _, bet in pairs(wager.bets or {}) do if bet.bettor and tostring(bet.bettor):lower() == me then return true end end
        for _, member in pairs(wager.snapshot or {}) do if member.name and tostring(member.name):lower() == me then return true end end
    end
    return false
end

local function SaveSession()
    GambleDB = GambleDB or {}
    GambleDB.version = VERSION
    GambleDB.sessionsByCharacter = GambleDB.sessionsByCharacter or {}
    GambleDB.sessionsByCharacter[CharacterStorageKey()] = {
        wagers = state.wagers,
        activeID = state.active and state.active.id or nil,
        selectedGUID = state.selectedGUID,
        selectedName = state.selectedName,
        selectedType = state.selectedType,
        selectedBoss = state.selectedBoss,
        bosses = state.bosses,
        lootItems = state.lootItems,
        seriesPicks = state.seriesPicks,
        seriesStep = state.seriesStep,
        payments = state.payments,
        defeatedBosses = state.defeatedBosses,
        defeatedInstance = state.defeatedInstance,
        bossResetTimes = state.bossResetTimes,
    }
end

local function RestoreSession()
    local saved = GambleDB and GambleDB.sessionsByCharacter and GambleDB.sessionsByCharacter[CharacterStorageKey()]
    if not saved and GambleDB and GambleDB.session and SessionBelongsToCurrentCharacter(GambleDB.session) then
        saved = GambleDB.session
        GambleDB.sessionsByCharacter = GambleDB.sessionsByCharacter or {}
        GambleDB.sessionsByCharacter[CharacterStorageKey()] = saved
        GambleDB.session = nil
    end
    if not saved then return end
    state.wagers = saved.wagers or {}
    state.selectedGUID = saved.selectedGUID
    state.selectedName = saved.selectedName
    state.selectedType = saved.selectedType
    state.selectedBoss = saved.selectedBoss
    state.bosses = saved.bosses or {}
    state.lootItems = saved.lootItems or {}
    state.seriesPicks = saved.seriesPicks or {}
    state.seriesStep = tonumber(saved.seriesStep) or 1
    state.payments = saved.payments or {}
    local legacyReasons = { ["Gewinn"] = "Winnings", ["Seriengewinn"] = "Series winnings", ["LMS-Gewinn"] = "LMS winnings", ["Rückzahlung"] = "Refund", ["Zu spät – Rückzahlung"] = "Too late – Refund", ["Boss-Tipps unvollständig – Rückzahlung"] = "Incomplete boss predictions – Refund", ["Item bereits vergeben – Rückzahlung"] = "Item already assigned – Refund" }
    for _, payment in ipairs(state.payments) do payment.reason = legacyReasons[payment.reason] or payment.reason end
    state.defeatedBosses = saved.defeatedBosses or {}
    state.defeatedInstance = saved.defeatedInstance
    state.bossResetTimes = saved.bossResetTimes or {}
    state.active = saved.activeID and FindWager(saved.activeID) or nil
    state.restoringSession = true
    for _, wager in ipairs(state.wagers) do
        wager.paymentStatus = wager.paymentStatus or {}
        if wager.host then wager.paymentStatus[wager.host] = "PAID" end
        for _, bet in pairs(wager.bets or {}) do if bet.bettor then wager.paymentStatus[bet.bettor] = "PAID" end end
    end
end

local function BossNameMatches(wanted, actual)
    if not wanted or wanted == "" then return true end
    if not actual then return false end
    if wanted:lower() == actual:lower() then return true end
    for _, bosses in pairs(BOSS_FALLBACKS) do
        for _, boss in ipairs(bosses) do
            if boss.name == wanted then
                for _, alias in ipairs(boss.aliases or {}) do
                    if alias:lower() == actual:lower() then return true end
                end
            end
        end
    end
    return false
end

local function SeriesBossIndex(a, encounterID, encounterName)
    for i, boss in ipairs(a.bosses or {}) do
        if (boss.encounterID and boss.encounterID == encounterID) or (not boss.encounterID and BossNameMatches(boss.name, encounterName)) then return i end
    end
end

local function BossContext()
    if state.selectedBoss then return state.selectedBoss.name, "Selected boss: " .. state.selectedBoss.name, state.selectedBoss.encounterID end
    local targetName
    if not InCombatLockdown() and UnitExists("target") and UnitCanAttack("player", "target") then targetName = UnitName("target") end
    local classification = targetName and UnitClassification("target")
    local bossAPI = false
    if targetName and UnitIsBossMob then local ok, value = pcall(UnitIsBossMob, "target"); bossAPI = ok and value or false end
    local isBossTarget = targetName and (bossAPI or classification == "worldboss" or UnitLevel("target") == -1)
    local instanceName, instanceType = GetInstanceInfo()
    local inInstance = instanceType == "party" or instanceType == "raid"
    if isBossTarget then return targetName, "Targeted boss: " .. targetName, nil end
    if inInstance and instanceName and instanceName ~= "" then return "", "Next boss in " .. instanceName, nil end
    return "", "Next detected boss encounter", nil end

local function SafeField(value)
    value = tostring(value or "")
    return value:gsub("[\t\r\n]", " ")
end

local function Split(message)
    local out = {}
    for part in (message .. "\t"):gmatch("(.-)\t") do out[#out + 1] = part end
    return out
end

local function CanonicalPlayerName(name)
    if not name then return "" end
    if Ambiguate then
        local ok, short = pcall(Ambiguate, name, "short")
        if ok and short and short ~= "" then return (short:match("^([^%- ]+)") or short):lower() end
    end
    return (name:match("^([^%- ]+)") or name):lower()
end

local function IsInOurGroup(sender)
    local short = CanonicalPlayerName(sender)
    for _, member in ipairs(state.roster) do
        if short == CanonicalPlayerName(member.name) then return true end
    end
    return short == CanonicalPlayerName(PlayerName())
end

local function SamePlayer(a, b)
    if not a or not b then return false end
    return CanonicalPlayerName(a) == CanonicalPlayerName(b)
end

local function Channel()
    if LE_PARTY_CATEGORY_INSTANCE then
        local ok, inInstanceGroup = pcall(IsInGroup, LE_PARTY_CATEGORY_INSTANCE)
        if ok and inInstanceGroup then return "INSTANCE_CHAT" end
    end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end

local function Send(...)
    local channel = Channel()
    if not channel then return end
    local fields = { ... }
    if type(fields[1])=="string" and (fields[1]:sub(1,5)=="RANK_" or (GambleDamageBets.queue and #GambleDamageBets.queue>0)) and not GambleDamageBets.dispatching then
        GambleDamageBets:Queue(function()
            GambleDamageBets.dispatching=true
            Send(unpack(fields))
            GambleDamageBets.dispatching=nil
        end)
        return true
    end
    for i = 1, #fields do fields[i] = SafeField(fields[i]) end
    local payload = table.concat(fields, "\t")
    local sender = C_ChatInfo and C_ChatInfo.SendAddonMessage
    local ok, result = sender and pcall(sender, PREFIX, payload, channel)
    if not ok and SendAddonMessage then ok, result = pcall(SendAddonMessage, PREFIX, payload, channel) end
    state.lastCommChannel = channel
    if ok then state.lastCommError = nil else state.lastCommError = tostring(result or "SendAddonMessage unavailable") end
    return ok, result
end

local function VersionParts(version)
    local parts = {}
    for number in tostring(version or "0"):gmatch("%d+") do parts[#parts + 1] = tonumber(number) or 0 end
    return parts
end

local function IsNewerVersion(candidate, current)
    local left, right = VersionParts(candidate), VersionParts(current)
    for index = 1, max(#left, #right) do
        local a, b = left[index] or 0, right[index] or 0
        if a ~= b then return a > b end
    end
    return false
end

local function BroadcastVersion()
    if not Channel() then return end
    state.lastVersionBroadcast = time()
    Send("VERSION", ADDON_VERSION)
end

local function FindRosterByGUID(guid)
    for _, member in ipairs(state.roster) do
        if member.guid == guid then return member end
    end
end

local function FindRosterByName(name)
    local wanted = CanonicalPlayerName(name)
    for _, member in ipairs(state.roster) do
        if CanonicalPlayerName(member.name) == wanted then return member end
    end
end

local function UnitOnline(unit)
    local ok, connected = pcall(UnitIsConnected, unit)
    if not ok then return false end
    if canaccessvalue and not canaccessvalue(connected) then return false end
    return connected and true or false
end

local function UnitLevelSafe(unit)
    local ok, level = pcall(UnitLevel, unit)
    if not ok or (canaccessvalue and not canaccessvalue(level)) then return nil end
    return tonumber(level)
end

local function UnitRoleSafe(unit)
    if not UnitGroupRolesAssigned then return "NONE" end
    local ok, role = pcall(UnitGroupRolesAssigned, unit)
    if not ok or (canaccessvalue and not canaccessvalue(role)) then return "NONE" end
    return role or "NONE"
end

local function BuildRoster()
    wipe(state.roster)
    local count = GetNumGroupMembers()
    if IsInRaid() then
        for i = 1, count do
            local unit = "raid" .. i
            local guid, name = UnitGUID(unit), FullName(unit)
            if guid and name then
                local _, class = UnitClass(unit)
                state.roster[#state.roster + 1] = { unit = unit, guid = guid, name = name, class = class or "PRIEST", level = UnitLevelSafe(unit), role = UnitRoleSafe(unit), online = UnitOnline(unit) }
            end
        end
    else
        local units = { "player", "party1", "party2", "party3", "party4" }
        for _, unit in ipairs(units) do
            if UnitExists(unit) then
                local guid, name = UnitGUID(unit), FullName(unit)
                if guid and name then
                    local _, class = UnitClass(unit)
                    state.roster[#state.roster + 1] = { unit = unit, guid = guid, name = name, class = class or "PRIEST", level = UnitLevelSafe(unit), role = UnitRoleSafe(unit), online = UnitOnline(unit) }
                end
            end
        end
    end
    table.sort(state.roster, function(a, b) return a.name < b.name end)
end

local function CurrentStake()
    local gold = tonumber(Gamble.goldBox:GetText()) or 0
    local silver = tonumber(Gamble.silverBox:GetText()) or 0
    local copper = tonumber(Gamble.copperBox:GetText()) or 0
    gold = max(0, floor(gold)); silver = max(0, floor(silver)); copper = max(0, floor(copper))
    return gold * 10000 + silver * 100 + copper
end

local function SetMoneyBoxes(amount)
    amount = max(0, floor(tonumber(amount) or 0))
    if not Gamble.goldBox or not Gamble.silverBox or not Gamble.copperBox then return end
    Gamble.goldBox:SetText(tostring(floor(amount / 10000)))
    Gamble.silverBox:SetText(tostring(floor((amount % 10000) / 100)))
    Gamble.copperBox:SetText(tostring(amount % 100))
end

local Resolve

local function HasNativeMeterSession()
    if not C_DamageMeter or not C_DamageMeter.IsDamageMeterAvailable then return false end
    local ok, available = pcall(C_DamageMeter.IsDamageMeterAvailable)
    return ok and available and true or false
end

local function CanRead(value)
    if canaccessvalue then return canaccessvalue(value) end
    if issecretvalue then return not issecretvalue(value) end
    return true
end

local function PlayerMoney()
    if not GetMoney then return 0 end
    local ok, amount = pcall(GetMoney)
    if not ok or not CanRead(amount) or type(amount) ~= "number" then return 0 end
    return max(0, floor(amount))
end

local function IsUnitHere(unit)
    local okConnected, connected = pcall(UnitIsConnected, unit)
    local okVisible, visible = pcall(UnitIsVisible, unit)
    return okConnected and CanRead(connected) and connected and okVisible and CanRead(visible) and visible
end

local function SafeGetItemInfo(itemID)
    local getter = GetItemInfo or (C_Item and C_Item.GetItemInfo)
    if not getter then return nil end
    local ok, name, link, quality, level, requiredLevel, itemType, subType, stackCount, equipLocation, icon = pcall(getter, itemID)
    if not ok then return nil end
    return name, link, quality, level, requiredLevel, itemType, subType, stackCount, equipLocation, icon
end

local function NormalizeInstanceName(name)
    if type(name) ~= "string" then return "" end
    name = name:lower()
    name = name:gsub("^the%s+", "")
    name = name:gsub("^stormwind%s+", "")
    return name:gsub("[^%w]", "")
end

local function ResolveInstanceDataName(currentName)
    local aliases = GambleData and GambleData.instanceAliases or {}
    local resolved = aliases[currentName] or currentName
    if BOSS_FALLBACKS[resolved] then return resolved end
    local wanted = NormalizeInstanceName(resolved)
    for dataName in pairs(BOSS_FALLBACKS) do
        if NormalizeInstanceName(dataName) == wanted then return dataName end
    end
    return resolved
end

local function BettingInstanceName()
    local name, kind, difficulty, _, _, _, _, instanceID = GetInstanceInfo()
    GambleDB = GambleDB or {}
    GambleDB.instancesByCharacter = GambleDB.instancesByCharacter or {}
    local key = CharacterStorageKey()
    if (kind == "party" or kind == "raid") and name and name ~= "" then
        GambleDB.instancesByCharacter[key] = { name = name, kind = kind, difficulty = difficulty, instanceID = instanceID }
        return name, kind
    end
    local saved = GambleDB.instancesByCharacter[key]
    if saved then return saved.name, saved.kind end
    return nil, nil
end

local function BettingCreationInstanceName()
    if state.preselectedInstance then return state.preselectedInstance end
    local _,kind=GetInstanceInfo()
    if kind=="party" or kind=="raid" then return BettingInstanceName() end
    local dead=UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")
    if not CanRead(dead) or dead then return BettingInstanceName() end
    for _,name in ipairs(GambleData.GetZoneInstances()) do
        if BOSS_FALLBACKS[name] then return name end
    end
    return BettingInstanceName()
end

local function IsConfiguredEndBoss(a, encounterID, encounterName)
    local instanceName = a and a.instanceName
    if not instanceName or instanceName == "" then instanceName = BettingInstanceName() end
    instanceName = ResolveInstanceDataName(instanceName or "")
    local configured = GambleEndBosses and GambleEndBosses[instanceName]
    if not configured then
        -- Custom instances use the last mandatory boss in their prepared list.
        local last
        for _,boss in ipairs(BOSS_FALLBACKS[instanceName] or {}) do
            if not GambleData.IsRareBoss(boss) then last=boss end
        end
        return last and BossNameMatches(last.name,encounterName) or false
    end
    for _, bossName in ipairs(configured) do
        if BossNameMatches(bossName, encounterName) then return true end
        for _, boss in ipairs(a and a.bosses or {}) do
            if boss.encounterID and encounterID and boss.encounterID == encounterID and BossNameMatches(bossName, boss.name) then return true end
        end
    end
    return false
end

local function BossDefeatKey(instanceName, bossName, encounterID)
    local instanceKey = NormalizeInstanceName(ResolveInstanceDataName(instanceName or ""))
    local bossKey = encounterID and ("id" .. tostring(encounterID)) or NormalizeInstanceName(bossName or "")
    return instanceKey .. ":" .. bossKey
end

local function MarkBossDefeated(instanceName, bossName, encounterID)
    if (not bossName or bossName == "") and not encounterID then return end
    state.defeatedBosses[BossDefeatKey(instanceName, bossName, encounterID)] = true
    if bossName and bossName ~= "" then state.defeatedBosses[BossDefeatKey(instanceName, bossName, nil)] = true end
end

local function IsBossDefeated(instanceName, bossName, encounterID)
    return state.defeatedBosses[BossDefeatKey(instanceName, bossName, encounterID)] or state.defeatedBosses[BossDefeatKey(instanceName, bossName, nil)] or false
end

local function ReadSavedBossDefeats(dataName)
    if not GetNumSavedInstances or not GetSavedInstanceInfo or not GetSavedInstanceEncounterInfo then return end
    local okCount, count = pcall(GetNumSavedInstances)
    if not okCount or type(count) ~= "number" then return end
    for instanceIndex = 1, count do
        local okInfo, savedName, _, _, _, locked, _, _, _, _, _, numEncounters = pcall(GetSavedInstanceInfo, instanceIndex)
        if okInfo and savedName and ResolveInstanceDataName(savedName) == dataName and (locked or (tonumber(numEncounters) or 0) > 0)
            and (locked or not (state.bossResetTimes or {})[dataName]) then
            for encounterIndex = 1, tonumber(numEncounters) or 0 do
                local okEncounter, bossName, _, killed = pcall(GetSavedInstanceEncounterInfo, instanceIndex, encounterIndex)
                if okEncounter and bossName and CanRead(killed) and killed then MarkBossDefeated(dataName, bossName, nil) end
            end
        end
    end
end

local function LoadCurrentInstanceBosses()
    wipe(state.bosses)
    wipe(state.lootItems)
    state.selectedBoss = nil
    state.selectedGUID, state.selectedName = nil, nil
    local currentName = BettingCreationInstanceName()
    if not currentName or currentName == "" then return end
    local dataName = ResolveInstanceDataName(currentName)
    if not state.lastBossSyncRequest or GetTime() - state.lastBossSyncRequest > 3 then
        state.lastBossSyncRequest = GetTime()
        Send("BOSS_PROGRESS_GET", dataName, (state.bossResetTimes or {})[dataName] or 0)
    end
    ReadSavedBossDefeats(dataName)
    state.allBossesDefeated = false
    local function RemoveDefeatedBosses()
        local hadBosses, alive = #state.bosses > 0, {}
        for _, boss in ipairs(state.bosses) do if not boss.defeated then alive[#alive + 1] = boss end end
        state.allBossesDefeated = hadBosses and #alive == 0
        state.bosses = alive
    end
    local function AddBoss(name, encounterID, aliases, fallback, loot)
        if not name or name == "" then return end
        local metadata
        for _,entry in ipairs(BOSS_FALLBACKS[dataName] or {}) do if entry.name==name then metadata=entry; break end end
        for _, existing in ipairs(state.bosses) do
            if existing.name == name then
                existing.encounterID = existing.encounterID or encounterID
                existing.aliases = existing.aliases or aliases
                if metadata then existing.npcID=metadata.npcID; existing.rare=metadata.rare end
                existing.loot = (#(existing.loot or {}) > 0 and existing.loot) or loot
                existing.fallback = existing.fallback or fallback
                existing.defeated = existing.defeated or IsBossDefeated(dataName, name, encounterID)
                return
            end
        end
        state.bosses[#state.bosses + 1] = { name = name, encounterID = encounterID, aliases = aliases, fallback = fallback, loot = loot, npcID=metadata and metadata.npcID, rare=metadata and metadata.rare, defeated = IsBossDefeated(dataName, name, encounterID) }
    end
    if not EJ_GetInstanceByIndex or not EJ_GetEncounterInfoByIndex then
        for _, boss in ipairs(BOSS_FALLBACKS[dataName] or {}) do AddBoss(boss.name, nil, boss.aliases, true, boss.loot) end
        RemoveDefeatedBosses()
        return
    end
    local oldTier = EJ_GetCurrentTier and EJ_GetCurrentTier()
    local journalID
    local tiers = EJ_GetNumTiers and EJ_GetNumTiers() or 1
    for tier = 1, tiers do
        if EJ_SelectTier then pcall(EJ_SelectTier, tier) end
        for _, isRaid in ipairs({ false, true }) do
            for index = 1, 200 do
                local id, name = EJ_GetInstanceByIndex(index, isRaid)
                if not id then break end
                if name == currentName then journalID = id; break end
            end
            if journalID then break end
        end
        if journalID then break end
    end
    if oldTier and EJ_SelectTier then pcall(EJ_SelectTier, oldTier) end
    if journalID then
        if EJ_SelectInstance then pcall(EJ_SelectInstance, journalID) end
        for index = 1, 100 do
            local name, _, _, _, _, _, encounterID = EJ_GetEncounterInfoByIndex(index, journalID)
            if not name then break end
            AddBoss(name, encounterID, nil, false)
        end
    end
    for _, boss in ipairs(BOSS_FALLBACKS[dataName] or {}) do AddBoss(boss.name, nil, boss.aliases, true, boss.loot) end
    RemoveDefeatedBosses()
end

local function MarkCurrentBossDefeated(encounterID, encounterName)
    local instanceName = BettingInstanceName()
    local alreadyKnown = IsBossDefeated(instanceName, encounterName, encounterID)
    MarkBossDefeated(instanceName, encounterName, encounterID)
    if instanceName and not alreadyKnown then
        local dataName=ResolveInstanceDataName(instanceName)
        Send("BOSS_PROGRESS", dataName, encounterName or "", encounterID or "", (state.bossResetTimes or {})[dataName] or 0)
    end
    for index = #state.bosses, 1, -1 do
        local boss = state.bosses[index]
        if (encounterID and boss.encounterID == encounterID) or BossNameMatches(boss.name, encounterName) then
            if state.selectedBoss == boss then
                state.selectedBoss = nil; state.selectedGUID, state.selectedName = nil, nil; wipe(state.lootItems)
                if Gamble.bossDropdown then UIDropDownMenu_SetText(Gamble.bossDropdown, "Boss: auto-detect") end
            end
            table.remove(state.bosses, index)
        end
    end
    state.allBossesDefeated = #state.bosses == 0
end

local function RefreshInstanceDefeatScope()
    local instanceName, instanceType = BettingInstanceName()
    local inside = instanceType == "party" or instanceType == "raid"
    local key = inside and NormalizeInstanceName(ResolveInstanceDataName(instanceName or "")) or nil
    if key ~= state.defeatedInstance then
        wipe(state.defeatedBosses)
        state.defeatedInstance = key
    end
end

local function LoadBossLoot(boss)
    wipe(state.lootItems)
    if not boss then return end
    if boss.encounterID and EJ_GetLootInfoByIndex then
      if EJ_SelectEncounter then pcall(EJ_SelectEncounter, boss.encounterID) end
      for index = 1, 300 do
        local ok, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12 = pcall(EJ_GetLootInfoByIndex, index, boss.encounterID)
        if not ok or not v1 then break end
        local values = { v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12 }
        local itemID = type(v1) == "number" and v1 or nil
        local itemName = type(v3) == "string" and v3 or nil
        local itemLink = type(v7) == "string" and v7:find("|Hitem:", 1, true) and v7 or nil
        local icon = type(v4) == "number" and v4 or nil
        for valueIndex = 1, 12 do
            local value = values[valueIndex]
            if type(value) == "number" then
                if not itemID and value > 100 then itemID = value end
            elseif type(value) == "string" then
                if value:find("|Hitem:", 1, true) then itemLink = value
                elseif not itemName and value ~= "" then itemName = value end
            end
        end
        if itemID then
            local cachedName, cachedLink = SafeGetItemInfo(itemID)
            itemName = itemName or cachedName or ("Item " .. itemID)
            itemLink = itemLink or cachedLink or itemName
            state.lootItems[#state.lootItems + 1] = { id = itemID, name = itemName, link = itemLink, icon = icon }
        end
      end
    end
    if #state.lootItems == 0 then
        for _, fallbackItem in ipairs(boss.loot or {}) do
            if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, fallbackItem.id) end
            local cachedName, cachedLink, _, _, _, _, _, _, _, cachedIcon = SafeGetItemInfo(fallbackItem.id)
            state.lootItems[#state.lootItems + 1] = {
                id = fallbackItem.id,
                name = cachedName or fallbackItem.name,
                link = cachedLink or ("|cff0070dd|Hitem:" .. fallbackItem.id .. "|h[" .. fallbackItem.name .. "]|h|r"),
                icon = cachedIcon,
            }
        end
    end
    table.sort(state.lootItems, function(a, b) return a.name < b.name end)
end

local function FreezeBossEligibleUnits()
    local a = state.active
    if not a or (a.mode ~= "NEXT_BOSS" and not IsBossSeries(a.mode) and a.mode ~= "LAST_MAN_STANDING" and not IsEncounterBetMode(a.mode)) then return end
    BuildRoster()
    local eligible = {}
    for _, member in ipairs(state.roster) do
        if a.snapshot[member.guid] and IsUnitHere(member.unit) then
            eligible[#eligible + 1] = { unit = member.unit, guid = member.guid, name = member.name }
        end
    end
    a.units = eligible
end

local function SnapshotDeadState()
    local a = state.active
    if not a then return end
    a.seenDead = a.seenDead or {}
    for _, member in ipairs(a.units or {}) do
        local ok, dead = pcall(UnitIsDeadOrGhost, member.unit)
        if ok and CanRead(dead) and dead then a.seenDead[member.unit] = true end
    end
end

local function FindGroupDeath(eventGUID)
    local a = state.active
    if not a or not a.locked or a.result then return end

    -- Outside restricted encounters the GUID is readable and remains the most exact route.
    if eventGUID and CanRead(eventGUID) then
        local member = a.snapshot[eventGUID]
        if member then return eventGUID, member.name end
    end

    -- In Forever encounters UNIT_DIED commonly carries a secret GUID. Never compare,
    -- concatenate or use that value as a key; inspect only our fixed friendly unit tokens.
    a.seenDead = a.seenDead or {}
    for _, member in ipairs(a.units or {}) do
        local ok, dead = pcall(UnitIsDeadOrGhost, member.unit)
        if ok and CanRead(dead) and dead and not a.seenDead[member.unit] then
            a.seenDead[member.unit] = true
            return member.guid, member.name
        end
    end
end


local function ResolveGroupDeath(eventGUID)
    local guid, name = FindGroupDeath(eventGUID)
    if guid then Resolve(guid, name, false) end
end

local OrderedBets

local function FindBetKey(a, bettor)
    for key, bet in pairs(a and a.bets or {}) do
        if SamePlayer(bet.bettor or key, bettor) then return key, bet end
    end
end

local function PreferredPlayerName(player)
    local member = FindRosterByName(player)
    return member and member.name or player
end

local function RemoveDuplicateBets(a, bettor, keepKey)
    for key, bet in pairs(a and a.bets or {}) do
        if key ~= keepKey and SamePlayer(bet.bettor or key, bettor) then a.bets[key] = nil end
    end
end

local function AddBet(bettor, targetGUID, targetName, stake)
    local a = state.active
    if not a or a.locked or a.result or a.cancelVote then return false end
    stake = floor(tonumber(stake) or 0)
    if stake < a.minimum or stake <= 0 then return false end
    if a.mode == "LAST_MAN_STANDING" and stake ~= a.minimum then return false end
    local oldKey, previous = FindBetKey(a, bettor)
    if previous and stake < previous.stake then return false end
    local betKey = oldKey or PreferredPlayerName(bettor)
    RemoveDuplicateBets(a, bettor, betKey)
    if a.mode == "ITEM_DROP" then
        local itemID = tonumber(tostring(targetGUID):match("ITEM:(%d+)") or targetGUID)
        if not itemID then return false end
        for _, bet in pairs(a.bets) do if bet.targetItemID == itemID and not SamePlayer(bet.bettor, bettor) then return false end end
        a.bets[betKey] = { bettor = PreferredPlayerName(bettor), targetGUID = "ITEM:" .. itemID, targetItemID = itemID, targetName = targetName, stake = stake }
        return true
    end
    if IsEncounterBetMode(a.mode) then
        local option = EncounterOption(a.mode, targetGUID)
        if not option then return false end
        a.bets[betKey] = { bettor = PreferredPlayerName(bettor), targetGUID = "OPT:" .. option.key, targetName = option.label, stake = stake }
        return true
    end
    if not ValidPrediction(a, targetGUID) then return false end
    a.bets[betKey] = { bettor = PreferredPlayerName(bettor), targetGUID = targetGUID, targetName = targetName, stake = stake }
    return true
end

local function AddSeriesBet(bettor, picks, stake)
    local a = state.active
    if not a or not IsBossSeries(a.mode) or a.result or a.cancelVote then return false end
    stake = floor(tonumber(stake) or 0)
    if stake < a.minimum or stake <= 0 or not picks then return false end
    local resolvedPicks = {}
    for i = 1, #a.bosses do
        local pick = picks[i]
        if a.mode=="BOSS_DAMAGE_SERIES" and not pick then pick={guid="RANK_PENDING",name="Noch kein Tipp"} end
        if not pick then return false end
        local guid, member = pick.guid, a.snapshot[pick.guid]
        if a.mode == "BOSS_DAMAGE_SERIES" and (guid=="RANK_PENDING" or GambleDamageBets:Valid(a, guid)) then member = {name=guid=="RANK_PENDING" and "Noch kein Tipp" or "Top 3"} end
        if not member and pick.name then
            for snapshotGUID, snapshotMember in pairs(a.snapshot) do
                if SamePlayer(snapshotMember.name, pick.name) then guid, member = snapshotGUID, snapshotMember; break end
            end
        end
        if not member then return false end
        resolvedPicks[i] = { guid = guid, name = member.name or pick.name }
    end
    local oldKey, previous = FindBetKey(a, bettor)
    if previous and stake < previous.stake then return false end
    if previous and a.locked then
        for i = 1, #a.bosses do
            if (a.seriesResults[i] or a.currentSeriesBoss == i) and previous.picks[i].guid ~= resolvedPicks[i].guid then return false end
        end
    end
    local storedPicks = {}
    for i = 1, #a.bosses do storedPicks[i] = resolvedPicks[i] end
    local betKey = oldKey or PreferredPlayerName(bettor)
    RemoveDuplicateBets(a, bettor, betKey)
    a.bets[betKey] = { bettor = PreferredPlayerName(bettor), picks = storedPicks, stake = stake }
    return true
end

local function OwnBet(a)
    if not a then return nil end
    for _, bet in pairs(a.bets or {}) do if SamePlayer(bet.bettor, PlayerName()) then return bet end end
end

local function SeriesPicksComplete(picks, bosses)
    if not picks or not bosses or #bosses == 0 then return false end
    for i = 1, #bosses do if not picks[i] then return false end end
    return true
end

local function SetPaymentStatus(a, player, status)
    if not a or not player then return end
    a.paymentStatus = a.paymentStatus or {}
    local preferred = (FindRosterByName(player) and FindRosterByName(player).name) or player
    for existing in pairs(a.paymentStatus) do
        if SamePlayer(existing, player) and existing ~= preferred then a.paymentStatus[existing] = nil end
    end
    a.paymentStatus[preferred] = status
    if status ~= "PAID" then
        for existing in pairs(a.readyStatus or {}) do if SamePlayer(existing, player) then a.readyStatus[existing] = nil end end
    end
end

local function ClearPaymentStatus(a, player)
    if not a or not a.paymentStatus then return end
    for existing in pairs(a.readyStatus or {}) do if SamePlayer(existing, player) then a.readyStatus[existing] = nil end end
    for existing in pairs(a.paymentStatus) do if SamePlayer(existing, player) then a.paymentStatus[existing] = nil end end
end

local function PendingPaymentNames(a)
    local pending, seen = {}, {}
    for player, status in pairs(a and a.paymentStatus or {}) do
        local key = CanonicalPlayerName(player)
        if status == "PENDING" and not seen[key] then pending[#pending + 1] = player; seen[key] = true end
    end
    table.sort(pending)
    return pending
end

local function AllPaymentsReceived(a)
    return #PendingPaymentNames(a) == 0
end

local function SeriesComplete(a)
    for i = 1, #a.bosses do if not GambleData.IsRareBoss(a.bosses[i]) and not a.seriesResults[i] then return false end end
    return #a.bosses > 0
end

local function FinalizeSeries()
    local a = state.active
    if a and a.mode == "BOSS_DAMAGE_SERIES" then
        GambleDamageBets:PromptFinish(Gamble,a)
        return
    end
    if not a or a.mode ~= "BOSS_SERIES" or a.result then return end
    local bets, total, scores = OrderedBets(), 0, {}
    for _, bet in ipairs(bets) do total = total + bet.stake; scores[bet.bettor] = 0 end
    local missedBosses, countedBosses = 0, 0
    for i = 1, #a.bosses do
        local result, anyCorrect = a.seriesResults[i], false
        if GambleData.SeriesBossCounts(a.bosses[i], result) then
        countedBosses = countedBosses + 1
        if result and result.guid then
            for _, bet in ipairs(bets) do
                if bet.picks[i] and bet.picks[i].guid == result.guid then scores[bet.bettor] = scores[bet.bettor] + 1; anyCorrect = true end
            end
        end
        if not anyCorrect then missedBosses = missedBosses + 1 end
        end
    end
    local bankCut = countedBosses > 0 and floor((total / countedBosses) * 0.20 * missedBosses) or 0
    local payoutPool = max(0, total - bankCut)
    local best = 0
    for _, score in pairs(scores) do if score > best then best = score end end
    local winners, winningStake = {}, 0
    for _, bet in ipairs(bets) do if scores[bet.bettor] == best then winners[#winners + 1] = bet; winningStake = winningStake + bet.stake end end
    local payouts, assigned = {}, 0
    for i, bet in ipairs(winners) do
        local amount = i == #winners and (payoutPool - assigned) or floor(payoutPool * bet.stake / max(1, winningStake))
        payouts[bet.bettor] = amount; assigned = assigned + amount
    end
    a.seriesScores, a.seriesPayouts, a.bankCut = scores, payouts, bankCut
    a.result = { series = true, name = "Boss series complete" }; a.locked = true
    wipe(state.payments)
    if SamePlayer(a.host, PlayerName()) then
        for _, bet in ipairs(winners) do
            if not SamePlayer(bet.bettor, a.host) and payouts[bet.bettor] > 0 then state.payments[#state.payments + 1] = { name = bet.bettor, amount = payouts[bet.bettor], reason = "Series winnings", wagerID = a.id } end
        end
        Send("SERIES_RESULT", a.id, bankCut, best)
        for bettor, amount in pairs(payouts) do Send("SERIES_PAYOUT", a.id, bettor, amount, scores[bettor]) end
    end
    Print("Boss series complete. Bank share: " .. Money(bankCut) .. ".")
    Gamble:Refresh()
end

OrderedBets = function()
    local bets = {}
    if state.active then
        for _, bet in pairs(state.active.bets) do bets[#bets + 1] = bet end
    end
    table.sort(bets, function(a, b) return a.bettor < b.bettor end)
    return bets
end

local function ComputeResult(deadGUID, wager)
    local a = wager or state.active
    local winners, losers, total, winningStake = {}, {}, 0, 0
    local bets = {}
    for _,bet in pairs(a and a.bets or {}) do bets[#bets+1]=bet end
    table.sort(bets,function(left,right) return left.bettor<right.bettor end)
    if a and a.result and a.result.rankedDamage then
        for _,bet in ipairs(bets) do
            total=total+bet.stake
            if (a.rankPayouts or {})[bet.bettor] then winners[#winners+1]=bet; winningStake=winningStake+bet.stake
            else losers[#losers+1]=bet end
        end
        return winners,losers,a.rankPayouts or {},total,winningStake
    end
    for _, bet in ipairs(bets) do
        total = total + bet.stake
        if bet.targetGUID == deadGUID or (a.mode == "DAMAGE_RACE" and a.damageWinners and a.damageWinners[bet.targetGUID]) then
            winners[#winners + 1] = bet
            winningStake = winningStake + bet.stake
        else
            losers[#losers + 1] = bet
        end
    end
    local payouts = {}
    if winningStake > 0 then
        local assigned = 0
        for i, bet in ipairs(winners) do
            local amount
            if i == #winners then amount = total - assigned
            else amount = floor(total * bet.stake / winningStake); assigned = assigned + amount end
            payouts[bet.bettor] = amount
        end
    end
    return winners, losers, payouts, total, winningStake
end

local function BuildPayments(deadGUID, isVoid)
    wipe(state.payments)
    local a = state.active
    local me = PlayerName()
    if not SamePlayer(me, a.host) then return end
    if isVoid then
        for _, bet in ipairs(OrderedBets()) do
            if not SamePlayer(bet.bettor, a.host) then state.payments[#state.payments + 1] = { name = bet.bettor, amount = bet.stake, reason = "Refund", wagerID = a.id } end
        end
        return
    end
    local winners, _, payouts, _, winningStake = ComputeResult(deadGUID)
    if winningStake == 0 then
        for _, bet in ipairs(OrderedBets()) do
            if not SamePlayer(bet.bettor, a.host) then state.payments[#state.payments + 1] = { name = bet.bettor, amount = bet.stake, reason = "Refund", wagerID = a.id } end
        end
        return
    end
    for _, winner in ipairs(winners) do
        if not SamePlayer(winner.bettor, a.host) and payouts[winner.bettor] and payouts[winner.bettor] > 0 then
            state.payments[#state.payments + 1] = { name = winner.bettor, amount = payouts[winner.bettor], reason = "Winnings", wagerID = a.id }
        end
    end
end

local function BuildEqualOptionPayments(winningKey, refundAll)
    local a = state.active
    if not a then return end
    for index = #state.payments, 1, -1 do
        if state.payments[index].wagerID == a.id then table.remove(state.payments, index) end
    end
    local isHost = SamePlayer(PlayerName(), a.host)
    local bets, winners, total = OrderedBets(), {}, 0
    for _, bet in ipairs(bets) do
        total = total + (tonumber(bet.stake) or 0)
        if winningKey and bet.targetGUID == "OPT:" .. winningKey then winners[#winners + 1] = bet end
    end
    a.encounterPayouts = {}
    if refundAll or #winners == 0 then
        a.result.noWinningBet = not refundAll and #winners == 0 or nil
        for _, bet in ipairs(bets) do
            a.encounterPayouts[bet.bettor] = bet.stake
            if isHost and not SamePlayer(bet.bettor, a.host) then state.payments[#state.payments + 1] = { name = bet.bettor, amount = bet.stake, reason = "Refund", wagerID = a.id } end
        end
        return
    end
    table.sort(winners, function(left, right) return CanonicalPlayerName(left.bettor) < CanonicalPlayerName(right.bettor) end)
    local base, remainder = floor(total / #winners), total % #winners
    for index, bet in ipairs(winners) do
        local amount = base + (index <= remainder and 1 or 0)
        a.encounterPayouts[bet.bettor] = amount
        if isHost and not SamePlayer(bet.bettor, a.host) and amount > 0 then state.payments[#state.payments + 1] = { name = bet.bettor, amount = amount, reason = "Winnings", wagerID = a.id } end
    end
end

local function FinalizeEncounterBet(a, winningKey, outcome, value, winnerName, elapsed, fromHost, ambiguous, refundAll)
    if not a or a.result then return end
    local selected = state.active; state.active = a
    a.locked = true
    a.result = {
        encounterBet = true,
        guid = winningKey and ("OPT:" .. winningKey) or nil,
        optionKey = winningKey,
        outcome = outcome,
        value = tonumber(value),
        winnerName = winnerName ~= "" and winnerName or nil,
        elapsed = tonumber(elapsed),
        ambiguous = ambiguous and true or false,
        void = (ambiguous or refundAll) and true or false,
        name = ambiguous and "AMBIGUOUS – host review required" or outcome,
    }
    if not ambiguous then BuildEqualOptionPayments(winningKey, refundAll) end
    if not fromHost and SamePlayer(a.host, PlayerName()) then
        Send("EBET_RESULT", a.id, winningKey or "", outcome or "", value or "", winnerName or "", elapsed or "", ambiguous and 1 or 0, refundAll and 1 or 0)
    end
    if ambiguous then Print("AMBIGUOUS – result could not be reliably determined. No automatic payout.")
    elseif refundAll then Print((outcome or "Bet void") .. " – all stakes will be refunded.")
    elseif a.result.noWinningBet then Print("NO WINNING BET – all stakes will be refunded.")
    else Print("Bet finished: " .. tostring(outcome or winningKey) .. ".") end
    if ambiguous and SamePlayer(a.host, PlayerName()) then state.selectedGUID, state.selectedName = nil, nil end
    state.active = selected == a and a or selected
    Gamble:Refresh()
end

local function LMSWinnerMap(a)
    local map = {}
    for _, guid in ipairs(a and a.lmsWinnerGUIDs or {}) do map[guid] = true end
    return map
end

local function FinalizeLMS(winnerGUIDs, ambiguous, fromHost)
    local a = state.active
    if not a or a.mode ~= "LAST_MAN_STANDING" or a.result then return end
    if ambiguous then
        a.lmsAmbiguous = true
        a.lmsState = "AMBIGUOUS"
        a.locked = true
        Print("Last Man Standing is ambiguous. The host must review the result.")
        DebugLMS("RESULT AMBIGUOUS")
        if not fromHost and SamePlayer(a.host, PlayerName()) then Send("LMS_AMBIGUOUS", a.id) end
        Gamble:Refresh()
        return
    end
    a.lmsAmbiguous = nil
    a.lmsWinnerGUIDs = winnerGUIDs or {}
    local winnerMap, winnerNames = LMSWinnerMap(a), {}
    for _, guid in ipairs(a.lmsWinnerGUIDs) do winnerNames[#winnerNames + 1] = a.snapshot[guid] and a.snapshot[guid].name or guid end
    local bets, total, winningBets = OrderedBets(), 0, {}
    for _, bet in ipairs(bets) do
        total = total + bet.stake
        if winnerMap[bet.targetGUID] then winningBets[#winningBets + 1] = bet end
    end
    a.lmsPayouts = {}
    wipe(state.payments)
    if #winningBets == 0 then
        a.result = { lms = true, noWinningBet = true, name = "NO WINNING BET", void = true }
        BuildPayments(nil, true)
    else
        local base, remainder = floor(total / #winningBets), total % #winningBets
        table.sort(winningBets, function(left, right) return tostring(left.bettor) < tostring(right.bettor) end)
        for index, bet in ipairs(winningBets) do
            local amount = base + (index <= remainder and 1 or 0)
            a.lmsPayouts[bet.bettor] = amount
            if SamePlayer(a.host, PlayerName()) and not SamePlayer(bet.bettor, a.host) and amount > 0 then
                state.payments[#state.payments + 1] = { name = bet.bettor, amount = amount, reason = "LMS winnings", wagerID = a.id }
            end
        end
        local firstGUID = a.lmsWinnerGUIDs[1]
        a.result = { lms = true, guid = firstGUID, name = #winnerNames > 1 and ("TIE: " .. table.concat(winnerNames, ", ")) or (winnerNames[1] or "Last Man Standing") }
    end
    a.lmsState = #state.payments > 0 and "PAYOUT_PENDING" or "RESULT"
    a.locked = true
    if not fromHost and SamePlayer(a.host, PlayerName()) then
        Send("LMS_RESULT", a.id, table.concat(a.lmsWinnerGUIDs, ","), a.result.noWinningBet and 1 or 0)
    end
    Print(a.result.noWinningBet and "NO WINNING BET – all stakes will be refunded." or ("LAST MAN STANDING: " .. a.result.name))
    DebugLMS("RESULT " .. tostring(a.result.name))
    Gamble:Refresh()
end

local function RecordLMSDeath(eventGUID, eventTimestamp)
    local a = state.active
    if not a or a.mode ~= "LAST_MAN_STANDING" or not a.locked or a.result then return end
    local guid, name = FindGroupDeath(eventGUID)
    if not guid then return end
    a.lmsFirstDeaths = a.lmsFirstDeaths or {}
    if a.lmsFirstDeaths[guid] then return end
    local stamp = tonumber(eventTimestamp) or (GetTime and GetTime() or time())
    a.lmsFirstDeaths[guid] = { guid = guid, name = name, stamp = stamp, order = #(a.lmsDeathOrder or {}) + 1 }
    a.lmsDeathOrder = a.lmsDeathOrder or {}
    a.lmsDeathOrder[#a.lmsDeathOrder + 1] = a.lmsFirstDeaths[guid]
    DebugLMS("FIRST_DEATH " .. DisplayName(name))
    if SamePlayer(a.host, PlayerName()) then Send("LMS_DEATH", a.id, guid, name, stamp, #a.lmsDeathOrder) end
    Gamble:Refresh()
end

local function ResolveLMSWipe(fromHost)
    local a = state.active
    if not a or a.mode ~= "LAST_MAN_STANDING" or a.result then return end
    local survivors = {}
    for guid in pairs(a.lmsEligible or a.snapshot or {}) do if not (a.lmsFirstDeaths and a.lmsFirstDeaths[guid]) then survivors[#survivors + 1] = guid end end
    if #survivors == 1 then
        BuildRoster()
        local member = FindRosterByGUID(survivors[1])
        if not member or member.online == false then FinalizeLMS(nil, true, fromHost) else FinalizeLMS({ survivors[1] }, false, fromHost) end
        return
    end
    if #survivors > 1 or #(a.lmsDeathOrder or {}) == 0 then FinalizeLMS(nil, true, fromHost); return end
    local lastStamp = a.lmsDeathOrder[#a.lmsDeathOrder].stamp
    local winners = {}
    for _, death in ipairs(a.lmsDeathOrder) do if math.abs((death.stamp or 0) - (lastStamp or 0)) < 0.001 then winners[#winners + 1] = death.guid end end
    FinalizeLMS(winners, false, fromHost)
end

local function ItemJackpotKey(a)
    return tostring(a.bossEncounterID or a.bossName or "unknown")
end

local function FinalizeItemDrop(winningItemID, fromHost)
    local a = state.active
    if not a or a.mode ~= "ITEM_DROP" or a.result then return end
    local total = 0
    for _, bet in ipairs(OrderedBets()) do total = total + bet.stake end
    GambleDB.itemJackpots = GambleDB.itemJackpots or {}
    local key = ItemJackpotKey(a)
    local carried = floor(tonumber(GambleDB.itemJackpots[key]) or 0)
    a.locked = true; a.bankCut = 0; a.carriedJackpot = carried
    if winningItemID then
        local winningGUID = "ITEM:" .. winningItemID
        local _, _, payouts, _, winningStake = ComputeResult(winningGUID)
        local payoutPool = total + carried
        if winningStake > 0 then
            local assigned = 0; local winners = {}
            for _, bet in ipairs(OrderedBets()) do if bet.targetItemID == winningItemID then winners[#winners + 1] = bet end end
            for i, bet in ipairs(winners) do
                local amount = i == #winners and (payoutPool - assigned) or floor(payoutPool * bet.stake / winningStake)
                payouts[bet.bettor] = amount; assigned = assigned + amount
            end
            GambleDB.itemJackpots[key] = 0
            a.itemPayouts = payouts
            a.result = { guid = winningGUID, item = true, itemID = winningItemID, name = a.droppedNames and a.droppedNames[winningItemID] or ("Item " .. winningItemID) }
            wipe(state.payments)
            if SamePlayer(a.host, PlayerName()) then
                for _, bet in ipairs(winners) do if not SamePlayer(bet.bettor, a.host) then state.payments[#state.payments + 1] = { name = bet.bettor, amount = payouts[bet.bettor], reason = "Item-Jackpot", wagerID = a.id } end end
            end
        end
    end
    if not a.result then
        a.bankCut = floor(total * .20)
        local rollover = total - a.bankCut + carried
        GambleDB.itemJackpots[key] = rollover
        a.itemRollover = rollover
        a.result = { item = true, itemMiss = true, name = "None of the predicted items dropped" }
        wipe(state.payments)
    end
    if not fromHost and SamePlayer(a.host, PlayerName()) then
        Send("ITEM_RESULT", a.id, winningItemID or 0, a.bankCut or 0, GambleDB.itemJackpots[key] or 0)
    end
    Print(a.result.itemMiss and ("No match. " .. Money(a.bankCut) .. " retained by the bank; jackpot: " .. Money(a.itemRollover) .. ".") or (a.result.name .. " detected – item bet completed."))
    Gamble:Refresh()
end

local function RecoverCompletedWagers()
    local selected = state.active
    for _, wager in ipairs(state.wagers or {}) do
        if not wager.result and SamePlayer(wager.host, PlayerName()) then
            state.active = wager
            if wager.mode == "ITEM_DROP" and wager.encounterEnded then
                local winner
                for _, bet in pairs(wager.bets or {}) do
                    if wager.droppedItems and wager.droppedItems[bet.targetItemID] then winner = bet.targetItemID; break end
                end
                FinalizeItemDrop(winner, false)
            elseif wager.mode=="BOSS_DAMAGE_SERIES" then
                -- Preserve the host's explicit Finish/Continue decision after reload.
                if wager.rankEndBossKilled then wager.rankFinishPromptPending=true end
            elseif IsBossSeries(wager.mode) then
                local endBossDefeated = false
                for index, boss in ipairs(wager.bosses or {}) do
                    if wager.seriesResults and wager.seriesResults[index] and IsConfiguredEndBoss(wager, boss.encounterID, boss.name) then
                        endBossDefeated = true
                        break
                    end
                end
                if endBossDefeated then
                    for index = 1, #wager.bosses do
                        if not wager.seriesResults[index] then
                            wager.seriesResults[index] = { nobody = true, name = "Not scored" }
                            wager.completedBosses = (wager.completedBosses or 0) + 1
                            Send("SERIES_BOSS", wager.id, index, "", "Not scored")
                        end
                    end
                    FinalizeSeries()
                end
            end
        end
    end
    state.active = selected
end

Resolve = function(deadGUID, deadName, fromHost)
    local a = state.active
    if not a or a.result then return end
    if not a.snapshot[deadGUID] then return end
    a.locked = true
    a.result = { guid = deadGUID, name = deadName or a.snapshot[deadGUID].name }
    BuildPayments(deadGUID, false)
    if not fromHost and a.host == PlayerName() then Send("RESULT", a.id, deadGUID, a.result.name) end
    Print(DisplayName(a.result.name) .. " died first. The bet is complete.")
    Gamble:Refresh()
end

local function VoidBoss(reason, fromHost)
    local a = state.active
    if not a or a.result then return end
    a.locked = true; a.result = { void = true, name = reason or "Boss defeated; nobody died" }
    BuildPayments(nil, true)
    if not fromHost and a.host == PlayerName() then Send("VOID", a.id, a.result.name) end
    Print(a.result.name .. ". Stakes will be refunded.")
    Gamble:Refresh()
end

local function FinalizeCancel(fromHost)
    local a = state.active
    if not a or a.result then return end
    local ownRefund = not SamePlayer(a.host, PlayerName()) and OwnBet(a) or nil
    local hasRefundRecipient = false
    for _, bet in pairs(a.bets or {}) do
        if not SamePlayer(bet.bettor, a.host) then hasRefundRecipient = true; break end
    end
    a.cancelVote = nil; a.locked = true
    a.result = { void = true, cancelled = true, name = "Bet cancelled" }
    if state.pendingJoin and state.pendingJoin.id == a.id then state.pendingJoin = nil end
    for sender, request in pairs(state.escrowRequests) do if request.id == a.id then state.escrowRequests[sender] = nil end end
    if state.tradeContext and state.tradeContext.request and state.tradeContext.request.id == a.id then state.tradeContext = nil end
    if Gamble.escrowFrame then Gamble.escrowFrame:Hide() end
    local otherPayments = {}
    for _, payment in ipairs(state.payments) do
        if payment.wagerID ~= a.id then otherPayments[#otherPayments + 1] = payment end
    end
    BuildPayments(nil, true)
    for _, payment in ipairs(otherPayments) do state.payments[#state.payments + 1] = payment end
    if not fromHost and SamePlayer(a.host, PlayerName()) then Send("CANCEL_FINAL", a.id) end
    Gamble.uiTab = "NEW"; Gamble.detailWagerID = nil
    state.active = nil
    state.selectedType = nil; state.selectedBoss = nil; state.selectedGUID = nil; state.selectedName = nil
    wipe(state.seriesPicks); state.seriesStep = 1; wipe(state.lootItems)
    if not hasRefundRecipient then
        if GambleBankSecurity then GambleBankSecurity:ResolveWager(a.id, {}, 0, "CANCELLED") end
        -- Keep a hidden cancellation record so reconnecting peers can remove stale lobbies.
        SaveSession()
        Print("The bet was cancelled without participants.")
        Gamble:Refresh()
        return
    end
    Print("The bet was cancelled. Paid stakes will be refunded.")
    SaveSession()
    Gamble:Refresh()
    if ownRefund then Gamble:ShowRefundAnnouncement(a.host, ownRefund.stake, a.id) end
end

local function NewActive(id, host, minimum, targetGUID, targetName, hostStake, mode, bossName, context, bossEncounterID)
    BuildRoster()
    local snapshot = {}
    local units = {}
    for _, member in ipairs(state.roster) do
        snapshot[member.guid] = { name = member.name, class = member.class, role = member.role, level = member.level, online = member.online }
        units[#units + 1] = { unit = member.unit, guid = member.guid, name = member.name }
    end
    local seriesBosses = {}
    if IsBossSeries(mode) then for _, boss in ipairs(state.bosses) do seriesBosses[#seriesBosses + 1] = { name = boss.name, encounterID = boss.encounterID, aliases = boss.aliases, npcID=boss.npcID, rare=boss.rare } end end
    local wagerLoot = {}
    if mode == "ITEM_DROP" then for _, item in ipairs(state.lootItems) do wagerLoot[#wagerLoot + 1] = { id = item.id, name = item.name, link = item.link, icon = item.icon } end end
    local instanceName = BettingCreationInstanceName()
    state.active = { id = id, host = host, minimum = minimum, bets = {}, snapshot = snapshot, units = units, seenDead = {}, locked = false, result = nil, meter = HasNativeMeterSession(), mode = mode or "NEXT_PULL", bossName = bossName or "", bossEncounterID = tonumber(bossEncounterID), context = context or "", instanceName = instanceName, bosses = seriesBosses, lootItems = wagerLoot, seriesResults = {}, paymentStatus = {}, createdAt = tonumber(tostring(id or ""):match("^(%d+)")) or time() }
    SetPaymentStatus(state.active, host, "PAID")
    state.active.awaitingStart = true
    state.wagers[#state.wagers + 1] = state.active
    SnapshotDeadState()
    if not IsBossSeries(mode) and targetGUID and targetGUID ~= "" then AddBet(host, targetGUID, targetName, hostStake) end
end

local function AnnounceWager(a)
    if a and a.result and a.result.cancelled and SamePlayer(a.host, PlayerName()) then Send("CANCEL_FINAL", a.id); return end
    if not a or a.result or not SamePlayer(a.host, PlayerName()) then return end
    local hostBet
    for _, bet in pairs(a.bets or {}) do if SamePlayer(bet.bettor, a.host) then hostBet = bet; break end end
    Send("OPEN", VERSION, a.id, a.mode, a.bossName or "", a.bossEncounterID or "", a.context or "", hostBet and hostBet.targetGUID or "", hostBet and hostBet.targetName or "", hostBet and hostBet.stake or a.minimum)
    if a.mode == "BOSS_DAMAGE_SERIES" then Gamble:SendRankBossList(a) end
    if IsBossSeries(a.mode) and hostBet and hostBet.picks then
        Send("SERIES_BET_BEGIN", a.id, a.host, hostBet.stake, #hostBet.picks)
        for index, pick in ipairs(hostBet.picks) do Send("SERIES_BET_PICK", a.id, a.host, index, pick.guid, pick.name) end
    end
end

local function ClassColor(class)
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if not color then return 1, 1, 1 end
    return color.r, color.g, color.b
end

local function ClassColoredName(guid, name)
    local member = FindRosterByGUID(guid)
    local class = member and member.class
    if not class and state.active and state.active.snapshot and state.active.snapshot[guid] then
        class = state.active.snapshot[guid].class
    end
    local r, g, b = ClassColor(class)
    return string.format("|cff%02x%02x%02x%s|r", floor(r * 255 + .5), floor(g * 255 + .5), floor(b * 255 + .5), DisplayName(name))
end

local function MakeButton(parent, width, height, text)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, height); b:SetText(text)
    return b
end

local function MakeMoneyBox(parent, iconPath, x)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(54, 24); box:SetPoint("TOPLEFT", x, -380); box:SetAutoFocus(false); box:SetNumeric(true); box:SetMaxLetters(6); box:SetText("0")
    local icon = box:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16); icon:SetPoint("LEFT", box, "RIGHT", 4, 0); icon:SetTexture(iconPath)
    return box
end

local function PositionMinimapButton(button)
    if not button or not Minimap then return end
    local angle = (GambleDB and GambleDB.minimapAngle) or DEFAULT_MINIMAP_ANGLE
    local radius = (GambleDB and GambleDB.minimapRadius) or DEFAULT_MINIMAP_RADIUS
    local radians = math.rad(angle)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(radians) * radius, math.sin(radians) * radius)
end

function Gamble:CreateMinimapButton()
    if self.minimapButton or not Minimap then return end
    local button = CreateFrame("Button", "GambleMinimapButton", Minimap)
    button:SetSize(32, 32); button:SetFrameStrata("MEDIUM"); button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(22, 22); background:SetPoint("CENTER"); background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20); icon:SetPoint("CENTER"); icon:SetTexture("Interface\\Icons\\achievement_guildperk_ladyluck"); icon:SetTexCoord(.08, .92, .08, .92)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54); border:SetPoint("TOPLEFT", 0, 0); border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    button:SetScript("OnClick", function()
        if Gamble.frame:IsShown() then Gamble.frame:Hide() else Gamble.frame:Show(); Gamble:Refresh() end
    end)
    button:SetScript("OnEnter", function(selfButton)
        GameTooltip:SetOwner(selfButton, "ANCHOR_LEFT")
        GameTooltip:SetText("Gamble - Betting Office", 1, .82, 0)
        GameTooltip:AddLine("Left-click: Open or close the betting office", 1, 1, 1)
        GameTooltip:AddLine("Drag: Change position", .75, .75, .75)
        GameTooltip:AddLine("/gamble minimap 94 225: set exact position", .75, .75, .75)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnDragStart", function(selfButton)
        selfButton:SetScript("OnUpdate", function(dragButton)
            local mapX, mapY = Minimap:GetCenter()
            local cursorX, cursorY = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cursorX, cursorY = cursorX / scale, cursorY / scale
            local deltaX, deltaY = cursorX - mapX, cursorY - mapY
            local angle
            if deltaX == 0 then angle = deltaY >= 0 and 90 or -90
            else
                angle = math.deg(math.atan(deltaY / deltaX))
                if deltaX < 0 then angle = angle + 180 end
            end
            GambleDB.minimapAngle = angle
            PositionMinimapButton(dragButton)
        end)
    end)
    button:SetScript("OnDragStop", function(selfButton) selfButton:SetScript("OnUpdate", nil) end)
    self.minimapButton = button
    PositionMinimapButton(button)
end

function Gamble:CloseAuxiliaryWindows()
    local combat = InCombatLockdown and InCombatLockdown()
    self.pendingWindowClose = nil
    for _, key in ipairs({ "seriesPopup", "detailsPopup", "settingsFrame", "inviteFrame", "winnerFrame", "escrowFrame" }) do
        local window = self[key]
        if window then
            if combat and window:IsProtected() then self.pendingWindowClose = true
            else window:Hide() end
        end
    end
    if GambleBankSecurity and GambleBankSecurity.frame then GambleBankSecurity.frame:Hide() end
    if GambleTestMode and GambleTestMode.frame then GambleTestMode.frame:Hide() end
    if GambleRPS then GambleRPS:HideEmbedded() end
    if GambleDON and GambleDON.CloseWindows then
        if not GambleDON:CloseWindows() then self.pendingWindowClose = true end
    end
end

function Gamble:GetDamageRaceSelection() return state.active end
function Gamble:GetDamageRaceWagers() return state.wagers end
function Gamble:GetOwnRankBet(a) return OwnBet(a) end
function Gamble:GetRankMember(a,guid)
    for _,member in ipairs(state.roster) do if member.guid==guid then return member end end
    return a.snapshot[guid]
end
function Gamble:IsRankHost(a) return SamePlayer(a.host,PlayerName()) end
function Gamble:SendRankMessage(...) Send(...) end
function Gamble:SaveRankState() SaveSession() end
function Gamble:IsRankEndBoss(a,id,name) return IsConfiguredEndBoss(a,id,name) end
function Gamble:BroadcastBossRankTarget(a,index)
    if not SamePlayer(a.host,PlayerName()) or GambleDamageBets:BossPickLocked(a,index) or not a.bosses[index] then return end
    GambleDamageBets:OpenBossPick(self,a,index)
    GambleDamageBets.targetBroadcast=GambleDamageBets.targetBroadcast or {}
    local key=a.id..":"..index; local last=GambleDamageBets.targetBroadcast[key]
    if last and GetTime()-last<15 then return end
    GambleDamageBets.targetBroadcast[key]=GetTime()
    Send("RANK_TARGET",a.id,index)
end
function Gamble:ApplyBossRankPick(a,bettor,index,token)
    if not a or a.mode~="BOSS_DAMAGE_SERIES" or not a.bosses[index] or GambleDamageBets:BossPickLocked(a,index) or not GambleDamageBets:Valid(a,token) then return false end
    local _,bet=FindBetKey(a,bettor); if not bet or not bet.picks then return false end
    bet.picks[index]={guid=token,name="Top 3"}
    Send("RANK_PICK_CONFIRMED",a.id,bet.bettor,index,token)
    if state.active==a and SamePlayer(bettor,PlayerName()) then state.seriesPicks[index]=bet.picks[index] end
    SaveSession(); self:Refresh(); return true
end
function Gamble:SubmitBossRankPick(a,index,token)
    if SamePlayer(a.host,PlayerName()) then return self:ApplyBossRankPick(a,PlayerName(),index,token)
    else Send("RANK_PICK_REQUEST",a.id,index,token) end
end
function Gamble:SendRankBossList(a)
    Send("RANK_LIST_BEGIN",a.id,#a.bosses)
    for i,boss in ipairs(a.bosses) do Send("RANK_LIST_ROW",a.id,i,boss.name,boss.encounterID or "",GambleData.IsRareBoss(boss) and 1 or 0) end
    Send("RANK_LIST_END",a.id)
end
function Gamble:RecordBossDamage(a,index,ranking,failureReason)
    a.rankPendingEncounter=nil
    a.currentSeriesBoss=nil
    a.rankResults=a.rankResults or {}; if a.rankResults[index] then return end
    a.rankResults[index]=ranking; a.seriesResults[index]={name=failureReason and "Not scored" or "Scored",nobody=true}
    if failureReason then
        a.rankMeasurementFailed=failureReason
        Print("Boss damage detail: "..failureReason)
        Print("Boss damage could not be evaluated: "..a.bosses[index].name..". Series continues; final settlement will refund stakes to avoid an incorrect winner.")
    end
    if GambleDamageBets.bossPick and GambleDamageBets.bossPick.wager==a and GambleDamageBets.bossPick.index==index and GambleDamageBets.bossPickFrame then GambleDamageBets.bossPickFrame:Hide() end
    a.completedBosses=(a.completedBosses or 0)+1
    self:SendDamageRanking(a,index,ranking,failureReason)
    local boss=a.bosses[index]
    if boss and IsConfiguredEndBoss(a,boss.encounterID,boss.name) then a.rankEndBossKilled=true end
    if a.rankEndBossKilled then GambleDamageBets:PromptFinish(self,a) end
    SaveSession(); self:Refresh()
end
function Gamble:SendDamageRanking(a,index,ranking,failureReason)
    Send("RANK_BEGIN",a.id,index)
    for place=1,3 do for guid in pairs(ranking[place] or {}) do Send("RANK_POS",a.id,index,place,guid) end end
    Send("RANK_BOSS",a.id,index,failureReason or "")
end
function Gamble:FinishRankDamage(a,invalid,reason,fromHost)
    if not a or a.result then return end
    if not fromHost and a.mode=="BOSS_DAMAGE_SERIES" and a.rankMeasurementFailed then
        invalid=true; reason=a.rankMeasurementFailed
    end
    GambleDamageBets:DismissFinish(a)
    if GambleDamageBets.bossPick and GambleDamageBets.bossPick.wager==a and GambleDamageBets.bossPickFrame then GambleDamageBets.bossPickFrame:Hide() end
    if not fromHost then
        a.rankScores,a.rankPayouts,a.rankBest=GambleDamageBets:Score(a)
        if invalid then a.rankPayouts={}; a.rankBest=0 end
    end
    local refund=invalid or (a.rankBest or 0)==0
    a.locked=true
    a.result={rankedDamage=true,damage=true,void=refund,
        name=refund and (reason or "Nobody predicted a correct place — all stakes will be refunded.") or ("Top-3 result — best score: "..a.rankBest)}
    a.seriesScores,a.seriesPayouts=a.rankScores,a.rankPayouts
    local selected=state.active; state.active=a
    local other={}; for _,payment in ipairs(state.payments) do if payment.wagerID~=a.id then other[#other+1]=payment end end
    BuildPayments(nil,refund); for _,payment in ipairs(other) do state.payments[#state.payments+1]=payment end
    if not fromHost and SamePlayer(a.host,PlayerName()) then
        for bettor,score in pairs(a.rankScores or {}) do Send("RANK_SCORE",a.id,bettor,score,(a.rankPayouts or {})[bettor] or 0) end
        Send("RANK_END",a.id,invalid and 1 or 0,a.rankBest or 0,reason or "")
    end
    if refund and (SamePlayer(a.host,PlayerName()) or OwnBet(a)) then
        self.damageResultNotice={id=a.id,headline=invalid and "Damage Race cancelled" or "Nobody predicted correctly",detail=a.result.name,topDamage=""}
    elseif not refund and not SamePlayer(a.host,PlayerName()) and OwnBet(a) then
        local names,amounts={},{}
        for name,amount in pairs(a.rankPayouts or {}) do
            if amount>0 then
                names[#names+1]=DisplayName(name)
                amounts[#amounts+1]=DisplayName(name)..": "..Money(amount)
            end
        end
        table.sort(names); table.sort(amounts)
        self.damageResultNotice={id=a.id,winner=true,headline="Winner — "..(a.rankBest or 0).." points",
            detail=table.concat(names,", "),topDamage=table.concat(amounts,"\n")}
    end
    Print(a.result.name); state.active=selected; SaveSession(); self:Refresh()
end
function Gamble:FinishDamageRace(a, winners, amount, invalid, fromHost, reason)
    if not a or a.mode ~= "DAMAGE_RACE" or a.result then return end
    local selected = state.active; state.active = a
    a.damageWinners = {}
    local names = {}
    if not invalid then
        for _, guid in ipairs(winners or {}) do
            if a.snapshot[guid] then a.damageWinners[guid] = true; names[#names + 1] = DisplayName(a.snapshot[guid].name) end
        end
    end
    local winningStake = 0
    for _, bet in pairs(a.bets) do if a.damageWinners[bet.targetGUID] then winningStake = winningStake + bet.stake end end
    local refund = invalid or (tonumber(amount) or 0) <= 0 or winningStake == 0
    local refundReason = invalid and (reason or "Damage data was protected, unavailable or lost.") or ((tonumber(amount) or 0) <= 0 and "No damage was recorded." or "Nobody predicted the top damage player.")
    a.locked = true
    a.result = { damage = true, guid = winners and winners[1], void = refund,
        name = refund and ("Damage Race void — stakes refunded. " .. refundReason) or (table.concat(names, ", ") .. " — " .. tostring(amount) .. " damage") }
    if refund and (SamePlayer(a.host, PlayerName()) or OwnBet(a)) then
        self.damageResultNotice = {
            id = a.id,
            headline = not invalid and (tonumber(amount) or 0) > 0 and winningStake == 0 and "Nobody predicted correctly" or "Damage Race cancelled",
            detail = refundReason,
            topDamage = not invalid and #names > 0 and ("Top damage: " .. table.concat(names, ", ") .. " — " .. tostring(amount)) or "",
        }
    end
    -- Keep unrelated simultaneous wager payments intact.
    local otherPayments = {}
    for _, payment in ipairs(state.payments) do if payment.wagerID ~= a.id then otherPayments[#otherPayments + 1] = payment end end
    BuildPayments(a.result.guid, refund)
    for _, payment in ipairs(otherPayments) do state.payments[#state.payments + 1] = payment end
    if not fromHost and SamePlayer(a.host, PlayerName()) then
        for _, guid in ipairs(winners or {}) do Send("DMG_WIN", a.id, guid) end
        Send("DMG_RESULT", a.id, amount or 0, invalid and 1 or 0, reason or "", table.concat(winners or {}, ","))
    end
    Print(a.result.name)
    state.active = selected
    SaveSession(); self:Refresh()
end
function Gamble:CanStartDamageRace(a)
    if not a or a.locked or a.result or a.setupPending or #PendingPaymentNames(a)>0 then return false end
    for _,bet in pairs(a.bets or {}) do if not GambleDamageBets:Valid(a,bet.targetGUID) then return false end end
    return GambleReadyCheck and GambleReadyCheck:CountReady(a, SamePlayer) >= 2
end
function Gamble:BossNeedsSeriesPrediction(a,index)
    local boss=a.bosses and a.bosses[index]
    return boss and not boss.defeated and not (a.seriesResults or {})[index] and not (a.rankResults or {})[index] and not IsBossDefeated(a.instanceName,boss.name,boss.encounterID)
end
function Gamble:CanStartBet(a)
    if not a or a.setupPending or a.result or a.cancelVote or #PendingPaymentNames(a)>0 or not GambleReadyCheck then return false end
    local count=0
    for _,bet in pairs(a.bets or {}) do
        if not GambleReadyCheck:IsReady(a,bet.bettor,SamePlayer) then return false end
        if a.mode=="BOSS_SERIES" and not SeriesPicksComplete(bet.picks or {},a.bosses) then return false end
        if a.mode=="DAMAGE_RACE" and not GambleDamageBets:Valid(a,bet.targetGUID) then return false end
        if a.mode=="BOSS_DAMAGE_SERIES" then
            if not GambleDamageBets:SeriesPicksComplete(a,bet.picks) then return false end
        end
        count=count+1
    end
    return count>=2
end
function Gamble:StartReadyBet(a, automatic)
    if not a or not a.awaitingStart or a.setupPending or a.result or a.cancelVote or not SamePlayer(a.host,PlayerName()) then return end
    if automatic and a.mode=="BOSS_DAMAGE_SERIES" then return end
    if automatic and not self:CanStartBet(a) then return end
    if a.mode=="BOSS_DAMAGE_SERIES" and not self:CanStartBet(a) then return end
    if not GambleReadyCheck or GambleReadyCheck:CountReady(a,SamePlayer)<2 then return end
    if a.mode=="BOSS_DAMAGE_SERIES" then
        if GambleDamageRace:InCombat() then
            if not a.rankStartCombatWarning then Print("Start Boss Damage Series outside group combat."); a.rankStartCombatWarning=true end
            return
        end
        a.rankStartCombatWarning=nil
        GambleDamageBets.knownSessions=GambleDamageBets:SessionIDs()
    end
    for key,bet in pairs(a.bets or {}) do
        if not GambleReadyCheck:IsReady(a,bet.bettor,SamePlayer) then
            if GambleBankSecurity then
                local ok=GambleBankSecurity:ExcludeParticipant(a.id,bet.bettor,bet.stake)
                if not ok then Print("Start blocked: refund reservation failed."); return end
            end
            state.payments[#state.payments+1]={name=bet.bettor,amount=bet.stake,reason="Excluded before start – Refund",wagerID=a.id}
            Send("BET_EXCLUDE",a.id,bet.bettor,bet.stake)
            a.bets[key]=nil; SetPaymentStatus(a,bet.bettor,"CANCELLED")
        end
    end
    for name,status in pairs(a.paymentStatus or {}) do if status~="PAID" then a.paymentStatus[name]=nil end end
    if a.mode=="DAMAGE_RACE" then self:StartDamageRace(); return end
    a.awaitingStart=false; Send("BET_START",a.id); SaveSession()
    if a.mode=="BOSS_DAMAGE_SERIES" then GambleDamageBets:ScanBossTargets(self) end
end
function Gamble:StartDamageRace()
    local a = state.active
    if not a or a.mode ~= "DAMAGE_RACE" or a.result or a.locked or a.setupPending or not SamePlayer(a.host, PlayerName()) then return end
    local attemptTime = GetTime()
    if a.damageStartRetryAt and attemptTime < a.damageStartRetryAt then return end
    if #PendingPaymentNames(a) > 0 then Print("Confirm all pending payments first."); return end
    if not self:CanStartDamageRace(a) then Print("At least two paid participants must be ready before starting Damage Race."); return end
    local seconds = a.damageDuration
    if not seconds then
        local minutes = tonumber(tostring(a.context):match("Duration: (%d+) minutes"))
        seconds = minutes and minutes * 60 or tonumber(tostring(a.context):match("Duration: (%d+) seconds"))
    end
    local ok, reason = GambleDamageRace:Start(a, seconds, function(wager, winners, amount, invalid, failureReason, totals)
        wager.rankResults={GambleDamageBets:Ranking(totals)}
        Gamble:SendDamageRanking(wager,1,wager.rankResults[1])
        Gamble:FinishRankDamage(wager,invalid,failureReason)
    end)
    if not ok then
        a.damageStartRetryAt = attemptTime + 5
        if a.damageStartFailure ~= reason then Print(reason); a.damageStartFailure = reason end
        return
    end
    a.damageStartRetryAt, a.damageStartFailure = nil, nil
    a.locked = true
    a.damageEndsAt = (GetServerTime and GetServerTime() or time()) + seconds
    a.awaitingStart = false
    Send("DMG_START", a.id, seconds, a.damageEndsAt)
    SaveSession(); self:Refresh()
end

function Gamble:CreateUI()
    local f = CreateFrame("Frame", "GambleMainFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(520, 600); f:SetPoint("CENTER"); f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing); f:Hide()
    f.TitleText:SetText("Gamble - Betting Office")
    self.frame = f
    f:HookScript("OnHide", function() Gamble:CloseAuxiliaryWindows() end)

    local settingsButton = CreateFrame("Button", nil, f)
    settingsButton:SetSize(24, 24)
    local settingsIcon = settingsButton:CreateTexture(nil, "ARTWORK")
    settingsIcon:SetAllPoints(); settingsIcon:SetAtlas("mechagon-projects", false)
    settingsButton:SetNormalTexture(settingsIcon)
    settingsButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    settingsButton:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT"); GameTooltip:SetText("Gamble Settings"); GameTooltip:Show()
    end)
    settingsButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.settingsButton = settingsButton

    local search = CreateFrame("EditBox", nil, f, "SearchBoxTemplate")
    if search.Instructions then search.Instructions:SetText("Search") end
    search:SetSize(260, 24); search:SetPoint("TOPLEFT", 18, -36); search:SetAutoFocus(false)
    settingsButton:SetPoint("LEFT", search, "RIGHT", 8, 0)
    search:SetScript("OnTextChanged", function(box)
        SearchBoxTemplate_OnTextChanged(box)
        Gamble:RefreshTypeDropdown()
    end)
    self.searchBox = search

    local function MakeBettingTab(text)
        local tab = CreateFrame("Button", nil, f, "BackdropTemplate")
        tab:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        tab:SetNormalFontObject("GameFontHighlight"); tab:SetHighlightFontObject("GameFontNormal")
        tab:SetText(text); tab:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        return tab
    end
    local newTab = MakeBettingTab("New Bet")
    newTab:SetSize(230, 28); newTab:SetPoint("TOPLEFT", 18, -66)
    newTab:SetScript("OnClick", function() Gamble:SelectBettingTab("NEW") end)
    local runningTab = MakeBettingTab("Active Bets")
    runningTab:SetSize(230, 28); runningTab:SetPoint("LEFT", newTab, "RIGHT", 8, 0)
    runningTab:SetScript("OnClick", function() Gamble:SelectBettingTab("RUNNING") end)
    self.newBetTab, self.runningBetsTab = newTab, runningTab

    local activeBanner = CreateFrame("Button", nil, f, "BackdropTemplate")
    activeBanner:SetPoint("TOPLEFT", 18, -100); activeBanner:SetPoint("TOPRIGHT", -18, -100); activeBanner:SetHeight(62)
    activeBanner:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    activeBanner:SetBackdropColor(.12, .09, .01, .96); activeBanner:SetBackdropBorderColor(1, .72, .05, 1)
    activeBanner:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    local bannerTitle = activeBanner:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    bannerTitle:SetPoint("TOPLEFT", 14, -10); bannerTitle:SetTextColor(1, .82, .12)
    local bannerLine1 = activeBanner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bannerLine1:SetPoint("TOPLEFT", 14, -32); bannerLine1:SetPoint("TOPRIGHT", -18, -32); bannerLine1:SetJustifyH("LEFT")
    local bannerLine2 = activeBanner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bannerLine2:SetPoint("TOPLEFT", 14, -47); bannerLine2:SetPoint("TOPRIGHT", -18, -47); bannerLine2:SetJustifyH("LEFT")
    activeBanner:SetScript("OnClick", function() Gamble:SelectBettingTab("RUNNING") end)
    activeBanner:Hide()
    self.activeBanner, self.activeBannerTitle, self.activeBannerLine1, self.activeBannerLine2 = activeBanner, bannerTitle, bannerLine1, bannerLine2

    local dropdown = CreateFrame("Frame", "GambleBetTypeDropdown", f, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", 5, -100); UIDropDownMenu_SetWidth(dropdown, 330)
    UIDropDownMenu_SetText(dropdown, "Select a bet type …")
    UIDropDownMenu_Initialize(dropdown, function(_, level) Gamble:BuildTypeDropdown(level) end)
    self.typeDropdown = dropdown

    local instanceDropdown = CreateFrame("Frame", "GambleInstanceDropdown", f, "UIDropDownMenuTemplate")
    instanceDropdown:SetPoint("TOPLEFT", 5, -130); UIDropDownMenu_SetWidth(instanceDropdown, 330)
    UIDropDownMenu_SetText(instanceDropdown, "Instanz: automatisch / auswählen")
    UIDropDownMenu_Initialize(instanceDropdown, function(_, level, menuList) Gamble:BuildInstanceDropdown(level, menuList) end)
    instanceDropdown:Hide(); self.instanceDropdown = instanceDropdown
    f:HookScript("OnShow", function() Gamble:Refresh() end)

    local bossDropdown = CreateFrame("Frame", "GambleBossDropdown", f, "UIDropDownMenuTemplate")
    bossDropdown:SetPoint("TOPLEFT", 5, -130); UIDropDownMenu_SetWidth(bossDropdown, 330)
    UIDropDownMenu_SetText(bossDropdown, "Boss: auto-detect")
    UIDropDownMenu_Initialize(bossDropdown, function(_, level) Gamble:BuildBossDropdown(level) end)
    bossDropdown:Hide(); self.bossDropdown = bossDropdown

    local itemHint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    itemHint:SetPoint("TOPLEFT", 18, -160); itemHint:SetText("Select a boss to see its loot list."); itemHint:Hide(); self.itemHint = itemHint

    local status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    status:SetPoint("TOPLEFT", 18, -171); status:SetPoint("TOPRIGHT", -18, -171); status:SetJustifyH("LEFT"); status:SetText("No open bet")
    self.status = status
    local rules = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rules:SetPoint("TOPLEFT", 22, -212); rules:SetPoint("TOPRIGHT", -22, -212); rules:SetJustifyH("LEFT"); rules:SetWordWrap(true); rules:Hide()
    self.rulesText = rules

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 18, -198); hint:SetText("Choose a prediction (nearby players only):"); self.rosterHint = hint

    local previousBoss = MakeButton(f, 82, 22, "Back")
    previousBoss:SetPoint("TOPRIGHT", -108, -190)
    previousBoss:SetScript("OnClick", function()
        state.seriesStep = max(1, state.seriesStep - 1)
        local pick = state.seriesPicks[state.seriesStep]; state.selectedGUID = pick and pick.guid or nil; state.selectedName = pick and pick.name or nil
        Gamble:Refresh()
    end)
    previousBoss:Hide(); self.previousBossButton = previousBoss

    local nextBoss = MakeButton(f, 82, 22, "Next")
    nextBoss:SetPoint("TOPRIGHT", -18, -190)
    nextBoss:SetScript("OnClick", function()
        local bosses = state.active and IsBossSeries(state.active.mode) and state.active.bosses or state.bosses
        state.seriesStep = math.min(#bosses, state.seriesStep + 1)
        local pick = state.seriesPicks[state.seriesStep]; state.selectedGUID = pick and pick.guid or nil; state.selectedName = pick and pick.name or nil
        Gamble:Refresh()
    end)
    nextBoss:Hide(); self.nextBossButton = nextBoss

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -216); scroll:SetSize(475, 149); self.rosterScroll = scroll
    local content = CreateFrame("Frame", nil, scroll); content:SetSize(450, 1); scroll:SetScrollChild(content)
    self.rosterContent, self.rosterButtons = content, {}

    self.goldBox = MakeMoneyBox(f, "Interface\\MoneyFrame\\UI-GoldIcon", 22)
    self.silverBox = MakeMoneyBox(f, "Interface\\MoneyFrame\\UI-SilverIcon", 112)
    self.copperBox = MakeMoneyBox(f, "Interface\\MoneyFrame\\UI-CopperIcon", 202)
    local function MoneyChanged()
        if Gamble.frame and Gamble.frame:IsShown() then Gamble:Refresh() end
    end
    self.goldBox:SetScript("OnTextChanged", MoneyChanged)
    self.silverBox:SetScript("OnTextChanged", MoneyChanged)
    self.copperBox:SetScript("OnTextChanged", MoneyChanged)

    local action = MakeButton(f, 170, 28, "Open Bet")
    action:SetPoint("TOPRIGHT", -22, -376); self.actionButton = action
    action:SetScript("OnClick", function() Gamble:PrimaryAction() end)

    local line = f:CreateTexture(nil, "ARTWORK"); line:SetColorTexture(.3, .3, .3, .7); line:SetHeight(1); line:SetPoint("TOPLEFT", 18, -422); line:SetPoint("TOPRIGHT", -18, -422); self.resultsLine = line
    local betsTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); betsTitle:SetPoint("TOPLEFT", 18, -436); betsTitle:SetText("Stakes / Results"); self.betsTitle = betsTitle
    local betsText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    betsText:SetPoint("TOPLEFT", 18, -458); betsText:SetPoint("TOPRIGHT", -18, -458); betsText:SetJustifyH("LEFT"); betsText:SetJustifyV("TOP"); betsText:SetWordWrap(true); betsText:Hide(); self.betsText = betsText
    self.seriesSummaryButtons = {}

    local detailsButton = MakeButton(f, 175, 24, "Show Payments")
    detailsButton:SetPoint("TOPRIGHT", -20, -134); detailsButton:Hide(); self.detailsButton = detailsButton

    local seriesReview = MakeButton(f, 220, 24, "Show Boss Picks")
    seriesReview:SetPoint("TOPRIGHT", -18, -452); seriesReview:Hide(); self.seriesReviewButton = seriesReview

    local seriesPopup = CreateFrame("Frame", "GambleSeriesTipsFrame", UIParent, "BasicFrameTemplateWithInset")
    seriesPopup:SetSize(360, 480); seriesPopup:SetPoint("TOPLEFT", f, "TOPRIGHT", 8, 0)
    seriesPopup:SetFrameStrata("DIALOG"); seriesPopup:SetClampedToScreen(true); seriesPopup:SetMovable(true); seriesPopup:EnableMouse(true)
    seriesPopup:RegisterForDrag("LeftButton"); seriesPopup:SetScript("OnDragStart", seriesPopup.StartMoving); seriesPopup:SetScript("OnDragStop", seriesPopup.StopMovingOrSizing)
    seriesPopup.TitleText:SetText("Gamble - Boss Picks")
    if seriesPopup.CloseButton then seriesPopup.CloseButton:Hide(); seriesPopup.CloseButton:Disable() end
    local seriesPopupHint = seriesPopup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    seriesPopupHint:SetPoint("TOPLEFT", 18, -38); seriesPopupHint:SetPoint("TOPRIGHT", -18, -38); seriesPopupHint:SetJustifyH("LEFT")
    seriesPopupHint:SetText("Click a boss to view or change your prediction.")
    local seriesPopupScroll = CreateFrame("ScrollFrame", nil, seriesPopup, "UIPanelScrollFrameTemplate")
    seriesPopupScroll:SetPoint("TOPLEFT", 14, -62); seriesPopupScroll:SetPoint("BOTTOMRIGHT", -34, 16)
    local seriesPopupContent = CreateFrame("Frame", nil, seriesPopupScroll); seriesPopupContent:SetSize(310, 1); seriesPopupScroll:SetScrollChild(seriesPopupContent)
    seriesPopup:Hide()
    seriesReview:SetScript("OnClick", function()
        if seriesPopup:IsShown() then seriesPopup:Hide() else seriesPopup:Show(); seriesPopup:Raise(); Gamble:RefreshSeriesPopup() end
    end)
    f:HookScript("OnHide", function() seriesPopup:Hide() end)
    self.seriesPopup, self.seriesPopupContent, self.seriesPopupRows = seriesPopup, seriesPopupContent, {}

    local detailsPopup = CreateFrame("Frame", "GambleBetDetailsFrame", UIParent, "BasicFrameTemplateWithInset")
    detailsPopup:SetSize(390, 480); detailsPopup:SetPoint("TOPRIGHT", f, "TOPLEFT", -8, 0)
    detailsPopup:SetFrameStrata("DIALOG"); detailsPopup:SetClampedToScreen(true); detailsPopup:SetMovable(true); detailsPopup:EnableMouse(true)
    detailsPopup:RegisterForDrag("LeftButton"); detailsPopup:SetScript("OnDragStart", detailsPopup.StartMoving); detailsPopup:SetScript("OnDragStop", detailsPopup.StopMovingOrSizing)
    detailsPopup.TitleText:SetText("Gamble - Stakes / Results")
    local detailsScroll = CreateFrame("ScrollFrame", nil, detailsPopup, "UIPanelScrollFrameTemplate")
    detailsScroll:SetPoint("TOPLEFT", 16, -38); detailsScroll:SetPoint("BOTTOMRIGHT", -34, 16)
    local detailsContent = CreateFrame("Frame", nil, detailsScroll); detailsContent:SetSize(334, 1); detailsScroll:SetScrollChild(detailsContent)
    local detailsText = detailsContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detailsText:SetPoint("TOPLEFT", 4, -4); detailsText:SetPoint("TOPRIGHT", -4, -4); detailsText:SetJustifyH("LEFT"); detailsText:SetJustifyV("TOP"); detailsText:SetWordWrap(true)
    detailsPopup.autoOpened = {}; detailsPopup:Hide()
    detailsButton:SetScript("OnClick", function()
        if detailsPopup:IsShown() then
            detailsPopup:Hide(); detailsButton:SetText("Show Payments")
        else
            detailsPopup:Show(); detailsPopup:Raise(); detailsButton:SetText("Hide Payments"); Gamble:Refresh()
        end
    end)
    if detailsPopup.CloseButton then detailsPopup.CloseButton:SetScript("OnClick", function() detailsPopup:Hide(); detailsButton:SetText("Show Payments") end) end
    f:HookScript("OnHide", function() detailsPopup:Hide() end)
    self.detailsPopup, self.detailsContent, self.detailsText = detailsPopup, detailsContent, detailsText

    if GambleBankSecurity then GambleBankSecurity:AttachToMainUI(f, settingsButton) end

    local runningTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    runningTitle:SetPoint("TOP", 0, -112); runningTitle:SetJustifyH("CENTER"); runningTitle:SetText("Active Bets")
    local runningScroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    runningScroll:SetPoint("TOPLEFT", 18, -138); runningScroll:SetPoint("BOTTOMRIGHT", -38, 54)
    local runningContent = CreateFrame("Frame", nil, runningScroll); runningContent:SetSize(450, 1); runningScroll:SetScrollChild(runningContent)
    runningTitle:Hide(); runningScroll:Hide()
    self.runningTitle, self.runningScroll, self.runningContent, self.runningCards = runningTitle, runningScroll, runningContent, {}

    local pay = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    pay:SetSize(230, 24); pay:SetText("Next Payment")
    pay:SetPoint("BOTTOMLEFT", 18, 12); pay:SetScript("OnClick", function() Gamble:PayNext() end); self.payButton = pay
    local versionText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    versionText:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 2); versionText:SetText("Version " .. ADDON_VERSION); self.versionText = versionText
    local cancel = CreateFrame("Button", nil, f)
    cancel:SetSize(28, 28)
    local cancelIcon = cancel:CreateTexture(nil, "ARTWORK")
    cancelIcon:SetAllPoints(); cancelIcon:SetAtlas("128-RedButton-Delete", false)
    cancel:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    local cancelLabel = cancel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cancel:SetFontString(cancelLabel); cancel:SetText("Cancel Bet"); cancelLabel:Hide()
    cancel:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_TOP")
        GameTooltip:SetText(button:GetText() or "Cancel Bet", 1, .82, .12)
        GameTooltip:Show()
    end)
    cancel:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cancel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 16); cancel:SetScript("OnClick", function()
        Gamble:RequestCancel()
    end); cancel:Hide(); self.cancelButton = cancel
    local finishSeries = MakeButton(f, 110, 24, "Finish Series")
    finishSeries:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -56, 16)
    finishSeries:SetScript("OnClick", function() FinalizeSeries() end)
    finishSeries:Hide(); self.finishSeriesButton = finishSeries

    local winner = CreateFrame("Frame", "GambleWinnerFrame", UIParent, "BasicFrameTemplateWithInset")
    winner:SetSize(390, 205); winner:SetPoint("TOP", UIParent, "TOP", 0, -60)
    winner:SetFrameStrata("FULLSCREEN_DIALOG"); winner:SetClampedToScreen(true); winner:SetMovable(true); winner:EnableMouse(true)
    winner:RegisterForDrag("LeftButton"); winner:SetScript("OnDragStart", winner.StartMoving); winner:SetScript("OnDragStop", winner.StopMovingOrSizing)
    winner.TitleText:SetText("Gamble - Winner")
    local headline = winner:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    headline:SetPoint("TOP", 0, -45); headline:SetText("Winner")
    local winnerName = winner:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    winnerName:SetPoint("TOPLEFT", 18, -78); winnerName:SetPoint("TOPRIGHT", -18, -78); winnerName:SetJustifyH("CENTER")
    local winnerAmount = winner:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    winnerAmount:SetPoint("TOP", winnerName, "BOTTOM", 0, -12)
    local winnerTrade = CreateFrame("Button", nil, winner, "UIPanelButtonTemplate,InsecureActionButtonTemplate")
    winnerTrade:SetSize(250, 26); winnerTrade:SetPoint("BOTTOM", 0, 16); winnerTrade:SetText("Trade with Bank"); winnerTrade:Hide()
    winner:Hide()
    if winner.CloseButton then winner.CloseButton:SetScript("OnClick", function()
        winner.dismissedNoticeKey = winner.noticeKey
        GambleDB.dismissedWinnerNotices = GambleDB.dismissedWinnerNotices or {}
        if winner.noticeKey then GambleDB.dismissedWinnerNotices[winner.noticeKey] = true end
        winner:Hide()
    end) end
    self.winnerFrame, self.winnerHeadline, self.winnerName, self.winnerAmount, self.winnerTradeButton = winner, headline, winnerName, winnerAmount, winnerTrade
    GambleTradeAction:Attach(winnerTrade, function()
        local payment = winner.payment
        local grouped=payment and Gamble:GetGroupedPayment(payment.name)
        if grouped then return {name=grouped.name,prepare=function() state.pendingTrade=grouped; Print("Gesamtauszahlung: "..Money(grouped.amount).." an "..grouped.name..". Gold manuell eintragen und Handel bestätigen.") end} end
    end, Print)

    local escrow = CreateFrame("Frame", "GambleEscrowFrame", UIParent, "BasicFrameTemplateWithInset")
    escrow:SetSize(410, 230); escrow:SetPoint("TOP", UIParent, "TOP", 0, -60)
    escrow:SetFrameStrata("DIALOG"); escrow:SetClampedToScreen(true); escrow:SetMovable(true); escrow:EnableMouse(true)
    escrow:RegisterForDrag("LeftButton"); escrow:SetScript("OnDragStart", escrow.StartMoving); escrow:SetScript("OnDragStop", escrow.StopMovingOrSizing)
    escrow.TitleText:SetText("Gamble - Pay Stake")
    local escrowHint = escrow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    escrowHint:SetPoint("TOPLEFT", 18, -44); escrowHint:SetPoint("TOPRIGHT", -18, -44); escrowHint:SetJustifyH("CENTER")
    escrowHint:SetText("Payment to the bank – enter gold manually:")
    local escrowBank = escrow:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    escrowBank:SetPoint("TOPLEFT", 18, -76); escrowBank:SetPoint("TOPRIGHT", -18, -76); escrowBank:SetJustifyH("CENTER")
    local escrowAmount = escrow:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    escrowAmount:SetPoint("TOP", escrowBank, "BOTTOM", 0, -12)
    local escrowRange = escrow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    escrowRange:SetPoint("TOP", escrowAmount, "BOTTOM", 0, -12)
    local escrowTrade = CreateFrame("Button", nil, escrow, "UIPanelButtonTemplate,InsecureActionButtonTemplate")
    escrowTrade:SetSize(250, 28); escrowTrade:SetText("Target Bank")
    escrowTrade:SetPoint("BOTTOM", 0, 20)
    escrow:SetScript("OnUpdate", function(frame, elapsed)
        frame.rangeElapsed = (frame.rangeElapsed or 0) + elapsed
        if frame.rangeElapsed >= .25 then frame.rangeElapsed = 0; Gamble:RefreshEscrowPopup() end
    end)
    escrow:Hide()
    if escrow.CloseButton then escrow.CloseButton:SetScript("OnClick", function()
        escrow.dismissedRequestKey = escrow.requestKey
        escrow:Hide()
    end) end
    self.escrowFrame, self.escrowBank, self.escrowAmount, self.escrowRange, self.escrowTradeButton = escrow, escrowBank, escrowAmount, escrowRange, escrowTrade
    GambleTradeAction:Attach(escrowTrade, function()
        local request = state.pendingJoin
        if request then return { name = request.host } end
    end, Print)

    local settings = CreateFrame("Frame", "GambleSettingsFrame", UIParent, "BasicFrameTemplateWithInset")
    settings:SetSize(430, 210); settings:SetPoint("CENTER"); settings:SetFrameStrata("DIALOG")
    settings:SetClampedToScreen(true); settings:SetMovable(true); settings:EnableMouse(true); settings:RegisterForDrag("LeftButton")
    settings:SetScript("OnDragStart", settings.StartMoving); settings:SetScript("OnDragStop", settings.StopMovingOrSizing)
    settings.TitleText:SetText("Gamble - Settings")
    local settingsTitle = settings:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    settingsTitle:SetPoint("TOPLEFT", 22, -48); settingsTitle:SetText("Notifications")
    local autoPopup = CreateFrame("CheckButton", "GambleAutoWagerPopupCheck", settings, "UICheckButtonTemplate")
    autoPopup:SetPoint("TOPLEFT", 18, -78); autoPopup:SetSize(26, 26)
    local autoPopupText = autoPopup.Text or _G[autoPopup:GetName() .. "Text"]
    if autoPopupText then
        autoPopupText:SetText("Automatically show invitations for new group bets")
        autoPopupText:SetWidth(350); autoPopupText:SetJustifyH("LEFT")
    end
    local settingsHint = settings:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    settingsHint:SetPoint("TOPLEFT", 50, -112); settingsHint:SetPoint("TOPRIGHT", -22, -112); settingsHint:SetJustifyH("LEFT")
    settingsHint:SetText("When disabled, new bets remain visible without opening  to invitation.")
    local testButton = MakeButton(settings, 180, 26, "Open Solo Test Mode")
    testButton:SetPoint("BOTTOMLEFT", 22, 18)
    testButton:SetScript("OnClick", function()
        if GambleTestMode then settings:Hide(); GambleTestMode:Open() end
    end)
    autoPopup:SetScript("OnClick", function(button)
        GambleDB.settings = GambleDB.settings or {}
        GambleDB.settings.autoWagerPopup = button:GetChecked() and true or false
    end)
    settings:SetScript("OnShow", function()
        GambleDB.settings = GambleDB.settings or {}
        autoPopup:SetChecked(GambleDB.settings.autoWagerPopup ~= false)
    end)
    settings:Hide(); self.settingsFrame = settings
    settingsButton:SetScript("OnClick", function() if settings:IsShown() then settings:Hide() else settings:Show(); settings:Raise() end end)

    local invite = CreateFrame("Frame", "GambleWagerInviteFrame", UIParent, "BasicFrameTemplateWithInset")
    invite:SetSize(430, 225); invite:SetPoint("CENTER", UIParent, "CENTER", 0, 120); invite:SetFrameStrata("DIALOG")
    invite:SetClampedToScreen(true); invite:SetMovable(true); invite:EnableMouse(true); invite:RegisterForDrag("LeftButton")
    invite:SetScript("OnDragStart", invite.StartMoving); invite:SetScript("OnDragStop", invite.StopMovingOrSizing)
    invite.TitleText:SetText("Gamble - New Bet")
    local inviteHost = invite:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    inviteHost:SetPoint("TOPLEFT", 18, -50); inviteHost:SetPoint("TOPRIGHT", -18, -50); inviteHost:SetJustifyH("CENTER")
    local inviteText = invite:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    inviteText:SetPoint("TOPLEFT", 24, -88); inviteText:SetPoint("TOPRIGHT", -24, -88); inviteText:SetJustifyH("CENTER"); inviteText:SetWordWrap(true)
    local joinButton = MakeButton(invite, 190, 28, "View Bet & Join")
    joinButton:SetPoint("BOTTOMLEFT", 20, 22)
    joinButton:SetScript("OnClick", function()
        if invite.wager and invite.wager.don then invite:Hide(); if GambleDON then GambleDON:ShowDetails() end; return end
        local wager = invite.wager
        invite:Hide(); Gamble.frame:Show(); Gamble.frame:Raise()
        if wager then Gamble:ShowWagerDetails(wager) end
    end)
    local declineButton = MakeButton(invite, 150, 28, "Maybe Later")
    declineButton:SetPoint("BOTTOMRIGHT", -20, 22); declineButton:SetScript("OnClick", function() invite:Hide() end)
    local inviteRules = invite:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    inviteRules:SetPoint("TOPLEFT", 24, -183); inviteRules:SetPoint("TOPRIGHT", -24, -183); inviteRules:SetJustifyH("LEFT"); inviteRules:SetWordWrap(true); inviteRules:Hide()
    local rulesToggle = CreateFrame("Button", nil, invite); rulesToggle:SetSize(28, 28); rulesToggle:SetPoint("TOPRIGHT", -24, -144)
    local rulesIcon = rulesToggle:CreateTexture(nil, "ARTWORK"); rulesIcon:SetAllPoints(); rulesIcon:SetAtlas("lorewalking-map-icon", false)
    rulesToggle:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    rulesToggle:SetScript("OnClick", function()
        local expanded = not inviteRules:IsShown()
        inviteRules:SetText(Gamble:GetRules(invite.wager and invite.wager.mode))
        inviteRules:SetShown(expanded)
        invite:SetHeight(expanded and (250 + inviteRules:GetStringHeight()) or 225)
    end)
    rulesToggle:SetScript("OnEnter", function(button) GameTooltip:SetOwner(button, "ANCHOR_RIGHT"); GameTooltip:SetText("Show / hide rules"); GameTooltip:Show() end)
    rulesToggle:SetScript("OnLeave", function() GameTooltip:Hide() end)
    invite:HookScript("OnHide", function() inviteRules:Hide(); invite:SetHeight(225) end)
    invite:Hide(); self.inviteFrame, self.inviteHost, self.inviteText = invite, inviteHost, inviteText
end

function Gamble:ShowWagerInvite(sender, wager)
    if not self.inviteFrame or not GambleDB.settings or GambleDB.settings.autoWagerPopup == false then return end
    local member = FindRosterByName(sender)
    local r, g, b = ClassColor(member and member.class)
    local color = string.format("|cff%02x%02x%02x", floor(r * 255), floor(g * 255), floor(b * 255))
    self.inviteHost:SetText(color .. DisplayName(sender) .. "|r opened a bet!")
    self.inviteText:SetText(BetLabel(wager.mode) .. "\nMinimum stake: " .. Money(wager.minimum) .. (wager.maxRounds and ("\nRounds: " .. wager.maxRounds) or "") .. "\n\nView the lobby and join?")
    self.inviteFrame.wager = wager
    self.inviteFrame:Show(); self.inviteFrame:Raise()
end

local function IsWinnerPayment(payment)
    return payment and (payment.reason == "Winnings" or payment.reason == "Series winnings" or payment.reason == "Item-Jackpot" or payment.reason == "LMS winnings")
end

local function WinnerEntries(a)
    local entries, payouts = {}, nil
    if not a or not a.result or a.result.void or a.result.itemMiss then return entries end
    if a.result.rankedDamage then payouts = a.rankPayouts
    elseif a.result.lms then payouts = a.lmsPayouts
    elseif a.result.series then payouts = a.seriesPayouts
    elseif a.result.item then payouts = a.itemPayouts
    else local _, _, computed = ComputeResult(a.result.guid, a); payouts = computed end
    for name, amount in pairs(payouts or {}) do
        amount = tonumber(amount) or 0
        if amount > 0 then entries[#entries + 1] = { name = name, amount = amount } end
    end
    table.sort(entries, function(left, right) return left.name < right.name end)
    return entries
end

local function WinnerWager()
    if state.active and not state.active.result then return nil end
    if state.active and state.active.result and not state.active.result.void and not state.active.result.itemMiss then return state.active end
    for index = #state.wagers, 1, -1 do
        local wager = state.wagers[index]
        if wager.result and not wager.result.void and not wager.result.itemMiss then return wager end
    end
end

function Gamble:RefreshWinnerPopup()
    if not self.winnerFrame then return end
    if state.tradeContext and state.tradeContext.direction ~= "payout" then self.winnerFrame:Hide(); return end
    if InCombatLockdown and InCombatLockdown() then return end
    local damageNotice = self.damageResultNotice
    if damageNotice then
        self.damageResultNotice = nil
        self.winnerFrame.payment = nil
        self.winnerFrame.finalWagerID = damageNotice.id
        self.winnerFrame.noticeKey = (damageNotice.winner and "DAMAGE_WINNER:" or "DAMAGE_REFUND:") .. damageNotice.id
        self.winnerFrame.TitleText:SetText("Gamble - Damage Race Result")
        self.winnerHeadline:SetText(damageNotice.headline)
        self.winnerName:SetText(damageNotice.detail)
        self.winnerAmount:SetText(damageNotice.topDamage .. (damageNotice.winner and "" or "\nAll stakes will be refunded."))
        self.winnerTradeButton:Hide()
        self.winnerFrame:Show(); self.winnerFrame:Raise()
        return
    end
    if state.active and state.active.result and (state.active.result.void or state.active.result.itemMiss) then
        if self.winnerFrame.finalWagerID == state.active.id then return end
        self.winnerFrame:Hide()
        return
    end
    local payment
    for _, queued in ipairs(state.payments) do
        if IsWinnerPayment(queued) then payment = queued; break end
    end
    local wager = WinnerWager()
    if self.winnerFrame.finalWagerID and wager and self.winnerFrame.finalWagerID == wager.id then return end
    if wager and not SamePlayer(wager.host, PlayerName()) and not OwnBet(wager) then
        self.winnerFrame:Hide()
        return
    end
    local entries = WinnerEntries(wager)
    local entry = payment or entries[1]
    if not entry then
        self.winnerFrame.payment = nil
        self.winnerFrame:Hide()
        return
    end
    local noticeKey
    if payment then
        noticeKey = "PAYMENT:" .. tostring(payment.wagerID or "") .. ":" .. tostring(payment.name) .. ":" .. tostring(payment.amount) .. ":" .. tostring(payment.reason or "")
    elseif wager then noticeKey = "RESULT:" .. wager.id .. ":" .. tostring(entry.name) .. ":" .. tostring(entry.amount) end
    local isNew = self.winnerFrame.noticeKey ~= noticeKey
    self.winnerFrame.noticeKey = noticeKey
    self.winnerFrame.payment = payment
    self.winnerFrame.TitleText:SetText("Gamble - Winner")
    self.winnerHeadline:SetText("Winner")
    if wager and wager.result and (wager.result.series or wager.result.rankedDamage) and #entries > 1 then
        local names, amounts = {}, {}
        for _, winner in ipairs(entries) do
            names[#names + 1] = DisplayName(winner.name)
            amounts[#amounts + 1] = DisplayName(winner.name) .. ": " .. Money(winner.amount)
        end
        self.winnerName:SetText(table.concat(names, ", "))
        self.winnerAmount:SetText(table.concat(amounts, "\n"))
    else
        self.winnerName:SetText(entry.name or "?")
        self.winnerAmount:SetText("Winnings: " .. Money(entry.amount))
    end
    if wager and wager.result.rankedDamage then self.winnerHeadline:SetText("Winner — "..(wager.rankBest or 0).." points") end
    GambleTradeAction:Prepare(self.winnerTradeButton)
    GambleDB.dismissedWinnerNotices = GambleDB.dismissedWinnerNotices or {}
    if state.restoringSession then
        GambleDB.dismissedWinnerNotices[noticeKey] = true
        self.winnerFrame.dismissedNoticeKey = noticeKey
    elseif isNew and self.winnerFrame.dismissedNoticeKey ~= noticeKey and not GambleDB.dismissedWinnerNotices[noticeKey] then
        GambleDB.dismissedWinnerNotices[noticeKey] = true
        self.winnerFrame.finalWagerID = nil; self.winnerFrame:Show(); self.winnerFrame:Raise()
    end
end

function Gamble:ShowWinnerAnnouncement(name, amount, wagerID)
    if not self.winnerFrame then return end
    local completed=FindWager(wagerID)
    if not completed or not completed.result or completed.result.void then return end
    self.winnerFrame.payment = nil
    self.winnerFrame.noticeKey = "PAID:" .. tostring(wagerID or "") .. ":" .. tostring(name) .. ":" .. tostring(amount)
    self.winnerFrame.finalWagerID = wagerID
    self.winnerFrame.TitleText:SetText("Gamble - Winner")
    self.winnerHeadline:SetText("Winner")
    self.winnerName:SetText(name or "?")
    self.winnerAmount:SetText("Winnings paid: " .. Money(amount))
    self.winnerTradeButton:Hide()
    GambleDB.dismissedWinnerNotices = GambleDB.dismissedWinnerNotices or {}
    if self.winnerFrame.dismissedNoticeKey ~= self.winnerFrame.noticeKey and not GambleDB.dismissedWinnerNotices[self.winnerFrame.noticeKey] then
        GambleDB.dismissedWinnerNotices[self.winnerFrame.noticeKey] = true
        self.winnerFrame:Show(); self.winnerFrame:Raise()
    end
end

function Gamble:ShowRefundAnnouncement(bank, amount, wagerID)
    if not self.winnerFrame then return end
    self.winnerFrame.payment = nil
    self.winnerFrame.noticeKey = "REFUND:" .. tostring(wagerID or "") .. ":" .. tostring(bank) .. ":" .. tostring(amount)
    self.winnerFrame.finalWagerID = wagerID
    self.winnerFrame.TitleText:SetText("Gamble - Refund")
    self.winnerHeadline:SetText("Bet cancelled")
    self.winnerName:SetText("Trade with the bank: " .. tostring(bank or "?"))
    self.winnerAmount:SetText("Your refund: " .. Money(amount) .. "\nOpen a trade with the bank.")
    GambleTradeAction:Prepare(self.winnerTradeButton)
    GambleDB.dismissedWinnerNotices = GambleDB.dismissedWinnerNotices or {}
    if self.winnerFrame.dismissedNoticeKey ~= self.winnerFrame.noticeKey and not GambleDB.dismissedWinnerNotices[self.winnerFrame.noticeKey] then
        GambleDB.dismissedWinnerNotices[self.winnerFrame.noticeKey] = true
        self.winnerFrame:Show(); self.winnerFrame:Raise()
    end
end

function Gamble:RefreshVersionLabel()
    if not self.versionText then return end
    local newest, peers = nil, 0
    for player, version in pairs(state.knownVersions) do
        if not SamePlayer(player, PlayerName()) then
            peers = peers + 1
            if not newest or IsNewerVersion(version, newest) then newest = version end
        end
    end
    if newest and IsNewerVersion(newest, ADDON_VERSION) then
        self.versionText:SetText("|cffff5555Version " .. ADDON_VERSION .. " – Update to " .. newest .. " available|r")
    elseif IsInGroup() and peers == 0 then
        self.versionText:SetText("|cffffd45aVersion " .. ADDON_VERSION .. " – no other Gamble client detected|r")
    else
        self.versionText:SetText("|cff55ff55Version " .. ADDON_VERSION .. " – up to date|r")
    end
end

local function TradeRange(name)
    local member = FindRosterByName(name)
    if not member then return false, nil end
    local inRange = false
    if CheckInteractDistance then
        local ok, result = pcall(CheckInteractDistance, member.unit, 2)
        inRange = ok and CanRead(result) and result and true or false
    end
    local distance
    if UnitDistanceSquared then
        local ok, squared = pcall(UnitDistanceSquared, member.unit)
        if ok and CanRead(squared) and type(squared) == "number" and squared >= 0 then distance = math.sqrt(squared) end
    end
    return inRange, distance
end

function Gamble:RefreshEscrowPopup()
    if not self.escrowFrame then return end
    if InCombatLockdown and InCombatLockdown() then
        if self.escrowFrame:IsShown() then self.escrowRange:SetText("|cffff5555Trading is unavailable in combat.|r") end
        return
    end
    local request = state.pendingJoin
    if not request or (state.active and SamePlayer(state.active.host, PlayerName())) then self.escrowFrame:Hide(); return end
    local requestKey = tostring(request.id) .. ":" .. tostring(request.host) .. ":" .. tostring(request.stake) .. ":" .. tostring(request.totalStake)
    self.escrowFrame.requestKey = requestKey
    if self.escrowFrame.dismissedRequestKey == requestKey then return end
    self.escrowBank:SetText(request.host or "?")
    self.escrowAmount:SetText("Stake: " .. Money(request.stake))
    local inRange, distance = TradeRange(request.host)
    local member = FindRosterByName(request.host)
    if InCombatLockdown and InCombatLockdown() then
        self.escrowRange:SetText("|cffff5555Trading is unavailable in combat.|r"); self.escrowTradeButton:Disable()
    elseif inRange then
        self.escrowRange:SetText((distance and string.format("|cff55ff55Within trade range (approx. %.1f m). Click below to trade.|r", distance)) or "|cff55ff55Within trade range. Click below to trade.|r")
        self.escrowTradeButton:Enable()
    elseif member and not distance then
        self.escrowRange:SetText("|cffffd45aRange unknown. Move closer to the bank.|r")
        self.escrowTradeButton:Enable()
    else
        self.escrowRange:SetText((distance and string.format("|cffff7777Too far away (approx. %.1f m) – move closer to the bank.|r", distance)) or "|cffff7777Too far away – move closer to the bank.|r")
        self.escrowTradeButton:Disable()
    end
    GambleTradeAction:Prepare(self.escrowTradeButton)
    if not self.escrowFrame:IsShown() then self.escrowFrame:Show(); self.escrowFrame:Raise() end
end

function Gamble:BuildTypeDropdown(level)
    if level ~= 1 then return end
    local query = self.searchBox and self.searchBox:GetText():lower() or ""
    local order = { "NEXT_PULL", "NEXT_BOSS", "LAST_MAN_STANDING", "BOSS_HP_WIPE", "PULL_TIMER_DEATH", "TOTAL_DEATHS", "BOSS_SERIES", "ITEM_DROP", "DOUBLE_OR_NOTHING", "ROCK_PAPER_SCISSORS", "DAMAGE_RACE", "BOSS_DAMAGE_SERIES" }
    local found = false
    for _, key in ipairs(order) do
        local entry = BET_TYPES[key]
        if query == "" or entry.label:lower():find(query, 1, true) or entry.search:find(query, 1, true) then
            found = true
            local info = UIDropDownMenu_CreateInfo()
            info.text = entry.label; info.checked = state.selectedType == key
            info.func = function()
                if state.active then
                    Print("An existing bet's type cannot be changed. Use New Bet or Active Bets.")
                    CloseDropDownMenus(); Gamble:Refresh(); return
                end
                state.selectedType = key
                state.selectedBoss = nil
                state.selectedGUID, state.selectedName = nil, nil
                wipe(state.lootItems)
                wipe(state.seriesPicks); state.seriesStep = 1
                if key == "NEXT_BOSS" or key == "LAST_MAN_STANDING" or IsBossSeries(key) or key == "ITEM_DROP" or IsEncounterBetMode(key) then LoadCurrentInstanceBosses() end
                UIDropDownMenu_SetText(Gamble.typeDropdown, entry.label)
                UIDropDownMenu_SetText(Gamble.bossDropdown, "Boss: auto-detect")
                CloseDropDownMenus(); Gamble:Refresh()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end
    if not found then
        local info = UIDropDownMenu_CreateInfo(); info.text = "No matching bet type"; info.disabled = true
        UIDropDownMenu_AddButton(info, level)
    end
end

function Gamble:BuildBossDropdown(level)
    if level ~= 1 then return end
    local automatic = UIDropDownMenu_CreateInfo()
    automatic.text = "Automatic: next detected boss"; automatic.checked = state.selectedBoss == nil
    automatic.disabled = state.selectedType == "ITEM_DROP"
    automatic.func = function()
        state.selectedBoss = nil; state.selectedGUID, state.selectedName = nil, nil
        wipe(state.lootItems)
        UIDropDownMenu_SetText(Gamble.bossDropdown, "Boss: auto-detect")
        CloseDropDownMenus(); Gamble:Refresh()
    end
    UIDropDownMenu_AddButton(automatic, level)
    for _, boss in ipairs(state.bosses) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = (GambleData.IsRareBoss(boss) and "|A:ui-hud-unitframe-target-portraiton-boss-rare-silver:24:24|a " or "") .. boss.name .. (GambleData.IsRareBoss(boss) and " |cffaaaaaa[OPTIONAL RARE]|r" or "") .. (boss.defeated and " |cff777777[DEFEATED]|r" or ""); info.checked = state.selectedBoss == boss
        info.disabled = boss.defeated and true or false
        info.func = function()
            if boss.defeated then return end
            state.selectedBoss = boss; state.selectedGUID, state.selectedName = nil, nil
            if state.selectedType == "ITEM_DROP" then LoadBossLoot(boss) end
            UIDropDownMenu_SetText(Gamble.bossDropdown, "Boss: " .. boss.name)
            CloseDropDownMenus(); Gamble:Refresh()
        end
        UIDropDownMenu_AddButton(info, level)
    end
    if #state.bosses == 0 then
        local unavailable = UIDropDownMenu_CreateInfo(); unavailable.text = state.allBossesDefeated and "All bosses in this instance have been defeated" or "No boss list available for this instance"; unavailable.disabled = true
        UIDropDownMenu_AddButton(unavailable, level)
    end
end

function Gamble:RefreshTypeDropdown()
    if self.typeDropdown and DropDownList1 and DropDownList1:IsShown() then
        CloseDropDownMenus(); ToggleDropDownMenu(1, nil, self.typeDropdown)
    end
end

function Gamble:RefreshRoster()
    BuildRoster()
    for _,wager in pairs(state.wagers) do GambleDamageBets:UpdateRoster(wager,state.roster) end
    if state.active then GambleDamageBets:UpdateRoster(state.active,state.roster) end
    for _, b in ipairs(self.rosterButtons) do b:Hide() end
    local shown = 0
    local itemMode = (state.active and state.active.mode == "ITEM_DROP") or (not state.active and state.selectedType == "ITEM_DROP")
    local optionMode = (state.active and IsEncounterBetMode(state.active.mode) and state.active.mode) or (not state.active and IsEncounterBetMode(state.selectedType) and state.selectedType)
    local entries
    if optionMode then
        entries = {}
        for _, option in ipairs(GambleEncounterTracker:GetOptions(optionMode)) do entries[#entries + 1] = option end
    else
        entries = itemMode and ((state.active and state.active.lootItems and #state.active.lootItems > 0) and state.active.lootItems or state.lootItems) or state.roster
    end
    if itemMode and #entries == 0 and state.active then
        entries = {}
        local seenItems = {}
        for _, bet in pairs(state.active.bets or {}) do
            if bet.targetItemID and not seenItems[bet.targetItemID] then
                seenItems[bet.targetItemID] = true
                local cachedName, cachedLink, _, _, _, _, _, _, _, cachedIcon = SafeGetItemInfo(bet.targetItemID)
                entries[#entries + 1] = { id = bet.targetItemID, name = cachedName or bet.targetName or ("Item " .. bet.targetItemID), link = cachedLink or bet.targetName, icon = cachedIcon }
            end
        end
        table.sort(entries, function(left, right) return tostring(left.name) < tostring(right.name) end)
    end
    for _, member in ipairs(entries) do
        if itemMode or optionMode or member.unit then
        shown = shown + 1
        local b = self.rosterButtons[shown]
        if not b then
            b = CreateFrame("Button", nil, self.rosterContent, "BackdropTemplate")
            b:SetSize(435, 30)
            b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 9, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
            if GambleUIStyle then GambleUIStyle:Row(b) end
            b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            b.text:SetPoint("LEFT", 15, 6); b.text:SetPoint("RIGHT", -105, 6); b.text:SetJustifyH("LEFT")
            b.meta = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); b.meta:SetPoint("LEFT", 15, -8); b.meta:SetPoint("RIGHT", -105, -8); b.meta:SetJustifyH("LEFT")
            b.classBar = b:CreateTexture(nil, "ARTWORK"); b.classBar:SetPoint("TOPLEFT", 5, -5); b.classBar:SetPoint("BOTTOMLEFT", 5, 5); b.classBar:SetWidth(4)
            b.selection = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); b.selection:SetPoint("RIGHT", -10, 0); b.selection:SetText("|cff33ff33SELECTED|r")
            b:SetHighlightTexture("Interface/QuestFrame/UI-QuestTitleHighlight")
            self.rosterButtons[shown] = b
        end
        b:SetPoint("TOPLEFT", 0, -(shown - 1) * 34); b:Show(); b.member = member; b.gambleRankPlace=nil
        b.text:ClearAllPoints(); b.meta:ClearAllPoints()
        b.text:SetPoint("LEFT", 15, 6); b.text:SetPoint("RIGHT", -105, 6)
        b.meta:SetPoint("LEFT", 15, -8); b.meta:SetPoint("RIGHT", -105, -8); b.meta:SetJustifyH("LEFT")
        if optionMode then
            local key = "OPT:" .. member.key
            local selected = state.selectedGUID == key
            b.text:SetText(member.label); b.text:SetTextColor(1, .82, .12)
            if optionMode == "BOSS_HP_WIPE" then b.meta:SetText("Boss-Restleben beim Wipe")
            elseif optionMode == "PULL_TIMER_DEATH" then b.meta:SetText(member.noDeath and "Boss kill without player deaths" or "First player death after the pull")
            else b.meta:SetText("Total player deaths in the encounter") end
            b.classBar:SetColorTexture(1, .72, .05, 1); b.classBar:Show(); b.selection:SetShown(selected)
            b:SetBackdropColor(selected and .24 or .035, selected and .18 or .035, selected and .035 or .035, selected and .96 or .82)
            b:SetBackdropBorderColor(selected and 1 or .28, selected and .72 or .28, selected and .08 or .28, selected and 1 or .75)
            b.itemLocked = nil; b:Enable(); b:SetScript("OnEnter", nil); b:SetScript("OnLeave", nil)
        elseif itemMode then
            local key = "ITEM:" .. member.id; local locked = false
            local selected = state.selectedGUID == key
            if state.active then for _, bet in pairs(state.active.bets) do if bet.targetItemID == member.id and not SamePlayer(bet.bettor, PlayerName()) then locked = true end end end
            b.text:SetText((member.icon and ("|T" .. member.icon .. ":18:18:0:0|t ") or "") .. (member.link or member.name) .. (locked and " |cffff5555[ASSIGNED]|r" or "")); b.text:SetTextColor(1, 1, 1)
            b.meta:SetText("")
            b.classBar:Hide(); b.selection:SetShown(selected)
            b:SetBackdropColor(selected and .24 or .035, selected and .18 or .035, selected and .035 or .035, selected and .96 or .82)
            b:SetBackdropBorderColor(selected and 1 or .28, selected and .72 or .28, selected and .08 or .28, selected and 1 or .75)
            b.itemLocked = locked
            b:Enable()
            b:SetScript("OnEnter", function(button)
                local item = button.member
                if not item or not item.id then return end
                GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
                local hyperlink = item.link
                if not hyperlink then
                    local _, cachedLink = SafeGetItemInfo(item.id)
                    hyperlink = cachedLink
                end
                local ok = hyperlink and pcall(GameTooltip.SetHyperlink, GameTooltip, hyperlink)
                if not ok then pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. item.id) end
                GameTooltip:Show()
                if GameTooltip_ShowCompareItem and IsModifiedClick and IsModifiedClick("COMPAREITEMS") then
                    pcall(GameTooltip_ShowCompareItem, GameTooltip)
                end
            end)
            b:SetScript("OnLeave", function()
                GameTooltip:Hide()
                if ShoppingTooltip1 then ShoppingTooltip1:Hide() end
                if ShoppingTooltip2 then ShoppingTooltip2:Hide() end
            end)
        else
            local selected = state.selectedGUID == member.guid
            local rankPlace=GambleDamageBets:SelectedPlace(self,state,member.guid)
            b.gambleRankPlace=rankPlace
            if state.active and GambleDamageBets:IsMode(state.active.mode) then selected=rankPlace~=nil end
            local rankColor=rankPlace==2 and "|cffffd919" or rankPlace==3 and "|cffff3333" or "|cff33ff33"
            b.selection:SetText(rankPlace and (rankColor.."Platz "..rankPlace.."|r") or "|cff33ff33SELECTED|r")
            local r, g, bl = ClassColor(member.class); b.text:SetText(DisplayName(member.name)); b.text:SetTextColor(r, g, bl)
            b.text:ClearAllPoints(); b.text:SetPoint("LEFT", 15, 0); b.text:SetPoint("RIGHT", b, "CENTER", -35, 0)
            b.meta:ClearAllPoints(); b.meta:SetPoint("CENTER", b, "CENTER", 0, 0); b.meta:SetJustifyH("CENTER")
            b.meta:SetText(member.online == false and "|cffff5555Offline|r" or "|cff55ff55Online|r")
            b.classBar:SetColorTexture(r, g, bl, 1); b.classBar:Show(); b.selection:SetShown(selected)
            b:SetBackdropColor(selected and .24 or .035, selected and .18 or .035, selected and .035 or .035, selected and .96 or .82)
            b:SetBackdropBorderColor(selected and 1 or .28, selected and .72 or .28, selected and .08 or .28, selected and 1 or .75)
            local unavailable = state.active and state.active.mode == "LAST_MAN_STANDING" and member.online == false
            if unavailable then b.text:SetText(DisplayName(member.name) .. " |cff777777[offline]|r"); b:Disable() else b:Enable() end
            b:SetScript("OnEnter", nil); b:SetScript("OnLeave", nil)
        end
        b:SetScript("OnClick", function(button)
            if state.active and GambleDamageBets:IsMode(state.active.mode) then
                GambleDamageBets:Choose(Gamble,state,button.member)
                Gamble:ApplySelectedPrediction(); Gamble:Refresh(); return
            end
            if optionMode then
                state.selectedGUID, state.selectedName = "OPT:" .. button.member.key, button.member.label
            elseif itemMode then
                local item = button.member
                GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
                local hyperlink = item and item.link
                if item and not hyperlink then local _, cachedLink = SafeGetItemInfo(item.id); hyperlink = cachedLink end
                local ok = hyperlink and pcall(GameTooltip.SetHyperlink, GameTooltip, hyperlink)
                if item and not ok then pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. item.id) end
                GameTooltip:Show()
                if button.itemLocked then return end
                state.selectedGUID, state.selectedName = "ITEM:" .. item.id, item.link or item.name
            else state.selectedGUID, state.selectedName = button.member.guid, button.member.name end
            local seriesBosses = state.active and IsBossSeries(state.active.mode) and state.active.bosses or state.bosses
            if ((not state.active and IsBossSeries(state.selectedType)) or (state.active and IsBossSeries(state.active.mode) and not state.active.result)) and #seriesBosses > 0 then
                if state.active and (state.active.seriesResults[state.seriesStep] or state.active.currentSeriesBoss == state.seriesStep) then
                    Print("This boss prediction is locked and cannot be changed."); return
                end
                state.seriesPicks[state.seriesStep] = { guid = button.member.guid, name = button.member.name }
                if state.seriesStep < #seriesBosses then
                    repeat state.seriesStep = state.seriesStep + 1 until state.seriesStep >= #seriesBosses or not state.active or (not state.active.seriesResults[state.seriesStep] and state.active.currentSeriesBoss ~= state.seriesStep)
                end
                local nextPick = state.seriesPicks[state.seriesStep]
                state.selectedGUID = nextPick and nextPick.guid or nil; state.selectedName = nextPick and nextPick.name or nil
            end
            Gamble:ApplySelectedPrediction()
            Gamble:Refresh()
        end)
        end
    end
    self.rosterContent:SetHeight(max(1, shown * 34))
end

function Gamble:HasInstanceProgress(name)
    local dataName=ResolveInstanceDataName(name)
    local prefix=NormalizeInstanceName(dataName)..":"
    for key,defeated in pairs(state.defeatedBosses or {}) do
        if defeated and key:sub(1,#prefix)==prefix then return true end
    end
    return false
end
function Gamble:ResetInstanceProgress(name,stamp,fromPeer)
    local dataName=ResolveInstanceDataName(name)
    if not BOSS_FALLBACKS[dataName] then return false end
    state.bossResetTimes=state.bossResetTimes or {}
    stamp=tonumber(stamp) or (GetServerTime and GetServerTime() or time())
    if stamp<=(state.bossResetTimes[dataName] or 0) then return false end
    state.bossResetTimes[dataName]=stamp
    local prefix=NormalizeInstanceName(dataName)..":"
    for key in pairs(state.defeatedBosses) do
        if key:sub(1,#prefix)==prefix then state.defeatedBosses[key]=nil end
    end
    state.lastBossSyncRequest=nil; state.bossSyncReplies=nil
    if not fromPeer then Send("BOSS_RESET",dataName,stamp) end
    -- Created wagers keep their agreed boss list and financial records.
    if not state.active then
        local selected=BettingCreationInstanceName()
        if selected and ResolveInstanceDataName(selected)==dataName then
            wipe(state.seriesPicks); state.seriesStep=1; LoadCurrentInstanceBosses()
        end
    end
    SaveSession()
    Print("Boss progress cleared: "..dataName..". New bets use the full boss list; existing bets remain unchanged.")
    self:Refresh()
    return true
end

function Gamble:HandleInstanceResetMessage(message)
    if not CanRead(message) or type(message)~="string" then return false end
    local function clean(text)
        return text:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r",""):gsub("|H.-|h(.-)|h","%1"):match("^%s*(.-)%s*$")
    end
    message=clean(message)
    for _,template in pairs({INSTANCE_RESET_SUCCESS,INSTANCE_RESET_SUCCESS_S,"%s has been reset.","%s wurde zurückgesetzt."}) do
        if type(template)=="string" then
            template=clean(template)
            local marker=template:find("%s",1,true)
            if marker then
                local before,after=template:sub(1,marker-1),template:sub(marker+2)
                if message:sub(1,#before)==before and (#after==0 or message:sub(-#after)==after) then
                    local name=message:sub(#before+1,#message-#after):match("^%s*(.-)%s*$")
                    local resolved=ResolveInstanceDataName(name)
                    if BOSS_FALLBACKS[resolved] then return self:ResetInstanceProgress(resolved) end
                    for dataName in pairs(BOSS_FALLBACKS) do
                        if NormalizeInstanceName(dataName)==NormalizeInstanceName(resolved) then return self:ResetInstanceProgress(dataName) end
                    end
                end
            end
        end
    end
    return false
end

function Gamble:BuildInstanceDropdown(level, menuList)
    level = level or 1
    local entries = {}
    for name, bosses in pairs(BOSS_FALLBACKS) do if #bosses > 0 then entries[#entries+1] = name end end
    table.sort(entries)
    local function Add(name)
        local info = UIDropDownMenu_CreateInfo(); info.text = name or "Automatic (current / last instance)"
        info.checked = state.preselectedInstance == name
        info.func = function()
            state.preselectedInstance = name; wipe(state.seriesPicks); state.seriesStep = 1
            LoadCurrentInstanceBosses()
            UIDropDownMenu_SetText(Gamble.instanceDropdown, name or "Instance: automatic")
            Gamble:Refresh()
        end
        UIDropDownMenu_AddButton(info, level)
    end
    if level == 2 then
        for i = menuList, math.min(menuList+11,#entries) do Add(entries[i]) end
        return
    end
    Add(nil)
    local last=BettingInstanceName()
    if last and self:HasInstanceProgress(last) then
        local resetInfo=UIDropDownMenu_CreateInfo(); resetInfo.text="Clear boss progress: "..last; resetInfo.notCheckable=true
        resetInfo.func=function() CloseDropDownMenus(); Gamble:ResetInstanceProgress(last) end
        UIDropDownMenu_AddButton(resetInfo,level)
    end
    local nearby = GambleData.GetZoneInstances()
    local current = BettingInstanceName()
    local shown = {}
    for _, name in ipairs(nearby) do if BOSS_FALLBACKS[name] and not shown[name] then Add(name); shown[name]=true end end
    current = current and ResolveInstanceDataName(current)
    if current and BOSS_FALLBACKS[current] and not shown[current] then Add(current) end
    for i=1,#entries,12 do
        local info=UIDropDownMenu_CreateInfo(); info.text=entries[i].." – "..entries[math.min(i+11,#entries)]
        info.hasArrow=true; info.notCheckable=true; info.menuList=i; UIDropDownMenu_AddButton(info,level)
    end
end

function Gamble:RefreshSeriesSummary(show, bosses)
    show = show and self.frame:IsShown()
    for _, button in ipairs(self.seriesSummaryButtons) do button:Hide() end
    self.seriesReviewButton:Hide()
    if not show then
        self.seriesAutoOpenKey = nil
        if self.seriesPopup then self.seriesPopup:Hide() end
        self.betsText:ClearAllPoints()
        self.betsText:SetPoint("TOPLEFT", 18, -458); self.betsText:SetPoint("TOPRIGHT", -18, -458)
        return
    end
    self.seriesReviewButton:SetText("Show Boss Picks (" .. #bosses .. ")")
    if self.seriesPopup then self.seriesPopup:Show() end
    if self.seriesPopup and self.seriesPopup:IsShown() then self:RefreshSeriesPopup() end
    self.betsText:ClearAllPoints()
    self.betsText:SetPoint("TOPLEFT", 18, -486); self.betsText:SetPoint("TOPRIGHT", -18, -486)
    self.betsText:SetText("")
end

function Gamble:RefreshSeriesPopup()
    if not self.seriesPopup or not self.seriesPopup:IsShown() then return end
    local bosses = state.active and IsBossSeries(state.active.mode) and state.active.bosses or state.bosses
    local showResults=state.active and state.active.mode=="BOSS_DAMAGE_SERIES" and state.active.result
    local rowHeight=showResults and 58 or 40
    for _, row in ipairs(self.seriesPopupRows) do row:Hide() end
    for index, boss in ipairs(bosses or {}) do
        local row = self.seriesPopupRows[index]
        if not row then
            row = CreateFrame("Button", nil, self.seriesPopupContent)
            row:SetSize(306, 36); row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            row.bg = row:CreateTexture(nil, "BACKGROUND"); row.bg:SetAllPoints(); row.bg:SetColorTexture(.08, .08, .08, .86)
            row.boss = row:CreateFontString(nil, "OVERLAY", "GameFontNormal"); row.boss:SetPoint("TOPLEFT", 8, -5); row.boss:SetPoint("TOPRIGHT", -8, -5); row.boss:SetJustifyH("LEFT")
            row.pick = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); row.pick:SetPoint("TOPLEFT", 8, -21); row.pick:SetPoint("TOPRIGHT", -8, -21); row.pick:SetJustifyH("LEFT")
            row.actual = row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
            row.actual:SetPoint("TOPLEFT",8,-37); row.actual:SetPoint("TOPRIGHT",-8,-37); row.actual:SetJustifyH("LEFT")
            row.rareIcon = row:CreateTexture(nil, "OVERLAY")
            row.rareIcon:SetSize(28, 28); row.rareIcon:SetPoint("LEFT", 2, 0)
            row.rareIcon:SetAtlas("ui-hud-unitframe-target-portraiton-boss-rare-silver")
            row:SetScript("OnClick", function(button)
                state.seriesStep = button.bossIndex
                local selected = state.seriesPicks[state.seriesStep]
                state.selectedGUID = selected and selected.guid or nil; state.selectedName = selected and selected.name or nil
                if button.locked then Print("This boss has started or been scored. Its prediction is locked.") end
                Gamble:Refresh()
            end)
            self.seriesPopupRows[index] = row
        end
        local pick = state.seriesPicks[index]
        local down = state.active and state.active.seriesResults[index]
        local running = state.active and state.active.currentSeriesBoss == index
        local locked = down or running
        row.bossIndex, row.locked = index, locked and true or false
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -((index - 1) * rowHeight)); row:SetHeight(rowHeight-4)
        row.actual:SetShown(not not showResults)
        if showResults then row.actual:SetText(GambleDamageBets:BossResultText(state.active,index)) end
        local rare = GambleData.IsRareBoss(boss)
        row.rareIcon:SetShown(rare)
        row.boss:ClearAllPoints(); row.boss:SetPoint("TOPLEFT", rare and 34 or 8, -5); row.boss:SetPoint("TOPRIGHT", -8, -5)
        row.pick:ClearAllPoints(); row.pick:SetPoint("TOPLEFT", rare and 34 or 8, -21); row.pick:SetPoint("TOPRIGHT", -8, -21)
        local unavailableLabel=state.active and state.active.mode=="BOSS_DAMAGE_SERIES" and " |cffff5555[DMG NICHT LESBAR]|r" or " |cffaaaaaa[SKIPPED]|r"
        row.boss:SetText(index .. ". " .. boss.name .. (rare and " |cffaaaaaa[OPTIONAL RARE]|r" or "") .. (down and (down.name == "Not scored" and unavailableLabel or " |cffff3333[DOWN]|r") or (running and " |cffffd100[RUNNING]|r" or "")))
        row.pick:SetText("Your prediction: " .. (pick and ClassColoredName(pick.guid, pick.name) or "|cffff5555not selected|r"))
        if state.active and state.active.mode=="BOSS_DAMAGE_SERIES" and pick then
            local names={}
            for place,guid in ipairs(GambleDamageBets:Decode(pick.guid)) do
                local member = (state.active.snapshot or {})[guid] or FindRosterByGUID(guid)
                local name=DisplayName(member and member.name or "Unbekannter Spieler")
                names[#names+1]=place..". "..GambleDamageBets:PredictionName(state.active,index,place,guid,name)
            end
            row.pick:SetText(#names>0 and table.concat(names," / ") or "|cffff5555Noch kein Tipp – Auswahl vor dem Boss-Pull|r")
        end
        row.bg:SetColorTexture(index == state.seriesStep and .22 or .08, index == state.seriesStep and .17 or .08, .04, .9)
        row:Show()
    end
    self.seriesPopupContent:SetHeight(max(1, #(bosses or {}) * rowHeight))
end

function Gamble:UpdateUnstartedSeries()
    local a = state.active
    if not a or not IsBossSeries(a.mode) or not a.setupPending or a.locked or a.result then return end
    if a.mode=="BOSS_DAMAGE_SERIES" then return end -- authoritative list is fixed when created
    ReadSavedBossDefeats(ResolveInstanceDataName(a.instanceName or ""))
    local bosses,picks={},{}
    for i,boss in ipairs(a.bosses or {}) do
        if not IsBossDefeated(a.instanceName,boss.name,boss.encounterID) then
            bosses[#bosses+1]=boss; picks[#bosses]=state.seriesPicks[i]
        end
    end
    if #bosses == #(a.bosses or {}) then return end
    a.bosses=bosses; state.seriesPicks=picks; state.seriesStep=math.min(state.seriesStep,math.max(1,#bosses))
    local pick=picks[state.seriesStep]
    state.selectedGUID=pick and pick.guid or nil; state.selectedName=pick and pick.name or nil
    SaveSession()
end

function Gamble:RefreshDetailsPopup(wager, text)
    if not self.detailsPopup then return end
    if not wager then
        self.detailsButton:Hide(); self.detailsPopup:Hide()
        return
    end
    self.detailsButton:Show()
    self.detailsButton:SetText(self.detailsPopup:IsShown() and "Hide Payments" or "Show Payments")
    self.detailsPopup.TitleText:SetText("Gamble - " .. BetLabel(wager.mode))
    self.detailsText:SetText((text and text ~= "") and text or "No stakes or results yet.")
    self.detailsContent:SetHeight(max(1, self.detailsText:GetStringHeight() + 12))
    local hasExternalParticipant = false
    for player in pairs(wager.paymentStatus or {}) do
        if not SamePlayer(player, wager.host) then hasExternalParticipant = true; break end
    end
    if not hasExternalParticipant then
        for _, bet in pairs(wager.bets or {}) do
            if not SamePlayer(bet.bettor, wager.host) then hasExternalParticipant = true; break end
        end
    end
    if hasExternalParticipant and not self.detailsPopup.autoOpened[wager.id] then
        self.detailsPopup.autoOpened[wager.id] = true
        self.detailsPopup:Show(); self.detailsPopup:Raise()
        self.detailsButton:SetText("Hide Payments")
    end
end

local function ActiveWagers()
    local wagers = {}
    if GambleRPS then local rps=GambleRPS:GetRunningCard(); if rps then wagers[#wagers+1]=rps end end
    for _, wager in ipairs(state.wagers or {}) do
        if not wager.hostMissing and not (wager.result and wager.result.cancelled) then wagers[#wagers + 1] = wager end
    end
    if GambleDON and GambleDON.GetRunningCard then
        local don = GambleDON:GetRunningCard()
        if don then wagers[#wagers + 1] = don end
    end
    table.sort(wagers, function(left, right) return (tonumber(left.createdAt) or 0) > (tonumber(right.createdAt) or 0) end)
    return wagers
end

local function WagerStartedAt(wager)
    return tonumber(wager.createdAt) or tonumber(tostring(wager.id or ""):match("^(%d+)")) or time()
end

local function FormatDuration(seconds)
    seconds = max(0, floor(tonumber(seconds) or 0))
    local minutes = floor(seconds / 60)
    return minutes > 0 and (minutes .. " min " .. (seconds % 60) .. " sek") or (seconds .. " sek")
end

function Gamble:SelectBettingTab(tab)
    self.uiTab = tab == "RUNNING" and "RUNNING" or "NEW"
    self.detailWagerID = nil
    state.active = nil
    if self.uiTab == "NEW" then
        state.selectedType = nil; state.selectedBoss = nil; state.selectedGUID = nil; state.selectedName = nil
        wipe(state.seriesPicks); state.seriesStep = 1; wipe(state.lootItems)
        UIDropDownMenu_SetText(self.typeDropdown, "Select a bet type …")
        UIDropDownMenu_SetText(self.bossDropdown, "Boss: auto-detect")
    end
    self:Refresh()
end

function Gamble:ShowWagerDetails(wager)
    if not wager then return end
    if wager.rps and GambleRPS then GambleRPS:ShowDetails(); return end
    if wager.don and GambleDON and GambleDON.ShowDetails then GambleDON:ShowDetails(); return end
    self.uiTab = "DETAIL"; self.detailWagerID = wager.id; state.active = wager
    local own = OwnBet(wager)
    SetMoneyBoxes(own and own.stake or wager.minimum)
    if not SamePlayer(wager.host, PlayerName()) then Send("BET_READY_GET", wager.id) end
    wipe(state.seriesPicks); state.seriesStep = 1
    self:Refresh()
end

function Gamble:SetFormAreaVisible(visible)
    for _, widget in ipairs({ self.typeDropdown, self.status, self.rosterHint, self.rosterScroll, self.goldBox, self.silverBox, self.copperBox, self.actionButton, self.resultsLine, self.betsTitle, self.detailsButton, self.payButton }) do
        if widget and (widget ~= self.payButton or not (InCombatLockdown and InCombatLockdown())) then widget:SetShown(visible and true or false) end
    end
    if not visible then
        self.bossDropdown:Hide(); self.itemHint:Hide(); self.previousBossButton:Hide(); self.nextBossButton:Hide(); self.seriesReviewButton:Hide(); self.cancelButton:Hide()
        if self.seriesPopup then self.seriesPopup:Hide() end
        if self.detailsPopup then self.detailsPopup:Hide() end
    end
end

function Gamble:RefreshRunningCards(wagers)
    for _, card in ipairs(self.runningCards) do card:Hide() end
    if self.emptyRunningCard then self.emptyRunningCard:Hide() end
    self.runningTitle:SetText("Active Bets (" .. #wagers .. ")")
    if #wagers == 0 then
        local card = self.emptyRunningCard
        if not card then
            card = CreateFrame("Frame", nil, self.runningContent, "BackdropTemplate")
            card:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
            card.text = card:CreateFontString(nil, "OVERLAY", "GameFontDisable")
            card.text:SetPoint("CENTER")
            self.emptyRunningCard = card
        end
        card:SetPoint("TOPLEFT", 2, -2); card:SetSize(440, 90); card.text:SetText("No active bets."); card:Show()
        self.runningContent:SetHeight(96); return
    end
    for index, wager in ipairs(wagers) do
        local card = self.runningCards[index]
        if not card or not card.details then
            card = CreateFrame("Frame", nil, self.runningContent, "BackdropTemplate")
            card:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
            card:SetBackdropColor(.04, .10, .035, .96); card:SetBackdropBorderColor(.85, .65, .08, 1)
            card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); card.title:SetPoint("TOPLEFT", 14, -12); card.title:SetPoint("TOPRIGHT", -90, -12); card.title:SetJustifyH("CENTER")
            card.context = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); card.context:SetPoint("TOPLEFT", 14, -38); card.context:SetPoint("TOPRIGHT", -14, -38); card.context:SetJustifyH("CENTER")
            card.pick = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); card.pick:SetPoint("TOPLEFT", 14, -58); card.pick:SetPoint("TOPRIGHT", -14, -58); card.pick:SetJustifyH("CENTER")
            card.age = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); card.age:SetPoint("BOTTOMLEFT", 14, 12)
            card.running = card:CreateFontString(nil, "OVERLAY", "GameFontNormal"); card.running:SetPoint("TOPRIGHT", -14, -14); card.running:SetText("|cff55ff55RUNNING|r")
            card.statusDot = card:CreateTexture(nil, "OVERLAY"); card.statusDot:SetSize(16, 16); card.statusDot:SetPoint("RIGHT", card.running, "LEFT", -5, 0); card.statusDot:SetAtlas("AlliedRace-UnlockingFrame-Checkmark", false)
            card.details = MakeButton(card, 92, 24, "Details"); card.details:SetPoint("BOTTOMRIGHT", -12, 9); card.details:SetScript("OnClick", function(button)
                local selected = button:GetParent().wager
                if selected and selected.rps and GambleRPS then GambleRPS:ShowDetails()
                elseif selected and selected.don and GambleDON and GambleDON.ShowDetails then GambleDON:ShowDetails() else Gamble:ShowWagerDetails(selected) end
            end)
            self.runningCards[index] = card
        end
        card.wager = wager; card:ClearAllPoints(); card:SetPoint("TOPLEFT", 2, -2 - ((index - 1) * 124)); card:SetSize(440, 114)
        local own = not wager.don and OwnBet(wager) or nil
        local cardTitle = BetLabel(wager.mode)
        if not wager.don and not IsBossSeries(wager.mode) and wager.bossName and wager.bossName ~= "" then
            cardTitle = cardTitle .. " – " .. wager.bossName
        end
        card.title:SetText(cardTitle)
        if wager.rps then
            card.context:SetText(wager.context or "Mehrspieler")
            card.pick:SetText(wager.minimum==0 and "Pussy Mode" or ("Einsatz pro Spieler: "..Money(wager.minimum)))
        elseif wager.don then
            card.context:SetText(wager.context or "Multiplayer dice game")
            card.pick:SetText(wager.summary or "")
        else
            card.context:SetText((wager.bossName and wager.bossName ~= "" and ("Boss: " .. wager.bossName)) or (wager.context and wager.context ~= "" and wager.context) or "Boss: auto-detect")
            card.pick:SetText("Your prediction: " .. (own and (own.targetName and DisplayName(own.targetName) or "Boss series selected") or "not joined") .. "    Stake: " .. Money(own and own.stake or wager.minimum))
        end
        card.age:SetText("Age: " .. FormatDuration(time() - WagerStartedAt(wager)))
        if wager.result then
            card.running:SetText("|cffff5555FINISHED|r")
            card.statusDot:Hide()
        else
            card.running:SetText("|cff55ff55RUNNING|r")
            card.statusDot:Show()
        end
        card:Show()
    end
    self.runningContent:SetHeight(max(1, #wagers * 124))
end

function Gamble:RefreshBettingNavigation()
    local wagers = ActiveWagers()
    if not self.uiTab then
        if state.active then self.uiTab = "DETAIL"; self.detailWagerID = state.active.id
        else self.uiTab = #wagers > 0 and "RUNNING" or "NEW" end
    end
    local runningView = self.uiTab == "RUNNING"
    local runningTabActive = self.uiTab == "RUNNING" or self.uiTab == "DETAIL" or self.uiTab == "DON_DETAIL" or self.uiTab == "RPS_DETAIL"
    local function StyleTab(button, active)
        button:Enable()
        button:SetBackdropColor(active and .42 or .08, active and .015 or .08, active and .015 or .08, .98)
        button:SetBackdropBorderColor(active and 1 or .38, active and .68 or .38, active and .05 or .38, 1)
        button:GetFontString():SetTextColor(active and 1 or .72, active and .82 or .72, active and .15 or .72)
    end
    StyleTab(self.newBetTab, self.uiTab == "NEW")
    StyleTab(self.runningBetsTab, runningTabActive)
    self.runningBetsTab:SetText(#wagers > 0 and ("Active Bets (" .. #wagers .. ")") or "Active Bets (0)")
    self.activeBanner:Hide()
    self.runningTitle:SetShown(runningView); self.runningScroll:SetShown(runningView)
    if runningView then self:RefreshRunningCards(wagers) end
    return runningView
end

function Gamble:Refresh()
    GambleDamageBets.main=self
    if not self.frame then return end
    if GambleUIStyle then GambleUIStyle:SetBetActive(self.actionButton,false) end
    if self.finishSeriesButton then self.finishSeriesButton:Hide() end
    if GambleRPS then GambleRPS:SyncSettlement() end
    if GambleBankSecurity and GambleBankSecurity.GetOpenPayments then
        local don=GambleDON and GambleDON.GetRunningCard and GambleDON:GetRunningCard()
        for _,payment in ipairs(GambleBankSecurity:GetOpenPayments()) do
            local queued=false
            for _,existing in ipairs(state.payments) do
                if existing.wagerID==payment.wagerID and SamePlayer(existing.name,payment.name) and existing.amount==payment.amount then queued=true; break end
            end
            if not queued and not (don and don.id=="DON:"..payment.wagerID) then state.payments[#state.payments+1]=payment end
        end
    end
    self.rulesText:SetShown(self.uiTab == "NEW" and state.selectedType ~= nil and state.selectedType ~= "DOUBLE_OR_NOTHING" and state.selectedType ~= "ROCK_PAPER_SCISSORS")
    if state.selectedType then self.rulesText:SetText(self:GetRules(state.selectedType)) end
    if GambleBankSecurity then GambleBankSecurity:SyncFromRuntime(state.wagers, state.payments, PlayerName()) end
    if GambleDON and GambleDON.SetMainController then GambleDON:SetMainController(self) end
    if GambleRPS then GambleRPS:SetMainController(self); GambleRPS:HideEmbedded() end
    self:RefreshVersionLabel()
    self:RefreshWinnerPopup()
    self:RefreshEscrowPopup()
    if self.uiTab == "NEW" then state.active = nil
    elseif self.uiTab == "RPS_DETAIL" then state.active=nil
    elseif self.uiTab == "DETAIL" and self.detailWagerID then state.active = FindWager(self.detailWagerID) end
    local runningListVisible = self:RefreshBettingNavigation()
    if GambleDamageRace then GambleDamageRace:Render(self, state.active, state.active and state.active.mode or state.selectedType, state.active and SamePlayer(state.active.host, PlayerName())) end
    local showInstance=self.uiTab=="NEW" and not state.active and (IsBossSeries(state.selectedType) or state.selectedType=="NEXT_BOSS" or state.selectedType=="LAST_MAN_STANDING" or state.selectedType=="ITEM_DROP" or IsEncounterBetMode(state.selectedType)) or false
    self.instanceDropdown:SetShown(showInstance)
    if state.active and state.active.mode~="BOSS_DAMAGE_SERIES" and state.active.awaitingStart and SamePlayer(state.active.host,PlayerName()) and self:CanStartBet(state.active) then
        self:StartReadyBet(state.active, true)
    end
    self:UpdateUnstartedSeries()
    if GambleReadyCheck then GambleReadyCheck:Render(self, state.active, self.uiTab == "DETAIL" and not runningListVisible, SamePlayer, PlayerName(), Send) end
    if runningListVisible then
        self:SetFormAreaVisible(false)
        if GambleDON and GambleDON.HideEmbedded then GambleDON:HideEmbedded() end
        self:RefreshDetailsPopup(nil)
        return
    end
    local rpsView=(self.uiTab=="NEW" and state.selectedType=="ROCK_PAPER_SCISSORS") or self.uiTab=="RPS_DETAIL"
    if rpsView and GambleRPS then
        self:SetFormAreaVisible(false); self.typeDropdown:SetShown(self.uiTab=="NEW")
        if GambleDON then GambleDON:HideEmbedded() end
        GambleRPS:RenderEmbedded(self,self.uiTab=="NEW"); self:RefreshDetailsPopup(nil); return
    end
    local donView = (self.uiTab == "NEW" and state.selectedType == "DOUBLE_OR_NOTHING") or self.uiTab == "DON_DETAIL"
    if donView and GambleDON and GambleDON.RenderEmbedded then
        self:SetFormAreaVisible(false)
        self.typeDropdown:SetShown(self.uiTab == "NEW")
        GambleDON:RenderEmbedded(self, self.uiTab == "NEW")
        self:RefreshDetailsPopup(nil)
        return
    elseif GambleDON and GambleDON.HideEmbedded then GambleDON:HideEmbedded() end
    self:SetFormAreaVisible(true)
    local activeBeforeRoster = state.active
    if activeBeforeRoster and activeBeforeRoster.mode == "ITEM_DROP" and #state.lootItems == 0 then
        LoadCurrentInstanceBosses()
        for _, boss in ipairs(state.bosses) do
            if (activeBeforeRoster.bossEncounterID and boss.encounterID == activeBeforeRoster.bossEncounterID) or BossNameMatches(boss.name, activeBeforeRoster.bossName) then
                state.selectedBoss = boss; LoadBossLoot(boss); break
            end
        end
    end
    if activeBeforeRoster and IsBossSeries(activeBeforeRoster.mode) and not activeBeforeRoster.result and #state.seriesPicks == 0 then
        for _, bet in pairs(activeBeforeRoster.bets or {}) do
            if SamePlayer(bet.bettor, PlayerName()) and bet.picks then
                for i, pick in ipairs(bet.picks) do state.seriesPicks[i] = { guid = pick.guid, name = pick.name } end
                break
            end
        end
    end
    state.seriesPicks=GambleDamageBets:PreparePicks(state.active,state.seriesPicks)
    self:RefreshRoster()
    local a = state.active
    self.typeDropdown:SetShown(self.uiTab ~= "DETAIL")
    if a then UIDropDownMenu_DisableDropDown(self.typeDropdown) else UIDropDownMenu_EnableDropDown(self.typeDropdown) end
    local configured = a or state.selectedType
    if not a and not state.preselectedInstance then
        local automatic=BettingCreationInstanceName()
        UIDropDownMenu_SetText(self.instanceDropdown,automatic and ("Automatic: "..automatic) or "Instance: automatic")
    end
    local bossMode = a and (a.mode == "NEXT_BOSS" or a.mode == "LAST_MAN_STANDING" or a.mode == "ITEM_DROP" or IsEncounterBetMode(a.mode))
    local itemMode = a and a.mode == "ITEM_DROP"
    local seriesEditing = (a and IsBossSeries(a.mode) and not a.result) and true or false
    local seriesBosses = a and IsBossSeries(a.mode) and a.bosses or state.bosses
    self:RefreshSeriesSummary(seriesEditing or (a and a.mode=="BOSS_DAMAGE_SERIES" and a.result and not a.result.cancelled), seriesBosses)
    self.previousBossButton:SetShown(seriesEditing); self.nextBossButton:SetShown(seriesEditing)
    if seriesEditing then
        if state.seriesStep > 1 then self.previousBossButton:Enable() else self.previousBossButton:Disable() end
        if state.seriesStep < #seriesBosses then self.nextBossButton:Enable() else self.nextBossButton:Disable() end
    end
    local hostSetup = a and a.setupPending and SamePlayer(a.host, PlayerName())
    self.bossDropdown:SetShown(bossMode and (self.uiTab ~= "DETAIL" or hostSetup) and true or false)
    self.itemHint:SetShown(itemMode and not a and not state.selectedBoss)
    if a and not hostSetup then UIDropDownMenu_DisableDropDown(self.bossDropdown) else UIDropDownMenu_EnableDropDown(self.bossDropdown) end
    self.rosterHint:SetShown(a and not GambleDamageBets:IsMode(a.mode) or false)
    self.rosterScroll:SetShown(a and true or false)
    self.goldBox:SetShown(configured and true or false)
    self.silverBox:SetShown(configured and true or false)
    self.copperBox:SetShown(configured and true or false)
    self.actionButton:SetShown(configured and true or false)
    local canFinishSeries = a and IsBossSeries(a.mode) and a.locked and not a.result and SamePlayer(a.host, PlayerName())
    self.cancelButton:SetShown(a and SamePlayer(a.host, PlayerName()) and not a.result and (not a.locked or canFinishSeries))
    self.cancelButton:Enable(); self.cancelButton:SetText(a and a.cancelVote and "Withdraw cancellation request" or "Cancel Bet")
    if self.finishSeriesButton then self.finishSeriesButton:SetShown(canFinishSeries and not a.cancelVote or false) end
    if not a then
        if not state.selectedType then
            self.status:SetText("Search above and select a bet type.")
        else
            self.status:SetText("Set the minimum stake first. Configure the bet in the lobby.")
        end
        self.actionButton:SetText("Create Game"); self.actionButton:Enable()
        self.betsText:SetText("Creating the bet opens a lobby for your group.")
        self:RefreshDetailsPopup(nil)
        if CurrentStake() <= 0 then self.actionButton:Disable() end
        if CurrentStake() > PlayerMoney() then self.actionButton:Disable(); self.actionButton:SetText("Not Enough Gold") end
        if not (InCombatLockdown and InCombatLockdown()) then
            if #state.payments > 0 then local payment=self:GetGroupedPayment(); self.payButton:Enable(); self.payButton:SetText("Pay: " .. DisplayName(payment.name) .. " " .. Money(payment.amount)) else self.payButton:Disable(); self.payButton:SetText("No pending payment") end
        end
        return
    end
    state.selectedType = a.mode
    UIDropDownMenu_SetText(self.typeDropdown, BetLabel(a.mode))
    if a.mode == "NEXT_BOSS" or a.mode == "LAST_MAN_STANDING" or a.mode == "ITEM_DROP" or IsEncounterBetMode(a.mode) then UIDropDownMenu_SetText(self.bossDropdown, a.bossName ~= "" and ("Boss: " .. a.bossName) or "Boss: auto-detect") end
    if a.setupPending then
        if SamePlayer(a.host, PlayerName()) then
            if IsBossSeries(a.mode) then
                local boss = a.bosses[state.seriesStep]
                self.status:SetText(SeriesPicksComplete(state.seriesPicks, a.bosses) and "Setup complete – open the lobby for participation." or (boss and ("Boss " .. state.seriesStep .. "/" .. #a.bosses .. ": " .. boss.name .. " – choose your prediction.") or "No boss list available."))
            elseif a.mode == "ITEM_DROP" then
                self.status:SetText(not state.selectedBoss and "Select the boss, then your item." or "Choose your item for " .. state.selectedBoss.name .. ".")
            else
                self.status:SetText((a.mode == "NEXT_BOSS" or a.mode == "LAST_MAN_STANDING" or IsEncounterBetMode(a.mode)) and "Select the boss and your prediction, then open the lobby." or "Choose your prediction, then open the lobby.")
            end
            self.actionButton:SetText("Open Lobby"); self.actionButton:Enable()
            if IsBossSeries(a.mode) and not SeriesPicksComplete(state.seriesPicks, a.bosses) then self.actionButton:Disable() end
            if not IsBossSeries(a.mode) and not state.selectedGUID then self.actionButton:Disable(); self.actionButton:SetText("Choose Prediction First") end
            if (a.mode == "NEXT_BOSS" or a.mode == "LAST_MAN_STANDING" or a.mode == "ITEM_DROP" or IsEncounterBetMode(a.mode)) and not state.selectedBoss then self.actionButton:Disable(); self.actionButton:SetText("Choose Boss First") end
        else
            self.status:SetText("The lobby is open. The host is configuring the bet.")
            self.actionButton:SetText("Join & Pay Stake"); self.actionButton:Enable()
            if IsBossSeries(a.mode) then
                if not SeriesPicksComplete(state.seriesPicks, a.bosses) then self.actionButton:Disable(); self.actionButton:SetText("Choose Boss Predictions First") end
            elseif not state.selectedGUID then self.actionButton:Disable(); self.actionButton:SetText("Choose Prediction First") end
            if CurrentStake() < a.minimum then self.actionButton:Disable(); self.actionButton:SetText("Minimum " .. Money(a.minimum)) end
            if OwnBet(a) and not state.pendingJoin and CurrentStake() <= OwnBet(a).stake then self.actionButton:Hide() end
        end
    elseif a.result then
        self.status:SetText(a.result.encounterBet and (a.result.ambiguous and a.result.name or ("Result: " .. tostring(a.result.outcome or "finished"))) or (a.result.lms and (a.result.void and a.result.name or ("LAST MAN STANDING: " .. a.result.name)) or (a.result.series and "Boss series complete – see the final scores below." or (a.result.item and (a.result.itemMiss and "No correct item prediction – jackpot rolls over." or ("Match: " .. a.result.name)) or (a.result.void and ("Bet finished: " .. a.result.name) or ("Result: " .. DisplayName(a.result.name) .. " died first."))))))
        if a.result.encounterBet and a.result.ambiguous and SamePlayer(a.host, PlayerName()) then
            self.actionButton:SetText(state.selectedGUID and "Confirm Host Result" or "Choose Winning Option")
            self.actionButton:SetEnabled(EncounterOption(a.mode, state.selectedGUID) and true or false)
        else self.actionButton:SetText("Back to Lobby"); self.actionButton:Enable() end
    elseif a.mode == "LAST_MAN_STANDING" and a.lmsAmbiguous then
        self.status:SetText("AMBIGUOUS – first death could not be determined. The host must review the result.")
        if SamePlayer(a.host, PlayerName()) then
            self.actionButton:SetText(state.selectedGUID and "Confirm LMS Result" or "Choose Candidates")
            self.actionButton:SetEnabled(state.selectedGUID and true or false)
        else
            self.actionButton:SetText("Host Reviewing Result"); self.actionButton:Disable()
        end
    elseif a.cancelVote then
        self.status:SetText("Cancellation requested – awaiting participant approval.")
        self.actionButton:SetText("Vote in Progress"); self.actionButton:Disable()
    elseif a.locked and not IsBossSeries(a.mode) then
        if IsEncounterBetMode(a.mode) then
            local tracker = a.encounterTracker or {}
            local live
            if a.mode == "BOSS_HP_WIPE" then live = tracker.lastBossHP and string.format("Boss HP: %.1f %%", tracker.lastBossHP) or "Boss HP: --"
            elseif a.mode == "PULL_TIMER_DEATH" then
                local elapsed = max(0, (GetTime and GetTime() or time()) - (tracker.startedAt or (GetTime and GetTime() or time())))
                live = tracker.firstDeath and string.format("First Death: %s – %.2fs", DisplayName(tracker.firstDeath.name), tracker.firstDeath.elapsed or 0) or string.format("Timer: %02d:%04.1f · First Death: --", floor(elapsed / 60), elapsed % 60)
            else live = "Deaths: " .. tostring(tracker.totalDeaths or 0) end
            self.status:SetText(BetLabel(a.mode) .. " – " .. live .. " · Betting closed.")
        else
            self.status:SetText(IsBossSeries(a.mode) and ("Boss series in progress – " .. (a.completedBosses or 0) .. "/" .. #a.bosses .. " scored.") or (((a.mode == "NEXT_BOSS" or a.mode == "LAST_MAN_STANDING" or a.mode == "ITEM_DROP") and ("Boss encounter " .. (a.encounterName or a.bossName or "") .. " in progress") or "Pull in progress") .. " – Betting closed."))
        end
        self.actionButton:SetText("Bet in Progress"); self.actionButton:Disable()
        if GambleUIStyle then GambleUIStyle:SetBetActive(self.actionButton,true) end
    else
        if IsBossSeries(a.mode) then
            local boss = a.bosses[state.seriesStep]
            self.status:SetText(a.mode=="BOSS_DAMAGE_SERIES" and "Boss rechts wählen – Platzierungen vor dem jeweiligen Pull hier setzen." or (SeriesPicksComplete(state.seriesPicks, a.bosses) and ("All " .. #a.bosses .. " predictions complete – pay your stake or review your picks.") or (boss and ("Boss " .. state.seriesStep .. "/" .. #a.bosses .. ": " .. boss.name .. " – choose your prediction. Minimum " .. Money(a.minimum)) or "All predictions selected – pay your stake.")))
        else self.status:SetText(BetLabel(a.mode) .. " · " .. (a.context ~= "" and (a.context .. " · ") or "") .. "Minimum " .. Money(a.minimum)) end
        local pendingNames = PendingPaymentNames(a)
        if #pendingNames > 0 then self.status:SetText("Awaiting payment from: " .. table.concat((function() local names = {}; for _, name in ipairs(pendingNames) do names[#names + 1] = DisplayName(name) end; return names end)(), ", ")) end
        local enteredStake = CurrentStake()
        local ownBet = OwnBet(a)
        if SamePlayer(a.host, PlayerName()) then
            self.actionButton:SetText("Change Prediction")
        elseif ownBet and state.pendingJoin then
            self.actionButton:SetText("Reopen Trade")
        elseif ownBet and enteredStake > ownBet.stake then
            self.actionButton:SetText("Change Pick & Pay Increase")
        elseif ownBet then
            self.actionButton:SetText("Change Prediction")
        else
            self.actionButton:SetText(state.pendingJoin and "Reopen Trade" or "Join & Pay Stake")
        end
        self.actionButton:Enable()
        if IsBossSeries(a.mode) and not SeriesPicksComplete(state.seriesPicks, a.bosses) then self.actionButton:Disable() end
        if not IsBossSeries(a.mode) and not state.selectedGUID then self.actionButton:Disable(); self.actionButton:SetText("Choose Prediction First") end
        if ownBet and enteredStake < ownBet.stake then
            self.actionButton:Disable(); self.actionButton:SetText("At least " .. Money(ownBet.stake))
        elseif enteredStake < a.minimum then
            self.actionButton:Disable(); self.actionButton:SetText("Minimum " .. Money(a.minimum))
        elseif a.mode == "LAST_MAN_STANDING" and enteredStake ~= a.minimum then
            self.actionButton:Disable(); self.actionButton:SetText("Exact stake: " .. Money(a.minimum))
        elseif (ownBet and (enteredStake - ownBet.stake) or enteredStake) > PlayerMoney() then
            self.actionButton:Disable(); self.actionButton:SetText("Not Enough Gold")
        end
    end
    if not a.result and not a.locked and not a.setupPending and OwnBet(a) and not state.pendingJoin and CurrentStake() <= OwnBet(a).stake then
        self.actionButton:Hide()
    end
    if a.mode == "DAMAGE_RACE" then
        if a.result then self.status:SetText("Result: " .. a.result.name)
        elseif a.locked then self.status:SetText("Damage Race in progress — betting closed.") end
    end
    if a.awaitingStart and SamePlayer(a.host,PlayerName()) and a.mode~="DAMAGE_RACE" and not a.result then
        local canStart=not a.setupPending and GambleReadyCheck:CountReady(a,SamePlayer)>=2
        if a.mode=="BOSS_DAMAGE_SERIES" then canStart=self:CanStartBet(a) end
        self.actionButton:Show(); self.actionButton:SetText(canStart and (a.mode=="BOSS_DAMAGE_SERIES" and "Boss-Serie freigeben" or "Start with Ready Players") or "Waiting for Ready & Payment"); self.actionButton:SetEnabled(canStart)
    end
    if a.awaitingStart == false and not a.result and a.mode~="DAMAGE_RACE" then
        self.actionButton:Show(); self.actionButton:SetText(a.mode=="BOSS_DAMAGE_SERIES" and a.rankAwaitingFinish and "Waiting for Host Decision" or "Bet Active"); self.actionButton:Disable()
        if GambleUIStyle then GambleUIStyle:SetBetActive(self.actionButton,true) end
    end
    local lines = {}
    local paymentPlayers, paymentByKey = {}, {}
    for player, status in pairs(a.paymentStatus or {}) do
        local key = CanonicalPlayerName(player)
        local existing = paymentByKey[key]
        if not existing or status == "PAID" then paymentByKey[key] = { player = player, status = status } end
    end
    for _, paymentEntry in pairs(paymentByKey) do paymentPlayers[#paymentPlayers + 1] = paymentEntry end
    table.sort(paymentPlayers, function(left, right) return left.player < right.player end)
    if #paymentPlayers > 0 then
        lines[#lines + 1] = "|cffffd45aPayment status:|r"
        for _, paymentEntry in ipairs(paymentPlayers) do
            local player, paid = paymentEntry.player, paymentEntry.status == "PAID"
            local bank = SamePlayer(player, a.host)
            lines[#lines + 1] = (paid and "|cff55ff55[PAID] " or "|cffff5555[PENDING] ") .. DisplayName(player) .. (paid and (bank and " – Bank / stake reserved|r" or " – paid|r") or " – payment pending|r")
        end
        if not AllPaymentsReceived(a) then lines[#lines + 1] = "|cffff5555Waiting for all outstanding payments.|r" end
        lines[#lines + 1] = ""
    end
    local payouts
    if a.mode == "LAST_MAN_STANDING" then
        lines[#lines + 1] = "|cffaaaaaaRule: Only each player's first death counts; battle resurrection and later deaths do not change the order.|r"
        lines[#lines + 1] = ""
    end
    if IsBossSeries(a.mode) and not a.locked then
        -- Die anklickbare Bossübersicht erklärt sich durch ihre hervorgehobenen Zeilen;
        -- kein zusätzlicher Text, der mit den unteren Schaltflächen kollidieren kann.
    end
    if a.result and not a.result.void and not a.result.series and not a.result.itemMiss then
        if a.result.encounterBet then payouts = a.encounterPayouts
        elseif a.result.lms then payouts = a.lmsPayouts else local _, _, p = ComputeResult(a.result.guid); payouts = a.itemPayouts or p end
    end
    for _, bet in ipairs(OrderedBets()) do
        if IsBossSeries(a.mode) then
            local score = a.seriesScores and a.seriesScores[bet.bettor] or 0
            local maximum = #a.bosses * (a.mode=="BOSS_DAMAGE_SERIES" and GambleDamageBets:Places(a) or 1)
            local lineText = DisplayName(bet.bettor) .. " – " .. score .. "/" .. maximum .. " points – " .. Money(bet.stake)
            if a.seriesPayouts and a.seriesPayouts[bet.bettor] then lineText = lineText .. "  |cffffd45aWinnings: " .. Money(a.seriesPayouts[bet.bettor]) .. "|r" end
            lines[#lines + 1] = lineText
        else
        local lmsWinners = a.result and a.result.lms and LMSWinnerMap(a) or nil
        local marker = a.result and (a.result.void and "- " or (((lmsWinners and lmsWinners[bet.targetGUID]) or (not lmsWinners and bet.targetGUID == a.result.guid)) and "|cff48d35b[Richtig]|r " or "|cffff5555[Falsch]|r ")) or "- "
            local targetText = (a.mode == "ITEM_DROP" or IsEncounterBetMode(a.mode) or a.mode=="DAMAGE_RACE") and bet.targetName or DisplayName(bet.targetName)
            if a.mode=="DAMAGE_RACE" then
                local names={}
                for place,guid in ipairs(GambleDamageBets:Decode(bet.targetGUID)) do
                    local member = (a.snapshot or {})[guid] or FindRosterByGUID(guid)
                    names[#names+1]=place..". "..DisplayName(member and member.name or "Unbekannter Spieler")
                end
                targetText=table.concat(names," / ")
            end
            local lineText = marker .. DisplayName(bet.bettor) .. " predicts " .. targetText .. " - " .. Money(bet.stake)
            if a.rankScores then lineText=lineText.." — "..(a.rankScores[bet.bettor] or 0).." points" end
        if payouts and payouts[bet.bettor] then lineText = lineText .. (a.result and a.result.noWinningBet and "  |cffffd45aRefund: " or "  |cffffd45aWinnings: ") .. Money(payouts[bet.bettor]) .. "|r" end
        if a.encounterPaidOut and a.encounterPaidOut[bet.bettor] then lineText = lineText .. "  |cff55ff55✓ AUSGEZAHLT|r" end
        lines[#lines + 1] = lineText
        end
    end
    if a.result and #lines == 0 then lines[1] = "No valid stakes." end
    if a.result and a.result.encounterBet then
        local total = 0; for _, bet in ipairs(OrderedBets()) do total = total + bet.stake end
        if a.mode == "BOSS_HP_WIPE" then
            lines[#lines + 1] = "RESULT: " .. tostring(a.result.outcome or "AMBIGUOUS")
            lines[#lines + 1] = a.result.value and string.format("Boss HP: %.1f %%", a.result.value) or "Boss HP: reliable data unavailable"
        elseif a.mode == "PULL_TIMER_DEATH" then
            lines[#lines + 1] = tostring(a.result.outcome or "FIRST DEATH")
            if a.result.winnerName then lines[#lines + 1] = ClassColoredName(nil, a.result.winnerName) end
            if a.result.elapsed then lines[#lines + 1] = string.format("%.2f seconds", a.result.elapsed) end
        else
            lines[#lines + 1] = "RESULT: " .. tostring(a.result.outcome or "ENCOUNTER END")
            lines[#lines + 1] = "TOTAL DEATHS: " .. tostring(a.result.value or 0)
            for _, death in ipairs(a.encounterTracker and a.encounterTracker.deaths or {}) do
                lines[#lines + 1] = string.format("#%d %s %02d:%02d", death.order or 0, DisplayName(death.name), floor((death.elapsed or 0) / 60), floor((death.elapsed or 0) % 60))
            end
        end
        local option = a.result.optionKey and EncounterOption(a.mode, a.result.optionKey)
        if option then lines[#lines + 1] = "Winning option: " .. option.label end
        lines[#lines + 1] = "Pot: " .. Money(total)
        if a.result.noWinningBet then lines[#lines + 1] = "NO WINNING BET – full refund." end
        if a.result.ambiguous then lines[#lines + 1] = "AMBIGUOUS – no automatic payout; host review required." end
    elseif a.result and a.result.itemMiss then
        lines[#lines + 1] = "Bank share: " .. Money(a.bankCut or 0) .. " · Rolled-over jackpot: " .. Money(a.itemRollover or 0)
    elseif a.result and a.result.item then
        lines[#lines + 1] = "Ausgezahlter Pot inklusive altem Jackpot: " .. Money((function() local sum = 0; for _, amount in pairs(a.itemPayouts or {}) do sum = sum + amount end; return sum end)())
    elseif a.result and a.result.series then
        lines[#lines + 1] = "Bank share from missed bosses: " .. Money(a.bankCut or 0)
    elseif a.result and a.result.lms and not a.result.void then
        lines[#lines + 1] = "|cffffd45aDeath Order (first death only):|r"
        local started = tonumber(a.lmsStartedAt) or ((a.lmsDeathOrder and a.lmsDeathOrder[1] and a.lmsDeathOrder[1].stamp) or 0)
        for index, death in ipairs(a.lmsDeathOrder or {}) do
            local elapsed = max(0, (tonumber(death.stamp) or started) - started)
            lines[#lines + 1] = string.format("%d. %s  %02d:%02d", index, DisplayName(death.name), floor(elapsed / 60), floor(elapsed % 60))
        end
        lines[#lines + 1] = "LAST MAN STANDING: " .. a.result.name
        local total = 0; for _, bet in ipairs(OrderedBets()) do total = total + bet.stake end
        lines[#lines + 1] = "Total pot: " .. Money(total)
    elseif a.result and not a.result.void then
        local _, _, _, total, winningStake = ComputeResult(a.result.guid)
        lines[#lines + 1] = winningStake == 0 and ("No correct prediction – refund. Pot: " .. Money(total)) or ("Total pot: " .. Money(total))
    elseif a.result and a.result.void then
        lines[#lines + 1] = a.result.cancelled and "Bet cancelled – all stakes will be refunded." or ((a.result.name or "Bet void") .. " – all stakes will be refunded.")
    end
    if a.result and a.result.rankedDamage then self.status:SetText(a.result.name) end
    if GambleDamageBets:IsMode(a.mode) then
        for index,ranking in pairs(a.rankResults or {}) do
            local places={}
            for place=1,3 do
                local names={}; for guid in pairs(ranking[place] or {}) do if a.snapshot[guid] then names[#names+1]=DisplayName(a.snapshot[guid].name) end end
                table.sort(names); if #names>0 then places[#places+1]=place..". "..table.concat(names,", ") end
            end
            lines[#lines+1]=(a.bosses[index] and a.bosses[index].name or "Damage Race")..": "..table.concat(places," / ")
        end
    end
    local detailsOutput = table.concat(lines, "\n")
    self.betsText:SetText(detailsOutput)
    self:RefreshDetailsPopup(a, detailsOutput)
    if #state.payments > 0 and not (InCombatLockdown and InCombatLockdown()) then
        local payment=self:GetGroupedPayment(); self.payButton:Enable(); self.payButton:SetText("Pay: " .. DisplayName(payment.name) .. " " .. Money(payment.amount))
    elseif #state.payments == 0 and not (InCombatLockdown and InCombatLockdown()) then
        self.payButton:Disable(); self.payButton:SetText("No pending payment")
    end
end

function Gamble:ApplySelectedPrediction()
    local a = state.active
    state.seriesPicks=GambleDamageBets:PreparePicks(a,state.seriesPicks)
    if a and a.awaitingStart == false then return end
    if a and a.setupPending and SamePlayer(a.host, PlayerName()) then
        local complete = IsBossSeries(a.mode) and SeriesPicksComplete(state.seriesPicks, a.bosses) or (not IsBossSeries(a.mode) and state.selectedGUID)
        local needsBoss = a.mode == "NEXT_BOSS" or a.mode == "LAST_MAN_STANDING" or a.mode == "ITEM_DROP" or IsEncounterBetMode(a.mode)
        if complete and (not needsBoss or state.selectedBoss) then self:PrimaryAction() end
        return
    end
    if not a or a.result or (a.setupPending and SamePlayer(a.host, PlayerName())) or (a.locked and not IsBossSeries(a.mode)) or state.pendingJoin then return end
    local own = OwnBet(a)
    if not own then return end
    -- Selection changes never increase stakes or initiate a new payment.
    local stake = own.stake
    if IsBossSeries(a.mode) then
        if not SeriesPicksComplete(state.seriesPicks, a.bosses) then return end
        if SamePlayer(a.host, PlayerName()) then
            if not AddSeriesBet(PlayerName(), state.seriesPicks, stake) then return end
            Send("SERIES_BET_BEGIN", a.id, PlayerName(), stake, #state.seriesPicks)
            for i, pick in ipairs(state.seriesPicks) do Send("SERIES_BET_PICK", a.id, PlayerName(), i, pick.guid, pick.name) end
        else
            Send("SERIES_EDIT_BEGIN", a.id, stake, 0, #state.seriesPicks)
            for i, pick in ipairs(state.seriesPicks) do Send("SERIES_EDIT_PICK", a.id, i, pick.guid, pick.name) end
        end
    else
        if not state.selectedGUID or own.targetGUID == state.selectedGUID then return end
        if SamePlayer(a.host, PlayerName()) then
            if not AddBet(PlayerName(), state.selectedGUID, state.selectedName, stake) then return end
            Send("CONFIRM", a.id, PlayerName(), state.selectedGUID, state.selectedName, stake)
        else Send("EDIT", a.id, state.selectedGUID, state.selectedName, stake) end
    end
    SaveSession()
end
function Gamble:PrimaryAction()
    state.seriesPicks=GambleDamageBets:PreparePicks(state.active,state.seriesPicks)
    local pending = state.active
    if pending and pending.awaitingStart and not pending.setupPending and SamePlayer(pending.host, PlayerName()) and not pending.result then
        self:StartReadyBet(pending, false); self:Refresh(); return
    end
    if state.active and state.active.result and state.active.result.encounterBet and state.active.result.ambiguous and SamePlayer(state.active.host, PlayerName()) then
        local a, option = state.active, EncounterOption(state.active.mode, state.selectedGUID)
        if not option then Print("Select the manually verified winning option first."); return end
        local oldResult = a.result
        a.result = nil
        FinalizeEncounterBet(a, option.key, "HOST REVIEW", oldResult.value, oldResult.winnerName, oldResult.elapsed, false, false, false)
        return
    end
    if state.active and state.active.result then
        RemoveWager(state.active); state.active = nil; state.selectedType = nil; state.selectedBoss = nil; wipe(state.seriesPicks); state.seriesStep = 1
        self.uiTab = "NEW"; self.detailWagerID = nil
        UIDropDownMenu_SetText(self.typeDropdown, "Select a bet type …"); self:Refresh(); return
    end
    if not IsInGroup() then Print("You must be in a party or raid."); return end
    local stake = CurrentStake()
    local a = state.active
    local moneyNeeded = stake
    if a then local prior = OwnBet(a); if prior then moneyNeeded = max(0, stake - prior.stake) end end
    if moneyNeeded > PlayerMoney() then Print("Not enough gold for this increase. Available: " .. Money(PlayerMoney()) .. "."); return end
    if not a then
        if not state.selectedType then Print("Select a bet type above first."); return end
        if GambleDamageBets:IsMode(state.selectedType) and (not GambleDamageRace or not GambleDamageRace:Available()) then Print("Damage Race unavailable: neither WoW Damage Meter nor readable combat logs are exposed."); return end
        if state.selectedType=="BOSS_DAMAGE_SERIES" and (not GambleDamageRace:NativeAvailable() or #state.bosses==0) then Print("Boss Damage Series requires WoW Damage Meter and a remaining boss list."); return end
        if stake <= 0 then Print("The stake must be greater th to 0."); return end
        if GambleBankSecurity then
            local allowed, reason = GambleBankSecurity:CanCreateFinancialObligation(stake, stake)
            if not allowed then Print("BET BLOCKED – " .. tostring(reason) .. ". Open Bank to check coverage and obligations."); return end
        end
        local id = tostring(time()) .. "-" .. tostring(math.random(1000, 9999))
        NewActive(id, PlayerName(), stake, nil, nil, stake, state.selectedType, "", "Lobby setup in progress", nil)
        if GambleBankSecurity then
            local registered, reason = GambleBankSecurity:RegisterWager(id, stake, stake)
            if not registered then RemoveWager(state.active); state.active = nil; Print("BET BLOCKED – " .. tostring(reason)); self:Refresh(); return end
        end
        state.active.setupPending = true
        if state.selectedType == "LAST_MAN_STANDING" then state.active.lmsState = "CREATED"; DebugLMS("BET_OPEN") end
        AnnounceWager(state.active)
        self.uiTab = "DETAIL"; self.detailWagerID = state.active.id
        Print("Lobby opened: " .. BetLabel(state.selectedType) .. ". Configure your bet now.")
        if state.active.mode=="BOSS_DAMAGE_SERIES" then self:PrimaryAction(); return end
    else
        if a.setupPending and SamePlayer(a.host, PlayerName()) then
            if not IsBossSeries(a.mode) and not state.selectedGUID then Print("Select a prediction first."); return end
            if (a.mode == "NEXT_BOSS" or a.mode == "LAST_MAN_STANDING" or a.mode == "ITEM_DROP" or IsEncounterBetMode(a.mode)) and not state.selectedBoss then Print("Select a boss first."); return end
            if IsBossSeries(a.mode) and not SeriesPicksComplete(state.seriesPicks, a.bosses) then Print("Select a prediction for each boss."); return end
            if a.mode == "NEXT_BOSS" or a.mode == "LAST_MAN_STANDING" or a.mode == "ITEM_DROP" or IsEncounterBetMode(a.mode) then
                a.bossName, a.context, a.bossEncounterID = BossContext()
            end
            if a.mode == "ITEM_DROP" then
                a.lootItems = {}
                for _, item in ipairs(state.lootItems) do a.lootItems[#a.lootItems + 1] = { id = item.id, name = item.name, link = item.link, icon = item.icon } end
            end
            a.setupPending = nil
            if a.mode == "DAMAGE_RACE" then
                local minutes = tonumber(GambleDamageRace.duration:GetText())
                if not minutes or minutes ~= floor(minutes) or minutes < 1 or minutes > 30 then a.setupPending = true; Print("Duration must be 1–30 whole minutes."); return end
                a.context = "Duration: " .. minutes .. " minutes"; a.damageDuration = minutes * 60
            end
            if a.mode == "LAST_MAN_STANDING" then a.lmsState = "BETTING_OPEN" end
            Send("CONFIG", a.id, a.bossName or "", a.bossEncounterID or "", a.context or "")
            if IsBossSeries(a.mode) then
                AddSeriesBet(PlayerName(), state.seriesPicks, stake)
                Send("SERIES_BET_BEGIN", a.id, PlayerName(), stake, #state.seriesPicks)
                for i, pick in ipairs(state.seriesPicks) do Send("SERIES_BET_PICK", a.id, PlayerName(), i, pick.guid, pick.name) end
            else
                AddBet(PlayerName(), state.selectedGUID, state.selectedName, stake)
                Send("CONFIRM", a.id, PlayerName(), state.selectedGUID, state.selectedName, stake)
            end
            Print("Lobby ready. Group members can now join.")
            self:Refresh(); return
        end
        if a.mode == "LAST_MAN_STANDING" and a.lmsAmbiguous then
            if SamePlayer(a.host, PlayerName()) and state.selectedGUID and a.snapshot[state.selectedGUID] then FinalizeLMS({ state.selectedGUID }, false, false) end
            return
        end
        if not state.selectedGUID and not IsBossSeries(a.mode) then Print(" an "); return end
        if (a.locked and not IsBossSeries(a.mode)) or a.result then return end
        if stake < a.minimum then Print("Minimum stake: " .. Money(a.minimum)); return end
        if a.mode == "LAST_MAN_STANDING" and stake ~= a.minimum then Print("Last Man Standing requires the same exact stake from everyone: " .. Money(a.minimum)); return end
        local previousBet = OwnBet(a)
        if previousBet and stake < previousBet.stake then Print("Stakes can only be increased. Previously confirmed: " .. Money(previousBet.stake) .. "."); return end
        if SamePlayer(a.host, PlayerName()) then
            if IsBossSeries(a.mode) then
                if not SeriesPicksComplete(state.seriesPicks, a.bosses) then Print("Complete all boss predictions."); return end
                if AddSeriesBet(PlayerName(), state.seriesPicks, stake) then
                    Send("SERIES_BET_BEGIN", a.id, PlayerName(), stake, #state.seriesPicks)
                    for i, pick in ipairs(state.seriesPicks) do Send("SERIES_BET_PICK", a.id, PlayerName(), i, pick.guid, pick.name) end
                end
            elseif AddBet(PlayerName(), state.selectedGUID, state.selectedName, stake) then
                Send("CONFIRM", a.id, PlayerName(), state.selectedGUID, state.selectedName, stake)
                Print("Your prediction was changed.")
            end
        else
            if IsBossSeries(a.mode) and not SeriesPicksComplete(state.seriesPicks, a.bosses) then Print("Complete all boss predictions."); return end
            local additionalStake = previousBet and (stake - previousBet.stake) or stake
            state.pendingJoin = { id = a.id, host = a.host, targetGUID = state.selectedGUID, targetName = state.selectedName, stake = additionalStake, totalStake = stake, picks = IsBossSeries(a.mode) and state.seriesPicks or nil }
            if additionalStake > 0 then SetPaymentStatus(a, PlayerName(), "PENDING") end
            if IsBossSeries(a.mode) then
                Send(additionalStake == 0 and "SERIES_EDIT_BEGIN" or "SERIES_JOIN_BEGIN", a.id, stake, additionalStake, #state.seriesPicks)
                for i, pick in ipairs(state.seriesPicks) do Send(additionalStake == 0 and "SERIES_EDIT_PICK" or "SERIES_JOIN_PICK", a.id, i, pick.guid, pick.name) end
            elseif additionalStake == 0 then
                Send("EDIT", a.id, state.selectedGUID, state.selectedName, stake)
            else Send("JOIN", a.id, state.selectedGUID, state.selectedName, stake, additionalStake) end
            if additionalStake == 0 then Print("Prediction change sent to the bank."); state.pendingJoin = nil; self:Refresh(); return end
            Print("Join request sent. Pay only the increase of " .. Money(additionalStake) .. "  to " .. a.host .. ".")
        end
    end
    self:Refresh()
end

function Gamble:BeginCancel(wager)
    local a = wager or state.active
    if a then state.active = a end
    if not a or a.result or (a.locked and not IsBossSeries(a.mode)) then Print("This bet can no longer be cancelled."); return end
    if not SamePlayer(a.host, PlayerName()) then Print("Only the bank can request cancellation."); return end
    if a.cancelVote then Print("Participant approval is already being requested."); return end
    local voters = {}
    for _, bet in ipairs(OrderedBets()) do
        if not SamePlayer(bet.bettor, a.host) then voters[bet.bettor] = false end
    end
    local count = 0; for _ in pairs(voters) do count = count + 1 end
    if count == 0 then FinalizeCancel(false); return end
    a.cancelVote = { voters = voters, required = count, accepted = 0 }
    Send("CANCEL_REQUEST", a.id)
    Print("Cancellation requested. All " .. count .. " participants must agree.")
    self:Refresh()
end

function Gamble:RequestCancel()
    local a = state.active
    if not a or a.result or (a.locked and not IsBossSeries(a.mode)) then Print("This bet can no longer be cancelled."); return end
    if not SamePlayer(a.host, PlayerName()) then Print("Only the bank can request cancellation."); return end
    if a.cancelVote then
        a.cancelVote = nil; Send("CANCEL_ABORT", a.id)
        Print("Cancellation request withdrawn. The bet remains open; you can request cancellation again.")
        self:Refresh(); return
    end
    StaticPopup_Show("GAMBLE_CANCEL_CONFIRM", nil, nil, a.id)
end

StaticPopupDialogs.GAMBLE_CANCEL_CONFIRM = {
    text = "Cancel this bet? Paid stakes will be refunded.",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function(_, wagerID)
        local wager = wagerID and FindWager(wagerID)
        if wager then Gamble:BeginCancel(wager) end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs.GAMBLE_CANCEL_REQUEST = {
    text = "%s wants to cancel the bet. Your full stake will be refunded. Agree?",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function(_, data) if data then Send("CANCEL_VOTE", data, "YES") end end,
    OnCancel = function(_, data) if data then Send("CANCEL_VOTE", data, "NO") end end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = false,
    preferredIndex = 3,
}

function Gamble:PayNext()
    local payment = self:GetGroupedPayment()
    if not payment then Print("No pending payment."); return end
    Print("Pending payout: Trade with " .. payment.name .. " and pay exactly " .. Money(payment.amount) .. ". Both players must accept the trade.")
    state.pendingTrade = payment
    if InCombatLockdown and InCombatLockdown() then Print("Payout remains pending. Prepare the trade after combat."); return end
    self.winnerFrame.payment = payment
    self.winnerFrame.TitleText:SetText("Gamble - Payout")
    self.winnerHeadline:SetText(payment.reason or "Payout")
    self.winnerName:SetText(payment.name)
    self.winnerAmount:SetText("Payout: " .. Money(payment.amount) .. "  to " .. DisplayName(payment.name))
    GambleTradeAction:Prepare(self.winnerTradeButton)
    self.winnerFrame:Show(); self.winnerFrame:Raise()
end

function Gamble:GetGroupedPayment(name)
    local first=state.payments[1]
    name=name or (first and first.name)
    if not name then return end
    local payment={name=name,amount=0,reason="Gesamtauszahlung",entries={}}
    for _,entry in ipairs(state.payments) do
        if SamePlayer(entry.name,name) then
            payment.amount=payment.amount+entry.amount
            payment.entries[#payment.entries+1]=entry
        end
    end
    if #payment.entries>0 then return payment end
end

local function TradePartnerName()
    return TradeFrameRecipientNameText and TradeFrameRecipientNameText:GetText() or nil
end

local function FindEscrowRequest(name)
    for sender, request in pairs(state.escrowRequests) do
        if SamePlayer(sender, name) then return sender, request end
    end
end

local function SetOfferedMoney(amount)
    local setter = C_TradeInfo and C_TradeInfo.SetTradeMoney or SetTradeMoney
    return setter and pcall(setter, amount)
end

local function ReadTargetTradeMoney()
    local getter = C_TradeInfo and C_TradeInfo.GetTargetTradeMoney or GetTargetTradeMoney
    if not getter then return nil end
    local ok, amount = pcall(getter)
    if not ok or not CanRead(amount) then return nil end
    amount = tonumber(amount)
    if not amount then return nil end
    amount = floor(amount)
    return amount >= 0 and amount or nil
end

function Gamble:CompleteEscrowTrade()
    local context = state.tradeContext
    if not context or context.direction ~= "incoming" or context.settled then return end
    local request = context.request
    if request and request.paymentProcessed then return end
    local a = request and FindWager(request.id)
    if not a or not SamePlayer(a.host, PlayerName()) then return end
    state.active = a
    local freshlyRead = ReadTargetTradeMoney()
    -- The trade APIs commonly reset to zero after a successful close. Keep the
    -- last live amount; live MONEY_CHANGED events still record a genuine zero.
    if freshlyRead and freshlyRead > 0 then context.offered = freshlyRead; context.moneyReadable = true end
    local actualStake = context.moneyReadable and floor(context.offered or 0) or floor(request.stake)
    if context.moneyReadable and actualStake < request.stake then
        Print("The trade from " .. request.bettor .. " contained insufficient gold; the prediction was not activated.")
        return
    end
    if not context.moneyReadable then
        Print("Forever could not read the trade amount. The confirmed stake of " .. Money(request.stake) .. " will be used; the bank must verify the trade amount.")
    end
    if request.picks then
        local picksComplete = true
        for i = 1, request.expected or #a.bosses do
            if not request.picks[i] then picksComplete = false; break end
        end
        if not picksComplete then
            request.receivedStake = actualStake
            Print("Stake received. Waiting for complete boss predictions; no refund is needed.")
            return
        end
    end
    if (a.locked and not IsBossSeries(a.mode)) or a.result or a.cancelVote then
        context.settled, request.paymentProcessed = true, true
        state.payments[#state.payments + 1] = { name = request.bettor, amount = actualStake, reason = "Too late – Refund" }
        ClearPaymentStatus(a, request.bettor); Send("PAYMENT_STATUS", a.id, request.bettor, "CANCELLED")
        state.escrowRequests[context.sender] = nil
        Print("The stake arrived after betting closed and was queued for a refund.")
        self:Refresh(); return
    end
    local _, previousBet = FindBetKey(a, request.bettor)
    local finalStake = (previousBet and floor(previousBet.stake or 0) or 0) + actualStake
    local added = request.picks and AddSeriesBet(request.bettor, request.picks, finalStake) or AddBet(request.bettor, request.targetGUID, request.targetName, finalStake)
    if added then
        context.settled, request.paymentProcessed = true, true
        SetPaymentStatus(a, request.bettor, "PAID")
        Send("PAYMENT_STATUS", a.id, request.bettor, "PAID")
        if request.picks then
            Send("SERIES_BET_BEGIN", a.id, request.bettor, finalStake, #request.picks)
            for i, pick in ipairs(request.picks) do Send("SERIES_BET_PICK", a.id, request.bettor, i, pick.guid, pick.name) end
        else Send("CONFIRM", a.id, request.bettor, request.targetGUID, request.targetName, finalStake) end
        state.escrowRequests[context.sender] = nil
        Print("Stake received: " .. request.bettor .. " now participates with a total stake of " .. Money(finalStake) .. ".")
        self:Refresh()
    else
        context.settled, request.paymentProcessed = true, true
        state.payments[#state.payments + 1] = { name = request.bettor, amount = actualStake, reason = IsBossSeries(a.mode) and "Incomplete boss predictions – Refund" or "Item already assigned – Refund" }
        ClearPaymentStatus(a, request.bettor); Send("PAYMENT_STATUS", a.id, request.bettor, "CANCELLED")
        state.escrowRequests[context.sender] = nil
        if IsBossSeries(a.mode) then
            Print("Boss predictions could not be fully matched. The full stake was queued for a refund.")
        else
            Print("The prediction could not be activated (e.g. item already assigned). The full stake was queued for a refund.")
        end
        self:Refresh()
    end
end

function Gamble:BindEscrowTrade(sender, request)
    local context = state.tradeContext
    local wager = request and FindWager(request.id)
    if not context or context.direction ~= "unassigned" or not wager or not SamePlayer(wager.host, PlayerName()) then return end
    if not SamePlayer(context.partner, sender) then return end
    context.direction, context.sender, context.request = "incoming", sender, request
    if context.confirmed then self:CompleteEscrowTrade() end
end

function Gamble:CompletePayoutTrade()
    local context = state.tradeContext
    if not context or context.direction ~= "payout" or not context.payment then return end
    if context.settled then return end
    local payment=context.payment
    local entries=payment.entries or {payment}
    if payment.entries and (not context.moneyReadable or context.offered~=payment.amount) then
        Print("Gesamtauszahlung nicht verbucht: Handelsbetrag ist nicht bestätigt oder stimmt nicht mit "..Money(payment.amount).." überein.")
        return
    end
    context.settled=true
    for _,first in ipairs(entries) do
    local queuedIndex
    for i,queued in ipairs(state.payments) do if queued==first then queuedIndex=i; break end end
    if queuedIndex then
        table.remove(state.payments, queuedIndex)
        if GambleBankSecurity and first.wagerID then
            local reason = tostring(first.reason or ""):lower()
            local refund = reason:find("rück", 1, true) ~= nil or reason:find("refund", 1, true) ~= nil
            GambleBankSecurity:CompleteObligation(first.wagerID, first.name, first.amount, refund)
        end
        Print("Payout completed: " .. Money(first.amount) .. "  to " .. DisplayName(first.name) .. ".")
        local wager = FindWager(first.wagerID)
        if wager and wager.mode == "LAST_MAN_STANDING" then
            wager.lmsPaidOut = wager.lmsPaidOut or {}; wager.lmsPaidOut[first.name] = first.amount
            DebugLMS("PAYOUT " .. DisplayName(first.name) .. " " .. Money(first.amount))
            local pending = false; for _, payment in ipairs(state.payments) do if payment.wagerID == wager.id then pending = true; break end end
            if not pending then wager.lmsState = "FINISHED" end
        elseif wager and IsEncounterBetMode(wager.mode) then
            wager.encounterPaidOut = wager.encounterPaidOut or {}; wager.encounterPaidOut[first.name] = first.amount
            DebugEncounter("PAYOUT: " .. DisplayName(first.name) .. " " .. Money(first.amount))
        end
        Send("PAYOUT_DONE", first.wagerID or "", first.name, first.amount)
    end
    end
    state.pendingTrade=nil; SaveSession(); self:Refresh()
    Print("Gesamtauszahlung abgeschlossen: "..Money(payment.amount).." an "..DisplayName(payment.name)..".")
end

function Gamble:OnAddonMessage(prefix, message, channel, sender)
    if prefix ~= PREFIX then return end
    if channel ~= "PARTY" and channel ~= "RAID" and channel ~= "INSTANCE_CHAT" then return end
    local p = Split(message); local command = p[1]
    if command == "SERIES_JOIN_BEGIN" or command == "SERIES_JOIN_PICK" or command == "SERIES_EDIT_BEGIN" or command == "SERIES_EDIT_PICK" then
        local addressed=FindWager(p[2])
        if addressed and addressed.awaitingStart == false then return end
    end
    state.lastCommReceived = time()
    if command == "LOBBY_SYNC_BEGIN" or command == "LOBBY_SYNC_ITEM" or command == "LOBBY_SYNC_END" then
        if not CanRead(sender) or SamePlayer(sender,PlayerName()) then return end
        state.lobbyInventories=state.lobbyInventories or {}
        local key=CanonicalPlayerName(sender)
        if command=="LOBBY_SYNC_BEGIN" then state.lobbyInventories[key]={token=p[2],ids={}}
        else
            local inventory=state.lobbyInventories[key]
            if not inventory or inventory.token~=p[2] then return end
            if command=="LOBBY_SYNC_ITEM" then inventory.ids[p[3]]=true
            else
                for _,wager in ipairs(state.wagers) do
                    if SamePlayer(wager.host,sender) then
                        wager.hostMissing=not inventory.ids[wager.id]
                        if wager.hostMissing and state.active==wager then
                            state.active=nil; self.detailWagerID=nil; self.uiTab="RUNNING"
                        end
                        if wager.hostMissing and self.inviteFrame and self.inviteFrame.wager==wager then self.inviteFrame:Hide() end
                    end
                end
                state.lobbyInventories[key]=nil
                SaveSession(); self:Refresh()
            end
        end
        return
    end
    if command == "BET_START" then
        local a=FindWager(p[2])
        if a and SamePlayer(sender,a.host) and not a.result then a.awaitingStart=false; a.setupPending=nil; SaveSession(); self:Refresh() end
        return
    end
    if command == "BET_EXCLUDE" then
        local a=FindWager(p[2])
        if a and SamePlayer(sender,a.host) and not a.result then
            local key=FindBetKey(a,p[3]); if key then a.bets[key]=nil end
            SetPaymentStatus(a,p[3],"CANCELLED")
            if SamePlayer(p[3],PlayerName()) then self:ShowRefundAnnouncement(a.host,tonumber(p[4]) or 0,a.id) end
            SaveSession(); self:Refresh()
        end
        return
    end
    if command=="BOSS_RESET" then
        if not CanRead(sender) or SamePlayer(sender,PlayerName()) or not IsInOurGroup(sender) then return end
        local stamp=tonumber(p[3])
        if stamp and stamp>0 and stamp<=(GetServerTime and GetServerTime() or time())+5 then self:ResetInstanceProgress(p[2],stamp,true) end
        return
    end
    if command == "BOSS_PROGRESS_GET" or command == "BOSS_PROGRESS" then
        if not CanRead(sender) or SamePlayer(sender, PlayerName()) then return end
        local current = BettingInstanceName()
        if not current or ResolveInstanceDataName(current) ~= p[2] then return end
        local reset=(state.bossResetTimes or {})[p[2]] or 0
        local remoteReset=tonumber(command=="BOSS_PROGRESS_GET" and p[3] or p[5]) or 0
        if remoteReset~=reset then
            if reset>remoteReset then Send("BOSS_RESET",p[2],reset) end
            return
        end
        if command == "BOSS_PROGRESS_GET" then
            state.bossSyncReplies = state.bossSyncReplies or {}
            local now = GetTime()
            if now - (state.bossSyncReplies[sender] or -10) < 3 then return end
            state.bossSyncReplies[sender] = now
            local prefix = NormalizeInstanceName(ResolveInstanceDataName(current)) .. ":"
            for key in pairs(state.defeatedBosses) do
                if key:sub(1, #prefix) == prefix then
                    local bossKey = key:sub(#prefix + 1)
                    if bossKey:match("^id%d+$") then Send("BOSS_PROGRESS", p[2], "", bossKey:sub(3),reset)
                    else Send("BOSS_PROGRESS", p[2], bossKey, "",reset) end
                end
            end
        else
            local bossName, encounterID = p[3] or "", tonumber(p[4])
            if bossName == "" and not encounterID then return end
            MarkBossDefeated(current, bossName, encounterID)
            -- Update available options only; never rewrite an already-created series.
            for i = #state.bosses, 1, -1 do
                local boss = state.bosses[i]
                if IsBossDefeated(current, boss.name, boss.encounterID) then
                    if state.selectedBoss == boss then state.selectedBoss = nil; wipe(state.lootItems) end
                    table.remove(state.bosses, i)
                end
            end
            state.allBossesDefeated = #state.bosses == 0
            self:Refresh()
        end
        return
    end
    if command == "BET_READY" or command == "BET_READY_STATE" or command == "BET_READY_GET" then
        local a = FindWager(p[2])
        if not a or a.don or not GambleReadyCheck then return end
        if command == "BET_READY_GET" then
            if SamePlayer(a.host, PlayerName()) and not SamePlayer(sender, PlayerName()) then
                a.readyRequests = a.readyRequests or {}
                local now = GetTime()
                if now - (a.readyRequests[sender] or -10) < 2 then return end
                a.readyRequests[sender] = now
                for name, value in pairs(a.readyStatus or {}) do Send("BET_READY_STATE", a.id, name, value and 1 or 0) end
            end
        elseif command == "BET_READY" then
            if SamePlayer(a.host, PlayerName()) and GambleReadyCheck:Set(a, sender, p[3] == "1", SamePlayer) then
                Send("BET_READY_STATE", a.id, sender, GambleReadyCheck:IsReady(a, sender, SamePlayer) and 1 or 0)
                SaveSession(); self:Refresh()
            end
        elseif SamePlayer(sender, a.host) and p[3] and GambleReadyCheck:Set(a, p[3], p[4] == "1", SamePlayer) then
            SaveSession(); self:Refresh()
        end
        return
    end
    if command == "PING" then Send("PONG", ADDON_VERSION); return end
    if command == "PONG" then
        if sender and CanRead(sender) then state.knownVersions[CanonicalPlayerName(sender)] = p[2] or ADDON_VERSION end
        self:RefreshVersionLabel(); return
    end
    if command == "VERSION" or command == "VERSION_REPLY" then
        if not SamePlayer(sender,PlayerName()) then
            local token=tostring(time()).."-"..tostring(math.random(1000,9999))
            Send("LOBBY_SYNC_BEGIN",token)
            for _,wager in ipairs(state.wagers) do
                if SamePlayer(wager.host,PlayerName()) and not (wager.result and wager.result.cancelled) then Send("LOBBY_SYNC_ITEM",token,wager.id) end
            end
            Send("LOBBY_SYNC_END",token)
        end
        if p[2] and p[2] ~= "" and sender and CanRead(sender) then state.knownVersions[CanonicalPlayerName(sender)] = p[2] end
        if command == "VERSION" and not SamePlayer(sender, PlayerName()) then
            Send("VERSION_REPLY", ADDON_VERSION)
            for _, wager in ipairs(state.wagers) do AnnounceWager(wager) end
        end
        self:RefreshVersionLabel()
        return
    end
    if command ~= "OPEN" and command ~= "PAYOUT_DONE" and p[2] then
        local addressed = FindWager(p[2])
        if addressed then state.active = addressed end
    end
    if command=="RANK_TARGET_REQUEST" or command=="RANK_PICK_REQUEST" then
        local a=FindWager(p[2]); local index=tonumber(p[3])
        if not a or a.mode~="BOSS_DAMAGE_SERIES" or a.result or not index or not a.bosses[index] or not SamePlayer(a.host,PlayerName()) or not IsInOurGroup(sender) then return end
        if command=="RANK_TARGET_REQUEST" then self:BroadcastBossRankTarget(a,index)
        elseif not self:ApplyBossRankPick(a,sender,index,p[4]) then Send("RANK_PICK_REJECTED",a.id,sender,index) end
        return
    elseif command:sub(1,5) == "RANK_" then
        local a=FindWager(p[2])
        if not a or not GambleDamageBets:IsMode(a.mode) or not SamePlayer(sender,a.host) or a.result then return end
        if SamePlayer(PlayerName(),a.host) then return end
        if command=="RANK_TARGET" and a.mode=="BOSS_DAMAGE_SERIES" then
            local index=tonumber(p[3]); if index and a.bosses[index] then GambleDamageBets:OpenBossPick(self,a,index) end
        elseif command=="RANK_PICK_CONFIRMED" and a.mode=="BOSS_DAMAGE_SERIES" then
            local index=tonumber(p[4]); local _,bet=FindBetKey(a,p[3])
            if index and a.bosses[index] and bet and GambleDamageBets:Valid(a,p[5]) then
                bet.picks[index]={guid=p[5],name="Top 3"}
                if state.active==a and SamePlayer(p[3],PlayerName()) then state.seriesPicks[index]=bet.picks[index] end
                local popup=GambleDamageBets.bossPick
                if popup and popup.wager==a and popup.index==index and SamePlayer(p[3],PlayerName()) then
                    popup.draft=GambleDamageBets:Decode(p[5]); popup.status="Tipp von der Bank bestätigt."
                    if GambleDamageBets.bossPickFrame and GambleDamageBets.bossPickFrame:IsShown() then GambleDamageBets:RenderBossPick() end
                end
            end
        elseif command=="RANK_PICK_REJECTED" and SamePlayer(p[3],PlayerName()) then
            local popup=GambleDamageBets.bossPick
            if popup and popup.wager==a and popup.index==tonumber(p[4]) then
                popup.status="Tipp nicht übernommen: Boss bereits gepullt oder Tipp ungültig."
                GambleDamageBets:RenderBossPick()
            end
        elseif command=="RANK_LIST_BEGIN" and a.mode=="BOSS_DAMAGE_SERIES" and a.awaitingStart~=false then
            local count=tonumber(p[3]); if not count or count<1 or count>100 then return end
            a.rankIncomingBosses={count=count,rows={}}
        elseif command=="RANK_LIST_ROW" and a.rankIncomingBosses then
            local index=tonumber(p[3]); local list=a.rankIncomingBosses
            if index and index>=1 and index<=list.count then list.rows[index]={name=p[4],encounterID=tonumber(p[5]),rare=p[6]=="1"} end
        elseif command=="RANK_LIST_END" and a.rankIncomingBosses then
            local list=a.rankIncomingBosses
            for i=1,list.count do if not list.rows[i] then return end end
            a.bosses=list.rows; a.rankIncomingBosses=nil
        elseif command=="RANK_LOCK" and a.mode=="BOSS_DAMAGE_SERIES" then
            local index=tonumber(p[3]); if not index or not a.bosses[index] then return end
            a.locked=true; a.currentSeriesBoss=index; GambleDamageBets:LockBossPick(a,index)
        elseif command=="RANK_WIPE" and a.mode=="BOSS_DAMAGE_SERIES" then
            a.currentSeriesBoss=nil
        elseif command=="RANK_REVIEW" and a.mode=="BOSS_DAMAGE_SERIES" then
            a.rankAwaitingFinish=true; if p[3]=="1" then a.rankEndBossKilled=true end
        elseif command=="RANK_CONTINUE" and a.mode=="BOSS_DAMAGE_SERIES" then
            a.rankAwaitingFinish=nil
        elseif command=="RANK_BEGIN" then
            local index=tonumber(p[3]); if not index or index<1 or (a.mode=="BOSS_DAMAGE_SERIES" and not a.bosses[index]) or (a.mode=="DAMAGE_RACE" and index~=1) then return end
            a.rankIncoming=a.rankIncoming or {}; a.rankIncoming[index]={}
        elseif command=="RANK_POS" then
            local index,place=tonumber(p[3]),tonumber(p[4]); local ranking=a.rankIncoming and a.rankIncoming[index]
            if ranking and place and place>=1 and place<=3 and a.snapshot[p[5]] then ranking[place]=ranking[place] or {}; ranking[place][p[5]]=true end
        elseif command=="RANK_BOSS" then
            local index=tonumber(p[3]); if not index or index<1 or (a.mode=="BOSS_DAMAGE_SERIES" and not a.bosses[index]) or (a.mode=="DAMAGE_RACE" and index~=1) then return end
            local ranking=a.rankIncoming and a.rankIncoming[index]; if not ranking then return end
            a.rankResults=a.rankResults or {}; a.rankResults[index]=ranking; a.rankIncoming[index]=nil
            if a.mode=="BOSS_DAMAGE_SERIES" then
                local failed=p[4] and p[4]~=""
                a.seriesResults[index]={name=failed and "Not scored" or "Scored",nobody=true}; a.currentSeriesBoss=nil
                if failed then a.rankMeasurementFailed=p[4] end
            end
            if GambleDamageBets.bossPick and GambleDamageBets.bossPick.wager==a and GambleDamageBets.bossPick.index==index and GambleDamageBets.bossPickFrame then GambleDamageBets.bossPickFrame:Hide() end
        elseif command=="RANK_SCORE" then
            local score,payout=tonumber(p[4]),tonumber(p[5])
            if not score or not payout or score<0 or payout<0 then return end
            a.rankScores=a.rankScores or {}; a.rankPayouts=a.rankPayouts or {}
            a.rankScores[p[3]]=score; if payout>0 then a.rankPayouts[p[3]]=payout end
        elseif command=="RANK_END" then
            a.rankBest=tonumber(p[4]) or 0
            self:FinishRankDamage(a,p[3]=="1",p[5]~="" and p[5] or nil,true)
            return
        end
        SaveSession(); self:Refresh(); return
    elseif command == "OPEN" then
        local version, id, mode, bossName, bossEncounterID, context, targetGUID, targetName, stake = tonumber(p[2]), p[3], p[4], p[5], tonumber(p[6]), p[7], p[8], p[9], tonumber(p[10])
        if version ~= VERSION then
            Print("Bet from " .. DisplayName(sender) .. " could not be loaded: incompatible Gamble versions. Both players must update.")
            return
        end
        if not id or not stake or stake <= 0 then return end
        if not FindWager(id) then
            state.selectedType = mode
            state.selectedGUID, state.selectedName = nil, nil
            if IsBossSeries(mode) then LoadCurrentInstanceBosses(); wipe(state.seriesPicks); state.seriesStep = 1 end
            if mode == "ITEM_DROP" then
                LoadCurrentInstanceBosses()
                for _, boss in ipairs(state.bosses) do if (bossEncounterID and boss.encounterID == bossEncounterID) or boss.name == bossName then state.selectedBoss = boss; LoadBossLoot(boss); break end end
            end
            NewActive(id, sender, floor(stake), targetGUID, targetName, floor(stake), mode, bossName, context, bossEncounterID)
            if not targetGUID or targetGUID == "" then state.active.setupPending = true end
            Print(sender .. " opened a bet (minimum " .. Money(stake) .. ").")
            local openedWager = state.active
            self:Refresh()
            self:ShowWagerInvite(sender, openedWager)
        end
    elseif command == "CONFIG" then
        local a = state.active
        if a and p[2] == a.id and SamePlayer(sender, a.host) then
            a.bossName, a.bossEncounterID, a.context = p[3] or "", tonumber(p[4]), p[5] or ""
            a.setupPending = nil
            if a.mode == "LAST_MAN_STANDING" then a.lmsState = "BETTING_OPEN" end
            if a.mode == "ITEM_DROP" then
                LoadCurrentInstanceBosses()
                for _, boss in ipairs(state.bosses) do
                    if (a.bossEncounterID and boss.encounterID == a.bossEncounterID) or BossNameMatches(boss.name, a.bossName) then
                        state.selectedBoss = boss; LoadBossLoot(boss); a.lootItems = {}
                        for _, item in ipairs(state.lootItems) do a.lootItems[#a.lootItems + 1] = { id = item.id, name = item.name, link = item.link, icon = item.icon } end
                        break
                    end
                end
            end
            self:Refresh()
        end
    elseif command == "EDIT" then
        local a = state.active
        local stake = tonumber(p[5])
        local _, previous = FindBetKey(a, sender)
        local validTarget = a and ((a.mode == "ITEM_DROP" and tostring(p[3]):match("^ITEM:%d+$")) or (IsEncounterBetMode(a.mode) and EncounterOption(a.mode, p[3])) or ValidPrediction(a,p[3]))
        if a and a.awaitingStart ~= false and p[2] == a.id and SamePlayer(PlayerName(), a.host) and previous and not a.locked and not a.result and not a.cancelVote and stake == previous.stake and validTarget then
            if AddBet(sender, p[3], p[4], stake) then
                Send("CONFIRM", a.id, sender, p[3], p[4], stake)
                Print(DisplayName(sender) .. " changed their prediction.")
                self:Refresh()
            end
        end
    elseif command == "JOIN" then
        local a = state.active
        local stake, additionalStake = tonumber(p[5]), tonumber(p[6])
        if not additionalStake then additionalStake = stake end
        local _, oldBet = FindBetKey(a, sender)
        if a and p[2] == a.id and oldBet and stake and oldBet.stake >= stake then
            if SamePlayer(PlayerName(), a.host) then Send("PAYMENT_STATUS", a.id, sender, "PAID") end
            return
        end
        local validTarget = a and ((a.mode == "ITEM_DROP" and tostring(p[3]):match("^ITEM:%d+$")) or (IsEncounterBetMode(a.mode) and EncounterOption(a.mode, p[3])) or ValidPrediction(a,p[3]))
        if a and a.awaitingStart ~= false and p[2] == a.id and SamePlayer(sender, a.host) == false and not a.locked and not a.cancelVote and stake and additionalStake and additionalStake > 0 and stake >= a.minimum and (not oldBet or stake >= oldBet.stake) and validTarget then
            if SamePlayer(PlayerName(), a.host) and GambleBankSecurity then
                local allowed, reason = GambleBankSecurity:CanAcceptDeposits()
                if not allowed then Print("Deposit rejected: " .. tostring(reason) .. ". Existing obligations can still be paid."); Send("PAYMENT_STATUS", a.id, sender, "CANCELLED"); return end
            end
            SetPaymentStatus(a, sender, "PENDING")
            if SamePlayer(PlayerName(), a.host) then
                state.escrowRequests[sender] = { bettor = sender, targetGUID = p[3], targetName = p[4], stake = floor(additionalStake), totalStake = floor(stake), id = a.id }
                Print(sender .. " wants to participate with a total stake of " .. Money(stake) .. " and is now paying " .. Money(additionalStake) .. ".")
            end
            self:Refresh()
        end
    elseif command == "SERIES_JOIN_BEGIN" then
        local a, totalStake, additionalStake, count = FindWager(p[2]), tonumber(p[3]), tonumber(p[4]), tonumber(p[5])
        local _, oldBet = FindBetKey(a, sender)
        -- The participant retries its predictions after trade completion. An
        -- already booked deposit must not become pending or be booked twice.
        if a and IsBossSeries(a.mode) and p[2] == a.id and oldBet and totalStake and oldBet.stake >= totalStake then
            if SamePlayer(PlayerName(), a.host) then Send("PAYMENT_STATUS", a.id, sender, "PAID") end
            return
        end
        if a and IsBossSeries(a.mode) and p[2] == a.id and not a.result and totalStake and additionalStake and additionalStake > 0 and totalStake >= a.minimum and (not oldBet or totalStake >= oldBet.stake) and count == #a.bosses then
            if SamePlayer(PlayerName(), a.host) and GambleBankSecurity then
                local allowed, reason = GambleBankSecurity:CanAcceptDeposits()
                if not allowed then Print("Deposit rejected: " .. tostring(reason)); Send("PAYMENT_STATUS", a.id, sender, "CANCELLED"); return end
            end
            SetPaymentStatus(a, sender, "PENDING")
            if SamePlayer(PlayerName(), a.host) then
                local existing = state.escrowRequests[sender]
                if not existing or existing.id ~= a.id or existing.totalStake ~= floor(totalStake) then
                    state.escrowRequests[sender] = { bettor = sender, stake = floor(additionalStake), totalStake = floor(totalStake), id = a.id, picks = {}, expected = count }
                end
                self:BindEscrowTrade(sender, state.escrowRequests[sender])
            end
            self:Refresh()
        end
    elseif command == "SERIES_JOIN_PICK" then
        local request = state.escrowRequests[sender]; local index = tonumber(p[3])
        if request and p[2] == request.id and index and index >= 1 and index <= request.expected and p[4] and p[4] ~= "" and p[5] and p[5] ~= "" then
            request.picks[index] = { guid = p[4], name = p[5] }
            if request.receivedStake then
                local complete = true
                for i = 1, request.expected do if not request.picks[i] then complete = false; break end end
                if complete then
                    local previousContext = state.tradeContext
                    state.tradeContext = { direction = "incoming", sender = sender, request = request, offered = request.receivedStake, moneyReadable = true, confirmed = true }
                    self:CompleteEscrowTrade()
                    state.tradeContext = previousContext
                end
            end
        end
    elseif command == "SERIES_EDIT_BEGIN" then
        local a, totalStake, additionalStake, count = state.active, tonumber(p[3]), tonumber(p[4]), tonumber(p[5]); local oldBet = a and a.bets[sender]
        if a and oldBet and IsBossSeries(a.mode) and p[2] == a.id and SamePlayer(PlayerName(), a.host) and not a.result and additionalStake == 0 and totalStake == oldBet.stake and count == #a.bosses then
            state.seriesIncoming["EDIT:" .. sender] = { bettor = sender, stake = totalStake, picks = {}, expected = count, id = a.id, edit = true }
        end
    elseif command == "SERIES_EDIT_PICK" then
        local index = tonumber(p[3]); local incoming = state.seriesIncoming["EDIT:" .. sender]
        if incoming and p[2] == incoming.id and index and ValidPrediction(state.active,p[4]) then
            incoming.picks[index] = { guid = p[4], name = p[5] }
            local complete = true; for i = 1, incoming.expected do if not incoming.picks[i] then complete = false; break end end
            if complete then
                if AddSeriesBet(sender, incoming.picks, incoming.stake) then
                    Send("SERIES_BET_BEGIN", incoming.id, sender, incoming.stake, incoming.expected)
                    for i, pick in ipairs(incoming.picks) do Send("SERIES_BET_PICK", incoming.id, sender, i, pick.guid, pick.name) end
                end
                state.seriesIncoming["EDIT:" .. sender] = nil; self:Refresh()
            end
        end
    elseif command == "SERIES_BET_BEGIN" then
        local a, bettor, stake, count = state.active, p[3], tonumber(p[4]), tonumber(p[5])
        if a and IsBossSeries(a.mode) and p[2] == a.id and SamePlayer(sender, a.host) and count == #a.bosses then
            state.seriesIncoming[bettor] = { bettor = bettor, stake = stake, picks = {}, expected = count, id = a.id }
        end
    elseif command == "SERIES_BET_PICK" then
        local bettor, index = p[3], tonumber(p[4]); local incoming = state.seriesIncoming[bettor]
        if incoming and p[2] == incoming.id and SamePlayer(sender, state.active.host) and index and ValidPrediction(state.active,p[5]) then
            incoming.picks[index] = { guid = p[5], name = p[6] }
            local complete = true; for i = 1, incoming.expected do if not incoming.picks[i] then complete = false; break end end
            if complete then
                AddSeriesBet(incoming.bettor, incoming.picks, incoming.stake)
                SetPaymentStatus(state.active, incoming.bettor, "PAID")
                if SamePlayer(incoming.bettor, PlayerName()) then
                    SetMoneyBoxes(incoming.stake)
                    if state.pendingJoin then state.pendingJoin = nil end
                end
                state.seriesIncoming[bettor] = nil; self:Refresh()
            end
        end
    elseif command == "SERIES_BOSS" then
        local a, index = state.active, tonumber(p[3])
        if a and IsBossSeries(a.mode) and p[2] == a.id and SamePlayer(sender, a.host) and index and a.bosses[index] and not a.seriesResults[index] then
            a.seriesResults[index] = p[4] ~= "" and { guid = p[4], name = p[5] } or { nobody = true, name = "Nobody" }
            a.completedBosses = (a.completedBosses or 0) + 1; self:Refresh()
        end
    elseif command == "SERIES_RESULT" then
        local a = state.active
        if a and IsBossSeries(a.mode) and p[2] == a.id and SamePlayer(sender, a.host) and not a.result then FinalizeSeries() end
    elseif command == "SERIES_PAYOUT" then
        local a = state.active
        if a and a.result and a.result.series and p[2] == a.id and SamePlayer(sender, a.host) then
            a.seriesPayouts[p[3]] = tonumber(p[4]) or 0; a.seriesScores[p[3]] = tonumber(p[5]) or 0; self:Refresh()
        end
    elseif command == "PAYOUT_DONE" then
        local wager = FindWager(p[2]) or state.active
        local amount = tonumber(p[4]) or 0
        if wager and SamePlayer(sender, wager.host) and amount > 0 then
            if IsEncounterBetMode(wager.mode) then wager.encounterPaidOut = wager.encounterPaidOut or {}; wager.encounterPaidOut[p[3]] = amount end
            if SamePlayer(wager.host, PlayerName()) or OwnBet(wager) then self:ShowWinnerAnnouncement(p[3], amount, wager.id) end
            self:Refresh()
        end
    elseif command == "CONFIRM" then
        local a = state.active
        if a and p[2] == a.id and SamePlayer(sender, a.host) then
            local bettor, targetGUID, targetName, stake = p[3], p[4], p[5], p[6]
            if AddBet(bettor, targetGUID, targetName, stake) then
                SetPaymentStatus(a, bettor, "PAID")
                if SamePlayer(bettor, PlayerName()) then
                    SetMoneyBoxes(stake)
                    if state.pendingJoin then state.pendingJoin = nil end
                end
                Print(bettor .. " joined with " .. Money(stake) .. "."); self:Refresh()
            end
        end
    elseif command == "PAYMENT_STATUS" then
        local a = state.active
        if a and p[2] == a.id and SamePlayer(sender, a.host) and p[3] then
            if p[4] == "CANCELLED" then ClearPaymentStatus(a, p[3]) else SetPaymentStatus(a, p[3], p[4]) end
            self:Refresh()
        end
    elseif command == "LOCK" then
        local a = state.active
        if a and p[2] == a.id and SamePlayer(sender, a.host) then
            a.locked = true; a.encounterName = p[3] ~= "" and p[3] or a.encounterName; a.encounterID = tonumber(p[4]) or a.encounterID
            FreezeBossEligibleUnits(); SnapshotDeadState()
            if a.mode == "LAST_MAN_STANDING" then
                a.lmsState, a.lmsFirstDeaths, a.lmsDeathOrder, a.lmsEligible, a.lmsStartedAt = "ENCOUNTER_ACTIVE", {}, {}, {}, GetTime and GetTime() or time()
                for _, member in ipairs(a.units or {}) do a.lmsEligible[member.guid] = true end
            elseif IsEncounterBetMode(a.mode) and GambleEncounterTracker then
                GambleEncounterTracker:Start(a, a.encounterID, a.encounterName)
            end
            self:Refresh()
        end
    elseif command == "LMS_DEATH" then
        local a, guid = state.active, p[3]
        if a and a.mode == "LAST_MAN_STANDING" and p[2] == a.id and SamePlayer(sender, a.host) and guid and not (a.lmsFirstDeaths and a.lmsFirstDeaths[guid]) then
            a.lmsFirstDeaths = a.lmsFirstDeaths or {}; a.lmsDeathOrder = a.lmsDeathOrder or {}
            local death = { guid = guid, name = p[4], stamp = tonumber(p[5]) or 0, order = tonumber(p[6]) or (#a.lmsDeathOrder + 1) }
            a.lmsFirstDeaths[guid] = death; a.lmsDeathOrder[#a.lmsDeathOrder + 1] = death; self:Refresh()
        end
    elseif command == "LMS_RESULT" then
        local a = state.active
        if a and a.mode == "LAST_MAN_STANDING" and p[2] == a.id and SamePlayer(sender, a.host) and not a.result then
            local winners = {}; for guid in tostring(p[3] or ""):gmatch("[^,]+") do winners[#winners + 1] = guid end
            FinalizeLMS(winners, false, true)
        end
    elseif command == "LMS_AMBIGUOUS" then
        local a = state.active
        if a and a.mode == "LAST_MAN_STANDING" and p[2] == a.id and SamePlayer(sender, a.host) and not a.result then FinalizeLMS(nil, true, true) end
    elseif command == "DMG_START" then
        local a = state.active
        if a and a.mode == "DAMAGE_RACE" and p[2] == a.id and SamePlayer(sender, a.host) and not a.result then
            local seconds = tonumber(p[3])
            if not seconds or seconds < 10 or seconds > 1800 then return end
            a.locked = true; a.awaitingStart = false; a.damageDuration = seconds
            a.damageEndsAt = tonumber(p[4]) or ((GetServerTime and GetServerTime() or time()) + seconds)
            self:Refresh()
        end
    elseif command == "DMG_WIN" then
        local a = state.active
        if a and a.mode == "DAMAGE_RACE" and p[2] == a.id and SamePlayer(sender, a.host) and a.snapshot[p[3]] and not a.result then a.damageCandidates = a.damageCandidates or {}; a.damageCandidates[p[3]] = true end
    elseif command == "DMG_RESULT" then
        local a = state.active
        if a and a.mode == "DAMAGE_RACE" and p[2] == a.id and SamePlayer(sender, a.host) and not a.result then
            local winners = {}; for guid in pairs(a.damageCandidates or {}) do winners[#winners + 1] = guid end; table.sort(winners)
            if p[6] then
                winners={}
                for guid in p[6]:gmatch("[^,]+") do if a.snapshot[guid] then winners[#winners+1]=guid end end
            end
            self:FinishDamageRace(a, winners, tonumber(p[3]) or 0, p[4] == "1", true, p[5] ~= "" and p[5] or nil)
        end
    elseif command == "EBET_RESULT" then
        local a = state.active
        if a and IsEncounterBetMode(a.mode) and p[2] == a.id and SamePlayer(sender, a.host) and (not a.result or a.result.ambiguous) then
            if a.result and a.result.ambiguous then a.result = nil end
            FinalizeEncounterBet(a, p[3] ~= "" and p[3] or nil, p[4], p[5], p[6], p[7], true, tonumber(p[8]) == 1, tonumber(p[9]) == 1)
        end
    elseif command == "EBET_DEATH" then
        local a, order = state.active, tonumber(p[6])
        if a and IsEncounterBetMode(a.mode) and p[2] == a.id and SamePlayer(sender, a.host) and a.encounterTracker and order and order > (a.encounterTracker.totalDeaths or 0) then
            local death = { guid = p[3], name = p[4], elapsed = tonumber(p[5]) or 0, order = order, stamp = (a.encounterTracker.startedAt or 0) + (tonumber(p[5]) or 0) }
            a.encounterTracker.deaths[#a.encounterTracker.deaths + 1] = death
            a.encounterTracker.totalDeaths = order
            a.encounterTracker.firstDeath = a.encounterTracker.firstDeath or death
            self:Refresh()
        end
    elseif command == "RESULT" then
        local a = state.active
        if a and p[2] == a.id and sender == a.host then Resolve(p[3], p[4], true) end
    elseif command == "VOID" then
        local a = state.active
        if a and p[2] == a.id and SamePlayer(sender, a.host) then VoidBoss(p[3], true) end
    elseif command == "ITEM_RESULT" then
        local a, itemID = state.active, tonumber(p[3])
        if a and a.mode == "ITEM_DROP" and p[2] == a.id and SamePlayer(sender, a.host) and not a.result then
            FinalizeItemDrop(itemID and itemID > 0 and itemID or nil, true)
            a.bankCut = tonumber(p[4]) or a.bankCut; a.itemRollover = tonumber(p[5]) or a.itemRollover
            GambleDB.itemJackpots[ItemJackpotKey(a)] = tonumber(p[5]) or GambleDB.itemJackpots[ItemJackpotKey(a)] or 0
        end
    elseif command == "CANCEL_REQUEST" then
        local a = FindWager(p[2])
        if a and SamePlayer(sender, a.host) and (not a.locked or IsBossSeries(a.mode)) and not a.result then
            local participates = false
            for _, bet in pairs(a.bets or {}) do if SamePlayer(bet.bettor, PlayerName()) and not SamePlayer(bet.bettor, a.host) then participates = true; break end end
            if participates then StaticPopup_Show("GAMBLE_CANCEL_REQUEST", DisplayName(sender), nil, a.id) end
        end
    elseif command == "CANCEL_VOTE" then
        local a = FindWager(p[2])
        if a and p[2] == a.id and a.cancelVote and SamePlayer(PlayerName(), a.host) then
            local voterKey
            for name in pairs(a.cancelVote.voters) do if SamePlayer(name, sender) then voterKey = name; break end end
            if voterKey and a.cancelVote.voters[voterKey] == false then
                if p[3] ~= "YES" then
                    a.cancelVote = nil; Send("CANCEL_ABORT", a.id)
                    Print(DisplayName(sender) .. " declined cancellation. The bet remains open."); self:Refresh()
                else
                    a.cancelVote.voters[voterKey] = true; a.cancelVote.accepted = a.cancelVote.accepted + 1
                    if a.cancelVote.accepted >= a.cancelVote.required then state.active = a; FinalizeCancel(false) else self:Refresh() end
                end
            end
        end
    elseif command == "CANCEL_ABORT" then
        local a = FindWager(p[2])
        if a and p[2] == a.id and SamePlayer(sender, a.host) then StaticPopup_Hide("GAMBLE_CANCEL_REQUEST"); Print("Cancellation was not unanimous. The bet remains open.") end
    elseif command == "CANCEL_FINAL" then
        local a = FindWager(p[2])
        if a and p[2] == a.id and SamePlayer(sender, a.host) then StaticPopup_Hide("GAMBLE_CANCEL_REQUEST"); state.active = a; FinalizeCancel(true) end
    end
end

function Gamble:OnEvent(event, ...)
    if event=="UNIT_HEALTH" or event=="UNIT_MAXHEALTH" then
        local needsHealth=false
        for _,wager in ipairs(state.wagers) do
            if not wager.result and wager.locked and IsEncounterBetMode(wager.mode) then needsHealth=true; break end
        end
        if not needsHealth then return end
    end
    local multiEvent = event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" or event == "ENCOUNTER_START" or event == "ENCOUNTER_END" or event == "UNIT_DIED" or event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "CHAT_MSG_LOOT" or event == "LOOT_OPENED"
    if multiEvent and not state.dispatchingWagers and #state.wagers > 0 then
        local selected = state.active
        state.dispatchingWagers = true
        for _, wager in ipairs(state.wagers) do
            state.active = wager
            self:OnEvent(event, ...)
        end
        state.dispatchingWagers = nil
        state.active = selected
        self:Refresh()
        return
    end
    if event == "PLAYER_LOGIN" then
        GambleDB = GambleDB or { version = VERSION }
        GambleDB.settings = GambleDB.settings or {}
        if GambleDB.settings.autoWagerPopup == nil then GambleDB.settings.autoWagerPopup = true end
        RestoreSession()
        if not state.active and (state.selectedType == "NEXT_BOSS" or IsBossSeries(state.selectedType) or state.selectedType == "ITEM_DROP" or IsEncounterBetMode(state.selectedType)) then
            LoadCurrentInstanceBosses()
        end
        local register = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
        local ok, result = register and pcall(register, PREFIX)
        state.prefixRegistered = ok and result ~= false
        if ok then state.prefixRegisterError = nil else state.prefixRegisterError = tostring(result or "Registration API unavailable") end
        BuildRoster(); self:CreateUI(); self:CreateMinimapButton(); RecoverCompletedWagers(); self:Refresh(); state.restoringSession = nil
        C_Timer.After(2, BroadcastVersion)
    elseif event == "PLAYER_LOGOUT" then
        SaveSession()
    elseif event == "PLAYER_ENTERING_WORLD" then
        RefreshInstanceDefeatScope()
        RecoverCompletedWagers()
        if not (InCombatLockdown and InCombatLockdown()) then
            local selected = state.active
            for _, wager in ipairs(state.wagers) do
                if wager.mode == "NEXT_PULL" and wager.locked and not wager.result and SamePlayer(wager.host, PlayerName()) then
                    state.active = wager
                    VoidBoss("Pull ended after a zone change; nobody died", false)
                end
            end
            state.active = selected
        end
        if not state.active and (state.selectedType == "NEXT_BOSS" or IsBossSeries(state.selectedType) or state.selectedType == "ITEM_DROP" or IsEncounterBetMode(state.selectedType)) then LoadCurrentInstanceBosses() end
        self:Refresh()
    elseif event=="ZONE_CHANGED_NEW_AREA" then
        if not state.active and not state.preselectedInstance then
            LoadCurrentInstanceBosses(); wipe(state.seriesPicks); state.seriesStep=1
        end
        self:Refresh()
    elseif event == "GROUP_ROSTER_UPDATE" then
        BuildRoster(); self:Refresh()
        if not state.lastVersionBroadcast or time() - state.lastVersionBroadcast >= 3 then BroadcastVersion() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if self.pendingWindowClose then self:CloseAuxiliaryWindows() end
        local a = state.active
        if a and not a.setupPending and a.mode == "NEXT_PULL" and a.locked and not a.result and SamePlayer(a.host, PlayerName()) then
            VoidBoss("Pull ended; nobody died", false)
        else
            self:Refresh()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        local a = state.active
        if a and not a.awaitingStart and not a.setupPending and a.mode == "NEXT_PULL" and not a.locked and not a.result then
            local pending = PendingPaymentNames(a)
            if #pending > 0 then Print("Bet not started: Missing " .. #pending .. " payment(s)."); self:Refresh(); return end
            if a.cancelVote and SamePlayer(a.host, PlayerName()) then a.cancelVote = nil; Send("CANCEL_ABORT", a.id) end
            a.locked = true
            SnapshotDeadState()
            if a.host == PlayerName() then Send("LOCK", a.id) end
            Print("Pull detected. Betting is closed."); self:Refresh()
        end
    elseif event == "ENCOUNTER_START" then
        local encounterID, encounterName = ...; local a = state.active
        if a and (a.setupPending or a.awaitingStart) then return end
        if a and not a.locked and not a.result and not AllPaymentsReceived(a) then
            Print("Bet not started: At least one payment is pending."); self:Refresh(); return
        end
        if a and a.mode == "BOSS_SERIES" and not a.result then
            local index = SeriesBossIndex(a, encounterID, encounterName)
            if index and not a.seriesResults[index] then
                if not a.locked then
                    a.locked = true
                    if SamePlayer(a.host, PlayerName()) then Send("LOCK", a.id, encounterName, encounterID) end
                end
                FreezeBossEligibleUnits()
                a.currentSeriesBoss = index; a.encounterID = encounterID; a.encounterName = encounterName; a.seenDead = {}
                SnapshotDeadState(); Print("Series boss detected: " .. encounterName .. "."); self:Refresh()
            end
        elseif a and (a.mode == "NEXT_BOSS" or a.mode == "LAST_MAN_STANDING" or a.mode == "ITEM_DROP" or IsEncounterBetMode(a.mode)) and not a.locked and not a.result then
            local wanted = (a.bossEncounterID and encounterID == a.bossEncounterID) or (not a.bossEncounterID and BossNameMatches(a.bossName, encounterName))
            if wanted then
                if a.cancelVote and SamePlayer(a.host, PlayerName()) then a.cancelVote = nil; Send("CANCEL_ABORT", a.id) end
                a.locked = true; a.encounterID = encounterID; a.encounterName = encounterName
                if a.mode == "ITEM_DROP" then a.droppedItems = {}; a.droppedNames = {} end
                FreezeBossEligibleUnits()
                SnapshotDeadState()
                if a.mode == "LAST_MAN_STANDING" then
                    a.lmsState, a.lmsFirstDeaths, a.lmsDeathOrder, a.lmsEligible, a.lmsStartedAt = "ENCOUNTER_ACTIVE", {}, {}, {}, GetTime and GetTime() or time()
                    for _, member in ipairs(a.units or {}) do a.lmsEligible[member.guid] = true end
                    DebugLMS("ENCOUNTER_START / BET_LOCKED")
                elseif IsEncounterBetMode(a.mode) and GambleEncounterTracker then
                    GambleEncounterTracker:Start(a, encounterID, encounterName)
                    GambleEncounterTracker:SampleBossHealth(a)
                    DebugEncounter("BET: LOCKED type=" .. a.mode)
                    DebugEncounter("ENCOUNTER: START id=" .. tostring(encounterID))
                end
                if SamePlayer(a.host, PlayerName()) then Send("LOCK", a.id, encounterName, encounterID) end
                Print("Boss encounter against " .. encounterName .. " detected. Betting closed."); self:Refresh()
            end
        end
    elseif event == "BOSS_KILL" then
        local encounterID, encounterName = ...
        if CanRead(encounterID) and CanRead(encounterName) then MarkCurrentBossDefeated(encounterID, encounterName); SaveSession(); self:Refresh() end
    elseif event == "ENCOUNTER_END" then
        local encounterID, encounterName, difficultyID, groupSize, success = ...; local a = state.active
        if CanRead(success) and success == 1 and CanRead(encounterID) and CanRead(encounterName) then MarkCurrentBossDefeated(encounterID, encounterName); SaveSession() end
        if a and not a.setupPending and IsEncounterBetMode(a.mode) and SamePlayer(a.host, PlayerName()) and a.locked and not a.result and a.encounterID == encounterID then
            local tracker = a.encounterTracker
            if GambleEncounterTracker then GambleEncounterTracker:SampleBossHealth(a); GambleEncounterTracker:Stop(a, success) end
            DebugEncounter("ENCOUNTER: END result=" .. (success == 1 and "BOSS_KILL" or "WIPE"))
            if a.mode == "BOSS_HP_WIPE" then
                if success == 1 then
                    FinalizeEncounterBet(a, nil, "BOSS KILLED", nil, nil, nil, false, false, true)
                else
                    local hp = GambleEncounterTracker and GambleEncounterTracker:FreshBossHealth(a)
                    local option = hp and GambleEncounterTracker:OptionForValue(a.mode, hp)
                    if option then
                        DebugEncounter(string.format("BOSS_HP: %.2f", hp))
                        FinalizeEncounterBet(a, option.key, "WIPE", hp, nil, nil, false, false, false)
                    else FinalizeEncounterBet(a, nil, "AMBIGUOUS", hp, nil, nil, false, true, false) end
                end
            elseif a.mode == "PULL_TIMER_DEATH" then
                local death = tracker and tracker.firstDeath
                if death then
                    local option = GambleEncounterTracker:OptionForValue(a.mode, death.elapsed)
                    FinalizeEncounterBet(a, option and option.key, "FIRST DEATH", death.elapsed, death.name, death.elapsed, false, not option, false)
                elseif success == 1 then
                    FinalizeEncounterBet(a, "NO_DEATH", "NO DEATH", 0, nil, nil, false, false, false)
                else FinalizeEncounterBet(a, nil, "AMBIGUOUS", nil, nil, nil, false, true, false) end
            elseif a.mode == "TOTAL_DEATHS" then
                local total = tracker and tracker.totalDeaths or 0
                local option = GambleEncounterTracker and GambleEncounterTracker:OptionForValue(a.mode, total)
                DebugEncounter("TOTAL_DEATHS: " .. tostring(total))
                FinalizeEncounterBet(a, option and option.key, success == 1 and "BOSS KILL" or "WIPE", total, nil, nil, false, not option, false)
            end
        elseif a and not a.setupPending and a.mode == "LAST_MAN_STANDING" and SamePlayer(a.host, PlayerName()) and a.locked and not a.result and a.encounterID == encounterID then
            a.lmsState = "WAITING_FOR_RESULT"
            if success == 1 then
                a.result = { void = true, lms = true, name = "BET VOID – BOSS KILLED" }
                BuildPayments(nil, true); Send("VOID", a.id, a.result.name); Print(a.result.name .. ". All stakes will be refunded."); self:Refresh()
            else ResolveLMSWipe(false) end
        elseif a and not a.awaitingStart and not a.setupPending and a.mode == "BOSS_SERIES" and SamePlayer(a.host, PlayerName()) then
            local index = SeriesBossIndex(a, encounterID, encounterName)
            if success == 1 and index then
                if not a.seriesResults[index] then
                    a.seriesResults[index] = { nobody = true, name = "Nobody" }; a.completedBosses = (a.completedBosses or 0) + 1
                    Send("SERIES_BOSS", a.id, index, "", "Nobody")
                end
                a.currentSeriesBoss = nil
                local lastRequired = #a.bosses
                while lastRequired > 0 and GambleData.IsRareBoss(a.bosses[lastRequired]) do lastRequired = lastRequired - 1 end
                if index == lastRequired or IsConfiguredEndBoss(a, encounterID, encounterName) then
                    for missingIndex = 1, #a.bosses do
                        if not a.seriesResults[missingIndex] then
                            a.seriesResults[missingIndex] = { nobody = true, name = "Not scored" }
                            a.completedBosses = (a.completedBosses or 0) + 1
                            Send("SERIES_BOSS", a.id, missingIndex, "", "Not scored")
                        end
                    end
                end
                if SeriesComplete(a) then FinalizeSeries() else self:Refresh() end
            elseif a.currentSeriesBoss and a.encounterID == encounterID then
                a.currentSeriesBoss = nil; self:Refresh()
            end
        elseif a and a.mode == "ITEM_DROP" and not a.result and SamePlayer(a.host, PlayerName()) and success == 1
            and ((a.encounterID and a.encounterID == encounterID)
                or (a.bossEncounterID and a.bossEncounterID == encounterID)
                or BossNameMatches(a.bossName, encounterName)) then
            a.locked = true
            a.encounterID = encounterID
            a.encounterName = encounterName
            a.encounterEnded = true
            C_Timer.After(10, function()
                if FindWager(a.id) == a and not a.result then
                    local winner
                    for _, bet in pairs(a.bets or {}) do if a.droppedItems and a.droppedItems[bet.targetItemID] then winner = bet.targetItemID; break end end
                    local selected = state.active
                    state.active = a
                    FinalizeItemDrop(winner, false)
                    state.active = selected
                    Gamble:Refresh()
                end
            end)
        elseif a and a.mode == "NEXT_BOSS" and a.locked and not a.result and a.encounterID == encounterID and SamePlayer(a.host, PlayerName()) then
            VoidBoss(encounterName .. " ended; nobody died", false)
        end
    elseif event == "CHAT_MSG_LOOT" then
        local message = ...; local a = state.active
        if a and a.mode == "ITEM_DROP" and a.locked and not a.result and type(message) == "string" then
            for itemID in message:gmatch("|Hitem:(%d+)") do
                itemID = tonumber(itemID)
                local cachedName, cachedLink = SafeGetItemInfo(itemID)
                a.droppedItems[itemID] = true; a.droppedNames[itemID] = cachedLink or cachedName or ("Item " .. itemID)
            end
        end
    elseif event == "LOOT_OPENED" then
        local a = state.active
        if a and a.mode == "ITEM_DROP" and a.locked and not a.result and GetNumLootItems and GetLootSlotLink then
            for slot = 1, GetNumLootItems() do
                local link = GetLootSlotLink(slot); local itemID = link and tonumber(link:match("item:(%d+)"))
                if itemID then a.droppedItems[itemID] = true; a.droppedNames[itemID] = link end
            end
        end
    elseif event == "UNIT_DIED" then
        local a = state.active
        if a and not a.setupPending and SamePlayer(a.host, PlayerName()) then
            if IsEncounterBetMode(a.mode) and a.locked and not a.result and GambleEncounterTracker then
                local deaths = GambleEncounterTracker:FindNewDeaths(a, ...)
                for _, member in ipairs(deaths) do
                    local death = GambleEncounterTracker:RecordDeath(a, member.guid, member.name, member.unit)
                    if death then
                        Send("EBET_DEATH", a.id, death.guid, death.name, death.elapsed, death.order)
                        DebugEncounter(string.format("DEATH: %s t=%.2f", DisplayName(death.name), death.elapsed))
                        DebugEncounter("TOTAL_DEATHS: " .. tostring(a.encounterTracker.totalDeaths or 0))
                        if a.mode == "PULL_TIMER_DEATH" then
                            local option = GambleEncounterTracker:OptionForValue(a.mode, death.elapsed)
                            FinalizeEncounterBet(a, option and option.key, "FIRST DEATH", death.elapsed, death.name, death.elapsed, false, not option, false)
                            break
                        end
                    end
                end
                self:Refresh()
            elseif a.mode == "LAST_MAN_STANDING" then
                RecordLMSDeath(...)
            elseif a.mode == "BOSS_SERIES" and a.currentSeriesBoss and not a.seriesResults[a.currentSeriesBoss] then
                local guid, name = FindGroupDeath(...)
                if guid then
                    local index = a.currentSeriesBoss; a.seriesResults[index] = { guid = guid, name = name }; a.completedBosses = (a.completedBosses or 0) + 1
                    Send("SERIES_BOSS", a.id, index, guid, name); Print(DisplayName(name) .. " was, on " .. a.bosses[index].name .. " the first player to die."); self:Refresh()
                end
            elseif a.mode == "NEXT_PULL" or a.mode == "NEXT_BOSS" then ResolveGroupDeath(...) end
        end
    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        local unit = ...; local a = state.active
        if a and IsEncounterBetMode(a.mode) and a.locked and not a.result and GambleEncounterTracker then
            GambleEncounterTracker:RefreshAliveUnits(a)
            if a.mode == "BOSS_HP_WIPE" then GambleEncounterTracker:SampleBossHealth(a, unit) end
            local now = GetTime and GetTime() or time()
            if not state.lastEncounterUIRefresh or now - state.lastEncounterUIRefresh >= .25 then
                state.lastEncounterUIRefresh = now; self:Refresh()
            end
        end
    elseif event == "CHAT_MSG_ADDON" then
        self:OnAddonMessage(...)
    elseif event == "TRADE_SHOW" then
        state.tradeContext = nil
        local recipient = TradePartnerName()
        local escrowSender, escrowRequest = FindEscrowRequest(recipient)
        local escrowWager = escrowRequest and FindWager(escrowRequest.id)
        if escrowWager and SamePlayer(PlayerName(), escrowWager.host) then
            state.tradeContext = { direction = "incoming", sender = escrowSender, request = escrowRequest, offered = 0 }
            Print("Escrow stake from " .. escrowRequest.bettor .. " expected: " .. Money(escrowRequest.stake))
        elseif state.pendingJoin and SamePlayer(recipient, state.pendingJoin.host) then
            state.tradeContext = { direction = "outgoingJoin", request = state.pendingJoin }
            if self.escrowFrame then self.escrowFrame:Hide() end
            Print("Please enter " .. Money(state.pendingJoin.stake) .. " as your stake. Forever blocks automatic gold entry by addons.")
        else
            local payment = self:GetGroupedPayment(recipient)
            if payment then
            if recipient and not SamePlayer(recipient, payment.name) then
                Print("Safety stop: This trade is not with " .. payment.name .. ". No gold was entered.")
                state.pendingTrade = nil
                return
            end
            state.tradeContext = { direction = "payout", payment = payment }
            Print("Please enter " .. Money(payment.amount) .. " for " .. payment.name .. ". Forever blocks automatic gold entry by addons.")
            end
        end
        if not state.tradeContext then
            if recipient and CanRead(recipient) then
                state.tradeContext = { direction = "unassigned", partner = recipient, offered = 0 }
            end
            Print("Trade partner: " .. tostring(recipient or "unavailable") .. ". No matching pending bet payment was found. Join the bet before trading.")
        end
    elseif event == "TRADE_MONEY_CHANGED" or event == "TRADE_ACCEPT_UPDATE" then
        if state.tradeContext and state.tradeContext.direction=="payout" then
            local getter=C_TradeInfo and C_TradeInfo.GetPlayerTradeMoney or GetPlayerTradeMoney
            if getter then
                local ok,amount=pcall(getter)
                if ok and CanRead(amount) and type(amount)=="number" then
                    state.tradeContext.offered=floor(amount); state.tradeContext.moneyReadable=true
                else state.tradeContext.moneyReadable=nil end
            end
        end
        if state.tradeContext and (state.tradeContext.direction == "incoming" or state.tradeContext.direction == "unassigned") then
            local amount = ReadTargetTradeMoney()
            if amount then state.tradeContext.offered = amount; state.tradeContext.moneyReadable = true end
        end
        if state.tradeContext and event == "TRADE_ACCEPT_UPDATE" then
            local playerAccepted, targetAccepted = ...
            if CanRead(playerAccepted) and CanRead(targetAccepted) then
                state.tradeContext.bothAccepted = (playerAccepted == 1 or playerAccepted == true) and (targetAccepted == 1 or targetAccepted == true)
            end
        end
    elseif event == "UI_INFO_MESSAGE" or event == "CHAT_MSG_SYSTEM" then
        local arg1, arg2 = ...
        local message
        if event == "UI_INFO_MESSAGE" then message = arg2 else message = arg1 end
        if not CanRead(message) then return end
        if self:HandleInstanceResetMessage(message) then return end
        if message and ERR_TRADE_COMPLETE and message == ERR_TRADE_COMPLETE then
            local completedContext = state.tradeContext
            if completedContext then completedContext.confirmed = true end
            if state.tradeContext and state.tradeContext.direction == "payout" then self:CompletePayoutTrade() else self:CompleteEscrowTrade() end
            if completedContext and completedContext.direction == "outgoingJoin" and completedContext.request and completedContext.request.picks then
                local request = completedContext.request
                Send("SERIES_JOIN_BEGIN", request.id, request.totalStake, request.stake, #request.picks)
                for i, pick in ipairs(request.picks) do Send("SERIES_JOIN_PICK", request.id, i, pick.guid, pick.name) end
            end
            if completedContext and completedContext.direction == "unassigned" then
                C_Timer.After(30, function() if state.tradeContext == completedContext then state.tradeContext = nil end end)
            else state.tradeContext = nil end
        end
    elseif event == "TRADE_CLOSED" then
        state.pendingTrade = nil
        if state.tradeContext and state.tradeContext.bothAccepted then
            local completedContext = state.tradeContext
            if state.tradeContext.direction == "payout" then self:CompletePayoutTrade() else self:CompleteEscrowTrade() end
            if completedContext.direction == "outgoingJoin" and completedContext.request and completedContext.request.picks then
                local request = completedContext.request
                Send("SERIES_JOIN_BEGIN", request.id, request.totalStake, request.stake, #request.picks)
                for i, pick in ipairs(request.picks) do Send("SERIES_JOIN_PICK", request.id, i, pick.guid, pick.name) end
            end
            if completedContext.direction == "unassigned" then
                C_Timer.After(30, function() if state.tradeContext == completedContext then state.tradeContext = nil end end)
            else state.tradeContext = nil end
        elseif state.tradeContext then
            local closingContext = state.tradeContext
            C_Timer.After(closingContext.direction == "unassigned" and 30 or 3, function()
                if state.tradeContext == closingContext then
                    if closingContext.direction == "incoming" then Print("Trade closed without a readable completion confirmation. Payment remains unconfirmed; do not pay again.") end
                    state.tradeContext = nil
                end
            end)
        end
    end
end

local eventFrame = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "ENCOUNTER_START", "ENCOUNTER_END", "BOSS_KILL", "UNIT_DIED", "UNIT_HEALTH", "UNIT_MAXHEALTH", "CHAT_MSG_LOOT", "LOOT_OPENED", "CHAT_MSG_ADDON", "TRADE_SHOW", "TRADE_MONEY_CHANGED", "TRADE_ACCEPT_UPDATE", "TRADE_CLOSED", "UI_INFO_MESSAGE", "CHAT_MSG_SYSTEM" }) do eventFrame:RegisterEvent(event) end
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:SetScript("OnEvent", function(_, event, ...) Gamble:OnEvent(event, ...) end)

SLASH_GAMBLE1 = "/gamble"
SlashCmdList.GAMBLE = function(input)
    local command = strtrim(input or ""):lower()
    if command == "hide" then Gamble.frame:Hide()
    elseif command == "status" then
        local a = state.active
        if not a then Print("No open bet.")
        elseif a.result then Print("Result: " .. a.result.name .. "; " .. #OrderedBets() .. " stake(s).")
        else Print((a.locked and "Running" or "Open") .. ": " .. #OrderedBets() .. " stake(s), Minimum " .. Money(a.minimum) .. ".") end
    elseif command == "pay" then Gamble:PayNext()
    elseif command == "debugmeter" or command:match("^debugmeter%s+%d+$") then
        GambleDamageBets:DebugMeter(Gamble,command:match("%d+$"))
    elseif command == "debugboss" then
        GambleDamageBets.debugBoss=not GambleDamageBets.debugBoss
        Print("Boss-Debug "..(GambleDamageBets.debugBoss and "aktiv" or "aus")..". Boss ins Ziel nehmen; /gamble debugboss status zeigt den aktuellen Zustand.")
        if GambleDamageBets.debugBoss then GambleDamageBets:DebugBossTarget(Gamble,"manuell") end
    elseif command == "debugboss status" then
        GambleDamageBets:DebugBossTarget(Gamble,"Status")
    elseif command == "debug" then
        GambleDB.debug = not GambleDB.debug
        Print("Debug mode " .. (GambleDB.debug and "enabled" or "disabled") .. ".")
    elseif command == "paid" then
        if #state.payments > 0 then local done = table.remove(state.payments, 1); Print("Marked as paid: " .. Money(done.amount) .. "  to " .. done.name); Gamble:Refresh() else Print("No pending payment.") end
    elseif command == "cancel" then
        Gamble:RequestCancel()
    elseif command == "finish" then
        local a = state.active
        if a and a.mode == "BOSS_SERIES" and a.locked and not a.result and SamePlayer(a.host, PlayerName()) then FinalizeSeries() else Print("No boss series available to finalize.") end
    elseif command == "comm" then
        local channel = Channel()
        local peerCount = 0
        for player in pairs(state.knownVersions) do if not SamePlayer(player, PlayerName()) then peerCount = peerCount + 1 end end
        Print("Communication: Channel=" .. tostring(channel or "none") .. ", Prefix=" .. (state.prefixRegistered and "registered" or "NOT registered") .. ", detected clients=" .. peerCount .. ".")
        if state.prefixRegisterError then Print("Prefix error: " .. state.prefixRegisterError) end
        if state.lastCommError then Print("Last send error: " .. state.lastCommError) end
        if channel then Send("PING", ADDON_VERSION); Print("Test message sent. The other client should turn green within a few seconds.")
        else Print("No group detected; unable to send a test message.") end
    elseif command:match("^minimap") then
        local radius, angle = command:match("^minimap%s+(%d+)%s*([%-]?%d*)$")
        radius, angle = tonumber(radius), tonumber(angle)
        if not radius then
            Print("Usage: /gamble minimap 94 or /gamble minimap 94 225")
        else
            GambleDB.minimapRadius = math.max(55, math.min(140, radius))
            if angle then GambleDB.minimapAngle = angle % 360 end
            PositionMinimapButton(Gamble.minimapButton)
            Print("Minimap icon: Radius " .. GambleDB.minimapRadius .. ", Angle " .. floor(GambleDB.minimapAngle or DEFAULT_MINIMAP_ANGLE) .. "°.")
        end
    elseif command == "reset" then
        if state.active and not state.active.result then Print("An active bet cannot be reset.") else if state.active then RemoveWager(state.active) end; state.active = nil; state.selectedType = nil; state.selectedBoss = nil; wipe(state.seriesPicks); state.seriesStep = 1; UIDropDownMenu_SetText(Gamble.typeDropdown, "Select a bet type …"); UIDropDownMenu_SetText(Gamble.bossDropdown, "Boss: auto-detect"); wipe(state.payments); Gamble:Refresh() end
    else Gamble.frame:Show(); Gamble:Refresh() end
end
