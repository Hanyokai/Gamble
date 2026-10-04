-- Offline sandbox. Deliberately never touches saved variables, communications,
-- money APIs, secure trade buttons or live wager state.
GambleTestMode = {}
local Test = GambleTestMode
local CreateFrame = GambleUIStyle and GambleUIStyle.CreateFrame or CreateFrame
Test.modes = { "NEXT_PULL", "NEXT_BOSS", "LAST_MAN_STANDING", "BOSS_HP_WIPE", "PULL_TIMER_DEATH", "TOTAL_DEATHS", "BOSS_SERIES", "ITEM_DROP", "DOUBLE_OR_NOTHING", "DAMAGE_RACE" }
local names = { "TestHost", "TestAlice", "TestBob" }
function Test:Reset(mode, stake, rounds)
    self.mode = mode or self.modes[1]
    self.stake = math.max(1, math.floor(tonumber(stake) or 2))
    self.rounds = math.max(1, math.min(50, math.floor(tonumber(rounds) or 5)))
    self.players = {}
    for i, name in ipairs(names) do self.players[i] = { name=name, joined=i==1, paid=i==1, ready=i==1, points=0, active=true, picks={} } end
    self.viewer, self.round, self.status, self.history, self.payments = 1, 0, "LOBBY", {}, {}
    self.bankRevenue, self.jackpot, self.message = 0, 0, "TEST ONLY: no real gold or group messages."
end
function Test:Pot()
    local pot=0; for _, p in ipairs(self.players) do if p.paid then pot=pot+self.stake end end; return pot
end
function Test:Options()
    if GambleEncounterTracker and GambleEncounterTracker:IsMode(self.mode) then
        local result={}; for _, option in ipairs(GambleEncounterTracker:GetOptions(self.mode)) do result[#result+1]=option.key end; return result
    end
    if self.mode=="ITEM_DROP" then return { "Test Sword", "Test Ring", "Test Shield" } end
    return names
end
function Test:Join()
    if self.status~="LOBBY" then return end
    self.players[self.viewer].joined=true
    self.message="Invitation accepted by "..names[self.viewer]
end
function Test:Pay()
    local p=self.players[self.viewer]
    if self.status=="LOBBY" and p.joined then p.paid=true; self.message="Simulated deposit confirmed: "..p.name end
end
function Test:Pick(value)
    local p=self.players[self.viewer]
    if (self.status~="LOBBY" and not (self.mode=="BOSS_SERIES" and self.status=="RUNNING")) or not p.joined then return end
    if self.mode=="ITEM_DROP" then
        for _, other in ipairs(self.players) do if other~=p and other.pick==value then self.message="Item already assigned."; return end end
    end
    p.pick=value
    p.picks[self.round+1]=value
end
function Test:Start()
    if self.viewer~=1 or self.status~="LOBBY" then return end
    local count=0
    for _, p in ipairs(self.players) do
        if p.joined then
            count=count+1
            if not p.paid or (self.mode=="DOUBLE_OR_NOTHING" and not p.ready) then self.message="Waiting for payment / ready."; return end
        end
    end
    if count<2 then self.message="Join at least one simulated participant."; return end
    self.status, self.round="RUNNING",1
end
function Test:Settle(winners, refund, bank)
    self.payments={}; self.bankRevenue=bank or 0
    local pot=self:Pot()-self.bankRevenue
    if refund then
        for i,p in ipairs(self.players) do if p.paid then self.payments[i]=self.stake end end
        self.message="Refunds pending."
    elseif #winners>0 then
        local share=math.floor(pot/#winners)
        for n,i in ipairs(winners) do self.payments[i]=share+(n==1 and pot-share*#winners or 0) end
        self.message="Winner(s): "; for _,i in ipairs(winners) do self.message=self.message..names[i].." " end
    else self.jackpot=self.jackpot+pot; self.message="No winning prediction. Test jackpot updated." end
    self.status=next(self.payments) and "PAYOUT" or "DONE"
end
function Test:Roll(value)
    local p=self.players[self.viewer]
    if self.status~="RUNNING" or self.mode~="DOUBLE_OR_NOTHING" or not p.joined or not p.active or p.roll then return end
    p.roll=math.max(1,math.min(100,math.floor(tonumber(value) or 75)))
    local active={}
    for i,player in ipairs(self.players) do
        if player.joined and player.active then if not player.roll then return end; active[#active+1]=i end
    end
    for _,i in ipairs(active) do
        local player=self.players[i]
        if self.round<=self.rounds and player.roll>50 then player.points=player.points+1 end
        self.history[#self.history+1]={round=self.round,text=player.name.." rolled "..player.roll}
    end
    if self.round>=self.rounds then
        local high,leaders=-1,{}
        for _,i in ipairs(active) do
            local score=self.round>self.rounds and self.players[i].roll or self.players[i].points
            if score>high then high,leaders=score,{i} elseif score==high then leaders[#leaders+1]=i end
        end
        if #leaders==1 then self:Settle(leaders); return end
        for _,i in ipairs(active) do self.players[i].active=false end
        for _,i in ipairs(leaders) do self.players[i].active=true end
        self.message="Tiebreaker: highest roll wins."
    end
    self.round=self.round+1
    for _,player in ipairs(self.players) do player.roll=nil end
end
function Test:Outcome(value, kill)
    if self.mode=="DAMAGE_RACE" and self.status=="RUNNING" then
        if not kill then
            local p=self.players[self.viewer]
            p.damage=(p.damage or 0)+math.max(0,tonumber(value) or 0)
            self.message="Simulated damage: "..p.name.." — "..p.damage; return
        elseif self.viewer==1 then
            local high,leaders=0,{}
            for _,p in ipairs(self.players) do if (p.damage or 0)>high then high,leaders=p.damage,{p.name} elseif (p.damage or 0)==high and high>0 then leaders[#leaders+1]=p.name end end
            local winners={}
            for i,p in ipairs(self.players) do if p.paid then for _,name in ipairs(leaders) do if p.pick==name then winners[#winners+1]=i; break end end end end
            self:Settle(winners,high==0 or #winners==0); return
        end
    end
    if self.viewer~=1 or self.status~="RUNNING" or self.mode=="DOUBLE_OR_NOTHING" then return end
    local winning=value
    if GambleEncounterTracker and GambleEncounterTracker:IsMode(self.mode) then
        local option=GambleEncounterTracker:GetOption(self.mode,value) or GambleEncounterTracker:OptionForValue(self.mode,tonumber(value))
        winning=option and option.key
        if kill and self.mode=="PULL_TIMER_DEATH" and value=="NO DEATH" then winning="NO_DEATH" end
    end
    local winners={}
    for i,p in ipairs(self.players) do
        if p.paid and p.pick==winning then winners[#winners+1]=i end
    end
    self.history[#self.history+1]={round=self.round,text="Test Boss "..self.round..": "..tostring(value)}
    if self.mode=="BOSS_SERIES" then
        for _,i in ipairs(winners) do self.players[i].points=self.players[i].points+1 end
        if #winners==0 then self.bankRevenue=self.bankRevenue+math.floor(self:Pot()/self.rounds*.2) end
        if self.round<self.rounds then self.round=self.round+1; return end
        local high=-1; winners={}
        for i,p in ipairs(self.players) do if p.paid then
            if p.points>high then high,winners=p.points,{i} elseif p.points==high then winners[#winners+1]=i end
        end end
        self:Settle(winners,false,self.bankRevenue); return
    end
    local refund=(kill and (self.mode=="LAST_MAN_STANDING" or self.mode=="BOSS_HP_WIPE")) or (#winners==0 and self.mode~="ITEM_DROP")
    self:Settle(winners,refund,self.mode=="ITEM_DROP" and #winners==0 and math.floor(self:Pot()*.2) or 0)
end
function Test:PayWinner()
    if self.viewer~=1 or self.status~="PAYOUT" then return end
    self.payments={}; self.status="DONE"; self.message="Simulated settlement confirmed. Result popup closed."
    if self.resultFrame then self.resultFrame:Hide() end
end
function Test:Cancel()
    if self.viewer~=1 or (self.status~="LOBBY" and self.status~="RUNNING") then return end
    self:Settle({},true); self.message="Cancelled. Simulated refunds pending."
end
function Test:Render()
    if not self.frame then return end
    self.view:SetText("Perspective: "..names[self.viewer]..(self.viewer==1 and " (Host)" or " (Participant)"))
    local lines={"TEST SANDBOX — "..self.mode,"Status: "..self.status.." · Round: "..self.round.."/"..self.rounds.." · Test pot: "..self:Pot().." copper",self.message,""}
    for i,p in ipairs(self.players) do
        lines[#lines+1]=p.name.." · "..(p.joined and "JOINED" or "NOT JOINED").." · "..(p.paid and "PAID" or "UNPAID").." · "..(p.ready and "READY" or "NOT READY").." · Points: "..p.points
        lines[#lines+1]="Prediction: "..(p.pick or "none").." · Roll: "..(p.roll or "waiting").." · Payout: "..(self.payments[i] or 0)
    end
    local last
    for _,entry in ipairs(self.history) do if last and last~=entry.round then lines[#lines+1]="" end; last=entry.round; lines[#lines+1]="Round "..entry.round..": "..entry.text end
    self.text:SetText(table.concat(lines,"\n")); self.content:SetHeight(math.max(1,#lines*16))
    self.roll:SetShown(self.mode=="DOUBLE_OR_NOTHING" and self.status=="RUNNING" and self.players[self.viewer].joined and self.players[self.viewer].active and not self.players[self.viewer].roll)
    self.rules:SetText(GambleRules and GambleRules[self.mode] or "")
    if self.status=="PAYOUT" then self.resultText:SetText(self.message.."\nTest payouts only — no real gold."); self.resultFrame:Show() end
end
function Test:Open()
    if not self.frame then
        local f=CreateFrame("Frame","GambleSoloTestFrame",UIParent,"BasicFrameTemplateWithInset")
        self.frame=f; f:SetSize(710,650); f:SetPoint("CENTER"); f:SetClampedToScreen(true); f:SetFrameStrata("DIALOG")
        f.TitleText:SetText("Gamble — SOLO TEST SANDBOX")
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton"); f:SetScript("OnDragStart",f.StartMoving); f:SetScript("OnDragStop",f.StopMovingOrSizing)
        local function button(label,x,y,width,callback)
            local b=CreateFrame("Button",nil,f,"UIPanelButtonTemplate"); b:SetSize(width or 135,26); b:SetPoint("TOPLEFT",x,-y); b:SetText(label)
            b:SetScript("OnClick",function() callback(); Test:Render() end); return b
        end
        local function box(x,y,text)
            local b=CreateFrame("EditBox",nil,f,"InputBoxTemplate"); b:SetSize(110,24); b:SetPoint("TOPLEFT",x,-y); b:SetAutoFocus(false); b:SetText(text); return b
        end
        local modeIndex=1
        button("Next bet type",18,38,135,function() modeIndex=modeIndex%#Test.modes+1; Test:Reset(Test.modes[modeIndex],Test.stakeBox:GetText(),Test.roundBox:GetText()) end)
        self.view=button("Perspective",160,38,240,function() Test.viewer=Test.viewer%#names+1 end)
        button("Reset test",410,38,125,function() Test:Reset(Test.modes[modeIndex],Test.stakeBox:GetText(),Test.roundBox:GetText()); Test.resultFrame:Hide() end)
        button("Rename player",542,38,145,function()
            local name=Test.value:GetText():match("^%s*(.-)%s*$")
            if name=="" then return end
            for i,n in ipairs(names) do if i~=Test.viewer and n==name then Test.message="Test names must be unique."; return end end
            names[Test.viewer]=name; Test.players[Test.viewer].name=name
        end)
        self.stakeBox=box(18,78,"2"); self.roundBox=box(160,78,"5"); self.value=box(410,78,"75")
        local hint=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); hint:SetPoint("TOPLEFT",18,-108); hint:SetText("Stake (copper)    ·    Rounds / series bosses    ·    Outcome / roll value (right)")
        button("Join / invite",18,130,nil,function() Test:Join() end)
        button("Confirm deposit",160,130,nil,function() Test:Pay() end)
        button("Ready / not ready",302,130,160,function() local p=Test.players[Test.viewer]; if p.joined and Test.status=="LOBBY" then p.ready=not p.ready end end)
        button("Start (host)",470,130,180,function() Test:Start() end)
        button("Next prediction",18,162,180,function()
            local opts=Test:Options(); local p=Test.players[Test.viewer]; local index=0
            for i,v in ipairs(opts) do if v==p.pick then index=i end end
            local value=opts[index%#opts+1]; Test:Pick(value); Test.value:SetText(value)
        end)
        self.roll=button("Roll value",206,162,135,function() Test:Roll(Test.value:GetText()) end)
        button("Outcome / wipe",350,162,150,function() Test:Outcome(Test.value:GetText(),false) end)
        button("Boss killed",508,162,142,function() Test:Outcome(Test.value:GetText(),true) end)
        self.rules=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); self.rules:SetPoint("TOPLEFT",18,-200); self.rules:SetPoint("TOPRIGHT",-25,-200); self.rules:SetJustifyH("LEFT")
        local scroll=CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate"); scroll:SetPoint("TOPLEFT",18,-285); scroll:SetPoint("BOTTOMRIGHT",-38,60)
        self.content=CreateFrame("Frame",nil,scroll); self.content:SetSize(640,1); scroll:SetScrollChild(self.content)
        self.text=self.content:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); self.text:SetPoint("TOPLEFT"); self.text:SetWidth(640); self.text:SetJustifyH("LEFT"); self.text:SetJustifyV("TOP")
        button("Confirm settlement",18,605,180,function() Test:PayWinner() end)
        button("Cancel test bet",206,605,155,function() StaticPopup_Show("GAMBLE_TEST_CANCEL") end)
        local result=CreateFrame("Frame",nil,UIParent,"BasicFrameTemplateWithInset"); result:SetSize(440,165); result:SetPoint("CENTER",0,180); result:SetFrameStrata("FULLSCREEN_DIALOG"); result.TitleText:SetText("Gamble — TEST Result")
        self.resultFrame=result; self.resultText=result:CreateFontString(nil,"OVERLAY","GameFontHighlight"); self.resultText:SetPoint("TOPLEFT",18,-45); self.resultText:SetWidth(400)
        result:Hide(); f:HookScript("OnHide",function() result:Hide() end)
        StaticPopupDialogs.GAMBLE_TEST_CANCEL={text="Cancel this simulated bet?",button1="Yes",button2="No",timeout=0,whileDead=true,hideOnEscape=true,OnAccept=function() Test:Cancel(); Test:Render() end}
        self:Reset()
    end
    self.frame:Show(); self:Render()
end
