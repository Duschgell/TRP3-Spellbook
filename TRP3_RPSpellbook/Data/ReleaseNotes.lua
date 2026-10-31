local _, addon = ...

addon.ReleaseNotes = {}
local releases = {
    ["1.2.0"] = {
        enUS = "- (optional) seasonal decorations to give your spellbook a little more flair\n"
            .. "- You can now move and anchor your buffs and debuffs wherever you want\n"
            .. "- The settings menu was very cluttered, so there are now submenus to make it easier to find your way around\n"
            .. "- You can now adjust some text and all spellbook buttons a little with sliders\n"
            .. "- You can now choose Spellbook's language independently of your client language\n"
            .. "- When you share your spells/abilities, their preset fields are now translated automatically\n"
            .. "- You can now flip through your spellbook with the mouse wheel\n"
            .. "- Spell/ability icons are now displayed correctly when hovering over chat links\n"
            .. "- Future versions will now have changelogs you can read in game. You can view the current one at any time by clicking the version in the settings\n"
            .. "- Prat 3.0 is now supported, as there were some issues with it\n"
            .. "- There was a scrollbar bug with long spell/ability descriptions. It's now fixed",
        deDE = "- (optionale) saisonale Dekorationen für dein Zauberbuch für mehr Flair \n"
            .. "- Ihr könnt nun eure Buffs und Debuffs verschieben und verankern wohin ihr wollt \n"
            .. "- Das Einstellungsmenü war sehr unübersichtlich, daher gibt es jetzt Submenüs um die Navigation und Übersicht zu erleichtern \n"
            .. "- Manche Schriftzüge und alle Knöpfe im Zauberbuch lassen sich nun mittels Regler etwas anpassen \n"
            .. "- Spellbooksprache ist jetzt unabhängig der Clientsprache auswählbar \n"
            .. "- Beim Teilen eurer Zaubersprüche/Fähigkeiten werden jetzt die vordefinierten Felder automatisch übersetzt \n"
            .. "- Man kann jetzt durch Mausscrollen durch sein Zauberbuch blättern \n"
            .. "- Zauberspruch/Fähigkeitsicons werden nun korrekt abgebildet beim Mousehovern über Chatlinks \n"
            .. "- Für zukünftige Versionen wird es nun Ingame einsehbare Changelogs geben, die aktuellen könnt ihr jederzeit in den Einstellungen beim anklicken euer aktuellen Version einsehen\n"
            .. "- Prat 3.0 wird nun unterstützt, da es zu Fehlern mit diesem Addon kam \n"
            .. "- Es gab einen Fehler mit der Scrollleiste bei langen Zauber/Fähigkeitsbeschreibungen, dieser ist jetzt behoben",
        frFR = "- Des décorations saisonnières (facultatives) pour donner un peu plus d'ambiance à votre grimoire\n"
            .. "- Vous pouvez maintenant déplacer et ancrer vos buffs et debuffs où vous voulez\n"
            .. "- Le menu des paramètres était trop chargé, il y a donc maintenant des sous-menus pour mieux s'y retrouver\n"
            .. "- Des curseurs permettent maintenant d'ajuster un peu certains textes et tous les boutons du grimoire\n"
            .. "- La langue du grimoire se choisit maintenant indépendamment de celle du client\n"
            .. "- Les champs prédéfinis sont maintenant traduits automatiquement quand vous partagez vos sorts/capacités\n"
            .. "- Vous pouvez maintenant feuilleter votre grimoire avec la molette de la souris\n"
            .. "- Les icônes des sorts/capacités s'affichent maintenant correctement au survol des liens de discussion\n"
            .. "- Les prochaines versions auront des notes de version consultables en jeu. Vous pouvez consulter les notes actuelles à tout moment en cliquant sur la version dans les paramètres\n"
            .. "- Prat 3.0 est maintenant pris en charge, car il causait des erreurs\n"
            .. "- La barre de défilement posait problème dans les longues descriptions de sorts/capacités, c'est maintenant corrigé",
    },
}
local locales = { enUS = true, deDE = true, frFR = true }
local limits = addon.Constants

local function validText(text)
    if type(text) ~= "string" or #text == 0 or #text > limits.VERSION_CHECK_MAX_NOTE_BYTES
        or not text:find("%S") or text:find("[|%z\1-\9\11-\31\127]") then return false end
    local index, lineStart, lines = 1, 1, 1
    while index <= #text do
        local first = text:byte(index)
        local length, code, minimum = 1, first, 0
        if first >= 194 and first <= 223 then length, code, minimum = 2, first - 192, 128
        elseif first >= 224 and first <= 239 then length, code, minimum = 3, first - 224, 2048
        elseif first >= 240 and first <= 244 then length, code, minimum = 4, first - 240, 65536
        elseif first >= 128 then return false end
        for offset = 1, length - 1 do
            local byte = text:byte(index + offset)
            if not byte or byte < 128 or byte > 191 then return false end
            code = code * 64 + byte - 128
        end
        if code < minimum or code > 1114111 or code >= 55296 and code <= 57343
            or code >= 128 and code <= 159 or code == 173 or code == 847 or code == 1564
            or code == 6158 or code >= 8203 and code <= 8207
            or code >= 8232 and code <= 8238 or code >= 8288 and code <= 8303
            or code == 65279 or code >= 65529 and code <= 65531
            or code >= 64976 and code <= 65007 or code % 65536 >= 65534 then return false end
        if code == 10 then
            if index - lineStart > limits.VERSION_CHECK_MAX_NOTE_LINE_BYTES then return false end
            lines, lineStart = lines + 1, index + 1
            if lines > limits.VERSION_CHECK_MAX_NOTE_LINES then return false end
        end
        index = index + length
    end
    return #text - lineStart + 1 <= limits.VERSION_CHECK_MAX_NOTE_LINE_BYTES
end

function addon.ReleaseNotes.Copy(value)
    if type(value) ~= "table" or getmetatable(value) ~= nil then return nil end
    local result, count, bytes = {}, 0, 0
    for locale, text in pairs(value) do
        if not locales[locale] or not validText(text) then return nil end
        bytes = bytes + #text
        if bytes > limits.VERSION_CHECK_MAX_NOTES_BYTES then return nil end
        result[locale], count = text, count + 1
    end
    return count > 0 and result or nil
end

function addon.ReleaseNotes.Key(value)
    local notes = addon.ReleaseNotes.Copy(value)
    if notes then return table.concat({ notes.enUS or "", notes.deDE or "", notes.frFR or "" }, "\0") end
end

function addon.ReleaseNotes.Same(left, right)
    for locale in pairs(locales) do
        if (left and left[locale]) ~= (right and right[locale]) then return false end
    end
    return true
end

function addon.ReleaseNotes.Get(version)
    return addon.ReleaseNotes.Copy(releases[version])
end

function addon.ReleaseNotes.GetVersions()
    local versions = {}
    for version in pairs(releases) do versions[#versions + 1] = version end
    return versions
end

function addon.ReleaseNotes.GetCurrent()
    return addon.ReleaseNotes.Get(addon.Constants.ADDON_VERSION)
end

function addon.ReleaseNotes.GetText(notes)
    notes = addon.ReleaseNotes.Copy(notes)
    return notes and (notes[addon.Localization.GetLocale()] or notes.enUS) or nil
end
