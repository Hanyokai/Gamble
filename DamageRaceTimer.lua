-- Independent, non-secure countdown. No network traffic or damage API polling.
local _, Gamble = ...
GambleDamageRaceTimer = {}
local Timer = GambleDamageRaceTimer
function Timer:Remaining(wager, now)
    if not wager or wager.mode ~= "DAMAGE_RACE" or not wager.locked or wager.result or not wager.damageEndsAt then return 0 end
    return math.max(0, math.ceil(wager.damageEndsAt - now))
end
local function Settings()
    GambleDB = GambleDB or {}
    GambleDB.damageTimer = GambleDB.damageTimer or {}
    return GambleDB.damageTimer
end
local function CreateTimer()
    local config = Settings()
    local f = CreateFrame("Frame", "GambleDamageRaceTimerFrame", UIParent, "BackdropTemplate")
    f:SetSize(math.max(150,math.min(420,tonumber(config.width) or 180)), math.max(65,math.min(180,tonumber(config.height) or 74))); f:SetFrameStrata("DIALOG")
    f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(150,65,420,180)
    else f:SetMinResize(150,65); f:SetMaxResize(420,180) end
    f:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12})
    if config.x and config.y then f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", config.x, config.y)
    else f:SetPoint("CENTER", UIParent, "CENTER", 0, 180) end
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not Settings().locked then self:StartMoving() end end)
    local function saveGeometry(self)
        self:StopMovingOrSizing()
        local saved=Settings(); saved.x, saved.y=self:GetLeft(),self:GetBottom()
        saved.width,saved.height=self:GetWidth(),self:GetHeight()
        self:ClearAllPoints(); self:SetPoint("BOTTOMLEFT",UIParent,"BOTTOMLEFT",saved.x,saved.y)
    end
    f:SetScript("OnDragStop", saveGeometry)
    f:SetScript("OnHide",saveGeometry)
    local title=f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    title:SetPoint("TOPLEFT",10,-10); title:SetText("Damage Race")
    local count=f:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    count:SetPoint("CENTER",0,-6)
    local font,fontSize,fontFlags=count:GetFont()
    local function resizeText()
        local scale=math.min(f:GetWidth()/180,f:GetHeight()/74)
        count:SetFont(font,fontSize*scale,fontFlags)
    end
    f:SetScript("OnSizeChanged",resizeText); resizeText()
    local grip=CreateFrame("Button",nil,f); grip:SetSize(18,18); grip:SetPoint("BOTTOMRIGHT",-4,4)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown",function(_,button)
        if button=="LeftButton" and not Settings().locked then f:StartSizing("BOTTOMRIGHT") end
    end)
    grip:SetScript("OnMouseUp",function(_,button) if button=="LeftButton" then saveGeometry(f) end end)
    local lock=CreateFrame("Button",nil,f); lock:SetSize(20,20); lock:SetPoint("TOPRIGHT",-8,-6)
    local icon=lock:CreateTexture(nil,"ARTWORK"); icon:SetAllPoints()
    local function updateLock()
        icon:SetTexture(Settings().locked and "Interface\\Buttons\\LockButton-Locked-Up" or "Interface\\Buttons\\LockButton-Unlocked-Up")
        grip:SetShown(not Settings().locked)
        f:SetMovable(not Settings().locked); f:SetResizable(not Settings().locked)
    end
    lock:SetScript("OnClick",function() saveGeometry(f); Settings().locked=not Settings().locked; updateLock() end)
    lock:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP"); GameTooltip:SetText(Settings().locked and "Unlock timer position and size" or "Lock timer position and size"); GameTooltip:Show()
    end)
    lock:SetScript("OnLeave",function() GameTooltip:Hide() end)
    updateLock(); f:Hide()
    Timer.frame,Timer.count=f,count
end
local watcher=CreateFrame("Frame")
local elapsed=0
watcher:SetScript("OnUpdate",function(_,dt)
    elapsed=elapsed+dt; if elapsed<0.2 then return end; elapsed=0
    if type(Gamble) ~= "table" or type(Gamble.GetDamageRaceWagers) ~= "function" then
        if Timer.frame then Timer.frame:Hide() end
        return
    end
    local now=GetServerTime and GetServerTime() or time()
    local selected,remaining
    for _,wager in ipairs(Gamble:GetDamageRaceWagers() or {}) do
        local left=Timer:Remaining(wager,now)
        if left>0 and (not remaining or left<remaining) then selected,remaining=wager,left end
    end
    if not selected then if Timer.frame then Timer.frame:Hide() end; return end
    if not Timer.frame then CreateTimer() end
    Timer.count:SetText(string.format("%02d:%02d",math.floor(remaining/60),remaining%60))
    Timer.frame:Show()
end)
