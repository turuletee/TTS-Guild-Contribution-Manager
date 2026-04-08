-- TTS Guild Contribution Manager - HistoryPruner
-- Removes old weekly history entries that are no longer needed.
--
-- Retention rules (from the user spec):
--
--   1. Always keep the current week and the previous week, regardless
--      of payment status. So if we are in week N, weeks N and N-1 are
--      never deleted.
--
--   2. A week W can be deleted ONLY when both of these are true:
--        - It is at least 2 weeks in the past (current_week_index - W_index >= 2)
--        - No tracked player still has an unpaid balance for week W
--
--      "No unpaid balance" uses DebtEngine:HasOutstandingDebt, which
--      checks if any currently-tracked player owes anything for week W.
--
-- Pruning runs:
--   - On PLAYER_LOGIN
--   - When the current week rolls over (detected on the next bank scan
--     or any /gcm command since the addon doesn't persistently know
--     when a Tuesday boundary crossed)

local TTSGCM = LibStub("AceAddon-3.0"):GetAddon("TTSGuildContributionManager")

local HistoryPruner = {}
TTSGCM.HistoryPruner = HistoryPruner

-- Returns a list of week start timestamps that are eligible to be deleted
-- right now (without actually deleting them). Useful for previewing.
function HistoryPruner:GetEligibleWeeks()
    local W = TTSGCM.WeekEngine
    local D = TTSGCM.DebtEngine
    local hist = TTSGCM.db.profile.weeklyHistory
    local currentWeek = W:GetCurrentWeekStart()
    local previousWeek = W:AddWeeks(currentWeek, -1)

    local eligible = {}
    for weekStart in pairs(hist) do
        if weekStart < previousWeek then
            -- At least 2 weeks back
            if not D:HasOutstandingDebt(weekStart) then
                table.insert(eligible, weekStart)
            end
        end
    end
    table.sort(eligible)
    return eligible
end

-- Deletes eligible weeks. Returns the number deleted.
function HistoryPruner:Prune()
    local hist = TTSGCM.db.profile.weeklyHistory
    local eligible = self:GetEligibleWeeks()
    for _, weekStart in ipairs(eligible) do
        hist[weekStart] = nil
    end
    return #eligible
end
