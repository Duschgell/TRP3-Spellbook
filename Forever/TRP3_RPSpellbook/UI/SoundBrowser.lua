local _, addon = ...

addon.SoundBrowser = {}

local window
local request
local rowsPerPage = 8
local tab, page, query = "recommended", 1, ""
local catalog, filtered = {}, {}
local selectedID

local function raiseAboveOwner()
    local anchor = request and request.anchor
    if not anchor then return end
    local ownerStrata = anchor.GetFrameStrata and anchor:GetFrameStrata()
    local raisedStrata = ownerStrata == "FULLSCREEN" or ownerStrata == "FULLSCREEN_DIALOG"
        or ownerStrata == "TOOLTIP"
    local strata = raisedStrata and ownerStrata or "DIALOG"
    if window:GetFrameStrata() ~= strata then window:SetFrameStrata(strata) end
    if anchor.GetFrameLevel and window:GetFrameLevel() <= anchor:GetFrameLevel() then
        window:SetFrameLevel(anchor:GetFrameLevel() + 10)
    end
end

local function readable(widget)
    local text = widget.GetFontString and widget:GetFontString() or widget
    if text and text.GetFont and text.SetFont then
        local font, _, flags = text:GetFont()
        if font then text:SetFont(font, 14, flags) end
    end
    return widget
end

local function playbackButton(button, id)
    local state = id and addon.GameMasterTurnSound.GetPlaybackState(id, "preview") or "idle"
    if button.playbackState ~= state then
        button.playbackState = state
        button:SetText(addon.L(state == "playing" and "SOUND_BROWSER_STOP"
            or state == "unconfirmed" and "SOUND_BROWSER_STOP_UNCONFIRMED"
            or state == "failed" and "SOUND_BROWSER_RETRY" or "GAMEMASTER_TURN_SOUND_PREVIEW"))
        if state == "playing" then button:LockHighlight() else button:UnlockHighlight() end
    end
end

local function refreshPlayback()
    for _, row in ipairs(window.rows) do
        playbackButton(row.preview, row.entry and row.entry.id)
    end
    playbackButton(window.preview, selectedID)
end

local function validRequest()
    local current = request
    if not current or not window or not window:IsShown() then return false end
    if not current.isValid then return true end
    local ok, valid = pcall(current.isValid)
    return ok and valid == true and request == current and window:IsShown()
end

local function setStatus(key, ...)
    window.status:SetText(key and string.format(addon.L(key), ...) or "")
    window.help:SetShown(key == nil)
end

local function refreshRows()
    local pages = math.max(1, math.ceil(#filtered / rowsPerPage))
    page = math.max(1, math.min(page, pages))
    for index, row in ipairs(window.rows) do
        local entry = filtered[(page - 1) * rowsPerPage + index]
        row.entry = entry
        row:SetShown(entry ~= nil)
        if entry then
            row.label:SetText(entry.name .. "  (" .. entry.id .. ")")
            local selected = selectedID == entry.id
            if selected then row:LockHighlight() else row:UnlockHighlight() end
            local color = selected and addon.Theme.Colors.gold or addon.Theme.Colors.text
            row.label:SetTextColor(color[1], color[2], color[3], color[4])
        end
    end
    window.pageLabel:SetText(string.format(addon.L("SOUND_BROWSER_PAGE"), page, pages, #filtered))
    window.previous:SetEnabled(page > 1)
    window.next:SetEnabled(page < pages)
    window.empty:SetShown(#filtered == 0)
    window.select:SetEnabled(selectedID ~= nil)
    window.preview:SetEnabled(selectedID ~= nil)
    refreshPlayback()
end

local function filterCatalog()
    filtered = {}
    local entries = tab == "recommended" and catalog.recommended or catalog.all
    for _, entry in ipairs(entries or {}) do
        if query == "" or string.lower(entry.name):find(query, 1, true)
            or string.lower(entry.key):find(query, 1, true)
            or tostring(entry.id):find(query, 1, true) then
            filtered[#filtered + 1] = entry
        end
    end
    page = 1
    refreshRows()
end

local function preview()
    if not validRequest() or not selectedID then return false end
    local sound = addon.GameMasterTurnSound
    local played
    local state = sound.GetPlaybackState(selectedID, "preview")
    if state == "playing" or state == "unconfirmed" then
        played = sound.Stop("preview", selectedID)
    else
        played = sound.Play("kit:" .. selectedID, "preview")
    end
    refreshPlayback()
    return played
end

local function choose(entry)
    if not validRequest() or not entry then return end
    window.id:SetText(tostring(entry.id))
end

local function createWindow()
    local factory, theme = addon.UIFactory, addon.Theme
    local frame = factory.CreateDialog(addon.L("SOUND_BROWSER_TITLE"), 620, 594)
    frame:SetFrameStrata("DIALOG")
     
     
    if _G.TRP3_BACKDROP_ACHIEVEMENT_TOOLTIP then
        frame:SetBackdrop(_G.TRP3_BACKDROP_ACHIEVEMENT_TOOLTIP)
        frame:SetBackdropColor(1, 1, 1, 1)
        frame:SetBackdropBorderColor(0.7, 0.7, 0.7, 1)
    end
    frame.closeButton:Hide()
    frame.closeButton:SetScript("OnClick", function() addon.SoundBrowser.Close() end)
     
     
    frame:HookScript("OnMouseDown", raiseAboveOwner)
    local help = readable(factory.CreateLabel(frame, theme.Fonts.body, addon.L("SOUND_BROWSER_HELP"), theme.Colors.text))
    help:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -46)
    help:SetSize(580, 42)
    help:SetWordWrap(true)
    help:SetJustifyH("LEFT")
    frame.help = help
    local recommended = readable(factory.CreateButton(frame, addon.L("SOUND_BROWSER_RECOMMENDED"), 180))
    recommended:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -96)
    local all = readable(factory.CreateButton(frame, addon.L("SOUND_BROWSER_ALL"), 230))
    all:SetPoint("LEFT", recommended, "RIGHT", 8, 0)
    local function setTab(nextTab)
        if not validRequest() then return end
        tab = nextTab
        if tab == "recommended" then recommended:LockHighlight(); all:UnlockHighlight()
        else all:LockHighlight(); recommended:UnlockHighlight() end
        filterCatalog()
    end
    recommended:SetScript("OnClick", function() setTab("recommended") end)
    all:SetScript("OnClick", function() setTab("all") end)
    frame.recommended, frame.all = recommended, all
    frame.search = factory.CreateEditBox(frame)
    frame.search:SetPoint("TOPLEFT", frame, "TOPLEFT", 26, -132)
    frame.search:SetWidth(568)
    readable(frame.search)
    frame.search:SetMaxLetters(80)
    frame.search:SetScript("OnTextChanged", function(self)
        if not validRequest() then return end
        query = string.lower(addon.Runtime.Trim(self:GetText()) or "")
        filterCatalog()
    end)
    local placeholder = readable(factory.CreateLabel(frame.search, theme.Fonts.body, addon.L("SOUND_BROWSER_SEARCH"), theme.Colors.text))
    placeholder:SetPoint("LEFT", frame.search, "LEFT", 8, 0)
    frame.search:HookScript("OnTextChanged", function(self) placeholder:SetShown(self:GetText() == "") end)
    frame.rows = {}
    for index = 1, rowsPerPage do
        local row = CreateFrame("Button", nil, frame, "BackdropTemplate")
        row:SetSize(580, 30)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
        row:SetBackdropColor(0.12, 0.12, 0.12, index % 2 == 0 and 0.65 or 0.35)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -170 - (index - 1) * 32)
        row.label = readable(factory.CreateLabel(row, theme.Fonts.body, "", theme.Colors.text))
        row.label:SetPoint("LEFT", row, "LEFT", 10, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -122, 0)
        row.label:SetWordWrap(false)
        row.label:SetJustifyH("LEFT")
        row:SetScript("OnClick", function() choose(row.entry) end)
        local play = readable(factory.CreateButton(row, addon.L("GAMEMASTER_TURN_SOUND_PREVIEW"), 108))
        play:SetFrameLevel(row:GetFrameLevel() + 1)
        play:SetHeight(26)
        play:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        play:SetScript("OnClick", function()
            choose(row.entry)
            preview()
        end)
        row.preview = play
        frame.rows[index] = row
    end
    frame.empty = factory.CreateLabel(frame, theme.Fonts.body, addon.L("SOUND_BROWSER_EMPTY"), theme.Colors.textMuted)
    frame.empty:SetPoint("TOP", frame, "TOP", 0, -220)
    frame.previous = factory.CreateButton(frame, "<", 34)
    frame.previous:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -430)
    frame.previous:SetScript("OnClick", function()
        if validRequest() then page = page - 1; refreshRows() end
    end)
    frame.next = factory.CreateButton(frame, ">", 34)
    frame.next:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, -430)
    frame.next:SetScript("OnClick", function()
        if validRequest() then page = page + 1; refreshRows() end
    end)
    frame.pageLabel = readable(factory.CreateLabel(frame, theme.Fonts.body, "", theme.Colors.text))
    frame.pageLabel:SetPoint("TOP", frame, "TOP", 0, -436)
    local idLabel = readable(factory.CreateLabel(frame, theme.Fonts.body, addon.L("SOUND_BROWSER_ID"), theme.Colors.text))
    idLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -478)
    frame.id = factory.CreateEditBox(frame)
    frame.id:SetPoint("LEFT", idLabel, "RIGHT", 14, 0)
    frame.id:SetWidth(150)
    readable(frame.id)
    frame.id:SetMaxLetters(32)
    frame.id:SetScript("OnTextChanged", function(self)
        if not validRequest() then return end
        selectedID = addon.SoundCatalog.ParseID(self:GetText())
        if selectedID then setStatus(nil) else setStatus("SOUND_BROWSER_INVALID") end
        refreshRows()
    end)
    frame.preview = readable(factory.CreateButton(frame, addon.L("GAMEMASTER_TURN_SOUND_PREVIEW"), 108))
    frame.preview:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, -472)
    frame.preview:SetScript("OnClick", preview)
    frame.stop = readable(factory.CreateButton(frame, addon.L("SOUND_BROWSER_STOP_ALL"), 200))
    frame.stop:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 16)
    frame.stop:SetScript("OnClick", function()
        if validRequest() then addon.GameMasterTurnSound.StopAll(); refreshPlayback() end
    end)
    local scope = readable(factory.CreateLabel(frame, theme.Fonts.body, addon.L("SOUND_BROWSER_STOP_SCOPE"), theme.Colors.text))
    scope:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -506)
    scope:SetSize(580, 36)
    scope:SetWordWrap(true)
    scope:SetJustifyH("LEFT")
    frame.status = readable(factory.CreateLabel(frame, theme.Fonts.body, "", theme.Colors.error))
    frame.status:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -46)
    frame.status:SetSize(580, 42)
    frame.status:SetWordWrap(true)
    frame.status:SetJustifyH("LEFT")
    frame.select = readable(factory.CreateButton(frame, addon.L("SOUND_BROWSER_SELECT"), 150))
    frame.select:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 16)
    frame.select:SetScript("OnClick", function()
        if not validRequest() or not selectedID then addon.SoundBrowser.Close(); return end
        local current = request
        local value = "kit:" .. selectedID
        local ok, result = pcall(current.onSelect, value)
        if not ok or result == false then
            if request == current then setStatus("SOUND_BROWSER_SAVE_FAILED") end
            return
        end
         
        if request == current then addon.SoundBrowser.Close() end
    end)
    frame.cancel = readable(factory.CreateButton(frame, addon.L("CANCEL"), 150))
    frame.cancel:SetPoint("RIGHT", frame.select, "LEFT", -8, 0)
    frame.cancel:SetScript("OnClick", function() addon.SoundBrowser.Close() end)
    frame:HookScript("OnHide", function()
        frame:SetScript("OnUpdate", nil)
        request, selectedID = nil, nil
        catalog, filtered = {}, {}
        addon.GameMasterTurnSound.Stop("preview")
    end)
    return frame
end

function addon.SoundBrowser.Close(owner)
    if owner and (not request or request.owner ~= owner) then return false end
    if window then window:Hide() end
    return true
end

function addon.SoundBrowser.Open(preset, onSelect, options)
    if type(onSelect) ~= "function" then return false end
    options = type(options) == "table" and options or {}
    if options.isValid and type(options.isValid) ~= "function" then return false end
    addon.SoundBrowser.Close()
    window = window or createWindow()
    request = { onSelect = onSelect, isValid = options.isValid, owner = options.owner }
    tab, page, query = "recommended", 1, ""
    selectedID = addon.SoundCatalog.GetPresetID(preset)
    catalog = { recommended = addon.SoundCatalog.GetRecommended(), all = addon.SoundCatalog.GetAll() }
    window:Show()
    local anchor = options.owner
    if (type(anchor) ~= "table" and type(anchor) ~= "userdata") or type(anchor.IsShown) ~= "function" then
        anchor = _G.TRP3_MainFrame
    end
    if not anchor or not anchor:IsShown() then anchor = UIParent end
    request.anchor = anchor
    raiseAboveOwner()
    window:ClearAllPoints()
    window:SetPoint("CENTER", anchor, "CENTER", 0, -10)
    window:SetScale(math.min(1, (UIParent:GetWidth() - 32) / 620, (UIParent:GetHeight() - 32) / 594))
    local current, elapsed = request, 0
    window:SetScript("OnUpdate", function(_, delta)
        if request ~= current then return end
        elapsed = elapsed + delta
        if elapsed < 0.1 then return end
        elapsed = 0
        if not validRequest() or not anchor:IsShown() then
            if request == current then addon.SoundBrowser.Close() end
            return
        end
        raiseAboveOwner()
        refreshPlayback()
    end)
    window.recommended:LockHighlight()
    window.all:UnlockHighlight()
    window.search:SetText("")
    window.id:SetText(selectedID and tostring(selectedID) or "")
    filterCatalog()
    setStatus(nil)
    addon.UIFactory.BringToFront(window)
    raiseAboveOwner()
    return true
end
