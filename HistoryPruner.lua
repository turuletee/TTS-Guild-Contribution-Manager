-- TTS Guild Contribution Manager - HistoryPruner
-- Removes old weekly history entries that are no longer needed.
--
-- Retention rules (from the user spec, updated 0.5.0):
--
--   1. Always keep the current week and the previous 4 weeks (so the
--      most recent 5 weeks total are never deleted). The user can edit
--      any of these weeks' minimums and per-player marks via the
--      Past Weeks UI.
--
--   2. A week W older than that 5-week window may be deleted ONLY when
--      no tracked player still has an unpaid balance for it. If anyone
--      still owes for that week, it's preserved indefinitely so the
--      compounding 1.5x penalty math keeps working.
--
-- Pruning runs:
--   - At addon load (in Core:OnEnable)
--   - On demand via /gcm prune

local TTSGCM = LibStub("AceAddon-3.0"):GetAddon("TTSGuildContributionManager")

local HistoryPruner = {}
TTSGCM.HistoryPruner = HistoryPruner

local RETENTION_WEEKS = 5

-- Returns a list of week start timestamps that are eligible to be deleted
-- right now (without actually deleting them). Useful for previewing.
function HistoryPruner:GetEligibleWeeks()
    local W = TTSGCM.WeekEngine
    local D = TTSGCM.DebtEngine
    local hist = TTSGCM.db.profile.weeklyHistory
    local currentWeek = W:GetCurrentWeekStart()
    -- Anything strictly older than (current - (RETENTION_WEEKS - 1))
    -- is candidate. e.g. with RETENTION_WEEKS=5, weeks N, N-1, N-2,
    -- N-3, N-4 are kept; N-5 and older are eligible if no debt.
    local oldestKept = W:AddWeeks(currentWeek, -(RETENTION_WEEKS - 1))

    local eligible = {}
    for weekStart in pairs(hist) do
        if weekStart < oldestKept then
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

-- Public so the UI can ask "what weeks are visible to the user?"
function HistoryPruner:RetentionWeeks()
    return RETENTION_WEEKS
end

-- Returns the list of week starts the user can browse in the Past
-- Weeks view: the last RETENTION_WEEKS weeks (current + previous 4),
-- plus any older weeks that still carry an unpaid balance.
function HistoryPruner:GetVisibleWeeks()
    local W = TTSGCM.WeekEngine
    local D = TTSGCM.DebtEngine
    local hist = TTSGCM.db.profile.weeklyHistory
    local currentWeek = W:GetCurrentWeekStart()
    local oldestStandard = W:AddWeeks(currentWeek, -(RETENTION_WEEKS - 1))

    local set = {}
    -- Always include the current week and the previous (RETENTION_WEEKS - 1)
    -- weeks even if they have no entries yet.
    for i = 0, RETENTION_WEEKS - 1 do
        set[W:AddWeeks(currentWeek, -i)] = true
    end
    -- Then any older week with debt or any explicit entry in history.
    for weekStart in pairs(hist) do
        if weekStart < oldestStandard and D:HasOutstandingDebt(weekStart) then
            set[weekStart] = true
        end
    end

    local out = {}
    for ws in pairs(set) do table.insert(out, ws) end
    table.sort(out, function(a, b) return a > b end)  -- newest first
    return out
end
