local _, addon = ...

_G.BINDING_HEADER_TRP3RPSPELLBOOK = addon.L("KEYBINDING_HEADER")
_G.BINDING_NAME_TRP3RPSPELLBOOK_OPEN = addon.L("KEYBINDING_OPEN_SPELLBOOK")
_G.BINDING_NAME_TRP3RPSPELLBOOK_COMPACT = addon.L(
    "KEYBINDING_TOGGLE_COMBAT_BOOK"
)

function _G.TRP3_RPSpellbook_OpenBinding()
    if addon.Core and addon.Core.OpenSpellbook then
        addon.Core.OpenSpellbook()
    end
end

function _G.TRP3_RPSpellbook_CompactBinding()
    if addon.GameMasterCompactSpellbook
        and addon.GameMasterCompactSpellbook.Toggle
    then
        addon.GameMasterCompactSpellbook.Toggle()
    end
end
