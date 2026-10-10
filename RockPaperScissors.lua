-- Host-authoritative multiplayer RPS; no combat data, no chat-channel messages.
GambleRPS={}
local R=GambleRPS
local prefix="GambleRPS1"
local game,main,view,incoming,trade
local broadcast
local outgoing,queueHead,sending={},1,false
local pendingBroadcast=false
local syncElapsed,lastSync=0,-10
local invited={}
local labels={R="Rock",P="Paper",S="Scissors"}
local beats={R="S",P="R",S="P"}
local function readable(v) return not (canaccessvalue and not canaccessvalue(v)) and not (issecretvalue and issecretvalue(v)) end
local function key(n) return (tostring(n or ""):match("^[^%- ]+") or ""):lower() end
local function same(a,b) return a and b and key(a)==key(b) end
local function me() local n,r=UnitFullName("player"); return n and (r and r~="" and n.."-"..r or n) or UnitName("player") end
local function host() return game and same(game.host,me()) end
local function printLine(s) if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffd8b65cGamble RPS:|r "..s) end end
local function groupMember(name)
    if same(name,me()) then return true end
    local raid=IsInRaid(); local n=raid and GetNumGroupMembers() or GetNumSubgroupMembers()
    for i=1,n do local unit=(raid and "raid" or "party")..i; local a,b=UnitFullName(unit); if a and same(name,b and b~="" and a.."-"..b or a) then return true end end
    return false
end
local function save()
    GambleRPSDB=GambleRPSDB or {}; GambleRPSDB.characters=GambleRPSDB.characters or {}; GambleRPSDB.characters[me()]=game
end
local function refresh()
    save()
    if R.AnnounceChoices then R:AnnounceChoices() end
    if main and main.Refresh then main:Refresh() end
    if R.RefreshChoicePopup then R:RefreshChoicePopup() end
    if R.RefreshWinnerPopup then R:RefreshWinnerPopup() end
end
local function drain()
    local item=outgoing[queueHead]
    if not item then
        outgoing,queueHead,sending={},1,false
        if pendingBroadcast then pendingBroadcast=false; broadcast() end
        return
    end
    outgoing[queueHead]=false; queueHead=queueHead+1
    pcall(C_ChatInfo.SendAddonMessage,prefix,item.text,item.channel,item.target)
    if C_Timer and C_Timer.After then C_Timer.After(.08,drain) else drain() end
end
local function send(command,target,...)
    local parts={command}; for i=1,select("#",...) do parts[#parts+1]=tostring(select(i,...)):gsub("[\t\r\n]"," ") end
    local text=table.concat(parts,"\t"); if #text>250 then return end
    local channel=target and "WHISPER" or (IsInRaid() and "RAID" or "PARTY")
    if target or IsInGroup() then
        outgoing[#outgoing+1]={text=text,channel=channel,target=target}
        if not sending then sending=true; if C_Timer and C_Timer.After then C_Timer.After(.01,drain) else drain() end end
    end
end
local function own() return game and game.players[key(me())] end
local function players()
    local list={}; if game then for _,p in pairs(game.players) do list[#list+1]=p end end
    table.sort(list,function(a,b) return a.name<b.name end); return list
end
local function pot() local total=0; for _,p in ipairs(players()) do if p.paid then total=total+game.stake end end; return total end
local function short(name) return tostring(name or ""):match("^[^%- ]+") or "" end
local function moneyText(amount)
    amount=math.floor(tonumber(amount) or 0)
    return math.floor(amount/10000).."|TInterface\\MoneyFrame\\UI-GoldIcon:12|t "..math.floor(amount/100)%100 .."|TInterface\\MoneyFrame\\UI-SilverIcon:12|t "..amount%100 .."|TInterface\\MoneyFrame\\UI-CopperIcon:12|t"
end
function R:GetPendingPayment()
    if not game or not host() or not GambleBankSecurity then return end
    for _,payment in ipairs(GambleBankSecurity:GetOpenPayments()) do if payment.wagerID==game.id then return payment end end
end
local function returnToNew()
    if view and view.paymentPopup then view.paymentPopup:Hide() end
    if main and main.uiTab=="RPS_DETAIL" then main.uiTab="NEW"; main.detailWagerID=nil end
end
function R:Finish()
    if not host() or not game or (game.status~="DONE" and game.status~="CANCELLED") then return end
    if self:GetPendingPayment() then printLine("Complete all payouts and refunds first."); return end
    game.status="CLOSED"; returnToNew(); broadcast()
end
function R:SyncSettlement()
    if host() and game and (game.status=="DONE" or game.status=="CANCELLED") and game.stake>0 and not self:GetPendingPayment() then self:Finish() end
end
broadcast=function(target)
    if not host() then return end
    -- Coalesce newer states while a complete snapshot is being transmitted.
    -- At most one 40-player snapshot and one pending refresh are retained.
    if sending then pendingBroadcast=true; refresh(); return end
    game.revision=(game.revision or 0)+1
    send("STATE",target,game.id,game.revision,game.host,game.stake,game.bestOf,game.status,game.round,game.bout,game.winner or "",#players(),game.createdAt or 0,game.generation or 0)
    for _,p in ipairs(players()) do send("PLAYER",target,game.id,game.revision,p.name,p.paid and 1 or 0,p.ready and 1 or 0,p.active and 1 or 0,p.points or 0,p.choice and 1 or 0,p.lastSign or "") end
    send("NOTICE",target,game.id,game.revision,(game.notice or ""):sub(1,165))
    if game.reveal then
        send("REVEAL",target,game.id,game.revision,game.reveal.bout,game.reveal.draw and 1 or 0)
        for name,sign in pairs(game.reveal.choices) do send("REVEAL_PICK",target,game.id,game.revision,name,sign) end
    end
    for _,line in ipairs(game.history or {}) do send("HISTORY",target,game.id,game.revision,line:sub(1,165)) end
    send("END",target,game.id,game.revision); refresh()
end
function R:Survivors(choices)
    local signs,count={},0
    for _,sign in pairs(choices) do if not labels[sign] then return nil end; if not signs[sign] then signs[sign]=true; count=count+1 end end
    if count~=2 then return nil end
    local winner
    for sign in pairs(signs) do if signs[beats[sign]] then winner=sign end end
    local out={}; for name,sign in pairs(choices) do if sign==winner then out[name]=true end end
    return out
end
local function nextBout()
    game.bout=game.bout+1
    for _,p in ipairs(players()) do p.choice=nil; p.chosen=false end
end
local function resolve(cancel)
    if game.stake>0 then
        local obligations={}
        for _,p in ipairs(players()) do
            if cancel and p.paid and not same(p.name,game.host) then obligations[#obligations+1]={name=p.name,amount=game.stake,reason="RPS refund"} end
        end
        if not cancel and not same(game.winner,game.host) then obligations[1]={name=game.winner,amount=pot(),reason="RPS winnings"} end
        local ok=GambleBankSecurity:ResolveWager(game.id,obligations,0,cancel and "RPS_CANCEL" or "RPS_WIN")
        if not ok then printLine("Bank entry failed; the game remains open for review."); return false end
    end
    game.status=cancel and "CANCELLED" or "DONE"; return true
end
local function settleBout()
    local choices={}
    for _,p in ipairs(players()) do if p.active then if not p.choice then return end; choices[p.name]=p.choice end end
    local survivors=R:Survivors(choices)
    game.reveal={bout=game.bout,draw=not survivors,choices=choices}
    for _,p in ipairs(players()) do if p.active then p.lastSign=p.choice end end
    if not survivors then game.notice="Draw — active players choose again."; nextBout(); broadcast(); return end
    local count,winner=0,nil
    for _,p in ipairs(players()) do if p.active then p.active=not not survivors[p.name]; if p.active then count=count+1; winner=p end end end
    if count==1 then
        winner.points=winner.points+1
        game.notice="Round "..game.round..": "..short(winner.name).." wins!"
        game.history=game.history or {}; game.history[#game.history+1]=game.notice
        printLine("|cff55ff55"..game.notice.."|r")
        if winner.points>=math.floor(game.bestOf/2)+1 then
            game.winner=winner.name; resolve(false)
        else game.round=game.round+1; for _,p in ipairs(players()) do p.active=true end; nextBout() end
    else game.notice="Losing signs eliminated — remaining players choose again."; nextBout() end
    broadcast()
end
local function request(command,...)
    if not game then return end
    if host() then R:Request(command,me(),...)
    else
        if command=="PICK" and own() then own().chosen=true end
        send(command,game.host,game.id,...); refresh()
    end
end
function R:Request(command,sender,argument,bout)
    if not host() or not groupMember(sender) then return end
    local p=game.players[key(sender)]
    if command=="JOIN" and game.status=="LOBBY" and not p and #players()<40 then
        game.players[key(sender)]={name=sender,paid=game.stake==0,ready=false,active=true,points=0}; broadcast()
    elseif command=="READY" and game.status=="LOBBY" and p and p.paid then p.ready=argument=="1"; broadcast()
    elseif command=="PICK" and game.status=="RUNNING" and p and p.active and not p.choice and labels[argument] and tonumber(bout)==game.bout then
        p.choice=argument; p.chosen=true; broadcast(); settleBout()
    end
end
function R:Create(stake,bestOf)
    if game and game.status~="CLOSED" then printLine("Finish the open RPS game first."); return end
    stake=math.max(0,math.floor(tonumber(stake) or 0)); bestOf=tonumber(bestOf)
    if not bestOf or bestOf<1 or bestOf>15 or bestOf%2~=1 then printLine("Best of: choose to odd number from 1 to 15, such as 3 or 5."); return end
    local id="RPS-"..time().."-"..math.random(100000,999999)
    if stake>0 then
        if not GambleBankSecurity then printLine("Bank management unavailable."); return end
        local ok,reason=GambleBankSecurity:RegisterWager(id,stake,stake); if not ok then printLine(tostring(reason)); return end
        local paid=GambleBankSecurity:RegisterDeposit(id,me(),stake); if not paid then printLine("The bank's stake could not be recorded."); return end
    end
    GambleRPSDB=GambleRPSDB or {}; GambleRPSDB.generations=GambleRPSDB.generations or {}
    local generation=math.max(time(),(GambleRPSDB.generations[me()] or 0)+1)
    GambleRPSDB.generations[me()]=generation
    game={id=id,createdAt=time(),generation=generation,host=me(),stake=stake,bestOf=bestOf,status="LOBBY",round=1,bout=1,players={},history={},revision=0}
    game.players[key(me())]={name=me(),paid=true,ready=true,active=true,points=0}
    broadcast(); if main then main.uiTab="RPS_DETAIL"; refresh() end
end
function R:Start()
    if not host() or game.status~="LOBBY" then return end
    if #players()<2 then printLine("At least two participants are required."); return end
    for _,p in ipairs(players()) do if not p.ready or not p.paid then printLine("Waiting for all participants to be ready and paid."); return end end
    if game.stake>0 and not GambleBankSecurity:ActivateWager(game.id) then printLine("Bank authorization failed."); return end
    game.status="RUNNING"; game.notice="All active players choose Rock, Paper or Scissors."; broadcast()
end
function R:Cancel()
    if not host() or game.status=="DONE" or game.status=="CANCELLED" or game.status=="CLOSED" then return end
    if trade and not trade.done then printLine("Close the current stake trade before cancelling."); return end
    if resolve(true) then game.notice="Cancelled. Paid stakes will be refunded."; broadcast() end
end
function R:SetMainController(controller) main=controller end
function R:RefreshWinnerPopup()
    if not game or not game.winner or (game.status~="DONE" and game.status~="CLOSED") or not own() then return end
    self.announcedWinners=self.announcedWinners or {}
    if self.announcedWinners[game.id] then return end
    if not self.resultPopup then
        local popup=CreateFrame("Frame","GambleRPSWinnerPopup",UIParent,"BasicFrameTemplateWithInset")
        popup:SetSize(320,170); popup:SetPoint("CENTER",UIParent,"CENTER",0,160); popup:SetFrameStrata("DIALOG")
        popup.TitleText:SetText("Gypsy Gamble - Rock Paper Scissors")
        popup.name=popup:CreateFontString(nil,"OVERLAY","GameFontNormalLarge"); popup.name:SetPoint("TOP",0,-42)
        popup.amount=popup:CreateFontString(nil,"OVERLAY","GameFontHighlight"); popup.amount:SetPoint("TOP",0,-74)
        popup.score=popup:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); popup.score:SetPoint("TOP",0,-98)
        local details=CreateFrame("Button",nil,popup,"UIPanelButtonTemplate")
        details:SetSize(120,24); details:SetPoint("BOTTOM",0,16); details:SetText("View Details")
        details:SetScript("OnClick",function() popup:Hide(); R:ShowDetails() end)
        self.resultPopup=popup
    end
    self.announcedWinners[game.id]=true
    local winner=game.players[key(game.winner)]
    self.resultPopup.name:SetText("|cff55ff55WINNER: "..short(game.winner).."|r")
    self.resultPopup.amount:SetText(game.stake>0 and ("Winnings: "..moneyText(pot())) or "Pussy Mode")
    self.resultPopup.score:SetText((winner and winner.points or 0).." wins · Best of "..game.bestOf)
    self.resultPopup:Show(); self.resultPopup:Raise()
end
function R:AnnounceChoices()
    if not game or not game.reveal or not own() then return end
    local id=game.id..":"..game.reveal.bout
    self.announcedChoices=self.announcedChoices or {}
    if self.announcedChoices[id] then return end
    self.announcedChoices[id]=true
    local names={}; for name in pairs(game.reveal.choices) do names[#names+1]=name end; table.sort(names)
    for _,name in ipairs(names) do printLine(short(name).." chose "..(labels[game.reveal.choices[name]] or "?")) end
    if game.reveal.draw then printLine("|cffffff00Draw — choose again.|r") end
end
function R:RefreshChoicePopup()
    local participant=own()
    if not game or game.status~="RUNNING" or not participant then
        if self.choicePopup then self.choicePopup:Hide() end
        return
    end
    if not main or not main.frame then return end
    if self.choiceGameID~=game.id then
        self.choiceGameID=game.id
        main.frame:Hide()
        self:HideEmbedded()
        if main.CloseAuxiliaryWindows then main:CloseAuxiliaryWindows() end
    end
    if not self.choicePopup then
        local popup=CreateFrame("Frame","GambleRPSChoicePopup",UIParent)
        popup:SetSize(190,108); popup:SetFrameStrata("DIALOG")
        popup:SetMovable(true); popup:SetClampedToScreen(true); popup:RegisterForDrag("LeftButton")
        GambleRPSDB=GambleRPSDB or {}
        local saved=GambleRPSDB.choicePosition
        popup:SetPoint("CENTER",UIParent,"CENTER",saved and saved.x or 0,saved and saved.y or 100)
        popup:SetScript("OnDragStart",function(self) if not GambleRPSDB.choiceLocked then self:StartMoving() end end)
        popup:SetScript("OnDragStop",function(self)
            self:StopMovingOrSizing()
            local x,y=self:GetCenter(); local cx,cy=UIParent:GetCenter()
            if x and y and cx and cy then GambleRPSDB.choicePosition={x=x-cx,y=y-cy} end
        end)
        popup.icons={}
        local icons={S="inv_knife_1h_garrison_a_01",R="inv_ore_tin_01",P="inv_misc_paperbundle02a"}
        for i,sign in ipairs({"S","R","P"}) do
            local b=CreateFrame("Button",nil,popup); b:SetSize(48,48); b:SetPoint("TOPLEFT",(i-1)*60,0)
            b.icon=b:CreateTexture(nil,"ARTWORK"); b.icon:SetAllPoints(); b.icon:SetTexture("Interface\\Icons\\"..icons[sign])
            b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square","ADD")
            b:SetScript("OnClick",function() if game and game.status=="RUNNING" then request("PICK",sign,game.bout) end end)
            b:SetScript("OnEnter",function(self)
                self.icon:SetVertexColor(1,1,.65); self.icon:SetAlpha(1)
                if self:IsEnabled() then self:LockHighlight() end
                if GameTooltip then GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:SetText(labels[sign]); GameTooltip:Show() end
            end)
            b:SetScript("OnLeave",function(self)
                self:UnlockHighlight(); self.icon:SetVertexColor(1,1,1); self.icon:SetAlpha(self:IsEnabled() and 1 or .45)
                if GameTooltip then GameTooltip:Hide() end
            end)
            popup.icons[i]=b
        end
        popup.result=popup:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        popup.result:SetPoint("TOPLEFT",0,-54); popup.result:SetPoint("TOPRIGHT",0,-54); popup.result:SetJustifyH("CENTER")
        local lock=CreateFrame("Button",nil,popup); lock:SetSize(80,18); lock:SetPoint("BOTTOM",0,0)
        lock.text=lock:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); lock.text:SetAllPoints()
        lock:SetScript("OnClick",function() GambleRPSDB.choiceLocked=not GambleRPSDB.choiceLocked; R:RefreshChoicePopup() end)
        popup.lock=lock; self.choicePopup=popup
    end
    local popup=self.choicePopup
    popup:EnableMouse(not GambleRPSDB.choiceLocked)
    popup.lock.text:SetText(GambleRPSDB.choiceLocked and "Unlock" or "Lock")
    local enabled=participant.active and not participant.chosen
    for _,b in ipairs(popup.icons) do b:SetEnabled(not not enabled); b.icon:SetDesaturated(not enabled); b.icon:SetAlpha(enabled and 1 or .45) end
    local history=game.history or {}
    local latest=history[#history]
    local status=participant.chosen and "Waiting for other players..." or (participant.active and "Choose your sign" or "Waiting for this round to finish...")
    local resultText=game.reveal and game.reveal.draw and "|cffffff00Draw — choose again.|r\n" or (latest and ("|cff55ff55"..latest.."|r\n") or "")
    popup.result:SetText(resultText..status)
    popup:Show()
end
function R:HideEmbedded() if view then view:Hide(); if view.paymentPopup then view.paymentPopup:Hide() end end end
function R:RequestSync(force)
    if host() then return end
    local now=GetTime and GetTime() or time()
    if not force and now-lastSync<5 then return end
    lastSync=now
    -- Query the current host, rather than continuing to display a saved snapshot forever.
    send("HELLO",nil)
end
function R:ShowDetails() if main then main.uiTab="RPS_DETAIL"; main.frame:Show(); self:RequestSync(); refresh() end end
function R:ShowInvitation()
    if not game or game.status~="LOBBY" or host() or own() or invited[game.id] then return end
    if GambleDB and GambleDB.settings and GambleDB.settings.autoWagerPopup==false then return end
    if not StaticPopupDialogs or not StaticPopup_Show then return end
    invited[game.id]=true
    StaticPopupDialogs.GAMBLE_RPS_INVITE={text="%s opened Rock Paper Scissors!\nBest of %s\nOpen the lobby?",
        button1="Open Lobby",button2="Later",timeout=0,whileDead=true,hideOnEscape=true,preferredIndex=3,
        OnAccept=function(_,data) if game and game.id==data then R:ShowDetails() end end}
    StaticPopup_Show("GAMBLE_RPS_INVITE",short(game.host),game.bestOf,game.id)
end
function R:GetRunningCard()
    if not game or game.status=="CLOSED" then return end
    return {id=game.id,rps=true,mode="ROCK_PAPER_SCISSORS",host=game.host,createdAt=game.createdAt or 0,minimum=game.stake,locked=game.status~="LOBBY",title="Rock Paper Scissors",context=game.status.." · Best of "..game.bestOf,result=game.status=="DONE" and {name=game.winner} or nil}
end
local function text(parent,label,x,y)
    local f=parent:CreateFontString(nil,"OVERLAY","GameFontHighlight"); f:SetPoint("TOPLEFT",x,y); f:SetText(label); return f
end
local function button(parent,label,x,y,callback,tradeAction)
    local create=GambleUIStyle and GambleUIStyle.CreateFrame or CreateFrame
    local b=create("Button",nil,parent,tradeAction and "UIPanelButtonTemplate,InsecureActionButtonTemplate" or "UIPanelButtonTemplate"); b:SetSize(135,25); b:SetPoint("TOPLEFT",x,y); b:SetText(label); b:SetScript("OnClick",callback); return b
end
function R:RenderEmbedded(controller,config)
    main=controller
    if not view then
        view=CreateFrame("Frame",nil,main.frame); view:SetPoint("TOPLEFT",18,-150); view:SetPoint("BOTTOMRIGHT",-18,38)
        view.heading=text(view,"Rock Paper Scissors",0,0)
        view.rules=text(view,"Everyone chooses secretly. Losing signs are eliminated each round.\nAll three signs or identical choices: choose again.\nBest of: first to a majority of round wins. Stake 0 = free.",0,-190)
        view.rules:SetWidth(465); view.rules:SetJustifyH("LEFT")
        view.config=CreateFrame("Frame",nil,view); view.config:SetAllPoints()
        text(view.config,"Stake per player:",0,-72)
        view.coins={}
        for i=1,3 do local b=CreateFrame("EditBox",nil,view.config,"InputBoxTemplate"); b:SetSize(65,24); b:SetPoint("TOPLEFT",145+(i-1)*95,-68); b:SetAutoFocus(false); b:SetNumeric(true); b:SetText("0"); view.coins[i]=b
            local icon=b:CreateTexture(nil,"ARTWORK"); icon:SetSize(14,14); icon:SetPoint("LEFT",b,"RIGHT",4,0); icon:SetTexture("Interface\\MoneyFrame\\UI-"..({"Gold","Silver","Copper"})[i].."Icon")
        end
        text(view.config,"Best of (1, 3, 5 … 15):",0,-112)
        view.best=CreateFrame("EditBox",nil,view.config,"InputBoxTemplate"); view.best:SetSize(65,24); view.best:SetPoint("TOPLEFT",145,-108); view.best:SetAutoFocus(false); view.best:SetNumeric(true); view.best:SetText("3")
        local createButton=button(view.config,"Create Game",250,-108,function() R:Create((tonumber(view.coins[1]:GetText()) or 0)*10000+(tonumber(view.coins[2]:GetText()) or 0)*100+(tonumber(view.coins[3]:GetText()) or 0),tonumber(view.best:GetText())) end); createButton:SetWidth(190)
        text(view.config,"Empty stake or 0 = free.",0,-35)
        view.play=CreateFrame("Frame",nil,view); view.play:SetAllPoints()
        view.meta=text(view.play,"",0,-90); view.notice=text(view.play,"",0,-125); view.notice:SetWidth(460); view.notice:SetJustifyH("LEFT")
        view.join=button(view.play,"Join",0,-158,function() request("JOIN") end)
        view.ready=button(view.play,"Ready",145,-158,function() request("READY",own() and own().ready and "0" or "1") end)
        view.start=button(view.play,"Start",290,-158,function() R:Start() end)
        view.pay=button(view.play,"Pay Stake",0,-192,function() end,true)
        GambleTradeAction:Attach(view.pay,function() if game and game.status=="LOBBY" and own() and not own().paid then return {name=game.host,prepare=function() printLine("Stake: "..game.stake.." copper. Enter gold manually in the trade.") end} end end,printLine)
        view.cancel=button(view.play,"Cancel",290,-192,function() R:Cancel() end)
        view.cancel:SetText(""); view.cancel:SetSize(28,28)
        local cancelIcon=view.cancel:CreateTexture(nil,"ARTWORK")
        cancelIcon:SetAllPoints(); cancelIcon:SetAtlas("128-RedButton-Delete",false)
        view.cancel:SetScript("OnEnter",function(b) if GameTooltip then GameTooltip:SetOwner(b,"ANCHOR_RIGHT"); GameTooltip:SetText("Cancel Game"); GameTooltip:Show() end end)
        view.cancel:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
        view.payout=button(view.play,"Pay Winner",145,-192,function() end,true)
        GambleTradeAction:Attach(view.payout,function()
            local payment=R:GetPendingPayment()
            if payment and game and (game.status=="DONE" or game.status=="CANCELLED") then
                local grouped=main:GetGroupedPayment(payment.name)
                return {name=payment.name,label=game.status=="CANCELLED" and "Refund" or "Pay Winner",prepare=function() printLine("Payout: "..moneyText(grouped and grouped.amount or payment.amount).." to "..short(payment.name)..". Enter gold manually in the trade.") end}
            end
        end,printLine)
        view.signs={}
        local icons={S="inv_knife_1h_garrison_a_01",R="inv_ore_tin_01",P="inv_misc_paperbundle02a"}
        for i,sign in ipairs({"S","R","P"}) do
            local b=button(view.play,"",(i-1)*60,-230,function() request("PICK",sign,game.bout) end)
            b:SetSize(48,48)
            b.icon=b:CreateTexture(nil,"ARTWORK"); b.icon:SetPoint("TOPLEFT",4,-4); b.icon:SetPoint("BOTTOMRIGHT",-4,4)
            b.icon:SetTexture("Interface\\Icons\\"..icons[sign]); b.sign=sign
            b:SetScript("OnEnter",function(self) if GameTooltip then GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:SetText(labels[sign]); GameTooltip:Show() end end)
            b:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
            view.signs[i]=b
        end
        view.scroll=CreateFrame("ScrollFrame",nil,view.play,"UIPanelScrollFrameTemplate"); view.scroll:SetPoint("TOPLEFT",0,-265); view.scroll:SetPoint("BOTTOMRIGHT",-24,5)
        view.content=CreateFrame("Frame",nil,view.scroll); view.content:SetSize(430,1); view.scroll:SetScrollChild(view.content); view.rows={}
        view.bank=text(view.play,"",0,-30)
        view.history=text(view.content,"",6,0); view.history:SetWidth(425); view.history:SetJustifyH("LEFT")
        view.finish=button(view.play,"Finish Game",0,0,function() R:Finish() end)
        view.paymentToggle=button(view.play,"Show Payments",0,0,function() view.paymentsOpen=not view.paymentsOpen; view.paymentDismissed=true; R:RenderEmbedded(main,false) end)
        local create=GambleUIStyle and GambleUIStyle.CreateFrame or CreateFrame
        view.paymentPopup=create("Frame","GambleRPSPaymentsFrame",UIParent,"BasicFrameTemplateWithInset")
        local popup=view.paymentPopup; popup:SetSize(390,480); popup:SetPoint("TOPRIGHT",main.frame,"TOPLEFT",-8,0); popup:SetFrameStrata("DIALOG"); popup:SetClampedToScreen(true)
        popup:SetMovable(true); popup:EnableMouse(true); popup:RegisterForDrag("LeftButton"); popup:SetScript("OnDragStart",popup.StartMoving); popup:SetScript("OnDragStop",popup.StopMovingOrSizing)
        popup.TitleText:SetText("Rock Paper Scissors - Payments"); text(popup,"Participants and payment status",18,-40)
        local scroll=create("ScrollFrame",nil,popup,"UIPanelScrollFrameTemplate"); scroll:SetPoint("TOPLEFT",14,-66); scroll:SetPoint("BOTTOMRIGHT",-34,50)
        view.paymentContent=CreateFrame("Frame",nil,scroll); view.paymentContent:SetSize(330,1); scroll:SetScrollChild(view.paymentContent); view.paymentRows={}
        view.paymentPot=text(popup,"",18,0); view.paymentPot:ClearAllPoints(); view.paymentPot:SetPoint("BOTTOMLEFT",18,22)
        if popup.CloseButton then popup.CloseButton:SetScript("OnClick",function() view.paymentsOpen=false; view.paymentDismissed=true; popup:Hide(); view.paymentToggle:SetText("Show Payments") end) end
        popup:Hide()
        view.meta:ClearAllPoints(); view.meta:SetPoint("TOPLEFT",0,-55)
        view.notice:ClearAllPoints(); view.notice:SetPoint("BOTTOMLEFT",0,42)
        view.scroll:ClearAllPoints(); view.scroll:SetPoint("TOPLEFT",0,-84); view.scroll:SetPoint("BOTTOMRIGHT",-24,120)
        for _,b in ipairs({view.join,view.ready,view.start,view.pay,view.cancel,view.payout,view.finish}) do b:ClearAllPoints() end
        view.join:SetPoint("BOTTOMLEFT",0,5); view.ready:SetPoint("BOTTOMLEFT",145,5); view.start:SetPoint("BOTTOMRIGHT",-2,5); view.start:SetWidth(210)
        view.pay:SetPoint("BOTTOMLEFT",0,39); view.cancel:SetPoint("BOTTOMRIGHT",-2,-24)
        view.payout:SetPoint("BOTTOMRIGHT",-2,5); view.finish:SetPoint("BOTTOMRIGHT",-2,5)
        view.paymentToggle:ClearAllPoints(); view.paymentToggle:SetPoint("TOPRIGHT",-2,-2); view.paymentToggle:SetWidth(175)
        for i,b in ipairs(view.signs) do b:ClearAllPoints(); b:SetPoint("BOTTOMLEFT",(i-1)*60,76) end
    end
    view:Show(); view.config:SetShown(config); view.play:SetShown(not config)
    view.rules:SetShown(config); main.frame:SetHeight(600)
    view.heading:SetText(config and "Create Rock Paper Scissors" or "Rock Paper Scissors")
    view.heading:SetFontObject("GameFontNormalLarge")
    if config then return end
    if not game then view.meta:SetText("No RPS lobby available."); return end
    local p=own()
    local statusLabels={LOBBY="LOBBY",RUNNING="RUNNING",DONE=R:GetPendingPayment() and "PAYOUT PENDING" or "COMPLETED",CANCELLED="CANCELLED",CLOSED="COMPLETED"}
    view.heading:SetText("Rock Paper Scissors — "..(statusLabels[game.status] or game.status))
    view.bank:SetText("Bank: "..short(game.host))
    view.meta:SetText("Pot: "..moneyText(pot()).."    Stake: "..moneyText(game.stake).."    Best of: "..game.bestOf.."    Round: "..game.round.."    Players: "..#players())
    view.notice:SetText("|cff55ff55"..(game.status=="DONE" and ("WINNER: "..short(game.winner).." — Payout: "..moneyText(pot())) or game.notice or game.status).."|r")
    view.join:SetShown(game.status=="LOBBY" and not p)
    view.ready:SetShown(game.status=="LOBBY" and p~=nil and not host()); view.ready:SetEnabled(p and p.paid or false); view.ready:SetText(p and p.ready and "Not Ready" or "Ready")
    view.start:SetShown(host() and game.status=="LOBBY")
    local canStart=#players()>=2; for _,player in ipairs(players()) do if not player.paid or not player.ready then canStart=false end end
    view.start:SetEnabled(canStart); view.start:SetText(canStart and "Start Game" or "Waiting for Ready & Payment")
    view.cancel:SetShown(host() and (game.status=="LOBBY" or game.status=="RUNNING"))
    local pending=R:GetPendingPayment()
    view.payout:SetShown(pending~=nil and (game.status=="DONE" or game.status=="CANCELLED")); view.payout:SetText(game.status=="CANCELLED" and "Refund" or "Pay Winner")
    view.finish:SetShown(host() and not pending and (game.status=="DONE" or game.status=="CANCELLED"))
    view.pay:SetShown(game.stake>0 and game.status=="LOBBY" and p~=nil and not p.paid)
    GambleTradeAction:Prepare(view.pay); GambleTradeAction:Prepare(view.payout)
    for _,b in ipairs(view.signs) do
        local enabled=p and p.active and not p.chosen or false
        b:SetShown(game.status=="RUNNING"); b:SetEnabled(enabled)
        b.icon:SetDesaturated(not enabled); b.icon:SetAlpha(enabled and 1 or .45)
    end
    for _,row in ipairs(view.rows) do row:Hide() end
    for i,player in ipairs(players()) do
        local row=view.rows[i]; if not row then
            row=CreateFrame("Frame",nil,view.content,"BackdropTemplate"); row:SetSize(438,42)
            row:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=9}); row:SetBackdropColor(.04,.04,.04,.82); row:SetBackdropBorderColor(.35,.28,.12,.9)
            if GambleUIStyle then GambleUIStyle:Row(row) end
            row.name=text(row,"",8,-6); row.amount=text(row,"",8,-24); row.amount:SetFontObject("GameFontHighlightSmall")
            row.state=text(row,"",0,0); row.state:ClearAllPoints(); row.state:SetPoint("TOPRIGHT",-8,-6)
            row.sign=text(row,"",0,0); row.sign:ClearAllPoints(); row.sign:SetPoint("BOTTOMRIGHT",-8,5); row.sign:SetFontObject("GameFontHighlightSmall")
            view.rows[i]=row
        end
        row:SetPoint("TOPLEFT",0,-(i-1)*46); row.name:SetText(short(player.name)..(same(player.name,game.host) and " (Bank)" or ""))
        row.amount:SetText(moneyText(game.stake).." · Wins: "..player.points.."  "..(player.paid and "|cff55ff55PAID|r" or "|cffff5555NOT PAID|r"))
        row.state:SetText(game.status=="LOBBY" and (player.ready and "|cff55ff55READY|r" or "|cffffcc55NOT READY|r") or (player.active and "|cff55ff55ACTIVE|r" or "|cffff5555OUT|r"))
        row.sign:SetText((player.lastSign and (labels[player.lastSign] or "-") or "")..(game.status=="RUNNING" and player.active and (player.chosen and " · chosen" or " · choosing") or "")); row:Show()
    end
    local history={}; for _,line in ipairs(game.history or {}) do history[#history+1]="|cff55ff55"..line.."|r" end
    view.history:ClearAllPoints(); view.history:SetPoint("TOPLEFT",6,-(#players()*46+8)); view.history:SetText(#history>0 and ("|cffffd100Round History|r\n"..table.concat(history,"\n")) or "")
    view.content:SetHeight(math.max(1,#players()*46+(#history>0 and (#history*16+35) or 0)))
    if view.paymentGame~=game.id then view.paymentGame=game.id; view.paymentsOpen=false; view.paymentAutoOpened=false; view.paymentDismissed=false end
    if #players()>1 and not view.paymentAutoOpened and not view.paymentDismissed then view.paymentsOpen=true; view.paymentAutoOpened=true end
    view.paymentToggle:SetText(view.paymentsOpen and "Hide Payments" or "Show Payments"); view.paymentPopup:SetShown(view.paymentsOpen==true)
    for _,row in ipairs(view.paymentRows) do row:Hide() end
    for i,player in ipairs(players()) do
        local row=view.paymentRows[i]; if not row then
            row=CreateFrame("Frame",nil,view.paymentContent,"BackdropTemplate"); row:SetSize(330,48)
            row:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=9}); row:SetBackdropColor(.04,.04,.04,.86); row:SetBackdropBorderColor(.32,.28,.16,.9)
            if GambleUIStyle then GambleUIStyle:Row(row) end
            row.name=text(row,"",9,-8); row.amount=text(row,"",9,-30); row.amount:SetFontObject("GameFontHighlightSmall")
            row.state=text(row,"",0,0); row.state:ClearAllPoints(); row.state:SetPoint("CENTER",0,0)
            view.paymentRows[i]=row
        end
        row:SetPoint("TOPLEFT",0,-(i-1)*52); row.name:SetText(short(player.name)..(same(player.name,game.host) and " (Bank)" or ""))
        row.amount:SetText("Stake: "..moneyText(game.stake)); row.state:SetText(player.paid and "|cff55ff55PAID|r" or "|cffff5555NOT PAID|r"); row:Show()
    end
    view.paymentContent:SetHeight(math.max(1,#players()*52)); view.paymentPot:SetText("Current pot: "..moneyText(pot()))
end
local function receive(message,sender)
    if not readable(message) or not groupMember(sender) or same(sender,me()) then return end
    local p={}; for part in (message.."\t"):gmatch("(.-)\t") do p[#p+1]=part end
    local cmd,id,rev=p[1],p[2],tonumber(p[3])
    if cmd=="HELLO" then if host() then broadcast(sender) end; return end
    if cmd=="JOIN" or cmd=="READY" or cmd=="PICK" then if game and game.id==id then R:Request(cmd,sender,p[3],p[4]) end; return end
    if cmd=="STATE" then
        if not same(sender,p[4]) or not rev or (game and game.id==id and rev<=(game.revision or 0)) then return end
        local createdAt=tonumber(p[12]) or tonumber(tostring(id):match("^RPS%-(%d+)")) or 0
        local generation=tonumber(p[13]) or createdAt
        if game and game.id~=id then
            if same(sender,game.host) then
                local previous=game.generation or tonumber(tostring(game.id):match("^RPS%-(%d+)")) or game.createdAt or 0
                -- A newer lobby from the same host supersedes a stale local game.
                -- Delayed cancellation/closure messages from to older game cannot replace it.
                if generation<previous then return end
                if generation==previous and game.status~="DONE" and game.status~="CANCELLED" and game.status~="CLOSED" then return end
            elseif game.status~="DONE" and game.status~="CANCELLED" and game.status~="CLOSED" then
                -- Do not let a stale game from to absent host hide the current group's lobby.
                if host() or groupMember(game.host) then return end
            end
        end
        local stake,best,round,bout,count=tonumber(p[5]),tonumber(p[6]),tonumber(p[8]),tonumber(p[9]),tonumber(p[11])
        if not stake or stake<0 or not best or best<1 or best>15 or best%2~=1 or not round or not bout or not count or count<1 or count>40 then return end
        incoming={id=id,revision=rev,host=p[4],stake=stake,bestOf=best,status=p[7],round=round,bout=bout,winner=p[10]~="" and p[10] or nil,players={},history={},expected=count,createdAt=createdAt,generation=generation}; return
    end
    if not incoming or incoming.id~=id or incoming.revision~=rev or not same(sender,incoming.host) then return end
    if cmd=="PLAYER" then incoming.players[key(p[4])]={name=p[4],paid=p[5]=="1",ready=p[6]=="1",active=p[7]=="1",points=tonumber(p[8]) or 0,chosen=p[9]=="1",lastSign=labels[p[10]] and p[10] or nil}
    elseif cmd=="NOTICE" then incoming.notice=p[4]
    elseif cmd=="REVEAL" then incoming.reveal={bout=tonumber(p[4]) or 0,draw=p[5]=="1",choices={}}
    elseif cmd=="REVEAL_PICK" then if incoming.reveal and labels[p[5]] then incoming.reveal.choices[p[4]]=p[5] end
    elseif cmd=="HISTORY" then if #incoming.history<15 then incoming.history[#incoming.history+1]=p[4] end
    elseif cmd=="END" then
        local n=0; for _ in pairs(incoming.players) do n=n+1 end
        if n==incoming.expected then game=incoming; incoming=nil; if game.status=="CLOSED" then returnToNew() end; refresh(); R:ShowInvitation() end
    end
end
local function money()
    local fn=C_TradeInfo and C_TradeInfo.GetTargetTradeMoney or GetTargetTradeMoney
    if fn then local ok,v=pcall(fn); if ok and readable(v) and type(v)=="number" then return v end end
end
local function completeTrade()
    if not trade or trade.done or not host() or game.id~=trade.id or game.status~="LOBBY" then return end
    local p=game.players[key(trade.partner)]
    if p and not p.paid and trade.amount==game.stake then
        if GambleBankSecurity:RegisterDeposit(game.id,p.name,game.stake) then trade.done=true; p.paid=true; broadcast() end
    end
end
local frame=CreateFrame("Frame")
for _,event in ipairs({"PLAYER_LOGIN","PLAYER_LOGOUT","PLAYER_ENTERING_WORLD","CHAT_MSG_ADDON","GROUP_ROSTER_UPDATE","TRADE_SHOW","TRADE_MONEY_CHANGED","TRADE_ACCEPT_UPDATE","CHAT_MSG_SYSTEM","UI_INFO_MESSAGE","TRADE_CLOSED"}) do frame:RegisterEvent(event) end
frame:SetScript("OnEvent",function(_,event,...)
    if event=="PLAYER_LOGIN" then
        GambleRPSDB=GambleRPSDB or {}; game=GambleRPSDB.characters and GambleRPSDB.characters[me()]
        C_ChatInfo.RegisterAddonMessagePrefix(prefix)
        if host() then if game.status=="RUNNING" then settleBout() end; broadcast() else send("HELLO",nil) end
        return
    elseif event=="PLAYER_LOGOUT" then save()
    elseif event=="GROUP_ROSTER_UPDATE" or event=="PLAYER_ENTERING_WORLD" then if host() then broadcast() else R:RequestSync() end
    elseif event=="CHAT_MSG_ADDON" then local pre,msg,channel,sender=...; if pre==prefix then receive(msg,sender) end
    elseif event=="TRADE_SHOW" then
        trade=nil
        if host() and game.status=="LOBBY" and game.stake>0 and main and main.uiTab=="RPS_DETAIL" then
            local partner=TradeFrameRecipientNameText and TradeFrameRecipientNameText:GetText()
            if readable(partner) and partner then local p=game.players[key(partner)]; if p and not p.paid then trade={id=game.id,partner=p.name,amount=money()} end end
        end
    elseif event=="TRADE_MONEY_CHANGED" or event=="TRADE_ACCEPT_UPDATE" then if trade then trade.amount=money() or trade.amount end
    elseif event=="CHAT_MSG_SYSTEM" or event=="UI_INFO_MESSAGE" then
        local a,b=...; local msg=event=="UI_INFO_MESSAGE" and b or a
        if ERR_TRADE_COMPLETE and readable(msg) and msg==ERR_TRADE_COMPLETE then completeTrade() end
    elseif event=="TRADE_CLOSED" then local old=trade; if C_Timer then C_Timer.After(1,function() if trade==old then trade=nil end end) end end
end)
frame:SetScript("OnUpdate",function(_,elapsed)
    syncElapsed=syncElapsed+elapsed; if syncElapsed<5 then return end; syncElapsed=0
    if not host() and main and main.frame and ((game and game.status=="RUNNING" and own()) or (main.frame:IsShown() and (main.uiTab=="RPS_DETAIL" or main.uiTab=="RUNNING"))) then R:RequestSync() end
end)
