local _, addon = ...

addon.SpellDetailsView = {}

local function hasText(value)
    return type(value) == "string" and value ~= ""
end

local function isHiddenTag(key, value, tags)
    local presentation = addon.SpellPresentation
    return presentation.IsInternalTag(key)
        or (presentation.IsRedundantClassificationTag
            and presentation.IsRedundantClassificationTag(key, value, tags))
end

local function getMagicSummary(spell)
    return addon.SpellPresentation.GetClassificationSummary(spell.tags, spell.effects) or ""
end

local function formatMetadata(spell, fancy)
    local lines = {}
    local function addLine(label, value)
        if hasText(value) then
            lines[#lines + 1] = string.format((fancy and "|cff38200c%s:|r %s" or "|cffffd16a%s:|r %s"), label, value)
        end
    end

    addLine(addon.L("FIELD_RESOURCE"), spell.resource)
    addLine(addon.L("FIELD_RANGE"), spell.range)
    addLine(addon.L("FIELD_CAST_TIME"), spell.castTime)
    if addon.SpellPresentation.ShouldShowCooldown(spell.cooldown) then
        addLine(addon.L("FIELD_COOLDOWN"), spell.cooldown)
    end
    addLine(addon.L("FIELD_DURATION"), addon.SpellPresentation.GetEffectDuration(spell))
    return table.concat(lines, "\n")
end

local function formatTags(tags, fancy)
    if type(tags) ~= "table" then
        return ""
    end

    local keys = {}
    for key, value in pairs(tags) do
        if hasText(key) and hasText(value) and not isHiddenTag(key, value, tags) then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)

    local lines = {}
    for _, key in ipairs(keys) do
        lines[#lines + 1] = string.format((fancy and "|cff38200c%s:|r %s" or "|cffffd16a%s:|r %s"), key, tags[key])
    end
    return table.concat(lines, "\n")
end

local function layoutContent(view)
    local theme = addon.Theme
    if view.effectsButton then
        local extraRow = view.effectsButton:IsShown() or view.gameMasterButton:IsShown()
        view.scrollFrame:ClearAllPoints()
        view.scrollFrame:SetPoint("TOPLEFT", view, "TOPLEFT", theme.Spacing.lg, -theme.Spacing.xl - theme.Sizes.buttonHeight)
        view.scrollFrame:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -theme.Spacing.xl,
            theme.Spacing.xl + theme.Sizes.buttonHeight + (extraRow and (theme.Sizes.buttonHeight + 8) or 0))
    end
    local iconSize = view.readingIconSize or theme.Sizes.detailIcon
    local scrollWidth = math.max(1, view.scrollFrame:GetWidth()
        - (view.hideScrollBar and 0 or theme.Sizes.detailScrollBarWidth))
    local availableWidth = scrollWidth
    if view.fancyReading then scrollWidth = math.min(scrollWidth, 720) end
    view.scrollChild:ClearAllPoints()
    view.scrollChild:SetPoint("TOPLEFT", view.scrollFrame, "TOPLEFT", (availableWidth - scrollWidth) / 2, 0)
    local headerTextWidth = math.max(1, scrollWidth - iconSize - theme.Spacing.md)
    view.scrollChild:SetWidth(scrollWidth)
    view.name:SetWidth(headerTextWidth)
    view.magicSubtitle:SetWidth(headerTextWidth)
    view.metadata:SetWidth(headerTextWidth)
    view.description:SetWidth(scrollWidth)
    view.tags:SetWidth(scrollWidth)

    view.magicSubtitle:ClearAllPoints()
    view.magicSubtitle:SetPoint("TOPLEFT", view.name, "BOTTOMLEFT", 0, -theme.Spacing.xs)
    view.metadata:ClearAllPoints()
    if view.magicSubtitle:IsShown() then
        view.metadata:SetPoint("TOPLEFT", view.magicSubtitle, "BOTTOMLEFT", 0, -theme.Spacing.sm)
    else
        view.metadata:SetPoint("TOPLEFT", view.name, "BOTTOMLEFT", 0, -theme.Spacing.sm)
    end

    local nameHeight = math.max(1, view.name:GetStringHeight())
    local subtitleHeight = view.magicSubtitle:IsShown() and (theme.Spacing.xs + view.magicSubtitle:GetStringHeight()) or 0
    local metadataHeight = view.metadata:IsShown() and (theme.Spacing.sm + view.metadata:GetStringHeight()) or 0
    local headerHeight = math.max(iconSize, nameHeight + subtitleHeight + metadataHeight)
    local topOffset = -headerHeight - theme.Spacing.lg

    if view.description:IsShown() then
        view.descriptionTitle:ClearAllPoints()
        view.descriptionTitle:SetPoint("TOPLEFT", view.scrollChild, "TOPLEFT", 0, topOffset)
        topOffset = topOffset - view.descriptionTitle:GetStringHeight() - theme.Spacing.xs

        view.description:ClearAllPoints()
        view.description:SetPoint("TOPLEFT", view.scrollChild, "TOPLEFT", 0, topOffset)
        topOffset = topOffset - view.description:GetStringHeight() - theme.Spacing.lg
    end

    if view.tags:IsShown() then
        view.tagsTitle:ClearAllPoints()
        view.tagsTitle:SetPoint("TOPLEFT", view.scrollChild, "TOPLEFT", 0, topOffset)
        topOffset = topOffset - view.tagsTitle:GetStringHeight() - theme.Spacing.xs

        view.tags:ClearAllPoints()
        view.tags:SetPoint("TOPLEFT", view.scrollChild, "TOPLEFT", 0, topOffset)
        topOffset = topOffset - view.tags:GetStringHeight() - theme.Spacing.lg
    end

    local requiredHeight = math.max(view.scrollFrame:GetHeight(), -topOffset + theme.Spacing.lg)
    view.scrollChild:SetHeight(requiredHeight)
    view.scrollFrame:UpdateScrollChildRect()
end

addon.SpellDetailsView.Layout = layoutContent

local function styleScrollBar(view)
    local bar = view.scrollFrame.ScrollBar
    if not bar then return end
    if view.hideScrollBar then
        if view.normalScrollBarShown == nil then view.normalScrollBarShown = bar:IsShown() end
        bar:Hide()
    elseif view.normalScrollBarShown ~= nil then
        bar:SetShown(view.normalScrollBarShown)
        view.normalScrollBarShown = nil
    end
end

function addon.SpellDetailsView.StopReadingReveal(view)
    local reveal = view.readingReveal
    if not reveal then return end
    reveal.driver:SetScript("OnUpdate", nil)
    for _, entry in ipairs(reveal.entries) do entry.region:SetAlpha(entry.alpha) end
    reveal.entries = {}
end

function addon.SpellDetailsView.RevealReading(view)
    addon.SpellDetailsView.StopReadingReveal(view)
    local settings = addon.SpellCreationSettings
    if settings and settings.ShouldReduceBookMotion and settings.ShouldReduceBookMotion() then return end
    if not view.fancyReading or not view:IsVisible() then return end
    local reveal = view.readingReveal
    if not reveal then
        reveal = { driver = CreateFrame("Frame", nil, view), entries = {} }
        view.readingReveal = reveal
        view:HookScript("OnHide", function() addon.SpellDetailsView.StopReadingReveal(view) end)
    end
    local function add(region, delay)
        if not region:IsShown() then return end
        reveal.entries[#reveal.entries + 1] = { region = region, alpha = region:GetAlpha(), delay = delay }
        region:SetAlpha(0)
    end
    add(view.magicSubtitle, 0)
    add(view.metadata, 0.05)
    add(view.descriptionTitle, 0.10)
    add(view.description, 0.16)
    add(view.tagsTitle, 0.20)
    add(view.tags, 0.24)
    for _, button in ipairs(view.themeButtons) do add(button, 0.08) end
    local elapsed = 0
    reveal.driver:SetScript("OnUpdate", function(_, delta)
        if settings and settings.ShouldReduceBookMotion and settings.ShouldReduceBookMotion() then
            addon.SpellDetailsView.StopReadingReveal(view)
            return
        end
        elapsed = elapsed + delta
        for _, entry in ipairs(reveal.entries) do
            local t = math.max(0, math.min(1, (elapsed - entry.delay) / 0.46))
            entry.region:SetAlpha(entry.alpha * t * t * (3 - 2 * t))
        end
        if elapsed >= 0.70 then addon.SpellDetailsView.StopReadingReveal(view) end
    end)
end

function addon.SpellDetailsView.Create(parent, callbacks)
    local theme = addon.Theme
    callbacks = type(callbacks) == "table" and callbacks or {}

    local view = addon.UIFactory.CreateBackdropFrame(parent, theme.Colors.parchmentDark, theme.Colors.border)

    local backButton = addon.UIFactory.CreateButton(view, addon.L("BACK"), theme.Sizes.detailBackButtonWidth)
    backButton:SetPoint("TOPLEFT", view, "TOPLEFT", theme.Spacing.lg, -theme.Spacing.md)
    backButton:SetScript("OnClick", function()
        if type(callbacks.onBack) == "function" then
            callbacks.onBack()
        end
    end)


    local editButton = addon.UIFactory.CreateButton(view, addon.L("EDIT"), theme.Sizes.dialogButtonWidth)
    editButton:SetPoint("TOPRIGHT", view, "TOPRIGHT", -theme.Spacing.lg, -theme.Spacing.md)
    editButton:SetScript("OnClick", function()
        if type(callbacks.onEdit) == "function" then
            callbacks.onEdit()
        end
    end)

    local deleteButton = addon.UIFactory.CreateButton(view, addon.L("DELETE"), theme.Sizes.deleteButtonWidth)
    deleteButton:SetPoint("RIGHT", editButton, "LEFT", -theme.Spacing.sm, 0)
    deleteButton:SetScript("OnClick", function()
        if type(callbacks.onDelete) == "function" then
            callbacks.onDelete()
        end
    end)

    local favoriteButton = addon.UIFactory.CreateButton(
        view,
        addon.L("FAVORITE_ADD"),
        130
    )
    favoriteButton:SetPoint("RIGHT", deleteButton, "LEFT", -theme.Spacing.sm, 0)
    favoriteButton:SetScript("OnClick", function()
        if type(callbacks.onFavorite) == "function" then
            callbacks.onFavorite(view.spellID)
        end
    end)

    local insertChatButton = addon.UIFactory.CreateButton(view, addon.L("INSERT_IN_CHAT"), theme.Sizes.chatButtonWidth)
    insertChatButton:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -theme.Spacing.lg, theme.Spacing.lg)
    insertChatButton:SetShown(type(callbacks.onInsertChat) == "function")
    insertChatButton:SetScript("OnClick", function()
        if type(callbacks.onInsertChat) == "function" then
            callbacks.onInsertChat(view.spellID)
        end
    end)

    local whisperButton = addon.UIFactory.CreateButton(
        view,
        addon.L("CHAT_FALLBACK_WHISPER"),
        theme.Sizes.exportActionButtonWidth
    )
    whisperButton:SetPoint("RIGHT", insertChatButton, "LEFT", -theme.Spacing.sm, 0)
    whisperButton:SetShown(type(callbacks.onWhisper) == "function")
    whisperButton:SetScript("OnClick", function()
        if type(callbacks.onWhisper) == "function" then
            callbacks.onWhisper(view.spellID)
        end
    end)

    local exportButton = addon.UIFactory.CreateButton(view, addon.L("EXPORT"), theme.Sizes.exportActionButtonWidth)
    exportButton:SetPoint("RIGHT", whisperButton, "LEFT", -theme.Spacing.sm, 0)
    exportButton:SetScript("OnClick", function()
        if type(callbacks.onExport) == "function" then
            callbacks.onExport(view.spellID)
        end
    end)

    local gameMasterButton = addon.UIFactory.CreateButton(
        view,
        addon.L("GAMEMASTER_CAST_SPELL"),
        150
    )
    gameMasterButton:SetPoint("BOTTOMLEFT", view, "BOTTOMLEFT", theme.Spacing.lg, theme.Spacing.lg + theme.Sizes.buttonHeight + 8)
    gameMasterButton:SetScript("OnClick", function()
        if view.timedEffectAction then
            addon.TimedEffectsView.Cast(view.spellID)
            return
        end
        if type(callbacks.onGameMasterAction) == "function" then
            callbacks.onGameMasterAction(view.spellID)
        end
    end)

    local effectsButton = addon.UIFactory.CreateButton(view, addon.L("QUICK_PIN"), 150)
    effectsButton:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -theme.Spacing.lg, theme.Spacing.lg + theme.Sizes.buttonHeight + 8)
    effectsButton:SetScript("OnClick", function()
        if view.quickProfile ~= addon.Database.GetActiveProfileKey() then return end
        if addon.QuickAccess and addon.QuickAccess.Toggle(view.spellID) then
            effectsButton:SetText(addon.L(addon.QuickAccess.IsPinned(view.spellID) and "QUICK_UNPIN" or "QUICK_PIN"))
        end
    end)
    view.effectsButton = effectsButton

    local copyButton = addon.UIFactory.CreateButton(
        view,
        addon.L("ARCHIVE_COPY_SPELL"),
        150
    )
    copyButton:SetPoint("BOTTOMLEFT", view, "BOTTOMLEFT", theme.Spacing.lg, theme.Spacing.lg)
    copyButton:SetScript("OnClick", function()
        if type(callbacks.onCopy) == "function" then
            callbacks.onCopy(view.spellID)
        end
    end)

    local scrollFrame = CreateFrame("ScrollFrame", nil, view, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", view, "TOPLEFT", theme.Spacing.lg, -theme.Spacing.xl - theme.Sizes.buttonHeight)
    scrollFrame:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -theme.Spacing.xl, theme.Spacing.xl + theme.Sizes.buttonHeight)

    local normalMouseWheel = scrollFrame:GetScript("OnMouseWheel")
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        if view.hideScrollBar then
            local target = self:GetVerticalScroll() - delta * 36
            self:SetVerticalScroll(math.max(0, math.min(target, self:GetVerticalScrollRange())))
        elseif normalMouseWheel then
            normalMouseWheel(self, delta)
        end
    end)
    if scrollFrame.ScrollBar then
        scrollFrame.ScrollBar:HookScript("OnShow", function(bar)
            if view.hideScrollBar then bar:Hide() end
        end)
    end

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
    scrollChild:SetSize(1, 1)
    scrollFrame:SetScrollChild(scrollChild)

    local icon = scrollChild:CreateTexture(nil, "ARTWORK")
    icon:SetSize(theme.Sizes.detailIcon, theme.Sizes.detailIcon)
    icon:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)

    local name = addon.UIFactory.CreateLabel(scrollChild, theme.Fonts.header, "", theme.Colors.gold)
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", theme.Spacing.md, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(true)

    local magicSubtitle = addon.UIFactory.CreateLabel(scrollChild, theme.Fonts.small, "", theme.Colors.textMuted)
    magicSubtitle:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -theme.Spacing.xs)
    magicSubtitle:SetJustifyH("LEFT")

    local metadata = addon.UIFactory.CreateLabel(scrollChild, theme.Fonts.body, "", theme.Colors.text)
    metadata:SetPoint("TOPLEFT", magicSubtitle, "BOTTOMLEFT", 0, -theme.Spacing.sm)
    metadata:SetJustifyH("LEFT")
    metadata:SetJustifyV("TOP")

    local descriptionTitle = addon.UIFactory.CreateLabel(scrollChild, theme.Fonts.body, addon.L("FIELD_DESCRIPTION"), theme.Colors.gold)
    local description = addon.UIFactory.CreateLabel(scrollChild, theme.Fonts.body, "", theme.Colors.text)
    description:SetJustifyH("LEFT")
    description:SetJustifyV("TOP")
    description:SetWordWrap(true)

    local tagsTitle = addon.UIFactory.CreateLabel(scrollChild, theme.Fonts.body, addon.L("FIELD_PROPERTIES"), theme.Colors.gold)
    local tags = addon.UIFactory.CreateLabel(scrollChild, theme.Fonts.small, "", theme.Colors.textMuted)
    tags:SetJustifyH("LEFT")
    tags:SetJustifyV("TOP")
    tags:SetWordWrap(true)

    view.canExport = type(callbacks.onExport) == "function"
    view.canCopy = type(callbacks.onCopy) == "function"
    view.copyButton = copyButton
    view.backButton = backButton
    view.deleteButton = deleteButton
    view.description = description
    view.descriptionTitle = descriptionTitle
    view.editButton = editButton
    view.exportButton = exportButton
    view.favoriteButton = favoriteButton
    view.icon = icon
    view.gameMasterButton = gameMasterButton
    view.canGameMasterAction = type(callbacks.onGameMasterAction) == "function"
    view.insertChatButton = insertChatButton
    view.whisperButton = whisperButton
    view.magicSubtitle = magicSubtitle
    view.metadata = metadata

    view.name = name
    view.scrollChild = scrollChild
    view.scrollFrame = scrollFrame
    view.tags = tags
    view.tagsTitle = tagsTitle
    view.themeButtons = {
        effectsButton,
        backButton,
        editButton,
        deleteButton,
        favoriteButton,
        insertChatButton,
        whisperButton,
        exportButton,
        gameMasterButton,
        copyButton,
    }

    view:SetScript("OnSizeChanged", function()
        if view:IsShown() then
            layoutContent(view)
        end
    end)
    view:SetScript("OnShow", function()
        layoutContent(view)
    end)
    view:Hide()
    return view
end

function addon.SpellDetailsView.ApplyTheme(view, themeSpec, fancy, spell, backgroundThemeID)
    local viewType = type(view)
    if (viewType ~= "table" and viewType ~= "userdata")
        or type(themeSpec) ~= "table"
    then
        return false
    end
    local theme = addon.Theme
    addon.SpellDetailsView.StopReadingReveal(view)
    if backgroundThemeID and not fancy then
        themeSpec, view.bookThemeID = addon.SpellCreationThemes.ApplyBook(view, backgroundThemeID)
        view.bookThemeSpec = themeSpec
    else
        if view.bookThemeID then addon.SpellCreationThemes.ClearBook(view) end
        view.bookThemeID, view.bookThemeSpec = nil, nil
    end
    view.fancyReading = fancy == true
    view.hideScrollBar = view.fancyReading or view.bookThemeID ~= nil
    styleScrollBar(view)
    view.readingIconSize = fancy and 72 or theme.Sizes.detailIcon
    view.icon:SetSize(view.readingIconSize, view.readingIconSize)
    for _, label in ipairs({ view.name, view.description, view.metadata, view.tags, view.magicSubtitle }) do
        if not label.readingBaseFont and label.GetFont then label.readingBaseFont = { label:GetFont() } end
    end
    if fancy then
        view:SetBackdropColor(0, 0, 0, 0)
        view:SetBackdropBorderColor(0, 0, 0, 0)
    else
        local background = view.bookThemeSpec and themeSpec.background or theme.Colors.parchmentDark
        local border = view.bookThemeSpec and themeSpec.border or theme.Colors.border
        view:SetBackdropColor(
            background[1], background[2], background[3], background[4]
        )
        view:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
    end

    local themed = fancy or view.bookThemeSpec ~= nil
    addon.BookLayout.SetNameColor(
        view.name,
        spell and spell.nameColor or nil,
        themed and themeSpec.accent or theme.Colors.gold,
        fancy
    )
    local accent = themed and themeSpec.accent or theme.Colors.gold
    local text = themed and themeSpec.text or theme.Colors.text
    local muted = themed and themeSpec.textMuted or theme.Colors.textMuted
    for _, label in ipairs({ view.descriptionTitle, view.tagsTitle }) do
        label:SetTextColor(accent[1], accent[2], accent[3], accent[4])
    end
    view.magicSubtitle:SetTextColor(muted[1], muted[2], muted[3], muted[4])
    view.metadata:SetTextColor(text[1], text[2], text[3], text[4])
    view.description:SetTextColor(text[1], text[2], text[3], text[4])
    view.tags:SetTextColor(muted[1], muted[2], muted[3], muted[4])
    local factory = addon.UIFactory
    if factory and type(factory.ApplyBookFont) == "function" then
        factory.ApplyBookFont(view.name, fancy, 3)
        factory.ApplyBookFont(view.magicSubtitle, false, 0)
        factory.ApplyBookFont(view.metadata, false, 0)
        factory.ApplyBookFont(view.descriptionTitle, fancy, 1)
        factory.ApplyBookFont(view.description, false, 0)
        factory.ApplyBookFont(view.tagsTitle, fancy, 1)
        factory.ApplyBookFont(view.tags, false, 0)
    end
    for _, item in ipairs({ { view.name, 26 }, { view.description, 18 },
            { view.metadata, 16 }, { view.tags, 16 }, { view.magicSubtitle, 15 } }) do
        local label, size = item[1], item[2]
        if label.GetFont and label.SetFont then
            local original = label.readingBaseFont
            label:SetFont(fancy and addon.BookLayout.Font or original[1], fancy and size or original[2], fancy and "" or original[3] or "")
        end
    end
    addon.BookLayout.IconInk(view.icon, fancy)
    for _, label in ipairs({ view.name, view.description, view.descriptionTitle,
            view.metadata, view.tags, view.tagsTitle, view.magicSubtitle }) do
        addon.BookLayout.TextInk(label, fancy,
            label == view.name and addon.BookLayout.Ink.name or addon.BookLayout.Ink.body)
    end
    if spell then
        view.metadata:SetText(formatMetadata(spell, fancy))
        view.tags:SetText(formatTags(spell.tags, fancy))
    end
    for _, button in ipairs(view.themeButtons or {}) do
        if factory and type(factory.ApplyButtonStyle) == "function" then
            factory.ApplyButtonStyle(
                button,
                fancy and "book" or "modern",
                fancy and nil or false
            )
        end
        if type(button.SetAlpha) == "function" then
            button:SetAlpha(fancy and 0.92 or 1)
        end
        local fontString = type(button.GetFontString) == "function"
            and button:GetFontString() or nil
        if factory and type(factory.ApplyBookFont) == "function" then
            factory.ApplyBookFont(fontString, false, 0)
        end
        if fontString and type(fontString.SetTextColor) == "function" then
            fontString:SetTextColor(
                fancy and 0.10 or 1,
                fancy and 0.045 or 0.82,
                fancy and 0.015 or 0,
                1
            )
        end
    end
    if view:IsShown() then layoutContent(view) end
    if addon.BookMagic then addon.BookMagic.SetText(view, view.name, spell, fancy, view.ownerPanel, view.description) end
    return true
end

function addon.SpellDetailsView.SetSpell(
    view,
    spell,
    canModify,
    allowGameMasterAction,
    allowCopy,
    favorite
)
    if not view or type(spell) ~= "table" then
        return false
    end

    view.spellID = spell.id
    view.quickProfile = addon.QuickAccess and addon.Database.GetActiveProfileKey() or nil
    addon.BookLayout.SetSpellIcon(view.icon, spell, addon.Constants.DEFAULT_BOOK_ICON, nil, view.fancyReading)
    view.name:SetText(hasText(spell.name) and spell.name or addon.L("UNKNOWN_ABILITY"))
    addon.BookLayout.SetNameColor(view.name, spell.nameColor,
        view.bookThemeSpec and view.bookThemeSpec.accent or addon.Theme.Colors.gold, view.fancyReading)

    local magicSummary = getMagicSummary(spell)
    view.magicSubtitle:SetText(magicSummary)
    view.magicSubtitle:SetShown(magicSummary ~= "")

    local metadata = formatMetadata(spell, view.fancyReading)
    view.metadata:SetText(metadata)
    view.metadata:SetShown(metadata ~= "")

    local description = hasText(spell.description) and spell.description or ""
    view.description:SetText(description)
    view.description:SetShown(description ~= "")
    view.descriptionTitle:SetShown(description ~= "")

    local tags = formatTags(spell.tags, view.fancyReading)
    view.tags:SetText(tags)
    view.tags:SetShown(tags ~= "")
    view.tagsTitle:SetShown(tags ~= "")

    view.editButton:SetShown(canModify == true)
    if view.effectsButton then
        view.effectsButton:SetShown(canModify == true and addon.QuickAccess ~= nil)
        view.effectsButton:SetText(addon.L(addon.QuickAccess and addon.QuickAccess.IsPinned(spell.id) and "QUICK_UNPIN" or "QUICK_PIN"))
    end
    view.exportButton:SetShown(canModify == true and view.canExport)
    view.deleteButton:SetShown(canModify == true)
    view.favoriteButton:SetShown(canModify == true)
    view.favoriteButton:SetText(
        favorite == true and addon.L("FAVORITE_REMOVE")
            or addon.L("FAVORITE_ADD")
    )
    view.timedEffectAction = canModify == true and addon.TimedEffects
        and addon.Database.GetSpell(spell.id) == spell
        and addon.TimedEffects.CanCast(spell.id) or false
    view.gameMasterButton:SetText(addon.L(view.timedEffectAction and "TIMED_CAST" or "GAMEMASTER_CAST_SPELL"))
    view.gameMasterButton:SetShown(view.timedEffectAction or (allowGameMasterAction == true and view.canGameMasterAction))
    view.copyButton:SetShown(allowCopy == true and view.canCopy)

    view.scrollFrame:SetVerticalScroll(0)
    if view:IsShown() then
        layoutContent(view)
    end
    return true
end
