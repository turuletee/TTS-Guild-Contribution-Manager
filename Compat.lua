-- TTS Guild Contribution Manager - Compat
-- Centralized wrappers around WoW APIs that have moved namespaces or
-- may not exist on a given client. Returning safe defaults instead of
-- crashing keeps the addon usable when Blizzard renames things.
--
-- Background: in patch 11.0.2 a bunch of global API helpers were moved
-- into namespaces (e.g. IsAddOnLoaded -> C_AddOns.IsAddOnLoaded), and
-- patch 12.0 removed the deprecated globals entirely. We don't currently
-- use IsAddOnLoaded but the same churn could happen to anything in this
-- file at any time, so route every WoW call through a function that
-- checks before invoking.

local TTSGCM = LibStub("AceAddon-3.0"):GetAddon("TTSGuildContributionManager")

local Compat = {}
TTSGCM.Compat = Compat

-- ----------------------------------------------------------------------
-- Guild membership and roster
-- ----------------------------------------------------------------------

function Compat:IsInGuild()
    if IsInGuild then return IsInGuild() and true or false end
    return false
end

function Compat:RequestGuildRoster()
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
        return true
    end
    if GuildRoster then  -- removed sometime around 8.2 but kept as a safety net
        GuildRoster()
        return true
    end
    return false
end

function Compat:GetNumGuildMembers()
    if GetNumGuildMembers then return GetNumGuildMembers() or 0 end
    return 0
end

function Compat:GetGuildRosterInfo(i)
    if not GetGuildRosterInfo then return nil end
    return GetGuildRosterInfo(i)
end

-- ----------------------------------------------------------------------
-- Guild bank money log
-- ----------------------------------------------------------------------

function Compat:GetMoneyLogTab()
    return (MAX_GUILD_BANK_TABS or 6) + 1
end

function Compat:QueryGuildBankLog(tab)
    tab = tab or self:GetMoneyLogTab()
    if QueryGuildBankLog then
        QueryGuildBankLog(tab)
        return true
    end
    -- Fallback for hypothetical future C_GuildBank namespace
    if C_GuildBank and C_GuildBank.QueryGuildBankLog then
        C_GuildBank.QueryGuildBankLog(tab)
        return true
    end
    return false
end

function Compat:GetNumGuildBankMoneyTransactions()
    if GetNumGuildBankMoneyTransactions then
        return GetNumGuildBankMoneyTransactions() or 0
    end
    if C_GuildBank and C_GuildBank.GetNumMoneyTransactions then
        return C_GuildBank.GetNumMoneyTransactions() or 0
    end
    return 0
end

function Compat:GetGuildBankMoneyTransaction(i)
    if GetGuildBankMoneyTransaction then
        return GetGuildBankMoneyTransaction(i)
    end
    if C_GuildBank and C_GuildBank.GetMoneyTransaction then
        return C_GuildBank.GetMoneyTransaction(i)
    end
    return nil
end

-- ----------------------------------------------------------------------
-- Misc
-- ----------------------------------------------------------------------

function Compat:Now()
    if time then return time() end
    return 0
end
