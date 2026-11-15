local _, private = ...
local addon = private.Shared or private
local archive = addon.NPCArchive
local L = archive.L
local page, refresh, openProfile
local mode, selectedNPC, selectedTab = "register", nil, nil
local profileDraft, profileDirty, refreshing = nil, false, false
local profileBaseline, profileToken
local updateDirty, requestDelete
local portraits, portraitPool = {}, {}
local data, rows = {}, {}
local sourceBookID
local bookSnapshot, bookRevision
local ROW_HEIGHT = 28
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local relationColors = { friendly = { 0.2, 1, 0.2 }, neutral = { 1, 0.82, 0 }, hostile = { 1, 0.25, 0.2 } }
local relationLabels = { friendly = "FRIENDLY", neutral = "NEUTRAL", hostile = "HOSTILE" }
local transferDialog, transferSession
local place, label, button, status, switchMode

function archive.IsTransferEditorBusy() return profileDirty end

function archive.OpenTransferDialog(npcID, importing)
    if not archive.Transfer then return nil end
    if profileDirty then status(false, "TRANSFER_EDITOR"); return nil end
    local output, err
    if not importing then
        output, err = archive.Transfer.Export(npcID)
        if not output then return nil, err end
    end
    if not transferDialog then
        local frame = addon.UIFactory.CreateDialog(L("TRANSFER_TITLE"), 560, 390)
        frame.help = label(frame, L("TRANSFER_HELP"), true)
        frame.help:SetWordWrap(true)
        place(frame.help, frame, 18, 48, 524, 65)
        frame.input, frame.text = addon.UIFactory.CreateTextArea(frame)
        place(frame.text, frame, 18, 120, 524, 190)
        frame.input:SetMaxLetters(addon.PortableTable.MAX_BYTES + 9)
        frame.feedback = label(frame, "", true)
        place(frame.feedback, frame, 18, 354, 524, 24)
        local function request(mode)
            local session, input = transferSession, frame.input:GetText()
            if not session then return end
            local plan, reason = archive.Transfer.Prepare(input, mode)
            if not plan then frame.feedback:SetText(L(reason)); return end
            addon.UIFactory.ShowConfirmation(L("TRANSFER_TITLE"),
                string.format(L(mode == "merge" and "TRANSFER_CONFIRM_MERGE" or "TRANSFER_CONFIRM_REPLACE"),
                    plan.added, plan.updated), function()
                    if transferSession ~= session or not frame:IsShown() or frame.input:GetText() ~= input then return end
                    local ok, failure = archive.Transfer.Commit(plan)
                    frame.feedback:SetText(L(ok and "TRANSFER_DONE" or failure))
                    if ok and page then switchMode("register"); status(true, "TRANSFER_DONE") end
                end)
        end
        frame.merge = button(frame, L("TRANSFER_MERGE"), function() request("merge") end)
        frame.replace = button(frame, L("TRANSFER_REPLACE"), function() request("replace") end)
        place(frame.merge, frame, 18, 320, 250, 24)
        place(frame.replace, frame, 280, 320, 262, 24)
        frame:SetScript("OnHide", function() transferSession = nil; frame.input:ClearFocus() end)
        transferDialog = frame
    end
    transferSession = {}
    transferDialog.merge:SetShown(importing == true)
    transferDialog.replace:SetShown(importing == true)
    transferDialog.feedback:SetText("")
    transferDialog.input:SetText(output or "")
    transferDialog:Show()
    transferDialog.input:SetFocus()
    if output then transferDialog.input:HighlightText() end
    return transferDialog
end

local function setSpellIcon(icon, spell)
    if type(addon.UIFactory.SetSpellIcon) == "function" then
        return addon.UIFactory.SetSpellIcon(icon, spell, FALLBACK_ICON, true)
    end
    return addon.UIFactory.SetIconTexture(icon, spell and spell.icon, FALLBACK_ICON)
end

local function clearSpellIconFrame(icon)
    if type(addon.UIFactory.ClearSpellIconEffectFrame) == "function" then
        addon.UIFactory.ClearSpellIconEffectFrame(icon)
    end
end

place = function(region, parent, x, y, width, height)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    region:SetSize(math.max(1, width), math.max(1, height))
end

label = function(parent, value, small)
    local result = addon.UIFactory.CreateLabel(parent, small and addon.Theme.Fonts.small or addon.Theme.Fonts.body,
        value, addon.Theme.Colors.text)
    result:SetJustifyH("LEFT")
    result:SetWordWrap(false)
    return result
end

button = function(parent, caption, action)
    local result = addon.UIFactory.CreateButton(parent, caption, 120)
    result:SetScript("OnClick", action)
    return result
end

status = function(ok, message)
    page.status:SetText(message and L(message) or (ok and L("OK") or L("INVALID")))
    page.status:SetTextColor(ok and 0.3 or 1, ok and 1 or 0.3, 0.3)
end

local function profileValues()
    if not profileDraft then return {} end
    local values = { icon = profileDraft.icon, nameColor = profileDraft.nameColor, relationship = profileDraft.relationship }
    for key, field in pairs(page.profile.fields) do values[key] = field:GetText():match("^%s*(.-)%s*$") end
    if values.nameColor then values.nameColor = values.nameColor:gsub("^#", ""):upper() end
    return values
end

updateDirty = function()
    if refreshing or not profileBaseline then return end
    local values, changed = profileValues(), false
    for _, key in ipairs({ "name", "title", "area", "description", "icon", "nameColor", "relationship" }) do
        if values[key] ~= profileBaseline[key] then changed = true; break end
    end
    if changed ~= profileDirty then
        page.status:SetText("")
        page.profile.feedback:SetText(changed and L("UNSAVED") or "")
        page.profile.feedback:SetTextColor(1, 0.82, 0)
    end
    profileDirty = changed
    page.profile.save:SetEnabled(changed)
end

local function hidePortraits()
    for _, value in pairs(portraits) do value:Hide() end
end

local function recyclePortraits()
    for token, portrait in pairs(portraits) do
        if archive.GetIdentityToken(portrait.npcID) ~= token then
            portrait:Hide(); portrait:SetParent(page)
            portrait.ready = false
            portraits[token] = nil; portraitPool[#portraitPool + 1] = portrait
        end
    end
end

local function cachePortrait(npcID)
    local token = archive.GetIdentityToken(npcID)
    if not token then return end
    local portrait = portraits[token]
    if not portrait then
         
        portrait = table.remove(portraitPool) or CreateFrame("Frame", nil, page)
        portrait.texture = portrait.texture or portrait:CreateTexture(nil, "ARTWORK")
        portrait.texture:SetAllPoints()
        portrait.npcID, portrait.ready = npcID, false
        portrait:Hide()
        portraits[token] = portrait
    end
    if not portrait.ready then portrait.ready = archive.ApplyPortrait(portrait.texture, npcID) == true end
    return portrait
end

local function showPortrait(parent, fallback, npcID, x, y, size)
    local identity = npcID and archive.GetIdentity(npcID)
    if not identity or identity.source == "authored" then return end
    local portrait = cachePortrait(npcID)
    if not portrait then return end
    portrait:SetParent(parent)
    place(portrait, parent, x, y, size, size)
    local creatureID = identity and identity.creatureID or npcID
    addon.UIFactory.SetNPCPortrait(portrait, portrait.texture, not portrait.ready and creatureID or nil, nil, size)
    portrait:Show()
    fallback:Hide()
end

local function resetScroll()
    page.scroll:SetVerticalScroll(0)
    if page.scroll.ScrollBar then page.scroll.ScrollBar:SetValue(0) end
end

switchMode = function(nextMode, npcID)
    local function apply()
        if mode == "profile" then
            for _, field in pairs(page.profile.fields) do field:ClearFocus() end
        end
        mode, selectedNPC = nextMode, npcID
        profileDraft, profileBaseline, profileDirty = nil, nil, false
        page.status:SetText("")
        page.search:SetText("")
        resetScroll()
        refresh()
    end
    if profileDirty and mode == "profile" then
        local draft = profileDraft
        addon.UIFactory.ShowConfirmation(L("PROFILE"), L("DISCARD"), function() if profileDraft == draft then apply() end end)
    else apply() end
end

local function showProfileTooltip(owner, npc)
    if not GameTooltip then return end
    local r, g, b = addon.UIFactory.GetColorRGB(npc.nameColor)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(npc.name, r, g, b)
    if npc.title and npc.title ~= "" then GameTooltip:AddLine(npc.title, 0.85, 0.8, 0.6, true) end
    if npc.relationship then
        local c = relationColors[npc.relationship]
        GameTooltip:AddLine(L(relationLabels[npc.relationship]), c[1], c[2], c[3])
    end
    if npc.description and npc.description ~= "" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(npc.description, 1, 1, 1, true)
    end
    GameTooltip:Show()
end

local function assignSpell(spellID)
    local npc = selectedNPC and archive.Get(selectedNPC)
    if not npc then return end
    local assigned = false
    for _, entry in ipairs(npc.spellIDs or {}) do if entry == spellID then assigned = true end end
    local ok, err = archive.AssignSpell(npc.id, spellID, not assigned)
    status(ok, err)
    refresh()
end

requestDelete = function(kind, id, token)
    local storage = archive.SpellbookStorage
    local currentToken = kind == "npc" and archive.GetIdentityToken or storage.GetSpellToken
    if not token or currentToken(id) ~= token then status(false, "INVALID"); return end
    local entry = kind == "npc" and archive.GetIdentity(id) or storage.GetSpell(id)
    local caption = kind == "npc" and L("DELETE_NPC") or L("DELETE")
    addon.UIFactory.ShowConfirmation(caption, entry.name .. "\n\n" .. L("CONFIRM_DELETE"), function()
        if currentToken(id) ~= token then status(false, "INVALID"); return end
        local ok, err
        if kind == "npc" then ok, err = archive.DeleteNPC(id, token)
        else ok, err = storage.DeleteSpell(id, token) end
        if ok and mode == "profile" and selectedNPC == id and profileToken == token then
            profileDirty = false; switchMode("register")
        elseif ok then refresh() end
        status(ok, err or (ok and "DELETED"))
    end)
end

local function rowMenu(row, kind, entry)
    local storage = archive.SpellbookStorage
    local getToken = kind == "npc" and archive.GetIdentityToken or storage.GetSpellToken
    local id, token = entry.id, row.entryToken
    if getToken(id) ~= token then status(false, "INVALID"); return end
    if not token then status(false, "INVALID"); return end
    local function generate(_, root)
         
        root:SetMinimumWidth(1)
        root:CreateTitle(entry.name)
        root:CreateButton(L("QUICK_EDIT"), function()
            if getToken(id) ~= token then status(false, "INVALID"); return end
            if kind == "npc" then openProfile(id)
            else addon.SpellEditorWindow.OpenEdit(id, refresh, storage) end
        end)
        root:CreateButton(kind == "npc" and L("DELETE_NPC") or L("DELETE"), function() requestDelete(kind, id, token) end)
        if kind == "npc" and archive.Transfer then
            root:CreateButton(L("TRANSFER_EXPORT_ONE"), function()
                if archive.GetIdentityToken(id) ~= token then status(false, "INVALID"); return end
                local ok, err = archive.OpenTransferDialog(id, false)
                if not ok then status(false, err) end
            end)
        end
    end
    local ok, err
    if type(addon.TRP3Bridge.CreateContextMenu) == "function" then
        ok, err = addon.TRP3Bridge.CreateContextMenu(row, generate)
    elseif MenuUtil and type(MenuUtil.CreateContextMenu) == "function" then
        ok = pcall(MenuUtil.CreateContextMenu, row, generate)
    end
    if not ok then status(false, err or "UNAVAILABLE") end
end

local function createRow()
    local row = CreateFrame("Button", nil, page.content)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local background = row:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetTexture("Interface\\ACHIEVEMENTFRAME\\UI-Achievement-Title")
    background:SetTexCoord(0, 1, 0.40625, 0.60125)
    row:SetHighlightTexture("Interface\\FriendsFrame\\UI-FriendsFrame-HighlightBar")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.name, row.relation, row.area = label(row, ""), label(row, ""), label(row, "", true)
    row.assigned = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.assigned:SetScript("OnClick", function() if row.entry then assignSpell(row.entry.id) end end)
    row:SetScript("OnClick", function(_, mouseButton)
        local entry = row.entry
        if not entry then return end
        local token = mode == "register" and archive.GetIdentityToken(entry.id)
            or (mode == "book" and archive.SpellbookStorage.GetSpellToken(entry.id) or nil)
        if mode ~= "copy" and (not token or token ~= row.entryToken) then status(false, "INVALID"); return end
        if mode ~= "register" then
            local source = mode == "copy" and addon.Database.GetActiveSpellbook() or bookSnapshot
            if mode == "copy" and (not source or source.id ~= sourceBookID) then status(false, "INVALID"); return end
            if addon.ChatInsert.HandleSpellClick(mouseButton,
                mode == "book" and "npc_shared" or (source and source.profileKey), entry) then return end
        end
        if mouseButton == "RightButton" then
            if mode ~= "copy" then rowMenu(row, mode == "register" and "npc" or "spell", entry) end
            return
        end
        if mode == "register" then
            openProfile(entry.id)
        elseif mode == "copy" then
            local spell, err = archive.CopyFromSpellbook(entry.id, selectedTab, nil, sourceBookID)
            status(spell, err or (spell and "BOOK_COPIED"))
        else
            addon.SpellEditorWindow.OpenEdit(entry.id, function() refresh() end, archive.SpellbookStorage)
        end
    end)
    row:SetScript("OnEnter", function()
        if not row.entry then return end
        if mode == "register" then showProfileTooltip(row, row.entry)
        elseif addon.SpellTooltip then addon.SpellTooltip.Show(row, row.entry, mode == "book") end
    end)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return row
end

local function renderRows()
    if not page or mode == "profile" then return end
    hidePortraits()
    local width, height = math.max(1, page.scroll:GetWidth()), math.max(1, page.scroll:GetHeight())
    local offset = page.scroll:GetVerticalScroll()
    local first = math.floor(offset / ROW_HEIGHT) + 1
    local capacity = math.min(80, math.ceil(height / ROW_HEIGHT) + 1)
    local assigned = {}
    local npc = selectedNPC and archive.Get(selectedNPC)
    for _, spellID in ipairs(npc and npc.spellIDs or {}) do assigned[spellID] = true end
    for slot = 1, capacity do
        local entry = data[first + slot - 1]
        if entry then
            rows[slot] = rows[slot] or createRow()
            local row, y = rows[slot], (first + slot - 2) * ROW_HEIGHT
            row.entry = entry
            row.entryToken = mode == "register" and archive.GetIdentityToken(entry.id)
                or (mode == "book" and archive.SpellbookStorage.GetSpellToken(entry.id) or nil)
            place(row, page.content, 0, y, width, ROW_HEIGHT - 1)
            local assign = mode == "book" and selectedNPC ~= nil
            row.assigned:SetShown(assign)
            row.assigned:SetChecked(assigned[entry.id] == true)
            place(row.assigned, row, 0, 2, 24, 24)
            local left = assign and 26 or 6
            place(row.icon, row, left, 4, 20, 20)
            row.icon:Show()
            if mode == "register" then
                clearSpellIconFrame(row.icon)
                addon.UIFactory.SetIconTexture(row.icon, entry.icon, FALLBACK_ICON)
                if not entry.icon then showPortrait(row, row.icon, entry.id, left, 4, 20) end
            else
                setSpellIcon(row.icon, entry)
            end
            row.name:SetText(entry.name)
            addon.UIFactory.SetFontColor(row.name, entry.nameColor, addon.Theme.Colors.text)
            local nameEnd = mode == "register" and math.floor(width * 0.48) or math.floor(width * 0.64)
            place(row.name, row, left + 27, 3, nameEnd - left - 33, 22)
            if mode == "register" then
                local c = relationColors[entry.relationship] or addon.Theme.Colors.textMuted
                row.relation:SetText(entry.relationship and L(relationLabels[entry.relationship]) or "")
                row.relation:SetTextColor(c[1], c[2], c[3])
                place(row.relation, row, nameEnd, 3, width * 0.23 - 6, 22)
                place(row.area, row, math.floor(width * 0.71), 3, width * 0.29 - 6, 22)
                row.area:SetText(entry.area or "")
            else
                row.relation:SetText("")
                place(row.area, row, nameEnd, 3, width - nameEnd - 6, 22)
                row.area:SetText(entry.npcDraft and L("DRAFT_SHORT") or (entry.castTime or ""))
            end
            row:SetHitRectInsets(0, 0, math.min(27, math.max(0, offset - y)),
                math.min(27, math.max(0, y + 27 - offset - height)))
            row:Show()
        elseif rows[slot] then rows[slot]:Hide() end
    end
    for index = capacity + 1, #rows do rows[index]:Hide() end
end

local function flow(controls, x, y, width)
    local start = x
    for _, control in ipairs(controls) do
        if control:IsShown() then
            local font = type(control.GetFontString) == "function" and control:GetFontString()
            if font then font:SetWordWrap(false); font:SetWidth(0) end
            local desired = control.npcWidth or math.max(64, (font and font:GetStringWidth() or 100) + 22)
            desired = math.min(width, desired)
            if x > start and x + desired > start + width then x, y = start, y + 29 end
            place(control, page, x, y, desired, 24)
            if font then font:SetWidth(math.max(1, desired - 16)) end
            x = x + desired + 6
        end
    end
    return y + 32
end

local function applyProfile()
    if not profileDraft then return nil end
    local saved, err
    if selectedNPC == nil then
        saved, err = archive.CreateProfile(profileValues())
        if saved then selectedNPC, profileToken = saved.id, archive.GetIdentityToken(saved.id) end
    elseif archive.GetIdentityToken(selectedNPC) ~= profileToken then err = "INVALID"
    elseif profileDirty then saved, err = archive.SaveProfile(selectedNPC, profileValues(), profileToken)
    else saved = archive.Get(selectedNPC) end
    status(saved, err)
    if saved then
        refreshing = true
        for key, field in pairs(page.profile.fields) do field:SetText(saved[key] or ""); field:ClearFocus() end
        profileDraft = saved
        profileBaseline, profileDirty, refreshing = profileValues(), false, false
        page.profile.save:SetEnabled(false)
        page.profile.feedback:SetText(L("PROFILE_SAVED"))
        page.profile.feedback:SetTextColor(0.3, 1, 0.3)
        refresh()
    else
        page.profile.feedback:SetText(L("SAVE_FAILED"))
        page.profile.feedback:SetTextColor(1, 0.3, 0.3)
    end
    return saved
end

local function createProfileEditor()
    local frame = CreateFrame("Frame", nil, page.content)
    frame.fields, frame.labels = {}, {}
    frame.icon = addon.UIFactory.CreateIconButton(frame)
    frame.icon:SetScript("OnClick", function(_, mouseButton)
        if not profileDraft then return end
        local draft = profileDraft
        local function setIcon(value)
            if profileDraft ~= draft then return end
            draft.icon = value
            hidePortraits()
            frame.icon.iconTexture:Show()
            addon.UIFactory.SetIconTexture(frame.icon.iconTexture, value, FALLBACK_ICON)
            if not value then showPortrait(frame.icon, frame.icon.iconTexture, selectedNPC, 0, 0, 56) end
            updateDirty()
        end
        if mouseButton == "RightButton" then setIcon(nil); return end
        local ok, err = addon.TRP3Bridge.OpenIconBrowser(draft.icon, setIcon, nil, page)
        if not ok then status(false, err) end
    end)
    frame.color = addon.UIFactory.CreateColorButton(frame)
    frame.color:SetScript("OnClick", function(_, mouseButton)
        if not profileDraft then return end
        local draft = profileDraft
        local function setColor(value)
            if profileDraft ~= draft then return end
            draft.nameColor = value
            addon.UIFactory.SetColorButton(frame.color, value)
            addon.UIFactory.SetFontColor(frame.fields.name, value, addon.Theme.Colors.text)
            updateDirty()
        end
        if mouseButton == "RightButton" then setColor(nil); return end
        local ok, err = addon.TRP3Bridge.OpenColorPicker(draft.nameColor, setColor, nil, page)
        if not ok then status(false, err) end
    end)
    for _, spec in ipairs({ { "name", "PROFILE_NAME" }, { "title", "PROFILE_TITLE" }, { "area", "AREA" } }) do
        local key = spec[1]
        frame.labels[key] = label(frame, L(spec[2]), true)
        frame.fields[key] = addon.UIFactory.CreateEditBox(frame, false)
        frame.fields[key]:SetMaxLetters(120)
        frame.fields[key]:HookScript("OnTextChanged", updateDirty)
    end
    frame.labels.relationship = label(frame, L("RELATIONSHIP"), true)
    frame.relationship = CreateFrame("Frame", nil, frame, "TRP3_DropdownButtonTemplate")
    frame.relationship:SetupMenu(function(_, root)
        local draft = profileDraft
        for _, value in ipairs({ "", "friendly", "neutral", "hostile" }) do
            local key = value
            root:CreateRadio(key == "" and L("UNSPECIFIED") or L(relationLabels[key]),
                function() return profileDraft and (profileDraft.relationship or "") == key end,
                function()
                    if not draft or profileDraft ~= draft then return end
                    profileDraft.relationship = key ~= "" and key or nil
                    frame.relationship:SetText(key == "" and L("UNSPECIFIED") or L(relationLabels[key]))
                    updateDirty()
                end)
        end
    end)
    frame.labels.description = label(frame, L("PROFILE_DESCRIPTION"), true)
     
    frame.descriptionBox = CreateFrame("Frame", "TRP3_RPSpellbookNPCProfileDescription", frame, "TRP3_TextArea")
    frame.fields.description = frame.descriptionBox:GetEditBox()
    local focus = frame.descriptionBox:GetFocusFrame()
    frame.fields.description:HookScript("OnEditFocusGained", function(self) focus:Hide(); self:EnableMouse(true) end)
    frame.fields.description:HookScript("OnEditFocusLost", function(self) focus:Show(); self:EnableMouse(false) end)
    frame.fields.description:HookScript("OnHide", function(self) self:ClearFocus() end)
    frame.fields.description:SetMaxLetters(2000)
    frame.fields.description:HookScript("OnTextChanged", updateDirty)
    frame.assignment = button(frame, L("ASSIGN_ABILITIES"), function()
        if applyProfile() then switchMode("book", selectedNPC) end
    end)
    frame.summary = label(frame, L("NO_ABILITIES"), true)
    frame.abilities = {}
    frame.save = button(page, addon.L("SAVE"), applyProfile)
    frame.feedback = label(page, "")
    frame.delete = button(frame, L("DELETE_NPC"), function() requestDelete("npc", selectedNPC, profileToken) end)
    return frame
end

local function layoutProfile(width)
    local frame = page.profile
    frame.delete:SetShown(selectedNPC ~= nil)
    hidePortraits()
    frame.icon.iconTexture:Show()
    if profileDraft and not profileDraft.icon then showPortrait(frame.icon, frame.icon.iconTexture, selectedNPC, 0, 0, 56) end
    frame:SetPoint("TOPLEFT", page.content, "TOPLEFT", 0, 0)
    place(frame.icon, frame, 8, 8, 56, 56)
    place(frame.labels.name, frame, 78, 4, width - 132, 18)
    place(frame.fields.name, frame, 78, 25, width - 132, 26)
    place(frame.color, frame, width - 40, 25, 26, 26)
    place(frame.labels.title, frame, 78, 58, width - 92, 18)
    place(frame.fields.title, frame, 78, 78, width - 92, 26)
    place(frame.labels.relationship, frame, 8, 116, 170, 18)
    place(frame.relationship, frame, 8, 137, 170, 24)
    place(frame.labels.area, frame, 190, 116, width - 204, 18)
    place(frame.fields.area, frame, 190, 137, width - 204, 26)
    place(frame.labels.description, frame, 8, 178, width - 22, 18)
    place(frame.descriptionBox, frame, 8, 199, width - 22, 166)
    place(frame.assignment, frame, 8, 381, 168, 24)
    local npc, y = selectedNPC and archive.Get(selectedNPC), 415
    local count = 0
    for _, spellID in ipairs(npc and npc.spellIDs or {}) do
        local spell = bookSnapshot and bookSnapshot.spells[spellID]
        if spell then
            count = count + 1
            local row = frame.abilities[count]
            if not row then
                row = CreateFrame("Button", nil, frame)
                row.icon, row.name = row:CreateTexture(nil, "ARTWORK"), label(row, "")
                row:SetScript("OnClick", function(_, mouseButton)
                    if row.spellID and archive.SpellbookStorage.GetSpellToken(row.spellID) == row.token then
                        if addon.ChatInsert.HandleSpellClick(mouseButton, "npc_shared",
                            archive.SpellbookStorage.GetSpell(row.spellID)) then return end
                        addon.SpellEditorWindow.OpenEdit(row.spellID, refresh, archive.SpellbookStorage)
                    end
                end)
                row:SetScript("OnEnter", function()
                    local current = row.spellID and archive.SpellbookStorage.GetSpell(row.spellID)
                    if current and addon.SpellTooltip then addon.SpellTooltip.Show(row, current, true) end
                end)
                row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
                frame.abilities[count] = row
            end
            row.spellID, row.token = spellID, archive.SpellbookStorage.GetSpellToken(spellID)
            place(row, frame, 8, y, width - 22, 24)
            place(row.icon, row, 0, 2, 20, 20)
            place(row.name, row, 28, 0, width - 50, 24)
            setSpellIcon(row.icon, spell)
            addon.UIFactory.SetFontColor(row.name, spell.nameColor, addon.Theme.Colors.text)
            row.name:SetText(spell.name); row:Show()
            y = y + 26
        end
    end
    for index = count + 1, #frame.abilities do
        clearSpellIconFrame(frame.abilities[index].icon)
        frame.abilities[index]:Hide()
    end
    frame.summary:SetShown(count == 0)
    place(frame.summary, frame, 8, y, width - 22, 24)
    if count == 0 then y = y + 26 end
    place(frame.delete, frame, 8, y + 10, 120, 24)
    frame:SetSize(width, y + 46)
    page.content:SetHeight(y + 46)
end

openProfile = function(npcID)
    if mode == "profile" and profileDirty then
        local draft = profileDraft
        addon.UIFactory.ShowConfirmation(L("PROFILE"), L("DISCARD"), function()
            if profileDraft == draft then profileDirty = false; openProfile(npcID) end
        end)
        return
    end
    local npc
    if npcID ~= nil then npc = archive.Get(npcID)
    else npc = { name = "", source = "authored", spellIDs = {} } end
    if not npc then return end
    mode, selectedNPC, profileDraft = "profile", npcID, npc
    profileToken = archive.GetIdentityToken(npcID)
    refreshing = true
    for key, field in pairs(page.profile.fields) do field:SetText(npc[key] or "") end
    addon.UIFactory.SetColorButton(page.profile.color, npc.nameColor)
    addon.UIFactory.SetFontColor(page.profile.fields.name, npc.nameColor, addon.Theme.Colors.text)
    addon.UIFactory.SetIconTexture(page.profile.icon.iconTexture, npc.icon, FALLBACK_ICON)
    page.profile.relationship:SetText(npc.relationship and L(relationLabels[npc.relationship]) or L("UNSPECIFIED"))
    profileBaseline = profileValues()
    profileDirty, refreshing = false, false
    page.profile.feedback:SetText(""); page.profile.save:SetEnabled(false); page.status:SetText("")
    resetScroll()
    refresh()
end

local function matches(entry, query)
    if query == "" then return true end
    local haystack = table.concat({ entry.name or "", entry.title or "", entry.area or "",
        entry.relationship and L(relationLabels[entry.relationship]) or "" }, " "):lower()
    return haystack:find(query, 1, true) ~= nil
end

local function layoutTabs(book, width, top)
    local tabBar = page.tab
    place(tabBar, page, 12, top, width - 24, 28)
    local available, selectedIndex = width - 88, 1
    for index, id in ipairs(book.tabOrder) do if id == selectedTab then selectedIndex = index end end
    local count = math.max(1, math.min(12, math.floor(available / 120), #book.tabOrder))
    local first = math.min(math.max(1, selectedIndex - count + 1), math.max(1, #book.tabOrder - count + 1))
    local size = math.min(120, available / count)
    place(page.tabPrevious, tabBar, 0, 1, 26, 26)
    place(page.tabNext, tabBar, width - 50, 1, 26, 26)
    page.tabPrevious:SetEnabled(#book.tabOrder > 1); page.tabNext:SetEnabled(#book.tabOrder > 1)
    for slot = 1, count do
        local id = book.tabOrder[first + slot - 1]
        local tab, control = book.tabs[id], tabBar.buttons[slot]
        if not control then
            control = CreateFrame("Button", nil, tabBar, "BackdropTemplate")
            control:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            local c = addon.Theme.Colors.parchmentDark
            control:SetBackdropColor(c[1], c[2], c[3], 1)
            control.icon, control.label = control:CreateTexture(nil, "ARTWORK"), label(control, "")
            control.label:SetJustifyH("CENTER")
            control:SetScript("OnClick", function() selectedTab = control.tabID; resetScroll(); refresh() end)
            control:SetScript("OnEnter", function()
                if GameTooltip then GameTooltip:SetOwner(control, "ANCHOR_TOP"); GameTooltip:SetText(control.label:GetText()); GameTooltip:Show() end
            end)
            control:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
            tabBar.buttons[slot] = control
        end
        control.tabID = id
        place(control, tabBar, 32 + (slot - 1) * size, 0, size - 4, 28)
        place(control.icon, control, 4, 4, 20, 20)
        place(control.label, control, 28, 0, size - 36, 28)
        control.label:SetText(tab.name)
        addon.UIFactory.SetIconTexture(control.icon, tab.icon, addon.Constants.DEFAULT_TAB_ICON)
        local c = addon.Theme.Colors[id == selectedTab and "gold" or "border"]
        control:SetBackdropBorderColor(c[1], c[2], c[3], 1)
        control:Show()
    end
    for slot = count + 1, #tabBar.buttons do tabBar.buttons[slot]:Hide() end
end

refresh = function()
    if not page or refreshing then return end
    refreshing = true
    recyclePortraits()
    local storage, width, height = archive.SpellbookStorage, math.max(300, page:GetWidth()), math.max(220, page:GetHeight())
    local revision = storage.GetRevision()
    if not bookSnapshot or bookRevision ~= revision then
        bookSnapshot, bookRevision = storage.GetActiveSpellbook(), revision
    end
    local book = bookSnapshot
    if not book then page.status:SetText(L("NOT_READY")); refreshing = false; return end
    if not book.tabs[selectedTab] then selectedTab = book.tabOrder[1] end
    place(page.title, page, 12, 10, width - 24, 24)
    place(page.registerButton, page, 12, 41, 122, 24)
    place(page.bookButton, page, 142, 41, 160, 24)
    page.title:SetText(mode == "profile" and L("PROFILE") or mode == "copy" and L("COPY_OWN")
        or mode == "book" and (selectedNPC and L("ASSIGN_ABILITIES") or L("BOOK")) or L("TITLE"))
    if mode == "book" and selectedNPC then
        local identity = archive.GetIdentity(selectedNPC)
        if identity then page.title:SetText(L("ASSIGN_ABILITIES") .. ": " .. identity.name) end
    end
    page.search:SetShown(mode ~= "profile")
    page.searchLabel:SetShown(mode ~= "profile")
    page.profile:SetShown(mode == "profile")
    page.profile.save:SetShown(mode == "profile")
    page.profile.feedback:SetShown(mode == "profile")
    page.capture:SetShown(mode == "register")
    page.create:SetShown(mode == "register")
    if page.transferExport then
        page.transferExport:SetShown(mode == "register")
        page.transferImport:SetShown(mode == "register")
    end
    page.tab:SetShown(mode == "book")
    page.newSpell:SetShown(mode == "book")
    page.newTab:SetShown(mode == "book")
    page.editTab:SetShown(mode == "book")
    page.copy:SetShown(mode == "book")
    page.returnButton:SetShown(mode == "profile" or mode == "copy" or (mode == "book" and selectedNPC ~= nil))
    page.tabPrevious:SetShown(mode == "book")
    page.tabNext:SetShown(mode == "book")
    local top = 77
    if mode ~= "profile" then
        place(page.searchLabel, page, 12, top + 4, 56, 22)
        place(page.search, page, 70, top, math.min(280, width - 86), 26)
        local actions = { page.create, page.capture, page.newSpell, page.newTab, page.editTab, page.copy, page.returnButton }
        if page.transferExport then
            table.insert(actions, 2, page.transferExport)
            table.insert(actions, 3, page.transferImport)
        end
        top = flow(actions, 12, top + 34, width - 24)
        if mode == "book" then layoutTabs(book, width, top); top = top + 34 end
    else
        place(page.returnButton, page, 12, top, 110, 24)
        place(page.profile.save, page, 132, top, 110, 24)
        top = top + 28
        place(page.profile.feedback, page, 12, top, width - 28, 24)
        top = top + 32
    end
    page.columns:SetShown(mode ~= "profile")
    local contentWidth = math.max(1, width - 44)
    if mode ~= "profile" then
        place(page.columns, page, 12, top, contentWidth, 25)
        place(page.columns.name, page.columns, 6, 0, contentWidth * 0.48 - 12, 23)
        page.columns.name:SetText(mode == "register" and L("CHARACTER") or L("ABILITY"))
        place(page.columns.relationship, page.columns, contentWidth * 0.48, 0, contentWidth * 0.23 - 6, 23)
        page.columns.relationship:SetText(mode == "register" and L("RELATIONSHIP") or "")
        place(page.columns.area, page.columns, contentWidth * 0.71, 0, contentWidth * 0.29 - 6, 23)
        page.columns.area:SetText(mode == "register" and L("AREA") or "")
        top = top + 27
    end
    place(page.scroll, page, 12, top, contentWidth, height - top - 34)
    page.content:SetWidth(contentWidth)
    place(page.status, page, 12, height - 28, width - 24, 24)
    if mode == "profile" then
        for _, row in ipairs(rows) do row:Hide() end
        layoutProfile(contentWidth)
    else
        data = {}
        local query = page.search:GetText():match("^%s*(.-)%s*$"):lower()
        if mode == "register" then
            for _, npc in ipairs(archive.List()) do if matches(npc, query) then data[#data + 1] = npc end end
            table.sort(data, function(a, b)
                local left, right = a.name:lower(), b.name:lower()
                if left == right then return a.id < b.id end
                return left < right
            end)
        else
            local source = mode == "copy" and addon.Database.GetActiveSpellbook() or book
            sourceBookID = source and source.id
            local tabs = mode == "copy" and (source and source.tabOrder or {}) or { selectedTab }
            for _, tabID in ipairs(tabs) do
                local tab = source and source.tabs[tabID]
                for _, spellID in ipairs(tab and tab.spellIds or {}) do
                    local spell = source.spells[spellID]
                    if spell and matches(spell, query) then data[#data + 1] = spell end
                end
            end
        end
        page.content:SetHeight(math.max(1, #data * ROW_HEIGHT))
    end
    local maximum = math.max(0, page.content:GetHeight() - page.scroll:GetHeight())
    if page.scroll:GetVerticalScroll() > maximum then page.scroll:SetVerticalScroll(maximum) end
    page.scroll:UpdateScrollChildRect()
    page.empty:SetShown(mode ~= "profile" and #data == 0)
    place(page.empty, page, 20, top + 12, contentWidth - 20, 40)
    local hasQuery = page.search:GetText():match("%S") ~= nil
    page.empty:SetText(hasQuery and L("NO_SEARCH_RESULTS") or (mode == "register" and L("EMPTY") or L("BOOK_EMPTY")))
    renderRows()
    refreshing = false
end

function archive.CreatePage(parent)
    if page then return page end
    page = CreateFrame("Frame", nil, parent)
    if parent then page:SetAllPoints(parent) end
    page:Hide()
    local backdrop = CreateFrame("Frame", nil, page)
    backdrop:SetAllPoints(page)
    backdrop:EnableMouse(false)
    local background = backdrop:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.11, 0.08, 0.045, 0.18)
    page.title, page.status = label(page, L("TITLE")), label(page, "", true)
    page.status:SetWordWrap(false)
    page.registerButton = button(page, L("REGISTER"), function() switchMode("register") end)
    page.bookButton = button(page, L("BOOK"), function() switchMode("book") end)
    page.searchLabel, page.search = label(page, L("SEARCH"), true), addon.UIFactory.CreateEditBox(page, false)
    page.search:SetMaxLetters(80)
    page.search:SetText("")
    page.capture = button(page, L("CAPTURE"), function()
        local npcID, err = archive.CaptureTarget()
        if npcID then
            openProfile(npcID)
            if addon.Onboarding and addon.Onboarding.RecordAction then addon.Onboarding.RecordAction("npcCaptured", npcID) end
        else status(false, err) end
    end)
    page.create = button(page, L("CREATE_NPC"), function() openProfile(nil) end)
    if archive.Transfer then
        page.transferExport = button(page, L("TRANSFER_EXPORT_ALL"), function()
            local ok, err = archive.OpenTransferDialog(nil, false)
            if not ok then status(false, err) end
        end)
        page.transferImport = button(page, L("TRANSFER_IMPORT"), function() archive.OpenTransferDialog(nil, true) end)
    end
    page.tab = CreateFrame("Frame", nil, page)
    page.tab.buttons = {}
    local function cycle(direction)
        local book = archive.SpellbookStorage.GetActiveSpellbook()
        if not book then return end
        for index, tabID in ipairs(book.tabOrder) do
            if tabID == selectedTab then selectedTab = book.tabOrder[(index - 1 + direction) % #book.tabOrder + 1]; break end
        end
        resetScroll(); refresh()
    end
    page.tabPrevious, page.tabNext = button(page, "<", function() cycle(-1) end), button(page, ">", function() cycle(1) end)
    page.tabPrevious.npcWidth, page.tabNext.npcWidth = 26, 26
    local function editedTab(tabID) selectedTab = tabID or selectedTab; refresh() end
    page.newSpell = button(page, addon.L("NEW_ABILITY"), function()
        addon.SpellEditorWindow.OpenNew(selectedTab, editedTab, archive.SpellbookStorage)
    end)
    page.newTab = button(page, addon.L("NEW_TAB"), function() addon.TabEditor.OpenNew(editedTab, archive.SpellbookStorage) end)
    page.editTab = button(page, L("EDIT_TAB"), function() addon.TabEditor.OpenEdit(selectedTab, editedTab, archive.SpellbookStorage) end)
    page.copy = button(page, L("COPY_OWN"), function() switchMode("copy", selectedNPC) end)
    page.returnButton = button(page, L("BACK"), function()
        if mode == "profile" then switchMode("register")
        elseif mode == "book" and selectedNPC then openProfile(selectedNPC) else switchMode("book", selectedNPC) end
    end)
    page.columns = CreateFrame("Frame", nil, page)
    local header = page.columns:CreateTexture(nil, "BACKGROUND")
    header:SetAllPoints()
    header:SetColorTexture(0.22, 0.14, 0.05, 0.6)
    page.columns.name, page.columns.relationship, page.columns.area = label(page.columns, ""), label(page.columns, ""), label(page.columns, "")
    page.scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    page.scroll:SetClipsChildren(true)
    page.content = CreateFrame("Frame", nil, page.scroll)
    page.content:SetSize(1, 1)
    page.scroll:SetScrollChild(page.content)
    page.scroll:HookScript("OnVerticalScroll", renderRows)
    page.scroll:EnableMouseWheel(true)
    page.scroll:SetScript("OnMouseWheel", function(self, delta)
        local value = math.max(0, math.min(self:GetVerticalScroll() - delta * ROW_HEIGHT * 3,
            math.max(0, page.content:GetHeight() - self:GetHeight())))
        self:SetVerticalScroll(value)
        if self.ScrollBar then self.ScrollBar:SetValue(value) end
    end)
    page.empty = label(page, "", true)
    page.empty:SetWordWrap(true)
    page.profile = createProfileEditor()
    page.search:HookScript("OnTextChanged", function() if not refreshing then resetScroll(); refresh() end end)
    page:SetScript("OnShow", refresh)
    page:SetScript("OnHide", function()
        if GameTooltip then GameTooltip:Hide() end
        for _, field in pairs(page.profile.fields) do field:ClearFocus() end
    end)
    page:SetScript("OnSizeChanged", refresh)
    if addon.SeasonalVisuals then addon.SeasonalVisuals.Attach(page, "npc", { backgrounds = { backdrop } }) end
    return page
end

function archive.RefreshPage() refresh() end
function archive.GetTutorialContext()
    return page, mode, selectedNPC, rows
end
function archive.OpenTutorialProfile(npcID)
    if not archive.Get(npcID) then return false end
    if not archive.Open() then return false end
    openProfile(npcID)
    return true
end
function archive.OnTargetCaptured(npcID)
     
    if not page then return end
    local identity = archive.GetIdentity(npcID)
    if not identity or identity.icon then return end
    recyclePortraits()
    cachePortrait(npcID)
end
function archive.Open()
    if not archive.ready then return nil, L("NOT_READY") end
    if not addon.TRP3Integration or type(addon.TRP3Integration.OpenNPCArchive) ~= "function" then return nil, L("NOT_READY") end
    return addon.TRP3Integration.OpenNPCArchive()
end

archive.OnChanged = function()
    if not page or not page:IsShown() then return end
     
    page:SetScript("OnUpdate", function(self)
        self:SetScript("OnUpdate", nil)
        refresh()
    end)
end
