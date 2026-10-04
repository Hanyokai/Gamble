-- Scoped styling: never modify Blizzard's global frame factory or templates.
GambleUIStyle = {}
local Style = GambleUIStyle
local NativeCreateFrame = CreateFrame
local function Outline(owner)
    local border=NativeCreateFrame("Frame",nil,owner,"BackdropTemplate")
    border:SetFrameLevel(owner:GetFrameLevel())
    border:SetAllPoints(owner)
    border:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12,insets={left=3,right=3,top=3,bottom=3}})
    border:SetBackdropColor(.08,.08,.08,.98)
    border:SetBackdropBorderColor(.38,.38,.38,1)
    local elapsed,lastState=0,nil
    local function updateBorder()
        local hover=owner:IsMouseOver() and (not owner.gambleStyled or owner:IsEnabled())
        local selected=owner.selection and owner.selection:IsShown()
        local active=owner.gambleStyled and owner:IsEnabled()
        local rank=owner.gambleRankPlace
        local state=(selected and "selected" or active and (hover and "activeHover" or "active") or hover and "hover" or "idle")..":"..tostring(rank or "")
        if state==lastState then return end
        lastState=state
        if rank==1 then border:SetBackdropBorderColor(.2,1,.2,1)
        elseif rank==2 then border:SetBackdropBorderColor(1,.85,.1,1)
        elseif rank==3 then border:SetBackdropBorderColor(1,.2,.2,1)
        elseif selected then border:SetBackdropBorderColor(.2,1,.2,1)
        elseif active or hover then border:SetBackdropBorderColor(1,.68,.05,1)
        else border:SetBackdropBorderColor(.38,.38,.38,1) end
        if active then border:SetBackdropColor(hover and .55 or .38,.025,.025,.98)
        else border:SetBackdropColor(.08,.08,.08,.98) end
    end
    -- Disabled buttons do not reliably fire OnEnter. Only visible borders poll.
    border:SetScript("OnUpdate",function(_,dt)
        elapsed=elapsed+dt; if elapsed<.1 then return end; elapsed=0
        updateBorder()
    end)
    border.UpdateStyle=updateBorder
    updateBorder()
    return border
end
function Style:Button(button)
    if button.gambleStyled then return end
    button.gambleStyled=true
    for _,key in ipairs({"Left","Middle","Right"}) do if button[key] then button[key]:Hide() end end
    for _,getter in ipairs({"GetNormalTexture","GetPushedTexture","GetDisabledTexture"}) do
        local texture=button[getter] and button[getter](button)
        if texture then texture:SetAlpha(0) end
    end
    local border=Outline(button)
    local function update()
        border.UpdateStyle()
    end
    button:HookScript("OnEnable",update); button:HookScript("OnDisable",update); update()
end
function Style:Row(row)
    if row.gambleRowStyled then return end
    row.gambleRowStyled=true
    if row.SetBackdrop then row:SetBackdrop(nil) end
    Outline(row)
end
function Style.CreateFrame(kind,name,parent,template,...)
    local frame=NativeCreateFrame(kind,name,parent,template,...)
    if kind=="Button" and template and template:find("UIPanelButtonTemplate",1,true) then Style:Button(frame) end
    return frame
end
