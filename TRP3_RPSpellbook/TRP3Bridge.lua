local _, addon = ...

addon.TRP3Bridge = {}

local function getAPI()
    local api = _G.TRP3_API
    if type(api) ~= "table" then
        return nil
    end

    return api
end

local function getCommunications()
    local trpAddon = _G.AddOn_TotalRP3
    local communications = trpAddon and trpAddon.Communications
    if type(communications) ~= "table" then
        return nil
    end
    return communications
end

local function callFunction(target, functionName, ...)
    local targetFunction = target and target[functionName]
    if type(targetFunction) ~= "function" then
        return false, addon.L("TRP3_API_UNAVAILABLE", tostring(functionName))
    end

    local success, result = pcall(targetFunction, ...)
    if not success then
        return false, result
    end

    return true, result
end

local function callProfileFunction(functionName, ...)
    local api = getAPI()
    local profileAPI = api and api.profile
    local profileFunction = profileAPI and profileAPI[functionName]
    if type(profileFunction) ~= "function" then
        return nil
    end

    local success, result = pcall(profileFunction, ...)
    if not success then
        return nil
    end

    return result
end

local function getCharacterKey()
    local guid = UnitGUID and UnitGUID("player")
    if type(guid) == "string" and guid ~= "" then
        return guid
    end

    local characterName = UnitName and UnitName("player")
    local realmName = GetRealmName and GetRealmName()
    if type(characterName) ~= "string" or characterName == "" then
        return nil
    end

    if type(realmName) ~= "string" or realmName == "" then
        realmName = "unknown-realm"
    end

    return characterName .. "-" .. realmName
end

function addon.TRP3Bridge.IsAvailable()
    local api = getAPI()
    return api ~= nil and type(api.profile) == "table"
end

function addon.TRP3Bridge.GetActiveProfileID()
    local profileID = callProfileFunction("getPlayerCurrentProfileID")
    if type(profileID) ~= "string" or profileID == "" then
        return nil
    end

    return profileID
end

function addon.TRP3Bridge.GetActiveProfileKey()
    local profileID = addon.TRP3Bridge.GetActiveProfileID()
    if not profileID then
        return nil
    end

    if callProfileFunction("isDefaultProfile", profileID) == true then
        local characterKey = getCharacterKey()
        if not characterKey then
            return nil
        end

        return "trp3_default:" .. characterKey
    end

    return "trp3_profile:" .. profileID
end

function addon.TRP3Bridge.GetActiveProfileName()
    local profile = callProfileFunction("getPlayerCurrentProfile")
    if type(profile) ~= "table" then
        return nil
    end

    if type(profile.profileName) ~= "string" or profile.profileName == "" then
        return nil
    end

    return profile.profileName
end

function addon.TRP3Bridge.GetExportOwnerInfo()
    local profile = callProfileFunction("getPlayerCurrentProfile")
    local player = type(profile) == "table" and profile.player or nil
    local characteristics = type(player) == "table" and player.characteristics or nil
    local firstName = type(characteristics) == "table" and characteristics.FN or nil
    local lastName = type(characteristics) == "table" and characteristics.LN or nil
    local rpName
    if type(firstName) == "string" and firstName ~= "" then
        rpName = firstName
        if type(lastName) == "string" and lastName ~= "" then
            rpName = rpName .. " " .. lastName
        end
    end

    local characterName = type(UnitName) == "function" and UnitName("player") or nil
    local realmName = type(GetRealmName) == "function" and GetRealmName() or nil
    local ownerGuid = type(UnitGUID) == "function" and UnitGUID("player") or nil
    return {
        profileKey = addon.TRP3Bridge.GetActiveProfileKey(),
        characterName = characterName,
        realmName = realmName,
        rpName = rpName,
        ownerGuid = ownerGuid,
    }
end

local function createTRP3Player(playerID)
    if type(playerID) ~= "string" or playerID == "" then
        return nil
    end

    local trpAddon = _G.AddOn_TotalRP3
    local playerClass = type(trpAddon) == "table" and trpAddon.Player or nil
    local factory = type(playerClass) == "table"
        and (
            playerClass.CreateFromCharacterID
            or (
                type(playerClass.static) == "table"
                and playerClass.static.CreateFromCharacterID
            )
        )
        or nil
    if type(factory) ~= "function" then
        return nil
    end

    local success, player = pcall(factory, playerID)
    if not success or type(player) ~= "table" then
        return nil
    end

    return player
end

local function callPlayerMethod(player, methodName)
    local method = player and player[methodName]
    if type(method) ~= "function" then
        return nil
    end
    local success, value = pcall(method, player)
    if not success then
        return nil
    end
    return value
end

function addon.TRP3Bridge.GetRoleplayProfileInfo(playerID)
    local player = createTRP3Player(playerID)
    if not player then
        return nil
    end
    local characteristics = callPlayerMethod(player, "GetCharacteristics")
    if type(characteristics) ~= "table" then
        characteristics = {}
    end
    local rpName = callPlayerMethod(player, "GetRoleplayingName")
    return {
        color = characteristics.CH,
        firstName = characteristics.FN,
        icon = characteristics.IC,
        lastName = characteristics.LN,
        rpName = rpName,
        title = characteristics.TI or characteristics.FT,
    }
end

function addon.TRP3Bridge.GetRoleplayName(playerID)
    local profile = addon.TRP3Bridge.GetRoleplayProfileInfo(playerID)
    local name = profile and profile.rpName or nil
    if type(name) ~= "string" or name == "" then
        return nil
    end
    return name
end

local function accessible(value)
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        if not ok or secret ~= false then return false end
    end
    if type(canaccessvalue) == "function" then
        local ok, readable = pcall(canaccessvalue, value)
        if not ok or readable ~= true then return false end
    end
    return true
end

local function cleanPlayerDisplayText(value)
    if not accessible(value) or type(value) ~= "string" or #value > 2000 then return nil end
    local text = value:gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", "")
        :gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|", "")
        :gsub("[%c]", " "):gsub("%${", "$ {"):match("^%s*(.-)%s*$")
    return text ~= "" and #text <= 200 and text or nil
end

 
 
function addon.TRP3Bridge.GetPlayerDisplayIdentity(playerID)
    if not accessible(playerID) or type(playerID) ~= "string" then return "", nil end
    local fallback = cleanPlayerDisplayText(playerID) or ""
    local key = addon.Runtime.NormalizePlayerID(playerID)
    if not key or #playerID > 200 then return fallback, nil end
    local api = getAPI()
    local localID = api and api.globals and api.globals.player_id
    if not localID and addon.GameMasterRoster and addon.GameMasterRoster.GetLocalPlayerID then
        local ok, value = pcall(addon.GameMasterRoster.GetLocalPlayerID)
        if ok then localID = value end
    end
    if accessible(localID) and addon.Runtime.NormalizePlayerID(localID) == key then
         
         
        playerID, fallback = localID, cleanPlayerDisplayText(localID) or fallback
    end
    local register = api and api.register
    local characterList = register and register.getCharacterList
    if type(characterList) == "function" then
        local ok, characters = pcall(characterList)
        if ok and type(characters) == "table" and not characters[playerID] then
             
            for knownID in pairs(characters) do
                if accessible(knownID) and addon.Runtime.NormalizePlayerID(knownID) == key then
                    playerID, fallback = knownID, cleanPlayerDisplayText(knownID) or fallback
                    break
                end
            end
        end
    end
    local profile = addon.TRP3Bridge.GetRoleplayProfileInfo(playerID) or {}
    local first = cleanPlayerDisplayText(profile.firstName) or ""
    local last = cleanPlayerDisplayText(profile.lastName) or ""
    if type(profile.firstName) == "nil" and last ~= "" then
        first = cleanPlayerDisplayText(playerID:match("^[^-]+")) or ""
    end
    local name = (first .. " " .. last):match("^%s*(.-)%s*$")
    local color = accessible(profile.color) and type(profile.color) == "string"
        and profile.color:gsub("^#", "") or nil
    if not color or not color:match("^%x%x%x%x%x%x$") then color = nil end
    return name ~= "" and name or fallback, color
end

 
local function whisperField(object, field)
    if not accessible(object) or type(object) ~= "table" then return nil end
    local ok, value = pcall(function() return object[field] end)
    if ok and accessible(value) then return value end
end

local function whisperCall(object, field, ...)
    local method = whisperField(object, field)
    if type(method) ~= "function" then return nil end
    local ok, value = pcall(method, ...)
    if ok and accessible(value) then return value end
end

local function whisperKey(value)
    if not accessible(value) or type(value) ~= "string" or #value > 200 then return nil end
    return addon.Runtime.NormalizePlayerID(value)
end

local function whisperUnitMatches(unit, key)
    if type(UnitIsPlayer) == "function" then
        local ok, isPlayer = pcall(UnitIsPlayer, unit)
        if not ok or not accessible(isPlayer) or isPlayer ~= true then return false end
    end
    local getName = type(UnitFullName) == "function" and UnitFullName or UnitName
    if type(getName) ~= "function" then return false end
    local ok, name, realm = pcall(getName, unit)
    if not ok or not accessible(name) or not accessible(realm)
        or type(name) ~= "string" or #name > 200 then return false end
    if realm == nil or realm == "" then
        local getRealm = type(GetNormalizedRealmName) == "function" and GetNormalizedRealmName or GetRealmName
        if type(getRealm) ~= "function" then return false end
        ok, realm = pcall(getRealm)
        if not ok or not accessible(realm) then return false end
    end
    if type(realm) ~= "string" or #realm > 200 then return false end
    return whisperKey(name .. "-" .. realm:gsub("%s+", "")) == key
end

 
 
function addon.TRP3Bridge.GetWhisperIdentity(playerID, unitToken)
    local identity = { firstName = "", lastName = "", fullName = "", race = "", class = "", title = "" }
    local key = whisperKey(playerID)
    if not key then return identity end
    playerID = playerID:match("^%s*(.-)%s*$")
    local api = whisperField(_G, "TRP3_API")
    local globals = whisperField(api, "globals")
    local localID = whisperField(globals, "player_id")
    if not whisperKey(localID) then
        localID = whisperCall(addon.GameMasterRoster, "GetLocalPlayerID")
    end
    local isLocal = whisperKey(localID) == key
    local register = whisperField(api, "register")
    local characters = whisperCall(register, "getCharacterList")
    if isLocal then
        playerID = localID
    elseif type(characters) == "table" then
         
        if not whisperField(characters, playerID) then
            local scanned = 0
            for knownID in next, characters do
                scanned = scanned + 1
                if scanned > 500 then break end
                if whisperKey(knownID) == key then playerID = knownID; break end
            end
        end
    end

    local playerClass = whisperField(whisperField(_G, "AddOn_TotalRP3"), "Player")
    local factoryOwner = type(whisperField(playerClass, "CreateFromCharacterID")) == "function"
        and playerClass or whisperField(playerClass, "static")
    local player = whisperCall(factoryOwner, "CreateFromCharacterID", playerID)
    local fields = whisperCall(player, "GetCharacteristics", player)
    local function text(field) return cleanPlayerDisplayText(whisperField(fields, field)) end
    local engineName = cleanPlayerDisplayText(playerID:match("^[^-]+")) or ""
    local first, last = text("FN"), text("LN")
    identity.firstName, identity.lastName = first or engineName, last or engineName
    identity.fullName = cleanPlayerDisplayText(identity.firstName .. (last and (" " .. last) or ""))
        or identity.firstName
    identity.race, identity.class, identity.title = text("RA") or "", text("CL") or "", text("TI") or ""

    if identity.race ~= "" and identity.class ~= "" then return identity end
     
     
    local cached = isLocal and globals or nil
    if identity.race == "" then
        identity.race = cleanPlayerDisplayText(whisperField(cached, "player_race_loc")) or ""
    end
    if identity.class == "" then
        identity.class = cleanPlayerDisplayText(whisperField(cached, "player_class_loc")) or ""
    end
     
    if identity.race ~= "" and identity.class ~= "" then return identity end

    local unit
    if accessible(unitToken) and type(unitToken) == "string" and #unitToken <= 40
        and unitToken:match("^[%a%d]+$") and whisperUnitMatches(unitToken, key) then
        unit = unitToken
    end
    if not unit then
         
         
        if whisperUnitMatches("player", key) then
            unit = "player"
        end
        for index = 1, 4 do
            if unit then break end
            local candidate = "party" .. index
            if whisperUnitMatches(candidate, key) then unit = candidate end
        end
        for index = 1, 40 do
            if unit then break end
            local candidate = "raid" .. index
            if whisperUnitMatches(candidate, key) then unit = candidate end
        end
        if not unit and whisperUnitMatches("target", key) then unit = "target" end
    end
    for _, entry in ipairs({ { "race", "UnitRace" }, { "class", "UnitClass" } }) do
        local field, engineAPI = entry[1], entry[2]
        if identity[field] == "" then
            local value
             
            if unit and whisperUnitMatches(unit, key) then
                value = whisperCall(_G, engineAPI, unit)
            end
            identity[field] = cleanPlayerDisplayText(value) or ""
        end
    end
    return identity
end

local function cleanRegisterPreviewText(value)
    if type(value) ~= "string" then
        return nil
    end
    local text = value:match("^%s*(.-)%s*$")
    if text == "" or #text > 120 or text:find("[%c|]") then
        return nil
    end
    return text
end

function addon.TRP3Bridge.GetPlayerProfileKey(playerID)
    local api = getAPI()
    local register = api and api.register
    if not register or type(register.getUnitIDProfileID) ~= "function" then return nil end
    local ok, id = pcall(register.getUnitIDProfileID, playerID)
    if not ok or type(id) ~= "string" then return nil end
    return "trp3_profile:" .. id
end

local function cleanCharacterDisplayName(value)
    if type(value) ~= "string" then
        return nil
    end
    if type(issecretvalue) == "function" and issecretvalue(value) then
        return nil
    end
    return cleanRegisterPreviewText(value)
end

function addon.TRP3Bridge.GetActiveCharacterFirstName()
    local profile = callProfileFunction("getPlayerCurrentProfile")
    local player = type(profile) == "table" and profile.player or nil
    local characteristics = type(player) == "table" and player.characteristics or nil
    local firstName = type(characteristics) == "table"
        and cleanCharacterDisplayName(characteristics.FN)
        or nil
    if firstName then
        return firstName
    end

    local characterName = type(UnitName) == "function" and UnitName("player") or nil
    return cleanCharacterDisplayName(characterName)
end

function addon.TRP3Bridge.GetKnownRoleplayProfiles(limit)
    limit = math.max(1, math.min(100, math.floor(tonumber(limit) or 80)))
    local api = getAPI()
    local register = api and api.register
    local getCharacterList = register and register.getCharacterList
    if type(getCharacterList) ~= "function" then
        return {}
    end

    local success, characters = pcall(getCharacterList)
    if not success or type(characters) ~= "table" then
        return {}
    end

    local results = {}
    local eligible = 0
    local scanned = 0
    local maximumScan = math.min(500, math.max(100, limit * 5))
    for playerID, character in pairs(characters) do
        scanned = scanned + 1
        if scanned > maximumScan then
            break
        end
        if type(playerID) == "string"
            and type(character) == "table"
            and character.profileID ~= nil
        then
            local profile = addon.TRP3Bridge.GetRoleplayProfileInfo(playerID)
            if type(profile) == "table" then
                local firstName = cleanRegisterPreviewText(profile.firstName)
                local lastName = cleanRegisterPreviewText(profile.lastName)
                local rpName = cleanRegisterPreviewText(profile.rpName)
                if not rpName and (firstName or lastName) then
                    rpName = table.concat({ firstName or "", lastName or "" }, " ")
                        :match("^%s*(.-)%s*$")
                end
                if rpName or firstName or lastName then
                    local color = cleanRegisterPreviewText(profile.color)
                    color = color and color:gsub("#", "") or nil
                    if color and not color:match("^%x%x%x%x%x%x$") then
                        color = nil
                    end
                    local candidate = {
                        firstName = firstName,
                        gameName = playerID,
                        lastName = lastName,
                        profileColor = color,
                        profileIcon = profile.icon,
                        rpName = rpName,
                        title = cleanRegisterPreviewText(profile.title),
                    }
                    eligible = eligible + 1
                    if #results < limit then
                        results[#results + 1] = candidate
                    else
                        local slot = math.random(eligible)
                        if slot <= limit then
                            results[slot] = candidate
                        end
                    end
                end
            end
        end
    end
    return results
end

function addon.TRP3Bridge.RegisterModule(moduleStructure)
    local api = getAPI()
    return callFunction(api and api.module, "registerModule", moduleStructure)
end

function addon.TRP3Bridge.RegisterWorkflowLoadedCallback(callback)
    local api = getAPI()
    local trpAddon = _G.TRP3_Addon
    local events = trpAddon and trpAddon.Events
    if type(api) ~= "table" or type(api.RegisterCallback) ~= "function" or type(trpAddon) ~= "table" or type(events) ~= "table" then
        return false, addon.L("TRP3_WORKFLOW_UNAVAILABLE")
    end

    local eventName = events.WORKFLOW_ON_LOADED
    if type(eventName) ~= "string" then
        return false, addon.L("TRP3_WORKFLOW_EVENT_UNAVAILABLE")
    end

    local success, result = pcall(api.RegisterCallback, trpAddon, eventName, callback)
    if not success then
        return false, result
    end

    return true, result
end

function addon.TRP3Bridge.RegisterNavigationPage(pageStructure)
    local api = getAPI()
    return callFunction(api and api.navigation and api.navigation.page, "registerPage", pageStructure)
end

function addon.TRP3Bridge.RegisterNavigationMenu(menuStructure)
    local api = getAPI()
    return callFunction(api and api.navigation and api.navigation.menu, "registerMenu", menuStructure)
end

function addon.TRP3Bridge.SetNavigationPage(pageID)
    local api = getAPI()
    return callFunction(api and api.navigation and api.navigation.page, "setPage", pageID)
end

function addon.TRP3Bridge.IsNavigationMenuRegistered(menuID)
    local api = getAPI()
    return callFunction(api and api.navigation and api.navigation.menu, "isMenuRegistered", menuID)
end

function addon.TRP3Bridge.OpenNavigationMenu(menuID)
    local api = getAPI()
    local navigation = api and api.navigation
    local menu = navigation and navigation.menu
    if type(navigation) ~= "table" or type(navigation.openMainFrame) ~= "function" or type(menu) ~= "table" then
        return false, addon.L("TRP3_NAVIGATION_UNAVAILABLE")
    end

    local registeredSuccess, isRegistered = addon.TRP3Bridge.IsNavigationMenuRegistered(menuID)
    if not registeredSuccess then
        return false, isRegistered
    end

    if not isRegistered then
        return false, addon.L("TRP3_MENU_NOT_REGISTERED")
    end

    local openSuccess, openError = pcall(navigation.openMainFrame)
    if not openSuccess then
        return false, openError
    end

    return callFunction(menu, "selectMenu", menuID)
end

function addon.TRP3Bridge.CloseMainFrame()
    local frame = _G.TRP3_MainFrame
    if frame and type(frame.Hide) == "function" then
        frame:Hide()
        return true
    end
    return false, addon.L("TRP3_NAVIGATION_UNAVAILABLE")
end

function addon.TRP3Bridge.OpenConfigurationPage(pageID)
    if type(pageID) ~= "string" or pageID == "" then
        return false, addon.L("TRP3_MENU_NOT_REGISTERED")
    end
    return addon.TRP3Bridge.OpenNavigationMenu(
        "main_91_config_" .. pageID
    )
end

function addon.TRP3Bridge.GetTutorialConfigurationPage(pageID)
    if type(pageID) ~= "string" or pageID == "" then return nil end
    local root = _G.TRP3_MainFramePageContainer
    if not root or not root:IsVisible() then return nil end
    local api = getAPI()
    local ok, current = callFunction(api and api.navigation and api.navigation.page, "getCurrentPageID")
    if ok and current == pageID then return root end
end

function addon.TRP3Bridge.GetTutorialWindows()
    local result = {}
    for _, name in ipairs({ "TRP3_MainFrame", "TRP3_IconBrowserFrame", "TRP3_ColorBrowser" }) do
        local frame = _G[name]
        if frame and frame:IsVisible() then result[#result + 1] = frame end
    end
    return result
end

function addon.TRP3Bridge.GetTutorialNavigationAnchor(menuID)
    local api = getAPI()
    local menu = api and api.navigation and api.navigation.menu
    local ok, item = callFunction(menu, "getMenuItem", menuID)
    local container = _G.TRP3_MainFrameMenuContainer
    if ok and item and container and type(container.GetChildren) == "function" then
        for _, child in ipairs({ container:GetChildren() }) do
            if child:IsShown() and type(child.GetText) == "function" and child:GetText() == item.text then
                return child
            end
        end
    end
    return container
end

function addon.TRP3Bridge.GetTutorialConfigurationAnchor(caption)
    local root = _G.TRP3_MainFramePageContainer
    if not root or not root:IsVisible() then return nil end
    local queue, head = { root }, 1
    while head <= #queue and head <= 128 do
        local current = queue[head]
        head = head + 1
        if current:IsVisible() then
            if type(current.GetText) == "function" and current:GetText() == caption then return current end
            if type(current.GetChildren) == "function" then
                for _, child in ipairs({ current:GetChildren() }) do
                    if #queue < 128 then queue[#queue + 1] = child end
                end
            end
        end
    end
end

function addon.TRP3Bridge.RegisterToolbarButton(buttonStructure)
    local api = getAPI()
    return callFunction(api and api.toolbar, "toolbarAddButton", buttonStructure)
end

function addon.TRP3Bridge.ResolveIconTexture(icon)
    if type(icon) == "number" and icon > 0 then
        return icon
    end

    if type(icon) ~= "string" or icon == "" then
        return nil
    end

    local numericIcon = tonumber(icon)
    if numericIcon and numericIcon > 0 then
        return numericIcon
    end

    if icon:find("\\", 1, true) or icon:find("/", 1, true) then
        return icon
    end

    local api = getAPI()
    local success, texture = callFunction(api and api.utils, "getIconTexture", icon)
    if success and texture then
        return texture
    end

    return "Interface\\Icons\\" .. icon
end

function addon.TRP3Bridge.SetIconTexture(texture, icon)
    if type(texture) ~= "table" and type(texture) ~= "userdata" then
        return false, addon.L("INVALID_TEXTURE")
    end

    local isPath = type(icon) == "string" and (icon:find("\\", 1, true) or icon:find("/", 1, true))
    if not isPath then
        local libStub = _G.LibStub
        local getLibrary = libStub and libStub.GetLibrary
        if type(getLibrary) == "function" then
            local librarySuccess, iconLibrary = pcall(getLibrary, libStub, "LibRPMedia-1.2", true)
            if librarySuccess and type(iconLibrary) == "table" and type(iconLibrary.SetTextureToIcon) == "function" then
                local textureSuccess, textureError = pcall(iconLibrary.SetTextureToIcon, iconLibrary, texture, icon)
                if textureSuccess then
                    return true
                end
                return false, textureError
            end
        end
    end

    local resolved = addon.TRP3Bridge.ResolveIconTexture(icon)
    if not resolved or type(texture.SetTexture) ~= "function" then
        return false, addon.L("ICON_RESOLVE_FAILED")
    end

    local success, errorMessage = pcall(texture.SetTexture, texture, resolved)
    return success, errorMessage
end

function addon.TRP3Bridge.OpenIconBrowser(selectedIcon, onAccepted, onCancelled, ownerFrame)
    if type(onAccepted) ~= "function" then
        return false, addon.L("INVALID_CALLBACK")
    end

    local selectedIconName = type(selectedIcon) == "string" and selectedIcon:match("([^\\/]+)$") or nil
    local api = getAPI()
    local popupAPI = api and api.popup
    if type(popupAPI) == "table"
        and type(popupAPI.showPopup) == "function"
        and popupAPI.ICONS ~= nil
    then
        local popupPosition = ownerFrame and {
            parent = ownerFrame,
            point = "CENTER",
            parentPoint = "CENTER",
        } or nil
        local success, errorMessage = pcall(
            popupAPI.showPopup,
            popupAPI.ICONS,
            popupPosition,
            {
                function(icon, iconInfo)
                    if icon ~= nil and icon ~= "" then
                        onAccepted(icon, iconInfo)
                    end
                end,
                onCancelled,
                nil,
                selectedIconName,
            }
        )
        if success then
            return true
        end
        return false, errorMessage
    end

    local iconBrowser = _G.TRP3_IconBrowser
    if type(iconBrowser) ~= "table" or type(iconBrowser.Open) ~= "function" then
        return false, addon.L("TRP3_ICON_BROWSER_UNAVAILABLE")
    end

    local success, errorMessage = pcall(iconBrowser.Open, {
        selectedIcon = selectedIconName,
        onAcceptCallback = function(iconInfo)
            if type(iconInfo) ~= "table" then
                return
            end

            local icon = iconInfo.name
            if icon == nil or icon == "" then
                icon = iconInfo.file
            end
            if icon ~= nil and icon ~= "" then
                onAccepted(icon, iconInfo)
            end
        end,
        onCancelCallback = onCancelled,
    })
    if not success then
        return false, errorMessage
    end

    local browserFrame = _G.TRP3_IconBrowserFrame
    if browserFrame then
        if type(browserFrame.SetFrameStrata) == "function" then
            browserFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        end
        if type(browserFrame.SetToplevel) == "function" then
            browserFrame:SetToplevel(true)
        end
        if ownerFrame then
            browserFrame:ClearAllPoints()
            browserFrame:SetPoint("CENTER", ownerFrame, "CENTER", 0, 0)
            local ownerLevel = type(ownerFrame.GetFrameLevel) == "function"
                and ownerFrame:GetFrameLevel()
                or 0
            browserFrame:SetFrameLevel(ownerLevel + 50)
        end
        browserFrame:Show()
    end
    return true
end

function addon.TRP3Bridge.OpenColorPicker(colorHex, onAccepted, _onCancelled, ownerFrame)
    if type(onAccepted) ~= "function" then
        return false, addon.L("INVALID_CALLBACK")
    end
    local api = getAPI()
    local popupAPI = api and api.popup
    if type(popupAPI) ~= "table" or type(popupAPI.showPopup) ~= "function" or popupAPI.COLORS == nil then
        return false, addon.L("TRP3_COLOR_BROWSER_UNAVAILABLE")
    end
    local color = type(colorHex) == "string" and colorHex:gsub("#", "") or "FFFFFF"
    if not color:match("^%x%x%x%x%x%x$") then
        color = "FFFFFF"
    end
    local red = tonumber(color:sub(1, 2), 16) or 255
    local green = tonumber(color:sub(3, 4), 16) or 255
    local blue = tonumber(color:sub(5, 6), 16) or 255
    local popupPosition = ownerFrame and {
        parent = ownerFrame,
        point = "CENTER",
        parentPoint = "CENTER",
    } or nil
    local success, errorMessage = pcall(
        popupAPI.showPopup,
        popupAPI.COLORS,
        popupPosition,
        {
            function(r8, g8, b8)
                local function clampByte(value)
                    return math.max(0, math.min(255, math.floor((tonumber(value) or 255) + 0.5)))
                end
                local selected = string.format("%02X%02X%02X", clampByte(r8), clampByte(g8), clampByte(b8))
                onAccepted(selected)
            end,
            red,
            green,
            blue,
        }
    )
    if not success then
        return false, errorMessage
    end
    return true
end

local spellChatLinksModule
local spellHoverInitialized = false
local spellHoverInitializationAttempted = false
local spellHoverInitializationError
local spellHoverResponseCallback
local spellHoverRequestRates = addon.Cache.NewBounded(
    addon.Constants.MAX_CHAT_HOVER_CACHE_ENTRIES
)

local function getMagicSummary(spell)
    return addon.SpellPresentation.GetClassificationSummary(spell.tags, spell.effects)
end

local function getTooltipColor(api, hex, fallback)
    if type(api.CreateColorFromHexString) == "function" then
        local success, color = pcall(api.CreateColorFromHexString, hex)
        if success and color then
            return color
        end
    end
    return fallback
end

function addon.TRP3Bridge.GetTooltipIconMarkup(icon)
    local resolved = addon.TRP3Bridge.ResolveIconTexture(icon)
        or addon.TRP3Bridge.ResolveIconTexture(addon.Constants.DEFAULT_BOOK_ICON)
    if resolved == nil then
        return ""
    end

    local texture = tostring(resolved):gsub("[|:%c]", "")
    if texture == "" then
        return ""
    end
    return "|T" .. texture .. ":32:32|t "
end

local function buildSpellChatTooltip(api, snapshot)
    local spell = type(snapshot) == "table" and snapshot.spell or nil
    if type(spell) ~= "table" then
        spell = { name = addon.L("UNKNOWN_ABILITY") }
    end
    if addon.ChatLinks.ValidateTooltipSpell then
        spell = addon.ChatLinks.ValidateTooltipSpell(spell) or spell
    end

    local tooltipLines = api.ChatLinkTooltipLines()
    local name = addon.ChatLinks.SanitizeDisplayName(spell.name)
    local nameColor = type(spell.nameColor) == "string" and spell.nameColor or "FFFFFF"
    tooltipLines:SetTitle(addon.TRP3Bridge.GetTooltipIconMarkup(spell.icon) .. "|cff" .. nameColor .. name .. "|r")

    local white = api.Colors.White
    local yellow = api.Colors.Yellow
    local magicSummary = getMagicSummary(spell)
    if magicSummary then
        tooltipLines:AddLine(magicSummary, getTooltipColor(api, "A6B8D1", white))
    end

    local hasResource = type(spell.resource) == "string" and spell.resource ~= ""
    local hasRange = type(spell.range) == "string" and spell.range ~= ""
    if hasResource or hasRange then
        tooltipLines:AddDoubleLine(
            hasResource and spell.resource or "",
            hasRange and (addon.L("FIELD_RANGE") .. ": " .. spell.range) or "",
            white,
            white
        )
    end
    local castTime, cooldown = addon.SpellPresentation.GetTooltipTiming(spell)
    if castTime or cooldown then
        tooltipLines:AddDoubleLine(castTime or " ", cooldown or "", white, white)
    end
    local effectText = addon.SpellPresentation.GetEffectTooltipText(spell)
    if effectText then tooltipLines:AddLine(effectText, white) end
    if type(spell.description) == "string" and spell.description ~= "" then
        tooltipLines:AddLine(" ", white)
        tooltipLines:AddLine(spell.description, yellow)
    end

    return tooltipLines
end

local function getSpellChatIdentifierStem(name)
    return addon.ChatLinks.GetNativeName(name)
end

local function getSnapshotChatStem(snapshot)
    local stem = type(snapshot) == "table" and snapshot.effectLinkStem
    local spell = type(snapshot) == "table" and snapshot.spell
    local name = getSpellChatIdentifierStem(type(spell) == "table" and spell.name or addon.L("UNKNOWN_ABILITY"))
    if type(stem) == "string" and #stem <= 180
        and stem:match("^(.-)%-rpsba%-%d+%-%d+%-%x+$") == name then return stem end
    return name
end

local function installSpellChatIdentifierLookup(manager)
    local original = manager.GetSentLinkForIdentifier
    function manager:GetSentLinkForIdentifier(identifier, ...)
        local link = original(self, identifier, ...)
        if link then return link end
        local originalIdentifier = addon.ChatLinks.DecodeNativeIdentifier(identifier)
        if not originalIdentifier then return nil end
        link = original(self, originalIdentifier, ...)
        if type(link) == "table" and type(link.GetModuleID) == "function"
            and type(link.GetIdentifier) == "function"
            and link:GetModuleID() == addon.Constants.CHAT_LINK_MODULE_ID
            and link:GetIdentifier() == identifier then return link end
    end
end

function addon.TRP3Bridge.InitializeSpellChatLinks()
    if addon.ChatAddonSupport then addon.ChatAddonSupport.Initialize() end
    if spellChatLinksModule then
        return true
    end

    local api = getAPI()
    local chatLinks = api and api.ChatLinks
    if type(chatLinks) ~= "table"
        or type(chatLinks.InstantiateModule) ~= "function"
        or api.ChatLinkTooltipLines == nil
        or type(api.Colors) ~= "table"
        or api.Colors.White == nil
        or api.Colors.Yellow == nil
        or type(api.ChatLinksManager) ~= "table"
        or type(api.ChatLinksManager.GetSentLinkForIdentifier) ~= "function"
    then
        return false, addon.L("CHAT_LINK_API_UNAVAILABLE")
    end

    local success, moduleOrError = pcall(
        chatLinks.InstantiateModule,
        chatLinks,
        addon.L("CHAT_LINK_MODULE_NAME"),
        addon.Constants.CHAT_LINK_MODULE_ID
    )
    if not success or type(moduleOrError) ~= "table" then
        return false, moduleOrError or addon.L("CHAT_LINK_API_UNAVAILABLE")
    end

    function moduleOrError:GetLinkData(snapshot)
        return getSnapshotChatStem(snapshot), snapshot
    end

    function moduleOrError:GetTooltipLines(snapshot)
        return buildSpellChatTooltip(api, snapshot)
    end

    installSpellChatIdentifierLookup(api.ChatLinksManager)
    spellChatLinksModule = moduleOrError
    return true
end

function addon.TRP3Bridge.CreateSpellChatLink(snapshot)
    if type(snapshot) ~= "table" or type(snapshot.spell) ~= "table" then
        return nil, addon.L("INVALID_CHAT_LINK")
    end

    local initialized, initializeError = addon.TRP3Bridge.InitializeSpellChatLinks()
    if not initialized then
        return nil, initializeError
    end

    local api = getAPI()
    if not api or api.ChatLink == nil then
        return nil, addon.L("CHAT_LINK_API_UNAVAILABLE")
    end

    local name = getSnapshotChatStem(snapshot)
    local success, linkOrError = pcall(
        api.ChatLink,
        name,
        snapshot,
        addon.Constants.CHAT_LINK_MODULE_ID
    )
    if not success or type(linkOrError) ~= "table" or type(linkOrError.GetText) ~= "function" then
        return nil, linkOrError or addon.L("CHAT_LINK_API_UNAVAILABLE")
    end

    if type(linkOrError.GetIdentifier) ~= "function" or type(linkOrError.SetIdentifier) ~= "function" then
        return nil, addon.L("CHAT_LINK_API_UNAVAILABLE")
    end
    local identifierSuccess, identifier = pcall(linkOrError.GetIdentifier, linkOrError)
    identifier = identifierSuccess and addon.ChatLinks.CreateNativeIdentifier(identifier, snapshot.effectLinkStem == name)
    if not identifier then return nil, addon.L("CHAT_LINK_TOO_LONG") end
    local renamed, renameError = pcall(linkOrError.SetIdentifier, linkOrError, identifier)
    if not renamed then return nil, renameError or addon.L("CHAT_LINK_API_UNAVAILABLE") end
    local lookupSuccess, registered = pcall(api.ChatLinksManager.GetSentLinkForIdentifier, api.ChatLinksManager, identifier)
    if not lookupSuccess or registered ~= linkOrError then return nil, addon.L("CHAT_LINK_API_UNAVAILABLE") end

    local textSuccess, textOrError = pcall(linkOrError.GetText, linkOrError)
    if not textSuccess or type(textOrError) ~= "string" or textOrError == "" then
        return nil, textOrError or addon.L("CHAT_LINK_API_UNAVAILABLE")
    end
     
    if #textOrError > addon.Constants.MAX_CHAT_TOKEN_LENGTH
        or not textOrError:match("^%[TRP3:[^%s%c%[%]|]+%]$")
    then
        return nil, addon.L("CHAT_LINK_TOO_LONG")
    end
    return textOrError
end

local function isValidChatLinkIdentifier(identifier)
    return type(identifier) == "string"
        and identifier ~= ""
        and #identifier <= addon.Constants.MAX_CHAT_TOKEN_LENGTH
        and not identifier:find("[%c|]")
end

local function getSentSpellChatLink(api, identifier)
    if not isValidChatLinkIdentifier(identifier) then
        return nil, "missing"
    end

    local manager = api and api.ChatLinksManager
    if type(manager) ~= "table" or type(manager.GetSentLinkForIdentifier) ~= "function" then
        return nil, "missing"
    end

    local linkSuccess, sentLink = pcall(manager.GetSentLinkForIdentifier, manager, identifier)
    if not linkSuccess or type(sentLink) ~= "table" then
        return nil, "missing"
    end
    if type(sentLink.GetModuleID) ~= "function" then
        return nil, "not_spell"
    end

    local moduleSuccess, moduleID = pcall(sentLink.GetModuleID, sentLink)
    if not moduleSuccess or moduleID ~= addon.Constants.CHAT_LINK_MODULE_ID then
        return nil, "not_spell"
    end
    return sentLink, "ok"
end

local function getSpellFromSentLink(sentLink)
    if type(sentLink) ~= "table" or type(sentLink.GetData) ~= "function" then
        return nil
    end

    local dataSuccess, snapshot = pcall(sentLink.GetData, sentLink)
    if not dataSuccess
        or type(snapshot) ~= "table"
        or snapshot.formatVersion ~= addon.Constants.CHAT_LINK_FORMAT_VERSION
        or type(snapshot.spell) ~= "table"
    then
        return nil
    end
    return addon.ChatLinks.ValidateTooltipSpell(snapshot.spell)
end

function addon.TRP3Bridge.FormatOwnSpellChatHyperlink(identifier)
    local api = getAPI()
    local sentLink = getSentSpellChatLink(api, identifier)
    if not sentLink then
        return nil
    end

    local playerID = api.globals and api.globals.player_id
    if type(playerID) ~= "string" or playerID == "" or playerID:find("[%c|:]") then
        return nil
    end

    local spell = getSpellFromSentLink(sentLink)
    local displayName = spell and spell.name or identifier:match("^(.*):%d+$") or identifier
    displayName = addon.ChatLinks.SanitizeDisplayName(displayName)
    local hyperlink = string.format(
        "|Haddon:totalrp3:%s:%s|h[%s]|h",
        playerID,
        identifier,
        displayName
    )

    local yellow = api.Colors and api.Colors.Yellow
    if yellow and type(yellow.WrapTextInColorCode) == "function" then
        local colorSuccess, coloredLink = pcall(yellow.WrapTextInColorCode, yellow, hyperlink)
        if colorSuccess and type(coloredLink) == "string" then
            return coloredLink
        end
    end
    return hyperlink
end

function addon.TRP3Bridge.ParseTotalRP3ChatHyperlink(link)
    if type(link) ~= "string" then
        return nil
    end

    local sender, identifier = link:match("^addon:totalrp3:([^:|]+):(.+)$")
    if type(sender) ~= "string"
        or sender == ""
        or sender:find("[%c|:]")
        or not isValidChatLinkIdentifier(identifier)
    then
        return nil
    end
    return sender, identifier
end

local function playerIDsMatch(first, second)
    if type(first) ~= "string" or type(second) ~= "string" then
        return false
    end

    local normalizedFirst = string.lower(first)
    local normalizedSecond = string.lower(second)
    if normalizedFirst == normalizedSecond then
        return true
    end

    local firstShort = normalizedFirst:match("^([^-]+)")
    local secondShort = normalizedSecond:match("^([^-]+)")
    return firstShort ~= nil
        and firstShort == secondShort
        and (not normalizedFirst:find("-", 1, true) or not normalizedSecond:find("-", 1, true))
end

function addon.TRP3Bridge.GetOwnSpellChatTooltip(sender, identifier)
    local api = getAPI()
    local playerID = api and api.globals and api.globals.player_id
    if not playerIDsMatch(sender, playerID) then
        return nil
    end

    local sentLink = getSentSpellChatLink(api, identifier)
    if not sentLink then
        return nil
    end
    return getSpellFromSentLink(sentLink)
end

local function isValidHoverRequestID(requestID)
    return type(requestID) == "string"
        and requestID ~= ""
        and #requestID <= addon.Constants.MAX_CHAT_HOVER_REQUEST_ID_LENGTH
        and not requestID:find("[%c|]")
end

local function sendHoverResponse(communications, target, payload)
    if type(target) ~= "string" or target == "" or target:find("[%c|:]") then
        return false
    end

    local success, result = pcall(
        communications.sendObject,
        addon.Constants.CHAT_HOVER_RESPONSE_PREFIX,
        payload,
        target,
        "LOW"
    )
    return success and result ~= false
end

local function allowHoverRequest(sender)
    if type(sender) ~= "string" or sender == "" then
        return false
    end

    local now = type(GetTime) == "function" and GetTime() or (type(time) == "function" and time() or 0)
    local key = string.lower(sender)
    local rate = spellHoverRequestRates:Get(key)
    if not rate or now - rate.startedAt >= addon.Constants.CHAT_HOVER_RATE_WINDOW then
        spellHoverRequestRates:Set(key, {
            startedAt = now,
            count = 1,
        })
        return true
    end

    if rate.count >= addon.Constants.MAX_CHAT_HOVER_REQUESTS_PER_SENDER_WINDOW then
        return false
    end
    rate.count = rate.count + 1
    return true
end

local function handleHoverRequest(communications, request, sender)
    if type(request) ~= "table"
        or request.formatVersion ~= addon.Constants.CHAT_LINK_FORMAT_VERSION
        or not isValidHoverRequestID(request.requestId)
        or not isValidChatLinkIdentifier(request.identifier)
    then
        return
    end
    if not allowHoverRequest(sender) then
        return
    end

    local sentLink, status = getSentSpellChatLink(getAPI(), request.identifier)
    local spell
    if sentLink then
        spell = getSpellFromSentLink(sentLink)
        if not spell then
            status = "missing"
        end
    end

    sendHoverResponse(communications, sender, {
        formatVersion = addon.Constants.CHAT_LINK_FORMAT_VERSION,
        requestId = request.requestId,
        identifier = request.identifier,
        status = status,
        spell = spell,
    })
end

local function handleHoverResponse(response, sender)
    if type(spellHoverResponseCallback) ~= "function" then
        return
    end

    local success, errorMessage = pcall(spellHoverResponseCallback, sender, response)
    if not success then
        addon.Logger.Error(tostring(errorMessage))
    end
end

function addon.TRP3Bridge.InitializeSpellHover(callback)
    if type(callback) ~= "function" then
        return false, addon.L("INVALID_CALLBACK")
    end
    spellHoverResponseCallback = callback

    if spellHoverInitialized then
        return true
    end
    if spellHoverInitializationAttempted then
        return false, spellHoverInitializationError or addon.L("CHAT_HOVER_API_UNAVAILABLE")
    end
    spellHoverInitializationAttempted = true

    local communications = getCommunications()
    if type(communications) ~= "table"
        or type(communications.registerSubSystemPrefix) ~= "function"
        or type(communications.sendObject) ~= "function"
    then
        spellHoverInitializationError = addon.L("CHAT_HOVER_API_UNAVAILABLE")
        return false, spellHoverInitializationError
    end

    local requestSuccess, requestError = pcall(
        communications.registerSubSystemPrefix,
        addon.Constants.CHAT_HOVER_REQUEST_PREFIX,
        function(request, sender)
            handleHoverRequest(communications, request, sender)
        end
    )
    if not requestSuccess then
        spellHoverInitializationError = requestError
        return false, requestError
    end

    local responseSuccess, responseError = pcall(
        communications.registerSubSystemPrefix,
        addon.Constants.CHAT_HOVER_RESPONSE_PREFIX,
        handleHoverResponse
    )
    if not responseSuccess then
        spellHoverInitializationError = responseError
        return false, responseError
    end

    spellHoverInitialized = true
    return true
end

function addon.TRP3Bridge.RequestSpellHover(sender, identifier, requestID)
    if not spellHoverInitialized
        or type(sender) ~= "string"
        or sender == ""
        or sender:find("[%c|:]")
        or not isValidChatLinkIdentifier(identifier)
        or not isValidHoverRequestID(requestID)
    then
        return false, addon.L("CHAT_HOVER_API_UNAVAILABLE")
    end

    local communications = getCommunications()
    if not communications or type(communications.sendObject) ~= "function" then
        return false, addon.L("CHAT_HOVER_API_UNAVAILABLE")
    end

    local success, result = pcall(
        communications.sendObject,
        addon.Constants.CHAT_HOVER_REQUEST_PREFIX,
        {
            formatVersion = addon.Constants.CHAT_LINK_FORMAT_VERSION,
            requestId = requestID,
            identifier = identifier,
        },
        sender,
        "LOW"
    )
    if not success or result == false then
        return false, result
    end
    return true
end
