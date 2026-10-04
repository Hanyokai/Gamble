-- Host-authoritative timed measurement. Prefer WoW's native overall damage
-- counters and subtract a start snapshot. Never reset the player's meter.
GambleDamageRace = { jobs = {} }
local Race=GambleDamageRace
local CreateFrame = GambleUIStyle and GambleUIStyle.CreateFrame or CreateFrame
local events
local combatUnits={"player"}
for i=1,4 do combatUnits[#combatUnits+1]="party"..i end
for i=1,40 do combatUnits[#combatUnits+1]="raid"..i end
local function CombatLogReadable()
    if C_CombatLog and C_CombatLog.IsCombatLogRestricted then
        local ok, restricted=pcall(C_CombatLog.IsCombatLogRestricted)
        if not ok or restricted~=false then return false end
    end
    return type(CombatLogGetCurrentEventInfo)=="function"
end
function Race:NativeAvailable()
    return C_DamageMeter and type(C_DamageMeter.GetCombatSessionFromType)=="function"
        and Enum and Enum.DamageMeterSessionType and Enum.DamageMeterType
end
function Race:Available()
    return self:NativeAvailable() or CombatLogReadable()
end
local function Readable(value)
    if canaccessvalue and not canaccessvalue(value) then return false end
    if issecretvalue and issecretvalue(value) then return false end
    return true
end
function Race:ReadNative(snapshot, sessionType, sessionID)
    if not self:NativeAvailable() then return nil,"WoW Damage Meter API is unavailable." end
    if GetCVarBool and not GetCVarBool("damageMeterEnabled") then return nil,"Enable WoW Damage Meter in Options first." end
    local failure="WoW damage values are protected or unavailable. Start outside combat; protected values at the deadline require a refund."
    local ok,result=pcall(function()
        -- Query known roster GUIDs directly: the summary list can conceal its
        -- identities even when per-source totals are readable out of combat.
        if snapshot and type(C_DamageMeter.GetCombatSessionSourceFromType)=="function" then
            local totals={}
            for guid in pairs(snapshot) do
                local source
                if sessionID and C_DamageMeter.GetCombatSessionSourceFromID then
                    source=C_DamageMeter.GetCombatSessionSourceFromID(sessionID,Enum.DamageMeterType.DamageDone,guid,nil)
                else source=C_DamageMeter.GetCombatSessionSourceFromType(sessionType or Enum.DamageMeterSessionType.Overall,Enum.DamageMeterType.DamageDone,guid,nil) end
                if not Readable(source) or type(source)~="table" then
                    failure="Damage Meter returned no readable participant session. Wait until combat ends and retry."; return nil
                end
                local amount=source.totalAmount
                if not Readable(amount) then
                    failure="WoW Damage Meter hides participant damage. Wait until combat ends and retry."; return nil
                end
                if type(amount)~="number" or amount<0 or amount~=amount then
                    failure="Damage Meter returned an invalid participant total."; return nil
                end
                totals[guid]=amount
            end
            return totals
        end
        local data=sessionID and C_DamageMeter.GetCombatSessionFromID and C_DamageMeter.GetCombatSessionFromID(sessionID,Enum.DamageMeterType.DamageDone)
            or C_DamageMeter.GetCombatSessionFromType(sessionType or Enum.DamageMeterSessionType.Overall,Enum.DamageMeterType.DamageDone)
        if not Readable(data) then failure="Damage Meter session is protected. Wait until combat ends."; return nil end
        if type(data)~="table" then failure="Damage Meter returned no overall session. Enable the meter and complete a combat first."; return nil end
        if not Readable(data.combatSources) then failure="Damage Meter source list is protected. Wait until combat ends."; return nil end
        if type(data.combatSources)~="table" then failure="Damage Meter returned no source list for the overall session."; return nil end
        local totals={}
        for _,row in ipairs(data.combatSources) do
            if not Readable(row) then return nil end
            local guid=row.sourceGUID
            if not Readable(guid) then failure="WoW Damage Meter hides source identities. Wait until combat ends and retry."; return nil end
            -- Creature/other-party rows are irrelevant to this race. Their
            -- protected totals must not prevent reading our participants.
            if guid and (not snapshot or snapshot[guid]) then
                local amount=row.totalAmount
                if not Readable(amount) then failure="WoW Damage Meter hides participant damage. Wait until combat ends and retry."; return nil end
                if type(guid)~="string" or type(amount)~="number" or amount<0 or amount~=amount then return nil end
                if totals[guid] then return nil end
                totals[guid]=amount
            end
        end
        return totals
    end)
    if not ok then
        local detail=Readable(result) and type(result)=="string" and result or "protected API error"
        return nil,"Damage Meter API failed: "..detail
    end
    if not result then return nil,failure end
    return result
end
function Race:NativeDelta(job)
    local current,reason=self:ReadNative(job.wager.snapshot)
    if not current then job.invalidReason=reason end
    if not current or job.invalid then return false end
    for guid in pairs(job.totals) do
        local before,after=job.baseline[guid] or 0,current[guid] or 0
        if after<before then job.invalidReason="Damage Meter counters were reset or lost."; return false end
        job.totals[guid]=after-before
    end
    return true
end
function Race:InCombat()
    if not UnitAffectingCombat then return false end
    for _,unit in ipairs(combatUnits) do
        local ok,value=pcall(UnitAffectingCombat,unit)
        if not ok or not Readable(value) or value then return true end
    end
    return false
end
function Race:Winners(totals)
    local highest,winners=0,{}
    for guid,total in pairs(totals or {}) do
        if total>highest then highest,winners=total,{guid}
        elseif total==highest and total>0 then winners[#winners+1]=guid end
    end
    table.sort(winners); return winners,highest
end
function Race:Consume(job,event)
    local kind,source=event[2],event[4]
    if not job.totals[source] then return end
    if bit and type(event[10])=="number" and bit.band(event[10],0x10)~=0 then return end
    local amount,overkill
    if kind=="SWING_DAMAGE" then amount,overkill=event[12],event[13]
    elseif kind=="SPELL_DAMAGE" or kind=="SPELL_PERIODIC_DAMAGE" or kind=="RANGE_DAMAGE" or kind=="DAMAGE_SHIELD" or kind=="DAMAGE_SPLIT" then amount,overkill=event[15],event[16]
    else return end
    if canaccessvalue and not canaccessvalue(amount) then job.invalid=true; return end
    if issecretvalue and issecretvalue(amount) then job.invalid=true; return end
    if type(amount)~="number" or amount<0 then job.invalid=true; return end
    -- Count effective damage, not damage beyond the target's remaining HP.
    if type(overkill)=="number" then amount=math.max(0,amount-math.max(0,overkill)) end
    job.totals[source]=job.totals[source]+amount
end
function Race:Start(wager,seconds,finish)
    if not self:Available() then return false,"Neither WoW Damage Meter nor readable combat logs are available." end
    seconds=tonumber(seconds)
    if not seconds or seconds~=math.floor(seconds) or seconds<10 or seconds>1800 then return false,"Duration must be 10–1800 whole seconds." end
    local baseline,backend
    if self:NativeAvailable() then
        local reason
        baseline,reason=self:ReadNative(wager.snapshot)
        if not baseline then return false,reason end
        backend="native"
    elseif not self.eventAvailable then
        self.eventAvailable=pcall(events.RegisterEvent,events,"COMBAT_LOG_EVENT_UNFILTERED")
        if not self.eventAvailable then return false,"Combat-log registration is unavailable on this client." end
    end
    local totals={}; for guid in pairs(wager.snapshot) do totals[guid]=0 end
    self.jobs[wager.id]={wager=wager,totals=totals,baseline=baseline,backend=backend or "log",ends=GetTime()+seconds,finish=finish}
    return true
end
function Race:Render(main,wager,mode,host)
    if not self.duration then
        self.duration=CreateFrame("EditBox",nil,main.frame,"InputBoxTemplate")
        self.duration:SetSize(65,24); self.duration:SetPoint("TOPLEFT",220,-140); self.duration:SetAutoFocus(false); self.duration:SetNumeric(true); self.duration:SetText("1")
        self.label=main.frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); self.label:SetPoint("RIGHT",self.duration,"LEFT",-8,0); self.label:SetText("Duration (minutes):")
        self.start=CreateFrame("Button",nil,main.frame,"UIPanelButtonTemplate"); self.start:SetSize(180,26); self.start:SetPoint("BOTTOMRIGHT",-18,145); self.start:SetText("Start Damage Race")
        self.start:SetScript("OnClick",function() main:StartDamageRace() end)
        self.main=main
    end
    local visible=mode=="DAMAGE_RACE" and main.uiTab~="RUNNING" and main.uiTab~="DON_DETAIL"
    self.duration:SetShown(visible and (not wager or wager.setupPending) and (not wager or host))
    self.label:SetShown(self.duration:IsShown())
    self.start:SetShown(visible and wager and host and not wager.setupPending and not wager.locked and not wager.result or false)
    self.start:SetEnabled(main:CanStartDamageRace(wager) and true or false)
    if visible and wager and wager.locked and not wager.result then
        local job=self.jobs[wager.id]
        main.status:SetText(job and job.waiting and "Damage Race — Waiting for combat to end. Damage still counts." or ("Damage Race — "..(job and string.format("%.1f minutes remaining",math.max(0,job.ends-GetTime())/60) or "Measurement in progress")..". Betting closed."))
    end
end
events=CreateFrame("Frame")
-- Never register restricted combat-log events during addon loading.
events:RegisterEvent("PLAYER_LOGIN")
if C_DamageMeter then pcall(events.RegisterEvent,events,"DAMAGE_METER_RESET") end
events:SetScript("OnEvent",function(_,eventName)
    if eventName=="DAMAGE_METER_RESET" then
        for _,job in pairs(Race.jobs) do if job.backend=="native" then job.invalid=true; job.invalidReason="WoW Damage Meter was reset during the race." end end
        return
    end
    if eventName=="PLAYER_LOGIN" then
        if Race.main then
            for _,a in ipairs(Race.main:GetDamageRaceWagers()) do
                local name,realm=UnitFullName("player")
                local me=realm and realm~="" and name.."-"..realm or name
                if a.mode=="DAMAGE_RACE" and a.locked and not a.result and a.host==me then
                    Race.main:FinishDamageRace(a,{},0,true)
                end
            end
        end
        return
    end
    if not next(Race.jobs) then return end
    local hasLog=false; for _,job in pairs(Race.jobs) do if job.backend=="log" then hasLog=true end end
    if not hasLog then return end
    if not CombatLogReadable() then for _,job in pairs(Race.jobs) do if job.backend=="log" then job.invalid=true end end; return end
    local ok,event=pcall(function() return {CombatLogGetCurrentEventInfo()} end)
    for _,job in pairs(Race.jobs) do
        if job.backend=="log" then
            if not ok then job.invalid=true
            else local readable=pcall(Race.Consume,Race,job,event); if not readable then job.invalid=true end end
        end
    end
end)
local elapsed=0
events:SetScript("OnUpdate",function(_,dt)
    if not next(Race.jobs) then return end
    elapsed=elapsed+dt; if elapsed<.25 then return end; elapsed=0
    for id,job in pairs(Race.jobs) do
        if job.wager.result then Race.jobs[id]=nil
        elseif GetTime()>=job.ends then
            if not job.invalid and Race:InCombat() then
                job.waiting=true; job.readGrace=nil
            else
                job.readGrace=job.readGrace or (GetTime()+5)
                local readable=job.backend~="native" or Race:NativeDelta(job)
                if job.invalid or readable or GetTime()>=job.readGrace then
                    Race.jobs[id]=nil
                    if not readable then job.invalid=true end
                    local winners,amount=Race:Winners(job.totals)
                    job.finish(job.wager,winners,amount,job.invalid,job.invalidReason,job.totals)
                end
            end
        end
    end
    if Race.main and Race.main.frame:IsShown() then
        local a=Race.main:GetDamageRaceSelection()
        if a and Race.jobs[a.id] then
            local job=Race.jobs[a.id]
            Race.main.status:SetText(job.waiting and "Damage Race — Waiting for combat to end. Damage still counts." or string.format("Damage Race — %.1f minutes remaining. Betting closed.",math.max(0,job.ends-GetTime())/60))
        end
    end
end)
