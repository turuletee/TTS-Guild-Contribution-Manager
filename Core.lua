-- TTS Bank Tracker (Three Tank Strat)
-- Tracks guild bank contributions on a weekly cycle (Tue 10:00 PST -> Tue 09:59 PST)

local TTSBT = LibStub("AceAddon-3.0"):NewAddon("TTSBankTracker", "AceConsole-3.0", "AceEvent-3.0")
_G.TTSBT = TTSBT -- expose for in-game debugging via /dump TTSBT

local defaults = {
    profile = {
        minContribution = 0,    -- gold required per tracked player per week
        trackedPlayers = {},    -- [playerName] = true
        weeklyHistory = {},     -- [weekStartTimestamp] = { [playerName] = copperContributed }
        installTime = 0,        -- set on first run, used to bound how far back the user can pick week 1
        -- firstWeekStart: timestamp of the user-chosen "week 1" Tuesday. Absent until configured.
    },
}

function TTSBT:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("TTSBankTrackerDB", defaults, true)
    if (self.db.profile.installTime or 0) == 0 then
        self.db.profile.installTime = time()
    end
    self:RegisterChatCommand("ttsbt", "HandleSlashCommand")
    self:Print("loaded. Type /ttsbt for commands.")
end

function TTSBT:OnEnable()
    -- Event registrations will go here as features come online
end

function TTSBT:HandleSlashCommand(input)
    input = (input or ""):trim()
    local cmd = input:match("^(%S+)") or ""
    if input == "" then
        self:Print("commands: |cffffff00/ttsbt status|r, |cffffff00/ttsbt week|r")
        return
    end
    if cmd == "status" then
        self:Print("addon is alive. Tracked players: " .. self:CountTrackedPlayers())
    elseif cmd == "week" then
        self:PrintWeekInfo()
    else
        self:Print("unknown command: " .. input)
    end
end

function TTSBT:CountTrackedPlayers()
    local n = 0
    for _ in pairs(self.db.profile.trackedPlayers) do n = n + 1 end
    return n
end

-- Helper for sanity-checking the WeekEngine math from in-game.
function TTSBT:PrintWeekInfo()
    local W = self.WeekEngine
    local now = time()
    local currentStart = W:GetCurrentWeekStart()
    local currentEnd = W:GetWeekEnd(currentStart)
    self:Print("|cffffff00Current week|r")
    self:Print("  start: " .. W:FormatWeek(currentStart))
    self:Print("  end:   " .. date("!%Y-%m-%d %I:%M %p PST", (currentEnd + 1) - 8 * 3600) .. " (exclusive)")
    self:Print("  now:   " .. date("!%Y-%m-%d %I:%M %p PST", now - 8 * 3600))
    if self.db.profile.firstWeekStart then
        local idx = W:GetWeekIndex(currentStart, self.db.profile.firstWeekStart)
        self:Print("  index: week " .. idx .. " (since first tracked week)")
    else
        self:Print("  first tracked week not set yet")
    end
    self:Print("  install: " .. date("!%Y-%m-%d %I:%M %p PST", self.db.profile.installTime - 8 * 3600))
end
