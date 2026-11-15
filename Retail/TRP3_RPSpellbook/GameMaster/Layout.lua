local _, addon = ...

addon.GameMasterLayout = {
    initialized = false,
}

local listeners = {}
local DEFAULT_PREVIEW_GROUP_SIZE = 5
local DEFAULT_PREVIEW_REFRESH_SECONDS = 40
local MAX_PREVIEW_GROUP_SIZE = 40
local MIN_PREVIEW_REFRESH_SECONDS = 10
local MAX_PREVIEW_REFRESH_SECONDS = 60
local PREVIEW_SETTINGS_VERSION = 1
local moduleOrder = {
    "gameMaster",
    "compactSpellbook",
    "roundOverview",
    "currentAction",
}
local validPoints = {
    BOTTOM = true,
    BOTTOMLEFT = true,
    BOTTOMRIGHT = true,
    CENTER = true,
    LEFT = true,
    RIGHT = true,
    TOP = true,
    TOPLEFT = true,
    TOPRIGHT = true,
}
local validStyles = {
    minimal = true,
    modern = true,
}
local validNameModes = {
    engine = true,
    trp_first = true,
    trp_full = true,
    trp_last = true,
    trp_title = true,
}

local definitions = {
    gameMaster = {
        audienceKey = "LAYOUT_AUDIENCE_GAMEMASTER",
        defaultHeight = 390,
        defaultWidth = 560,
        defaultX = 230,
        defaultY = 100,
        maxHeight = 1600,
        maxWidth = 2000,
        minHeight = 260,
        minWidth = 230,
        editorTitleKey = "LAYOUT_MODULE_GAMEMASTER",
        titleKey = "GAMEMASTER_WINDOW_TITLE",
        defaults = {
            autoOpen = true,
            editorVisible = true,
            fontSize = 12,
            opacity = 95,
            previewColor = "B8C0C8",
            showBorder = true,
            style = "modern",
            options = {
                autoFontSize = true,
                nameMode = "trp_full",
                profileColors = true,
                profileIcons = true,
                showVersions = true,
            },
        },
    },
    compactSpellbook = {
        audienceKey = "LAYOUT_AUDIENCE_COMPACT",
        defaultHeight = 500,
        defaultWidth = 380,
        defaultX = -340,
        defaultY = 70,
        maxHeight = 1600,
        maxWidth = 1600,
        minHeight = 165,
        minWidth = 175,
        editorTitleKey = "LAYOUT_MODULE_COMPACT",
        titleKey = "GAMEMASTER_COMPACT_TITLE",
        defaults = {
            autoOpen = false,
            editorVisible = true,
            fontSize = 12,
            opacity = 92,
            previewColor = "B8C0C8",
            showBorder = true,
            style = "modern",
            options = {
                autoFontSize = true,
                previewOwnData = false,
                showIcons = true,
            },
        },
    },
    roundOverview = {
        audienceKey = "LAYOUT_AUDIENCE_ROUND_OVERVIEW",
        defaultHeight = 260,
        defaultWidth = 520,
        defaultX = 210,
        defaultY = -260,
        maxHeight = 1600,
        maxWidth = 2000,
        minHeight = 130,
        minWidth = 210,
        editorTitleKey = "LAYOUT_MODULE_ROUND_OVERVIEW",
        titleKey = "GAMEMASTER_SHARED_ACTIONS_TITLE",
        defaults = {
            autoOpen = true,
            editorVisible = true,
            fontSize = 12,
            opacity = 95,
            previewColor = "B8C0C8",
            showBorder = true,
            style = "modern",
            options = {
                autoFontSize = true,
                nameMode = "trp_full",
                profileColors = true,
                showIcons = true,
            },
        },
    },
    currentAction = {
        audienceKey = "LAYOUT_AUDIENCE_CURRENT_ACTION",
        defaultHeight = 138,
        defaultWidth = 320,
        defaultX = -180,
        defaultY = -260,
        maxHeight = 1200,
        maxWidth = 1600,
        minHeight = 112,
        minWidth = 180,
        editorTitleKey = "LAYOUT_MODULE_CURRENT_ACTION",
        titleKey = "GAMEMASTER_CURRENT_ACTION",
        defaults = {
            autoOpen = true,
            editorVisible = true,
            fontSize = 12,
            opacity = 95,
            previewColor = "B8C0C8",
            showBorder = true,
            style = "modern",
            options = {
                autoCompleteTurn = true,
                autoFontSize = true,
                notifyTurn = true,
                showIcon = true,
                turnSound = false,
            },
        },
    },
}

local function copy(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end
    local result = {}
    seen[value] = result
    for key, entry in pairs(value) do
        result[copy(key, seen)] = copy(entry, seen)
    end
    return result
end

local function clamp(value, minimum, maximum, fallback)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge
        or number == -math.huge
    then
        number = fallback
    end
    return math.max(minimum, math.min(maximum, number))
end

local function cleanColor(value, fallback)
    local color = type(value) == "string" and value:gsub("#", "") or ""
    if not color:match("^%x%x%x%x%x%x$") then
        return fallback
    end
    return color:upper()
end

local function getConfigurationValue(key, fallback)
    local api = _G.TRP3_API
    local configuration = type(api) == "table" and api.configuration or nil
    if type(configuration) ~= "table"
        or type(configuration.getValue) ~= "function"
    then
        return fallback
    end
    local success, value = pcall(configuration.getValue, key)
    return success and value ~= nil and value or fallback
end

local function getRoot()
    local database = addon.Database.GetDB()
    if type(database) ~= "table" then
        return nil
    end
    if type(database.settings) ~= "table" then
        database.settings = {}
    end
    if type(database.settings.gameMasterLayout) ~= "table" then
        database.settings.gameMasterLayout = {}
    end
    local root = database.settings.gameMasterLayout
    if type(root.modules) ~= "table" then
        root.modules = {}
    end
    local previewVersion = math.floor(tonumber(
        root.previewSettingsVersion
    ) or 0)
    if previewVersion < PREVIEW_SETTINGS_VERSION then
        if root.previewGroupSize == nil or root.previewGroupSize == 20 then
            root.previewGroupSize = DEFAULT_PREVIEW_GROUP_SIZE
        end
        local roundOverview = root.modules.roundOverview
        local roundLayout = type(roundOverview) == "table"
            and roundOverview.layout or nil
        if type(roundLayout) == "table" and roundLayout.height == 310 then
            roundLayout.height = definitions.roundOverview.defaultHeight
        end
        local currentAction = root.modules.currentAction
        local actionLayout = type(currentAction) == "table"
            and currentAction.layout or nil
        if type(actionLayout) == "table"
            and actionLayout.width == 390
            and actionLayout.height == 176
        then
            actionLayout.width = definitions.currentAction.defaultWidth
            actionLayout.height = definitions.currentAction.defaultHeight
        end
        root.previewSettingsVersion = PREVIEW_SETTINGS_VERSION
    end
    root.previewGroupSize = math.floor(clamp(
        root.previewGroupSize,
        1,
        MAX_PREVIEW_GROUP_SIZE,
        DEFAULT_PREVIEW_GROUP_SIZE
    ))
    root.previewRefreshSeconds = math.floor(clamp(
        root.previewRefreshSeconds,
        MIN_PREVIEW_REFRESH_SECONDS,
        MAX_PREVIEW_REFRESH_SECONDS,
        DEFAULT_PREVIEW_REFRESH_SECONDS
    ))
    return root
end

local function normalizeOptions(moduleID, raw)
    raw = type(raw) == "table" and raw or {}
    local defaults = definitions[moduleID].defaults.options
    local result = {}
    for key, fallback in pairs(defaults) do
        if key == "nameMode" then
            result[key] = validNameModes[raw[key]] and raw[key] or fallback
        else
            result[key] = raw[key] == nil and fallback or raw[key] == true
        end
    end
    return result
end

local function normalizeLayout(definition, raw)
    raw = type(raw) == "table" and raw or {}
    local point = validPoints[raw.point] and raw.point or "CENTER"
    local relativePoint = validPoints[raw.relativePoint]
        and raw.relativePoint or point
    return {
        height = clamp(
            raw.height,
            definition.minHeight,
            definition.maxHeight,
            definition.defaultHeight
        ),
        point = point,
        relativePoint = relativePoint,
        width = clamp(
            raw.width,
            definition.minWidth,
            definition.maxWidth,
            definition.defaultWidth
        ),
        x = clamp(raw.x, -10000, 10000, definition.defaultX),
        y = clamp(raw.y, -10000, 10000, definition.defaultY),
    }
end

local function normalizeModule(moduleID, raw)
    local definition = definitions[moduleID]
    local defaults = definition.defaults
    raw = type(raw) == "table" and raw or {}
    return {
        autoOpen = raw.autoOpen == nil
            and defaults.autoOpen or raw.autoOpen == true,
        editorVisible = raw.editorVisible == nil
            and defaults.editorVisible or raw.editorVisible == true,
        fontSize = math.floor(clamp(raw.fontSize, 9, 20, defaults.fontSize)),
        layout = normalizeLayout(definition, raw.layout),
        opacity = math.floor(clamp(raw.opacity, 20, 100, defaults.opacity)),
        options = normalizeOptions(moduleID, raw.options),
        previewColor = cleanColor(raw.previewColor, defaults.previewColor),
        showBorder = raw.showBorder == nil
            and defaults.showBorder or raw.showBorder == true,
        style = validStyles[raw.style] and raw.style or defaults.style,
    }
end

local function getLegacyLayout(moduleID)
    if moduleID == "gameMaster" and addon.GameMasterStore then
        return addon.GameMasterStore.GetWindowLayout()
    end
    if moduleID == "compactSpellbook" and addon.GameMasterStore then
        return addon.GameMasterStore.GetCompactWindowLayout()
    end
    if moduleID == "currentAction" and addon.GameMasterPlayerState then
        return addon.GameMasterPlayerState.GetActionWindowLayout()
    end
    return nil
end

local function createInitialModule(moduleID)
    local initial = copy(definitions[moduleID].defaults)
    initial.layout = getLegacyLayout(moduleID)
    local constants = addon.Constants
    if moduleID == "gameMaster" then
        initial.opacity = getConfigurationValue(
            constants.GAMEMASTER_SETTING_OPACITY,
            initial.opacity
        )
        initial.fontSize = getConfigurationValue(
            constants.GAMEMASTER_SETTING_FONT_SIZE,
            initial.fontSize
        )
        initial.style = getConfigurationValue(
            constants.GAMEMASTER_SETTING_STYLE,
            initial.style
        )
        initial.options.nameMode = getConfigurationValue(
            constants.GAMEMASTER_SETTING_NAME_MODE,
            initial.options.nameMode
        )
        initial.options.profileColors = getConfigurationValue(
            constants.GAMEMASTER_SETTING_PROFILE_COLORS,
            initial.options.profileColors
        )
        initial.options.profileIcons = getConfigurationValue(
            constants.GAMEMASTER_SETTING_PROFILE_ICONS,
            initial.options.profileIcons
        )
    elseif moduleID == "compactSpellbook" then
        initial.opacity = getConfigurationValue(
            constants.GAMEMASTER_SETTING_COMPACT_OPACITY,
            initial.opacity
        )
        initial.fontSize = getConfigurationValue(
            constants.GAMEMASTER_SETTING_COMPACT_FONT_SIZE,
            initial.fontSize
        )
        initial.style = getConfigurationValue(
            constants.GAMEMASTER_SETTING_COMPACT_STYLE,
            initial.style
        )
    end
    return normalizeModule(moduleID, initial)
end

local function notifyListeners(moduleID)
    for _, listener in ipairs(listeners) do
        local success, errorMessage = addon.Runtime.SafeInvoke(
            listener,
            moduleID
        )
        if not success then
            addon.Logger.Error(tostring(errorMessage))
        end
    end
end

local metricProfiles = {
    gameMaster = {
        baseRow = 36,
        minCardWidth = 400,
        minRow = 24,
        maxColumns = 2,
        maxRow = 80,
        preferredCardWidth = 820,
        singleLineWidth = 530,
        twoLineWidth = 400,
    },
    compactSpellbook = {
        baseRow = 30,
        minCardWidth = 145,
        minRow = 20,
        maxColumns = 5,
        maxRow = 52,
        preferredCardWidth = 190,
    },
    roundOverview = {
        baseRow = 32,
        minCardWidth = 205,
        minRow = 24,
        maxColumns = 4,
        maxRow = 90,
        preferredCardWidth = 320,
        singleLineWidth = 430,
        twoLineWidth = 255,
    },
    currentAction = {
        baseRow = 30,
        minCardWidth = 180,
        minRow = 22,
        maxColumns = 1,
        maxRow = 56,
        preferredCardWidth = 320,
    },
}

function addon.GameMasterLayout.GetAdaptiveMetrics(
    moduleID,
    width,
    height,
    fontSize,
    options,
    styleName
)
    local definition = definitions[moduleID]
    local profile = metricProfiles[moduleID]
    if not definition or not profile then
        return nil
    end

    options = type(options) == "table" and options or {}
    width = clamp(width, 1, 10000, definition.defaultWidth)
    height = clamp(height, 1, 10000, definition.defaultHeight)
    local baseFontSize = math.floor(clamp(fontSize, 8, 24, 12))
    local widthRatio = width / definition.defaultWidth
    local heightRatio = height / definition.defaultHeight
    local aspectRatio = width / math.max(1, height)
    local automaticFont = options.autoFontSize ~= false

    local orientation = "balanced"
    if aspectRatio < 0.9 then
        orientation = "portrait"
    elseif aspectRatio > 1.35 and widthRatio >= 0.95 then
        orientation = "landscape"
    end

    local density = "normal"
    if widthRatio < 0.72 or heightRatio < 0.7 then
        density = "compact"
    elseif widthRatio > 1.25 and heightRatio > 1.15 then
        density = "spacious"
    end
    if moduleID == "gameMaster" then
        density = width < 440 and "compact" or "normal"
    end

    local fontDelta = 0
    if widthRatio < 0.58 then
        fontDelta = -2
    elseif widthRatio < 0.82 then
        fontDelta = -1
    end
    if width < definition.minWidth * 1.15 then
        fontDelta = math.min(fontDelta, -1)
    end
    if moduleID == "gameMaster" then
        if width < 300 then
            fontDelta = -2
        elseif width < 440 then
            fontDelta = -1
        else
            fontDelta = 0
        end
    end
     
     
    local effectiveFontSize = automaticFont
        and math.min(baseFontSize, baseFontSize + fontDelta)
        or baseFontSize
    effectiveFontSize = math.floor(clamp(
        effectiveFontSize,
        8,
        24,
        baseFontSize
    ))

    local rowLines = 1
    if moduleID == "gameMaster" or moduleID == "roundOverview" then
        if width < profile.twoLineWidth then
            rowLines = 3
        elseif width < profile.singleLineWidth then
            rowLines = 2
        end
    end

    local minimal = styleName == "minimal"
    local rowHeight = profile.baseRow + effectiveFontSize - 12
    if rowLines > 1 then
        local lineHeight = effectiveFontSize + (minimal and 3 or 5)
        rowHeight = math.max(rowHeight, (lineHeight * rowLines) + 6)
    elseif minimal then
        rowHeight = rowHeight - 6
    end
    rowHeight = math.floor(clamp(
        rowHeight,
        profile.minRow,
        profile.maxRow,
        profile.baseRow
    ))

    local padding = 6
    local iconSize = math.floor(clamp(
        effectiveFontSize + (minimal and 5 or 8),
        16,
        34,
        20
    ))
    local headerHeight = effectiveFontSize * 2 + 18

    return {
        adaptive = true,
        aspectRatio = aspectRatio,
        autoFontSize = automaticFont,
        density = density,
        fontSize = effectiveFontSize,
        headerHeight = headerHeight,
        iconSize = iconSize,
        orientation = orientation,
        padding = padding,
        rowHeight = rowHeight,
        rowLines = rowLines,
        stacked = rowLines > 1,
    }
end

local function getRowLines(moduleID, profile, cardWidth)
    if moduleID ~= "gameMaster" and moduleID ~= "roundOverview" then
        return 1
    end
    if cardWidth >= profile.singleLineWidth then
        return 1
    end
    if cardWidth >= profile.twoLineWidth then
        return 2
    end
    return 3
end

local function getRowHeight(profile, rowLines, fontSize, minimal)
    local lineHeight = fontSize + (minimal and 3 or 5)
    local rowHeight
    if rowLines > 1 then
        rowHeight = (lineHeight * rowLines) + (minimal and 4 or 7)
    else
        rowHeight = math.max(
            profile.baseRow + fontSize - 12 - (minimal and 5 or 0),
            fontSize + (minimal and 7 or 11)
        )
    end
    return math.floor(clamp(
        rowHeight,
        profile.minRow,
        profile.maxRow,
        profile.baseRow
    ))
end

local function getGameMasterCollectionMetrics(
    profile,
    width,
    height,
    itemCount,
    fontSize,
    minimal
)
    local gap = minimal and 2 or 4
    local columns = width >= 1200 and itemCount >= 10 and 2 or 1
    local cardWidth = math.floor(
        (width - ((columns - 1) * gap)) / columns
    )
    local rowLines = getRowLines("gameMaster", profile, cardWidth)
    local rowFontSize = fontSize
    local rowHeight = getRowHeight(
        profile,
        rowLines,
        rowFontSize,
        minimal
    )
    local visibleGridRows = math.max(
        1,
        math.floor((height + gap) / (rowHeight + gap))
    )
    local contentRows = math.max(
        1,
        math.ceil(math.max(1, itemCount) / columns)
    )
    return {
        capacity = visibleGridRows * columns,
        cardWidth = cardWidth,
        columns = columns,
        contentHeight = math.max(
            1,
            (contentRows * (rowHeight + gap)) - gap
        ),
        contentRows = contentRows,
        fontSize = rowFontSize,
        gap = gap,
        rowHeight = rowHeight,
        rowLines = rowLines,
        visibleGridRows = visibleGridRows,
    }
end

function addon.GameMasterLayout.GetCollectionMetrics(
    moduleID,
    width,
    height,
    itemCount,
    fontSize,
    styleName,
    constraints
)
    local profile = metricProfiles[moduleID]
    if not profile then
        return nil
    end

    width = math.max(1, tonumber(width) or profile.minCardWidth)
    height = math.max(1, tonumber(height) or profile.baseRow)
    itemCount = math.max(0, math.floor(tonumber(itemCount) or 0))
    fontSize = math.floor(clamp(fontSize, 8, 24, 12))
    local minimal = styleName == "minimal"
    if moduleID == "gameMaster" then
        return getGameMasterCollectionMetrics(
            profile,
            width,
            height,
            itemCount,
            fontSize,
            minimal
        )
    end
    constraints = type(constraints) == "table" and constraints or {}
    local gap = minimal and 2 or 4
    local minimumCardWidth = clamp(
        constraints.minCardWidth,
        120,
        2000,
        profile.minCardWidth
    )
    local preferredCardWidth = clamp(
        constraints.preferredCardWidth,
        minimumCardWidth,
        3000,
        profile.preferredCardWidth
    )
    local maximumAllowedColumns = math.floor(clamp(
        constraints.maxColumns,
        1,
        profile.maxColumns,
        profile.maxColumns
    ))
    local maximumColumns = math.max(
        1,
        math.min(
            maximumAllowedColumns,
            math.floor((width + gap) / (minimumCardWidth + gap))
        )
    )
    local preferredColumns = math.max(
        1,
        math.min(
            maximumColumns,
            math.floor(
                (width + gap) / (preferredCardWidth + gap)
            )
        )
    )
    if itemCount > 0 then
        preferredColumns = math.min(preferredColumns, itemCount)
    end
    local selected

    for columns = preferredColumns, maximumColumns do
        local cardWidth = math.floor(
            (width - ((columns - 1) * gap)) / columns
        )
        local rowLines = getRowLines(moduleID, profile, cardWidth)
        local rowFontSize = fontSize
        local rowHeight = getRowHeight(
            profile,
            rowLines,
            rowFontSize,
            minimal
        )
        local visibleGridRows = math.max(
            1,
            math.floor((height + gap) / (rowHeight + gap))
        )
        local candidate = {
            capacity = visibleGridRows * columns,
            cardWidth = cardWidth,
            columns = columns,
            fontSize = rowFontSize,
            gap = gap,
            rowHeight = rowHeight,
            rowLines = rowLines,
            visibleGridRows = visibleGridRows,
        }
        if not selected
            or candidate.capacity > selected.capacity
            or (
                candidate.capacity == selected.capacity
                and candidate.columns < selected.columns
            )
        then
            selected = candidate
        end
        if itemCount > 0 and candidate.capacity >= itemCount then
            selected = candidate
            break
        end
    end

    selected = selected or {
        capacity = 1,
        cardWidth = width,
        columns = 1,
        fontSize = fontSize,
        gap = gap,
        rowHeight = profile.baseRow,
        rowLines = 1,
        visibleGridRows = 1,
    }
    selected.contentRows = math.max(
        1,
        math.ceil(math.max(1, itemCount) / selected.columns)
    )
    selected.contentHeight = math.max(
        1,
        (selected.contentRows * (selected.rowHeight + selected.gap))
            - selected.gap
    )
    return selected
end

function addon.GameMasterLayout.GetParticipantCardColumns(cardWidth, options)
    options = type(options) == "table" and options or {}
    cardWidth = math.max(1, tonumber(cardWidth) or 1)
    local inset = math.max(0, tonumber(options.inset) or 4)
    local gap = math.max(0, tonumber(options.gap) or 6)
    local available = math.max(1, cardWidth - (inset * 2))
    local minimumIdentity = math.max(
        40,
        tonumber(options.minIdentityWidth) or 150
    )
    local maximumIdentity = math.max(
        minimumIdentity,
        tonumber(options.maxIdentityWidth) or 280
    )
    local minimumDetail = math.max(
        80,
        tonumber(options.minDetailWidth) or 280
    )
    local ratio = clamp(options.identityRatio, 0.2, 0.6, 0.34)
    local inline = available >= minimumIdentity + gap + minimumDetail

    if not inline then
        return {
            availableWidth = available,
            detailLeft = inset,
            detailWidth = available,
            gap = gap,
            identityLeft = inset,
            identityWidth = available,
            inline = false,
        }
    end

    local identityMaximum = math.min(
        maximumIdentity,
        available - gap - minimumDetail
    )
    local identityWidth = math.floor(clamp(
        available * ratio,
        minimumIdentity,
        identityMaximum,
        minimumIdentity
    ))
    return {
        availableWidth = available,
        detailLeft = inset + identityWidth + gap,
        detailWidth = available - identityWidth - gap,
        gap = gap,
        identityLeft = inset,
        identityWidth = identityWidth,
        inline = true,
    }
end

function addon.GameMasterLayout.GetGameMasterChromeLayout(
    width,
    height,
    padding,
    buttonHeight,
    fontSize
)
    width = math.max(1, tonumber(width) or definitions.gameMaster.defaultWidth)
    height = math.max(1, tonumber(height) or definitions.gameMaster.defaultHeight)
    padding = math.floor(clamp(padding, 6, 10, 6))
    buttonHeight = math.max(18, tonumber(buttonHeight) or 24)
    fontSize = math.floor(clamp(fontSize, 8, 24, 12))
    local compact = width < 700
    local stackControls = width < 470
    local stackHeader = width < 480
    local metadataTop = math.max(26, fontSize + 14)
    local metadataLineHeight = math.max(12, fontSize + 2)
    local secondaryTop = stackHeader and metadataTop + metadataLineHeight * 2 + 3
        or metadataTop
    local controlsTop = math.max(metadataTop + metadataLineHeight * 2,
        secondaryTop + buttonHeight) + 4
    local controlsHeight = stackControls and buttonHeight * 2 + 10 or buttonHeight + 8
    local controlsWidth = math.max(1, width - (padding * 2))
    local controlButtons = {}
    local controlGap = compact and 4 or 8
    local controlY = math.max(0, math.floor((controlsHeight - buttonHeight) / 2))

    if stackControls then
        local firstRowY = 5
        local controlWidth = math.min(
            140,
            math.floor((math.max(1, controlsWidth - 8) - controlGap) / 2)
        )
        local controlsX = math.max(4, math.floor(
            (controlsWidth - ((controlWidth * 2) + controlGap)) / 2
        ))
        local secondRowY = controlsHeight - firstRowY - buttonHeight
        controlButtons = {
            { width = controlWidth, x = controlsX, y = firstRowY },
            { width = controlWidth, x = controlsX + controlWidth + controlGap, y = firstRowY },
            { width = controlWidth, x = controlsX, y = secondRowY },
            { width = controlWidth, x = controlsX + controlWidth + controlGap, y = secondRowY },
        }
    elseif compact then
        local desired = { 125, 118, 170, 78 }
        local innerWidth = math.max(1, controlsWidth - 8)
        local scale = math.min(
            1,
            math.max(0.55, (innerWidth - (controlGap * 3)) / 491)
        )
        local totalWidth = controlGap * 3
        local widths = {}
        for index, desiredWidth in ipairs(desired) do
            widths[index] = math.floor(desiredWidth * scale)
            totalWidth = totalWidth + widths[index]
        end
        local x = math.max(4, math.floor((controlsWidth - totalWidth) / 2))
        for index, controlWidth in ipairs(widths) do
            controlButtons[index] = {
                width = controlWidth,
                x = x,
                y = controlY,
            }
            x = x + controlWidth + controlGap
        end
    else
        local widths = { 140, 140, 190, 90 }
        local x = 8
        for index = 1, 3 do
            controlButtons[index] = {
                width = widths[index],
                x = x,
                y = controlY,
            }
            x = x + widths[index] + controlGap
        end
        controlButtons[4] = {
            width = widths[4],
            x = math.max(x, controlsWidth - 8 - widths[4]),
            y = controlY,
        }
    end

    local contentLeft = padding + 4
    local contentRight = padding + 4
    local contentTop = controlsTop + controlsHeight + 8
    local contentBottom = buttonHeight + padding + 10
    return {
        compact = stackHeader,
        metadataTop = metadataTop,
        metadataLineHeight = metadataLineHeight,
        metadataWidth = math.max(1, width - padding * 2 - (stackHeader and 0 or 205)),
        secondaryTop = secondaryTop,
        controlButtons = controlButtons,
        contentBottom = contentBottom,
        contentHeight = math.max(1, height - contentTop - contentBottom),
        contentLeft = contentLeft,
        contentRight = contentRight,
        contentTop = contentTop,
        contentWidth = math.max(1, width - contentLeft - contentRight),
        controlsHeight = controlsHeight,
        controlsTop = controlsTop,
        controlsWidth = controlsWidth,
        padding = padding,
        stackControls = stackControls,
    }
end

function addon.GameMasterLayout.PlanGameMasterParticipants(options)
    options = type(options) == "table" and options or {}
    local participants = type(options.participants) == "table"
        and options.participants or {}
    local itemCount = math.min(addon.Constants.GAMEMASTER_MAX_VISIBLE_ACTORS or 60, #participants)
    local fontSize = math.floor(clamp(options.fontSize, 8, 24, 12))
    local grid = addon.GameMasterLayout.GetCollectionMetrics(
        "gameMaster",
        options.width,
        options.height,
        itemCount,
        fontSize,
        options.styleName
    )
    local showMoveButtons = options.showMoveButtons == true
    local showVersions = options.showVersions == true
    local versionWidth = showVersions and 31 or 0
    local indexWidth = math.max(24, math.ceil(fontSize * 1.8))
    local headerHeight = math.max(18, fontSize + 6)
    local preferredIconSize = math.max(14, tonumber(options.iconSize) or 20)
    local sharedIdentityWidth = 0
    local minimumIdentityWidth = 0
    local metrics = {}

    for index = 1, itemCount do
        local participant = type(participants[index]) == "table"
            and participants[index] or {}
        local hasProfileIcon = participant.hasProfileIcon == true
        local iconSize = math.max(14, math.min(headerHeight - 3, preferredIconSize))
        local controlWidth = 2 + indexWidth + 1 + 18
            + (showMoveButtons and 38 or 0)
            + (hasProfileIcon and iconSize + 3 or 0)
            + 4
        local nameWidth = math.max(0, tonumber(participant.nameWidth) or 0)
        metrics[index] = {
            buffHeight = math.max(0, tonumber(participant.buffHeight) or 0),
            controlWidth = controlWidth,
            hasProfileIcon = hasProfileIcon,
            iconSize = iconSize,
        }
        minimumIdentityWidth = math.max(minimumIdentityWidth,
            controlWidth + math.max(54, 72 * fontSize / 12) + versionWidth)
        sharedIdentityWidth = math.max(
            sharedIdentityWidth,
            math.ceil(controlWidth + nameWidth + versionWidth + 8)
        )
    end
    sharedIdentityWidth = math.max(130, math.min(320, sharedIdentityWidth))

    local function measureGrid(columnCount)
        local cardWidth = math.floor((math.max(1, tonumber(options.width) or 1)
            - (columnCount - 1) * grid.gap) / columnCount)
        local plans = {}
        local rowHeights = {}
        for index = 1, itemCount do
            local metric = metrics[index]
            local columns = addon.GameMasterLayout.GetParticipantCardColumns(
                cardWidth,
                {
                    gap = 6,
                    identityRatio = 0.2,
                    inset = 4,
                    maxIdentityWidth = sharedIdentityWidth,
                    minDetailWidth = math.max(220, 300 * fontSize / 12),
                    minIdentityWidth = minimumIdentityWidth,
                }
            )
            local actionLeft = columns.inline and columns.detailLeft or 18
            local actionWidth = columns.inline and columns.detailWidth
                or math.max(1, cardWidth - actionLeft - 6)
            local actionHeight = headerHeight
            if type(options.measureAction) == "function" then
                actionHeight = math.max(
                    1,
                    tonumber(options.measureAction(index, actionWidth, fontSize))
                        or actionHeight
                )
            end
            local identityWidth = columns.inline and columns.identityWidth
                or math.max(1, cardWidth - 8)
            local identityHeight = metric.buffHeight + headerHeight
            local height = columns.inline
                and math.max(identityHeight, actionHeight) + 6
                or identityHeight + actionHeight + 8
            plans[index] = {
                actionHeight = actionHeight,
                actionLeft = actionLeft,
                actionTop = columns.inline and 3 or identityHeight + 3,
                actionWidth = actionWidth,
                buffHeight = metric.buffHeight,
                controlWidth = metric.controlWidth,
                headerHeight = headerHeight,
                iconSize = metric.iconSize,
                identityHeight = identityHeight,
                identityWidth = identityWidth,
                indexWidth = indexWidth,
                inline = columns.inline,
                profileIcon = metric.hasProfileIcon,
            }
            rowHeights[index] = height
        end

        local packed = addon.GameMasterLayout.GetVariableRowLayout(
            columnCount,
            rowHeights,
            grid.gap
        )
        local capacity = 0
        for _, position in ipairs(packed.positions) do
            if position.offset + position.height <= math.max(1, tonumber(options.height) or 1) then
                capacity = capacity + 1
            end
        end
        return {
            capacity = capacity, cardWidth = cardWidth, columns = columnCount,
            contentHeight = packed.contentHeight, plans = plans,
            positions = packed.positions, rowHeights = packed.rowHeights,
        }
    end

     
    local selected = measureGrid(1)
    local minimumCardWidth = math.max(390, 520 * fontSize / 12)
    if itemCount >= 10 and selected.capacity < itemCount
        and (tonumber(options.width) or 0) >= minimumCardWidth * 2 + grid.gap then
        local candidate = measureGrid(2)
        if candidate.capacity > selected.capacity then selected = candidate end
    end
    for key, value in pairs(selected) do grid[key] = value end
    grid.viewportHeight = math.max(1, tonumber(options.height) or 1)
    grid.viewportWidth = math.max(1, tonumber(options.width) or 1)
    grid.sharedIdentityWidth = sharedIdentityWidth
    return grid
end

function addon.GameMasterLayout.GetVariableRowLayout(columns, heights, gap)
    columns = math.max(1, math.floor(tonumber(columns) or 1))
    heights = type(heights) == "table" and heights or {}
    gap = math.max(0, tonumber(gap) or 0)
    local rowHeights = {}
    for index, height in ipairs(heights) do
        local rowIndex = math.floor((index - 1) / columns) + 1
        rowHeights[rowIndex] = math.max(
            rowHeights[rowIndex] or 1,
            math.max(1, tonumber(height) or 1)
        )
    end

    local rowOffsets = {}
    local contentHeight = 0
    for rowIndex, height in ipairs(rowHeights) do
        rowOffsets[rowIndex] = contentHeight
        contentHeight = contentHeight + height
        if rowIndex < #rowHeights then
            contentHeight = contentHeight + gap
        end
    end

    local positions = {}
    for index = 1, #heights do
        local rowIndex = math.floor((index - 1) / columns) + 1
        positions[index] = {
            column = (index - 1) % columns,
            height = rowHeights[rowIndex],
            offset = rowOffsets[rowIndex],
            row = rowIndex,
        }
    end
    return {
        contentHeight = math.max(1, contentHeight),
        positions = positions,
        rowHeights = rowHeights,
    }
end

function addon.GameMasterLayout.PlanGameMasterWindow(options)
    options = type(options) == "table" and options or {}
    local chrome = addon.GameMasterLayout.GetGameMasterChromeLayout(
        options.width,
        options.height,
        options.padding,
        options.buttonHeight,
        options.fontSize
    )
    local participants = addon.GameMasterLayout.PlanGameMasterParticipants({
        fontSize = options.fontSize,
        height = chrome.contentHeight,
        iconSize = options.iconSize,
        measureAction = options.measureAction,
        participants = options.participants,
        showMoveButtons = options.showMoveButtons,
        showVersions = options.showVersions,
        styleName = options.styleName,
        width = chrome.contentWidth,
    })
    return {
        chrome = chrome,
        participants = participants,
    }
end

function addon.GameMasterLayout.Initialize()
    local root = getRoot()
    if not root then
        return false, addon.L("DATABASE_INVALID")
    end
    for _, moduleID in ipairs(moduleOrder) do
        if type(root.modules[moduleID]) ~= "table" then
            root.modules[moduleID] = createInitialModule(moduleID)
        else
            root.modules[moduleID] = normalizeModule(
                moduleID,
                root.modules[moduleID]
            )
        end
    end
    addon.GameMasterLayout.initialized = true
    return true
end

local function ensureInitialized()
    if addon.GameMasterLayout.initialized then
        return getRoot()
    end
    local success = addon.GameMasterLayout.Initialize()
    return success and getRoot() or nil
end

function addon.GameMasterLayout.GetPreviewGroupSize()
    local root = ensureInitialized()
    return root and root.previewGroupSize or DEFAULT_PREVIEW_GROUP_SIZE
end

function addon.GameMasterLayout.GetPreviewRefreshSeconds()
    local root = ensureInitialized()
    return root and root.previewRefreshSeconds
        or DEFAULT_PREVIEW_REFRESH_SECONDS
end

function addon.GameMasterLayout.GetModuleOrder()
    return copy(moduleOrder)
end

function addon.GameMasterLayout.GetDefinition(moduleID)
    return definitions[moduleID] and copy(definitions[moduleID]) or nil
end

function addon.GameMasterLayout.GetModule(moduleID)
    local root = definitions[moduleID] and ensureInitialized() or nil
    return root and copy(root.modules[moduleID])
        or (definitions[moduleID] and createInitialModule(moduleID) or nil)
end

function addon.GameMasterLayout.GetModules()
    local result = {}
    for _, moduleID in ipairs(moduleOrder) do
        result[moduleID] = addon.GameMasterLayout.GetModule(moduleID)
    end
    return result
end

function addon.GameMasterLayout.GetDefaultModule(moduleID)
    return definitions[moduleID]
        and normalizeModule(moduleID, definitions[moduleID].defaults)
        or nil
end

function addon.GameMasterLayout.Commit(
    modules,
    previewGroupSize,
    previewRefreshSeconds
)
    if type(modules) ~= "table" then
        return false
    end
    local root = ensureInitialized()
    if not root then
        return false
    end
    for _, moduleID in ipairs(moduleOrder) do
        root.modules[moduleID] = normalizeModule(
            moduleID,
            modules[moduleID]
        )
    end
    if previewGroupSize ~= nil then
        root.previewGroupSize = math.floor(clamp(
            previewGroupSize,
            1,
            MAX_PREVIEW_GROUP_SIZE,
            DEFAULT_PREVIEW_GROUP_SIZE
        ))
    end
    if previewRefreshSeconds ~= nil then
        root.previewRefreshSeconds = math.floor(clamp(
            previewRefreshSeconds,
            MIN_PREVIEW_REFRESH_SECONDS,
            MAX_PREVIEW_REFRESH_SECONDS,
            DEFAULT_PREVIEW_REFRESH_SECONDS
        ))
    end
    notifyListeners(nil)
    return true
end

function addon.GameMasterLayout.SaveFrameLayout(moduleID, frame, saveSize)
    local root = definitions[moduleID] and ensureInitialized() or nil
    if not root or not frame or type(frame.GetPoint) ~= "function" then
        return false
    end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    if not validPoints[point] or not validPoints[relativePoint] then
        return false
    end
    local module = copy(root.modules[moduleID])
    module.layout.point = point
    module.layout.relativePoint = relativePoint
    module.layout.x = tonumber(x) or 0
    module.layout.y = tonumber(y) or 0
    if saveSize == true
        and type(frame.GetWidth) == "function"
        and type(frame.GetHeight) == "function"
    then
        module.layout.width = frame:GetWidth()
        module.layout.height = frame:GetHeight()
    end
    root.modules[moduleID] = normalizeModule(moduleID, module)
    notifyListeners(moduleID)
    return true
end

function addon.GameMasterLayout.ApplyFrameLayout(moduleID, frame, applySize)
    local module = addon.GameMasterLayout.GetModule(moduleID)
    if not module or not frame then
        return false
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
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    if applySize ~= false then
        frame:SetSize(layout.width, layout.height)
    end
    return true
end

function addon.GameMasterLayout.RegisterListener(listener)
    if type(listener) ~= "function" then
        return false
    end
    listeners[#listeners + 1] = listener
    return true
end
