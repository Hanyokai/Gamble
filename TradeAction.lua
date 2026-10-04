-- Only prepares a user-clicked trade; settlement and money handling remain with callers.
GambleTradeAction = {}
local Trade = GambleTradeAction
local buttons = {}
local function Combat() return InCombatLockdown and InCombatLockdown() end
local function Name(unit)
    local name, realm = UnitFullName(unit)
    if not name and UnitName then name, realm = UnitName(unit) end
    return name and (realm and realm ~= "" and (name .. "-" .. realm) or name)
end
local function CharacterName(name)
    -- Forever can expose names such as "Yin Yang", while rolls and saved
    -- participants contain just "Yin". Only use this fallback if unique.
    return name and name:match("^([^%- ]+)"):lower()
end
function Trade:Resolve(name, guid)
    local matches = {}
    local raid = IsInRaid()
    local count = raid and GetNumGroupMembers() or GetNumSubgroupMembers()
    for i = 1, count do
        local unit = (raid and "raid" or "party") .. i
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            local full = Name(unit)
            if guid and UnitGUID(unit) == guid then return unit end
            if not guid and full and name and full:lower() == name:lower() then return unit end
            if not guid and full and name and CharacterName(full) == CharacterName(name) then matches[#matches + 1] = unit end
        end
    end
    if #matches == 1 then return matches[1] end
end
local function Range(unit)
    local inRange, distance
    local ok = pcall(function()
        local value = CheckInteractDistance and CheckInteractDistance(unit, 2)
        if canaccessvalue and not canaccessvalue(value) then return end
        if issecretvalue and issecretvalue(value) then return end
        inRange = value == true or value == 1
    end)
    if not ok then inRange = nil end
    if UnitDistanceSquared then
        pcall(function()
            local squared, checked = UnitDistanceSquared(unit)
            if checked == false then return end
            if canaccessvalue and not canaccessvalue(squared) then return end
            if issecretvalue and issecretvalue(squared) then return end
            if type(squared) == "number" and squared >= 0 then distance = math.sqrt(squared) end
        end)
    end
    return inRange, distance
end
function Trade:Prepare(button)
    if Combat() then
        button.pendingTradeRefresh = true
        -- These are non-protected, out-of-combat action buttons. Disable their
        -- click handler in combat without touching action attributes.
        button:SetEnabled(false)
        return
    end
    button.pendingTradeRefresh = nil
    local intent = button.tradeProvider()
    button:SetAttribute("type", nil)
    button:SetAttribute("macrotext", nil)
    button.tradeIntent = intent
    if not intent then button:Hide(); return end
    local unit = self:Resolve(intent.name, intent.guid)
    local reason, distance
    if not unit then reason = "The trade partner cannot be uniquely identified in your party or raid."
    elseif not UnitIsConnected(unit) then reason = "The trade partner is offline."
    else
        local inRange
        inRange, distance = Range(unit)
        if not inRange then reason = inRange == false and "Move closer to the trade partner." or "Trade range is unavailable." end
    end
    button.tradeError = reason
    local label = intent.label or ("Trade with " .. (intent.name:match("^[^-]+") or intent.name))
    if reason then label = label .. (distance and string.format(" (approx. %.1f m)", distance) or " (unavailable)") end
    button:SetText(label)
    button:Show()
    button:SetEnabled(not reason)
    if unit and not reason then
        button.tradeGUID = UnitGUID(unit)
        button:SetAttribute("type", "macro")
        button:SetAttribute("macrotext", "/stopmacro [combat]\n/target [@" .. unit .. ",exists]\n/trade")
    end
end
function Trade:Attach(button, provider, notify)
    button.tradeProvider, button.tradeNotify = provider, notify
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetAttribute("useOnKeyDown", false)
    button:SetScript("PreClick", function(owner, _, down)
        if down then return end
        if Combat() then owner.tradeNotify("Trading is unavailable in combat. Click again after combat."); return end
        Trade:Prepare(owner)
        local intent = owner.tradeIntent
        if not intent then owner.tradeNotify("This payment has already been completed or cancelled."); return end
        if owner.tradeError then owner.tradeNotify(owner.tradeError); return end
        if intent.prepare then intent.prepare() end
    end)
    button:SetScript("PostClick", function(owner, _, down)
        if down or Combat() or not owner.tradeIntent or owner.tradeError then return end
        C_Timer.After(1.5, function()
            if not (TradeFrame and TradeFrame:IsShown()) then
                owner.tradeNotify("Trade did not open. Check range and availability. If the beta blocks the macro: right-click the target portrait and choose Trade.")
            end
        end)
    end)
    button:SetScript("OnEnter", function(owner)
        Trade:Prepare(owner)
        if owner.tradeError then
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            GameTooltip:SetText(owner.tradeError)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    buttons[#buttons + 1] = button
    self:Prepare(button)
end
local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "GROUP_ROSTER_UPDATE", "UNIT_CONNECTION", "TRADE_CLOSED" }) do events:RegisterEvent(event) end
events:SetScript("OnEvent", function() for _, button in ipairs(buttons) do Trade:Prepare(button) end end)
-- Local polling only: no addon messages. Refresh disabled buttons as players
-- move, and leave protected attributes untouched during combat.
local rangeElapsed = 0
events:SetScript("OnUpdate", function(_, elapsed)
    rangeElapsed = rangeElapsed + elapsed
    if rangeElapsed < .25 then return end
    rangeElapsed = 0
    if Combat() then return end
    for _, button in ipairs(buttons) do
        if button:IsVisible() then Trade:Prepare(button) end
    end
end)
