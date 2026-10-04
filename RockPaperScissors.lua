-- Host-authoritative multiplayer RPS; no combat data, no chat-channel messages.
GambleRPS={}
local R=GambleRPS
local prefix="GambleRPS1"
local game,main,view,incoming,trade
local broadcast
local outgoing,queueHead,sending={},1,false
local pendingBroadcast=false
local labels={R="Stein",P="Papier",S="Schere"}
local beats={R="S",P="R",S="P"}
local function readable(v) return not (canaccessvalue and not canaccessvalue(v)) and not (issecretvalue and issecretvalue(v)) end
local function key(n) return (tostring(n or ""):match("^[^%- ]+") or ""):lower() end
local function same(a,b) return a and b and key(a)==key(b) end
local function me() local n,r=UnitFullName("player"); return n and (r and r~="" and n.."-"..r or n) or UnitName("player") end
local function host() return game and same(game.host,me()) end
local function printLine(s) if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffd8b65cGamble SSP:|r "..s) end end
local function groupMember(name)
    if same(name,me()) then return true end
    local raid=IsInRaid(); local n=raid and GetNumGroupMembers() or GetNumSubgroupMembers()
    for i=1,n do local unit=(raid and "raid" or "party")..i; local a,b=UnitFullName(unit); if a and same(name,b and b~="" and a.."-"..b or a) then return true end end
    return false
end
local function save()
    GambleRPSDB=GambleRPSDB or {}; GambleRPSDB.characters=GambleRPSDB.characters or {}; GambleRPSDB.characters[me()]=game
end
local function refresh() save(); if main and main.Refresh then main:Refresh() end end
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
broadcast=function(target)
    if not host() then return end
    -- Coalesce newer states while a complete snapshot is being transmitted.
    -- At most one 40-player snapshot and one pending refresh are retained.
    if sending then pendingBroadcast=true; refresh(); return end
    game.revision=(game.revision or 0)+1
    send("STATE",target,game.id,game.revision,game.host,game.stake,game.bestOf,game.status,game.round,game.bout,game.winner or "",#players())
    for _,p in ipairs(players()) do send("PLAYER",target,game.id,game.revision,p.name,p.paid and 1 or 0,p.ready and 1 or 0,p.active and 1 or 0,p.points or 0,p.choice and 1 or 0,p.lastSign or "") end
    send("NOTICE",target,game.id,game.revision,(game.notice or ""):sub(1,165))
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
        if not ok then printLine("Bankbuchung fehlgeschlagen; Spiel bleibt zur Prüfung offen."); return false end
    end
    game.status=cancel and "CANCELLED" or "DONE"; return true
end
local function settleBout()
    local choices={}
    for _,p in ipairs(players()) do if p.active then if not p.choice then return end; choices[p.name]=p.choice end end
    local survivors=R:Survivors(choices)
    for _,p in ipairs(players()) do if p.active then p.lastSign=p.choice end end
    if not survivors then game.notice="Unentschieden – aktive Spieler wählen erneut."; nextBout(); broadcast(); return end
    local count,winner=0,nil
    for _,p in ipairs(players()) do if p.active then p.active=not not survivors[p.name]; if p.active then count=count+1; winner=p end end end
    if count==1 then
        winner.points=winner.points+1
        game.notice="Runde "..game.round..": "..key(winner.name).." gewinnt!"
        printLine("|cff55ff55"..game.notice.."|r")
        if winner.points>=math.floor(game.bestOf/2)+1 then
            game.winner=winner.name; resolve(false)
        else game.round=game.round+1; for _,p in ipairs(players()) do p.active=true end; nextBout() end
    else game.notice="Unterlegene Zeichen ausgeschieden – verbleibende Spieler wählen erneut."; nextBout() end
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
    if game and game.status~="DONE" and game.status~="CANCELLED" then printLine("Es gibt bereits ein offenes SSP-Spiel."); return end
    stake=math.max(0,math.floor(tonumber(stake) or 0)); bestOf=tonumber(bestOf)
    if not bestOf or bestOf<1 or bestOf>15 or bestOf%2~=1 then printLine("Best-of: ungerade Zahl von 1 bis 15, z. B. 3 oder 5."); return end
    local id="RPS-"..time().."-"..math.random(100000,999999)
    if stake>0 then
        if not GambleBankSecurity then printLine("Bankverwaltung fehlt."); return end
        local ok,reason=GambleBankSecurity:RegisterWager(id,stake,stake); if not ok then printLine(tostring(reason)); return end
        local paid=GambleBankSecurity:RegisterDeposit(id,me(),stake); if not paid then printLine("Bankeinsatz konnte nicht gebucht werden."); return end
    end
    game={id=id,createdAt=time(),host=me(),stake=stake,bestOf=bestOf,status="LOBBY",round=1,bout=1,players={},revision=0}
    game.players[key(me())]={name=me(),paid=true,ready=true,active=true,points=0}
    broadcast(); if main then main.uiTab="RPS_DETAIL"; refresh() end
end
function R:Start()
    if not host() or game.status~="LOBBY" then return end
    if #players()<2 then printLine("Mindestens zwei Teilnehmer nötig."); return end
    for _,p in ipairs(players()) do if not p.ready or not p.paid then printLine("Warte auf Ready und Einzahlung aller Teilnehmer."); return end end
    if game.stake>0 and not GambleBankSecurity:ActivateWager(game.id) then printLine("Bankfreigabe fehlgeschlagen."); return end
    game.status="RUNNING"; game.notice="Alle aktiven Spieler wählen Schere, Stein oder Papier."; broadcast()
end
function R:Cancel()
    if not host() or game.status=="DONE" or game.status=="CANCELLED" then return end
    if trade and not trade.done then printLine("Erst den laufenden Einsatz-Handel schließen, dann abbrechen."); return end
    if resolve(true) then game.notice="Abgebrochen. Bezahlte Einsätze werden zurückgezahlt."; broadcast() end
end
function R:SetMainController(controller) main=controller end
function R:HideEmbedded() if view then view:Hide() end end
function R:ShowDetails() if main then main.uiTab="RPS_DETAIL"; main.frame:Show(); refresh() end end
function R:GetRunningCard()
    if not game or game.status=="CANCELLED" then return end
    return {id=game.id,rps=true,mode="ROCK_PAPER_SCISSORS",host=game.host,createdAt=game.createdAt or 0,minimum=game.stake,locked=game.status~="LOBBY",title="Schere Stein Papier",context=game.status.." · Best of "..game.bestOf,result=game.status=="DONE" and {name=game.winner} or nil}
end
local function text(parent,label,x,y)
    local f=parent:CreateFontString(nil,"OVERLAY","GameFontHighlight"); f:SetPoint("TOPLEFT",x,y); f:SetText(label); return f
end
local function button(parent,label,x,y,callback)
    local create=GambleUIStyle and GambleUIStyle.CreateFrame or CreateFrame
    local b=create("Button",nil,parent,"UIPanelButtonTemplate"); b:SetSize(135,25); b:SetPoint("TOPLEFT",x,y); b:SetText(label); b:SetScript("OnClick",callback); return b
end
function R:RenderEmbedded(controller,config)
    main=controller
    if not view then
        view=CreateFrame("Frame",nil,main.frame); view:SetPoint("TOPLEFT",18,-150); view:SetPoint("BOTTOMRIGHT",-18,38)
        view.heading=text(view,"Schere Stein Papier",0,0)
        view.rules=text(view,"Alle wählen verdeckt. Unterlegene Zeichen scheiden pro Runde aus.\nDrei Zeichen oder gleiche Auswahl: erneut wählen.\nBest of 3: zuerst 2 Rundensiege. Einsatz 0 = kostenlos.",0,-27)
        view.rules:SetWidth(465); view.rules:SetJustifyH("LEFT")
        view.config=CreateFrame("Frame",nil,view); view.config:SetAllPoints()
        text(view.config,"Einsatz: Gold / Silber / Kupfer",0,-92)
        view.coins={}
        for i=1,3 do local b=CreateFrame("EditBox",nil,view.config,"InputBoxTemplate"); b:SetSize(65,24); b:SetPoint("TOPLEFT",5+(i-1)*85,-116); b:SetAutoFocus(false); b:SetNumeric(true); b:SetText("0"); view.coins[i]=b end
        text(view.config,"Best of (1, 3, 5 … 15):",0,-158)
        view.best=CreateFrame("EditBox",nil,view.config,"InputBoxTemplate"); view.best:SetSize(65,24); view.best:SetPoint("TOPLEFT",230,-153); view.best:SetAutoFocus(false); view.best:SetNumeric(true); view.best:SetText("3")
        button(view.config,"Create Game",0,-200,function() R:Create((tonumber(view.coins[1]:GetText()) or 0)*10000+(tonumber(view.coins[2]:GetText()) or 0)*100+(tonumber(view.coins[3]:GetText()) or 0),tonumber(view.best:GetText())) end)
        view.play=CreateFrame("Frame",nil,view); view.play:SetAllPoints()
        view.meta=text(view.play,"",0,-90); view.notice=text(view.play,"",0,-125); view.notice:SetWidth(460); view.notice:SetJustifyH("LEFT")
        view.join=button(view.play,"Beitreten",0,-158,function() request("JOIN") end)
        view.ready=button(view.play,"Ready",145,-158,function() request("READY",own() and own().ready and "0" or "1") end)
        view.start=button(view.play,"Start",290,-158,function() R:Start() end)
        view.pay=button(view.play,"Einsatz zahlen",0,-192,function() end)
        GambleTradeAction:Attach(view.pay,function() if game and game.status=="LOBBY" and own() and not own().paid then return {name=game.host,prepare=function() printLine("Einsatz: "..game.stake.." Kupfer. Gold im Handel manuell eintragen.") end} end end,printLine)
        view.cancel=button(view.play,"Abbrechen",290,-192,function() R:Cancel() end)
        view.payout=button(view.play,"Offene Zahlungen",145,-192,function() main:PayNext() end)
        view.signs={}
        for i,sign in ipairs({"R","P","S"}) do view.signs[i]=button(view.play,labels[sign],(i-1)*145,-230,function() request("PICK",sign,game.bout) end) end
        view.scroll=CreateFrame("ScrollFrame",nil,view.play,"UIPanelScrollFrameTemplate"); view.scroll:SetPoint("TOPLEFT",0,-265); view.scroll:SetPoint("BOTTOMRIGHT",-24,5)
        view.content=CreateFrame("Frame",nil,view.scroll); view.content:SetSize(430,1); view.scroll:SetScrollChild(view.content); view.rows={}
    end
    view:Show(); view.config:SetShown(config); view.play:SetShown(not config)
    if config then return end
    if not game then view.meta:SetText("Keine SSP-Lobby bekannt."); return end
    local p=own()
    view.meta:SetText("Best of "..game.bestOf.." · Runde "..game.round.." · Pot: "..pot().." Kupfer")
    view.notice:SetText("|cff55ff55"..(game.status=="DONE" and ("GEWINNER: "..tostring(game.winner)) or game.notice or game.status).."|r")
    view.join:SetShown(game.status=="LOBBY" and not p)
    view.ready:SetShown(game.status=="LOBBY" and p~=nil); view.ready:SetEnabled(p and p.paid or false); view.ready:SetText(p and p.ready and "Nicht bereit" or "Ready")
    view.start:SetShown(host() and game.status=="LOBBY")
    view.cancel:SetShown(host() and (game.status=="LOBBY" or game.status=="RUNNING"))
    view.payout:SetShown(host() and game.stake>0 and (game.status=="DONE" or game.status=="CANCELLED"))
    view.pay:SetShown(game.stake>0 and game.status=="LOBBY" and p~=nil and not p.paid)
    for _,b in ipairs(view.signs) do b:SetShown(game.status=="RUNNING"); b:SetEnabled(p and p.active and not p.chosen or false) end
    for _,row in ipairs(view.rows) do row:Hide() end
    for i,player in ipairs(players()) do
        local row=view.rows[i]; if not row then row=text(view.content,"",4,-(i-1)*32); row:SetWidth(425); row:SetJustifyH("LEFT"); view.rows[i]=row end
        row:SetText(key(player.name).." · "..player.points.." Siege · "..(game.stake==0 and "kostenlos" or player.paid and "|cff55ff55PAID|r" or "|cffff5555NOT PAID|r").." · "..(game.status=="LOBBY" and (player.ready and "READY" or "nicht bereit") or player.active and (player.chosen and "gesetzt" or "wählt") or "ausgeschieden")..(player.lastSign and " · zuletzt: "..(labels[player.lastSign] or "-") or "")); row:Show()
    end
    view.content:SetHeight(math.max(1,#players()*32))
end
local function receive(message,sender)
    if not readable(message) or not groupMember(sender) or same(sender,me()) then return end
    local p={}; for part in (message.."\t"):gmatch("(.-)\t") do p[#p+1]=part end
    local cmd,id,rev=p[1],p[2],tonumber(p[3])
    if cmd=="HELLO" then if host() then broadcast(sender) end; return end
    if cmd=="JOIN" or cmd=="READY" or cmd=="PICK" then if game and game.id==id then R:Request(cmd,sender,p[3],p[4]) end; return end
    if cmd=="STATE" then
        if not same(sender,p[4]) or not rev or (game and game.id==id and rev<=(game.revision or 0)) then return end
        if game and game.id~=id and game.status~="DONE" and game.status~="CANCELLED" then return end
        local stake,best,round,bout,count=tonumber(p[5]),tonumber(p[6]),tonumber(p[8]),tonumber(p[9]),tonumber(p[11])
        if not stake or stake<0 or not best or best<1 or best>15 or best%2~=1 or not round or not bout or not count or count<1 or count>40 then return end
        incoming={id=id,revision=rev,host=p[4],stake=stake,bestOf=best,status=p[7],round=round,bout=bout,winner=p[10]~="" and p[10] or nil,players={},expected=count,createdAt=time()}; return
    end
    if not incoming or incoming.id~=id or incoming.revision~=rev or not same(sender,incoming.host) then return end
    if cmd=="PLAYER" then incoming.players[key(p[4])]={name=p[4],paid=p[5]=="1",ready=p[6]=="1",active=p[7]=="1",points=tonumber(p[8]) or 0,chosen=p[9]=="1",lastSign=labels[p[10]] and p[10] or nil}
    elseif cmd=="NOTICE" then incoming.notice=p[4]
    elseif cmd=="END" then
        local n=0; for _ in pairs(incoming.players) do n=n+1 end
        if n==incoming.expected then game=incoming; incoming=nil; refresh() end
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
for _,event in ipairs({"PLAYER_LOGIN","PLAYER_LOGOUT","CHAT_MSG_ADDON","GROUP_ROSTER_UPDATE","TRADE_SHOW","TRADE_MONEY_CHANGED","TRADE_ACCEPT_UPDATE","CHAT_MSG_SYSTEM","UI_INFO_MESSAGE","TRADE_CLOSED"}) do frame:RegisterEvent(event) end
frame:SetScript("OnEvent",function(_,event,...)
    if event=="PLAYER_LOGIN" then
        GambleRPSDB=GambleRPSDB or {}; game=GambleRPSDB.characters and GambleRPSDB.characters[me()]
        C_ChatInfo.RegisterAddonMessagePrefix(prefix)
        if host() then if game.status=="RUNNING" then settleBout() end; broadcast() else send("HELLO",nil) end
        return
    elseif event=="PLAYER_LOGOUT" then save()
    elseif event=="GROUP_ROSTER_UPDATE" then send("HELLO",nil)
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
