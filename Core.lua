-- Weekly Contribution Manager
-- Tracks guild bank contributions on a weekly cycle (Tue 10:00 PST -> Tue 09:59 PST)

local addonName, addon = ...

-- Saved variables table (declared in .toc)
WeeklyContributionManagerDB = WeeklyContributionManagerDB or {}

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loaded = ...
        if loaded == addonName then
            print("|cff33ff99Weekly Contribution Manager|r loaded.")
        end
    elseif event == "PLAYER_LOGIN" then
        -- Hook for future init logic
    end
end)
