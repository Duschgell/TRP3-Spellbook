local _, addon = ...

addon.GameMasterLayoutEditor = {}

local editor
local optionsWindow
local draft
local draftSoundPreset
local draftIncomingSoundEnabled
local draftIncomingSoundPreset
local selectedModuleID
local previews = {}
function addon.GameMasterLayoutEditor.GetTutorialContext()
    return editor, optionsWindow, previews, selectedModuleID
end
local optionRows = {}
local suppressOptions = false
local sampleCache = {}
local registerSampleProfiles = {}
local sampleElapsed = 0
local sampleInterval = 40
local previewGroupSize = 5
local previewRefreshSeconds = 40
local pendingSampleRefresh = false
local pendingSampleRefreshDelay = 0
local COMPACT_PREVIEW_ROWS = 320
local SAMPLE_REFRESH_DEBOUNCE = 0.2

local function moduleAvailable(moduleID)
    return moduleID ~= "gameMaster" or not addon.Modules or addon.Modules.IsEnabled("gameMaster")
end

local sampleNames = {
    "Aelira Sonnenpfad",
    "Bran Eisenlied",
    "Yazrin",
    "Testtestst",
    "Yussif",
    "Mira Nachtwind",
    "Kael Dorn",
    "Lysandra",
}
local sampleSpells = {
    { icon = 135812, name = addon.L("LAYOUT_SAMPLE_SPELL_FIREBALL"), color = "FF7A22" },
    { icon = 135846, name = addon.L("LAYOUT_SAMPLE_SPELL_FROSTBOLT"), color = "55BFFF" },
    { icon = 136096, name = addon.L("LAYOUT_SAMPLE_SPELL_ARCANE_MISSILES"), color = "B067FF" },
    { icon = 136048, name = addon.L("LAYOUT_SAMPLE_SPELL_HOLY_LIGHT"), color = "FFE66B" },
    { icon = 136188, name = addon.L("LAYOUT_SAMPLE_SPELL_SHADOW_WORD"), color = "9966CC" },
    { icon = 136052, name = addon.L("LAYOUT_SAMPLE_SPELL_NATURE_GRASP"), color = "55D96B" },
    { icon = 132223, name = addon.L("LAYOUT_SAMPLE_SPELL_SHIELD_SLAM"), color = "D9C19A" },
    { icon = 132307, name = addon.L("LAYOUT_SAMPLE_SPELL_AIMED_SHOT"), color = "D98545" },
}
local sampleActions = {
    "GAMEMASTER_ACTION_CAST",
    "GAMEMASTER_ACTION_CHANNEL",
    "GAMEMASTER_ACTION_PREPARE",
}
local sampleTargets = {
    {
        color = "55D96B",
        label = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:14:14|t "
            .. addon.L("LAYOUT_SAMPLE_TARGET_RUNESTONE"),
    },
    {
        color = "F2C84B",
        label = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_2:14:14|t "
            .. addon.L("LAYOUT_SAMPLE_TARGET_FLAME_CIRCLE"),
    },
    {
        color = "E05A47",
        label = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_7:14:14|t "
            .. addon.L("LAYOUT_SAMPLE_TARGET_ASH_WOLF"),
    },
    { color = "67B7FF", label = "Mira Nachtwind" },
    { color = "D7B7FF", label = "Yussif" },
    { color = "F7D99A", label = "Aelira Sonnenpfad" },
}

local function choose(values)
    return values[math.random(1, #values)]
end

local function createSampleTargets()
    local targets = {}
    local count = math.random(1, 4)
    local offset = math.random(0, #sampleTargets - 1)
    for index = 1, count do
        local source = sampleTargets[
            ((offset + index - 1) % #sampleTargets) + 1
        ]
        targets[index] = {
            color = source.color,
            label = source.label,
        }
    end
    return targets
end

local function formatSampleTargets(targets)
    local labels = {}
    for _, target in ipairs(targets or {}) do
        labels[#labels + 1] = target.color
            and string.format("|cff%s%s|r", target.color, target.label)
            or target.label
    end
    return table.concat(labels, ", ")
end

local function setFontSize(fontString, size, offset)
    addon.GameMasterWidgets.SetFontSize(
        fontString,
        size,
        offset or 0
    )
end

local function setBackdrop(frame, background, border)
    frame:SetBackdropColor(
        background[1], background[2], background[3], background[4]
    )
    frame:SetBackdropBorderColor(
        border[1], border[2], border[3], border[4]
    )
end

local function setCheckLabel(check, text)
    check.Text:SetText(text)
    check.Text:SetTextColor(0.96, 0.87, 0.68, 1)
end

local function updateDraftLayout(moduleID, frame)
    local module = draft and draft[moduleID]
    if not module or not frame then
        return
    end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    if type(point) == "string" and type(relativePoint) == "string" then
        module.layout.point = point
        module.layout.relativePoint = relativePoint
        module.layout.x = tonumber(x) or 0
        module.layout.y = tonumber(y) or 0
    end
    module.layout.width = tonumber(frame:GetWidth()) or module.layout.width
    module.layout.height = tonumber(frame:GetHeight()) or module.layout.height
end

local function anchorTopLeft(frame)
    local left = frame:GetLeft()
    local top = frame:GetTop()
    if type(left) ~= "number" or type(top) ~= "number" then
        return false
    end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    return true
end

local function getFallbackProfile()
    local name = choose(sampleNames)
    local firstName, lastName = name:match("^(%S+)%s+(.+)$")
    firstName = firstName or name
    return {
        firstName = firstName,
        gameName = firstName .. "-DieAldor",
        lastName = lastName,
        rpName = name,
        title = "Mag.",
    }
end

local function createSample(moduleID)
    local sample = {
        entries = {},
        roundNumber = math.random(2, 8),
    }
    if moduleID == "gameMaster" or moduleID == "roundOverview" then
        for index = 1, previewGroupSize do
            local profile = #registerSampleProfiles > 0
                and choose(registerSampleProfiles) or getFallbackProfile()
            sample.entries[index] = {
                action = choose(sampleActions),
                firstName = profile.firstName,
                gameName = profile.gameName,
                lastName = profile.lastName,
                profileColor = profile.profileColor,
                profileIcon = profile.profileIcon,
                rpName = profile.rpName,
                spell = choose(sampleSpells),
                targets = createSampleTargets(),
                title = profile.title,
            }
        end
    elseif moduleID == "compactSpellbook" then
        local offset = math.random(0, #sampleSpells - 1)
        for index = 1, COMPACT_PREVIEW_ROWS do
            sample.entries[index] = sampleSpells[
                ((offset + index - 1) % #sampleSpells) + 1
            ]
        end
    else
        sample.action = choose(sampleActions)
        sample.spell = choose(sampleSpells)
        sample.targets = createSampleTargets()
        sample.targetCount = #sample.targets
    end
    return sample
end

local function clampPreviewGroupSize(value)
    return math.max(1, math.min(40, math.floor(tonumber(value) or 5)))
end
local function getSample(moduleID)
    if not sampleCache[moduleID] then
        sampleCache[moduleID] = createSample(moduleID)
    end
    return sampleCache[moduleID]
end

local function regenerateSamples()
    local refreshed = {}
    for _, moduleID in ipairs(addon.GameMasterLayout.GetModuleOrder()) do
        if moduleAvailable(moduleID) then refreshed[moduleID] = createSample(moduleID) end
    end
    sampleCache = refreshed
    sampleElapsed = 0
    sampleInterval = previewRefreshSeconds
end

local function getOwnCompactPreview()
    local book = addon.Database.GetActiveSpellbook()
    local entries = {}
    local tabNames = {}
    if type(book) ~= "table" then
        return entries, tabNames
    end
    for _, tabID in ipairs(book.tabOrder or {}) do
        local tab = type(book.tabs) == "table" and book.tabs[tabID] or nil
        if type(tab) == "table" then
            tabNames[#tabNames + 1] = tab.name or "?"
            for _, spellID in ipairs(tab.spellIds or {}) do
                local spell = type(book.spells) == "table"
                    and book.spells[spellID] or nil
                if type(spell) == "table" then
                    entries[#entries + 1] = {
                        color = spell.color,
                        icon = spell.icon,
                        name = spell.name or addon.L("UNKNOWN_ABILITY"),
                    }
                    if #entries >= COMPACT_PREVIEW_ROWS then
                        return entries, tabNames
                    end
                end
            end
        end
    end
    return entries, tabNames
end

local function getCompactPreviewEntries(module)
    if module.options.previewOwnData == true then
        local entries, tabNames = getOwnCompactPreview()
        if #entries > 0 then
            return entries, tabNames
        end
    end
    return getSample("compactSpellbook").entries, {
        addon.L("DEFAULT_TAB_NAME"),
        addon.L("LAYOUT_SAMPLE_TAB_COMBAT"),
    }
end

local function getPreviewLines(moduleID, module)
    local sample = getSample(moduleID)
    local lines = {}
    local icons = {}
    local secondaryIcons = {}
    local colors = {}
    if moduleID == "compactSpellbook" then
        local entries = getCompactPreviewEntries(module)
        for index, spell in ipairs(entries) do
            lines[index] = spell.name
            icons[index] = module.options.showIcons and spell.icon or nil
            colors[index] = spell.color
        end
    else
        lines[1] = sample.spell.name
        lines[2] = string.format(
            "%s | %s",
            addon.L(sample.action),
            formatSampleTargets(sample.targets)
        )
        lines[3] = addon.L("GAMEMASTER_SUBMISSION_ACCEPTED")
        icons[1] = module.options.showIcon and sample.spell.icon or nil
        colors[1] = sample.spell.color
    end
    return lines, icons, secondaryIcons, colors
end
local function getPreviewSubtitle(moduleID, module)
    local sample = getSample(moduleID)
    if moduleID == "gameMaster" then
        return string.format(
            "%s | %s | %s",
            addon.L("LAYOUT_SAMPLE_ENCOUNTER"),
            addon.L("GAMEMASTER_ASSISTANT_ROLE"),
            addon.L("LAYOUT_SAMPLE_ROUND", sample.roundNumber)
        )
    end
    if moduleID == "compactSpellbook" then
        local _, tabs = getCompactPreviewEntries(module)
        local tabText = table.concat(tabs, "  |  ", 1, math.min(2, #tabs))
        return addon.L("SEARCH_PLACEHOLDER")
            .. (#tabText > 0 and "  |  " .. tabText or "")
    end
    if moduleID == "roundOverview" then
        return addon.L("LAYOUT_SAMPLE_ROUND", sample.roundNumber)
    end
    return ""
end

local function getPreviewItemCount(moduleID, module)
    if moduleID == "compactSpellbook" then
        local entries = getCompactPreviewEntries(module)
        return #entries
    end
    if moduleID == "currentAction" then
        return 3
    end
    return #(getSample(moduleID).entries or {})
end

local function createPreviewRow(frame)
    local row = CreateFrame("Frame", nil, frame.content, "BackdropTemplate")
    row:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("LEFT", row, "LEFT", 3, 0)
    local secondaryIcon = row:CreateTexture(nil, "ARTWORK")
    local controlLabel = addon.UIFactory.CreateLabel(
        row, addon.Theme.Fonts.small, "", addon.Theme.Colors.textMuted
    )
    controlLabel:SetJustifyH("LEFT")
    controlLabel:SetJustifyV("MIDDLE")
    controlLabel:SetWordWrap(false)
    controlLabel:Hide()
    local label = addon.UIFactory.CreateLabel(
        row, addon.Theme.Fonts.small, "", addon.Theme.Colors.text
    )
    label:SetJustifyH("LEFT")
    label:SetJustifyV("MIDDLE")
    local version = addon.UIFactory.CreateLabel(
        row, addon.Theme.Fonts.small, "", addon.Theme.Colors.textMuted
    )
    version:SetJustifyH("RIGHT")
    version:SetJustifyV("MIDDLE")
    version:SetWordWrap(false)
    version:Hide()
    row.controlLabel = controlLabel
    row.icon = icon
    row.label = label
    row.secondaryIcon = secondaryIcon
    row.version = version
    row:Hide()
    frame.rows[#frame.rows + 1] = row
end

local function ensurePreviewRows(frame, count)
    count = math.max(0, math.floor(tonumber(count) or 0))
    while #frame.rows < count do
        createPreviewRow(frame)
    end
end

local function populateGameMasterRows(
    frame,
    module,
    metrics,
    style
)
    local entries = getSample("gameMaster").entries
    local fontSize = metrics.fontSize
    local actions = {
        GAMEMASTER_ACTION_CAST = "cast",
        GAMEMASTER_ACTION_CHANNEL = "channel",
        GAMEMASTER_ACTION_PREPARE = "prepare",
    }
    local showMoveButtons = addon.GameMasterStore
        and type(addon.GameMasterStore.IsOrderLocked) == "function"
        and not addon.GameMasterStore.IsOrderLocked()
        or false
    local showVersions = module.options.showVersions == true
    local participants = {}

    for index, entry in ipairs(entries) do
        local row = frame.rows[index]
        if not row.actionList then
            row.actionList = addon.GameMasterActionList.Create(row)
            for _, view in ipairs(row.actionList.views) do
                view.spell:EnableMouse(false)
                view.targets:EnableMouse(false)
            end
        end
        row.actionList.showIcons = true
        addon.GameMasterActionList.SetSubmission(row.actionList, {
            action = actions[entry.action],
            preparation = actions[entry.action] == "prepare"
                and { progress = 1, required = 2 }
                or nil,
            spell = {
                icon = entry.spell.icon,
                name = entry.spell.name,
                nameColor = entry.spell.color,
            },
            targets = entry.targets,
        })
        row.label:SetText(addon.GameMasterParticipantPresentation.FormatName(
            entry,
            module.options.nameMode
        ))
        row.controlLabel:SetText(
            tostring(index) .. "  X" .. (showMoveButtons and "  < >" or "")
        )
        row.version:SetText(showVersions
            and ("v" .. addon.Constants.ADDON_VERSION)
            or "")
        row.profileIcon = module.options.profileIcons and entry.profileIcon
        participants[index] = {
            buffHeight = 0,
            hasProfileIcon = row.profileIcon ~= nil
                and row.profileIcon ~= false,
            nameWidth = addon.GameMasterWidgets.MeasureTextWidth(
                row.label,
                row.label:GetText(),
                fontSize
            ),
        }
        row.secondaryIcon:Hide()
    end

    local actionLists = {}
    for index = 1, #entries do actionLists[index] = frame.rows[index].actionList end
    local planColumns = addon.GameMasterActionList.CreateColumnPlanner(actionLists, fontSize)
    local windowPlan = addon.GameMasterLayout.PlanGameMasterWindow({
        buttonHeight = addon.Theme.Sizes.buttonHeight,
        fontSize = fontSize,
        height = frame:GetHeight(),
        iconSize = metrics.iconSize,
        measureAction = function(index, actionWidth, size)
            return addon.GameMasterActionList.Measure(
                frame.rows[index].actionList,
                actionWidth,
                size,
                planColumns(actionWidth)
            )
        end,
        participants = participants,
        showMoveButtons = showMoveButtons,
        showVersions = showVersions,
        styleName = module.style,
        padding = metrics.padding,
        width = frame:GetWidth(),
    })
    local grid = windowPlan.participants
    frame.chromeLayout = windowPlan.chrome

    for index, row in ipairs(frame.rows) do
        local entry = entries[index]
        local position = grid.positions[index]
        local plan = grid.plans[index]
        row:SetShown(entry ~= nil and position ~= nil)
        if entry and position and plan then
            row:ClearAllPoints()
            row:SetPoint(
                "TOPLEFT",
                frame.content,
                "TOPLEFT",
                position.column * (grid.cardWidth + grid.gap),
                -position.offset
            )
            row:SetSize(grid.cardWidth, position.height)

            local headerTop = plan.buffHeight + 3
            local profileWidth = plan.profileIcon
                and plan.iconSize + 3
                or 0
            row.controlLabel:ClearAllPoints()
            row.controlLabel:SetPoint(
                "TOPLEFT", row, "TOPLEFT", 2, -headerTop
            )
            row.controlLabel:SetSize(
                math.max(20, plan.controlWidth - profileWidth - 4),
                plan.headerHeight
            )
            row.controlLabel:Show()
            setFontSize(row.controlLabel, math.max(8, fontSize - 2))

            row.icon:ClearAllPoints()
            row.icon:SetSize(plan.iconSize, plan.iconSize)
            row.icon:SetPoint(
                "TOPLEFT",
                row,
                "TOPLEFT",
                plan.controlWidth - plan.iconSize - 4,
                -headerTop
            )
            row.icon:SetShown(plan.profileIcon)
            if plan.profileIcon then
                addon.UIFactory.SetIconTexture(
                    row.icon,
                    row.profileIcon,
                    addon.Constants.DEFAULT_BOOK_ICON
                )
            end

            local versionWidth = showVersions and 31 or 0
            row.label:ClearAllPoints()
            row.label:SetPoint(
                "TOPLEFT",
                row,
                "TOPLEFT",
                plan.controlWidth,
                -headerTop
            )
            row.label:SetSize(
                math.max(
                    20,
                    plan.identityWidth - plan.controlWidth - versionWidth
                        - (showVersions and 6 or 3)
                ),
                plan.headerHeight
            )
            row.label:SetWordWrap(false)
            row.label:SetJustifyV("MIDDLE")
            setFontSize(row.label, fontSize)

            row.version:ClearAllPoints()
            row.version:SetShown(showVersions)
            if showVersions then
                row.version:SetPoint(
                    "TOPLEFT",
                    row,
                    "TOPLEFT",
                    plan.identityWidth - 34,
                    -headerTop
                )
                row.version:SetSize(31, plan.headerHeight)
                setFontSize(row.version, math.max(8, fontSize - 3))
            end

            row.actionList:ClearAllPoints()
            row.actionList:SetPoint(
                "TOPLEFT",
                row,
                "TOPLEFT",
                plan.actionLeft,
                -plan.actionTop
            )
            addon.GameMasterActionList.Layout(
                row.actionList,
                plan.actionWidth,
                fontSize,
                planColumns(plan.actionWidth)
            )
            addon.GameMasterActionList.ApplyStyle(
                row.actionList,
                style,
                module.showBorder
            )
            addon.UIFactory.SetFontColor(
                row.label,
                module.options.profileColors and entry.profileColor or nil,
                addon.Theme.Colors.text
            )
            setBackdrop(
                row,
                index % 2 == 0
                    and style.rowBackgroundEven
                    or style.rowBackgroundOdd,
                module.showBorder and style.rowBorder or { 0, 0, 0, 0 }
            )
        end
    end
    frame.content:SetHeight(grid.contentHeight)
    frame.scroll:UpdateScrollChildRect()
    addon.GameMasterWidgets.ClampScroll(frame.scroll, grid.contentHeight)
    frame.collectionMetrics = grid
    frame.participantLayout = grid
end

local function populateParticipantRows(frame, moduleID, module, metrics, width, height, style)
    if moduleID == "gameMaster" then
        populateGameMasterRows(
            frame,
            module,
            metrics,
            style
        )
        return
    end
    local entries = getSample(moduleID).entries
    local fontSize = metrics.fontSize
    local scale = fontSize / 12
    local actions = {
        GAMEMASTER_ACTION_CAST = "cast",
        GAMEMASTER_ACTION_CHANNEL = "channel",
        GAMEMASTER_ACTION_PREPARE = "prepare",
    }
    local sharedIdentityWidth = 0
    for index, entry in ipairs(entries) do
        local row = frame.rows[index]
        if not row.actionList then
            row.actionList = addon.GameMasterActionList.Create(row)
             
            for _, view in ipairs(row.actionList.views) do
                view.spell:EnableMouse(false)
                view.targets:EnableMouse(false)
            end
        end
        row.actionList.showIcons = moduleID == "gameMaster" or module.options.showIcons ~= false
        addon.GameMasterActionList.SetSubmission(row.actionList, {
            action = actions[entry.action], targets = entry.targets,
            spell = { name = entry.spell.name, icon = entry.spell.icon, nameColor = entry.spell.color },
            preparation = actions[entry.action] == "prepare" and { progress = 1, required = 2 } or nil,
        })
        row.label:SetText(string.format("%d. %s%s", index,
            addon.GameMasterParticipantPresentation.FormatName(entry, module.options.nameMode),
            moduleID == "gameMaster" and module.options.showVersions
                and ("  v" .. addon.Constants.ADDON_VERSION) or ""))
        row.profileIcon = moduleID == "gameMaster" and module.options.profileIcons and entry.profileIcon
        sharedIdentityWidth = math.max(sharedIdentityWidth,
            addon.GameMasterWidgets.MeasureTextWidth(row.label, row.label:GetText(), fontSize)
                + (row.profileIcon and metrics.iconSize + 4 or 0) + 2)
        row.secondaryIcon:Hide()
    end
    sharedIdentityWidth = math.max(80, math.min(250 * scale, sharedIdentityWidth))
    local actionLists = {}
    for index = 1, #entries do actionLists[index] = frame.rows[index].actionList end
    local planColumns = addon.GameMasterActionList.CreateColumnPlanner(actionLists, fontSize)
    local function measureCard(index, cardWidth)
        local row = frame.rows[index]
        local columns = addon.GameMasterLayout.GetParticipantCardColumns(cardWidth, {
            gap = 6, identityRatio = 0.2, inset = 6,
            maxIdentityWidth = sharedIdentityWidth, minIdentityWidth = math.min(135 * scale, sharedIdentityWidth),
            minDetailWidth = 260 * scale,
        })
        local iconInset = row.profileIcon and metrics.iconSize + 4 or 0
        local nameWidth = (columns.inline and columns.identityWidth or cardWidth - 12) - iconInset
        local nameHeight = addon.GameMasterWidgets.MeasureText(
            row.label, row.label:GetText(), nameWidth, fontSize, true
        )
        local identityHeight = math.max(nameHeight, row.profileIcon and metrics.iconSize or 0)
        local actionLeft = columns.inline and columns.detailLeft or 14
        local actionWidth = columns.inline and columns.detailWidth or math.max(1, cardWidth - actionLeft - 6)
        local actionHeight = addon.GameMasterActionList.Measure(
            row.actionList, actionWidth, fontSize, planColumns(actionWidth))
        return {
            nameLeft = 6 + iconInset, nameHeight = nameHeight,
            actionLeft = actionLeft, actionWidth = actionWidth,
            actionTop = columns.inline and 3 or identityHeight + 4,
            height = columns.inline and math.max(identityHeight, actionHeight) + 6
                or identityHeight + actionHeight + 8,
        }
    end
    local grid = addon.GameMasterWidgets.GetMeasuredGrid(
        width, height, #entries, fontSize, 350 * scale, 3,
        function(index, cardWidth) return measureCard(index, cardWidth).height end
    )
    for index, row in ipairs(frame.rows) do
        local entry, position = entries[index], grid.positions[index]
        row:SetShown(entry ~= nil and position ~= nil)
        if entry and position then
            local plan = measureCard(index, grid.cardWidth)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", frame.content, "TOPLEFT",
                position.column * (grid.cardWidth + grid.gap), -position.offset)
            row:SetSize(grid.cardWidth, position.height)
            row.label:SetPoint("TOPLEFT", row, "TOPLEFT", plan.nameLeft, -3)
            row.label:SetHeight(plan.nameHeight)
            row.label:SetJustifyV("TOP")
            row.icon:ClearAllPoints()
            row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -3)
            row.icon:SetSize(metrics.iconSize, metrics.iconSize)
            row.icon:SetShown(row.profileIcon ~= nil and row.profileIcon ~= false)
            if row.profileIcon then
                addon.UIFactory.SetIconTexture(row.icon, row.profileIcon, addon.Constants.DEFAULT_BOOK_ICON)
            end
            row.actionList:ClearAllPoints()
            row.actionList:SetPoint("TOPLEFT", row, "TOPLEFT", plan.actionLeft, -plan.actionTop)
            addon.GameMasterActionList.Layout(row.actionList, plan.actionWidth, fontSize,
                planColumns(plan.actionWidth))
            addon.GameMasterActionList.ApplyStyle(row.actionList, style, module.showBorder)
            addon.UIFactory.SetFontColor(row.label,
                module.options.profileColors and entry.profileColor or nil, addon.Theme.Colors.text)
            setBackdrop(row, index % 2 == 0 and style.rowBackgroundEven or style.rowBackgroundOdd,
                module.showBorder and style.rowBorder or { 0, 0, 0, 0 })
        end
    end
    frame.content:SetHeight(grid.contentHeight)
    frame.scroll:UpdateScrollChildRect()
    addon.GameMasterWidgets.ClampScroll(frame.scroll, grid.contentHeight)
    frame.collectionMetrics = grid
end

local function populatePreview(moduleID)
    local frame = previews[moduleID]
    if not moduleAvailable(moduleID) then
        if frame then frame:Hide() end
        return
    end
    local module = draft and draft[moduleID]
    if not frame or not module then
        return
    end
    local definition = addon.GameMasterLayout.GetDefinition(moduleID)
    local style = addon.Theme.GetGameMasterStyle(module.style)
    local metrics = addon.GameMasterWidgets.GetContentMetrics(
        moduleID, frame,
        module.fontSize,
        module.options,
        module.style
    )
    local red, green, blue = addon.UIFactory.GetColorRGB(module.previewColor)
    setBackdrop(frame, style.frameBackground, {
        red,
        green,
        blue,
        module.showBorder
            and (selectedModuleID == moduleID and 1 or 0.72)
            or 0,
    })
    frame.editTint:SetColorTexture(
        red,
        green,
        blue,
        module.style == "minimal" and 0.018 or 0.08
    )
    frame:SetAlpha(module.opacity / 100)

    local compact = moduleID == "compactSpellbook"
    local padding = metrics.padding
    local subtitleText = getPreviewSubtitle(moduleID, module)
    local headerHeight = compact and metrics.fontSize + 16
        or metrics.fontSize + 19
            + (subtitleText ~= "" and metrics.fontSize + 2 or 0)
    frame.title:ClearAllPoints()
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", padding, -6)
    frame.title:SetPoint("RIGHT", frame, "RIGHT", -padding, 0)
    frame.title:SetShown(not compact)
    frame.title:SetText(addon.L(definition.editorTitleKey or definition.titleKey))
    frame.subtitle:ClearAllPoints()
    if compact then
        frame.subtitle:SetPoint("TOPLEFT", frame, "TOPLEFT", padding, -9)
    else
        frame.subtitle:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -3)
    end
    frame.subtitle:SetPoint("RIGHT", frame, "RIGHT", -padding, 0)
    frame.subtitle:SetText(subtitleText)
    frame.subtitle:SetShown(compact or frame.subtitle:GetText() ~= "")

    setFontSize(frame.title, metrics.fontSize, 1)
    setFontSize(frame.subtitle, metrics.fontSize, -2)

    local contentWidth
    local contentHeight
    if moduleID == "gameMaster" then
        local chrome = addon.GameMasterLayout.GetGameMasterChromeLayout(
            frame:GetWidth(),
            frame:GetHeight(),
            padding,
            addon.Theme.Sizes.buttonHeight,
            metrics.fontSize
        )
        frame.chromeLayout = chrome
        frame.subtitle:ClearAllPoints()
        frame.subtitle:SetPoint("TOPLEFT", frame, "TOPLEFT", padding, -chrome.metadataTop)
        frame.subtitle:SetSize(chrome.metadataWidth, chrome.metadataLineHeight)
        frame.subtitle:SetText(addon.L("LAYOUT_SAMPLE_ENCOUNTER"))
        frame.gmRound:ClearAllPoints()
        frame.gmRound:SetPoint("TOPLEFT", frame, "TOPLEFT", padding,
            -chrome.metadataTop - chrome.metadataLineHeight)
        frame.gmRound:SetSize(chrome.metadataWidth, chrome.metadataLineHeight)
        frame.gmRound:SetText(addon.L("LAYOUT_SAMPLE_ROUND", getSample(moduleID).roundNumber))
        frame.gmRound:Show()
        setFontSize(frame.gmRound, metrics.fontSize, -2)
        local secondaryWidth = 197
        local secondaryLeft = chrome.compact and math.max(padding,
            math.floor((frame:GetWidth() - secondaryWidth) / 2))
            or frame:GetWidth() - padding - secondaryWidth
        for index, button in ipairs(frame.gmSecondaryButtons) do
            addon.UIFactory.ApplyButtonStyle(button, module.style)
            button:ClearAllPoints()
            button:SetSize(index == 1 and 105 or 88, addon.Theme.Sizes.buttonHeight)
            button:SetPoint("TOPLEFT", frame, "TOPLEFT",
                secondaryLeft + (index == 2 and 109 or 0), -chrome.secondaryTop)
            button:Show()
        end
        frame.gmHistory:ClearAllPoints()
        frame.gmHistory:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", padding, padding)
        frame.gmHistory:SetSize(math.max(1, frame:GetWidth() - padding * 2),
            addon.Theme.Sizes.buttonHeight)
        frame.gmHistory:SetText("<   " .. addon.L("GAMEMASTER_HISTORY_POSITION",
            getSample(moduleID).roundNumber, getSample(moduleID).roundNumber) .. "   >")
        frame.gmHistory:Show()
        setFontSize(frame.gmHistory, metrics.fontSize, -2)
        frame.gmControls:ClearAllPoints()
        frame.gmControls:SetPoint(
            "TOPLEFT", frame, "TOPLEFT", padding, -chrome.controlsTop
        )
        frame.gmControls:SetPoint(
            "TOPRIGHT", frame, "TOPRIGHT", -padding, -chrome.controlsTop
        )
        frame.gmControls:SetHeight(chrome.controlsHeight)
        frame.gmControls:Show()
        setBackdrop(
            frame.gmControls,
            style.rowBackgroundEven,
            module.showBorder and style.rowBorder or { 0, 0, 0, 0 }
        )
        for index, button in ipairs(frame.gmControlButtons) do
            addon.UIFactory.ApplyButtonStyle(button, module.style)
            local plan = chrome.controlButtons[index]
            button:ClearAllPoints()
            button:SetSize(plan.width, addon.Theme.Sizes.buttonHeight)
            button:SetPoint(
                "TOPLEFT",
                frame.gmControls,
                "TOPLEFT",
                plan.x,
                -plan.y
            )
            local label = type(button.GetFontString) == "function"
                and button:GetFontString()
                or nil
            if label then
                label:SetWidth(math.max(20, plan.width - 10))
                label:SetWordWrap(false)
                setFontSize(label, math.max(8, metrics.fontSize - 2))
            end
        end
        contentWidth = chrome.contentWidth
        contentHeight = chrome.contentHeight
    else
        frame.chromeLayout = nil
        frame.gmControls:Hide()
        frame.gmRound:Hide()
        frame.gmHistory:Hide()
        for _, button in ipairs(frame.gmSecondaryButtons) do button:Hide() end
        contentWidth = math.max(
            1,
            frame:GetWidth() - (padding * 2)
        )
        contentHeight = math.max(
            1,
            frame:GetHeight() - headerHeight - padding
        )
    end
    local itemCount = getPreviewItemCount(moduleID, module)
    ensurePreviewRows(frame, itemCount)
    frame.scroll:ClearAllPoints()
    if moduleID == "gameMaster" then
        local chrome = frame.chromeLayout
        frame.scroll:SetPoint(
            "TOPLEFT",
            frame,
            "TOPLEFT",
            chrome.contentLeft,
            -chrome.contentTop
        )
        frame.scroll:SetPoint(
            "BOTTOMRIGHT",
            frame,
            "BOTTOMRIGHT",
            -chrome.contentRight,
            chrome.contentBottom
        )
    else
        frame.scroll:SetPoint(
            "TOPLEFT", frame, "TOPLEFT", padding, -headerHeight
        )
        frame.scroll:SetPoint(
            "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -padding, padding
        )
    end
    frame.content:SetWidth(contentWidth)
    if moduleID == "gameMaster" or moduleID == "roundOverview" then
        populateParticipantRows(frame, moduleID, module, metrics, contentWidth, contentHeight, style)
        return
    end
    local fontSize = metrics.fontSize
    local minimumWidth = (compact and 155 or 270) * fontSize / 12
    local maximumColumns = compact and 5 or 1
    local lines, icons, secondaryIcons, colors = getPreviewLines(moduleID, module)
    local function textInset(icons, secondaryIcons, index)
        return 10 + (icons[index] and metrics.iconSize + 4 or 0)
            + (secondaryIcons[index] and metrics.iconSize + 4 or 0)
    end
    local grid = addon.GameMasterWidgets.GetMeasuredGrid(
        contentWidth, contentHeight, itemCount, fontSize,
        math.max(120, minimumWidth), maximumColumns,
        function(index, cardWidth)
            local measured = addon.GameMasterWidgets.MeasureText(
                frame.rows[index].label, lines[index],
                cardWidth - textInset(icons, secondaryIcons, index), fontSize, not compact
            )
            local hasIcon = icons[index] or secondaryIcons[index]
            return math.max(measured, hasIcon and metrics.iconSize or 0) + 6
        end
    )
    for index, row in ipairs(frame.rows) do
        local text = lines[index]
        local position = grid.positions[index]
        local visible = text ~= nil and position ~= nil
        row:SetShown(visible)
        if visible then
            row:ClearAllPoints()
            row:SetPoint(
                "TOPLEFT",
                frame.content,
                "TOPLEFT",
                position.column * (grid.cardWidth + grid.gap),
                -position.offset
            )
            row:SetSize(grid.cardWidth, position.height)
            local background = index % 2 == 0
                and style.rowBackgroundEven
                or style.rowBackgroundOdd
            row:SetBackdropColor(
                background[1], background[2], background[3], background[4]
            )
            local rowBorder = module.showBorder
                and style.rowBorder or { 0, 0, 0, 0 }
            row:SetBackdropBorderColor(
                rowBorder[1], rowBorder[2], rowBorder[3], rowBorder[4]
            )
            local primarySize = metrics.iconSize
            row.icon:SetSize(primarySize, primarySize)
            row.icon:SetShown(icons[index] ~= nil)
            if icons[index] then
                addon.UIFactory.SetIconTexture(
                    row.icon, icons[index], addon.Constants.DEFAULT_BOOK_ICON
                )
            end
            local secondarySize = metrics.iconSize
            row.secondaryIcon:SetSize(secondarySize, secondarySize)
            row.secondaryIcon:SetShown(secondaryIcons[index] ~= nil)
            if secondaryIcons[index] then
                addon.UIFactory.SetIconTexture(
                    row.secondaryIcon,
                    secondaryIcons[index],
                    addon.Constants.DEFAULT_BOOK_ICON
                )
            end
            row.secondaryIcon:ClearAllPoints()
            local iconAnchor = row
            local iconPoint = "LEFT"
            if icons[index] then
                iconAnchor = row.icon
                iconPoint = "RIGHT"
            end
            row.secondaryIcon:SetPoint("LEFT", iconAnchor, iconPoint, 3, 0)
            local inset = textInset(icons, secondaryIcons, index)
            local measured = addon.GameMasterWidgets.MeasureText(
                row.label, text, grid.cardWidth - inset,
                grid.fontSize, not compact
            )
            row.label:SetPoint("TOPLEFT", row, "TOPLEFT", inset - 5, -3)
            row.label:SetHeight(measured)
            row.label:SetJustifyV("TOP")
            addon.UIFactory.SetFontColor(
                row.label, colors[index], addon.Theme.Colors.text
            )
        end
    end
    frame.content:SetHeight(math.max(1, grid.contentHeight))
    frame.scroll:UpdateScrollChildRect()
    addon.GameMasterWidgets.ClampScroll(frame.scroll, grid.contentHeight)
    frame.collectionMetrics = grid
end
local function applyPreviewLayout(moduleID)
    local frame = previews[moduleID]
    if not moduleAvailable(moduleID) then
        if frame then frame:Hide() end
        return
    end
    local module = draft and draft[moduleID]
    if not frame or not module then
        return
    end
    local layout = module.layout
    frame:ClearAllPoints()
    local positioned = pcall(
        frame.SetPoint,
        frame,
        layout.point,
        UIParent,
        layout.relativePoint,
        layout.x,
        layout.y
    )
    if not positioned then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER")
    end
    frame:SetSize(layout.width, layout.height)
    frame:SetShown(module.editorVisible == true)
    populatePreview(moduleID)
end

local function refreshAllPreviews()
    for _, moduleID in ipairs(addon.GameMasterLayout.GetModuleOrder()) do
        applyPreviewLayout(moduleID)
    end
end

local function refreshPreviewContent()
    for _, moduleID in ipairs(addon.GameMasterLayout.GetModuleOrder()) do
        populatePreview(moduleID)
    end
end
local function createPreview(moduleID)
    local definition = addon.GameMasterLayout.GetDefinition(moduleID)
    local frame = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(20)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetClipsChildren(true)
    frame:RegisterForClicks("LeftButtonUp")
    frame:RegisterForDrag("LeftButton")
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 2,
    })
    if type(frame.SetResizeBounds) == "function" then
        frame:SetResizeBounds(
            definition.minWidth,
            definition.minHeight,
            definition.maxWidth,
            definition.maxHeight
        )
    else
        frame:SetMinResize(definition.minWidth, definition.minHeight)
        frame:SetMaxResize(definition.maxWidth, definition.maxHeight)
    end

    local editTint = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
    editTint:SetAllPoints()

    local title = addon.UIFactory.CreateLabel(
        frame,
        addon.Theme.Fonts.header,
        "",
        addon.Theme.Colors.gold
    )
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -8)
    title:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
    title:SetWordWrap(false)
    title:SetJustifyH("LEFT")

    local subtitle = addon.UIFactory.CreateLabel(
        frame,
        addon.Theme.Fonts.small,
        "",
        addon.Theme.Colors.textMuted
    )
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    subtitle:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
    subtitle:SetWordWrap(false)
    subtitle:SetJustifyH("LEFT")

    local gmControls = addon.GameMasterWidgets.CreateSection(frame)
    gmControls:Hide()
    local gmRound = addon.UIFactory.CreateLabel(frame, addon.Theme.Fonts.small,
        "", addon.Theme.Colors.textMuted)
    gmRound:SetWordWrap(false)
    local gmHistory = addon.UIFactory.CreateLabel(frame, addon.Theme.Fonts.small,
        "", addon.Theme.Colors.textMuted)
    gmHistory:SetWordWrap(false)
    local gmSecondaryButtons = {}
    for _, key in ipairs({ "GAMEMASTER_ASSISTANTS_BUTTON", "GAMEMASTER_SESSIONS" }) do
        local button = addon.UIFactory.CreateButton(frame, addon.L(key), 90)
        button:EnableMouse(false)
        gmSecondaryButtons[#gmSecondaryButtons + 1] = button
    end
    local gmControlButtons = {}
    local controlKeys = {
        "GAMEMASTER_START_ROUND",
        "GAMEMASTER_LOCK_ACTIONS",
        "GAMEMASTER_UNLOCK_ORDER",
        "GAMEMASTER_STOP",
    }
    for index, key in ipairs(controlKeys) do
        local button = addon.UIFactory.CreateButton(
            gmControls,
            addon.L(key),
            80
        )
        button:EnableMouse(false)
        gmControlButtons[index] = button
    end

    local rows = {}
    local scroll = addon.GameMasterWidgets.CreateScrollViewport(frame)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    local resize = CreateFrame("Button", nil, frame)
    resize:SetSize(18, 18)
    resize:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    local resizeTexture = resize:CreateTexture(nil, "ARTWORK")
    resizeTexture:SetAllPoints()
    resizeTexture:SetTexture(
        "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"
    )

    frame:SetScript("OnSizeChanged", function(self)
        if draft and draft[moduleID] and self:IsShown() then
            populatePreview(moduleID)
        end
    end)
    frame:SetScript("OnDragStart", function(self)
        selectedModuleID = moduleID
        populatePreview(moduleID)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        updateDraftLayout(moduleID, self)
    end)
    frame:SetScript("OnClick", function()
        addon.GameMasterLayoutEditor.SelectModule(moduleID)
    end)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(addon.L(definition.editorTitleKey or definition.titleKey), 1, 0.82, 0)
        GameTooltip:AddLine(addon.L(definition.audienceKey), 0.78, 0.72, 0.62, true)
        GameTooltip:AddLine(addon.L("LAYOUT_EDITOR_CLICK_HINT"), 1, 1, 1)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    resize:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then
            return
        end
        selectedModuleID = moduleID
        populatePreview(moduleID)
        anchorTopLeft(frame)
        frame:StartSizing("BOTTOMRIGHT", true)
    end)
    resize:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        updateDraftLayout(moduleID, frame)
        populatePreview(moduleID)
    end)

    frame.editTint = editTint
    frame.gmControlButtons = gmControlButtons
    frame.gmControls = gmControls
    frame.gmRound = gmRound
    frame.gmHistory = gmHistory
    frame.gmSecondaryButtons = gmSecondaryButtons
    frame.scroll = scroll
    frame.content = content
    frame.rows = rows
    frame.subtitle = subtitle
    frame.title = title
    frame.resize = resize
    previews[moduleID] = frame
    return frame
end

local function createSlider(parent, labelText, minimum, maximum, step)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(390, 48)
    local label = addon.UIFactory.CreateLabel(
        holder,
        addon.Theme.Fonts.body,
        labelText,
        addon.Theme.Colors.text
    )
    label:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    local valueLabel = addon.UIFactory.CreateLabel(
        holder,
        addon.Theme.Fonts.small,
        "",
        addon.Theme.Colors.gold
    )
    valueLabel:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 0)
    local slider = CreateFrame("Slider", nil, holder, "OptionsSliderTemplate")
    for _, region in ipairs({ slider:GetRegions() }) do
        if type(region.GetObjectType) == "function"
            and region:GetObjectType() == "FontString"
        then
            region:Hide()
        end
    end
    slider:SetPoint("TOPLEFT", holder, "TOPLEFT", 4, -22)
    slider:SetPoint("RIGHT", holder, "RIGHT", -4, 0)
    slider:SetHeight(16)
    slider:SetMinMaxValues(minimum, maximum)
    slider:SetValueStep(step)
    if type(slider.SetObeyStepOnDrag) == "function" then
        slider:SetObeyStepOnDrag(true)
    end
    slider.valueLabel = valueLabel
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor((value / step) + 0.5) * step
        self.valueLabel:SetText(tostring(value))
        if value == self.lastNotifiedValue then
            return
        end
        self.lastNotifiedValue = value
        if not suppressOptions and type(self.onChanged) == "function" then
            self.onChanged(value)
        end
    end)
    return holder, slider
end

local function createOptionCheck(parent, labelText)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    setCheckLabel(check, labelText)
    return check
end

local function updateSelectedPreview()
    if selectedModuleID then
        populatePreview(selectedModuleID)
    end
end

local function createStyleSelector(parent)
    local theme = addon.Theme
    local selector = CreateFrame("Frame", nil, parent)
    selector:SetSize(210, theme.Sizes.buttonHeight)
    selector.value = nil

    local modern = addon.UIFactory.CreateButton(
        selector, addon.L("GAMEMASTER_COMPACT_STYLE_MODERN"), 103
    )
    modern:SetPoint("LEFT", selector, "LEFT", 0, 0)

    local minimal = addon.UIFactory.CreateButton(
        selector, addon.L("GAMEMASTER_COMPACT_STYLE_MINIMAL"), 103
    )
    minimal:SetPoint("RIGHT", selector, "RIGHT", 0, 0)

    selector.buttons = {
        modern = modern,
        minimal = minimal,
    }

    function selector:SetValue(value, silent)
        if value ~= "modern" and value ~= "minimal" then
            value = "modern"
        end
        self.value = value
        for styleName, button in pairs(self.buttons) do
            local selected = styleName == value
            if selected then
                button:LockHighlight()
            else
                button:UnlockHighlight()
            end
            local fontString = button:GetFontString()
            if fontString then
                local color = selected and theme.Colors.gold or theme.Colors.text
                fontString:SetTextColor(
                    color[1], color[2], color[3], color[4] or 1
                )
            end
        end
        if not silent and type(self.onValueChanged) == "function" then
            self.onValueChanged(value)
        end
    end

    function selector:GetValue()
        return self.value
    end

    function selector:SetOnValueChanged(callback)
        self.onValueChanged = callback
    end

    modern:SetScript("OnClick", function()
        selector:SetValue("modern")
    end)
    minimal:SetScript("OnClick", function()
        selector:SetValue("minimal")
    end)
    selector:SetValue("modern", true)
    return selector
end

local function createOptionsWindow()
    local theme = addon.Theme
    local frame = addon.UIFactory.CreateDialog(
        addon.L("LAYOUT_EDITOR_OPTIONS"),
        440,
        560
    )
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(100)

    local styleLabel = addon.UIFactory.CreateLabel(
        frame, theme.Fonts.body, addon.L("LAYOUT_EDITOR_STYLE"), theme.Colors.text
    )
    styleLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -48)
    local style = createStyleSelector(frame)
    style:SetPoint("LEFT", styleLabel, "RIGHT", 16, 0)
    style:SetOnValueChanged(function(value)
        if suppressOptions or not selectedModuleID or not value then
            return
        end
        draft[selectedModuleID].style = value
        updateSelectedPreview()
    end)

    local opacityHolder, opacity = createSlider(
        frame, addon.L("LAYOUT_EDITOR_OPACITY"), 20, 100, 5
    )
    opacityHolder:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -88)
    opacity.onChanged = function(value)
        draft[selectedModuleID].opacity = value
        updateSelectedPreview()
    end

    local fontHolder, fontSize = createSlider(
        frame, addon.L("LAYOUT_EDITOR_FONT_SIZE"), 9, 20, 1
    )
    fontHolder:SetPoint("TOPLEFT", opacityHolder, "BOTTOMLEFT", 0, -4)
    fontSize.onChanged = function(value)
        draft[selectedModuleID].fontSize = value
        updateSelectedPreview()
    end

    local colorLabel = addon.UIFactory.CreateLabel(
        frame, theme.Fonts.body, addon.L("LAYOUT_EDITOR_PREVIEW_COLOR"), theme.Colors.text
    )
    colorLabel:SetPoint("TOPLEFT", fontHolder, "BOTTOMLEFT", 0, -10)
    local color = addon.UIFactory.CreateColorButton(frame)
    color:SetPoint("LEFT", colorLabel, "RIGHT", 16, 0)
    color:SetScript("OnClick", function()
        local module = selectedModuleID and draft[selectedModuleID]
        if not module then return end
        addon.TRP3Bridge.OpenColorPicker(
            module.previewColor,
            function(value)
                module.previewColor = value
                addon.UIFactory.SetColorButton(color, value)
                updateSelectedPreview()
            end,
            nil,
            frame
        )
    end)

    local border = createOptionCheck(
        frame, addon.L("LAYOUT_EDITOR_SHOW_BORDER")
    )
    border:SetPoint("TOPLEFT", colorLabel, "BOTTOMLEFT", -4, -14)
    border:SetScript("OnClick", function(self)
        if not suppressOptions and selectedModuleID then
            draft[selectedModuleID].showBorder = self:GetChecked() == true
            updateSelectedPreview()
        end
    end)
    local autoOpen = createOptionCheck(
        frame, addon.L("LAYOUT_EDITOR_AUTO_OPEN")
    )
    autoOpen:SetPoint("TOPLEFT", border, "BOTTOMLEFT", 0, -4)
    autoOpen:SetScript("OnClick", function(self)
        if not suppressOptions and selectedModuleID then
            draft[selectedModuleID].autoOpen = self:GetChecked() == true
        end
    end)


    local autoFontSize = createOptionCheck(
        frame, addon.L("LAYOUT_EDITOR_AUTO_FONT_SIZE")
    )
    autoFontSize:SetPoint("TOPLEFT", autoOpen, "BOTTOMLEFT", 0, -4)
    autoFontSize:SetScript("OnClick", function(self)
        if not suppressOptions and selectedModuleID then
            draft[selectedModuleID].options.autoFontSize =
                self:GetChecked() == true
            updateSelectedPreview()
        end
    end)
    local specificStart = CreateFrame("Frame", nil, frame)
    specificStart:SetPoint("TOPLEFT", autoFontSize, "BOTTOMLEFT", 4, -10)
    specificStart:SetSize(390, 156)
    local contentLabel = addon.UIFactory.CreateLabel(
        frame,
        addon.Theme.Fonts.body,
        addon.L("LAYOUT_EDITOR_CONTENT_OPTIONS"),
        addon.Theme.Colors.gold
    )
    contentLabel:SetPoint("TOPLEFT", specificStart, "TOPLEFT", 0, 0)
    local checks = {
        autoCompleteTurn = createOptionCheck(
            frame, addon.L("LAYOUT_EDITOR_AUTO_COMPLETE_TURN")
        ),
        notifyTurn = createOptionCheck(
            frame, addon.L("LAYOUT_EDITOR_NOTIFY_TURN")
        ),
        previewOwnData = createOptionCheck(
            frame, addon.L("LAYOUT_EDITOR_PREVIEW_OWN_SPELLS")
        ),
        showVersions = createOptionCheck(frame, addon.L("LAYOUT_EDITOR_SHOW_VERSIONS")),
        showIcons = createOptionCheck(frame, addon.L("LAYOUT_EDITOR_SHOW_ICONS")),
        profileColors = createOptionCheck(frame, addon.L("LAYOUT_EDITOR_PROFILE_COLORS")),
        profileIcons = createOptionCheck(frame, addon.L("LAYOUT_EDITOR_PROFILE_ICONS")),
        turnSound = createOptionCheck(
            frame, addon.L("LAYOUT_EDITOR_TURN_SOUND")
        ),
    }
    checks.showVersions:SetPoint("TOPLEFT", specificStart, "TOPLEFT", -4, -24)
    checks.showIcons:SetPoint("TOPLEFT", specificStart, "TOPLEFT", -4, -24)
    checks.previewOwnData:SetPoint("TOPLEFT", specificStart, "TOPLEFT", -4, -54)
    checks.profileColors:SetPoint("TOPLEFT", specificStart, "TOPLEFT", -4, -54)
    checks.profileIcons:SetPoint("TOPLEFT", specificStart, "TOPLEFT", -4, -84)
    checks.autoCompleteTurn:SetPoint("TOPLEFT", specificStart, "TOPLEFT", -4, -54)
    checks.notifyTurn:SetPoint("TOPLEFT", specificStart, "TOPLEFT", -4, -84)
    checks.turnSound:SetPoint("TOPLEFT", specificStart, "TOPLEFT", -4, -114)
    for key, check in pairs(checks) do
        check:SetScript("OnClick", function(self)
            if not suppressOptions and selectedModuleID then
                local optionKey = key
                if selectedModuleID == "currentAction"
                    and key == "showIcons"
                then
                    optionKey = "showIcon"
                end
                draft[selectedModuleID].options[optionKey] =
                    self:GetChecked() == true
                updateSelectedPreview()
            end
        end)
    end

    local nameLabel = addon.UIFactory.CreateLabel(
        frame, theme.Fonts.body, addon.L("LAYOUT_EDITOR_NAME_MODE"), theme.Colors.text
    )
    nameLabel:SetPoint("TOPLEFT", specificStart, "TOPLEFT", 0, -118)
    local nameMode = addon.GameMasterWidgets.CreateSelector(frame, 220)
    nameMode:SetPoint("LEFT", nameLabel, "RIGHT", 12, 0)
    nameMode:SetOptions({
        { label = addon.L("GAMEMASTER_NAME_MODE_ENGINE"), value = "engine" },
        { label = addon.L("GAMEMASTER_NAME_MODE_TRP_TITLE"), value = "trp_title" },
        { label = addon.L("GAMEMASTER_NAME_MODE_TRP_FULL"), value = "trp_full" },
        { label = addon.L("GAMEMASTER_NAME_MODE_TRP_FIRST"), value = "trp_first" },
        { label = addon.L("GAMEMASTER_NAME_MODE_TRP_LAST"), value = "trp_last" },
    }, "trp_full")
    nameMode:SetOnValueChanged(function(value)
        if not suppressOptions and selectedModuleID and value then
            draft[selectedModuleID].options.nameMode = value
            updateSelectedPreview()
        end
    end)

    local soundPreset = addon.GameMasterWidgets.CreateSelector(frame, 168)
    soundPreset:SetPoint("TOPLEFT", specificStart, "TOPLEFT", 0, -147)
    soundPreset:SetOptions(addon.GameMasterTurnSound and addon.GameMasterTurnSound.GetPresets()
        or { { label = addon.L("GAMEMASTER_TURN_SOUND_READY"), value = "ready" } }, "ready")
    soundPreset:SetOnValueChanged(function(value)
        if not suppressOptions and selectedModuleID == "currentAction" then draftSoundPreset = value end
    end)
    local soundPreview = addon.UIFactory.CreateButton(frame, addon.L("GAMEMASTER_TURN_SOUND_PREVIEW"), 100)
    soundPreview:SetPoint("LEFT", soundPreset, "RIGHT", 8, 0)
    soundPreview:SetScript("OnClick", function()
        if selectedModuleID == "currentAction" and addon.GameMasterTurnSound then
            addon.GameMasterTurnSound.Play(draftSoundPreset, "preview")
        end
    end)
    local incomingSound = createOptionCheck(frame, addon.L("LAYOUT_EDITOR_INCOMING_SOUND"))
    incomingSound:SetPoint("TOPLEFT", specificStart, "TOPLEFT", -4, -184)
    incomingSound:SetScript("OnClick", function(self)
        if not suppressOptions and selectedModuleID == "currentAction" then
            draftIncomingSoundEnabled = self:GetChecked() == true
        end
    end)
    local incomingPreset = addon.GameMasterWidgets.CreateSelector(frame, 168)
    incomingPreset:SetPoint("TOPLEFT", specificStart, "TOPLEFT", 0, -217)
    incomingPreset:SetOptions(addon.GameMasterTurnSound and addon.GameMasterTurnSound.GetPresets()
        or { { label = addon.L("GAMEMASTER_TURN_SOUND_READY"), value = "ready" } }, "ready")
    incomingPreset:SetOnValueChanged(function(value)
        if not suppressOptions and selectedModuleID == "currentAction" then draftIncomingSoundPreset = value end
    end)
    local incomingPreview = addon.UIFactory.CreateButton(frame, addon.L("GAMEMASTER_TURN_SOUND_PREVIEW"), 100)
    incomingPreview:SetPoint("LEFT", incomingPreset, "RIGHT", 8, 0)
    incomingPreview:SetScript("OnClick", function()
        if selectedModuleID == "currentAction" and addon.GameMasterTurnSound then
            addon.GameMasterTurnSound.Play(draftIncomingSoundPreset, "preview")
        end
    end)
    local function browseSound(incoming, selector)
        if selectedModuleID ~= "currentAction" or not draft or not addon.SoundBrowser then return end
        local currentDraft = draft
        addon.SoundBrowser.Open(incoming and draftIncomingSoundPreset or draftSoundPreset, function(value)
            if incoming then draftIncomingSoundPreset = value else draftSoundPreset = value end
            selector:SetOptions(addon.GameMasterTurnSound.GetPresets(value), value)
        end, {
            owner = frame,
            isValid = function()
                return draft == currentDraft and selectedModuleID == "currentAction"
                    and frame:IsShown() and editor and editor:IsShown()
            end,
        })
    end
    local soundBrowse = addon.UIFactory.CreateButton(frame, addon.L("SOUND_BROWSER_OPEN"), 106)
    soundBrowse:SetPoint("LEFT", soundPreview, "RIGHT", 8, 0)
    soundBrowse:SetScript("OnClick", function() browseSound(false, soundPreset) end)
    local incomingBrowse = addon.UIFactory.CreateButton(frame, addon.L("SOUND_BROWSER_OPEN"), 106)
    incomingBrowse:SetPoint("LEFT", incomingPreview, "RIGHT", 8, 0)
    incomingBrowse:SetScript("OnClick", function() browseSound(true, incomingPreset) end)
    frame:HookScript("OnHide", function()
        if addon.SoundBrowser then addon.SoundBrowser.Close(frame) end
        if addon.GameMasterTurnSound then addon.GameMasterTurnSound.Stop("preview") end
    end)

    local reset = addon.UIFactory.CreateButton(
        frame, addon.L("LAYOUT_EDITOR_RESET"), 220
    )
    reset:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 16)
    reset:SetScript("OnClick", function()
        if not selectedModuleID then return end
        if selectedModuleID == "currentAction" then
            draftSoundPreset, draftIncomingSoundPreset = "ready", "ready"
            draftIncomingSoundEnabled = false
        end
        draft[selectedModuleID] = addon.GameMasterLayout.GetDefaultModule(
            selectedModuleID
        )
        applyPreviewLayout(selectedModuleID)
        addon.GameMasterLayoutEditor.SelectModule(selectedModuleID, true)
    end)

    frame.autoFontSize = autoFontSize
    frame.autoOpen = autoOpen
    frame.border = border
    frame.checks = checks
    frame.color = color
    frame.fontSize = fontSize
    frame.nameLabel = nameLabel
    frame.nameMode = nameMode
    frame.opacity = opacity
    frame.specificStart = specificStart
    frame.style = style
    frame.soundPreset = soundPreset
    frame.soundPreview = soundPreview
    frame.soundBrowse = soundBrowse
    frame.incomingSound = incomingSound
    frame.incomingPreset = incomingPreset
    frame.incomingPreview = incomingPreview
    frame.incomingBrowse = incomingBrowse
    return frame
end

local function refreshOptions(moduleID)
    optionsWindow = optionsWindow or createOptionsWindow()
    local module = draft[moduleID]
    local definition = addon.GameMasterLayout.GetDefinition(moduleID)
    suppressOptions = true
    optionsWindow:SetHeight(moduleID == "currentAction" and 670 or 560)
    optionsWindow.soundPreset:Hide()
    optionsWindow.soundPreview:Hide()
    optionsWindow.soundBrowse:Hide()
    optionsWindow.incomingSound:Hide()
    optionsWindow.incomingPreset:Hide()
    optionsWindow.incomingPreview:Hide()
    optionsWindow.incomingBrowse:Hide()
    optionsWindow.title:SetText(string.format(
        "%s - %s",
        addon.L(definition.editorTitleKey or definition.titleKey),
        addon.L("LAYOUT_EDITOR_OPTIONS")
    ))
    optionsWindow.style:SetValue(module.style, true)
    optionsWindow.opacity:SetValue(module.opacity)
    optionsWindow.fontSize:SetValue(module.fontSize)
    addon.UIFactory.SetColorButton(optionsWindow.color, module.previewColor)
    optionsWindow.border:SetChecked(module.showBorder)
    optionsWindow.autoOpen:SetChecked(module.autoOpen)

    optionsWindow.autoFontSize:SetChecked(
        module.options.autoFontSize ~= false
    )
    for key, check in pairs(optionsWindow.checks) do
        check:SetChecked(module.options[key] == true)
        check:Hide()
    end
    optionsWindow.nameLabel:Hide()
    optionsWindow.nameMode:Hide()
    if moduleID == "gameMaster" then
        optionsWindow.checks.showVersions:Show()
        optionsWindow.checks.profileColors:Show()
        optionsWindow.checks.profileIcons:Show()
        optionsWindow.nameLabel:Show()
        optionsWindow.nameMode:Show()
        optionsWindow.nameMode:SetValue(module.options.nameMode, true)
    elseif moduleID == "compactSpellbook" then
        optionsWindow.checks.showIcons:Show()
        optionsWindow.checks.previewOwnData:Show()
    elseif moduleID == "roundOverview" then
        optionsWindow.checks.showIcons:Show()
        optionsWindow.checks.profileColors:Show()
        optionsWindow.nameLabel:Show()
        optionsWindow.nameMode:Show()
        optionsWindow.nameMode:SetValue(module.options.nameMode, true)
    else
        optionsWindow.checks.showIcons:Show()
        optionsWindow.checks.showIcons:SetChecked(module.options.showIcon == true)
        optionsWindow.checks.autoCompleteTurn:Show()
        optionsWindow.checks.notifyTurn:Show()
        optionsWindow.checks.turnSound:Show()
        optionsWindow.soundPreset:SetOptions(addon.GameMasterTurnSound.GetPresets(draftSoundPreset), draftSoundPreset or "ready")
        optionsWindow.soundPreset:Show()
        optionsWindow.soundPreview:Show()
        optionsWindow.soundBrowse:Show()
        optionsWindow.incomingSound:SetChecked(draftIncomingSoundEnabled == true)
        optionsWindow.incomingPreset:SetOptions(addon.GameMasterTurnSound.GetPresets(draftIncomingSoundPreset), draftIncomingSoundPreset or "ready")
        optionsWindow.incomingSound:Show()
        optionsWindow.incomingPreset:Show()
        optionsWindow.incomingPreview:Show()
        optionsWindow.incomingBrowse:Show()
    end
    suppressOptions = false
    if not optionsWindow.hasInitialPosition then
        optionsWindow:ClearAllPoints()
        optionsWindow:SetPoint("LEFT", editor, "RIGHT", 10, 0)
        optionsWindow.hasInitialPosition = true
    end
    optionsWindow:Show()
    addon.UIFactory.BringToFront(optionsWindow)
end

local function setPreviewGroupSize(value, refresh)
    local nextSize = clampPreviewGroupSize(value)
    local changed = nextSize ~= previewGroupSize
    previewGroupSize = nextSize
    if editor and editor.groupSizeSlider
        and math.floor(editor.groupSizeSlider:GetValue() + 0.5)
            ~= previewGroupSize
    then
        suppressOptions = true
        editor.groupSizeSlider:SetValue(previewGroupSize)
        suppressOptions = false
    end
    if refresh and changed then
        pendingSampleRefresh = true
        pendingSampleRefreshDelay = SAMPLE_REFRESH_DEBOUNCE
    end
end

local function setPreviewRefreshSeconds(value)
    previewRefreshSeconds = math.max(
        10,
        math.min(60, math.floor((tonumber(value) or 40) / 5 + 0.5) * 5)
    )
    sampleInterval = previewRefreshSeconds
    sampleElapsed = 0
end
local function closeEditor(save)
    pendingSampleRefresh = false
    pendingSampleRefreshDelay = 0
    if save and draft then
        if addon.GameMasterPlayerState.SetTurnSoundPreset then
            addon.GameMasterPlayerState.SetTurnSoundPreset(draftSoundPreset or "ready")
        end
        if addon.GameMasterPlayerState.SetIncomingActionSoundPreset then
            addon.GameMasterPlayerState.SetIncomingActionSoundPreset(draftIncomingSoundPreset or "ready")
            addon.GameMasterPlayerState.SetIncomingActionSoundEnabled(draftIncomingSoundEnabled)
        end
        addon.GameMasterLayout.Commit(
            draft,
            previewGroupSize,
            previewRefreshSeconds
        )
    end
    for _, frame in pairs(previews) do
        frame:Hide()
    end
    if optionsWindow then optionsWindow:Hide() end
    if editor then editor:Hide() end
    selectedModuleID = nil
    draft = nil
    draftSoundPreset = nil
    draftIncomingSoundEnabled, draftIncomingSoundPreset = nil, nil
end

local function createEditor()
    local theme = addon.Theme
    local frame = addon.UIFactory.CreateDialog(
        addon.L("LAYOUT_EDITOR_TITLE"),
        470,
        485
    )
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(80)
    frame.closeButton:SetScript("OnClick", function()
        closeEditor(false)
    end)

    local description = addon.UIFactory.CreateLabel(
        frame,
        theme.Fonts.small,
        addon.L("LAYOUT_EDITOR_DESCRIPTION"),
        theme.Colors.textMuted
    )
    description:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -48)
    description:SetPoint("RIGHT", frame, "RIGHT", -20, 0)
    description:SetJustifyH("LEFT")
    description:SetWordWrap(true)

    local groupHolder, groupSizeSlider = createSlider(
        frame,
        addon.L("LAYOUT_EDITOR_GROUP_SIZE"),
        1,
        40,
        1
    )
    groupHolder:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -8)
    groupHolder:SetWidth(430)
    groupSizeSlider.onChanged = function(value)
        if not suppressOptions then
            setPreviewGroupSize(value, true)
        end
    end

    local frequencyHolder, frequencySlider = createSlider(
        frame,
        addon.L("LAYOUT_EDITOR_REFRESH_RATE"),
        10,
        60,
        5
    )
    frequencyHolder:SetPoint("TOPLEFT", groupHolder, "BOTTOMLEFT", 0, -2)
    frequencyHolder:SetWidth(430)
    frequencyHolder:SetHeight(58)
    frequencySlider.valueLabel:Hide()
    local frequent = addon.UIFactory.CreateLabel(
        frequencyHolder,
        theme.Fonts.small,
        addon.L("LAYOUT_EDITOR_REFRESH_FREQUENT"),
        theme.Colors.textMuted
    )
    frequent:SetPoint("TOPLEFT", frequencySlider, "BOTTOMLEFT", 0, -2)
    local rare = addon.UIFactory.CreateLabel(
        frequencyHolder,
        theme.Fonts.small,
        addon.L("LAYOUT_EDITOR_REFRESH_RARE"),
        theme.Colors.textMuted
    )
    rare:SetPoint("TOPRIGHT", frequencySlider, "BOTTOMRIGHT", 0, -2)
    frequencySlider.onChanged = function(value)
        if not suppressOptions then
            setPreviewRefreshSeconds(value)
        end
    end
    local rows = {}
    local previous = frequencyHolder
    for _, moduleID in ipairs(addon.GameMasterLayout.GetModuleOrder()) do
        local definition = addon.GameMasterLayout.GetDefinition(moduleID)
        local row = CreateFrame("Button", nil, frame, "BackdropTemplate")
        row:SetSize(430, 43)
        row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -6)
        row:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        row:SetBackdropColor(0.08, 0.06, 0.04, 0.72)
        row:SetBackdropBorderColor(0.36, 0.25, 0.13, 0.85)
        local check = CreateFrame(
            "CheckButton", nil, row, "UICheckButtonTemplate"
        )
        check:SetSize(24, 24)
        check:SetPoint("LEFT", row, "LEFT", 8, 0)
        local name = addon.UIFactory.CreateLabel(
            row, theme.Fonts.body, addon.L(definition.editorTitleKey or definition.titleKey), theme.Colors.gold
        )
        name:SetPoint("TOPLEFT", check, "TOPRIGHT", 6, 0)
        local audience = addon.UIFactory.CreateLabel(
            row, theme.Fonts.small, addon.L(definition.audienceKey), theme.Colors.textMuted
        )
        audience:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
        audience:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        audience:SetWordWrap(false)
        row:SetScript("OnClick", function()
            addon.GameMasterLayoutEditor.SelectModule(moduleID)
        end)
        check:SetScript("OnClick", function(self)
            if not moduleAvailable(moduleID) then return end
            local module = draft[moduleID]
            module.editorVisible = self:GetChecked() == true
            applyPreviewLayout(moduleID)
            if module.editorVisible then
                addon.GameMasterLayoutEditor.SelectModule(moduleID)
            elseif selectedModuleID == moduleID and optionsWindow then
                optionsWindow:Hide()
            end
        end)
        row.check = check
        rows[moduleID] = row
        previous = row
    end

    local discard = addon.UIFactory.CreateButton(
        frame, addon.L("LAYOUT_EDITOR_DISCARD"), 180
    )
    discard:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 16)
    discard:SetScript("OnClick", function()
        closeEditor(false)
    end)
    local save = addon.UIFactory.CreateButton(
        frame, addon.L("LAYOUT_EDITOR_SAVE"), 180
    )
    save:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 16)
    save:SetScript("OnClick", function()
        closeEditor(true)
    end)
    frame.discard, frame.save = discard, save

    frame.frequencySlider = frequencySlider
    frame.moduleStart = frequencyHolder
    frame.groupSizeSlider = groupSizeSlider
    frame.moduleRows = rows
    frame:SetScript("OnUpdate", function(_, elapsed)
        local delta = tonumber(elapsed) or 0
        if pendingSampleRefresh then
            pendingSampleRefreshDelay = pendingSampleRefreshDelay - delta
            if pendingSampleRefreshDelay <= 0 then
                pendingSampleRefresh = false
                pendingSampleRefreshDelay = 0
                regenerateSamples()
                refreshPreviewContent()
            end
            return
        end
        sampleElapsed = sampleElapsed + delta
        if sampleElapsed < sampleInterval then
            return
        end
        regenerateSamples()
        refreshPreviewContent()
    end)
    return frame
end

function addon.GameMasterLayoutEditor.SelectModule(moduleID)
    if not draft or not draft[moduleID] or not moduleAvailable(moduleID) then
        return false
    end
    if addon.SoundBrowser and optionsWindow then addon.SoundBrowser.Close(optionsWindow) end
    if draft[moduleID].editorVisible ~= true then
        draft[moduleID].editorVisible = true
        if editor and editor.moduleRows[moduleID] then
            editor.moduleRows[moduleID].check:SetChecked(true)
        end
        previews[moduleID]:Show()
    end
    selectedModuleID = moduleID
    for id in pairs(previews) do
        populatePreview(id)
    end
    refreshOptions(moduleID)
    return true
end

function addon.GameMasterLayoutEditor.Open()
    addon.TRP3Bridge.CloseMainFrame()
    draft = addon.GameMasterLayout.GetModules()
    draftSoundPreset = addon.GameMasterPlayerState.GetTurnSoundPreset
        and addon.GameMasterPlayerState.GetTurnSoundPreset() or "ready"
    draftIncomingSoundEnabled = addon.GameMasterPlayerState.ShouldPlayIncomingActionSound
        and addon.GameMasterPlayerState.ShouldPlayIncomingActionSound() or false
    draftIncomingSoundPreset = addon.GameMasterPlayerState.GetIncomingActionSoundPreset
        and addon.GameMasterPlayerState.GetIncomingActionSoundPreset() or "ready"
    previewGroupSize = addon.GameMasterLayout.GetPreviewGroupSize()
    previewRefreshSeconds = addon.GameMasterLayout
        .GetPreviewRefreshSeconds()
    sampleInterval = previewRefreshSeconds
    editor = editor or createEditor()
    suppressOptions = true
    editor.groupSizeSlider:SetValue(previewGroupSize)
    editor.frequencySlider:SetValue(previewRefreshSeconds)
    suppressOptions = false
    local previous = editor.moduleStart
    local visibleModules = 0
    for _, moduleID in ipairs(addon.GameMasterLayout.GetModuleOrder()) do
        local available = moduleAvailable(moduleID)
        if available and not previews[moduleID] then
            createPreview(moduleID)
        end
        local row = editor.moduleRows[moduleID]
        row:SetShown(available)
        if available then
            visibleModules = visibleModules + 1
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -6)
            previous = row
        end
        row.check:SetChecked(draft[moduleID].editorVisible == true)
    end
    editor:SetHeight(485 - 49 * (#addon.GameMasterLayout.GetModuleOrder() - visibleModules))
    selectedModuleID = nil
    if optionsWindow then optionsWindow:Hide() end
    registerSampleProfiles = addon.TRP3Bridge.GetKnownRoleplayProfiles(80)
    pendingSampleRefresh = false
    pendingSampleRefreshDelay = 0
    regenerateSamples()
    refreshAllPreviews()
    editor:ClearAllPoints()
    editor:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    editor:Show()
    addon.UIFactory.BringToFront(editor)
    return true
end
