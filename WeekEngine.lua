-- TTS Guild Contribution Manager - WeekEngine
-- Pure date math for the weekly cycle.
--
-- A "week" runs from Tuesday 10:00 PST -> the following Tuesday 09:59:59 PST.
-- PST is treated as a fixed UTC-8 offset (no daylight saving). 10:00 PST = 18:00 UTC.
--
-- Implementation: weeks are computed as fixed 7-day intervals offset from a
-- known anchor. This avoids any date-table-to-timestamp conversion (which is
-- awkward in Lua because os.time interprets tables as local time).

local TTSGCM = LibStub("AceAddon-3.0"):GetAddon("TTSGuildContributionManager")

local WeekEngine = {}
TTSGCM.WeekEngine = WeekEngine

-- Anchor: Tuesday 2024-01-02 18:00:00 UTC = Tuesday 2024-01-02 10:00:00 PST.
-- Verified manually: Jan 2 2024 is a Tuesday.
local ANCHOR_WEEK_START = 1704218400
local WEEK_SECONDS = 7 * 24 * 60 * 60  -- 604800
local PST_OFFSET = -8 * 3600           -- PST is UTC-8

WeekEngine.WEEK_SECONDS = WEEK_SECONDS

-- Returns the UNIX timestamp of the start of the week containing `t`.
-- If `t` is omitted, uses the current time.
function WeekEngine:GetWeekStart(t)
    t = t or time()
    local diff = t - ANCHOR_WEEK_START
    if diff >= 0 then
        return ANCHOR_WEEK_START + math.floor(diff / WEEK_SECONDS) * WEEK_SECONDS
    else
        return ANCHOR_WEEK_START - math.ceil(-diff / WEEK_SECONDS) * WEEK_SECONDS
    end
end

function WeekEngine:GetCurrentWeekStart()
    return self:GetWeekStart(time())
end

-- Returns the timestamp of the last second of the week (inclusive end).
function WeekEngine:GetWeekEnd(weekStart)
    return weekStart + WEEK_SECONDS - 1
end

-- Returns a new weekStart shifted by `n` weeks (n can be negative).
function WeekEngine:AddWeeks(weekStart, n)
    return weekStart + n * WEEK_SECONDS
end

-- Number of weeks from `fromWeekStart` to `toWeekStart` (can be negative).
function WeekEngine:WeeksBetween(fromWeekStart, toWeekStart)
    return math.floor((toWeekStart - fromWeekStart) / WEEK_SECONDS)
end

-- 1-indexed week number relative to a chosen first week.
-- firstWeekStart is the start timestamp of the user-configured "week 1".
function WeekEngine:GetWeekIndex(weekStart, firstWeekStart)
    return self:WeeksBetween(firstWeekStart, weekStart) + 1
end

-- Human-readable PST label for a week start timestamp.
-- We format as UTC after applying the PST offset, so the resulting string
-- shows the PST wall clock time.
function WeekEngine:FormatWeek(weekStart)
    return date("!%Y-%m-%d %I:%M %p PST", weekStart + PST_OFFSET)
end

-- Returns the earliest week start the user is allowed to pick as "first week".
-- Bounded to 5 weeks before the addon was installed.
function WeekEngine:GetEarliestSelectableWeek(installTime)
    return self:GetWeekStart(installTime - 5 * WEEK_SECONDS)
end
