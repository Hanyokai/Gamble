GambleBankSecurity = GambleBankSecurity or {}
local Bank = GambleBankSecurity
local CreateFrame = GambleUIStyle and GambleUIStyle.CreateFrame or CreateFrame

local PREFIX = "GambleBank1"
local SCHEMA = 1
local SNAPSHOT_INTERVAL = 100
local WARNING_COOLDOWN = 30
local floor, max, min = math.floor, math.max, math.min
local unpack = unpack or table.unpack

local runtime = { initialized = false, lastActual = nil, lastStatus = nil, lastWarning = 0, recovery = nil }

local function Now() return time and time() or 0 end
local function Clock() return GetTime and GetTime() or Now() end
local function Safe(value) return tostring(value or ""):gsub("[|\t\r\n]", " ") end
local function Canonical(name) return Safe(name):lower():gsub("%s+", "") end
local function PlayerName()
    local name, realm = UnitFullName and UnitFullName("player")
    if not name and UnitName then name = UnitName("player") end
    return realm and realm ~= "" and (name .. "-" .. realm) or (name or "?")
end
local function SamePlayer(left, right)
    local function short(value) return Canonical(value):match("^([^%-]+)") or Canonical(value) end
    return Canonical(left) == Canonical(right) or short(left) == short(right)
end
local function ActualGold()
    local ok, amount = pcall(GetMoney)
    return ok and type(amount) == "number" and max(0, floor(amount)) or 0
end
local function Money(copper)
    copper = max(0, floor(tonumber(copper) or 0))
    return string.format("%d|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:1:0|t %02d|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:1:0|t %02d|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:1:0|t", floor(copper / 10000), floor((copper % 10000) / 100), copper % 100)
end
local function Debug(message)
    if GambleDB and GambleDB.debug and DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffBANK:|r " .. tostring(message)) end
end
local function Chat(message)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffd8b65cGamble Bank:|r " .. tostring(message)) end
end

local function Hash(text)
    local a, b = 1, 0
    text = tostring(text or "")
    for index = 1, #text do a = (a + text:byte(index)) % 65521; b = (b + a) % 65521 end
    return string.format("%04x%04x", b, a)
end

local function Channel()
    if LE_PARTY_CATEGORY_INSTANCE then
        local ok, value = pcall(IsInGroup, LE_PARTY_CATEGORY_INSTANCE)
        if ok and value then return "INSTANCE_CHAT" end
    end
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
end

local function Send(...)
    local channel = Channel()
    if not channel then return false end
    local fields = { ... }
    for index = 1, #fields do fields[index] = Safe(fields[index]) end
    local message = table.concat(fields, "|")
    local sender = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
    local ok = sender and pcall(sender, PREFIX, message, channel)
    return ok and true or false
end

local function Split(message)
    local fields = {}
    for value in (tostring(message or "") .. "|"):gmatch("(.-)|") do fields[#fields + 1] = value end
    return fields
end

local function NewState(identity)
    return {
        schema = SCHEMA, bankIdentity = identity, sequence = 0, ledger = {}, knownTransactions = {},
        freeBankReserve = 0, accounts = {}, riskReservations = {}, snapshots = {},
        lastChecksum = "GENESIS", integrityOK = true, securityLock = nil, status = "SOLVENT",
    }
end

local function RootDB()
    GambleBankSecurityDB = GambleBankSecurityDB or { schema = SCHEMA, banks = {}, backups = {} }
    GambleBankSecurityDB.banks = GambleBankSecurityDB.banks or {}
    GambleBankSecurityDB.backups = GambleBankSecurityDB.backups or {}
    return GambleBankSecurityDB
end

function Bank:GetBankIdentity() return PlayerName() end

function Bank:GetState()
    local root, identity = RootDB(), self:GetBankIdentity()
    root.banks[Canonical(identity)] = root.banks[Canonical(identity)] or NewState(identity)
    return root.banks[Canonical(identity)]
end

local function Account(state, betID)
    betID = Safe(betID)
    state.accounts[betID] = state.accounts[betID] or { betID = betID, state = "CREATED", deposits = {}, activePot = 0, payouts = {}, refunds = {}, risk = 0 }
    return state.accounts[betID]
end

local function ObligationTotal(entries)
    local total = 0
    for _, item in pairs(entries or {}) do if item.status ~= "COMPLETED" then total = total + max(0, floor(tonumber(item.amount) or 0)) end end
    return total
end

function Bank:GetTotals()
    local state = self:GetState()
    local active, payout, refund, risk = 0, 0, 0, 0
    for _, account in pairs(state.accounts or {}) do
        active = active + max(0, floor(tonumber(account.activePot) or 0))
        payout = payout + ObligationTotal(account.payouts)
        refund = refund + ObligationTotal(account.refunds)
    end
    for _, reservation in pairs(state.riskReservations or {}) do if reservation.status == "RESERVED" then risk = risk + max(0, floor(tonumber(reservation.amount) or 0)) end end
    return { free = max(0, floor(tonumber(state.freeBankReserve) or 0)), active = active, payout = payout, refund = refund, risk = risk }
end

function Bank:GetActualGold() return ActualGold() end
function Bank:GetRequiredReserve()
    local totals = self:GetTotals()
    return totals.free + totals.active + totals.payout + totals.refund
end
function Bank:GetPrivateAvailableGold() return max(0, self:GetActualGold() - self:GetRequiredReserve()) end
function Bank:GetBankOwnedGold() return min(self:GetActualGold(), self:GetRequiredReserve()) end
function Bank:GetCoverageRatio()
    local required = self:GetRequiredReserve()
    if required <= 0 then return 1 end
    return self:GetActualGold() / required
end
function Bank:GetShortfall() return max(0, self:GetRequiredReserve() - self:GetActualGold()) end
function Bank:GetStatus()
    local state = self:GetState()
    if state.securityLock then return state.securityLock end
    return self:GetActualGold() < self:GetRequiredReserve() and "UNDERFUNDED" or "SOLVENT"
end
function Bank:IsSolvent() return self:GetStatus() == "SOLVENT" end
function Bank:GetFreeRiskCapacity()
    local totals = self:GetTotals()
    return max(0, totals.free - totals.risk)
end

local function StateVector(bank)
    local totals = Bank:GetTotals()
    return table.concat({ bank.freeBankReserve or 0, totals.active, totals.payout, totals.refund, totals.risk }, ":")
end

local function TxMaterial(tx)
    return table.concat({ tx.sequence, tx.id, tx.timestamp, tx.betID, tx.type, tx.player, tx.amount, tx.before, tx.after, tx.previousChecksum }, "|")
end

function Bank:_Snapshot(force)
    local state = self:GetState()
    if not force and (state.sequence == 0 or state.sequence % SNAPSHOT_INTERVAL ~= 0) then return end
    local totals = self:GetTotals()
    local snapshot = {
        sequence = state.sequence, free = totals.free, active = totals.active, payout = totals.payout,
        refund = totals.refund, risk = totals.risk, required = totals.free + totals.active + totals.payout + totals.refund,
        checksum = state.lastChecksum, timestamp = Now(),
    }
    state.snapshots[#state.snapshots + 1] = snapshot
    while #state.snapshots > 10 do table.remove(state.snapshots, 1) end
    Debug("LEDGER: SNAPSHOT #" .. state.sequence)
    Send("SNAP", state.bankIdentity, snapshot.sequence, snapshot.free, snapshot.active, snapshot.payout, snapshot.refund, snapshot.risk, snapshot.checksum)
end

function Bank:_BroadcastTransaction(tx)
    Send("TX", self:GetState().bankIdentity, tx.sequence, tx.id, tx.betID, tx.type, tx.player, tx.amount, tx.timestamp, tx.before, tx.after, tx.metadata, tx.previousChecksum, tx.checksum)
end

function Bank:RegisterTransaction(transactionID, kind, betID, player, amount, metadata, apply)
    local state = self:GetState()
    transactionID, amount = Safe(transactionID), floor(tonumber(amount) or 0)
    if transactionID == "" or kind == "" or amount < 0 then state.securityLock = "BANK SECURITY LOCK"; return false, "INVALID_TRANSACTION" end
    local known = state.knownTransactions[transactionID]
    if known then
        if known.type ~= kind or known.amount ~= amount or known.betID ~= Safe(betID) then state.securityLock = "BANK SECURITY LOCK"; return false, "DUPLICATE_CONFLICT" end
        return true, "DUPLICATE_IGNORED"
    end
    local before = StateVector(state)
    if apply then
        local ok, errorMessage = pcall(apply, state)
        if not ok then state.securityLock = "BANK SECURITY LOCK"; return false, tostring(errorMessage) end
    end
    if (state.freeBankReserve or 0) < 0 then state.securityLock = "BANK SECURITY LOCK"; return false, "NEGATIVE_RESERVE" end
    state.sequence = (state.sequence or 0) + 1
    local tx = {
        id = transactionID, sequence = state.sequence, timestamp = Now(), betID = Safe(betID), type = kind,
        player = Safe(player), amount = amount, before = before, after = StateVector(state),
        metadata = Safe(metadata), previousChecksum = state.lastChecksum or "GENESIS",
    }
    tx.checksum = Hash(TxMaterial(tx))
    state.lastChecksum = tx.checksum
    state.ledger[#state.ledger + 1] = tx
    state.knownTransactions[transactionID] = { type = kind, amount = amount, betID = tx.betID, sequence = tx.sequence, checksum = tx.checksum }
    Debug("LEDGER: TX #" .. tx.sequence .. " " .. kind)
    self:_BroadcastTransaction(tx); if not runtime.batch then self:_Snapshot(false); self:CheckSolvency() end
    return true, tx
end

function Bank:RegisterWager(betID, hostStake, maximumLiability)
    local state, risk = self:GetState(), max(0, floor(tonumber(maximumLiability) or 0) - floor(tonumber(hostStake) or 0))
    if state.accounts[Safe(betID)] then return true, "ALREADY_REGISTERED" end
    local allowed, reason = self:CanOpenBet(maximumLiability or hostStake, hostStake)
    if not allowed then return false, reason end
    Account(state, betID)
    if risk > 0 then
        local ok, err = self:ReserveRisk(betID, risk)
        if not ok then return false, err end
    end
    return self:RegisterDeposit(betID, PlayerName(), hostStake, Safe(betID) .. ":DEPOSIT:" .. Canonical(PlayerName()) .. ":" .. floor(hostStake or 0))
end

function Bank:RegisterDeposit(betID, player, cumulativeAmount, transactionID)
    local state, account = self:GetState(), Account(self:GetState(), betID)
    if account.state == "RESULT" or account.state == "PAYOUT" or account.state == "REFUND" or account.state == "SETTLED" then return false, "INVALID_TRANSACTION_STATE" end
    cumulativeAmount = max(0, floor(tonumber(cumulativeAmount) or 0))
    local old = max(0, floor(tonumber(account.deposits[Canonical(player)]) or 0))
    if cumulativeAmount <= old then return true, "ALREADY_FUNDED" end
    local delta = cumulativeAmount - old
    transactionID = transactionID or (Safe(betID) .. ":DEPOSIT:" .. Canonical(player) .. ":" .. cumulativeAmount)
    return self:RegisterTransaction(transactionID, "DEPOSIT", betID, player, delta, "cumulative=" .. cumulativeAmount, function(bank)
        local target = Account(bank, betID)
        target.deposits[Canonical(player)] = cumulativeAmount
        target.activePot = max(0, floor(tonumber(target.activePot) or 0)) + delta
        if target.state == "CREATED" then target.state = "FUNDED" end
    end)
end

function Bank:ActivateWager(betID)
    local account = Account(self:GetState(), betID)
    if account.state == "ACTIVE" then return true, "ALREADY_ACTIVE" end
    if account.state ~= "FUNDED" and account.state ~= "CREATED" then return false, "INVALID_TRANSACTION_STATE" end
    return self:RegisterTransaction(Safe(betID) .. ":ACTIVE", "POT_RESERVE", betID, PlayerName(), 0, nil, function(state) Account(state, betID).state = "ACTIVE" end)
end
function Bank:ExcludeParticipant(betID, player, amount)
    local key=Canonical(player)
    return self:RegisterTransaction(Safe(betID)..":EXCLUDE:"..key,"REFUND_CREATED",betID,player,amount,"Excluded before start",function(bank)
        local account=Account(bank,betID)
        account.activePot=max(0,(account.activePot or 0)-amount)
        account.deposits[key]=nil
        account.refunds[key]={player=player,amount=amount,status="OPEN"}
    end)
end

function Bank:RegisterBankRevenue(betID, amount, transactionID, metadata)
    amount = max(0, floor(tonumber(amount) or 0))
    return self:RegisterTransaction(transactionID or (Safe(betID) .. ":BANK_REVENUE:" .. amount), "BANK_REVENUE", betID, PlayerName(), amount, metadata, function(state)
        state.freeBankReserve = max(0, floor(tonumber(state.freeBankReserve) or 0)) + amount
    end)
end

function Bank:ReserveRisk(betID, amount)
    amount = max(0, floor(tonumber(amount) or 0))
    if amount > self:GetFreeRiskCapacity() then return false, "INSUFFICIENT_BANK_COVERAGE" end
    return self:RegisterTransaction(Safe(betID) .. ":RISK_RESERVED:" .. amount, "RISK_RESERVED", betID, PlayerName(), amount, nil, function(state)
        state.riskReservations[Safe(betID)] = { amount = amount, status = "RESERVED" }
        Account(state, betID).risk = amount
    end)
end

function Bank:ReleaseRisk(betID)
    local reservation = self:GetState().riskReservations[Safe(betID)]
    if not reservation or reservation.status ~= "RESERVED" then return true, "NO_RISK" end
    local amount = reservation.amount
    return self:RegisterTransaction(Safe(betID) .. ":RISK_RELEASED:" .. amount, "RISK_RELEASED", betID, PlayerName(), amount, nil, function(state)
        state.riskReservations[Safe(betID)].status = "RELEASED"
        Account(state, betID).risk = 0
    end)
end

function Bank:ResolveWager(betID, obligations, bankRevenue, resultKey)
    local state, account = self:GetState(), Account(self:GetState(), betID)
    if account.state == "RESULT" or account.state == "PAYOUT" or account.state == "REFUND" or account.state == "SETTLED" then return true, "ALREADY_RESOLVED" end
    local pot = max(0, floor(tonumber(account.activePot) or 0))
    runtime.batch, runtime.batchStartSequence = true, state.sequence or 0
    local ok, err = self:RegisterTransaction(Safe(betID) .. ":POT_RELEASE:" .. pot, "POT_RELEASE", betID, PlayerName(), pot, resultKey, function(bank)
        local target = Account(bank, betID); target.activePot = 0; target.state = "RESULT"; target.resultKey = Safe(resultKey)
    end)
    if not ok then runtime.batch, runtime.batchStartSequence = nil, nil; self:CheckSolvency(); return false, err end
    for _, obligation in ipairs(obligations or {}) do
        local amount = max(0, floor(tonumber(obligation.amount) or 0))
        local refund = tostring(obligation.reason or ""):lower():find("rück", 1, true) or tostring(obligation.reason or ""):lower():find("refund", 1, true)
        local kind = refund and "REFUND_CREATED" or "PAYOUT_CREATED"
        local player = Safe(obligation.name)
        local txid = Safe(betID) .. ":" .. kind .. ":" .. Canonical(player) .. ":" .. amount
        local liabilityOK = self:RegisterTransaction(txid, kind, betID, player, amount, obligation.reason, function(bank)
            local target = Account(bank, betID); local bucket = refund and target.refunds or target.payouts
            bucket[Canonical(player)] = { player = player, amount = amount, status = "OPEN", transactionID = txid }
            target.state = refund and "REFUND" or "PAYOUT"
        end)
        if not liabilityOK then state.securityLock = "BANK SECURITY LOCK" end
    end
    if tonumber(bankRevenue) and tonumber(bankRevenue) > 0 then self:RegisterBankRevenue(betID, bankRevenue, nil, resultKey) end
    self:ReleaseRisk(betID)
    local crossedSnapshot = floor((runtime.batchStartSequence or 0) / SNAPSHOT_INTERVAL) < floor((state.sequence or 0) / SNAPSHOT_INTERVAL)
    runtime.batch, runtime.batchStartSequence = nil, nil
    if crossedSnapshot then self:_Snapshot(true) end
    self:CheckSolvency()
    return true
end

function Bank:CompleteObligation(betID, player, amount, isRefund, transactionID)
    local state, account = self:GetState(), Account(self:GetState(), betID)
    local bucket = isRefund and account.refunds or account.payouts
    local key, obligation = Canonical(player), bucket[Canonical(player)]
    if not obligation then return false, "UNKNOWN_OBLIGATION" end
    amount = max(0, floor(tonumber(amount) or 0))
    if amount ~= obligation.amount then state.securityLock = "BANK SECURITY LOCK"; return false, "AMOUNT_MISMATCH" end
    local kind = isRefund and "REFUND_COMPLETED" or "PAYOUT_COMPLETED"
    local ok, result = self:RegisterTransaction(transactionID or (Safe(betID) .. ":" .. kind .. ":" .. key .. ":" .. amount), kind, betID, player, amount, nil, function(bank)
        local target = Account(bank, betID); local item = (isRefund and target.refunds or target.payouts)[key]
        if item then item.status = "COMPLETED" end
    end)
    if ok and ObligationTotal(account.payouts) == 0 and ObligationTotal(account.refunds) == 0 and account.activePot == 0 then account.state = "SETTLED" end
    return ok, result
end

function Bank:RegisterLiability(betID, player, amount, liabilityType, transactionID, metadata)
    local refund = liabilityType == "REFUND" or liabilityType == "REFUND_CREATED"
    local kind = refund and "REFUND_CREATED" or "PAYOUT_CREATED"
    local key, account = Canonical(player), Account(self:GetState(), betID)
    amount = max(0, floor(tonumber(amount) or 0))
    transactionID = transactionID or (Safe(betID) .. ":" .. kind .. ":" .. key .. ":" .. amount)
    return self:RegisterTransaction(transactionID, kind, betID, player, amount, metadata, function(state)
        local target = Account(state, betID); local bucket = refund and target.refunds or target.payouts
        bucket[key] = { player = Safe(player), amount = amount, status = "OPEN", transactionID = transactionID }
        target.state = refund and "REFUND" or "PAYOUT"
    end)
end

function Bank:ReleaseLiability(betID, player, amount, liabilityType, transactionID)
    return self:CompleteObligation(betID, player, amount, liabilityType == "REFUND" or liabilityType == "REFUND_CREATED", transactionID)
end

function Bank:RegisterPayout(betID, player, amount, transactionID) return self:CompleteObligation(betID, player, amount, false, transactionID) end
function Bank:RegisterRefund(betID, player, amount, transactionID) return self:CompleteObligation(betID, player, amount, true, transactionID) end

function Bank:ManualAdjustment(amount, reason)
    amount = floor(tonumber(amount) or 0)
    if amount == 0 or Safe(reason) == "" then return false, "AMOUNT_AND_REASON_REQUIRED" end
    local state = self:GetState()
    if (state.freeBankReserve or 0) + amount < 0 then return false, "NEGATIVE_RESERVE" end
    return self:RegisterTransaction("MANUAL:" .. Now() .. ":" .. state.sequence + 1, "MANUAL_ADJUSTMENT", "", PlayerName(), math.abs(amount), (amount < 0 and "-" or "+") .. Safe(reason), function(bank)
        bank.freeBankReserve = bank.freeBankReserve + amount
        bank.lastManualAdjustment = { amount = amount, reason = Safe(reason), timestamp = Now() }
    end)
end

function Bank:CanOpenBet(maximumLiability, playerPot)
    local state = self:GetState()
    if state.securityLock then return false, state.securityLock end
    if not self:IsSolvent() then return false, "BANK_UNDERFUNDED" end
    local liability, pot = max(0, floor(tonumber(maximumLiability) or 0)), max(0, floor(tonumber(playerPot) or 0))
    local additionalRisk = max(0, liability - pot)
    if additionalRisk > self:GetFreeRiskCapacity() then return false, "INSUFFICIENT_BANK_COVERAGE" end
    if self:GetActualGold() < self:GetRequiredReserve() + pot then return false, "INSUFFICIENT_ACTUAL_GOLD" end
    return true
end
function Bank:CanAcceptDeposits()
    if self:GetState().securityLock then return false, self:GetState().securityLock end
    return self:IsSolvent(), self:IsSolvent() and nil or "BANK_UNDERFUNDED"
end
function Bank:CanAcceptLiability(additionalAmount)
    if not self:IsSolvent() then return false, "BANK_UNDERFUNDED" end
    return self:GetActualGold() >= self:GetRequiredReserve() + max(0, floor(tonumber(additionalAmount) or 0)), "INSUFFICIENT_COVERAGE"
end
function Bank:CanCreateFinancialObligation(maximumLiability, playerPot) return self:CanOpenBet(maximumLiability, playerPot) end

function Bank:CheckSolvency()
    local state, actual, required = self:GetState(), self:GetActualGold(), self:GetRequiredReserve()
    local status = state.securityLock or (actual < required and "UNDERFUNDED" or "SOLVENT")
    state.status, state.lastActualGold, state.lastRequiredReserve = status, actual, required
    Debug("ACTUAL_GOLD " .. actual); Debug("REQUIRED_RESERVE " .. required); Debug("PRIVATE_AVAILABLE " .. max(0, actual - required)); Debug("STATUS " .. status)
    if status == "UNDERFUNDED" and runtime.lastStatus ~= "UNDERFUNDED" then
        self:ShowReserveWarning("Shortfall: " .. Money(required - actual) .. ". New bets are locked.")
        Debug("UNDERFUNDED shortfall=" .. (required - actual)); Debug("BETTING_LOCKED")
    elseif status == "SOLVENT" and runtime.lastStatus == "UNDERFUNDED" then Chat("Bank coverage restored. New bets are available.") end
    runtime.lastStatus = status
    if self.frame and self.frame:IsShown() then self:RefreshUI() end
    self:RefreshBagBankDisplay()
    return status
end

function Bank:ShowReserveWarning(message)
    local now = Clock()
    if now - (runtime.lastWarning or 0) < WARNING_COOLDOWN then return end
    runtime.lastWarning = now
    if StaticPopupDialogs then
        StaticPopupDialogs.GAMBLE_BANK_WARNING = StaticPopupDialogs.GAMBLE_BANK_WARNING or {
            text = "BANKRESERVE WARNING\n\n%s", button1 = "OK", timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
        StaticPopup_Show("GAMBLE_BANK_WARNING", tostring(message))
    else Chat(message) end
end

function Bank:GetLedger() return self:GetState().ledger end
function Bank:GetOpenPayments()
    local payments={}
    for betID,account in pairs(self:GetState().accounts or {}) do
        for _,kind in ipairs({"refunds","payouts"}) do
            for _,item in pairs(account[kind] or {}) do
                if item.status~="COMPLETED" and (tonumber(item.amount) or 0)>0 then
                    payments[#payments+1]={wagerID=betID,name=item.player,amount=item.amount,reason=kind=="refunds" and "Refund" or "Winnings",fromBankLedger=true}
                end
            end
        end
    end
    table.sort(payments,function(a,b) return tostring(a.wagerID)..a.name < tostring(b.wagerID)..b.name end)
    return payments
end

function Bank:ValidateLedger()
    local state, previous, seen, startIndex = self:GetState(), "GENESIS", {}, 1
    local snapshot = state.snapshots and state.snapshots[#state.snapshots]
    if snapshot and snapshot.sequence and snapshot.sequence <= #(state.ledger or {}) then
        startIndex = snapshot.sequence + 1; previous = snapshot.checksum
        for index = 1, snapshot.sequence do local tx = state.ledger[index]; if not tx or seen[tx.id] then state.integrityOK = false; state.securityLock = "BANK SECURITY LOCK"; return false end; seen[tx.id] = true end
    end
    for index = startIndex, #(state.ledger or {}) do
        local tx = state.ledger[index]
        if tx.sequence ~= index or tx.previousChecksum ~= previous or tx.checksum ~= Hash(TxMaterial(tx)) or seen[tx.id] then
            state.integrityOK = false; state.securityLock = "BANK SECURITY LOCK"; return false
        end
        seen[tx.id], previous = true, tx.checksum
    end
    if state.sequence ~= #(state.ledger or {}) or (state.sequence > 0 and state.lastChecksum ~= previous) then state.integrityOK = false; state.securityLock = "BANK SECURITY LOCK"; return false end
    state.integrityOK = true
    return true
end

local function Backup(bankIdentity)
    local root, key = RootDB(), Canonical(bankIdentity)
    root.backups[key] = root.backups[key] or { bankIdentity = bankIdentity, entries = {}, snapshots = {}, highestSequence = 0 }
    return root.backups[key]
end

function Bank:_StoreBackupTx(fields, sender)
    local bankIdentity, sequence = fields[2], tonumber(fields[3])
    if not bankIdentity or not sequence or SamePlayer(bankIdentity, PlayerName()) or not SamePlayer(bankIdentity, sender) then return end
    local backup = Backup(bankIdentity)
    local record = table.concat(fields, "|")
    local existing = backup.entries[sequence]
    if existing and existing.record ~= record then backup.conflict = sequence; return end
    backup.entries[sequence] = { record = record, fields = fields, sender = sender }
    backup.highestSequence = max(backup.highestSequence or 0, sequence)
end

function Bank:_StoreBackupSnapshot(fields, sender)
    local bankIdentity, sequence = fields[2], tonumber(fields[3])
    if not bankIdentity or not sequence or SamePlayer(bankIdentity, PlayerName()) or not SamePlayer(bankIdentity, sender) then return end
    Backup(bankIdentity).snapshots[sequence] = { fields = fields, sender = sender }
end

function Bank:RequestRecovery()
    local state = self:GetState()
    runtime.recovery = { bankIdentity = state.bankIdentity, fromSequence = state.sequence or 0, candidates = {}, sources = {}, started = Clock(), conflict = nil }
    Send("RECOVER", state.bankIdentity, state.sequence or 0)
    Debug("RECOVERY: REQUEST seq=" .. (state.sequence or 0))
    if C_Timer and C_Timer.After then C_Timer.After(4, function() Bank:_FinalizeRecovery() end) end
    return true
end

function Bank:_RespondRecovery(bankIdentity, fromSequence)
    local backup = Backup(bankIdentity)
    local delay, messages = 0, {}
    local startAt = tonumber(fromSequence) or 0
    for sequence = startAt + 1, backup.highestSequence or 0 do if backup.entries[sequence] then messages[#messages + 1] = backup.entries[sequence].fields end end
    for _, fields in ipairs(messages) do
        delay = delay + .08
        if C_Timer and C_Timer.After then C_Timer.After(delay, function() Send("RECOVERY_DATA", unpack(fields, 2)) end) end
    end
end

function Bank:_ReceiveRecovery(fields, sender)
    local recovery = runtime.recovery
    if not recovery or not SamePlayer(fields[2], recovery.bankIdentity) then return end
    local sequence, checksum = tonumber(fields[3]), fields[#fields]
    if not sequence or not checksum then return end
    recovery.sources[Canonical(sender)] = true
    recovery.candidates[sequence] = recovery.candidates[sequence] or {}
    local candidate = recovery.candidates[sequence][checksum]
    if not candidate then candidate = { fields = fields, senders = {} }; recovery.candidates[sequence][checksum] = candidate end
    candidate.senders[Canonical(sender)] = true
    local variants = 0; for _ in pairs(recovery.candidates[sequence]) do variants = variants + 1 end
    if variants > 1 then recovery.conflict = sequence end
end

function Bank:_FinalizeRecovery(allowSingleSource)
    local recovery, state = runtime.recovery, self:GetState()
    if not recovery then return end
    if recovery.conflict then state.securityLock = "RECOVERY CONFLICT"; Debug("RECOVERY: CONFLICT seq=" .. recovery.conflict); self:CheckSolvency(); return end
    local sourceCount = 0; for _ in pairs(recovery.sources) do sourceCount = sourceCount + 1 end
    if sourceCount == 0 then Chat("No recovery data found."); return end
    if sourceCount < 2 and state.sequence == 0 and not allowSingleSource then state.securityLock = "RECOVERY REVIEW"; Chat("Only one backup source found. Verify it and confirm recovery in the bank window."); self:CheckSolvency(); return end
    -- Delta-Recovery is accepted only when every next sequence has one consistent candidate.
    local nextSequence, applied = (state.sequence or 0) + 1, 0
    while recovery.candidates[nextSequence] do
        local candidate; for _, value in pairs(recovery.candidates[nextSequence]) do candidate = value; break end
        if not candidate then break end
        if (recovery.fromSequence or 0) == 0 and not allowSingleSource then
            local confirmations = 0; for _ in pairs(candidate.senders or {}) do confirmations = confirmations + 1 end
            if confirmations < 2 then state.securityLock = "RECOVERY REVIEW"; break end
        end
        local f = candidate.fields
        local tx = { sequence = tonumber(f[3]), id = f[4], betID = f[5], type = f[6], player = f[7], amount = tonumber(f[8]), timestamp = tonumber(f[9]) or 0, before = f[10], after = f[11], metadata = f[12], previousChecksum = f[13], checksum = f[14] }
        if tx.previousChecksum ~= state.lastChecksum or tx.checksum ~= Hash(TxMaterial(tx)) then state.securityLock = "RECOVERY CONFLICT"; break end
        local account = Account(state, tx.betID)
        local key = Canonical(tx.player)
        if tx.type == "DEPOSIT" or tx.type == "POT_RESERVE" then account.activePot = account.activePot + tx.amount; account.deposits[key] = (account.deposits[key] or 0) + tx.amount; account.state = "ACTIVE"
        elseif tx.type == "POT_RELEASE" then account.activePot = max(0, account.activePot - tx.amount); account.state = "RESULT"
        elseif tx.type == "PAYOUT_CREATED" then account.payouts[key] = { player = tx.player, amount = tx.amount, status = "OPEN" }; account.state = "PAYOUT"
        elseif tx.type == "REFUND_CREATED" then account.refunds[key] = { player = tx.player, amount = tx.amount, status = "OPEN" }; account.state = "REFUND"
        elseif tx.type == "PAYOUT_COMPLETED" and account.payouts[key] then account.payouts[key].status = "COMPLETED"
        elseif tx.type == "REFUND_COMPLETED" and account.refunds[key] then account.refunds[key].status = "COMPLETED"
        elseif tx.type == "BANK_REVENUE" then state.freeBankReserve = state.freeBankReserve + tx.amount
        elseif tx.type == "RISK_RESERVED" then state.riskReservations[tx.betID] = { amount = tx.amount, status = "RESERVED" }
        elseif tx.type == "RISK_RELEASED" and state.riskReservations[tx.betID] then state.riskReservations[tx.betID].status = "RELEASED"
        elseif tx.type == "MANUAL_ADJUSTMENT" then state.freeBankReserve = state.freeBankReserve + (tostring(tx.metadata):sub(1, 1) == "-" and -tx.amount or tx.amount) end
        if StateVector(state) ~= tx.after then state.securityLock = "RECOVERY CONFLICT"; break end
        state.ledger[#state.ledger + 1] = tx; state.sequence = tx.sequence; state.lastChecksum = tx.checksum
        state.knownTransactions[tx.id] = { type = tx.type, amount = tx.amount, betID = tx.betID, sequence = tx.sequence, checksum = tx.checksum }
        applied = applied + 1; nextSequence = nextSequence + 1
    end
    Debug("RECOVERY: RECEIVED " .. ((recovery.fromSequence or 0) + 1) .. "-" .. (state.sequence or 0))
    if applied == 0 then Chat("No missing ledger entries found.")
    elseif not state.securityLock and self:ValidateLedger() then Chat(applied .. " ledger entries restored consistently."); state.securityLock = nil
    else state.securityLock = state.securityLock or "RECOVERY CONFLICT" end
    self:CheckSolvency()
end

function Bank:ConfirmRecovery()
    if self:GetState().securityLock ~= "RECOVERY REVIEW" or not runtime.recovery then return false end
    self:GetState().securityLock = nil
    self:_FinalizeRecovery(true)
    return self:GetState().securityLock == nil
end

function Bank:OnAddonMessage(prefix, message, channel, sender)
    if prefix ~= PREFIX or (channel ~= "PARTY" and channel ~= "RAID" and channel ~= "INSTANCE_CHAT") then return end
    local fields = Split(message)
    if fields[1] == "TX" then self:_StoreBackupTx(fields, sender)
    elseif fields[1] == "SNAP" then self:_StoreBackupSnapshot(fields, sender)
    elseif fields[1] == "RECOVER" and not SamePlayer(fields[2], PlayerName()) then self:_RespondRecovery(fields[2], tonumber(fields[3]) or 0)
    elseif fields[1] == "RECOVERY_DATA" then
        table.remove(fields, 1); table.insert(fields, 1, "TX"); self:_ReceiveRecovery(fields, sender)
    end
end

function Bank:OnMoneyChanged()
    local actual, required = self:GetActualGold(), self:GetRequiredReserve()
    if runtime.lastActual and actual < runtime.lastActual then
        local spent = runtime.lastActual - actual
        local previousPrivate = max(0, runtime.lastActual - required)
        if spent > previousPrivate then self:ShowReserveWarning("Spent: " .. Money(spent) .. "\nPrivate funds available: " .. Money(previousPrivate) .. "\nBank funds affected: " .. Money(spent - previousPrivate) .. "\n\nThis may lock new bets.") end
    end
    runtime.lastActual = actual
    self:CheckSolvency()
end

function Bank:SyncFromRuntime(wagers, payments, playerName)
    local me = playerName or PlayerName()
    for _, wager in ipairs(wagers or {}) do
        if SamePlayer(wager.host, me) then
            local account = Account(self:GetState(), wager.id)
            for _, bet in pairs(wager.bets or {}) do
                local status
                for name, value in pairs(wager.paymentStatus or {}) do if SamePlayer(name, bet.bettor) then status = value; break end end
                if status == "PAID" then self:RegisterDeposit(wager.id, bet.bettor, bet.stake) end
            end
            if wager.locked and not wager.result then self:ActivateWager(wager.id) end
            if wager.result and account.state ~= "RESULT" and account.state ~= "PAYOUT" and account.state ~= "REFUND" and account.state ~= "SETTLED" then
                local obligations = {}
                for _, payment in ipairs(payments or {}) do if payment.wagerID == wager.id then obligations[#obligations + 1] = payment end end
                self:ResolveWager(wager.id, obligations, wager.bankCut or 0, wager.result.name or wager.result.outcome or "RESULT")
            end
        end
    end
end

function Bank:GetStatusText()
    local totals, actual, required, status = self:GetTotals(), self:GetActualGold(), self:GetRequiredReserve(), self:GetStatus()
    local coverage = required > 0 and floor(actual / required * 1000 + .5) / 10 or 100
    local lines = {
        "|cffffd45aBANK STATUS|r", "",
        "Actual Gold: " .. Money(actual),
        "Private Available: " .. Money(max(0, actual - required)), "",
        "Free Bank Reserve: " .. Money(totals.free),
        "Active Pots: " .. Money(totals.active),
        "Pending Payouts: " .. Money(totals.payout),
        "Refunds: " .. Money(totals.refund),
        "Risk reserved: " .. Money(totals.risk), "",
        "Required Reserve: " .. Money(required),
        "Coverage: " .. coverage .. " %",
        "Status: " .. (status == "SOLVENT" and "|cff55ff55SOLVENT|r" or "|cffff4444" .. status .. "|r"),
    }
    if actual < required then lines[#lines + 1] = "Shortfall: " .. Money(required - actual); lines[#lines + 1] = "|cffff4444NEW BETS LOCKED|r" end
    local open = {}
    for betID, account in pairs(self:GetState().accounts or {}) do
        for _, item in pairs(account.payouts or {}) do if item.status ~= "COMPLETED" then open[#open + 1] = "PAYOUT → " .. item.player .. ": " .. Money(item.amount) .. " [" .. betID .. "]" end end
        for _, item in pairs(account.refunds or {}) do if item.status ~= "COMPLETED" then open[#open + 1] = "REFUND → " .. item.player .. ": " .. Money(item.amount) .. " [" .. betID .. "]" end end
    end
    table.sort(open)
    if #open > 0 then lines[#lines + 1] = ""; lines[#lines + 1] = "|cffffd45aOpene Verpflichtungen:|r"; for index = 1, math.min(#open, 8) do lines[#lines + 1] = open[index] end; if #open > 8 then lines[#lines + 1] = "+ " .. (#open - 8) .. " weitere" end end
    if self:GetState().lastManualAdjustment then lines[#lines + 1] = ""; lines[#lines + 1] = "|cffffaa00Letzte manuelle Korrektur: " .. Safe(self:GetState().lastManualAdjustment.reason) .. "|r" end
    return table.concat(lines, "\n")
end

function Bank:RefreshUI()
    if not self.frame then return end
    self.statusText:SetText(self:GetStatusText())
    self.ledgerText:SetText("Ledger: " .. #(self:GetState().ledger or {}) .. " transactions · Sequence " .. (self:GetState().sequence or 0))
    if self.recoveryConfirm then self.recoveryConfirm:SetShown(self:GetState().securityLock == "RECOVERY REVIEW") end
end

local function CombinedBagFrame()
    return _G.ContainerFrameCombinedBags or _G.CombinedBagFrame or _G.CombinedBackpack
end

function Bank:RefreshBagBankDisplay()
    local bag = CombinedBagFrame()
    if not bag then return false end
    if not self.bagBankDisplay then
        local display = CreateFrame("Frame", "GambleBagBankDisplay", UIParent, "BackdropTemplate")
        display:SetSize(250, 22)
        display:SetFrameStrata("HIGH")
        display:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
        display:SetBackdropColor(.025, .025, .025, .92)
        display:SetBackdropBorderColor(.55, .42, .12, .9)
        display.text = display:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        display.text:SetPoint("RIGHT", -7, 0)
        display.text:SetJustifyH("RIGHT")
        display:Hide()
        self.bagBankDisplay = display
        if bag.HookScript then
            bag:HookScript("OnShow", function() Bank:RefreshBagBankDisplay() end)
            bag:HookScript("OnHide", function() if Bank.bagBankDisplay then Bank.bagBankDisplay:Hide() end end)
        end
    end
    local display = self.bagBankDisplay
    display:ClearAllPoints()
    display:SetPoint("TOPRIGHT", bag, "BOTTOMRIGHT", -8, 1)
    local bankGold = self:GetBankOwnedGold()
    display.text:SetText("|cffffd45aGable Bank:|r " .. Money(bankGold))
    display:SetShown(bag:IsShown() and bankGold > 0)
    return true
end

function Bank:AttachToMainUI(mainFrame, settingsButton)
    if self.frame or not mainFrame then return end
    local button = CreateFrame("Button", nil, mainFrame)
    button:SetSize(24, 24)
    if settingsButton then button:SetPoint("LEFT", settingsButton, "RIGHT", 6, 0) else button:SetPoint("TOPLEFT", 322, -36) end
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetAtlas("plunderstorm-menu-shop-selected", false)
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:SetScript("OnEnter", function(owner)
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT"); GameTooltip:SetText("Bank Security", 1, .82, .12)
        GameTooltip:AddLine("View bank reserve, coverage and outstanding obligations.", 1, 1, 1, true); GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local frame = CreateFrame("Frame", "GambleBankSecurityFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(430, 430); frame:SetPoint("TOPLEFT", mainFrame, "TOPRIGHT", 8, 0); frame:SetFrameStrata("DIALOG"); frame:SetClampedToScreen(true)
    frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton"); frame:SetScript("OnDragStart", frame.StartMoving); frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame.TitleText:SetText("Gamble - Bank Security")
    local status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); status:SetPoint("TOPLEFT", 20, -42); status:SetPoint("TOPRIGHT", -20, -42); status:SetJustifyH("LEFT"); status:SetJustifyV("TOP")
    local ledger = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); ledger:SetPoint("BOTTOMLEFT", 20, 58); ledger:SetPoint("RIGHT", -20, 0); ledger:SetJustifyH("LEFT")
    local recover = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate"); recover:SetSize(170, 25); recover:SetPoint("BOTTOMLEFT", 20, 20); recover:SetText("RECOVER BANK DATA"); recover:SetScript("OnClick", function() Bank:RequestRecovery() end)
    local confirm = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate"); confirm:SetSize(170, 25); confirm:SetPoint("BOTTOM", 0, 52); confirm:SetText("Accept Single Source"); confirm:SetScript("OnClick", function() Bank:ConfirmRecovery(); Bank:RefreshUI() end); confirm:Hide()
    button:SetScript("OnClick", function() if frame:IsShown() then frame:Hide() else Bank:RefreshUI(); frame:Show(); frame:Raise() end end)
    frame:Hide(); self.frame, self.statusText, self.ledgerText, self.mainButton, self.recoveryConfirm = frame, status, ledger, button, confirm
end

function Bank:Initialize()
    if runtime.initialized then return end
    runtime.initialized = true
    RootDB(); self:GetState(); self:ValidateLedger()
    local register = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
    if register then pcall(register, PREFIX) end
    runtime.lastActual = self:GetActualGold(); self:CheckSolvency()
    if C_Timer and C_Timer.After then
        C_Timer.After(1, function() Bank:RefreshBagBankDisplay() end)
        C_Timer.After(4, function() Bank:RefreshBagBankDisplay() end)
    end
end

function Bank:OnEvent(event, ...)
    if event == "PLAYER_LOGIN" then self:Initialize()
    elseif event == "PLAYER_MONEY" then self:OnMoneyChanged()
    elseif event == "BAG_UPDATE_DELAYED" then self:RefreshBagBankDisplay()
    elseif event == "CHAT_MSG_ADDON" then self:OnAddonMessage(...)
    elseif event == "PLAYER_LOGOUT" then self:_Snapshot(true) end
end

local eventFrame = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_MONEY", "BAG_UPDATE_DELAYED", "CHAT_MSG_ADDON", "PLAYER_LOGOUT" }) do eventFrame:RegisterEvent(event) end
eventFrame:SetScript("OnEvent", function(_, event, ...) Bank:OnEvent(event, ...) end)
