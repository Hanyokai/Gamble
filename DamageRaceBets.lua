-- Shared Top-3 rules and Boss Damage Series. Host alone reads damage data.
GambleDamageBets = { drafts = {}, jobs = {} }
local B = GambleDamageBets
local bossTargetUnits={"target"}
for i=1,4 do bossTargetUnits[#bossTargetUnits+1]="party"..i.."target" end
for i=1,40 do bossTargetUnits[#bossTargetUnits+1]="raid"..i.."target" end
function B:Queue(callback)
    self.queue=self.queue or {}; self.queue[#self.queue+1]=callback
end
function B:IsMode(mode) return mode == "DAMAGE_RACE" or mode == "BOSS_DAMAGE_SERIES" end
function B:Places(a)
    if a.mode=="BOSS_DAMAGE_SERIES" and a.rankRoster then
        local count=0; for _ in pairs(a.rankRoster) do count=count+1 end
        return math.min(3,count)
    end
    local count=0; for _ in pairs(a.snapshot or {}) do count=count+1 end
    return math.min(3,count)
end
function B:UpdateRoster(a,roster)
    if a.mode~="BOSS_DAMAGE_SERIES" or a.result then return end
    a.snapshot=a.snapshot or {}
    local current={}
    for _,member in ipairs(roster) do
        current[member.guid]=member
        a.snapshot[member.guid]=a.snapshot[member.guid] or {name=member.name,class=member.class,online=member.online}
    end
    a.rankRoster=current
end
function B:Decode(token)
    local picks={}
    if type(token)~="string" or token:sub(1,5)~="RANK:" then return picks end
    for guid in token:sub(6):gmatch("[^,]+") do picks[#picks+1]=guid end
    return picks
end
function B:Valid(a,token)
    local picks,seen=self:Decode(token),{}
    if #picks~=self:Places(a) or #picks<2 then return false end
    for _,guid in ipairs(picks) do
        if not a.snapshot[guid] or seen[guid] then return false end
        seen[guid]=true
    end
    return true
end
function B:BossPickLocked(a,index)
    return a.result or (a.rankResults or {})[index] or (a.rankBossLocks or {})[index] or a.currentSeriesBoss==index or self.jobs[a.id] and self.jobs[a.id].index==index
end
function B:SeriesPicksComplete(a,picks)
    for index,boss in ipairs(a.bosses or {}) do
        local required=not boss.defeated and not (a.seriesResults or {})[index] and not (a.rankResults or {})[index]
        if required and self.main and self.main.BossNeedsSeriesPrediction then required=self.main:BossNeedsSeriesPrediction(a,index) end
        if required and not self:Valid(a,picks and picks[index] and picks[index].guid) then return false end
    end
    return true
end
function B:PredictionName(a,index,place,guid,name)
    local ranking=(a.rankResults or {})[index]
    local result=(a.seriesResults or {})[index]
    if not ranking or not next(ranking) or (result and result.name=="Not scored") then return name end
    local correct=ranking[place] and ranking[place][guid]
    return (correct and "|cff55ff55" or "|cffff5555")..name.."|r"
end
function B:BossResultText(a,index)
    local result=(a.seriesResults or {})[index]
    local ranking=(a.rankResults or {})[index]
    if result and result.name=="Not scored" then return "|cffaaaaaaErgebnis nicht auswertbar|r" end
    if not ranking or not next(ranking) then return "|cffaaaaaaKein Ergebnis|r" end
    local places={}
    for place=1,3 do
        local names={}
        for guid in pairs(ranking[place] or {}) do
            local member=(a.snapshot or {})[guid]
            names[#names+1]=member and (member.name:match("^([^%-]+)") or member.name) or "Unbekannter Spieler"
        end
        table.sort(names)
        if #names>0 then places[#places+1]=place..". "..table.concat(names,", ") end
    end
    return "|cff55ff55Top: "..table.concat(places," / ").."|r"
end
local function TargetReadable(value)
    return not (canaccessvalue and not canaccessvalue(value)) and not (issecretvalue and issecretvalue(value))
end
function B:DebugBossTarget(main,event)
    local function safe(value)
        if not TargetReadable(value) then return "<geschuetzt>" end
        return tostring(value)
    end
    local function read(fn,unit)
        if not fn then return "<API fehlt>" end
        local ok,value=pcall(fn,unit)
        return ok and safe(value) or "<API Fehler>"
    end
    local function log(message)
        if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("Gamble BossDebug: "..message) end
    end
    log("Ereignis="..safe(event)..", Modul verbunden="..tostring(main~=nil))
    log("target: existiert="..read(UnitExists,"target")..", Name="..read(UnitName,"target")..", tot="..read(UnitIsDeadOrGhost,"target")..", Spieler="..read(UnitIsPlayer,"target"))
    local guidOK,guid=false,nil
    if UnitGUID then guidOK,guid=pcall(UnitGUID,"target") end
    local npc="<nicht verfuegbar>"
    if guidOK and TargetReadable(guid) and type(guid)=="string" then
        npc=guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-") or guid:match("^Vehicle%-%d+%-%d+%-%d+%-%d+%-(%d+)%-") or "<keine NPC-GUID>"
    elseif guidOK and not TargetReadable(guid) then npc="<geschuetzt>" end
    log("target: GUID="..(guidOK and safe(guid) or "<API fehlt/Fehler>")..", NPC-ID="..npc)
    if not main then return end
    local wagers=main:GetDamageRaceWagers()
    local live=0
    for _,a in ipairs(wagers) do if a.mode=="BOSS_DAMAGE_SERIES" and not a.result then live=live+1 end end
    log("Offene Boss-Damage-Wetten="..tostring(live))
    local ok,name=pcall(UnitName,"target")
    for _,a in ipairs(wagers) do
        if a.mode=="BOSS_DAMAGE_SERIES" and not a.result then
            local index=ok and self:BossTargetIndex(a,name)
            log("Wette="..safe(a.id)..", Ergebnis="..tostring(a.result~=nil)..", wartet auf Start="..safe(a.awaitingStart)..", Bossindex="..safe(index)..", Host="..tostring(main:IsRankHost(a))..", eigener Einsatz="..tostring(main:GetOwnRankBet(a)~=nil))
            if index then
                log("Boss: Pull-Lock="..tostring((a.rankBossLocks or {})[index]~=nil)..", Ergebnis="..tostring((a.rankResults or {})[index]~=nil)..", currentSeriesBoss="..safe(a.currentSeriesBoss)..", Messung="..tostring(self.jobs[a.id]~=nil)..", gesperrt="..tostring(not not self:BossPickLocked(a,index)))
            end
        end
    end
    log("Popup vorhanden="..tostring(self.bossPickFrame~=nil)..", sichtbar="..tostring(self.bossPickFrame and self.bossPickFrame:IsShown() or false))
end
function B:NormalizeBossName(name)
    if not TargetReadable(name) or type(name)~="string" then return end
    return name:gsub("^%s*%(!%)%s*",""):match("^%s*(.-)%s*$"):lower()
end
function B:BossTargetIndex(a,name)
    name=self:NormalizeBossName(name)
    if not name then return end
    for index,boss in ipairs(a.bosses or {}) do
        if self:NormalizeBossName(boss.name)==name then return index end
        for _,alias in ipairs(boss.aliases or {}) do if self:NormalizeBossName(alias)==name then return index end end
    end
end
-- Legacy entry points intentionally ignore target/popup requests from older clients.
function B:ScanBossTargets() end
function B:OpenBossPick() end
function B:RenderBossPick() end
function B:LockBossPick(a,index)
    a.rankBossLocks=a.rankBossLocks or {}; a.rankBossLocks[index]=true
    if self.bossPick and self.bossPick.wager==a and self.bossPick.index==index then
        self.bossPick.status="PULL — Tipp gesperrt."
        if self.bossPickFrame and self.bossPickFrame:IsShown() then self:RenderBossPick() end
    end
end
function B:Ranking(totals)
    local entries={}; for guid,amount in pairs(totals or {}) do
        if amount>0 then entries[#entries+1]={guid=guid,amount=amount} end
    end
    table.sort(entries,function(a,b) if a.amount==b.amount then return a.guid<b.guid end return a.amount>b.amount end)
    local result,last,place={},nil,0
    for index,entry in ipairs(entries) do
        if last~=entry.amount then place=index; last=entry.amount end
        if place>3 then break end
        result[place]=result[place] or {}; result[place][entry.guid]=true
    end
    return result
end
function B:Pack(ranking)
    local slots={}; for i=1,3 do
        local guids={}; for guid in pairs(ranking[i] or {}) do guids[#guids+1]=guid end
        table.sort(guids); slots[i]=table.concat(guids,"/")
    end
    return table.concat(slots,",")
end
function B:Unpack(token)
    local result={}; local index=0
    for slot in (tostring(token or "")..","):gmatch("(.-),") do
        index=index+1; if index>3 then break end
        result[index]={}; for guid in slot:gmatch("[^/]+") do result[index][guid]=true end
    end
    return result
end
function B:Points(token,ranking)
    local points=0
    for place,guid in ipairs(self:Decode(token)) do if ranking[place] and ranking[place][guid] then points=points+1 end end
    return points
end
function B:Score(a)
    local scores,best,total={},0,0
    for _,bet in pairs(a.bets or {}) do
        local score=0
        if a.mode=="BOSS_DAMAGE_SERIES" then
            for index,result in pairs(a.rankResults or {}) do
                local pick=bet.picks and bet.picks[index]
                if pick then score=score+self:Points(pick.guid,result) end
            end
        else score=self:Points(bet.targetGUID,a.rankResults and a.rankResults[1] or {}) end
        scores[bet.bettor]=score; best=math.max(best,score); total=total+bet.stake
    end
    local winners,winningStake={},0
    for _,bet in pairs(a.bets or {}) do if best>0 and scores[bet.bettor]==best then winners[#winners+1]=bet; winningStake=winningStake+bet.stake end end
    table.sort(winners,function(a,b) return a.bettor<b.bettor end)
    local payouts,assigned={},0
    for i,bet in ipairs(winners) do
        local amount=i==#winners and total-assigned or math.floor(total*bet.stake/winningStake)
        payouts[bet.bettor]=amount; assigned=assigned+amount
    end
    return scores,payouts,best
end
function B:Choose(main,state,member)
    local a=state.active
    if not a or a.result then return true end
    local index=a.mode=="BOSS_DAMAGE_SERIES" and state.seriesStep or 1
    if a.mode=="BOSS_DAMAGE_SERIES" then
        if self:BossPickLocked(a,index) then return true end
        if a.awaitingStart==false and not main:GetOwnRankBet(a) then return true end
    elseif a.locked or a.awaitingStart==false then return true end
    local key=a.id..":"..index
    local draft=self.drafts[key]
    if not draft then
        local own=main:GetOwnRankBet(a)
        draft=self:Decode(a.mode=="BOSS_DAMAGE_SERIES" and own and own.picks and own.picks[index] and own.picks[index].guid or own and own.targetGUID)
        self.drafts[key]=draft
    end
    local slot=self.slot or 1
    for i,guid in pairs(draft) do if guid==member.guid and i~=slot then draft[i]=nil end end
    draft[slot]=member.guid
    local complete=true; for i=1,self:Places(a) do if not draft[i] then complete=false end end
    local token=complete and "RANK:"..table.concat(draft,",") or nil
    state.selectedGUID,state.selectedName=token,"Top 3"
    if a.mode=="BOSS_DAMAGE_SERIES" then
        state.seriesPicks[index]=token and {guid=token,name="Top 3"} or nil
        if token and main:GetOwnRankBet(a) then main:SubmitBossRankPick(a,index,token) end
    end
    self.slot=slot%self:Places(a)+1
    return true
end
function B:PreparePicks(a,picks)
    if not a or a.mode~="BOSS_DAMAGE_SERIES" then return picks end
    picks=picks or {}
    for i=1,#a.bosses do
        if not picks[i] then picks[i]={guid="RANK_PENDING",name="Noch kein Tipp"} end
    end
    return picks
end
function B:SelectedPlace(main,state,guid)
    local a=state.active; if not a or not self:IsMode(a.mode) then return end
    local index=a.mode=="BOSS_DAMAGE_SERIES" and state.seriesStep or 1
    local draft=self.drafts[a.id..":"..index]
    if not draft then
        local own=main:GetOwnRankBet(a)
        draft=self:Decode(a.mode=="BOSS_DAMAGE_SERIES" and own and own.picks and own.picks[index] and own.picks[index].guid or own and own.targetGUID)
    end
    for place,selected in pairs(draft) do if selected==guid then return place end end
end
function B:Complete(a)
    for i,boss in ipairs(a.bosses or {}) do
        if not GambleData.IsRareBoss(boss) and not (a.rankResults or {})[i] then return false end
    end
    return #(a.bosses or {})>0
end
function B:RemainingText(a)
    local required,optional={},{}
    for index,boss in ipairs(a.bosses or {}) do
        if not (a.rankResults or {})[index] then
            local list=GambleData.IsRareBoss(boss) and optional or required
            list[#list+1]=boss.name
        end
    end
    local function listText(list)
        local names={}; for i=1,math.min(6,#list) do names[#names+1]=list[i] end
        return table.concat(names,", ")..(#list>6 and (" … +"..(#list-6).." weitere (siehe Bossliste)") or "")
    end
    local text=#required>0 and ("Noch nicht gewertet ("..#required.."): "..listText(required)) or "Alle Pflichtbosse sind gewertet."
    if #optional>0 then text=text.."\nOptionale Rares ("..#optional.."): "..listText(optional) end
    if a.rankMeasurementFailed then
        return text.."\n\nDamage-Auswertung unvollständig. Bei Finish werden die Einsätze zurückerstattet; keine unzuverlässige Gewinnervergabe."
    end
    return text.."\n\nBei Abschluss zählen nur bereits gewertete Bosse. Fehlende Bosse geben keine Punkte und keinen Abzug."
end
function B:DismissFinish(a)
    if not a then return end
    a.rankFinishPromptPending=nil; a.rankAwaitingFinish=nil
    if self.promptedWager==a then
        self.promptedWager=nil
        if StaticPopup_Hide then StaticPopup_Hide("GAMBLE_RANK_FINISH") end
    end
end
function B:PauseFinish(a)
    if self.promptedWager==a then
        self.promptedWager=nil
        if StaticPopup_Hide then StaticPopup_Hide("GAMBLE_RANK_FINISH") end
        a.rankFinishPromptPending=true
    end
end
function B:PromptFinish(main,a)
    if not a or a.result or not main:IsRankHost(a) then return end
    a.rankFinishPromptPending=true; a.rankAwaitingFinish=true
    main:SendRankMessage("RANK_REVIEW",a.id,a.rankEndBossKilled and 1 or 0)
    main:SaveRankState()
end
function B:AnswerFinish(main,a,finish)
    if not a or a.result or not main:IsRankHost(a) then return end
    if finish then
        if self.jobs[a.id] or a.rankPendingEncounter or (GambleDamageRace and GambleDamageRace:InCombat()) then
            a.rankFinishPromptPending=true; return
        end
        self:DismissFinish(a)
        main:FinishRankDamage(a)
    else
        self:DismissFinish(a)
        main:SendRankMessage("RANK_CONTINUE",a.id)
        main:SaveRankState(); main:Refresh()
    end
end
function B:ShowFinishPrompts(main)
    if not StaticPopupDialogs or not StaticPopup_Show then return end
    if self.promptedWager and not self.promptedWager.result then return end
    local pending=false
    for _,a in ipairs(main:GetDamageRaceWagers()) do
        if a.rankFinishPromptPending and not a.result then pending=true; break end
    end
    if not pending then return end
    if GambleDamageRace and GambleDamageRace:InCombat() then return end
    StaticPopupDialogs.GAMBLE_RANK_FINISH=StaticPopupDialogs.GAMBLE_RANK_FINISH or {
        text="Boss-Damage-Serie jetzt beenden und den Pot verteilen?\n\n%s",
        button1="Beenden & auswerten",button2="Weiterspielen",
        OnAccept=function(_,a) B:AnswerFinish(main,a,true) end,
        OnCancel=function(_,a) B:AnswerFinish(main,a,false) end,
        OnHide=function() B.promptedWager=nil end,
        timeout=0,whileDead=true,hideOnEscape=false,preferredIndex=3,
    }
    for _,a in ipairs(main:GetDamageRaceWagers()) do
        if a.mode=="BOSS_DAMAGE_SERIES" and a.rankFinishPromptPending and not a.result and main:IsRankHost(a)
            and not self.jobs[a.id] and not a.rankPendingEncounter then
            self.promptedWager=a
            if not StaticPopup_Show("GAMBLE_RANK_FINISH",self:RemainingText(a),nil,a) then self.promptedWager=nil end
            return
        end
    end
end
-- Only ephemeral prediction/UI caches are discarded. Wagers, payments and ledger remain intact.
function B:Cleanup(main)
    local function live(id)
        for _,a in ipairs(main:GetDamageRaceWagers()) do
            if a.id==id then return not a.result end
        end
        return false
    end
    for key in pairs(self.drafts) do
        if not live(key:match("^(.*):%d+$")) then self.drafts[key]=nil end
    end
    for _,cache in ipairs({self.targetSent or {},self.targetBroadcast or {}}) do
        for key in pairs(cache) do if not live(key:match("^(.*):%d+$")) then cache[key]=nil end end
    end
    for id in pairs(self.jobs) do if not live(id) then self.jobs[id]=nil end end
    if self.bossPick and not live(self.bossPick.wager.id) then
        if self.bossPickFrame then self.bossPickFrame:Hide() end
        self.bossPick=nil; self.targetShown=nil
    end
    if self.promptedWager and not live(self.promptedWager.id) then self:DismissFinish(self.promptedWager) end
end
function B:Encounter(main,event,id,name,success)
    if not TargetReadable(id) or type(id)~="number" then return end
    if event=="ENCOUNTER_START" then
        for _,a in ipairs(main:GetDamageRaceWagers()) do
            if a.mode=="BOSS_DAMAGE_SERIES" and not a.result then
                for index,boss in ipairs(a.bosses) do
                    if boss.encounterID==id or self:BossTargetIndex(a,name)==index then self:LockBossPick(a,index) end
                end
            end
        end
    end
    for _,a in ipairs(main:GetDamageRaceWagers()) do
        if a.mode=="BOSS_DAMAGE_SERIES" and a.awaitingStart==false and not a.result and main:IsRankHost(a) then
            local index=self:BossTargetIndex(a,name)
            for i,boss in ipairs(a.bosses) do
                if boss.encounterID==id or (a.rankEncounterIDs or {})[i]==id then index=i; break end
            end
            local previous=self.jobs[a.id]
            if event=="ENCOUNTER_END" and previous and previous.encounterID==id then index=previous.index end
            if index and not (a.rankResults or {})[index] then
                if event=="ENCOUNTER_START" then
                    self:PauseFinish(a)
                    a.locked=true
                    a.currentSeriesBoss=index
                    a.rankPendingEncounter={index=index,encounterID=id}
                    a.rankEncounterIDs=a.rankEncounterIDs or {}; a.rankEncounterIDs[index]=id
                    -- Current-session reads after the encounter exclude trash and
                    -- earlier bosses. No arithmetic on in-combat secret values.
                    self.jobs[a.id]={wager=a,index=index,encounterID=id,name=a.bosses[index].name,aliases=a.bosses[index].aliases,startedAt=GetTime(),sessionsBefore=self.knownSessions or self:SessionIDs()}
                    main:SendRankMessage("RANK_LOCK",a.id,index)
                    main:SaveRankState()
                else
                    local job=self.jobs[a.id]
                    if job and job.encounterID==id then
                        if success~=1 then
                            self.jobs[a.id]=nil; a.rankPendingEncounter=nil; a.currentSeriesBoss=nil
                            main:SendRankMessage("RANK_WIPE",a.id,index)
                            main:SaveRankState() -- wipe: retry the boss
                        else job.finished=true; job.endedAt=GetTime(); job.deadline=GetTime()+45 end
                    end
                end
                main:Refresh()
            elseif event=="ENCOUNTER_END" and success==1 and not index then
                if main:IsRankEndBoss(a,id,name) then a.rankEndBossKilled=true end
                if a.rankEndBossKilled then self:PromptFinish(main,a) end
            end
        end
    end
end
local function Readable(value)
    return not (canaccessvalue and not canaccessvalue(value)) and not (issecretvalue and issecretvalue(value))
end
function B:FindSession(job)
    if not C_DamageMeter or not C_DamageMeter.GetAvailableCombatSessions then return nil end
    local ok,sessions=pcall(C_DamageMeter.GetAvailableCombatSessions)
    if not ok or not Readable(sessions) or type(sessions)~="table" then return nil end
    local candidate
    for _,session in ipairs(sessions) do
        if Readable(session) and Readable(session.name) and Readable(session.sessionID)
            and type(session.name)=="string" and type(session.sessionID)=="number" then
            local matches=self:BossTargetIndex({bosses={{name=job.name,aliases=job.aliases}}},session.name)==1
            if matches and not (job.sessionsBefore or {})[session.sessionID] then
                if candidate then return nil,"Multiple new segments match this boss; refusing an ambiguous damage result." end
                candidate=session.sessionID
            end
        end
    end
    return candidate
end
function B:DebugMeter(main,offset)
    local function safe(value)
        if not Readable(value) then return "<geschuetzt>" end
        return tostring(value)
    end
    local function log(message)
        if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("Gamble MeterDebug: "..message) end
    end
    if not C_DamageMeter or not C_DamageMeter.GetAvailableCombatSessions then log("Segment-API fehlt."); return end
    local ok,sessions=pcall(C_DamageMeter.GetAvailableCombatSessions)
    if not ok then log("Segment-Abfrage fehlgeschlagen: "..safe(sessions)); return end
    if not Readable(sessions) or type(sessions)~="table" then log("Segmentliste geschuetzt oder nicht verfuegbar."); return end
    local a=main:GetDamageRaceSelection()
    local count=0; for _ in ipairs(sessions) do count=count+1 end
    offset=math.max(1,math.floor(tonumber(offset) or 1))
    log("Segmente="..count..", Anzeige ab "..offset..", aktive Wette="..safe(a and a.id)..". Ausserhalb von Gruppenkampf testen.")
    for i=offset,math.min(count,offset+7) do
        local session=sessions[i]
        if not Readable(session) or type(session)~="table" then log(i..": Segment geschuetzt/ungueltig.")
        else
            local id,name=session.sessionID,session.name
            local matched=false
            if a and Readable(name) and type(name)=="string" then matched=self:BossTargetIndex(a,name)~=nil end
            log(i..": ID="..safe(id)..", Name="..safe(name)..", passt zu Boss="..tostring(matched))
            if a and Readable(id) and type(id)=="number" and GambleDamageRace then
                local readOK,totals,reason=pcall(GambleDamageRace.ReadNative,GambleDamageRace,a.snapshot,nil,id)
                if not readOK then log("  Schaden: API-Fehler "..safe(totals))
                elseif totals then
                    local players=0; for _ in pairs(totals) do players=players+1 end
                    log("  Schaden lesbar: "..players.." Spieler.")
                else log("  Schaden nicht lesbar: "..safe(reason)) end
            else log("  Keine Schadensprobe (Wette oder lesbare Segment-ID fehlt).") end
        end
    end
    if offset+8<=count then log("Weitere: /gamble debugmeter "..(offset+8)) end
end
function B:SessionIDs()
    local ids={}
    if not C_DamageMeter or not C_DamageMeter.GetAvailableCombatSessions then return ids end
    local ok,sessions=pcall(C_DamageMeter.GetAvailableCombatSessions)
    if ok and Readable(sessions) and type(sessions)=="table" then
        for _,session in ipairs(sessions) do
            if Readable(session) and Readable(session.sessionID) and type(session.sessionID)=="number" then ids[session.sessionID]=true end
        end
    end
    return ids
end
local frame=CreateFrame("Frame")
frame:RegisterEvent("ENCOUNTER_START"); frame:RegisterEvent("ENCOUNTER_END")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("UNIT_TARGET"); frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("UNIT_FLAGS")
pcall(frame.RegisterEvent,frame,"DAMAGE_METER_RESET")
frame:SetScript("OnEvent",function(_,event,id,name,_,_,success)
    if event=="UNIT_TARGET" or event=="PLAYER_TARGET_CHANGED" or event=="UNIT_FLAGS" then
        if B.main then B:ScanBossTargets(B.main) end
        if B.debugBoss and event=="PLAYER_TARGET_CHANGED" then B:DebugBossTarget(B.main,event) end
        return
    end
    if event=="PLAYER_LOGIN" and C_Timer then
        C_Timer.After(1,function()
            if not B.main then return end
            for _,a in ipairs(B.main:GetDamageRaceWagers()) do
                if a.mode=="BOSS_DAMAGE_SERIES" and a.rankPendingEncounter and not a.result and B.main:IsRankHost(a) then
                    B.main:FinishRankDamage(a,true,"Boss damage measurement was interrupted by a reload. Stakes will be refunded.")
                end
            end
        end)
        return
    end
    if event=="DAMAGE_METER_RESET" and B.main then
        for _,a in ipairs(B.main:GetDamageRaceWagers()) do
            if a.mode=="BOSS_DAMAGE_SERIES" and a.awaitingStart==false and not a.result and B.main:IsRankHost(a) then
                B.main:FinishRankDamage(a,true,"Damage Meter was reset during Boss Damage Series.")
            end
        end
        return
    end
    if B.main then B:Encounter(B.main,event,id,name,success) end
end)
local elapsed,maintenanceElapsed=0,0
frame:SetScript("OnUpdate",function(_,dt)
    elapsed=elapsed+(dt or 0)
    if elapsed<.1 then return end; elapsed=0
    if B.queue and #B.queue>0 then table.remove(B.queue,1)() end
    if not B.main then return end
    maintenanceElapsed=maintenanceElapsed+.1
    for id,job in pairs(B.jobs) do
        if job.wager.result then B.jobs[id]=nil
        elseif job.finished then
            if not GambleDamageRace:InCombat() then
                local sessionReason
                if not job.sessionID then job.sessionID,sessionReason=B:FindSession(job) end
                local totals,reason
                if job.sessionID then totals,reason=GambleDamageRace:ReadNative(job.wager.snapshot,nil,job.sessionID)
                else reason=sessionReason or "The boss damage session could not be identified reliably." end
                if totals then
                    B.jobs[id]=nil
                    B.main:RecordBossDamage(job.wager,job.index,B:Ranking(totals))
                elseif GetTime()>=job.deadline then
                    B.jobs[id]=nil; B.main:RecordBossDamage(job.wager,job.index,{},reason or "Boss damage was unavailable.")
                end
            end
        end
    end
    if maintenanceElapsed>=1 then
        maintenanceElapsed=0
        B:Cleanup(B.main)
        local armed,hostArmed=false,false
        for _,a in ipairs(B.main:GetDamageRaceWagers()) do
            if a.mode=="BOSS_DAMAGE_SERIES" and a.awaitingStart==false and not a.result then
                armed=true
                if B.main:IsRankHost(a) then hostArmed=true end
            end
        end
        if armed then B:ScanBossTargets(B.main) end
        if hostArmed and GambleDamageRace and not GambleDamageRace:InCombat() then B.knownSessions=B:SessionIDs()
        elseif not hostArmed then B.knownSessions=nil end
        B:ShowFinishPrompts(B.main)
    end
end)
