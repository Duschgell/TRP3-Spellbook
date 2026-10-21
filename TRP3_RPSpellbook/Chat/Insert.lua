local _, addon = ...

addon.ChatInsert = {}

local function isUIObject(value)
    local valueType = type(value)
    return valueType == "table" or valueType == "userdata"
end

local function resolveEditBox(activeWindow)
    if not isUIObject(activeWindow) then
        return nil
    end
    if type(activeWindow.Insert) == "function" then
        return activeWindow
    end
    if isUIObject(activeWindow.editBox) and type(activeWindow.editBox.Insert) == "function" then
        return activeWindow.editBox
    end
    local chatFrame = activeWindow.chatFrame
    if isUIObject(chatFrame)
        and isUIObject(chatFrame.editBox)
        and type(chatFrame.editBox.Insert) == "function"
    then
        return chatFrame.editBox
    end
    return nil
end

local function getActiveEditBox()
    local chatFrameUtil = _G.ChatFrameUtil
    if type(chatFrameUtil) == "table" and type(chatFrameUtil.GetActiveWindow) == "function" then
        local success, activeWindow = pcall(chatFrameUtil.GetActiveWindow)
        if success then
            local editBox = resolveEditBox(activeWindow)
            if editBox then
                return editBox, chatFrameUtil
            end
        end
    end

    if type(_G.ChatEdit_GetActiveWindow) == "function" then
        local success, editBox = pcall(_G.ChatEdit_GetActiveWindow)
        if success and isUIObject(editBox) and type(editBox.Insert) == "function" then
            return editBox, chatFrameUtil
        end
    end
    return nil, chatFrameUtil
end

local function getInsertionText(editBox, link)
    local currentText = ""
    if type(editBox.GetText) == "function" then
        local success, value = pcall(editBox.GetText, editBox)
        if success and type(value) == "string" then
            currentText = value
        end
    end

    if currentText == "" then
        return link .. " "
    end
     
     
     
    return " " .. link .. " "
end

function addon.ChatInsert.InsertSpell(ownerKey, spell, effectID)
    local snapshot, snapshotError = addon.ChatLinks.CreateSnapshot(ownerKey, spell)
    if not snapshot then
        return false, snapshotError
    end

    local prepared = addon.EffectVisibility and addon.EffectVisibility.PrepareLink(snapshot, effectID)
    if prepared == false then return false, addon.L("TIMED_SHARE_LIMIT") end
    if prepared then snapshot.effectLinkStem = prepared.stem end
    local link, linkError = addon.TRP3Bridge.CreateSpellChatLink(snapshot)
    if not link then
        return false, linkError
    end
    if prepared and not addon.EffectVisibility.BindLink(prepared, link) then return false, addon.L("CHAT_INSERT_FAILED") end

    local editBox, chatFrameUtil = getActiveEditBox()
    if editBox then
        if type(chatFrameUtil) == "table" and type(chatFrameUtil.FocusActiveWindow) == "function" then
            pcall(chatFrameUtil.FocusActiveWindow)
        end
        local insertion = getInsertionText(editBox, link)
        local success, insertError = pcall(editBox.Insert, editBox, insertion)
        if success then
            if addon.ChatFallbacks then
                addon.ChatFallbacks.TrackInsertedSpell(snapshot, link)
            end
            return true
        end
        return false, insertError
    end

    if type(chatFrameUtil) == "table" and type(chatFrameUtil.OpenChat) == "function" then
        local success, openError = pcall(chatFrameUtil.OpenChat, link .. " ")
        if success then
            if addon.ChatFallbacks then
                addon.ChatFallbacks.TrackInsertedSpell(snapshot, link)
            end
            return true
        end
        return false, openError
    end

    return false, addon.L("CHAT_INSERT_FAILED")
end

function addon.ChatInsert.HandleSpellClick(mouseButton, ownerKey, spell)
    if mouseButton ~= "LeftButton" or type(spell) ~= "table"
        or type(IsShiftKeyDown) ~= "function" or not IsShiftKeyDown()
    then
        return false
    end
    ownerKey = ownerKey or spell.ownerKey
        or (addon.Database and addon.Database.GetActiveProfileKey())
    local success, errorMessage = addon.ChatInsert.InsertSpell(ownerKey, spell)
    if not success then
        addon.Logger.Error(errorMessage or addon.L("CHAT_INSERT_FAILED"))
    end
     
    return true
end

function addon.ChatInsert.ReplaceHyperlink(link, displayName, reference)
    if type(link) ~= "string" or type(reference) ~= "table" then
        return false
    end

    local token = addon.ChatLinks.CreateTransportReference(reference, displayName)
    if not token then
        return false
    end

    local editBox = getActiveEditBox()
    if not editBox
        or type(editBox.GetText) ~= "function"
        or type(editBox.SetText) ~= "function"
    then
        return false
    end

    local textSuccess, currentText = pcall(editBox.GetText, editBox)
    if not textSuccess or type(currentText) ~= "string" then
        return false
    end

    local cursorPosition = type(editBox.GetCursorPosition) == "function"
        and editBox:GetCursorPosition()
        or #currentText
    local escapedLink = link:gsub("(%W)", "%%%1")
    local replacement = token .. " "
    local updatedText, colorCount = currentText:gsub(
        "|c%x%x%x%x%x%x%x%x|H" .. escapedLink .. "|h.-|h|r",
        function()
            return replacement
        end
    )
    local plainCount = 0
    if colorCount == 0 then
        updatedText, plainCount = currentText:gsub(
            "|H" .. escapedLink .. "|h.-|h",
            function()
                return replacement
            end
        )
    end
    if colorCount == 0 and plainCount == 0 then
        return false
    end

    local setSuccess = pcall(editBox.SetText, editBox, updatedText)
    if setSuccess and type(editBox.SetCursorPosition) == "function" then
        local difference = #updatedText - #currentText
        pcall(editBox.SetCursorPosition, editBox, math.min(#updatedText, math.max(0, cursorPosition + difference)))
    end
    return setSuccess
end
