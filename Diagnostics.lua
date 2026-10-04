-- Passive diagnostics only. Does not suppress Blizzard warnings or modify
-- protected UI, combat logs, trades, saved variables or addon communications.
GambleDiagnostics = { entries = {} }
local Diag = GambleDiagnostics
local function Print(message)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffff8866Gamble diagnostic:|r " .. message) end
end
function Diag:Report()
    if #self.entries == 0 then Print("No blocked action recorded since this reload."); return end
    for _, entry in ipairs(self.entries) do
        Print(entry.event .. " — addon: " .. entry.addon .. " — function: " .. entry.func .. " — combat: " .. entry.combat)
        for line in tostring(entry.stack or ""):gmatch("[^\r\n]+") do
            if line:find("Gamble/",1,true) and not line:find("Diagnostics.lua",1,true) then Print(line) end
        end
    end
end
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_ACTION_BLOCKED")
frame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, addon, func)
    if event == "PLAYER_LOGIN" then
        if #Diag.entries > 0 and C_Timer then C_Timer.After(1, function() Diag:Report() end) end
        return
    end
    local entry = { event = event, addon = tostring(addon or "?"), func = tostring(func or "?"),
        combat = InCombatLockdown and InCombatLockdown() and "yes" or "no" }
    if debugstack then entry.stack=debugstack(2,20,5) end
    Diag.entries[#Diag.entries + 1] = entry
    if #Diag.entries > 12 then table.remove(Diag.entries, 1) end
    Print(entry.event .. " — addon: " .. entry.addon .. " — function: " .. entry.func .. " — combat: " .. entry.combat)
end)
SLASH_GAMBLEDIAGNOSTICS1 = "/gamblediag"
SlashCmdList.GAMBLEDIAGNOSTICS = function() Diag:Report() end
