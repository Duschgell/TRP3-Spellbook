local _, addon = ...
addon.CurrentlyEffects = {}
local adapter = addon.CurrentlyEffects
local initialized, busy = false, false
local editorSnapshot
local MAX_INSTANCES = 256
local nativePointers = setmetatable({}, { __mode = "k" })
local editorBox, editorPendingUntil = nil, 0
local tooltipColors = setmetatable({}, { __mode = "k" })

local function validKey(value, limit)
    return type(value) == "string" and value ~= "" and #value <= (limit or 1000)
        and not value:find("[\r\n|]")
end

local function lastOccurrence(text, value)
    local position, found = 1
    while position <= #text do
        local first = text:find(value, position, true)
        if not first then break end
        local after = first + #value
        local beginsLine = value:sub(1, 1) == "\n" or first == 1 or text:sub(first - 1, first - 1) == "\n"
        local endsLine = value:sub(-1) == "\n" or after > #text or text:sub(after, after) == "\n" or text:sub(after, after + 1) == "\r\n"
        if beginsLine and endsLine then found = first end
        position = after
    end
    return found
end

local function lineCounts(text)
    local counts = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
        line = line:gsub("\r$", "")
        counts[line] = (counts[line] or 0) + 1
    end
    return counts
end

local function removeLine(text, line)
    local position, first, last, terminated = 1
    while position <= #text do
        local newline = text:find("\n", position, true)
        local finish = newline and newline - 1 or #text
        local content = text:sub(position, finish):gsub("\r$", "")
        if content == line then first, last, terminated = position, newline or finish, newline ~= nil end
        if not newline then break end
        position = newline + 1
    end
    if not first then return text end
    if last == #text and first > 1 and not terminated then
        first = first - 1
        if text:sub(first - 1, first - 1) == "\r" then first = first - 1 end
    end
    return text:sub(1, first - 1) .. text:sub(last + 1)
end

function adapter.PositionOffset(text, position)
    if position == "top" then return 0 end
    if type(position) ~= "number" or position ~= position or math.abs(position) == math.huge then return #text end
    local offset = math.max(0, math.min(#text, math.floor(position)))
     
    while offset > 0 do
        local byte = text:byte(offset + 1)
        if not byte or byte < 128 or byte >= 192 then break end
        offset = offset - 1
    end
    if text:sub(offset, offset + 1) == "\r\n" then offset = offset - 1 end
    return offset
end

local function receiptPosition(text, receipt, position)
    if type(position) ~= "number" or not receipt then return position end
    local first = lastOccurrence(text, receipt.block)
    if not first then return position end
    local counts, owned = lineCounts(text), {}
    for _, line in ipairs(receipt.lines) do owned[line] = (owned[line] or 0) + 1 end
    for line, count in pairs(owned) do
        if (counts[line] or 0) < (receipt.counts[line] or 0) + count then return position end
    end
    return first - 1
end

 
function adapter.Merge(text, receipt, lines, position)
    position = receiptPosition(text, receipt, position)
    if receipt then
        local counts, owned, complete = lineCounts(text), {}, true
        for _, line in ipairs(receipt.lines) do owned[line] = (owned[line] or 0) + 1 end
        for line, count in pairs(owned) do
            if (counts[line] or 0) < (receipt.counts[line] or 0) + count then complete = false end
        end
        local first = receipt.block ~= "" and lastOccurrence(text, receipt.block)
        if first and complete then
            text = text:sub(1, first - 1) .. text:sub(first + #receipt.block)
        else
            for index = #receipt.lines, 1, -1 do
                local line = receipt.lines[index]
                if (counts[line] or 0) > (receipt.counts[line] or 0) then
                    text = removeLine(text, line)
                    counts[line] = counts[line] - 1
                end
            end
        end
    end
    if #lines == 0 then return text, nil end
    local content = table.concat(lines, "\n")
    local block, updated
    if type(position) == "number" then
        local offset = adapter.PositionOffset(text, position)
        local before, after = text:sub(1, offset), text:sub(offset + 1)
        local startsLine = before == "" or before:sub(-1) == "\n"
        local endsLine = after == "" or after:sub(1, 1) == "\n" or after:sub(1, 2) == "\r\n"
        block = (startsLine and "" or "\n") .. content .. (endsLine and "" or "\n")
        updated = before .. block .. after
    else
        block = position == "top" and (content .. (text ~= "" and "\n" or ""))
            or ((text ~= "" and "\n" or "") .. content)
        updated = position == "top" and (block .. text) or (text .. block)
    end
    local existing, counts, owned = lineCounts(updated), {}, {}
    for _, line in ipairs(lines) do owned[line] = (owned[line] or 0) + 1 end
    for line, count in pairs(owned) do counts[line] = (existing[line] or 0) - count end
    return updated,
        { version = 1, block = block, lines = lines, counts = counts }
end

local function cleanReceipt(value, profileID)
    if type(value) ~= "table" or (value.version ~= 1 and value.version ~= 2) or value.profileID ~= profileID
        or type(value.block) ~= "string" or #value.block > 20000
        or type(value.lines) ~= "table" or #value.lines > 64 or type(value.counts) ~= "table" then return nil end
    local lines, counts = {}, {}
    for _, line in ipairs(value.lines) do
        if type(line) ~= "string" or line == "" or #line > 500 or line:find("[\r\n]") then return nil end
        local count = value.counts[line]
        if type(count) ~= "number" or count % 1 ~= 0 or count < 0 or count > 1000000 then return nil end
        lines[#lines + 1] = line
        counts[line] = count
    end
    if #lines == 0 then return nil end
    local content = table.concat(lines, "\n")
    if value.block ~= content and value.block ~= "\n" .. content and value.block ~= content .. "\n"
        and value.block ~= "\n" .. content .. "\n" then return nil end
    local members
    if value.version == 2 then
        if type(value.members) ~= "table" then return nil end
        members = {}
        local total = 0
        for _, line in ipairs(lines) do
            local ids = value.members[line]
            if type(ids) ~= "table" then return nil end
            members[line] = {}
            for id, present in pairs(ids) do
                total = total + 1
                if total > MAX_INSTANCES or not validKey(id) or present ~= true then return nil end
                members[line][id] = true
            end
        end
    end
    return { block = value.block, lines = lines, counts = counts, members = members }
end

local function publicationState(value, profileID)
    local state = { version = 1, profileID = profileID, suppressed = {}, native = {}, serial = 0 }
    if type(value) ~= "table" or value.version ~= 1 or value.profileID ~= profileID then return state end
    local serial = value.serial
    if type(serial) == "number" and serial % 1 == 0 and serial >= 0 and serial < 1e12 then state.serial = serial end
    local count = 0
    for id, present in pairs(type(value.suppressed) == "table" and value.suppressed or {}) do
        if count >= MAX_INSTANCES then break end
        if validKey(id) and present == true then state.suppressed[id] = true; count = count + 1 end
    end
    count = 0
    for id, generation in pairs(type(value.native) == "table" and value.native or {}) do
        if count >= 64 then break end
        if validKey(id, 500) and type(generation) == "number" and generation % 1 == 0
            and generation > 0 and generation <= state.serial then
            state.native[id] = generation; count = count + 1
        end
    end
    return state
end

local function duration(entry, context, now)
    if not entry.combat then
        if type(entry.expiresAt) == "number" and entry.expiresAt <= now then return nil end
        return ""
    end
    if type(entry.expiresRound) == "number" and context and type(context.roundNumber) == "number" then
        local rounds = entry.expiresRound - context.roundNumber
        if rounds <= 0 then return nil end
        return addon.L("CURRENTLY_EFFECT_ROUNDS", rounds)
    end
    local expiry = entry.expiresAt
    if type(expiry) == "number" and expiry == expiry and expiry < math.huge then
        if expiry <= now then return nil end
        return addon.L("CURRENTLY_EFFECT_MINUTES", math.ceil((expiry - now) / 60))
    end
    return addon.L("CURRENTLY_EFFECT_ENCOUNTER")
end

local function tooltipColorMap(playerID)
    local colors, seen = {}, {}
    local presentation = addon.SpellPresentation
    if not presentation or not presentation.GetMagicTextColor then return colors end
    local context, now = addon.GameMasterService.GetSubmissionContext(), addon.Runtime.GetTimestamp()
    for index, entry in ipairs(addon.EffectDisplay.List(playerID) or {}) do
        if index > MAX_INSTANCES then break end
        local spell = entry.spell
        local time = duration(entry, context, now)
        if time and not entry.hidden and not entry.pending and (not entry.native or entry.public)
            and spell and spell.effects and (spell.effects.buff or spell.effects.debuff) then
            local color = presentation.GetMagicTextColor(spell)
            local code = color and string.format("|cff%02x%02x%02x", math.floor(color[1] * 255 + 0.5),
                math.floor(color[2] * 255 + 0.5), math.floor(color[3] * 255 + 0.5)) or false
            local kind = addon.L(spell.effects.debuff and "TIMED_DEBUFF" or "TIMED_BUFF")
            local line = addon.L(time ~= "" and "CURRENTLY_EFFECT_LINE_DURATION" or "CURRENTLY_EFFECT_LINE",
                kind, addon.EffectDisplay.Text(spell.name, 200), time)
            if seen[line] and colors[line] ~= code then colors[line] = false
            elseif not seen[line] then colors[line] = code end
            seen[line] = true
        end
    end
    return colors
end

local function stripColors(text)
    return text:gsub("|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", "")
end

function adapter.ColorizeTooltip(tooltip, playerID)
    local ok, changed = pcall(function()
        local api = _G.TRP3_API
        local title = api and api.loc and api.loc.DB_STATUS_CURRENTLY
        if not playerID or type(title) ~= "string" or not tooltip or not tooltip.NumLines then return false end
        local colors = tooltipColorMap(playerID)
        local name = tooltip.GetName and tooltip:GetName()
        local inCurrently, updated = false, false
        for index = 1, math.min(100, tooltip:NumLines()) do
            local line = tooltip["TextLeft" .. index] or (name and _G[name .. "TextLeft" .. index])
            local text = line and line.GetText and line:GetText()
            if type(canaccessvalue) == "function" and not canaccessvalue(text) then return false end
            if type(text) == "string" and line.SetText then
                local previous = tooltipColors[line]
                local original = previous and text == previous.rendered and previous.original or text
                tooltipColors[line] = nil
                local rendered = original
                if inCurrently then
                    local restore = original:match("^|[cC]%x%x%x%x%x%x%x%x") or ""
                    rendered = original:gsub("[^\r\n]+", function(part)
                        local plain = stripColors(part)
                        local color = colors[plain]
                        return color and (color .. plain .. "|r" .. restore) or part
                    end)
                end
                if rendered ~= original then tooltipColors[line] = { original = original, rendered = rendered } end
                if text ~= rendered then line:SetText(rendered); updated = true end
                 
                inCurrently = stripColors(original) == title
            else inCurrently = false end
        end
        return updated
    end)
    return ok and changed == true
end

local function collectRows(state, data, user)
    local rows, byLine, active, eligible, nativeActive = {}, {}, {}, {}, {}
    local now = addon.Runtime.GetTimestamp()
    local context = addon.GameMasterService.GetSubmissionContext()
    local entries, nativeReady = addon.EffectDisplay.List(addon.GameMasterRoster.GetLocalPlayerID())
     
    if nativeReady == false then error(addon.L("TRP3_API_UNAVAILABLE", "Extended auras"), 0) end
    local records = {}
    local hasNative = false
    for _, entry in ipairs(entries) do if entry.native then hasNative = true; break end end
    if hasNative then
        local api = _G.TRP3_API
        local profile = api and api.profile and api.profile.getPlayerCurrentProfile
            and api.profile.getPlayerCurrentProfile() or nil
        if not profile and user and type(user.GetProfile) == "function" then profile = user:GetProfile() end
        for index, record in ipairs(profile and type(profile.auras) == "table" and profile.auras or {}) do
            if index > 64 then break end
            if type(record) == "table" and validKey(record.id, 500) and not record.invalid then records[record.id] = record end
        end
    end
    local pointers = {}
    for id, record in pairs(data and nativePointers[data] or {}) do pointers[id] = record end
    for index, entry in ipairs(entries) do
        if index > MAX_INSTANCES then break end
        local spell, time = entry.spell, duration(entry, context, now)
        if time and validKey(entry.id, 500) and spell and spell.effects and (spell.effects.buff or spell.effects.debuff) then
            local id
            if entry.native then
                local nativeID = entry.nativeID or entry.id
                if validKey(nativeID, 500) then
                    nativeActive[nativeID] = true
                    local record, generation = records[nativeID], state.native[nativeID]
                    if not generation or (record and pointers[nativeID] and record ~= pointers[nativeID]) then
                        state.serial = state.serial + 1
                        generation = state.serial
                        state.native[nativeID] = generation
                    end
                    if record then pointers[nativeID] = record end
                    id = "native\031" .. nativeID .. "\031" .. generation
                end
            elseif entry.roundEffect then
                id = table.concat({ "round", entry.id, tostring(entry.sourceRoundID or ""), tostring(entry.appliedAt or "") }, "\031")
            else
                 
                id = table.concat({ "timed", entry.id, tostring(entry.source or "") }, "\031")
            end
            if id then
                active[id] = true
                if not entry.hidden and not entry.pending and (not entry.native or entry.public) then
                    eligible[id] = true
                    local kind, name = addon.L(spell.effects.debuff and "TIMED_DEBUFF" or "TIMED_BUFF"), addon.EffectDisplay.Text(spell.name, 200)
                    local line = addon.L(time ~= "" and "CURRENTLY_EFFECT_LINE_DURATION" or "CURRENTLY_EFFECT_LINE", kind, name, time)
                    local presentation = addon.SpellPresentation
                    local color = presentation and presentation.GetMagicTextColor and presentation.GetMagicTextColor(spell)
                    local row = byLine[line]
                    if not row and #rows < 64 then
                        row = { line = line, label = addon.L("CURRENTLY_EFFECT_LINE", kind, name), timed = time ~= "", ids = {}, color = color }
                        rows[#rows + 1], byLine[line] = row, row
                    end
                    if row and row.color and (not color or row.color[1] ~= color[1]
                        or row.color[2] ~= color[2] or row.color[3] ~= color[3]) then row.color = nil end
                    if row then row.ids[id] = true end
                end
            end
        end
    end
    for id in pairs(state.suppressed) do if not active[id] then state.suppressed[id] = nil end end
    for id in pairs(state.native) do if not nativeActive[id] then state.native[id], pointers[id] = nil, nil end end
    for id in pairs(pointers) do if not nativeActive[id] then pointers[id] = nil end end
    return rows, active, eligible, pointers
end

local function suppressRemovedRows(text, receipt, rows, eligible, state)
    if not receipt then return end
    local counts, owned = lineCounts(text), {}
    for _, line in ipairs(receipt.lines) do owned[line] = (owned[line] or 0) + 1 end
    for line, count in pairs(owned) do
        if (counts[line] or 0) < (receipt.counts[line] or 0) + count then
            if receipt.members then
                for id in pairs(receipt.members[line]) do if eligible[id] then state.suppressed[id] = true end end
            else
                 
                for _, row in ipairs(rows) do
                    if line == row.line or (row.timed and line:sub(1, #row.label + 2) == row.label .. " (" and line:sub(-1) == ")") then
                        for id in pairs(row.ids) do state.suppressed[id] = true end
                    end
                end
            end
        end
    end
end

local function cleanOrder(order)
    local result, seen = {}, {}
    if type(order) ~= "table" then return result end
    for index, key in ipairs(order) do
        if index > 64 then break end
        if validKey(key, 1500) and not seen[key] then result[#result + 1], seen[key] = key, true end
    end
    return result
end

local function displayLines(rows, state, order)
    local lines, members, keys, ranks, sorted, colors = {}, {}, {}, {}, {}, {}
    for index, key in ipairs(cleanOrder(order)) do ranks[key] = index end
    for index, row in ipairs(rows) do
        local ids, first = {}, nil
        for id in pairs(row.ids) do
            if not state.suppressed[id] then
                ids[id] = true
                if not first or id < first then first = id end
            end
        end
        if first then sorted[#sorted + 1] = { row = row, index = index, ids = ids, key = row.label .. "\031" .. first } end
    end
    table.sort(sorted, function(first, second)
        local left, right = ranks[first.key] or 65, ranks[second.key] or 65
        return left < right or (left == right and first.index < second.index)
    end)
    for _, item in ipairs(sorted) do
        local row = item.row
        lines[#lines + 1], keys[#keys + 1], members[row.line] = row.line, item.key, item.ids
        if row.color then colors[item.key] = row.color end
    end
    return lines, members, keys, colors
end

local function currentUser()
    local player = _G.AddOn_TotalRP3 and AddOn_TotalRP3.Player
    if not player or type(player.GetCurrentUser) ~= "function" then return nil end
    local ok, user = pcall(player.GetCurrentUser)
    if ok and user and type(user.GetCurrentlyText) == "function" and type(user.SetCurrentlyText) == "function"
        and type(user.GetProfileID) == "function" and type(user.IsProfileDefault) == "function" then return user end
end

local function writtenCurrently(user, profileID, originalPlayer, expected)
    if user:GetProfileID() == profileID then return (user:GetCurrentlyText() or "") == expected end
     
    local character = type(originalPlayer) == "table" and originalPlayer.character
    return type(character) == "table" and (character.CU or "") == expected
end

function adapter.GetReceipt()
    local user = currentUser()
    local profileID = user and user:GetProfileID()
    local data = addon.Database.GetActiveProfileData()
    if data and profileID == addon.TRP3Bridge.GetActiveProfileID() then return cleanReceipt(data.currentlyEffects, profileID), profileID end
end

function adapter.Lines()
    local user, data = currentUser(), addon.Database.GetActiveProfileData()
    local state = publicationState(data and data.currentlyEffectPublication, user and user:GetProfileID())
    local rows = collectRows(state, data, user)
    return displayLines(rows, state, data and data.currentlyEffectsOrder)
end

local function editorState()
    if addon.GameMasterService.IsTutorialActive() or addon.GameMasterService.IsTestMode() then return nil end
    local user = currentUser()
    if not user or user:IsProfileDefault() then return nil end
    local profileID = user:GetProfileID()
    if type(profileID) ~= "string" or profileID ~= addon.TRP3Bridge.GetActiveProfileID() then return nil end
    local data, text = addon.Database.GetActiveProfileData(), user:GetCurrentlyText() or ""
    if not data or type(text) ~= "string" then return nil end
    local receipt = cleanReceipt(data.currentlyEffects, profileID)
    local state = publicationState(data.currentlyEffectPublication, profileID)
    local enabled = addon.SpellCreationSettings.ShouldPublishCurrentlyEffects()
    local lines, members, keys, colors, pointers, rows = {}, {}, {}, {}, nil, {}
    if enabled then
        local _, eligible, nextPointers
        rows, _, eligible, nextPointers = collectRows(state, data, user)
        suppressRemovedRows(text, receipt, rows, eligible, state)
        lines, members, keys, colors = displayLines(rows, state, data.currentlyEffectsOrder)
        pointers = nextPointers
    end
    return { profileID = profileID, data = data, user = user, publishedText = text,
        personalText = adapter.Merge(text, receipt, {}), lines = lines, members = members, keys = keys, colors = colors, rows = rows,
        enabled = enabled, position = type(data.currentlyEffectsPosition) == "number" and receiptPosition(text, receipt, data.currentlyEffectsPosition)
            or (data.currentlyEffectsPosition == "top" and "top" or "bottom"),
        publication = state, pointers = pointers }
end

function adapter.GetEditorModel()
    local ok, view = pcall(function()
        if editorSnapshot then
            if editorSnapshot.profileID ~= addon.TRP3Bridge.GetActiveProfileID()
                or addon.Database.GetActiveProfileData() ~= editorSnapshot.data then return nil end
            return editorSnapshot
        end
        return editorState()
    end)
    if not ok or not view then return nil end
    local lines, keys, colors = {}, {}, {}
    for index, line in ipairs(view.lines) do
        local key = view.keys[index]
        lines[index], keys[index] = line, key
        local color = view.colors and view.colors[key]
        if color then colors[key] = { color[1], color[2], color[3] } end
    end
    return { profileID = view.profileID, publishedText = view.publishedText, personalText = view.personalText,
        lines = lines, keys = keys, colors = colors, enabled = view.enabled, position = view.position,
        suppressedCount = addon.Runtime.CountEntries(view.publication.suppressed) }
end

function adapter.RestorePublication(profileID)
    local ok, view = pcall(editorState)
    if not ok or not view or view.profileID ~= profileID then return false end
    local publication = view.publication
    publication.suppressed = {}
    view.data.currentlyEffectPublication = next(publication.native) and publication or nil
    adapter.Sync()
    return true
end

function adapter.ComposePersonalText(text, position, profileID, order)
    if type(text) ~= "string" then return nil end
    local ok, view = pcall(editorState)
    if not ok or not view or view.profileID ~= profileID then return nil end
    local lines = order and displayLines(view.rows, view.publication, order) or view.lines
    return adapter.Merge(text, nil, lines, type(position) == "number" and position
        or (position == "top" and "top" or "bottom"))
end

function adapter.CommitPersonalText(text, position, profileID, order)
    if busy or type(text) ~= "string" then return false end
    busy = true
    local ok, saved = pcall(function()
        local view = editorState()
        if not view or view.profileID ~= profileID then return false end
        local api = _G.TRP3_API
        local sanitize = api and api.utils and api.utils.str and api.utils.str.sanitize
        if type(sanitize) == "function" then text = sanitize(text, true) end
        position = type(position) == "number" and adapter.PositionOffset(text, position)
            or (position == "top" and "top" or "bottom")
        local nextOrder = cleanOrder(order or view.data.currentlyEffectsOrder)
        local nextKeys
        view.lines, view.members, nextKeys, view.colors = displayLines(view.rows, view.publication, nextOrder)
        local updated, receipt = adapter.Merge(text, nil, view.lines, position)
        local originalPlayer = type(view.user.GetProfile) == "function" and view.user:GetProfile() or nil
        if addon.Database.GetActiveProfileData() ~= view.data or view.user:GetProfileID() ~= profileID
            or (view.user:GetCurrentlyText() or "") ~= view.publishedText then return false end
        if updated ~= view.publishedText then
             
            editorSnapshot = { profileID = profileID, data = view.data, personalText = text,
                publishedText = updated, lines = view.lines, keys = nextKeys, colors = view.colors, enabled = view.enabled,
                position = position, publication = view.publication }
            local written = pcall(view.user.SetCurrentlyText, view.user, updated)
            if not writtenCurrently(view.user, profileID, originalPlayer, updated) then return false end
            if not written and addon.Logger then addon.Logger.Error(addon.L("CURRENTLY_EDITOR_SAVE_CALLBACK")) end
        end
        if receipt then receipt.version, receipt.profileID, receipt.members = 2, profileID, view.members end
        view.data.currentlyEffects, view.data.currentlyEffectsPosition = receipt, position
        view.data.currentlyEffectsOrder = #nextKeys > 0 and nextKeys or nil
        local publication = view.publication
        view.data.currentlyEffectPublication = (next(publication.suppressed) or next(publication.native)) and publication or nil
        if view.pointers then nativePointers[view.data] = view.pointers end
        return true
    end)
    busy, editorSnapshot = false, nil
    if not ok and addon.Logger then addon.Logger.Error(tostring(saved)) end
    return ok and saved == true
end

local function editorPending()
    local editor = _G.TRP3_CurrentlyFrame
    local box = editor and editor.CurrentlyText and editor.CurrentlyText.scroll and editor.CurrentlyText.scroll.text
    if box and box ~= editorBox and type(box.HookScript) == "function" then
        box:HookScript("OnTextChanged", function(_, userInput)
            if userInput then
                 
                editorPendingUntil = addon.Runtime.GetMonotonicTime() + 0.6
            end
        end)
        editorBox = box
    end
    return (editor and editor:IsShown()) or addon.Runtime.GetMonotonicTime() < editorPendingUntil
end

local function synchronize()
    if addon.GameMasterService.IsTutorialActive() or addon.GameMasterService.IsTestMode() then return end
    if editorPending() then return end
    local user = currentUser()
    if not user or user:IsProfileDefault() then return end
    local profileID = user:GetProfileID()
    if type(profileID) ~= "string" or profileID ~= addon.TRP3Bridge.GetActiveProfileID() then return end
    local data = addon.Database.GetActiveProfileData()
    if not data then return end
    local text = user:GetCurrentlyText() or ""
    if type(text) ~= "string" then return end
    local receipt = cleanReceipt(data.currentlyEffects, profileID)
    local enabled = addon.SpellCreationSettings.ShouldPublishCurrentlyEffects()
    if not enabled and not receipt then return end
    local state = publicationState(data.currentlyEffectPublication, profileID)
    local lines, members, keys, colors, pointers = {}, {}, {}, {}, nil
    if enabled then
        local rows, _, eligible, nextPointers = collectRows(state, data, user)
        suppressRemovedRows(text, receipt, rows, eligible, state)
        lines, members, keys, colors = displayLines(rows, state, data.currentlyEffectsOrder)
        pointers = nextPointers
    end
    local updated, nextReceipt = adapter.Merge(text, receipt, lines, data.currentlyEffectsPosition)
    local originalPlayer = type(user.GetProfile) == "function" and user:GetProfile() or nil
    if addon.Database.GetActiveProfileData() ~= data or user:GetProfileID() ~= profileID
        or (user:GetCurrentlyText() or "") ~= text then return end
    if updated ~= text then
        editorSnapshot = { profileID = profileID, data = data, personalText = adapter.Merge(text, receipt, {}),
            publishedText = updated, lines = lines, keys = keys, colors = colors, enabled = enabled,
            position = receiptPosition(text, receipt, data.currentlyEffectsPosition), publication = state }
        local ok, failure = pcall(user.SetCurrentlyText, user, updated)
        if not writtenCurrently(user, profileID, originalPlayer, updated) then
            if not ok and addon.Logger then addon.Logger.Error(tostring(failure)) end
            return
        end
    end
    if nextReceipt then nextReceipt.version, nextReceipt.profileID, nextReceipt.members = 2, profileID, members end
    data.currentlyEffects = nextReceipt
    if type(data.currentlyEffectsPosition) == "number" then
        data.currentlyEffectsPosition = adapter.PositionOffset(adapter.Merge(text, receipt, {}), receiptPosition(text, receipt, data.currentlyEffectsPosition))
    end
    data.currentlyEffectPublication = (next(state.suppressed) or next(state.native)) and state or nil
    if pointers then nativePointers[data] = pointers end
end

function adapter.Sync()
    if busy then return end
    busy = true
    local ok, failure = pcall(synchronize)
    busy, editorSnapshot = false, nil
    if not ok and addon.Logger then addon.Logger.Error(tostring(failure)) end
end

function adapter.Initialize()
    if initialized then return end
    initialized = true
    local queued = false
    local function request()
        if busy or queued then return end
        queued = true
        local function run() queued = false; adapter.Sync() end
        if C_Timer and C_Timer.After then C_Timer.After(0, run) else run() end
    end
    addon.TimedEffects.RegisterListener(request)
    addon.GameMasterService.RegisterListener(request)
    addon.SpellCreationSettings.RegisterListener(request)
    local api = _G.TRP3_API
    if api and api.RegisterCallback and _G.TRP3_Addon then
        api.RegisterCallback(TRP3_Addon, "REGISTER_PROFILES_LOADED", request)
        api.RegisterCallback(TRP3_Addon, "REGISTER_DATA_UPDATED", function(_, unitID, _, dataType)
            if (not unitID or addon.EffectDisplay.IsSelf(unitID)) and (not dataType or dataType == "character") then request() end
        end)
    end
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(5, request) end
    request()
end
