-- TTS Guild Contribution Manager - AssistanceTracker
--
-- Implements the raid attendance + DKP + fine layer alongside the
-- existing Consumable Contribution layer. The two layers share the
-- tracked-players list (db.profile.trackedPlayers) but otherwise
-- live in completely separate database subtrees:
--
--   db.profile.trackedPlayers       -- shared
--   db.profile.weeklyHistory        -- consumable contribution data
--   db.profile.assistance.*         -- everything in this module
--
-- See `project_ttsgcm_assistance_tracker.md` in memory for the full
-- spec, including the docx rules document and the Excel structure
-- this module is modeled after.
--
-- Status codes (the seven the addon uses internally):
--
--   "ok"                  - on time
--   "late_no_notice"      - late, didn't tell raid leader (-5 DKP, 5000g + escalation)
--   "late_w_notice"       - late, notified ahead          (-5 DKP, no gold)
--   "absent_w_notice"     - absent, notified ahead        (-5 DKP, no gold)
--   "absent_no_notice"    - absent, no notice             (-10 DKP, 10000g)
--   "vacation"            - vacation/holiday              (-10 DKP per WEEK, no gold)
--   "cancelled"           - raid cancelled                (no penalty)

local TTSGCM = LibStub("AceAddon-3.0"):GetAddon("TTSGuildContributionManager")

local AssistanceTracker = {}
TTSGCM.AssistanceTracker = AssistanceTracker

local STATUS = {
    OK                = "ok",
    LATE_NO_NOTICE    = "late_no_notice",
    LATE_W_NOTICE     = "late_w_notice",
    ABSENT_W_NOTICE   = "absent_w_notice",
    ABSENT_NO_NOTICE  = "absent_no_notice",
    VACATION          = "vacation",
    CANCELLED         = "cancelled",
}
AssistanceTracker.STATUS = STATUS

-- Display labels and colors. Used by the UI in branch B.
AssistanceTracker.STATUS_LABELS = {
    [STATUS.OK]                = "OK",
    [STATUS.LATE_NO_NOTICE]    = "LATE (no notice)",
    [STATUS.LATE_W_NOTICE]     = "Late (notified)",
    [STATUS.ABSENT_W_NOTICE]   = "Absent (notified)",
    [STATUS.ABSENT_NO_NOTICE]  = "ABSENT (no notice)",
    [STATUS.VACATION]          = "Vacation",
    [STATUS.CANCELLED]         = "Cancelled",
}

AssistanceTracker.STATUS_COLORS = {
    [STATUS.OK]                = "ff33ff99",  -- green
    [STATUS.LATE_NO_NOTICE]    = "ffff5555",  -- red
    [STATUS.LATE_W_NOTICE]     = "ffffff33",  -- yellow
    [STATUS.ABSENT_W_NOTICE]   = "ffffff33",  -- yellow
    [STATUS.ABSENT_NO_NOTICE]  = "ffff5555",  -- red
    [STATUS.VACATION]          = "ff66ccff",  -- blue
    [STATUS.CANCELLED]         = "ffaaaaaa",  -- gray
}

-- Display order in dropdowns / cycles.
AssistanceTracker.STATUS_ORDER = {
    STATUS.OK, STATUS.LATE_W_NOTICE, STATUS.LATE_NO_NOTICE,
    STATUS.ABSENT_W_NOTICE, STATUS.ABSENT_NO_NOTICE,
    STATUS.VACATION, STATUS.CANCELLED,
}

-- ----------------------------------------------------------------------
-- Internal helpers
-- ----------------------------------------------------------------------

local function getProfile()
    return TTSGCM.db.profile
end

local function getAssist()
    return TTSGCM.db.profile.assistance
end

local function getRules()
    -- Merge the saved rules over the defaults table at read time, so a
    -- partial customisation never reads as nil.
    local A = getAssist()
    return A and A.fineRules or {}
end

local function ensureWeeklyDebtBucket(weekStart)
    local A = getAssist()
    A.weeklyDebt[weekStart] = A.weeklyDebt[weekStart] or {}
    local b = A.weeklyDebt[weekStart]
    if type(b.fines) ~= "table" then b.fines = {} end
    if type(b.paid)  ~= "table" then b.paid  = {} end
    if type(b.enchantMissing) ~= "table" then b.enchantMissing = {} end
    return b
end

local function getOrCreateRaidEventForToday()
    local A = getAssist()
    local W = TTSGCM.WeekEngine
    local now = time()
    -- Use the day-of-year as the event id within the year, plus the
    -- year, so multiple raid days resolve to distinct ids and same-day
    -- repeated scans hit the same event.
    local d = date("*t", now)
    local eventId = string.format("%04d-%02d-%02d", d.year, d.month, d.day)
    if not A.raidEvents[eventId] then
        A.raidEvents[eventId] = {
            id        = eventId,
            createdAt = now,
            scannedAt = 0,
            weekStart = W:GetWeekStart(now),
            attendance = {},
        }
    end
    return A.raidEvents[eventId]
end

-- Counts how many tardy events (any kind) the player has accumulated
-- since the start of the current tier. Used by the +1000g escalation.
local function countTardiesThisTier(name)
    local A = getAssist()
    local since = A.tierStartedAt or 0
    local count = 0
    for _, event in pairs(A.raidEvents) do
        if (event.createdAt or 0) >= since then
            local s = event.attendance and event.attendance[name]
            if s == STATUS.LATE_NO_NOTICE or s == STATUS.LATE_W_NOTICE then
                count = count + 1
            end
        end
    end
    return count
end

-- Returns true if the player has at least one vacation entry in the
-- given week, EXCLUDING the event we're about to write. Used by the
-- "-10 DKP per week of vacation" rule to make sure we only count once
-- per week.
local function hasOtherVacationThisWeek(name, weekStart, excludeEventId)
    local A = getAssist()
    for id, event in pairs(A.raidEvents) do
        if id ~= excludeEventId and event.weekStart == weekStart then
            if event.attendance and event.attendance[name] == STATUS.VACATION then
                return true
            end
        end
    end
    return false
end

local function appendAuditLog(name, delta, reason, source)
    local A = getAssist()
    table.insert(A.dkpAuditLog, {
        time = time(), player = name, delta = delta,
        reason = reason or "", source = source or "manual",
    })
    -- Cap the log at 500 entries to keep saved-vars manageable.
    while #A.dkpAuditLog > 500 do
        table.remove(A.dkpAuditLog, 1)
    end
end

-- ----------------------------------------------------------------------
-- DKP
-- ----------------------------------------------------------------------

function AssistanceTracker:GetDKP(name)
    return getAssist().dkp[name] or 0
end

function AssistanceTracker:AdjustDKP(name, delta, reason, source)
    if not name or not delta or delta == 0 then return end
    local A = getAssist()
    A.dkp[name] = (A.dkp[name] or 0) + delta
    appendAuditLog(name, delta, reason, source)
end

function AssistanceTracker:SetDKP(name, value, reason)
    if not name or type(value) ~= "number" then return end
    local A = getAssist()
    local old = A.dkp[name] or 0
    A.dkp[name] = value
    appendAuditLog(name, value - old, reason or "manual set", "manual")
end

-- ----------------------------------------------------------------------
-- Fine accumulation
-- ----------------------------------------------------------------------

function AssistanceTracker:AddFine(name, weekStart, copperAmount, reason)
    if not name or not weekStart or not copperAmount or copperAmount <= 0 then return end
    local b = ensureWeeklyDebtBucket(weekStart)
    b.fines[name] = (b.fines[name] or 0) + copperAmount
end

function AssistanceTracker:GetWeeklyFineTotal(name, weekStart)
    local b = ensureWeeklyDebtBucket(weekStart)
    local fine = b.fines[name] or 0
    local enchant = (b.enchantMissing[name] or 0) * (getRules().missingEnchantPerPc or 0)
    return fine + enchant
end

function AssistanceTracker:GetWeeklyPaid(name, weekStart)
    local b = ensureWeeklyDebtBucket(weekStart)
    return b.paid[name] or 0
end

function AssistanceTracker:GetWeeklyRemaining(name, weekStart)
    return math.max(0, self:GetWeeklyFineTotal(name, weekStart) - self:GetWeeklyPaid(name, weekStart))
end

function AssistanceTracker:MarkPaid(name, weekStart, copperAmount)
    if not name or not weekStart or not copperAmount or copperAmount <= 0 then return end
    local b = ensureWeeklyDebtBucket(weekStart)
    b.paid[name] = (b.paid[name] or 0) + copperAmount
end

function AssistanceTracker:ClearPaid(name, weekStart)
    local b = ensureWeeklyDebtBucket(weekStart)
    b.paid[name] = nil
end

function AssistanceTracker:SetEnchantMissingCount(name, weekStart, count)
    if not name or not weekStart then return end
    count = tonumber(count) or 0
    if count < 0 then count = 0 end
    if count > 42 then count = 42 end
    local b = ensureWeeklyDebtBucket(weekStart)
    b.enchantMissing[name] = (count > 0) and count or nil
end

function AssistanceTracker:GetEnchantMissingCount(name, weekStart)
    local b = ensureWeeklyDebtBucket(weekStart)
    return b.enchantMissing[name] or 0
end

-- ----------------------------------------------------------------------
-- Setting an attendance status (the heart of the module)
-- ----------------------------------------------------------------------

-- Apply the side effects of a status change for one player on one event:
-- DKP delta, gold fine, vacation-once-per-week handling.
local function applyStatusEffects(name, status, event)
    local rules = getRules()
    local A = getAssist()

    -- DKP and per-event fine
    local dkpDelta = 0
    local goldFine = 0
    local fineReason = nil

    if status == STATUS.OK then
        -- no penalty
    elseif status == STATUS.LATE_NO_NOTICE then
        dkpDelta = rules.dkpLateNoNotice or -5
        local base = rules.lateNoNoticeBase or 0
        -- "From the 2nd tardy onward, +1000g extra" - applied as a
        -- flat surcharge, not escalating. countTardiesThisTier
        -- includes the new entry because attendance was written
        -- before this function was called.
        local extras = countTardiesThisTier(name)
        if extras >= 2 then
            base = base + (rules.repeatTardyExtra or 0)
        end
        goldFine = base
        fineReason = "late_no_notice"
    elseif status == STATUS.LATE_W_NOTICE then
        dkpDelta = rules.dkpLateWithNotice or -5
        -- No gold base for "late w/ notice" but the +1000g surcharge
        -- DOES apply (rules say "regardless of motive" for repeat tardy).
        local extras = countTardiesThisTier(name)
        if extras >= 2 then
            goldFine = rules.repeatTardyExtra or 0
            fineReason = "tardy_repeat"
        end
    elseif status == STATUS.ABSENT_W_NOTICE then
        dkpDelta = rules.dkpAbsentWithNotice or -5
    elseif status == STATUS.ABSENT_NO_NOTICE then
        dkpDelta = rules.dkpAbsentNoNotice or -10
        goldFine = rules.absentNoNoticeBase or 0
        fineReason = "absent_no_notice"
    elseif status == STATUS.VACATION then
        if not hasOtherVacationThisWeek(name, event.weekStart, event.id) then
            dkpDelta = rules.dkpVacationPerWeek or -10
        end
    elseif status == STATUS.CANCELLED then
        -- no penalty
    end

    if dkpDelta ~= 0 then
        AssistanceTracker:AdjustDKP(name, dkpDelta, "auto: " .. status .. " on " .. event.id, "auto")
    end
    if goldFine > 0 then
        AssistanceTracker:AddFine(name, event.weekStart, goldFine, fineReason)
    end
end

-- Reverse the side effects of a previously-set status. Used when the
-- officer changes a player's status from one value to another - we
-- undo the old penalty before applying the new one. Symmetric with
-- applyStatusEffects.
local function reverseStatusEffects(name, status, event)
    local rules = getRules()
    local dkpDelta = 0
    local goldFine = 0

    if status == STATUS.LATE_NO_NOTICE then
        dkpDelta = -(rules.dkpLateNoNotice or -5)
        local base = rules.lateNoNoticeBase or 0
        -- countTardiesThisTier still includes this event (caller hasn't
        -- overwritten attendance yet), so the surcharge condition
        -- evaluates the same way the original charge did. Reverses
        -- exactly the amount applyStatusEffects added.
        local extras = countTardiesThisTier(name)
        if extras >= 2 then
            base = base + (rules.repeatTardyExtra or 0)
        end
        goldFine = -base
    elseif status == STATUS.LATE_W_NOTICE then
        dkpDelta = -(rules.dkpLateWithNotice or -5)
        local extras = countTardiesThisTier(name)
        if extras >= 2 then
            goldFine = -(rules.repeatTardyExtra or 0)
        end
    elseif status == STATUS.ABSENT_W_NOTICE then
        dkpDelta = -(rules.dkpAbsentWithNotice or -5)
    elseif status == STATUS.ABSENT_NO_NOTICE then
        dkpDelta = -(rules.dkpAbsentNoNotice or -10)
        goldFine = -(rules.absentNoNoticeBase or 0)
    elseif status == STATUS.VACATION then
        -- Only reverse the per-week DKP if THIS event was the one that
        -- triggered it (i.e. no OTHER vacation entries in the same week).
        if not hasOtherVacationThisWeek(name, event.weekStart, event.id) then
            dkpDelta = -(rules.dkpVacationPerWeek or -10)
        end
    end

    if dkpDelta ~= 0 then
        AssistanceTracker:AdjustDKP(name, dkpDelta, "reverse: " .. status .. " on " .. event.id, "auto")
    end
    if goldFine ~= 0 then
        local b = ensureWeeklyDebtBucket(event.weekStart)
        b.fines[name] = math.max(0, (b.fines[name] or 0) + goldFine)
        if b.fines[name] == 0 then b.fines[name] = nil end
    end
end

-- Public API: set a player's attendance status for a specific event.
-- Reverses old side effects, writes the new status, applies new ones.
function AssistanceTracker:SetStatus(eventId, name, newStatus)
    if not eventId or not name or not newStatus then return end
    local A = getAssist()
    local event = A.raidEvents[eventId]
    if not event then return end
    event.attendance = event.attendance or {}
    local oldStatus = event.attendance[name]
    if oldStatus == newStatus then return end
    if oldStatus then
        reverseStatusEffects(name, oldStatus, event)
    end
    event.attendance[name] = newStatus
    applyStatusEffects(name, newStatus, event)
end

-- ----------------------------------------------------------------------
-- Mark current raid group
-- ----------------------------------------------------------------------

-- Returns a set of player names currently in the player's raid group.
-- Names are normalized to bare (no -Realm) for comparison with the
-- tracked-players list (which canonicalizes the same way).
local function getCurrentRaidNamesSet()
    local set = {}
    if not IsInRaid or not IsInRaid() then return set end
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    for i = 1, n do
        local name = GetRaidRosterInfo and GetRaidRosterInfo(i) or nil
        if name then
            local bare = name:gsub("%-.*$", ""):lower()
            set[bare] = name  -- store under bare key, value is the API form
        end
    end
    return set
end

-- Marks today's raid event: in-raid players -> ok, tracked players
-- not in raid -> absent_no_notice. Returns counts for chat feedback.
function AssistanceTracker:MarkRaidGroup()
    local event = getOrCreateRaidEventForToday()
    event.scannedAt = time()
    local raidSet = getCurrentRaidNamesSet()
    local presentCount, absentCount = 0, 0
    for trackedName in pairs(getProfile().trackedPlayers) do
        local bare = trackedName:gsub("%-.*$", ""):lower()
        if raidSet[bare] then
            self:SetStatus(event.id, trackedName, STATUS.OK)
            presentCount = presentCount + 1
        else
            self:SetStatus(event.id, trackedName, STATUS.ABSENT_NO_NOTICE)
            absentCount = absentCount + 1
        end
    end
    return event, presentCount, absentCount
end

-- ----------------------------------------------------------------------
-- Tier reset
-- ----------------------------------------------------------------------

-- Wipes attendance, raid events, DKP balances, and the assistance
-- weekly debt ledger. Sets a new tier start. The audit log is kept
-- (truncated automatically) so the user can see the historical
-- adjustments across tiers if they want.
function AssistanceTracker:ResetTier(label)
    local A = getAssist()
    A.tierStartedAt = time()
    A.tierLabel = label or A.tierLabel or ""
    A.dkp = {}
    A.raidEvents = {}
    A.weeklyDebt = {}
    -- audit log left in place; the reset itself gets a marker
    table.insert(A.dkpAuditLog, {
        time = time(), player = "<TIER>", delta = 0,
        reason = "tier reset" .. (label and (" (" .. label .. ")") or ""),
        source = "reset",
    })
end

-- ----------------------------------------------------------------------
-- Inspection helpers
-- ----------------------------------------------------------------------

function AssistanceTracker:GetEventsThisTier()
    local A = getAssist()
    local since = A.tierStartedAt or 0
    local out = {}
    for _, event in pairs(A.raidEvents) do
        if (event.createdAt or 0) >= since then
            table.insert(out, event)
        end
    end
    table.sort(out, function(a, b) return (a.createdAt or 0) > (b.createdAt or 0) end)
    return out
end

function AssistanceTracker:GetEventForToday()
    return getOrCreateRaidEventForToday()
end

function AssistanceTracker:GetStatusCounts(name)
    local A = getAssist()
    local since = A.tierStartedAt or 0
    local counts = { ok = 0, late_no_notice = 0, late_w_notice = 0,
                     absent_no_notice = 0, absent_w_notice = 0,
                     vacation = 0, cancelled = 0 }
    for _, event in pairs(A.raidEvents) do
        if (event.createdAt or 0) >= since then
            local s = event.attendance and event.attendance[name]
            if s and counts[s] ~= nil then counts[s] = counts[s] + 1 end
        end
    end
    return counts
end
