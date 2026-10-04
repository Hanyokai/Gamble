local ADDON_NAME = ...
local function CanRead(value)
    if canaccessvalue then return canaccessvalue(value) end
    if issecretvalue then return not issecretvalue(value) end
    return true
end
local CreateFrame = GambleUIStyle and GambleUIStyle.CreateFrame or CreateFrame

GambleDON = GambleDON or {}
local DON = GambleDON

local PREFIX = "GambleDON1"
local PROTOCOL = 4
local ADDON_VERSION = "0.17.5"
local floor, max, min = math.floor, math.max, math.min
local session
local ui = {}
local pendingRoll
local tradeContext
local debugEnabled = false
local incompatiblePeers = {}
local ShowWinnerPopup

local function RefreshMainAddon()
    local main = ui.main
    if main and main.frame and main.Refresh and not ui.refreshingMain then
        ui.refreshingMain = true
        main:Refresh()
        ui.refreshingMain = nil
    end
end

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffd8b65cGamble:|r " .. tostring(message))
end

local function Debug(message)
    if debugEnabled then DEFAULT_CHAT_FRAME:AddMessage("|cff8888ffDON Debug:|r " .. tostring(message)) end
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

local function CharacterStorageKey()
    return tostring(PlayerName()):lower()
end

local function ShortName(name)
    if not name then return "?" end
    if Ambiguate then
        local ok, short = pcall(Ambiguate, name, "short")
        if ok and short and short ~= "" then return short:match("^([^%- ]+)") or short end
    end
    return name:match("^([^%- ]+)") or name
end

local function Key(name)
    return ShortName(name):lower()
end

local function SamePlayer(a, b)
    return a and b and Key(a) == Key(b)
end

local function Money(copper)
    copper = max(0, floor(tonumber(copper) or 0))
    local gold, silver, coins = floor(copper / 10000), floor((copper % 10000) / 100), copper % 100
    return string.format("%d|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:1:0|t %02d|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:1:0|t %02d|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:1:0|t", gold, silver, coins)
end

local function Safe(value)
    return tostring(value or ""):gsub("[\t\r\n]", " ")
end

local function Split(message)
    local values = {}
    for part in (message .. "\t"):gmatch("(.-)\t") do values[#values + 1] = part end
    return values
end

local function Channel()
    if LE_PARTY_CATEGORY_INSTANCE then
        local ok, grouped = pcall(IsInGroup, LE_PARTY_CATEGORY_INSTANCE)
        if ok and grouped then return "INSTANCE_CHAT" end
    end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

function DON:RoundWinnerText(entries,round,maxRounds)
    maxRounds=maxRounds or 5
    local best,names=-1,{}
    for _,entry in ipairs(entries or {}) do
        if entry.round==round then
            local roll=entry.roll or 0
            if roll>best then best,names=roll,{ShortName(entry.name)}
            elseif roll==best then names[#names+1]=ShortName(entry.name) end
        end
    end
    if best<0 then return nil end
    table.sort(names)
    if round<=maxRounds and best<=50 then return "Runde "..round..": Kein Sieger – alle OUT." end
    return "Runde "..round..": "..(#names>1 and "Sieger (Gleichstand): " or "Sieger: ")..table.concat(names,", ").." – höchster Wurf: "..best
end
function DON:HistoryLines(history,maxRounds)
    local lines,round={},nil
    local function finish()
        if round then lines[#lines+1]="|cff55ff55"..self:RoundWinnerText(history,round,maxRounds).."|r" end
    end
    for _,entry in ipairs(history or {}) do
        if round and round~=entry.round then finish(); lines[#lines+1]="" end
        round=entry.round
        lines[#lines+1]=string.format("Round %d: %s — %d — %s",entry.round or 0,ShortName(entry.name),entry.roll or 0,entry.result or "")
    end
    finish(); return lines
end

local outgoingTarget
local sendQueue, queueHead, sending = {}, 1, false
local function DrainQueue()
    local item = sendQueue[queueHead]
    if not item then sendQueue, queueHead, sending = {}, 1, false; return end
    sendQueue[queueHead] = false; queueHead = queueHead + 1
    local sender = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
    if sender then pcall(sender, PREFIX, item.payload, item.channel, item.target) end
    C_Timer.After(max(.08, (#item.payload + #PREFIX) / 1500), DrainQueue)
end
local function Send(...)
    local channel = outgoingTarget and "WHISPER" or Channel()
    if not channel then return false end
    local fields = { ... }
    for index = 1, #fields do fields[index] = Safe(fields[index]) end
    local payload = table.concat(fields, "\t")
    local item = { payload = payload, channel = channel, target = outgoingTarget }
    if fields[1] == "ROLL" or fields[1] == "ROLL_ACK" then table.insert(sendQueue, queueHead, item)
    else sendQueue[#sendQueue + 1] = item end
    if not sending then sending = true; C_Timer.After(0, DrainQueue) end
    Debug("SEND " .. payload)
    return true
end

local function IsGroupMember(name)
    if SamePlayer(name, PlayerName()) then return true end
    local prefix = IsInRaid() and "raid" or "party"
    local count = IsInRaid() and GetNumGroupMembers() or GetNumSubgroupMembers()
    for index = 1, count do
        local unit = prefix .. index
        if UnitExists(unit) and SamePlayer(name, FullName(unit) or UnitName(unit)) then return true end
    end
    return false
end

local function ClassColor(name)
    local prefix = IsInRaid() and "raid" or "party"
    local count = IsInRaid() and GetNumGroupMembers() or GetNumSubgroupMembers()
    for index = 0, count do
        local unit = index == 0 and "player" or (prefix .. index)
        if UnitExists(unit) and SamePlayer(name, FullName(unit) or UnitName(unit)) then
            local _, class = UnitClass(unit)
            local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
            if color then return string.format("|cff%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255) end
        end
    end
    return "|cffffffff"
end

local function IsHost()
    return session and SamePlayer(session.host, PlayerName())
end

local function Participant(name)
    if not session then return nil end
    return session.players[Key(name)]
end

local function PlayerCount()
    local count = 0
    if session then for _ in pairs(session.players) do count = count + 1 end end
    return count
end

local function Pot()
    local pot = 0
    if session then for _, player in pairs(session.players) do if player.paid then pot = pot + session.stake end end end
    return pot
end

local function WinnerAmount()
    local amount = Pot()
    if session and session.winner and SamePlayer(session.winner, session.host) then
        amount = max(0, amount - (tonumber(session.stake) or 0))
    end
    return amount
end

local function TradeIntent()
    if not session then return end
    local me = Participant(PlayerName())
    if session.status == "PAYOUT" and IsHost() and not session.payoutDone and not SamePlayer(session.winner, session.host) then
        return { name = session.winner, label = "Pay Winner", prepare = function() DON:PreparePayout() end }
    elseif session.status == "LOBBY" and me and not me.paid and not IsHost() then
        return { name = session.host, prepare = function() Print("Payment: " .. Money(session.stake) .. " to " .. ShortName(session.host) .. ". Enter gold manually.") end }
    end
end

local function SyncBankSession()
    if not GambleBankSecurity or not session or not SamePlayer(session.host, PlayerName()) then return true end
    local ok, reason = GambleBankSecurity:RegisterWager(session.id, session.stake, session.stake)
    if not ok and reason ~= "ALREADY_FUNDED" and reason ~= "DUPLICATE_IGNORED" then return false, reason end
    for _, player in pairs(session.players or {}) do if player.paid then GambleBankSecurity:RegisterDeposit(session.id, player.name, session.stake) end end
    if session.status == "RUNNING" then GambleBankSecurity:ActivateWager(session.id) end
    if session.status == "PAYOUT" or session.status == "DONE" then
        local obligations = {}
        if session.winner and not SamePlayer(session.winner, session.host) and not session.payoutDone then obligations[1] = { name = session.winner, amount = WinnerAmount(), reason = "Winnings" } end
        GambleBankSecurity:ResolveWager(session.id, obligations, 0, "DOUBLE_OR_NOTHING")
    end
    return true
end

local function ActiveCount()
    local count, last = 0
    if session then
        for _, player in pairs(session.players) do
            if player.active then count, last = count + 1, player end
        end
    end
    return count, last
end

local function Save()
    GambleDONDB = GambleDONDB or {}
    GambleDONDB.version = PROTOCOL
    GambleDONDB.sessionsByCharacter = GambleDONDB.sessionsByCharacter or {}
    GambleDONDB.sessionsByCharacter[CharacterStorageKey()] = session
    GambleDONDB.debug = debugEnabled
end

local function Bump()
    if session then session.revision = (tonumber(session.revision) or 0) + 1; session.updatedAt = time() end
    Save()
end

local function NewID()
    return tostring(time()) .. "-" .. tostring(math.random(100000, 999999))
end

local function StatusText(status)
    local labels = { LOBBY = "LOBBY", RUNNING = "RUNNING", PAYOUT = "PAYOUT PENDING", DONE = "COMPLETED", ABORTED = "CANCELLED" }
    return labels[status] or tostring(status or "-")
end

local function OrderedPlayers()
    local result = {}
    if session then for _, player in pairs(session.players) do result[#result + 1] = player end end
    table.sort(result, function(a, b)
        if a.joinedAt ~= b.joinedAt then return (a.joinedAt or 0) < (b.joinedAt or 0) end
        return a.name < b.name
    end)
    return result
end

local historySentID, historySentCount = nil, 0
local function BroadcastStateNow(target)
    if not IsHost() then return end
    local command = target and "SYNC" or "STATE"
    outgoingTarget = target
    local fullHistory = target or historySentID ~= session.id
    local historyStart = fullHistory and 1 or (historySentCount + 1)
    Send(command, PROTOCOL, session.id, session.revision, session.host, session.stake, session.maxPlayers, session.maxRounds, session.status, session.round, session.winner or "", Pot(), session.payoutDone and 1 or 0, fullHistory and 1 or 0)
    for _, player in ipairs(OrderedPlayers()) do
        Send("PLAYER", session.id, session.revision, player.name, player.ready and 1 or 0, player.paid and 1 or 0, player.active and 1 or 0, player.connected == false and 0 or 1, player.roll or 0, player.result or "", player.joinedAt or 0, player.points or 0)
    end
    for index = historyStart, #(session.history or {}) do
        local entry = session.history[index]
        Send("HISTORY", session.id, session.revision, entry.round, entry.name, entry.roll, entry.result)
    end
    Send("STATE_END", session.id, session.revision)
    if not target then historySentID, historySentCount = session.id, #(session.history or {}) end
    outgoingTarget = nil
end
local broadcastPending = false
local function BroadcastState(target)
    if target then BroadcastStateNow(target); return end
    if broadcastPending then return end
    broadcastPending = true
    C_Timer.After(.15, function() broadcastPending = false; BroadcastStateNow() end)
end

local function CloseSettledWinnerPopup()
    if not session or not session.payoutDone or session.status ~= "DONE" then return end
    ui.pendingWinnerPopup = nil
    if ui.winnerFrame and not (InCombatLockdown and InCombatLockdown()) then
        ui.winnerFrame:Hide()
    end
end

local function Refresh()
    CloseSettledWinnerPopup()
    if not ui.frame then return end
    local s = session
    ui.noSession:SetShown(not s)
    ui.sessionArea:SetShown(s ~= nil)
    ui.createButton:SetShown(not s or s.status == "DONE" or s.status == "ABORTED")
    ui.joinButton:Hide(); ui.leaveButton:Hide(); ui.readyButton:Hide(); ui.startButton:Hide(); ui.rollButton:Hide(); ui.payoutButton:Hide(); ui.abortButton:Hide()
    if not s then RefreshMainAddon(); return end

    local me = Participant(PlayerName())
    ui.title:SetText("DOUBLE OR NOTHING — " .. StatusText(s.status))
    ui.host:SetText("Bank: " .. ClassColor(s.host) .. ShortName(s.host) .. "|r")
    ui.pot:SetText("Pot: " .. Money(Pot()) .. "    Stake: " .. Money(s.stake) .. "    Round: " .. (s.round or 0) .. "/" .. (s.maxRounds or 5))
    ui.capacity:SetText("Players: " .. PlayerCount() .. "/" .. s.maxPlayers)

    if s.status == "LOBBY" then
        if not me and PlayerCount() < s.maxPlayers then ui.joinButton:Show() end
        if me and not SamePlayer(me.name, s.host) then ui.leaveButton:Show() end
        if me and not SamePlayer(me.name, s.host) then ui.readyButton:SetText((me.paid and me.ready) and "Not Ready" or "Ready"); ui.readyButton:SetEnabled(me.paid == true); ui.readyButton:Show() end
        if IsHost() then ui.startButton:Show(); ui.abortButton:Show() end
    elseif s.status == "RUNNING" then
        if me and me.active and not me.roll then ui.rollButton:Show() end
        if IsHost() then ui.abortButton:Show() end
    elseif s.status == "PAYOUT" then
        if IsHost() and not s.payoutDone then
            ui.payoutButton:SetText(SamePlayer(s.winner, s.host) and "Settle Winnings" or "Pay Winner")
            ui.payoutButton:Show()
        end
    end

    local canStart = IsHost() and s.status == "LOBBY" and PlayerCount() >= 2
    if canStart then
        for _, player in pairs(s.players) do
            if not player.ready or not player.paid or player.connected == false then canStart = false; break end
        end
    end
    ui.startButton:SetEnabled(canStart and true or false)
    ui.startButton:SetText(canStart and "Start Game" or "Waiting for Ready & Payment")

    for _, row in ipairs(ui.rows) do row:Hide() end
    for index, player in ipairs(OrderedPlayers()) do
        local row = ui.rows[index]
        if not row then
            row = CreateFrame("Frame", nil, ui.content, "BackdropTemplate")
            row:SetSize(520, 42)
            row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10 })
            row:SetBackdropColor(0.04, 0.04, 0.04, 0.82); row:SetBackdropBorderColor(0.35, 0.28, 0.12, 0.9)
            if GambleUIStyle then GambleUIStyle:Row(row) end
            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal"); row.name:SetPoint("LEFT", 10, 7)
            row.money = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); row.money:SetPoint("LEFT", 10, -10)
            row.state = row:CreateFontString(nil, "OVERLAY", "GameFontNormal"); row.state:SetPoint("RIGHT", -10, 7)
            row.roll = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); row.roll:SetPoint("RIGHT", -10, -10)
            ui.rows[index] = row
        end
        row:SetPoint("TOPLEFT", 2, -((index - 1) * 46))
        row.name:SetText(ClassColor(player.name) .. ShortName(player.name) .. "|r" .. (player.connected == false and " |cff888888(offline)|r" or ""))
        row.money:SetText(Money(s.stake) .. " · Points: " .. (player.points or 0) .. (player.paid and "  |cff55ff55PAID|r" or "  |cffff5555NOT PAID|r"))
        local stateText
        if s.status == "LOBBY" then stateText = (player.paid and player.ready) and "|cff55ff55READY|r" or "|cffffcc55NOT READY|r"
        elseif player.active then stateText = "|cff55ff55ACTIVE|r" else stateText = "|cffff5555OUT|r" end
        row.state:SetText(stateText)
        row.roll:SetText(player.roll and ("Roll: " .. player.roll .. "  " .. (player.result or "")) or (s.status == "RUNNING" and player.active and "⏳ waiting" or ""))
        row:Show()
    end
    local historyLines = DON:HistoryLines(s.history, s.maxRounds)
    ui.history:ClearAllPoints()
    ui.history:SetPoint("TOPLEFT", 8, -(PlayerCount() * 46 + 10)); ui.history:SetPoint("RIGHT", -8, 0)
    ui.history:SetText(#historyLines > 0 and ("|cffffd100Roll History|r\n" .. table.concat(historyLines, "\n")) or "")
    ui.content:SetHeight(max(1, PlayerCount() * 46 + (#historyLines > 0 and (#historyLines * 15 + 34) or 0)))

    if s.status == "PAYOUT" then
        if SamePlayer(s.winner, s.host) then
            ui.notice:SetText("|cffffd100WINNER: " .. ShortName(s.winner) .. "|r\nBANK NET WINNINGS: " .. Money(WinnerAmount()))
        else
            ui.notice:SetText("|cffffd100WINNER: " .. ShortName(s.winner) .. "|r\nPAYMENT PENDING: " .. Money(WinnerAmount()) .. " an " .. ShortName(s.winner))
        end
        local resultKey = s.id .. ":" .. tostring(s.winner)
        if ui.announcedResultKey ~= resultKey then ui.announcedResultKey = resultKey; ShowWinnerPopup() end
    elseif s.status == "DONE" then
        ui.notice:SetText("|cff55ff55Payout completed: " .. ShortName(s.winner) .. " won " .. Money(WinnerAmount()) .. ".|r")
    elseif s.status == "ABORTED" then
        ui.notice:SetText("|cffff5555Game cancelled. Paid stakes must be refunded manually.|r")
    else ui.notice:SetText("") end
    RefreshMainAddon()
end

local function MakeButton(parent, width, text)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 26); button:SetText(text)
    return button
end

local function MakeMoneyBox(parent, x, label)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(62, 24); box:SetPoint("TOPLEFT", x, -99); box:SetAutoFocus(false); box:SetNumeric(true); box:SetMaxLetters(7); box:SetText("0")
    local icon = parent:CreateTexture(nil, "ARTWORK"); icon:SetSize(15, 15); icon:SetPoint("LEFT", box, "RIGHT", 3, 0); icon:SetTexture(label)
    return box
end

local function StakeFromBoxes()
    if ui.embedded and ui.embedded:IsShown() and ui.embGold then
        return (tonumber(ui.embGold:GetText()) or 0) * 10000 + (tonumber(ui.embSilver:GetText()) or 0) * 100 + (tonumber(ui.embCopper:GetText()) or 0)
    end
    return (tonumber(ui.gold:GetText()) or 0) * 10000 + (tonumber(ui.silver:GetText()) or 0) * 100 + (tonumber(ui.copper:GetText()) or 0)
end

local function CreateUI()
    if ui.frame then return end
    local frame = CreateFrame("Frame", "GambleDoubleOrNothingFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(590, 650); frame:SetPoint("CENTER"); frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving); frame:SetScript("OnDragStop", frame.StopMovingOrSizing); frame:Hide()
    frame.TitleText:SetText("Gamble – Double or Nothing")
    ui.frame = frame

    local intro = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); intro:SetPoint("TOPLEFT", 22, -38); intro:SetText("Stake per player:")
    ui.gold = MakeMoneyBox(frame, 150, "Interface\\MoneyFrame\\UI-GoldIcon"); ui.silver = MakeMoneyBox(frame, 245, "Interface\\MoneyFrame\\UI-SilverIcon"); ui.copper = MakeMoneyBox(frame, 350, "Interface\\MoneyFrame\\UI-CopperIcon")
    ui.gold:ClearAllPoints(); ui.gold:SetPoint("TOPLEFT", 150, -64); ui.silver:ClearAllPoints(); ui.silver:SetPoint("TOPLEFT", 245, -64); ui.copper:ClearAllPoints(); ui.copper:SetPoint("TOPLEFT", 350, -64)
    local maxLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); maxLabel:SetPoint("TOPLEFT", 22, -101); maxLabel:SetText("Rounds:")
    ui.maxRounds = CreateFrame("EditBox", nil, frame, "InputBoxTemplate"); ui.maxRounds:SetSize(45, 24); ui.maxRounds:SetPoint("TOPLEFT", 150, -94); ui.maxRounds:SetNumeric(true); ui.maxRounds:SetMaxLetters(2); ui.maxRounds:SetText("5"); ui.maxRounds:SetAutoFocus(false)
    ui.createButton = MakeButton(frame, 180, "Create Game"); ui.createButton:SetPoint("TOPRIGHT", -22, -92)

    ui.noSession = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); ui.noSession:SetPoint("CENTER", 0, 80); ui.noSession:SetText("No Double or Nothing lobby found.\nCreate a game or wait for the host.")
    ui.sessionArea = CreateFrame("Frame", nil, frame); ui.sessionArea:SetAllPoints()
    ui.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); ui.title:SetPoint("TOPLEFT", 22, -137)
    ui.host = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); ui.host:SetPoint("TOPLEFT", 22, -164)
    ui.pot = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal"); ui.pot:SetPoint("TOPLEFT", 22, -186)
    ui.capacity = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); ui.capacity:SetPoint("TOPRIGHT", -28, -164)

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate"); scroll:SetPoint("TOPLEFT", 20, -214); scroll:SetPoint("BOTTOMRIGHT", -42, 176)
    ui.content = CreateFrame("Frame", nil, scroll); ui.content:SetSize(520, 1); scroll:SetScrollChild(ui.content); ui.rows = {}
    ui.history = ui.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); ui.history:SetJustifyH("LEFT"); ui.history:SetJustifyV("TOP")
    ui.notice = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal"); ui.notice:SetPoint("BOTTOMLEFT", 22, 135); ui.notice:SetPoint("BOTTOMRIGHT", -22, 135); ui.notice:SetJustifyH("CENTER")

    ui.joinButton = MakeButton(frame, 112, "Join"); ui.joinButton:SetPoint("BOTTOMLEFT", 20, 94)
    ui.leaveButton = MakeButton(frame, 112, "Leave"); ui.leaveButton:SetPoint("BOTTOMLEFT", 20, 94)
    ui.readyButton = MakeButton(frame, 112, "Ready"); ui.readyButton:SetPoint("BOTTOMLEFT", 140, 94)
    ui.startButton = MakeButton(frame, 220, "Start Game"); ui.startButton:SetPoint("BOTTOMRIGHT", -20, 94)
    ui.rollButton = MakeButton(frame, 280, "ROLL (1–100)"); ui.rollButton:SetSize(280, 42); ui.rollButton:SetPoint("BOTTOM", 0, 82)
    local rollIcon = ui.rollButton:CreateTexture(nil, "ARTWORK")
    rollIcon:SetSize(32, 32); rollIcon:SetPoint("RIGHT", ui.rollButton, "LEFT", -6, 0)
    rollIcon:SetAtlas("lootroll-toast-icon-need-up", false)
    ui.payoutButton = MakeButton(frame, 260, "Pay Winner"); ui.payoutButton:SetPoint("BOTTOM", 0, 94)
    ui.abortButton = MakeButton(frame, 130, "Cancel Game"); ui.abortButton:SetPoint("BOTTOMLEFT", 20, 56)
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); hint:SetPoint("BOTTOMLEFT", 20, 23); hint:SetText("Double or Nothing is integrated into Gamble's main window.")

    ui.createButton:SetScript("OnClick", function() DON:CreateGame() end)
    ui.joinButton:SetScript("OnClick", function() if session then Send("JOIN", session.id, session.revision) end end)
    ui.leaveButton:SetScript("OnClick", function() if session then Send("LEAVE", session.id, session.revision) end end)
    ui.readyButton:SetScript("OnClick", function() local me = Participant(PlayerName()); if session and me and me.paid then Send("READY", session.id, session.revision, me.ready and 0 or 1) end end)
    ui.startButton:SetScript("OnClick", function() DON:StartGame() end)
    ui.rollButton:SetScript("OnClick", function() DON:Roll() end)
    ui.payoutButton:SetScript("OnClick", function() DON:PreparePayout() end)
    ui.abortButton:SetScript("OnClick", function() DON:Abort() end)

    local winner = CreateFrame("Frame", "GambleDONWinnerFrame", UIParent, "BasicFrameTemplateWithInset")
    winner:SetSize(420, 265); winner:SetPoint("TOP", UIParent, "TOP", 0, -60); winner:SetFrameStrata("FULLSCREEN_DIALOG"); winner:SetClampedToScreen(true); winner:Hide()
    winner:SetMovable(true); winner:EnableMouse(true); winner:RegisterForDrag("LeftButton")
    winner:SetScript("OnDragStart",winner.StartMoving); winner:SetScript("OnDragStop",winner.StopMovingOrSizing)
    winner.TitleText:SetText("Double or Nothing – Winner")
    winner.name = winner:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge"); winner.name:SetPoint("TOP", 0, -58)
    winner.amount = winner:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge"); winner.amount:SetPoint("TOP", winner.name, "BOTTOM", 0, -18)
    winner.rounds = winner:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); winner.rounds:SetPoint("TOP", winner.amount, "BOTTOM", 0, -12)
    ui.winnerFrame = winner
    ui.winnerTrade = CreateFrame("Button", nil, winner, "UIPanelButtonTemplate,InsecureActionButtonTemplate")
    ui.winnerTrade:SetSize(250, 26); ui.winnerTrade:SetPoint("BOTTOM", 0, 53)
    GambleTradeAction:Attach(ui.winnerTrade, TradeIntent, Print)
end

ShowWinnerPopup = function()
    if not session or session.status ~= "PAYOUT" or not ui.winnerFrame then return end
    if InCombatLockdown and InCombatLockdown() then ui.pendingWinnerPopup = true; return end
    ui.pendingWinnerPopup = nil
    GambleTradeAction:Prepare(ui.winnerTrade)
    ui.winnerFrame.name:SetText("|cffffd100WINNER: " .. ShortName(session.winner) .. "|r")
    ui.winnerFrame.amount:SetText("Winnings: " .. Money(WinnerAmount()))
    ui.winnerFrame.rounds:SetText("Rounds played: " .. tostring(session.round or 0))
    ui.winnerFrame:Show(); ui.winnerFrame:Raise()
end

function DON:CreateGame()
    if session and session.status ~= "DONE" and session.status ~= "ABORTED" then Print("A Double or Nothing game is already active."); return end
    if not Channel() then Print("You must be in a party or raid."); return end
    local stake, limit = floor(StakeFromBoxes()), 40
    local roundsBox = ui.embedded and ui.embedded:IsShown() and ui.embRounds or ui.maxRounds
    local maxRounds = floor(tonumber(roundsBox and roundsBox:GetText()) or 0)
    if stake <= 0 then Print("The stake must be greater th to 0."); return end
    if maxRounds < 1 or maxRounds > 50 then Print("The round count must be between 1 and 50."); return end
    if GetMoney and GetMoney() < stake then Print("Not enough gold for your stake."); return end
    if GambleBankSecurity then
        local allowed, reason = GambleBankSecurity:CanCreateFinancialObligation(stake, stake)
        if not allowed then Print("BET BLOCKED – " .. tostring(reason) .. ". Open Bank Status in the main window."); return end
    end
    local me = PlayerName()
    session = { id = NewID(), host = me, stake = stake, maxPlayers = limit, maxRounds = maxRounds, status = "LOBBY", round = 0, revision = 1, createdAt = time(), players = {}, history = {} }
    session.players[Key(me)] = { name = me, ready = true, paid = true, active = true, connected = true, joinedAt = time() }
    local bankOK, bankReason = SyncBankSession()
    if not bankOK then session = nil; Print("BET BLOCKED – " .. tostring(bankReason)); Save(); Refresh(); return end
    Save(); BroadcastState(); Refresh(); Print("Lobby opened. The host stake is reserved in the pot.")
    self:ShowDetails()
end

function DON:StartGame()
    if not IsHost() or not session or session.status ~= "LOBBY" then return end
    if PlayerCount() < 2 then Print("At least two players are required."); return end
    for _, player in pairs(session.players) do
        if not player.ready or not player.paid or player.connected == false then Print("All players must be online, ready and fully paid."); return end
        player.active, player.roll, player.result, player.points = true, nil, nil, 0
    end
    if GetMoney and GetMoney() < Pot() then Print("Safety stop: The bank holds less gold th to the total pot."); return end
    session.status, session.round = "RUNNING", 1
    Bump(); BroadcastState(); Refresh(); Print("Round 1 begins – each active player rolls.")
end

function DON:Roll()
    local me = Participant(PlayerName())
    if not session or session.status ~= "RUNNING" or not me or not me.active or me.roll then Print("You cannot roll right now."); return end
    if type(RandomRoll) ~= "function" then Print("RandomRoll is unavailable in this client."); return end
    if pendingRoll and pendingRoll.id == session.id and pendingRoll.round == session.round and pendingRoll.expires >= time() then return end
    pendingRoll = { id = session.id, round = session.round, expires = time() + 12 }
    RandomRoll(1, 100)
    Debug("RandomRoll(1, 100) triggered")
end

local function FinishRoundIfReady()
    if not IsHost() or not session or session.status ~= "RUNNING" then return end
    local active = {}
    for _, player in pairs(session.players) do
        if player.active then
            if not player.roll then return end
            active[#active + 1] = player
        end
    end
    if #active == 0 then return end
    for _, player in ipairs(active) do
        session.history[#session.history + 1] = { round = session.round, name = player.name, roll = player.roll, result = player.result }
        if session.round <= session.maxRounds and player.roll > 50 then player.points = (player.points or 0) + 1 end
    end
    local roundNotice=DON:RoundWinnerText(session.history,session.round,session.maxRounds)
    Print("|cff55ff55"..roundNotice.."|r")
    if session.round >= session.maxRounds then
        local highest, finalists = -1, {}
        for _, player in ipairs(active) do
            local score = session.round > session.maxRounds and player.roll or (player.points or 0)
            if score > highest then highest, finalists = score, { player }
            elseif score == highest then finalists[#finalists + 1] = player end
        end
        if #finalists == 1 then
            session.winner, session.status = finalists[1].name, "PAYOUT"
            SyncBankSession()
            Bump(); BroadcastState(); Refresh()
            Print("Winner: " .. ShortName(session.winner) .. " – payout: " .. Money(Pot()) .. ".")
            return
        end
        for _, player in ipairs(active) do player.active = false end
        for _, player in ipairs(finalists) do player.active = true end
        Print("Tiebreaker: tied leaders roll again. The highest roll wins.")
    end
    session.round = session.round + 1
    for _, player in pairs(session.players) do player.roll, player.result = nil, nil end
    Bump(); BroadcastState(); Refresh(); Print("Round " .. session.round .. " begins.")
end

local function RecordRoll(player, value)
    if not IsHost() or not session or session.status ~= "RUNNING" then return end
    local participant = Participant(player)
    if not participant or not participant.active or participant.roll or value < 1 or value > 100 then return end
    participant.roll = value; participant.result = value <= 50 and "OUT" or "SAFE"
    -- A single accepted roll does not need a complete player/history snapshot.
    Send("ROLL_ACK",session.id,session.round,participant.name,value)
    Save(); Refresh(); FinishRoundIfReady()
end

function DON:PreparePayout()
    if not IsHost() or not session or session.status ~= "PAYOUT" or session.payoutDone then return end
    if SamePlayer(session.winner, session.host) then
        local net = WinnerAmount()
        session.payoutDone, session.status = true, "DONE"
        Bump(); BroadcastState(); Save(); Refresh()
        Print("You won. Your own stake was accounted for; your net winnings are " .. Money(net) .. ".")
        local main = ui.main
        if main and main.SelectBettingTab then main:SelectBettingTab("NEW") end
        return
    end
    Print("Trade with " .. ShortName(session.winner) .. " and pay exactly " .. Money(WinnerAmount()) .. ". Payment is confirmed only after a successful trade.")
end

function DON:ConfirmAbort()
    if not IsHost() or not session or (session.status ~= "LOBBY" and session.status ~= "RUNNING") then return end
    if GambleBankSecurity then
        local refunds = {}
        for _, player in pairs(session.players or {}) do if player.paid and not SamePlayer(player.name, session.host) then refunds[#refunds + 1] = { name = player.name, amount = session.stake, reason = "Refund" } end end
        GambleBankSecurity:ResolveWager(session.id, refunds, 0, "ABORTED")
    end
    session.status = "ABORTED"; Bump(); BroadcastState(); Refresh()
    Print("Game cancelled. Paid stakes must be refunded manually.")
    session = nil
    pendingRoll = nil
    tradeContext = nil
    if ui.paymentPopup then ui.paymentPopup:Hide(); ui.paymentPopup.dismissedSessionID = nil end
    Save()
    local main = ui.main
    if main and main.SelectBettingTab then main:SelectBettingTab("NEW") else Refresh() end
end

function DON:Abort()
    if not IsHost() or not session or (session.status ~= "LOBBY" and session.status ~= "RUNNING") then return end
    StaticPopup_Show("GAMBLE_DON_ABORT_CONFIRM")
end

StaticPopupDialogs.GAMBLE_DON_ABORT_CONFIRM = {
    text = "Cancel Double or Nothing? Paid stakes must then be refunded manually.",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function() DON:ConfirmAbort() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs.GAMBLE_DON_NEW_LOBBY = {
    text = "%s opened a Double or Nothing bet.\nStake per player: %s",
    button1 = "View Bet",
    button2 = "Later",
    OnAccept = function(_, data)
        if data and session and session.id == data.id then DON:ShowDetails() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function ReadTargetMoney()
    local getter = C_TradeInfo and C_TradeInfo.GetTargetTradeMoney or GetTargetTradeMoney
    if not getter then return nil end
    local ok, amount = pcall(getter)
    return ok and tonumber(amount) and floor(tonumber(amount)) or nil
end

local function ReadPlayerMoney()
    local getter = C_TradeInfo and C_TradeInfo.GetPlayerTradeMoney or GetPlayerTradeMoney
    if not getter then return nil end
    local ok, amount = pcall(getter)
    return ok and tonumber(amount) and floor(tonumber(amount)) or nil
end

local function TradePartner()
    return TradeFrameRecipientNameText and TradeFrameRecipientNameText:GetText() or nil
end

local function CompleteTrade(context)
    if not context or context.completed or not session or context.id ~= session.id then return end
    context.completed = true
    local balanceDelta = context.startMoney and GetMoney and (GetMoney() - context.startMoney) or nil
    if context.kind == "DEPOSIT" then
        local actual = context.offered
        if balanceDelta and balanceDelta > 0 then actual = balanceDelta end
        if actual == session.stake then
            local player = Participant(context.partner)
            if player and not player.paid and session.status == "LOBBY" then
                player.paid = true; Bump(); BroadcastState(); Refresh(); Print(ShortName(player.name) .. " is now PAID.")
                if GambleBankSecurity then GambleBankSecurity:RegisterDeposit(session.id, player.name, session.stake) end
            end
        else Print("Payment from " .. ShortName(context.partner) .. " rejected: expected " .. Money(session.stake) .. ", detected " .. Money(actual or 0) .. ".") end
    elseif context.kind == "PAYOUT" then
        local actual = context.offered
        if balanceDelta and balanceDelta < 0 then actual = -balanceDelta end
        if actual == Pot() then
            if GambleBankSecurity then GambleBankSecurity:CompleteObligation(session.id, session.winner, actual, false) end
            session.payoutDone, session.status = true, "DONE"; Bump(); BroadcastState(); Refresh(); Print("Payout completed.")
        else Print("Payout not confirmed: expected " .. Money(Pot()) .. ", detected " .. Money(actual or 0) .. ".") end
    end
    Save()
end

local function ParseRoll(message)
    if not message then return nil end
    local name, value, low, high = message:match("^(.+) rolls (%d+) %((%d+)%-(%d+)%)%.?$")
    if not name then name, value, low, high = message:match("^(.+) würfelt (%d+) %((%d+)%-(%d+)%)%.?$") end
    if not name and RANDOM_ROLL_RESULT then
        local pattern = RANDOM_ROLL_RESULT
        pattern = pattern:gsub("%%%d*%$?s", "\1", 1)
        pattern = pattern:gsub("%%%d*%$?d", "\2", 1):gsub("%%%d*%$?d", "\3", 1):gsub("%%%d*%$?d", "\4", 1)
        pattern = pattern:gsub("([%(%)%.%+%-%*%?%[%]%^%$%%])", "%%%1")
        pattern = pattern:gsub("\1", "(.+)"):gsub("\2", "(%%d+)"):gsub("\3", "(%%d+)"):gsub("\4", "(%%d+)")
        name, value, low, high = message:match("^" .. pattern .. "$")
    end
    return name, tonumber(value), tonumber(low), tonumber(high)
end

local function ApplyHostState(parts, sender)
    local protocol, id, revision = tonumber(parts[2]), parts[3], tonumber(parts[4])
    if protocol ~= PROTOCOL then Print("Lobby von " .. ShortName(sender) .. " verwendet ein inkompatibles Double-or-Nothing-Protokoll."); return end
    if not id or not revision then return end
    if session and session.id == id and revision < (session.revision or 0) then return end
    local incomingHost = parts[5]
    if not SamePlayer(sender, incomingHost) then return end
    local isNewLobby = not session or session.id ~= id
    local previousRound = session and session.id == id and (tonumber(session.round) or 0) or 0
    if not session or session.id ~= id then
        session = { id = id, players = {}, history = {}, revision = revision }
    else
        session.revision = revision
        if parts[14] == "1" then session.history = {} end
    end
    session.host, session.stake, session.maxPlayers = incomingHost, tonumber(parts[6]), 40
    session.maxRounds = max(1, min(50, tonumber(parts[8]) or 5))
    session.status, session.round, session.winner = parts[9], tonumber(parts[10]) or 0, parts[11] ~= "" and parts[11] or nil
    session.payoutDone = parts[13] == "1"
    session.syncSeen = {}
    if session.status == "RUNNING" and session.round > previousRound then
        pendingRoll = nil
        for _, player in pairs(session.players or {}) do
            if session.round <= session.maxRounds and player.paid then player.active = true end
            if player.active then player.roll, player.result = nil, nil end
        end
        -- The round header already makes all eligible players ready to roll.
        -- Do not wait for the full (throttled) history/state batch to redraw.
        Refresh()
    end
    Save()
    GambleDONDB.notifiedSessionsByCharacter = GambleDONDB.notifiedSessionsByCharacter or {}
    local notices = GambleDONDB.notifiedSessionsByCharacter[CharacterStorageKey()] or {}
    GambleDONDB.notifiedSessionsByCharacter[CharacterStorageKey()] = notices
    if isNewLobby and session.status == "LOBBY" and not notices[id] then
        notices[id] = true
        Save()
        Print(ShortName(incomingHost) .. " opened a Double or Nothing bet.")
        if ui.main and ui.main.ShowWagerInvite then
            ui.main:ShowWagerInvite(incomingHost, { id = id, mode = "DOUBLE_OR_NOTHING", don = true, minimum = session.stake, maxRounds = session.maxRounds })
        else StaticPopup_Show("GAMBLE_DON_NEW_LOBBY", ShortName(incomingHost), Money(session.stake), { id = id }) end
    end
end

local playerRefreshPending = false
local function SchedulePlayerRefresh()
    if playerRefreshPending then return end
    playerRefreshPending = true
    C_Timer.After(.1, function() playerRefreshPending = false; Refresh() end)
end

local function OnAddonMessage(prefix, message, channel, sender)
    if prefix ~= PREFIX or (channel ~= "PARTY" and channel ~= "RAID" and channel ~= "INSTANCE_CHAT" and channel ~= "WHISPER") or not IsGroupMember(sender) then return end
    if SamePlayer(sender, PlayerName()) then return end
    local p, command = Split(message), nil; command = p[1]
    Debug("RECV " .. tostring(sender) .. " " .. message)
    if command == "HELLO" then
        DON.lastHelloReply = DON.lastHelloReply or {}
        local now = GetTime()
        if DON.lastHelloReply[sender] and now - DON.lastHelloReply[sender] < 3 then return end
        DON.lastHelloReply[sender] = now
        if tonumber(p[2]) ~= PROTOCOL then incompatiblePeers[Key(sender)] = true; Print(ShortName(sender) .. " nutzt eine inkompatible Double-or-Nothing-Version.")
        else incompatiblePeers[Key(sender)] = nil; if IsHost() then BroadcastState(sender) end end
        return
    end
    if command == "STATE" or command == "SYNC" then ApplyHostState(p, sender); return end
    if command == "ROLL_ACK" then
        if session and p[2]==session.id and tonumber(p[3])==session.round and SamePlayer(sender,session.host) then
            local player=Participant(p[4]); local value=tonumber(p[5])
            if player and value and value>=1 and value<=100 then
                player.roll=value; player.result=value<=50 and "OUT" or "SAFE"
                Save(); Refresh()
            end
        end
        return
    end
    if command == "PLAYER" then
        local id, revision = p[2], tonumber(p[3])
        if session and id == session.id and revision == session.revision and SamePlayer(sender, session.host) then
            session.players[Key(p[4])] = { name = p[4], ready = p[5] == "1", paid = p[6] == "1", active = p[7] == "1", connected = p[8] == "1", roll = tonumber(p[9]) ~= 0 and tonumber(p[9]) or nil, result = p[10] ~= "" and p[10] or nil, joinedAt = tonumber(p[11]) or 0, points = tonumber(p[12]) or 0 }
            if session.syncSeen then session.syncSeen[Key(p[4])] = true end
            -- Save once at STATE_END; coalesce UI updates during the batch.
            -- Player eligibility must appear promptly even while a batch is arriving.
            SchedulePlayerRefresh()
        end
        return
    end
    if command == "HISTORY" then
        if session and p[2] == session.id and tonumber(p[3]) == session.revision and SamePlayer(sender, session.host) then
            local duplicate = false
            for _, entry in ipairs(session.history) do
                if entry.round == tonumber(p[4]) and entry.name == p[5] then duplicate = true; break end
            end
            if not duplicate then session.history[#session.history + 1] = { round = tonumber(p[4]), name = p[5], roll = tonumber(p[6]), result = p[7] } end
        end
        return
    end
    if command == "STATE_END" then
        if session and session.syncSeen and p[2] == session.id and tonumber(p[3]) == session.revision and SamePlayer(sender, session.host) then
            for key in pairs(session.players or {}) do if not session.syncSeen[key] then session.players[key] = nil end end
            session.syncSeen = nil
            Save()
            Refresh()
        end
        return
    end
    if not IsHost() or not session or p[2] ~= session.id or incompatiblePeers[Key(sender)] then return end
    if command == "JOIN" and session.status == "LOBBY" and not Participant(sender) and PlayerCount() < session.maxPlayers then
        if GambleBankSecurity then local allowed, reason = GambleBankSecurity:CanAcceptDeposits(); if not allowed then Print("Join rejected: " .. tostring(reason)); return end end
        session.players[Key(sender)] = { name = sender, ready = false, paid = false, active = true, connected = true, joinedAt = time() }
        Bump(); BroadcastState(); Refresh(); Print(ShortName(sender) .. " joined the lobby.")
    elseif command == "LEAVE" and session.status == "LOBBY" and not SamePlayer(sender, session.host) then
        local player = Participant(sender)
        if player and not player.paid then session.players[Key(sender)] = nil; Bump(); BroadcastState(); Refresh()
        elseif player then Print(ShortName(sender) .. " can only leave after a manual refund once paid.") end
    elseif command == "READY" and session.status == "LOBBY" then
        local player = Participant(sender)
        if player then player.ready = player.paid == true and p[4] == "1"; Bump(); BroadcastState(); Refresh() end
    elseif command == "ROLL" and session.status == "RUNNING" and tonumber(p[3]) == session.round then
        RecordRoll(sender, tonumber(p[4]) or 0)
    end
end

local function UpdateConnections()
    if not IsHost() or not session then return end
    local changed = false
    for _, player in pairs(session.players) do
        local connected = IsGroupMember(player.name)
        if player.connected ~= connected then player.connected = connected; changed = true end
    end
    if changed then Bump(); BroadcastState(); Refresh() end
end

local function OnEvent(event, ...)
    if event == "PLAYER_LOGIN" then
        GambleDONDB = GambleDONDB or { version = PROTOCOL }
        GambleDONDB.sessionsByCharacter = GambleDONDB.sessionsByCharacter or {}
        session = GambleDONDB.sessionsByCharacter[CharacterStorageKey()]
        if not session and GambleDONDB.session then
            local legacy = GambleDONDB.session
            local belongs = SamePlayer(legacy.host, PlayerName()) or (legacy.players and legacy.players[Key(PlayerName())] ~= nil)
            if belongs then
                session = legacy
                GambleDONDB.sessionsByCharacter[CharacterStorageKey()] = legacy
                GambleDONDB.session = nil
            end
        end
        debugEnabled = GambleDONDB.debug == true
        if session then session.maxPlayers = 40; session.maxRounds = max(1, min(50, tonumber(session.maxRounds) or 5)) end
        if session and SamePlayer(session.host, PlayerName()) then SyncBankSession() end
        local register = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
        if register then pcall(register, PREFIX) end
        CreateUI(); Refresh(); C_Timer.After(2, function() if IsHost() then BroadcastState() else Send("HELLO", PROTOCOL, ADDON_VERSION) end end)
    elseif event == "PLAYER_LOGOUT" then Save()
    elseif event == "CHAT_MSG_ADDON" then OnAddonMessage(...)
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        UpdateConnections()
        local now = GetTime()
        if not DON.lastHelloSent or now - DON.lastHelloSent >= 3 then
            DON.lastHelloSent = now; Send("HELLO", PROTOCOL, ADDON_VERSION)
        end
    elseif event == "CHAT_MSG_SYSTEM" then
        local message = ...
        if not CanRead(message) then return end
        if tradeContext and message and ERR_TRADE_COMPLETE and message == ERR_TRADE_COMPLETE then
            local context = tradeContext; tradeContext = nil; C_Timer.After(0.2, function() CompleteTrade(context) end)
        end
        local name, value, low, high = ParseRoll(message)
        if name and value and low == 1 and high == 100 and pendingRoll and pendingRoll.expires >= time() and session and pendingRoll.id == session.id and pendingRoll.round == session.round and SamePlayer(name, PlayerName()) then
            pendingRoll = nil
            if IsHost() then RecordRoll(PlayerName(), value) else Send("ROLL", session.id, session.round, value) end
        end
    elseif event == "TRADE_SHOW" then
        if not session then return end
        local partner = TradePartner()
        if IsHost() and session.status == "LOBBY" then
            local player = Participant(partner)
            if player and not player.paid and not SamePlayer(player.name, session.host) then
                tradeContext = { kind = "DEPOSIT", id = session.id, partner = player.name, startMoney = GetMoney and GetMoney(), offered = ReadTargetMoney() or 0 }
                Print("Expected stake from " .. ShortName(player.name) .. ": " .. Money(session.stake) .. ".")
            end
        elseif IsHost() and session.status == "PAYOUT" and SamePlayer(partner, session.winner) then
            tradeContext = { kind = "PAYOUT", id = session.id, partner = session.winner, startMoney = GetMoney and GetMoney(), offered = ReadPlayerMoney() or 0 }
            Print("Expected payout: " .. Money(Pot()) .. " an " .. ShortName(session.winner) .. ".")
        end
    elseif event == "TRADE_MONEY_CHANGED" or event == "TRADE_ACCEPT_UPDATE" then
        if tradeContext then
            if tradeContext.kind == "DEPOSIT" then tradeContext.offered = ReadTargetMoney() or tradeContext.offered
            else tradeContext.offered = ReadPlayerMoney() or tradeContext.offered end
            if event == "TRADE_ACCEPT_UPDATE" then local mine, theirs = ...; if CanRead(mine) and CanRead(theirs) then tradeContext.bothAccepted = mine == 1 and theirs == 1 end end
        end
    elseif event == "UI_INFO_MESSAGE" then
        local _, message = ...
        if not CanRead(message) then return end
        if tradeContext and message and ERR_TRADE_COMPLETE and message == ERR_TRADE_COMPLETE then
            local context = tradeContext; tradeContext = nil; C_Timer.After(0.2, function() CompleteTrade(context) end)
        end
    elseif event == "TRADE_CLOSED" then
        local context = tradeContext
        if context then
            C_Timer.After(0.6, function()
                if tradeContext == context then tradeContext = nil end
                local moneyChanged = context.startMoney and GetMoney and GetMoney() ~= context.startMoney
                if context.bothAccepted or moneyChanged then CompleteTrade(context)
                elseif not context.completed then Print("Trade cancelled – payment status unchanged.") end
            end)
        end
    end
end

local function EmbeddedMoneyBox(parent, x, texture)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(64, 24); box:SetPoint("TOPLEFT", x, -45); box:SetAutoFocus(false); box:SetNumeric(true); box:SetMaxLetters(7); box:SetText("0")
    local icon = parent:CreateTexture(nil, "ARTWORK"); icon:SetSize(15, 15); icon:SetPoint("LEFT", box, "RIGHT", 4, 0); icon:SetTexture(texture)
    return box
end

local function EnsureEmbedded(main)
    ui.main = main
    if ui.embedded then return end
    local panel = CreateFrame("Frame", nil, main.frame)
    panel:SetPoint("TOPLEFT", 18, -132); panel:SetPoint("BOTTOMRIGHT", -18, 52); panel:Hide(); ui.embedded = panel

    local heading = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); heading:SetPoint("TOPLEFT", 4, -4); heading:SetText("Double or Nothing")
    ui.embeddedHeading = heading
    local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); sub:SetPoint("TOPLEFT", 4, -29); sub:SetPoint("RIGHT", -4, 0); sub:SetJustifyH("LEFT")
    ui.embeddedSub = sub

    local config = CreateFrame("Frame", nil, panel); config:SetAllPoints(); ui.embeddedConfig = config
    local stakeLabel = config:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); stakeLabel:SetPoint("TOPLEFT", 4, -72); stakeLabel:SetText("Stake per player:")
    ui.embGold = EmbeddedMoneyBox(config, 145, "Interface\\MoneyFrame\\UI-GoldIcon")
    ui.embSilver = EmbeddedMoneyBox(config, 240, "Interface\\MoneyFrame\\UI-SilverIcon")
    ui.embCopper = EmbeddedMoneyBox(config, 335, "Interface\\MoneyFrame\\UI-CopperIcon")
    for _, box in ipairs({ ui.embGold, ui.embSilver, ui.embCopper }) do box:ClearAllPoints() end
    ui.embGold:SetPoint("TOPLEFT", 145, -65); ui.embSilver:SetPoint("TOPLEFT", 240, -65); ui.embCopper:SetPoint("TOPLEFT", 335, -65)
    local roundsLabel = config:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); roundsLabel:SetPoint("TOPLEFT", 4, -112); roundsLabel:SetText("Rounds:")
    ui.embRounds = CreateFrame("EditBox", nil, config, "InputBoxTemplate"); ui.embRounds:SetSize(64, 24); ui.embRounds:SetPoint("TOPLEFT", 145, -105); ui.embRounds:SetAutoFocus(false); ui.embRounds:SetNumeric(true); ui.embRounds:SetMaxLetters(2); ui.embRounds:SetText("5")
    ui.embCreate = MakeButton(config, 190, "Create Game"); ui.embCreate:SetPoint("TOPLEFT", 240, -105); ui.embCreate:SetScript("OnClick", function() DON:CreateGame() end)
    local function updateCreate() ui.embCreate:SetEnabled((tonumber(ui.embGold:GetText()) or 0)*10000 + (tonumber(ui.embSilver:GetText()) or 0)*100 + (tonumber(ui.embCopper:GetText()) or 0) > 0) end
    for _, box in ipairs({ui.embGold, ui.embSilver, ui.embCopper}) do box:HookScript("OnTextChanged", updateCreate) end
    updateCreate()
    local explanation = config:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); explanation:SetPoint("TOPLEFT", 4, -153); explanation:SetPoint("RIGHT", -4, 0); explanation:SetJustifyH("LEFT"); explanation:SetJustifyV("TOP")
    explanation:SetText(main:GetRules("DOUBLE_OR_NOTHING"))

    local game = CreateFrame("Frame", nil, panel); game:SetAllPoints(); ui.embeddedGame = game
    ui.embMeta = game:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); ui.embMeta:SetPoint("TOPLEFT", 4, -55); ui.embMeta:SetPoint("RIGHT", -4, 0); ui.embMeta:SetJustifyH("LEFT")
    local scroll = CreateFrame("Frame", nil, game); scroll:SetPoint("TOPLEFT", 2, -82); scroll:SetPoint("BOTTOMRIGHT", -26, 105)
    ui.embContent = CreateFrame("Frame", nil, scroll); ui.embContent:SetSize(450, 1); ui.embContent:SetPoint("TOPLEFT"); ui.embRows = {}
    ui.embHistory = ui.embContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); ui.embHistory:SetJustifyH("LEFT"); ui.embHistory:SetJustifyV("TOP")
    ui.embNotice = game:CreateFontString(nil, "OVERLAY", "GameFontNormal"); ui.embNotice:SetPoint("BOTTOMLEFT", 4, 76); ui.embNotice:SetPoint("RIGHT", -4, 0); ui.embNotice:SetJustifyH("CENTER")
    ui.embJoin = MakeButton(game, 105, "Join"); ui.embJoin:SetPoint("BOTTOMLEFT", 2, 39); ui.embJoin:SetScript("OnClick", function() if session then Send("JOIN", session.id, session.revision) end end)
    ui.embLeave = MakeButton(game, 105, "Leave"); ui.embLeave:SetPoint("BOTTOMLEFT", 2, 39); ui.embLeave:SetScript("OnClick", function() if session then Send("LEAVE", session.id, session.revision) end end)
    ui.embReady = MakeButton(game, 105, "Ready"); ui.embReady:SetPoint("BOTTOMLEFT", 114, 39); ui.embReady:SetScript("OnClick", function() local me = Participant(PlayerName()); if session and me and me.paid then Send("READY", session.id, session.revision, me.ready and 0 or 1) end end)
    ui.embStart = MakeButton(game, 185, "Start Game"); ui.embStart:SetPoint("BOTTOMRIGHT", -2, 39); ui.embStart:SetScript("OnClick", function() DON:StartGame() end)
    ui.embRoll = MakeButton(game, 250, "ROLL (1–100)"); ui.embRoll:SetSize(250, 38); ui.embRoll:SetPoint("BOTTOM", 0, 33); ui.embRoll:SetScript("OnClick", function() DON:Roll() end)
    local embeddedRollIcon = ui.embRoll:CreateTexture(nil, "ARTWORK")
    embeddedRollIcon:SetSize(32, 32); embeddedRollIcon:SetPoint("RIGHT", ui.embRoll, "LEFT", -6, 0)
    embeddedRollIcon:SetAtlas("lootroll-toast-icon-need-up", false)
    ui.embPayout = MakeButton(game, 210, "Pay Winner"); ui.embPayout:SetPoint("BOTTOMRIGHT", -2, 39); ui.embPayout:SetScript("OnClick", function() DON:PreparePayout() end)
    ui.embTrade = CreateFrame("Button", nil, game, "UIPanelButtonTemplate,InsecureActionButtonTemplate")
    ui.embTrade:SetSize(210, 26); ui.embTrade:SetPoint("BOTTOMRIGHT", -2, 5)
    GambleTradeAction:Attach(ui.embTrade, TradeIntent, Print)
    ui.embAbort = CreateFrame("Button", nil, game)
    ui.embAbort:SetSize(28, 28)
    ui.embAbort:SetPoint("BOTTOMRIGHT", main.frame, "BOTTOMRIGHT", -18, 16)
    local cancelIcon = ui.embAbort:CreateTexture(nil, "ARTWORK")
    cancelIcon:SetAllPoints(); cancelIcon:SetAtlas("128-RedButton-Delete", false)
    ui.embAbort:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    ui.embAbort:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_TOP")
        GameTooltip:SetText("Cancel Bet")
        GameTooltip:Show()
    end)
    ui.embAbort:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ui.embAbort:SetScript("OnClick", function() DON:Abort() end)

    ui.embPaymentToggle = MakeButton(game, 175, "Payments")
    ui.embPaymentToggle:SetPoint("TOPRIGHT", -2, -2)
    ui.embPaymentToggle:SetScript("OnClick", function()
        if not ui.paymentPopup then return end
        if ui.paymentPopup:IsShown() then ui.paymentPopup.dismissedSessionID = session and session.id; ui.paymentPopup:Hide()
        else ui.paymentPopup.dismissedSessionID = nil; ui.paymentPopup:Show(); ui.paymentPopup:Raise(); DON:RefreshPaymentPopup() end
        DON:RenderEmbedded(main, creationMode)
    end)

    local payments = CreateFrame("Frame", "GambleDONPaymentsFrame", UIParent, "BasicFrameTemplateWithInset")
    payments:SetSize(390, 480); payments:SetPoint("TOPRIGHT", main.frame, "TOPLEFT", -8, 0); payments:SetFrameStrata("DIALOG"); payments:SetClampedToScreen(true)
    payments:SetMovable(true); payments:EnableMouse(true); payments:RegisterForDrag("LeftButton"); payments:SetScript("OnDragStart", payments.StartMoving); payments:SetScript("OnDragStop", payments.StopMovingOrSizing)
    payments.TitleText:SetText("Double or Nothing - Payments")
    local paymentHint = payments:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); paymentHint:SetPoint("TOPLEFT", 18, -40); paymentHint:SetPoint("RIGHT", -18, 0); paymentHint:SetJustifyH("LEFT"); paymentHint:SetText("Participants and payment status")
    local paymentScroll = CreateFrame("ScrollFrame", nil, payments, "UIPanelScrollFrameTemplate"); paymentScroll:SetPoint("TOPLEFT", 14, -66); paymentScroll:SetPoint("BOTTOMRIGHT", -34, 50)
    ui.paymentContent = CreateFrame("Frame", nil, paymentScroll); ui.paymentContent:SetSize(340, 1); paymentScroll:SetScrollChild(ui.paymentContent); ui.paymentRows = {}
    ui.paymentPot = payments:CreateFontString(nil, "OVERLAY", "GameFontNormal"); ui.paymentPot:SetPoint("BOTTOMLEFT", 18, 22); ui.paymentPot:SetPoint("RIGHT", -18, 0); ui.paymentPot:SetJustifyH("LEFT")
    payments.autoOpened = {}; payments:Hide(); ui.paymentPopup = payments
    if payments.CloseButton then payments.CloseButton:SetScript("OnClick", function() payments.dismissedSessionID = session and session.id; payments:Hide(); if ui.embPaymentToggle then ui.embPaymentToggle:SetText("Show Payments") end end) end
end

function DON:GetRunningCard()
    if not session or (session.status ~= "LOBBY" and session.status ~= "RUNNING" and session.status ~= "PAYOUT") then return nil end
    local me = Participant(PlayerName())
    return {
        id = "DON:" .. session.id, mode = "DOUBLE_OR_NOTHING", don = true, createdAt = session.createdAt or tonumber(tostring(session.id):match("^(%d+)")),
        context = StatusText(session.status) .. " · Round " .. tostring(session.round or 0) .. "/" .. tostring(session.maxRounds or 5) .. " · " .. PlayerCount() .. " players",
        summary = "Stake: " .. Money(session.stake) .. "    Pot: " .. Money(Pot()) .. (me and ("    " .. (me.active and "ACTIVE" or "OUT")) or "    not joined"),
    }
end

function DON:ShowDetails()
    local main = ui.main
    if not main or not session then return end
    main.uiTab = "DON_DETAIL"; main.detailWagerID = "DON:" .. session.id
    if main.frame then main.frame:Show(); main.frame:Raise() end
    main:Refresh()
end

function DON:SetMainController(main)
    ui.main = main
    -- Build trade widgets before combat, so opening the ordinary display later
    -- never needs to create action templates during combat.
    if not ui.embedded and not (InCombatLockdown and InCombatLockdown()) then EnsureEmbedded(main) end
end

function DON:CloseWindows()
    local closed = true
    for _, key in ipairs({ "frame", "embedded", "paymentPopup", "winnerFrame" }) do
        local window = ui[key]
        if window then
            if InCombatLockdown and InCombatLockdown() and window:IsProtected() then closed = false
            else window:Hide() end
        end
    end
    return closed
end

function DON:HideEmbedded()
    if ui.embedded then ui.embedded:Hide() end
    if ui.paymentPopup then ui.paymentPopup:Hide() end
end

function DON:RefreshPaymentPopup()
    if not ui.paymentPopup or not session then return end
    for _, row in ipairs(ui.paymentRows) do row:Hide() end
    for index, player in ipairs(OrderedPlayers()) do
        local row = ui.paymentRows[index]
        if not row then
            row = CreateFrame("Frame", nil, ui.paymentContent, "BackdropTemplate"); row:SetSize(330, 48)
            row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 9 }); row:SetBackdropColor(.04, .04, .04, .86); row:SetBackdropBorderColor(.32, .28, .16, .9)
            if GambleUIStyle then GambleUIStyle:Row(row) end
            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal"); row.name:SetPoint("TOPLEFT", 9, -8)
            row.amount = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); row.amount:SetPoint("BOTTOMLEFT", 9, 7)
            row.status = row:CreateFontString(nil, "OVERLAY", "GameFontNormal"); row.status:SetPoint("CENTER", 0, 0); row.status:SetJustifyH("CENTER")
            ui.paymentRows[index] = row
        end
        row:SetPoint("TOPLEFT", 0, -((index - 1) * 52)); row.name:SetText(ClassColor(player.name) .. ShortName(player.name) .. "|r" .. (SamePlayer(player.name, session.host) and " |cffffd100(Bank)|r" or ""))
        row.amount:SetText("Stake: " .. Money(session.stake)); row.status:SetText(player.paid and "|cff55ff55PAID|r" or "|cffff5555PENDING|r"); row:Show()
    end
    ui.paymentContent:SetHeight(max(1, PlayerCount() * 52)); ui.paymentPot:SetText("Current pot: " .. Money(Pot()))
end

function DON:RenderEmbedded(main, creationMode)
    if not ui.embedded and InCombatLockdown and InCombatLockdown() then Print("The trade view will be available after combat."); return end
    EnsureEmbedded(main)
    ui.embedded:Show()
    GambleTradeAction:Prepare(ui.embTrade)
    if not (InCombatLockdown and InCombatLockdown()) then
        ui.embTrade:ClearAllPoints()
        ui.embTrade:SetPoint("BOTTOMRIGHT", -2, session and session.status == "PAYOUT" and 39 or 5)
    end
    local activeSession = session and session.status ~= "DONE" and session.status ~= "ABORTED"
    ui.embeddedConfig:SetShown(not activeSession)
    ui.embeddedGame:SetShown(activeSession and true or false)
    ui.embeddedHeading:SetText(activeSession and ("Double or Nothing — " .. StatusText(session.status)) or "Create Double or Nothing")
    ui.embeddedSub:SetText(activeSession and ("Bank: " .. ClassColor(session.host) .. ShortName(session.host) .. "|r") or "Set the stake per player.")
    ui.embCreate:SetEnabled(StakeFromBoxes() > 0)
    if not activeSession then main.frame:SetHeight(600); return end

    local me = Participant(PlayerName())
    ui.embMeta:SetText("Pot: " .. Money(Pot()) .. "    Stake: " .. Money(session.stake) .. "    Round: " .. (session.round or 0) .. "/" .. (session.maxRounds or 5) .. "    Players: " .. PlayerCount())
    for _, button in ipairs({ ui.embJoin, ui.embLeave, ui.embReady, ui.embStart, ui.embRoll, ui.embPayout, ui.embAbort }) do button:Hide() end
    if session.status == "LOBBY" then
        if not me and PlayerCount() < session.maxPlayers then ui.embJoin:Show() end
        if me and not SamePlayer(me.name, session.host) then ui.embLeave:Show() end
        if me and not SamePlayer(me.name, session.host) then ui.embReady:SetText((me.paid and me.ready) and "Not Ready" or "Ready"); ui.embReady:SetEnabled(me.paid == true); ui.embReady:Show() end
        if IsHost() then ui.embStart:Show(); ui.embAbort:Show() end
    elseif session.status == "RUNNING" then
        if me and me.active and not me.roll then ui.embRoll:Show() end
        if IsHost() then ui.embAbort:Show() end
    elseif session.status == "PAYOUT" and IsHost() and not session.payoutDone then
        ui.embPayout:SetText(SamePlayer(session.winner, session.host) and "Settle Winnings" or "Pay Winner")
        -- External payouts use the actual trade-action button, not a second instruction-only button.
        if SamePlayer(session.winner, session.host) then ui.embPayout:Show() end
    end
    local canStart = IsHost() and session.status == "LOBBY" and PlayerCount() >= 2
    if canStart then for _, player in pairs(session.players) do if not player.ready or not player.paid or player.connected == false then canStart = false; break end end end
    ui.embStart:SetEnabled(canStart and true or false); ui.embStart:SetText(canStart and "Start Game" or "Waiting for Ready & Payment")

    for _, row in ipairs(ui.embRows) do row:Hide() end
    for index, player in ipairs(OrderedPlayers()) do
        local row = ui.embRows[index]
        if not row then
            row = CreateFrame("Frame", nil, ui.embContent, "BackdropTemplate"); row:SetSize(438, 42)
            row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 9 }); row:SetBackdropColor(.04, .04, .04, .82); row:SetBackdropBorderColor(.35, .28, .12, .9)
            if GambleUIStyle then GambleUIStyle:Row(row) end
            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal"); row.name:SetPoint("LEFT", 8, 7)
            row.money = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); row.money:SetPoint("LEFT", 8, -10)
            row.state = row:CreateFontString(nil, "OVERLAY", "GameFontNormal"); row.state:SetPoint("RIGHT", -8, 7)
            row.roll = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); row.roll:SetPoint("RIGHT", -8, -10)
            ui.embRows[index] = row
        end
        row:SetPoint("TOPLEFT", 0, -((index - 1) * 46)); row.name:SetText(ClassColor(player.name) .. ShortName(player.name) .. "|r" .. (player.connected == false and " |cff888888(offline)|r" or ""))
        row.money:SetText(Money(session.stake) .. " · Points: " .. (player.points or 0) .. (player.paid and "  |cff55ff55PAID|r" or "  |cffff5555NOT PAID|r"))
        row.state:SetText(session.status == "LOBBY" and ((player.paid and player.ready) and "|cff55ff55READY|r" or "|cffffcc55NOT READY|r") or (player.active and "|cff55ff55ACTIVE|r" or "|cffff5555OUT|r"))
        row.roll:SetText(player.roll and ("Roll: " .. player.roll .. "  " .. (player.result or "")) or (session.status == "RUNNING" and player.active and "WAITING" or "")); row:Show()
    end
    local history = DON:HistoryLines(session.history, session.maxRounds)
    ui.embHistory:ClearAllPoints(); ui.embHistory:SetPoint("TOPLEFT", 6, -(PlayerCount() * 46 + 8)); ui.embHistory:SetPoint("RIGHT", -6, 0)
    ui.embHistory:SetText(#history > 0 and ("|cffffd100Roll History|r\n" .. table.concat(history, "\n")) or "")
    ui.embContent:SetHeight(max(1, PlayerCount() * 46 + (#history > 0 and (#history * 15 + 32) or 0)))
    main.frame:SetHeight(600 + max(0, ui.embContent:GetHeight() - 235))
    if session.status == "PAYOUT" then
        local label = SamePlayer(session.winner, session.host) and "Net winnings" or "Payout"
        ui.embNotice:SetText("|cffffd100WINNER: " .. ShortName(session.winner) .. " — " .. label .. ": " .. Money(WinnerAmount()) .. "|r")
    else ui.embNotice:SetText("") end
    ui.embPaymentToggle:SetText(ui.paymentPopup:IsShown() and "Hide Payments" or "Show Payments")
    local externalPlayers = max(0, PlayerCount() - 1)
    if externalPlayers > 0 and not ui.paymentPopup.autoOpened[session.id] and ui.paymentPopup.dismissedSessionID ~= session.id then
        ui.paymentPopup.autoOpened[session.id] = true; ui.paymentPopup:Show(); ui.paymentPopup:Raise()
    end
    if ui.paymentPopup:IsShown() then DON:RefreshPaymentPopup() end
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED", "CHAT_MSG_ADDON", "CHAT_MSG_SYSTEM", "TRADE_SHOW", "TRADE_MONEY_CHANGED", "TRADE_ACCEPT_UPDATE", "TRADE_CLOSED", "UI_INFO_MESSAGE" }) do events:RegisterEvent(event) end
events:SetScript("OnEvent", function(_, event, ...) if event == "PLAYER_REGEN_ENABLED" then CloseSettledWinnerPopup(); if ui.pendingWinnerPopup then ShowWinnerPopup() end; RefreshMainAddon() else OnEvent(event, ...) end end)
