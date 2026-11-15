local _, addon = ...
local view = {}
addon.BackupWindow = view
local window, scope, prepared, checkedText, checkedBinding
local scopes = { "core", "full", "settings", "npc" }
local labels = { core = "BACKUP_SCOPE_CORE", full = "BACKUP_SCOPE_FULL", settings = "BACKUP_SCOPE_SETTINGS", npc = "BACKUP_SCOPE_NPC" }

local function status(key) window.status:SetText(addon.L(key or "BACKUP_GUIDANCE")) end
local function clear()
    prepared, checkedText, checkedBinding = nil, nil, nil
    window.restore:Disable()
end

local function check()
    clear()
    local input, source = window.text:GetText(), window.binding:GetText()
    source = source ~= "" and source or nil
    local destination = source and addon.Database.GetActiveProfileKey() or nil
    local plan, err = addon.Backup.Prepare(input, source, destination)
    if not plan then status(err); return end
    prepared, checkedText, checkedBinding = plan, input, source
    window.restore:Enable()
    window.status:SetText(addon.L("BACKUP_CHECKED", addon.L(labels[plan.scope]), source or "-", destination or "-"))
end

local function confirm()
    local plan, text, binding = prepared, checkedText, checkedBinding
    if not plan then return end
    addon.UIFactory.ShowConfirmation(addon.L("BACKUP_TITLE"), addon.L("BACKUP_CONFIRM", addon.L(labels[plan.scope])), function()
         
        if prepared ~= plan or not window:IsShown() or window.text:GetText() ~= text
            or (window.binding:GetText() ~= "" and window.binding:GetText() or nil) ~= binding
            or binding and addon.Database.GetActiveProfileKey() ~= plan.destinationProfile then
            clear(); status("BACKUP_CHECK_REQUIRED"); return
        end
        local ok, err = addon.Backup.Stage(plan, true)
        clear(); status(err)
        if ok then window.reload:Enable() end
    end)
end

local function create()
    local factory, theme = addon.UIFactory, addon.Theme
    local frame = factory.CreateDialog(addon.L("BACKUP_TITLE"), 680, 600)
    local description = factory.CreateLabel(frame, theme.Fonts.small, addon.L("BACKUP_GUIDANCE"), theme.Colors.textMuted)
    description:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -48)
    description:SetWidth(640); description:SetWordWrap(true); description:SetJustifyH("LEFT")
    local scopeButton = factory.CreateButton(frame, "", 260)
    scopeButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -142)
    local export = factory.CreateButton(frame, addon.L("BACKUP_EXPORT"), 150)
    export:SetPoint("LEFT", scopeButton, "RIGHT", 12, 0)
    local recovery = factory.CreateButton(frame, addon.L("BACKUP_RECOVERY"), 170)
    recovery:SetPoint("LEFT", export, "RIGHT", 12, 0)
    local text, container = factory.CreateTextArea(frame)
    container:SetPoint("TOPLEFT", scopeButton, "BOTTOMLEFT", 0, -14); container:SetSize(640, 240)
    if text.SetMaxBytes then text:SetMaxBytes(addon.Backup.MAX_BYTES + 1) end
    local bindingLabel = factory.CreateLabel(frame, theme.Fonts.small, addon.L("BACKUP_BINDING"), theme.Colors.textMuted)
    bindingLabel:SetPoint("TOPLEFT", container, "BOTTOMLEFT", 0, -12)
    bindingLabel:SetWidth(640); bindingLabel:SetWordWrap(true); bindingLabel:SetJustifyH("LEFT")
    local binding = factory.CreateEditBox(frame)
    binding:SetPoint("TOPLEFT", bindingLabel, "BOTTOMLEFT", 0, -8); binding:SetSize(260, 24); binding:SetMaxLetters(200)
    local checkButton = factory.CreateButton(frame, addon.L("BACKUP_CHECK"), 150)
    checkButton:SetPoint("LEFT", binding, "RIGHT", 12, 0)
    local restore = factory.CreateButton(frame, addon.L("BACKUP_RESTORE"), 170)
    restore:SetPoint("LEFT", checkButton, "RIGHT", 12, 0); restore:Disable()
    local state = factory.CreateLabel(frame, theme.Fonts.small, "", theme.Colors.textMuted)
    state:SetPoint("TOPLEFT", binding, "BOTTOMLEFT", 0, -12)
    state:SetWidth(640); state:SetHeight(46); state:SetWordWrap(true); state:SetJustifyH("LEFT")
    local cancel = factory.CreateButton(frame, addon.L("BACKUP_CANCEL_PENDING"), 230)
    cancel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 18)
    local reload = factory.CreateButton(frame, addon.L("BACKUP_RELOAD"), 220)
    reload:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 18); reload:Disable()
    frame.text, frame.binding, frame.restore, frame.status, frame.reload, frame.scopeButton = text, binding, restore, state, reload, scopeButton
    scopeButton:SetScript("OnClick", function()
        for index, current in ipairs(scopes) do if current == scope then scope = scopes[index % #scopes + 1]; break end end
        scopeButton:SetText(addon.L(labels[scope])); clear(); status()
    end)
    export:SetScript("OnClick", function()
        clear()
        local output, warning = addon.Backup.Export(scope)
        if not output then status(warning); return end
        text:SetText(output); text:SetFocus(); text:HighlightText(); status(warning or "BACKUP_EXPORTED")
    end)
    recovery:SetScript("OnClick", function()
        clear()
        local output = addon.Backup.GetRecovery()
        if not output then status("BACKUP_NO_RECOVERY"); return end
        text:SetText(output); text:SetFocus(); text:HighlightText(); status("BACKUP_RECOVERY_GUIDANCE")
    end)
    checkButton:SetScript("OnClick", check); restore:SetScript("OnClick", confirm)
    text:HookScript("OnTextChanged", function() clear() end)
    binding:HookScript("OnTextChanged", function() clear() end)
    frame:HookScript("OnHide", clear)
    cancel:SetScript("OnClick", function()
        addon.Backup.CancelPending(); reload:Disable(); clear(); status("BACKUP_CANCELED")
    end)
    reload:SetScript("OnClick", function()
        local ok, err = addon.Backup.CanReload()
        if not ok then status(err); return end
        if type(ReloadUI) == "function" then ReloadUI() end
    end)
    return frame
end

function view.Open()
    window = window or create()
    scope = "core"; window.scopeButton:SetText(addon.L(labels[scope]))
    if addon.Backup.CanReload() then window.reload:Enable() else window.reload:Disable() end
    clear(); status(); window:Show(); addon.UIFactory.BringToFront(window)
end
