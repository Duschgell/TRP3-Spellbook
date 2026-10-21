local _, addon = ...

addon.ImportWindow = {}

local window
local state = {}

local function debugLog(stage, detail)
    if not addon.ImportDebug or addon.ImportDebug.enabled ~= true then
        return
    end
    local log = addon.ImportDebug.Log
    if type(log) == "function" then
        pcall(log, stage, detail)
    end
end

local function setStatus(message, isError)
    window.status:SetText(message or "")
    local color = isError and addon.Theme.Colors.error or addon.Theme.Colors.textMuted
    window.status:SetTextColor(color[1], color[2], color[3], color[4])
    debugLog("status", (isError and "error: " or "info: ") .. tostring(message or ""))
end

local function setImportEnabled(enabled)
    if enabled then
        window.importButton:Enable()
    else
        window.importButton:Disable()
    end
    debugLog("import.enabled", tostring(enabled == true))
end

local function clearPreview()
    state.decoded = nil
    state.checkedText = nil
    if window then
        window.previewMeta:SetText("")
        window.previewDetails:Hide()
        window.collectionPreview:SetText("")
        window.collectionPreview:Hide()
        setImportEnabled(false)
    end
end

local function formatExpiration(expiresAt)
    if not expiresAt or expiresAt <= 0 then
        return addon.L("IMPORT_EXPIRES_NEVER")
    end
    local now = type(time) == "function" and time() or 0
    local formatted = tostring(expiresAt)
    if type(date) == "function" then
        local success, result = pcall(date, "%Y-%m-%d %H:%M", expiresAt)
        if success and type(result) == "string" then
            formatted = result
        end
    end
    if now >= expiresAt then
        return addon.L("IMPORT_EXPIRED_AT", formatted)
    end
    return addon.L("IMPORT_EXPIRES_AT", formatted)
end

local function getExportTypeLabel(exportType)
    if exportType == "tab" then return addon.L("EXPORT_TYPE_TAB") end
    if exportType == "book" then return addon.L("EXPORT_TYPE_BOOK") end
    return addon.L("EXPORT_TYPE_SPELL")
end

local function countCollection(decoded)
    local book = decoded.book
    local tabCount = type(book) == "table" and type(book.tabOrder) == "table" and #book.tabOrder or 0
    local spellCount = 0
    if type(book) == "table" and type(book.spells) == "table" then
        for _ in pairs(book.spells) do spellCount = spellCount + 1 end
    end
    return tabCount, spellCount
end

local function buildPreviewMeta(decoded)
    local meta = decoded.exportMeta
    local owner = addon.Import.GetOwnerDisplayName(decoded.owner)
    local parts = {
        addon.L("IMPORT_PREVIEW_TYPE", getExportTypeLabel(meta.exportType)),
        addon.L("IMPORT_PREVIEW_OWNER", owner),
        addon.L("IMPORT_OWNER_UNVERIFIED"),
        formatExpiration(meta.expiresAt),
        addon.L("IMPORTED_CONTENT_VIEW_ONLY"),
    }
    if meta.exportType ~= "spell" then
        local tabCount, spellCount = countCollection(decoded)
        parts[#parts + 1] = addon.L("IMPORT_PREVIEW_COUNTS", tabCount, spellCount)
    end
    return table.concat(parts, "\n")
end

local function buildCollectionPreview(decoded)
    local book = decoded.book
    local lines = { type(book.name) == "string" and book.name or addon.L("DEFAULT_BOOK_NAME") }
    local maximumVisibleTabs = 8
    for index, tabID in ipairs(book.tabOrder) do
        if index > maximumVisibleTabs then
            lines[#lines + 1] = addon.L("IMPORT_PREVIEW_MORE_TABS", #book.tabOrder - maximumVisibleTabs)
            break
        end
        local tab = book.tabs[tabID]
        lines[#lines + 1] = addon.L(
            "IMPORT_PREVIEW_TAB_ROW",
            type(tab) == "table" and tab.name or addon.L("UNKNOWN"),
            type(tab) == "table" and type(tab.spellIds) == "table" and #tab.spellIds or 0
        )
    end
    return table.concat(lines, "\n")
end

local function checkImport()
    debugLog("check.enter", "handler reached")
    local input = window.input:GetText() or ""
    debugLog("check.input", "bytes=" .. tostring(#input))
    clearPreview()
    setStatus(addon.L("IMPORT_CHECKING"), false)

    debugLog("decode.begin")
    local decodeSuccess, decoded, errorMessage = pcall(addon.Import.Decode, input)
    debugLog("decode.end", string.format("call=%s decoded=%s error=%s", tostring(decodeSuccess), tostring(decoded ~= nil), tostring(errorMessage)))
    if not decodeSuccess then
        setStatus(addon.L("IMPORT_CHECK_FAILED"), true)
        addon.Logger.Error(addon.L("IMPORT_CHECK_FAILED_DETAIL", tostring(decoded)))
        return
    end
    if not decoded then
        setStatus(errorMessage or addon.L("IMPORT_INVALID_STRING"), true)
        return
    end

    local expiresAt = tonumber(decoded.exportMeta and decoded.exportMeta.expiresAt)
    if expiresAt and expiresAt > 0 and addon.Runtime.GetTimestamp() >= expiresAt then
        setStatus(addon.L("IMPORT_EXPIRED_CANNOT_IMPORT"), true)
        return
    end

    debugLog("preview.begin")
    local previewSuccess, previewReady = pcall(function()
        window.previewMeta:SetText(buildPreviewMeta(decoded))
        if decoded.exportMeta.exportType == "spell" then
            window.collectionPreview:Hide()
            window.previewDetails:Show()
            return addon.SpellDetailsView.SetSpell(window.previewDetails, decoded.spell, false)
        end
        window.previewDetails:Hide()
        window.collectionPreview:SetText(buildCollectionPreview(decoded))
        window.collectionPreview:Show()
        return true
    end)
    debugLog("preview.end", string.format("call=%s ready=%s", tostring(previewSuccess), tostring(previewReady)))
    if not previewSuccess or not previewReady then
        clearPreview()
        setStatus(addon.L("IMPORT_PREVIEW_FAILED"), true)
        if not previewSuccess then
            addon.Logger.Error(addon.L("IMPORT_PREVIEW_FAILED_DETAIL", tostring(previewReady)))
        end
        return
    end

    state.decoded = decoded
    state.checkedText = input
    state.lastContentName = decoded.spell and decoded.spell.name or decoded.book and decoded.book.name
    setImportEnabled(true)
    setStatus(addon.L("IMPORT_VALID"), false)
    debugLog("check.complete", "import enabled")
end

local function confirmImport()
    if not state.decoded or state.checkedText ~= (window.input:GetText() or "") then
        clearPreview()
        setStatus(addon.L("IMPORT_CHECK_REQUIRED"), true)
        return
    end

    local importedBook, errorMessage
    if state.decoded.exportMeta.exportType == "spell" then
        importedBook, errorMessage = addon.Database.AddImportedSpell(state.decoded)
    else
        importedBook, errorMessage = addon.Database.AddImportedBook(state.decoded)
    end
    if not importedBook then
        setStatus(errorMessage or addon.L("IMPORT_SAVE_FAILED"), true)
        return
    end

    local callback = state.onImported
    state.decoded = nil
    state.checkedText = nil
    state.onImported = nil
    window:Hide()
    addon.Logger.Info(addon.L("IMPORT_SUCCESS_CONTENT", state.lastContentName or importedBook.name))
    if type(callback) == "function" then
        callback(importedBook)
    end
end

local function createWindow()
    local theme = addon.Theme
    local frame = addon.UIFactory.CreateDialog(
        addon.L("IMPORT_CONTENT_TITLE"),
        theme.Sizes.importDialogWidth,
        theme.Sizes.importDialogHeight
    )

    local inputLabel = addon.UIFactory.CreateLabel(frame, theme.Fonts.body, addon.L("IMPORT_INPUT"), theme.Colors.gold)
    inputLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", theme.Spacing.lg, -(theme.Spacing.xl + theme.Spacing.lg))

    local input, inputContainer = addon.UIFactory.CreateTextArea(frame)
    inputContainer:SetPoint("TOPLEFT", inputLabel, "BOTTOMLEFT", 0, -theme.Spacing.xs)
    inputContainer:SetWidth(theme.Sizes.importDialogWidth - (theme.Spacing.lg * 2))
    inputContainer:SetHeight(theme.Sizes.importInputHeight)
    if type(input.SetMaxBytes) == "function" then
        input:SetMaxBytes(addon.Constants.MAX_EXPORT_STRING_LENGTH + 1)
    end

    local checkButton = addon.UIFactory.CreateButton(frame, addon.L("CHECK_IMPORT"), theme.Sizes.importActionButtonWidth)
    checkButton:SetFrameLevel(frame:GetFrameLevel() + 20)
    checkButton:SetPoint("TOPLEFT", inputContainer, "BOTTOMLEFT", 0, -theme.Spacing.sm)

    local status = addon.UIFactory.CreateLabel(frame, theme.Fonts.small, "", theme.Colors.textMuted)
    status:SetPoint("LEFT", checkButton, "RIGHT", theme.Spacing.sm, 0)
    status:SetWidth(theme.Sizes.importDialogWidth - (theme.Spacing.lg * 2) - theme.Sizes.importActionButtonWidth - theme.Spacing.sm)
    status:SetJustifyH("LEFT")

    local previewMeta = addon.UIFactory.CreateLabel(frame, theme.Fonts.small, "", theme.Colors.textMuted)
    previewMeta:SetPoint("TOPLEFT", checkButton, "BOTTOMLEFT", 0, -theme.Spacing.sm)
    previewMeta:SetWidth(theme.Sizes.importDialogWidth - (theme.Spacing.lg * 2))
    previewMeta:SetHeight(theme.Sizes.importPreviewMetaHeight)
    previewMeta:SetJustifyH("LEFT")
    previewMeta:SetJustifyV("TOP")
    previewMeta:SetWordWrap(true)

    local previewDetails = addon.SpellDetailsView.Create(frame, {})
    previewDetails:SetPoint("TOPLEFT", previewMeta, "BOTTOMLEFT", 0, -theme.Spacing.xs)
    previewDetails:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -theme.Spacing.lg, theme.Spacing.xl + theme.Sizes.buttonHeight)
    previewDetails.backButton:Hide()
    previewDetails:Hide()

    local collectionPreview = addon.UIFactory.CreateLabel(frame, theme.Fonts.body, "", theme.Colors.text)
    collectionPreview:SetPoint("TOPLEFT", previewMeta, "BOTTOMLEFT", 0, -theme.Spacing.md)
    collectionPreview:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -theme.Spacing.lg, theme.Spacing.xl + theme.Sizes.buttonHeight)
    collectionPreview:SetJustifyH("LEFT")
    collectionPreview:SetJustifyV("TOP")
    collectionPreview:SetWordWrap(true)
    collectionPreview:Hide()

    local importButton = addon.UIFactory.CreateButton(frame, addon.L("IMPORT_CONFIRM"), theme.Sizes.dialogButtonWidth)
    importButton:SetFrameLevel(frame:GetFrameLevel() + 20)
    importButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -theme.Spacing.lg, theme.Spacing.lg)
    importButton:Disable()

    local cancelButton = addon.UIFactory.CreateButton(frame, addon.L("CANCEL"), theme.Sizes.dialogButtonWidth)
    cancelButton:SetFrameLevel(frame:GetFrameLevel() + 20)
    cancelButton:SetPoint("RIGHT", importButton, "LEFT", -theme.Spacing.sm, 0)

    frame.importButton = importButton
    frame.input = input
    frame.previewDetails = previewDetails
    frame.previewMeta = previewMeta
    frame.collectionPreview = collectionPreview
    frame.status = status

    input:HookScript("OnTextChanged", function(self)
        local currentText = self:GetText() or ""
        if state.checkedText ~= nil and currentText ~= state.checkedText then
            clearPreview()
            setStatus(addon.L("IMPORT_CHECK_REQUIRED"), false)
        end
    end)
    checkButton:SetScript("OnClick", function()
        debugLog("check.onclick", "primary handler")
        checkImport()
    end)
    importButton:SetScript("OnClick", confirmImport)
    cancelButton:SetScript("OnClick", function() frame:Hide() end)
    frame.closeButton:SetScript("OnClick", function() frame:Hide() end)
    frame.closeButton:SetFrameLevel(frame:GetFrameLevel() + 20)
    if addon.ImportDebug and addon.ImportDebug.enabled == true and type(addon.ImportDebug.Attach) == "function" then
        local attached, attachError = pcall(addon.ImportDebug.Attach, frame, {
            input = input,
            inputContainer = inputContainer,
            checkButton = checkButton,
            importButton = importButton,
            cancelButton = cancelButton,
            onForceCheck = checkImport,
        })
        if not attached then
            addon.Logger.Error("Import debug attach failed: " .. tostring(attachError))
        end
    end
    return frame
end

function addon.ImportWindow.Open(onImported)
    window = window or createWindow()
    state.onImported = onImported
    state.lastContentName = nil
    clearPreview()
    window.input:SetText("")
    setStatus(addon.L("IMPORT_PASTE_CONTENT_HINT"), false)
    window:Show()
    addon.UIFactory.BringToFront(window)
    window.input:SetFocus()
end
