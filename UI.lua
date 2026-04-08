-- TTS Guild Contribution Manager - UI
-- AceGUI-based windows:
--
--   MainWindow:   tracked-player list with paid/unpaid status, owed
--                 amount, manual mark controls, set-minimum input,
--                 plus buttons to scan, prune, open the picker.
--
--   PickerWindow: guild-roster browser to choose which players to
--                 track. Supports filter-by-rank and substring name
--                 search. Currently-tracked players show as checked
--                 and clicking the checkbox toggles tracking.

local TTSGCM = LibStub("AceAddon-3.0"):GetAddon("TTSGuildContributionManager")
local AceGUI = LibStub("AceGUI-3.0")

local UI = {}
TTSGCM.UI = UI

-- ----------------------------------------------------------------------
-- Main window
-- ----------------------------------------------------------------------

local mainFrame = nil   -- AceGUI frame, or nil when closed

local function closeMain()
    if mainFrame then
        AceGUI:Release(mainFrame)
        mainFrame = nil
    end
end

local function buildPlayerRow(parent, name)
    local D = TTSGCM.DebtEngine
    local W = TTSGCM.WeekEngine
    local currentWeek = W:GetCurrentWeekStart()

    local owed = D:GetOwedAtStartOfWeek(name, currentWeek)
    local paid = D:GetPaidForWeek(name, currentWeek)
    local rem = D:GetRemainingForWeek(name, currentWeek)
    local isPaid = rem <= 0

    local row = AceGUI:Create("InlineGroup")
    row:SetFullWidth(true)
    row:SetLayout("Flow")
    row:SetTitle("")

    local statusLabel = AceGUI:Create("Label")
    if isPaid then
        statusLabel:SetText("|cff33ff99[PAID]|r")
    else
        statusLabel:SetText("|cffff5555[UNPAID]|r")
    end
    statusLabel:SetWidth(80)
    row:AddChild(statusLabel)

    local nameLabel = AceGUI:Create("Label")
    nameLabel:SetText("|cffffffff" .. name .. "|r")
    nameLabel:SetWidth(160)
    row:AddChild(nameLabel)

    local amountLabel = AceGUI:Create("Label")
    amountLabel:SetText(string.format("paid %s / owed %s   remaining: %s",
        D:FormatCopper(paid), D:FormatCopper(owed), D:FormatCopper(rem)))
    amountLabel:SetWidth(340)
    row:AddChild(amountLabel)

    -- Inline custom-amount EditBox (gold). Empty = use remaining.
    local customBox = AceGUI:Create("EditBox")
    customBox:SetLabel("custom (g)")
    customBox:SetWidth(110)
    row:AddChild(customBox)

    local markBtn = AceGUI:Create("Button")
    markBtn:SetText("Mark Paid")
    markBtn:SetWidth(110)
    markBtn:SetCallback("OnClick", function()
        local g = tonumber(customBox:GetText())
        local copper
        if g and g > 0 then
            copper = D:GoldToCopper(g)
        else
            copper = rem
        end
        if copper <= 0 then return end
        D:ManualMark(name, currentWeek, copper)
        UI:RefreshMain()
    end)
    row:AddChild(markBtn)

    local clearBtn = AceGUI:Create("Button")
    clearBtn:SetText("Clear")
    clearBtn:SetWidth(70)
    clearBtn:SetCallback("OnClick", function()
        D:ClearManualMark(name, currentWeek)
        UI:RefreshMain()
    end)
    row:AddChild(clearBtn)

    local untrackBtn = AceGUI:Create("Button")
    untrackBtn:SetText("Untrack")
    untrackBtn:SetWidth(90)
    untrackBtn:SetCallback("OnClick", function()
        TTSGCM.TrackedPlayers:Remove(name)
        UI:RefreshMain()
    end)
    row:AddChild(untrackBtn)

    parent:AddChild(row)
end

local function buildMainContents(frame)
    local W = TTSGCM.WeekEngine
    local D = TTSGCM.DebtEngine
    local TP = TTSGCM.TrackedPlayers
    local currentWeek = W:GetCurrentWeekStart()

    frame:ReleaseChildren()
    frame:SetLayout("List")

    -- Header strip
    local header = AceGUI:Create("SimpleGroup")
    header:SetFullWidth(true)
    header:SetLayout("Flow")

    local weekLabel = AceGUI:Create("Label")
    if TTSGCM.db.profile.firstWeekStart then
        local idx = W:GetWeekIndex(currentWeek, TTSGCM.db.profile.firstWeekStart)
        weekLabel:SetText("|cffffff00Week " .. idx .. "|r  " .. W:FormatWeek(currentWeek))
    else
        weekLabel:SetText("|cffffff00Current week|r  " .. W:FormatWeek(currentWeek) .. "   |cffff5555(first week not set)|r")
    end
    weekLabel:SetWidth(420)
    header:AddChild(weekLabel)

    local minBox = AceGUI:Create("EditBox")
    minBox:SetLabel("Min (gold)")
    minBox:SetWidth(140)
    minBox:SetText(tostring(D:CopperToGold(D:GetCurrentWeekMin())))
    minBox:SetCallback("OnEnterPressed", function(widget, _, value)
        local g = tonumber(value)
        if g and g >= 0 then
            D:SetCurrentWeekMin(D:GoldToCopper(g))
            UI:RefreshMain()
        end
    end)
    header:AddChild(minBox)

    frame:AddChild(header)

    -- Summary strip
    local list = TP:List()
    local paidCount, unpaidCount = 0, 0
    for _, name in ipairs(list) do
        if D:IsPaidForWeek(name, currentWeek) then
            paidCount = paidCount + 1
        else
            unpaidCount = unpaidCount + 1
        end
    end

    local summary = AceGUI:Create("Label")
    summary:SetFullWidth(true)
    summary:SetText(string.format("Tracked: %d    |cff33ff99Paid: %d|r    |cffff5555Unpaid: %d|r",
        #list, paidCount, unpaidCount))
    frame:AddChild(summary)

    -- Player list (in a scroll frame)
    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetFullWidth(true)
    scroll:SetLayout("List")
    -- Give it explicit height so it doesn't collapse
    scroll:SetHeight(380)
    frame:AddChild(scroll)

    if #list == 0 then
        local empty = AceGUI:Create("Label")
        empty:SetText("\n  No players tracked yet. Click |cffffff00Add Players...|r below.")
        empty:SetFullWidth(true)
        scroll:AddChild(empty)
    else
        -- Sort: unpaid first (most owed first), then paid alphabetically
        table.sort(list, function(a, b)
            local pa = D:IsPaidForWeek(a, currentWeek)
            local pb = D:IsPaidForWeek(b, currentWeek)
            if pa ~= pb then return not pa end
            if not pa then
                return D:GetRemainingForWeek(a, currentWeek) > D:GetRemainingForWeek(b, currentWeek)
            end
            return a < b
        end)
        for _, name in ipairs(list) do
            buildPlayerRow(scroll, name)
        end
    end

    -- Bottom button strip
    local bottom = AceGUI:Create("SimpleGroup")
    bottom:SetFullWidth(true)
    bottom:SetLayout("Flow")

    local addBtn = AceGUI:Create("Button")
    addBtn:SetText("Add Players...")
    addBtn:SetWidth(140)
    addBtn:SetCallback("OnClick", function() UI:OpenPicker() end)
    bottom:AddChild(addBtn)

    local scanBtn = AceGUI:Create("Button")
    scanBtn:SetText("Scan Bank Now")
    scanBtn:SetWidth(140)
    scanBtn:SetCallback("OnClick", function()
        TTSGCM.BankReader:RequestLog()
        TTSGCM:Print("requested guild bank log (must be at the bank)")
    end)
    bottom:AddChild(scanBtn)

    local pruneBtn = AceGUI:Create("Button")
    pruneBtn:SetText("Prune History")
    pruneBtn:SetWidth(120)
    pruneBtn:SetCallback("OnClick", function()
        local n = TTSGCM.HistoryPruner:Prune()
        TTSGCM:Print(string.format("pruned %d week(s)", n))
        UI:RefreshMain()
    end)
    bottom:AddChild(pruneBtn)

    local refreshBtn = AceGUI:Create("Button")
    refreshBtn:SetText("Refresh")
    refreshBtn:SetWidth(100)
    refreshBtn:SetCallback("OnClick", function() UI:RefreshMain() end)
    bottom:AddChild(refreshBtn)

    frame:AddChild(bottom)
end

function UI:OpenMain()
    if mainFrame then
        self:RefreshMain()
        return
    end
    if not AceGUI then
        TTSGCM:Print("|cffff5555AceGUI-3.0 not loaded; cannot open UI|r")
        return
    end
    local frame = AceGUI:Create("Frame")
    if not frame then
        TTSGCM:Print("|cffff5555AceGUI failed to create main Frame|r")
        return
    end
    mainFrame = frame
    mainFrame:SetTitle("TTS Guild Contribution Manager")
    mainFrame:SetStatusText("Three Tank Strat - guild bank weekly contributions")
    mainFrame:SetWidth(900)
    mainFrame:SetHeight(620)
    mainFrame:SetCallback("OnClose", function() closeMain() end)
    local ok, err = pcall(buildMainContents, mainFrame)
    if not ok then
        TTSGCM:Print("|cffff5555UI build error:|r " .. tostring(err))
    end
end

function UI:RefreshMain()
    if not mainFrame then return end
    local ok, err = pcall(buildMainContents, mainFrame)
    if not ok then
        TTSGCM:Print("|cffff5555UI refresh error:|r " .. tostring(err))
    end
end

function UI:ToggleMain()
    if mainFrame then closeMain() else self:OpenMain() end
end

-- ----------------------------------------------------------------------
-- Picker window
-- ----------------------------------------------------------------------

local pickerFrame = nil
local pickerFilters = { rankIndex = nil, nameQuery = "" }
local safeBuildPicker  -- forward declaration; assigned below

local function closePicker()
    if pickerFrame then
        AceGUI:Release(pickerFrame)
        pickerFrame = nil
    end
end

local function buildPickerContents(frame)
    local TP = TTSGCM.TrackedPlayers
    frame:ReleaseChildren()
    frame:SetLayout("List")

    if not TTSGCM.Compat:IsInGuild() then
        local lbl = AceGUI:Create("Label")
        lbl:SetText("\n  You are not in a guild.")
        lbl:SetFullWidth(true)
        frame:AddChild(lbl)
        return
    end

    -- Filter strip
    local filterRow = AceGUI:Create("SimpleGroup")
    filterRow:SetFullWidth(true)
    filterRow:SetLayout("Flow")

    local rankDropdown = AceGUI:Create("Dropdown")
    rankDropdown:SetLabel("Filter by rank")
    rankDropdown:SetWidth(220)
    local ranks = TP:GetRanks()
    -- Use string keys so we don't depend on AceGUI handling negative
    -- integer keys consistently. "ALL" is the sentinel for "no filter".
    local rankList = { ALL = "All ranks" }
    local order = { "ALL" }
    for _, r in ipairs(ranks) do
        local key = "rank" .. r.index
        rankList[key] = string.format("[%d] %s", r.index, r.name)
        table.insert(order, key)
    end
    rankDropdown:SetList(rankList, order)
    rankDropdown:SetValue(pickerFilters.rankIndex and ("rank" .. pickerFilters.rankIndex) or "ALL")
    rankDropdown:SetCallback("OnValueChanged", function(_, _, value)
        if value == "ALL" then
            pickerFilters.rankIndex = nil
        else
            pickerFilters.rankIndex = tonumber((tostring(value)):match("rank(%-?%d+)"))
        end
        safeBuildPicker(frame)
    end)
    filterRow:AddChild(rankDropdown)

    local searchBox = AceGUI:Create("EditBox")
    searchBox:SetLabel("Search by name")
    searchBox:SetWidth(220)
    searchBox:SetText(pickerFilters.nameQuery or "")
    searchBox:SetCallback("OnEnterPressed", function(_, _, value)
        pickerFilters.nameQuery = value or ""
        safeBuildPicker(frame)
    end)
    filterRow:AddChild(searchBox)

    local refreshBtn = AceGUI:Create("Button")
    refreshBtn:SetText("Refresh Roster")
    refreshBtn:SetWidth(140)
    refreshBtn:SetCallback("OnClick", function()
        TP:InvalidateRosterCache()
        TP:RequestRosterUpdate()
        safeBuildPicker(frame)
    end)
    filterRow:AddChild(refreshBtn)

    frame:AddChild(filterRow)

    -- Roster scroll list
    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetFullWidth(true)
    scroll:SetLayout("List")
    scroll:SetHeight(420)
    frame:AddChild(scroll)

    local roster = TP:GetRoster(pickerFilters)
    if #roster == 0 then
        local lbl = AceGUI:Create("Label")
        lbl:SetText("\n  No matches. (Roster fetch is async; try Refresh Roster.)")
        lbl:SetFullWidth(true)
        scroll:AddChild(lbl)
    else
        for _, m in ipairs(roster) do
            local cb = AceGUI:Create("CheckBox")
            cb:SetFullWidth(true)
            cb:SetLabel(string.format("%s   |cff999999[%s, lvl %d, %s]|r",
                m.name, m.rankName or "?", m.level or 0, m.class or "?"))
            cb:SetValue(TP:IsTracked(m.name))
            cb:SetCallback("OnValueChanged", function(_, _, value)
                if value then
                    TP:Add(m.name)
                else
                    TP:Remove(m.name)
                end
                UI:RefreshMain()
            end)
            scroll:AddChild(cb)
        end
    end

    local statusLbl = AceGUI:Create("Label")
    statusLbl:SetFullWidth(true)
    statusLbl:SetText(string.format("Showing %d guild member(s).  Tracked: %d", #roster, TP:Count()))
    frame:AddChild(statusLbl)
end

safeBuildPicker = function(frame)
    local ok, err = pcall(buildPickerContents, frame)
    if not ok then
        TTSGCM:Print("|cffff5555Picker build error:|r " .. tostring(err))
    end
end

function UI:OpenPicker()
    if pickerFrame then
        safeBuildPicker(pickerFrame)
        return
    end
    if not AceGUI then
        TTSGCM:Print("|cffff5555AceGUI-3.0 not loaded; cannot open picker|r")
        return
    end
    local frame = AceGUI:Create("Frame")
    if not frame then
        TTSGCM:Print("|cffff5555AceGUI failed to create picker Frame|r")
        return
    end
    pickerFrame = frame
    pickerFrame:SetTitle("TTS Guild Contribution Manager - Add Players")
    pickerFrame:SetStatusText("Pick which guild members to track")
    pickerFrame:SetWidth(640)
    pickerFrame:SetHeight(620)
    pickerFrame:SetCallback("OnClose", function() closePicker() end)
    -- Make sure we have current roster data before drawing
    TTSGCM.TrackedPlayers:RequestRosterUpdate()
    safeBuildPicker(pickerFrame)
end
