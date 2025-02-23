-- ------------------------------- --
local  _, CLM = ...
-- ------ CLM common cache ------- --
local LOG       = CLM.LOG
local CONSTANTS = CLM.CONSTANTS
local UTILS     = CLM.UTILS
-- ------------------------------- --

local _, _, _, isElvUI = GetAddOnInfo("ElvUI")

local colorRed = {r = 0.93, g = 0.276, b = 0.27, a = 1.0}
local colorRedTransparent = {r = 0.93, g = 0.276, b = 0.27, a = 0.3}
local colorBlueTransparent = {r = 0.27, g = 0.276, b = 0.93, a = 0.3}
local colorGreen = {r = 0.27, g = 0.93, b = 0.27, a = 1.0}

local function ST_GetName(row)
    return row.cols[2].value
end

local function ST_GetClass(row)
    return row.cols[15].value
end

local function ST_GetWeeklyGains(row)
    return row.cols[7].value
end

local function ST_GetWeeklyCap(row)
    return row.cols[8].value
end

local function ST_GetPointInfo(row)
    return row.cols[9].value
end

local function ST_GetProfileLoot(row)
    return row.cols[10].value
end

local function ST_GetProfilePoints(row)
    return row.cols[11].value
end

local function ST_GetPointType(row)
    return row.cols[12].value
end

local function ST_GetEP(row)
    return row.cols[4].value
end

local function ST_GetIsLocked(row)
    return row.cols[13].value
end

local function ST_GetHighlight(row)
    return row.cols[14].value
end

local function ST_GetGP(row)
    return row.cols[5].value
end

local highlightPlayer = UTILS.getHighlightMethod(colorBlueTransparent, true)
local highlightLocked = UTILS.getHighlightMethod(colorRedTransparent, true)

local function refreshFn(...)
    CLM.GUI.Unified:Refresh(...)
end

local UnifiedGUI_Standings = {
    name = "standings",
    awardReason = CONSTANTS.POINT_CHANGE_REASON.MANUAL_ADJUSTMENT,
    filter = CLM.MODELS.Filters:New(
    (function() CLM.GUI.Unified:FilterScrollingTable() end),
    UTILS.Set({
        "class", "inRaid", "inStandby",
        "inGuild", "external", "main", "rank", "locked"
    }),
    UTILS.Set({
        "buttons", "search"
    }),
    nil, 2),
    tooltip = CreateFrame("GameTooltip", "CLMUnifiedGUIStandingsDialogTooltip", UIParent, "GameTooltipTemplate"),
}

local function HandleRosterChange(rosterUid)
    UnifiedGUI_Standings.roster = rosterUid
    UnifiedGUI_Standings.awardType = CONSTANTS.POINT_CHANGE_TYPE.POINTS
    UnifiedGUI_Standings.decayType = CONSTANTS.POINT_CHANGE_TYPE.POINTS
    local roster = CLM.MODULES.RosterManager:GetRosterByUid(UnifiedGUI_Standings.roster)
    if roster and roster:GetPointType() == CONSTANTS.POINT_TYPE.EPGP then
        UnifiedGUI_Standings.decayType = CONSTANTS.POINT_CHANGE_TYPE.TOTAL
    end
end

function UnifiedGUI_Standings:GetSelection()
    LOG:Trace("UnifiedGUI_Standings:GetSelection()")
    local st = CLM.GUI.Unified:GetScrollingTable()
    local profiles = {}
    -- Roster
    local roster = CLM.MODULES.RosterManager:GetRosterByUid(self.roster)
    if not roster then
        return profiles
    end
    -- Profiles
    local selected = st:GetSelection()
    if #selected == 0 then
        return profiles
    end
    for _,s in pairs(selected) do
        local profile = CLM.MODULES.ProfileManager:GetProfileByName(ST_GetName(st:GetRow(s)))
        if profile then
            profiles[#profiles+1] = profile
        else
            LOG:Debug("No profile for %s", ST_GetName(st:GetRow(s)))
        end
    end
    return profiles
end

local function GenerateUntrustedOptions(self)
    local options = {}
    options.roster = {
        name = CLM.L["Roster"],
        type = "select",
        values = CLM.MODULES.RosterManager:GetRostersUidMap(),
        set = function(i, v)
            -- self.roster = v
            HandleRosterChange(v)
            self.context = CONSTANTS.ACTION_CONTEXT.ROSTER
            refreshFn()
        end,
        get = function(i) return self.roster end,
        width = "full",
        order = 0
    }
    UTILS.mergeDictsInline(options, self.filter:GetAceOptions())
    return options
end

local function GenerateAssistantOptions(self)
    return {
        award_header = {
            type = "header",
            name = CLM.L["Management"],
            order = 9
        },
        action_context = {
            name = CLM.L["Action context"],
            type = "select",
            values = CONSTANTS.ACTION_CONTEXT_GUI,
            set = function(i, v) self.context = v end,
            get = function(i) return self.context end,
            order = 10,
            width = "full"
        },
        award_dkp_note = {
            name = CLM.L["Note"],
            desc = (function()
                local n = CLM.L["Note to be added to award. Max 25 characters. It is recommended to not include date nor selected reason here. If you will input encounter ID it will be transformed into boss name."]
                if strlen(self.note or "") > 0 then
                    n = n .. "\n\n|cffeeee00Note:|r " .. self.note
                end
                return n
            end),
            type = "input",
            set = function(i, v) self.note = v end,
            get = function(i) return self.note end,
            width = "full",
            order = 12
        },
        award_reason = {
            name = CLM.L["Reason"],
            type = "select",
            values = CONSTANTS.POINT_CHANGE_REASONS.GENERAL,
            set = function(i, v) self.awardReason = v end,
            get = function(i) return self.awardReason end,
            order = 11,
            width = "full"
        },
        award_dkp_value = {
            name = CLM.L["Award value"],
            desc = CLM.L["Points value that will be awarded."],
            type = "input",
            set = function(i, v) self.awardValue = v end,
            get = function(i) return self.awardValue end,
            width = 0.5,
            pattern = CONSTANTS.REGEXP_FLOAT,
            order = 13
        },
        award_dkp = {
            name = CLM.L["Award"],
            desc = CLM.L["Award points to players based on context."],
            type = "execute",
            width = isElvUI and 0.5 or 0.575,
            func = (function(i)
                -- Award Value
                local awardValue = tonumber(self.awardValue)
                if not awardValue then LOG:Debug("UnifiedGUI_Standings(Award): missing award value"); return end
                -- Reason
                local awardReason
                if self.awardReason and CONSTANTS.POINT_CHANGE_REASONS.GENERAL[self.awardReason] then
                    awardReason = self.awardReason
                else
                    LOG:Debug("UnifiedGUI_Standings(Award): missing reason");
                    awardReason = CONSTANTS.POINT_CHANGE_REASON.MANUAL_ADJUSTMENT
                end
                local roster = CLM.MODULES.RosterManager:GetRosterByUid(self.roster)
                if self.context == CONSTANTS.ACTION_CONTEXT.RAID then
                    if CLM.MODULES.RaidManager:IsInRaid() then
                        CLM.MODULES.PointManager:UpdateRaidPoints(CLM.MODULES.RaidManager:GetRaid(), awardValue, awardReason, CONSTANTS.POINT_MANAGER_ACTION.MODIFY, self.note, self.awardType)
                    else
                        LOG:Warning("You are not in raid.")
                    end
                elseif self.context == CONSTANTS.ACTION_CONTEXT.ROSTER then
                    if roster then
                        CLM.MODULES.PointManager:UpdateRosterPoints(roster, awardValue, awardReason, CONSTANTS.POINT_MANAGER_ACTION.MODIFY, false, self.note, self.awardType)
                    else
                        LOG:Warning("Missing valid roster.")
                    end
                elseif self.context == CONSTANTS.ACTION_CONTEXT.SELECTED then
                    local profiles = UnifiedGUI_Standings:GetSelection()
                    if not profiles or #profiles == 0 then
                        LOG:Message(CLM.L["No players selected"])
                        LOG:Debug("UnifiedGUI_Standings(Award): profiles == 0")
                        return
                    end
                    if roster then
                        CLM.MODULES.PointManager:UpdatePoints(roster, profiles, awardValue, awardReason, CONSTANTS.POINT_MANAGER_ACTION.MODIFY, self.note, self.awardType)
                    else
                        LOG:Warning("Missing valid roster.")
                    end
                end
            end),
            confirm = (function()
                local awardValue = tonumber(self.awardValue)
                if not awardValue then return CLM.L["Missing award value"] end
                local roster = CLM.MODULES.RosterManager:GetRosterByUid(self.roster)
                local points = UTILS.DecodePointTypeChangeName(roster:GetPointType(), self.awardType, true)
                if self.context == CONSTANTS.ACTION_CONTEXT.RAID then
                    return string.format(CLM.L["Award %s %s to everyone in raid."], awardValue, points)
                elseif self.context == CONSTANTS.ACTION_CONTEXT.ROSTER then
                    return string.format(CLM.L["Award %s %s to everyone in roster."], awardValue, points)
                elseif self.context == CONSTANTS.ACTION_CONTEXT.SELECTED then
                    local profiles = UnifiedGUI_Standings:GetSelection()
                    if not profiles then profiles = {} end
                    return string.format(CLM.L["Award %s %s to %s selected players."], awardValue, points, #profiles)
                end
            end),
            order = 14
        },
        award_type_dropdown = {
            name = CLM.L["Type"],
            type = "select",
            values = CONSTANTS.EPGP_POINT_AWARD_TYPES_GUI,
            set = function(i, v) self.awardType = v end,
            get = function(i) return self.awardType end,
            control = "CLMButtonDropDown",
            hidden = (function()
                local roster = CLM.MODULES.RosterManager:GetRosterByUid(self.roster)
                if roster then
                    return (roster:GetPointType() ~= CONSTANTS.POINT_TYPE.EPGP)
                end

                return true
            end),
            order = 15,
            width = 0.2
        },
    }
end

local function GenerateManagerOptions(self)
    return {
        decay_dkp_value = {
            name = CLM.L["Decay %"],
            desc = CLM.L["% that will be decayed."],
            type = "input",
            set = function(i, v) self.decayValue = v end,
            get = function(i) return self.decayValue end,
            width = 0.5,
            pattern = CONSTANTS.REGEXP_FLOAT,
            order = 21
        },
        decay_type_dropodown = {
            name = CLM.L["Type"],
            type = "select",
            values = CONSTANTS.EPGP_POINT_DECAY_TYPES_GUI,
            set = function(i, v) self.decayType = v end,
            get = function(i) return self.decayType end,
            control = "CLMButtonDropDown",
            hidden = (function()
                local roster = CLM.MODULES.RosterManager:GetRosterByUid(self.roster)
                if roster then
                    return (roster:GetPointType() ~= CONSTANTS.POINT_TYPE.EPGP)
                end

                return true
            end),
            order = 23,
            width = 0.2
        },
        decay_negative = {
            name = CLM.L["Decay Negatives"],
            desc = CLM.L["Include players with negative standings in decay."],
            type = "toggle",
            set = function(i, v) self.includeNegative = v end,
            get = function(i) return self.includeNegative end,
            hidden = function()
                local roster = CLM.MODULES.RosterManager:GetRosterByUid(UnifiedGUI_Standings.roster)
                if not roster then return false end
                return (roster:GetPointType() == CONSTANTS.POINT_TYPE.EPGP)
            end,
            width = "full",
            order = 24
        },
        decay_dkp = {
            name = CLM.L["Decay"],
            desc = CLM.L["Execute decay for players based on context."],
            type = "execute",
            width = isElvUI and 0.5 or 0.575,
            func = (function(i)
                -- Decay Value
                local decayValue = tonumber(self.decayValue)
                if not decayValue then LOG:Debug("UnifiedGUI_Standings(Decay): missing decay value"); return end
                if decayValue > 100 or decayValue < 0 then LOG:Warning("Standings: Decay value should be between 0 and 100%"); return end
                local roster = CLM.MODULES.RosterManager:GetRosterByUid(self.roster)
                if roster == nil then
                    LOG:Debug("UnifiedGUI_Standings(Decay): roster == nil")
                    return
                end
                if self.context == CONSTANTS.ACTION_CONTEXT.ROSTER then
                    CLM.MODULES.PointManager:UpdateRosterPoints(roster, decayValue, CONSTANTS.POINT_CHANGE_REASON.DECAY, CONSTANTS.POINT_MANAGER_ACTION.DECAY, not self.includeNegative, nil, self.decayType)
                elseif self.context == CONSTANTS.ACTION_CONTEXT.SELECTED then
                    local profiles = UnifiedGUI_Standings:GetSelection()
                    if not profiles or #profiles == 0 then
                        LOG:Message(CLM.L["No players selected"])
                        LOG:Debug("UnifiedGUI_Standings(Decay): profiles == 0")
                        return
                    end
                    CLM.MODULES.PointManager:UpdatePoints(roster, profiles, decayValue, CONSTANTS.POINT_CHANGE_REASON.DECAY, CONSTANTS.POINT_MANAGER_ACTION.DECAY, nil, self.decayType)
                else
                    LOG:Warning("Invalid context. You should not decay raid only.")
                end
            end),
            confirm = (function()
                local decayValue = tonumber(self.decayValue)
                if not decayValue then return CLM.L["Missing decay value"] end
                local roster = CLM.MODULES.RosterManager:GetRosterByUid(self.roster)
                local points = UTILS.DecodePointTypeChangeName(roster:GetPointType(), self.decayType, true)
                if self.context == CONSTANTS.ACTION_CONTEXT.RAID then
                    return CLM.L["Invalid context. You should not decay raid only."]
                elseif self.context == CONSTANTS.ACTION_CONTEXT.ROSTER then
                    return string.format(CLM.L["Decay %s%% %s to everyone in roster."], decayValue, points)
                elseif self.context == CONSTANTS.ACTION_CONTEXT.SELECTED then
                    local profiles = UnifiedGUI_Standings:GetSelection()
                    if not profiles then profiles = {} end
                    return string.format(CLM.L["Decay %s%% %s to %s selected players."], decayValue, points, #profiles)
                end
            end),
            order = 22
        }
    }
end

local function verticalOptionsFeeder()
    local options = {
        type = "group",
        args = {}
    }
    UTILS.mergeDictsInline(options.args, GenerateUntrustedOptions(UnifiedGUI_Standings))
    if CLM.MODULES.ACL:CheckLevel(CONSTANTS.ACL.LEVEL.ASSISTANT) then
        UTILS.mergeDictsInline(options.args, GenerateAssistantOptions(UnifiedGUI_Standings))
    end
    if CLM.MODULES.ACL:CheckLevel(CONSTANTS.ACL.LEVEL.MANAGER) then
        UTILS.mergeDictsInline(options.args, GenerateManagerOptions(UnifiedGUI_Standings))
    end
    return options
end

local columnsDKP = {
    {   name = "", width = 18, DoCellUpdate = UTILS.LibStClassCellUpdate },
    {   name = CLM.L["Name"],   width = 107 },
    {   name = CLM.L["DKP"], width = 65, sort = LibStub("ScrollingTable").SORT_DSC, color = colorGreen },
    {   name = CLM.L["Spent"], width = 65 },
    {   name = CLM.L["Received"], width = 65 },
    {   name = CLM.L["Att. [%]"], width = 60,
        comparesort = UTILS.LibStCompareSortWrapper(UTILS.LibStModifierFnNumber)
    }
}

local columnsEPGP = {
    {   name = "", width = 18, DoCellUpdate = UTILS.LibStClassCellUpdate },
    {   name = CLM.L["Name"], width = 107 },
    {   name = CLM.L["PR"], width = 65, sort = LibStub("ScrollingTable").SORT_DSC, color = colorGreen },
    {   name = CLM.L["EP"], width = 65 },
    {   name = CLM.L["GP"], width = 65 },
    {   name = CLM.L["Att. [%]"], width = 60,
        comparesort = UTILS.LibStCompareSortWrapper(UTILS.LibStModifierFnNumber)
    }
}

local tableStructure = {
    rows = 25,
    -- columns - structure of the ScrollingTable
    columns = columnsDKP,
    -- Function to filter ScrollingTable
    filter = (function(stobject, row)
        local playerName = ST_GetName(row)
        local class = ST_GetClass(row)
        return UnifiedGUI_Standings.filter:Filter(playerName, class, {playerName, class})
    end),
    -- Events to override for ScrollingTable
    events = {
        -- OnEnter handler -> on hover
        OnEnter = (function (rowFrame, cellFrame, data, cols, row, realrow, column, table, ...)
            local status = table.DefaultEvents["OnEnter"](rowFrame, cellFrame, data, cols, row, realrow, column, table, ...)
            local rowData = table:GetRow(realrow)
            if not rowData or not rowData.cols then return status end
            local tooltip = UnifiedGUI_Standings.tooltip
            if not tooltip then return end
            tooltip:SetOwner(rowFrame, "ANCHOR_RIGHT")
            local lockedString = ""
            if ST_GetIsLocked(rowData) then
                lockedString = "|c4eED3333" .. CLM.L["Locked"] .. "|r"
            end
            local pointInfo = ST_GetPointInfo(rowData)
            local weeklyGain = ST_GetWeeklyGains(rowData)
            local weeklyCap = ST_GetWeeklyCap(rowData)
            local gains = weeklyGain
            if weeklyCap > 0 then
                gains = gains .. " / " .. weeklyCap
            end

            local isEPGP = (ST_GetPointType(rowData) == CONSTANTS.POINT_TYPE.EPGP)
            if isEPGP then
                tooltip:AddDoubleLine(CLM.L["Information"], lockedString)
                tooltip:AddDoubleLine(
                    UTILS.ColorCodeText(tostring(ST_GetEP(rowData)) .. " ".. CLM.L["EP"], "44ee44"),
                    UTILS.ColorCodeText(tostring(ST_GetGP(rowData)) .. " ".. CLM.L["GP"], "44ee44"))
                tooltip:AddDoubleLine(CLM.L["Weekly gains"], tostring(gains) .. " " .. CLM.L["EP"])
            else
                tooltip:AddDoubleLine(CLM.L["Information"], lockedString)
                tooltip:AddDoubleLine(CLM.L["Weekly gains"], gains)
                tooltip:AddLine("\n")
                -- Statistics
                tooltip:AddDoubleLine(UTILS.ColorCodeText(CLM.L["Statistics"], "44ee44"), CLM.L["DKP"])
                tooltip:AddDoubleLine(CLM.L["Total spent"], pointInfo.spent)
                tooltip:AddDoubleLine(CLM.L["Total received"], pointInfo.received)
                tooltip:AddDoubleLine(CLM.L["Total blocked"], pointInfo.blocked)
                tooltip:AddDoubleLine(CLM.L["Total decayed"], pointInfo.decayed)
            end
            -- Loot History
            local lootList = ST_GetProfileLoot(rowData)
            tooltip:AddLine("\n")
            if #lootList > 0 then
                tooltip:AddDoubleLine(UTILS.ColorCodeText(CLM.L["Latest loot"], "44ee44"), isEPGP and "" or CLM.L["DKP"])
                local limit = #lootList - 4 -- inclusive (- 5 + 1)
                if limit < 1 then
                    limit = 1
                end
                for i=#lootList, limit, -1 do
                    local loot = lootList[i]
                    local _, itemLink = GetItemInfo(loot:Id())
                    if itemLink then
                        local value = loot:Value()
                        if isEPGP then
                            value = tostring(value) .. " " .. CLM.L["GP"]
                        end
                        tooltip:AddDoubleLine(itemLink, value)
                    end
                end
            else
                tooltip:AddLine(UTILS.ColorCodeText(CLM.L["No loot received"], "44ee44"))
            end
            -- Point History
            local pointList = ST_GetProfilePoints(rowData)
            tooltip:AddLine("\n")
            if #pointList > 0 then
                tooltip:AddDoubleLine(UTILS.ColorCodeText(CLM.L["Latest points"], "44ee44"), isEPGP and "" or CLM.L["DKP"])
                local limit = #pointList - 4 -- inclusive (- 5 + 1)
                if limit < 1 then
                    limit = 1
                end
                for i=#pointList, limit, -1 do
                    local point = pointList[i]

                    local reason = point:Reason() or 0
                    local value = tostring(point:Value())

                    if reason == CONSTANTS.POINT_CHANGE_REASON.DECAY then
                        value = value .. "%"
                    end
                    local suffix = UTILS.DecodePointTypeChangeName(ST_GetPointType(rowData), point:Type())
                    value = value .. " " .. suffix
                    tooltip:AddDoubleLine(CONSTANTS.POINT_CHANGE_REASONS.ALL[reason] or "", value)
                end
            else
                tooltip:AddLine(UTILS.ColorCodeText(CLM.L["No points received"], "44ee44"))
            end
            -- Display
            tooltip:Show()
            return status
        end),
        -- OnLeave handler -> on hover out
        OnLeave = (function (rowFrame, cellFrame, data, cols, row, realrow, column, table, ...)
            local status = table.DefaultEvents["OnLeave"](rowFrame, cellFrame, data, cols, row, realrow, column, table, ...)
            UnifiedGUI_Standings.tooltip:Hide()
            local rowData = table:GetRow(realrow)
            if not rowData or not rowData.cols then return status end
            local highlight = ST_GetHighlight(rowData)
            if highlight then
                highlight(rowFrame, cellFrame, data, cols, row, realrow, column, true, table, ...)
            end
            return status
        end),
        -- OnClick handler -> click
        OnClick = function(rowFrame, cellFrame, data, cols, row, realrow, column, table, button, ...)
            UTILS.LibStClickHandler(table, UnifiedGUI_Standings.RightClickMenu, rowFrame, cellFrame, data, cols, row, realrow, column, table, button, ...)
            UnifiedGUI_Standings.context = CONSTANTS.ACTION_CONTEXT.SELECTED
            CLM.GUI.Unified:RefreshOptionsPane()
            return true
        end
    }
}

local function tableDataFeeder()
    LOG:Trace("UnifiedGUI_Standings tableDataFeeder()")
    local roster = CLM.MODULES.RosterManager:GetRosterByUid(UnifiedGUI_Standings.roster)
    if not roster then return {} end
    local weeklyCap = roster:GetConfiguration("weeklyCap")
    local rowId = 1
    local data = {}
    local isEPGP = (roster:GetPointType() == CONSTANTS.POINT_TYPE.EPGP)
    for GUID,value in pairs(roster:Standings()) do
        local profile = CLM.MODULES.ProfileManager:GetProfileByGUID(GUID)
        local attendance = UTILS.round(roster:GetAttendance(GUID) or 0, 0)
        local pointInfo = roster:GetPointInfoForPlayer(GUID)
        local numColumnValue
        local primary
        local secondary
        if isEPGP then
            numColumnValue = roster:Priority(GUID)
            primary = value
            secondary = roster:GP(GUID)
        else
            primary = pointInfo.spent
            secondary = pointInfo.received
            numColumnValue = value
        end
        if profile then
            local highlight
            if profile:IsLocked() then
                highlight = highlightLocked
            elseif profile:Name() == UTILS.whoami() then
                highlight = highlightPlayer
            end
            local classColor = UTILS.GetClassColor(profile:ClassInternal())
            local row = { cols = {
        --[[1]]  {value = profile:ClassInternal()},
        --[[2]]  {value = profile:Name(), color = classColor},
        --[[3]]  {value = numColumnValue, color = (value > 0 and colorGreen or colorRed)},
        --[[4]]  {value = primary},
        --[[5]]  {value = secondary},
        --[[6]]  {value = UTILS.ColorCodeByPercentage(attendance)},
            -- not displayed
        --[[7]]  {value = roster:GetCurrentGainsForPlayer(GUID)},                            -- 7
        --[[8]]  {value = weeklyCap},
        --[[9]]  {value = pointInfo},
        --[[10]] {value = roster:GetProfileLootByGUID(GUID)},
        --[[11]] {value = roster:GetProfilePointHistoryByGUID(GUID)},
        --[[12]] {value = roster:GetPointType()},
        --[[13]] {value = profile:IsLocked()},
        --[[14]] {value = highlight},
        --[[15]] {value = profile:Class()}
            },
            DoCellUpdate = highlight
            }
            data[rowId] = row
            rowId = rowId + 1
        end
    end
    return data
end

local function initializeHandler()
    LOG:Trace("UnifiedGUI_Standings initializeHandler()")
    UnifiedGUI_Standings.RightClickMenu = CLM.UTILS.GenerateDropDownMenu(
        {
            {
                title = CLM.L["Add to standby"],
                func = (function()
                    if not CLM.MODULES.RaidManager:IsInRaid() then
                        LOG:Message(CLM.L["Not in raid"])
                        return
                    end
                    local profiles = UnifiedGUI_Standings:GetSelection()
                    local raid = CLM.MODULES.RaidManager:GetRaid()
                    local roster = CLM.MODULES.RosterManager:GetRosterByUid(UnifiedGUI_Standings.roster)
                    if roster ~= raid:Roster() then
                        LOG:Message(string.format(
                            CLM.L["You can only bench players from same roster as the raid (%s)."],
                            CLM.MODULES.RosterManager:GetRosterNameByUid(raid:Roster():UID())
                        ))
                        return
                    end

                    if CLM.MODULES.RaidManager:IsInProgressingRaid() then
                        if #profiles > 10 then
                            LOG:Message(string.format(
                                CLM.L["You can %s max %d players to standby at the same time to a %s raid."],
                                CLM.L["add"], 10, CLM.L["progressing"]
                            ))
                            return
                        end
                        CLM.MODULES.RaidManager:AddToStandby(CLM.MODULES.RaidManager:GetRaid(), profiles)
                    elseif CLM.MODULES.RaidManager:IsInCreatedRaid() then
                        if #profiles > 25 then
                            LOG:Message(string.format(
                                CLM.L["You can %s max %d players to standby at the same time to a %s raid."],
                                CLM.L["add"], 25, CLM.L["created"]
                            ))
                            return
                        end
                        for _, profile in ipairs(profiles) do
                            CLM.MODULES.StandbyStagingManager:AddToStandby(CLM.MODULES.RaidManager:GetRaid():UID(), profile:GUID())
                        end
                    end
                    refreshFn(true)
                    CLM.GUI.Unified:ClearSelection()
                end),
                trustedOnly = true,
                color = "eeee00"
            },
            {
                title = CLM.L["Remove from standby"],
                func = (function()
                    if not CLM.MODULES.RaidManager:IsInRaid() then
                        LOG:Message(CLM.L["Not in raid"])
                        return
                    end
                    local profiles = UnifiedGUI_Standings:GetSelection()
                    local raid = CLM.MODULES.RaidManager:GetRaid()
                    local roster = CLM.MODULES.RosterManager:GetRosterByUid(UnifiedGUI_Standings.roster)
                    if roster ~= raid:Roster() then
                        LOG:Message(string.format(
                            CLM.L["You can only remove from bench players from same roster as the raid (%s)."],
                            CLM.MODULES.RosterManager:GetRosterNameByUid(raid:Roster():UID())
                        ))
                        return
                    end

                    if CLM.MODULES.RaidManager:IsInProgressingRaid() then
                        if #profiles > 10 then
                            LOG:Message(string.format(
                                CLM.L["You can %s max %d players from standby at the same time to a %s raid."],
                                CLM.L["remove"], 10, CLM.L["progressing"]
                            ))
                            return
                        end
                        CLM.MODULES.RaidManager:RemoveFromStandby(CLM.MODULES.RaidManager:GetRaid(), profiles)
                    elseif CLM.MODULES.RaidManager:IsInCreatedRaid() then
                        if #profiles > 25 then
                            LOG:Message(string.format(
                                CLM.L["You can %s max %d players from standby at the same time to a %s raid."],
                                CLM.L["remove"], 25, CLM.L["created"]
                            ))
                            return
                        end
                        for _, profile in ipairs(profiles) do
                            CLM.MODULES.StandbyStagingManager:RemoveFromStandby(CLM.MODULES.RaidManager:GetRaid():UID(), profile:GUID())
                        end
                    end
                    refreshFn(true)
                    CLM.GUI.Unified:ClearSelection()
                end),
                trustedOnly = true,
                color = "eeee00"
            },
            {
                separator = true,
                trustedOnly = true
            },
            {
                title = CLM.L["Remove from roster"],
                func = (function(i)
                    local profiles = UnifiedGUI_Standings:GetSelection()
                    local roster = CLM.MODULES.RosterManager:GetRosterByUid(UnifiedGUI_Standings.roster)
                    if roster == nil then
                        LOG:Debug("UnifiedGUI_Standings(Remove): roster == nil")
                        return
                    end
                    if not profiles or #profiles == 0 then
                        LOG:Debug("UnifiedGUI_Standings(Remove): profiles == 0")
                        return
                    end
                    if #profiles > 10 then
                        LOG:Message(string.format(
                            CLM.L["You can remove max %d players from roster at the same time."],
                            10
                        ))
                        return
                    end
                    CLM.MODULES.RosterManager:RemoveProfilesFromRoster(roster, profiles)
                    refreshFn(true)
                    CLM.GUI.Unified:ClearSelection()
                end),
                trustedOnly = true,
                color = "cc0000"
            },
        },
        CLM.MODULES.ACL:CheckLevel(CONSTANTS.ACL.LEVEL.ASSISTANT),
        CLM.MODULES.ACL:CheckLevel(CONSTANTS.ACL.LEVEL.MANAGER)
    )
end

local function refreshHandler()
    local roster = CLM.MODULES.RosterManager:GetRosterByUid(UnifiedGUI_Standings.roster)
    if roster then
        if roster:GetPointType() == CONSTANTS.POINT_TYPE.EPGP then
            CLM.GUI.Unified:GetScrollingTable():SetDisplayCols(columnsEPGP)
        else
            CLM.GUI.Unified:GetScrollingTable():SetDisplayCols(columnsDKP)
        end
    end
end

local function beforeShowHandler()
    LOG:Trace("UnifiedGUI_Standings beforeShowHandler()")
    UnifiedGUI_Standings.context = CONSTANTS.ACTION_CONTEXT.ROSTER
    if CLM.MODULES.RaidManager:IsInRaid() then
        HandleRosterChange(CLM.MODULES.RaidManager:GetRaid():Roster():UID())
        UnifiedGUI_Standings.filter:SetFilterValue(CONSTANTS.FILTER.IN_RAID, true)
        UnifiedGUI_Standings.context = CONSTANTS.ACTION_CONTEXT.RAID
    end

    refreshHandler() -- this is actually here only for the structure update
end

local function storeHandler()
    LOG:Trace("UnifiedGUI_Standings storeHandler()")
    local storage = CLM.GUI.Unified:GetStorage(UnifiedGUI_Standings.name)
    storage.roster = UnifiedGUI_Standings.roster
end

local function restoreHandler()
    LOG:Trace("UnifiedGUI_Standings restoreHandler()")
    local storage = CLM.GUI.Unified:GetStorage(UnifiedGUI_Standings.name)
    HandleRosterChange(storage.roster)
end

local function dataReadyHandler()
    LOG:Trace("UnifiedGUI_Standings dataReadyHandler()")
    if not CLM.MODULES.RosterManager:GetRosterByUid(UnifiedGUI_Standings.roster) then
        local _, roster = next(CLM.MODULES.RosterManager:GetRosters())
        if roster then
            HandleRosterChange(roster:UID())
        end
    else
        HandleRosterChange(UnifiedGUI_Standings.roster) -- force update of data relying on roster
    end
end

CONSTANTS.ACTION_CONTEXT = {
    SELECTED = 1,
    ROSTER = 2,
    RAID = 3
}

CONSTANTS.ACTION_CONTEXT_GUI = {
    [CONSTANTS.ACTION_CONTEXT.SELECTED] = CLM.L["Selected"],
    [CONSTANTS.ACTION_CONTEXT.ROSTER] = CLM.L["Roster"],
    [CONSTANTS.ACTION_CONTEXT.RAID] = CLM.L["Raid"],
}

CONSTANTS.ACTION_CONTEXT_LIST = {
    CONSTANTS.ACTION_CONTEXT.SELECTED,
    CONSTANTS.ACTION_CONTEXT.ROSTER,
    CONSTANTS.ACTION_CONTEXT.RAID
}

CLM.GUI.Unified:RegisterTab(
    UnifiedGUI_Standings.name, 1,
    tableStructure,
    tableDataFeeder,
    nil,
    verticalOptionsFeeder,
    {
        initialize = initializeHandler,
        refresh = refreshHandler,
        beforeShow = beforeShowHandler,
        store = storeHandler,
        restore = restoreHandler,
        dataReady = dataReadyHandler
    }
)
