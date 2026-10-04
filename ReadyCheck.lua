-- Shared participant readiness for non-DoN wagers. Payment stays authoritative.
GambleReadyCheck = {}
local Ready=GambleReadyCheck
local CreateFrame = GambleUIStyle and GambleUIStyle.CreateFrame or CreateFrame
function Ready:IsPaid(wager,name,same)
    for player,status in pairs(wager.paymentStatus or {}) do
        if same(player,name) then return status=="PAID" end
    end
    for _,bet in pairs(wager.bets or {}) do if same(bet.bettor,name) then return true end end
    return false
end
function Ready:IsReady(wager,name,same)
    if not self:IsPaid(wager,name,same) then return false end
    if same(wager.host,name) then return true end
    for player,value in pairs(wager.readyStatus or {}) do if same(player,name) then return value==true end end
    return false
end
function Ready:CountReady(wager,same)
    local names,count={},0
    for _,bet in pairs(wager.bets or {}) do
        local duplicate=false
        for _,name in ipairs(names) do if same(name,bet.bettor) then duplicate=true; break end end
        if not duplicate then
            names[#names+1]=bet.bettor
            if self:IsReady(wager,bet.bettor,same) then count=count+1 end
        end
    end
    return count
end
function Ready:Set(wager,name,value,same)
    if wager.locked or wager.awaitingStart == false or wager.result or same(wager.host,name) then return false end
    if not self:IsPaid(wager,name,same) then value=false end
    wager.readyStatus=wager.readyStatus or {}
    for player in pairs(wager.readyStatus) do if same(player,name) then wager.readyStatus[player]=nil end end
    wager.readyStatus[name]=value==true
    return true
end
function Ready:Render(main,wager,visible,same,me,send)
    if not self.scroll then
        local scroll=CreateFrame("Frame",nil,main.frame)
        scroll:SetPoint("TOPLEFT",18,-484); scroll:SetPoint("BOTTOMRIGHT",-38,44)
        local content=CreateFrame("Frame",nil,scroll); content:SetSize(450,1); content:SetPoint("TOPLEFT")
        self.scroll,self.content,self.rows=scroll,content,{}
        local toggle=CreateFrame("Button",nil,main.frame,"UIPanelButtonTemplate")
        toggle:SetSize(120,24); toggle:SetPoint("TOPLEFT",250,-452)
        toggle:SetScript("OnClick",function()
            local a=Ready.wager
            if not a or not Ready:IsPaid(a,Ready.me,Ready.same) or a.locked or a.result then return end
            Ready.send("BET_READY",a.id,Ready:IsReady(a,Ready.me,Ready.same) and 0 or 1)
        end)
        self.toggle=toggle
    end
    self.wager,self.me,self.same,self.send=wager,me,same,send
    main.frame:SetHeight(600)
    self.scroll:SetShown(visible and wager~=nil)
    self.toggle:Hide()
    if not visible or not wager then return end
    for _,row in ipairs(self.rows) do row:Hide() end
    local names={}
    local function add(name)
        if not name then return end
        for _,other in ipairs(names) do if same(other,name) then return end end
        names[#names+1]=name
    end
    add(wager.host)
    for _,bet in pairs(wager.bets or {}) do add(bet.bettor) end
    for name,status in pairs(wager.paymentStatus or {}) do if status~="CANCELLED" then add(name) end end
    table.sort(names,function(a,b) if a==b then return false elseif same(a,wager.host) then return true elseif same(b,wager.host) then return false else return a<b end end)
    for index,name in ipairs(names) do
        local row=self.rows[index]
        if not row then
            row=CreateFrame("Frame",nil,self.content,"BackdropTemplate")
            row:SetSize(450,36)
            row:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background-Dark",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=8})
            if GambleUIStyle then GambleUIStyle:Row(row) end
            row.name=row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); row.name:SetPoint("TOPLEFT",8,-5)
            row.payment=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.payment:SetPoint("CENTER",0,0); row.payment:SetJustifyH("CENTER")
            row.ready=row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); row.ready:SetPoint("RIGHT",-8,0)
            self.rows[index]=row
        end
        local paid=self:IsPaid(wager,name,same)
        row:SetPoint("TOPLEFT",0,-((index-1)*38))
        row.name:SetText((name:match("^([^%-]+)") or name)..(same(name,wager.host) and " (Bank)" or ""))
        row.payment:SetText(paid and "|cff55ff55PAID|r" or "|cffff5555NOT PAID|r")
        row.ready:SetText(self:IsReady(wager,name,same) and "|cff55ff55READY|r" or "|cffffcc55NOT READY|r")
        row:Show()
    end
    self.content:SetHeight(math.max(1,#names*38))
    main.frame:SetHeight(600+math.max(0,#names*38-72))
    local involved=false; for _,name in ipairs(names) do if same(name,me) then involved=true end end
    if involved and not same(wager.host,me) and not wager.locked and wager.awaitingStart ~= false and not wager.result then
        self.toggle:SetText(self:IsReady(wager,me,same) and "Not Ready" or "Ready")
        self.toggle:SetEnabled(self:IsPaid(wager,me,same)); self.toggle:Show()
    end
end
