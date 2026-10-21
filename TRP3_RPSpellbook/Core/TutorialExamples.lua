local _, addon = ...
local examples = {
    WARRIOR = { "ability", nil, "Ability_Warrior_HeroicStrike" },
    PALADIN = { "magic", "light", "Spell_Holy_HolyBolt" },
    HUNTER = { "ability", nil, "Ability_Marksmanship" },
    ROGUE = { "ability", nil, "Spell_Shadow_RitualOfSacrifice" },
    PRIEST = { "magic", "light", "Spell_Holy_FlashHeal" },
    DEATHKNIGHT = { "magic", "necromancy", "Spell_DeathKnight_IceTouch" },
    SHAMAN = { "magic", "elemental", "Spell_Nature_Lightning" },
    MAGE = { "magic", "arcane", "Spell_Fire_FlameBolt" },
    WARLOCK = { "magic", "demonic", "Spell_Shadow_ShadowBolt" },
    MONK = { "magic", "chi", "Ability_Monk_TigerPalm" },
    DRUID = { "magic", "nature", "Spell_Nature_Rejuvenation" },
    DEMONHUNTER = { "magic", "demonic", "Ability_DemonHunter_FelRush" },
    EVOKER = { "magic", "elemental", "Ability_Evoker_LivingFlame" },
    DEFAULT = { "magic", "arcane", "Spell_Fire_FlameBolt" },
}

local practice = {
    spark = { "arcane", "Spell_Fire_FlameBolt" },
    shield = { "light", "Spell_Holy_PowerWordShield" },
    ritual = { "arcane", "Spell_Frost_FrostBolt02" },
    heal = { "nature", "Spell_Nature_HealingTouch" },
    hamper = { "arcane", "Spell_Nature_Slow" },
}

addon.TutorialExamples = {}
function addon.TutorialExamples.ForPractice(id)
    local example = practice[id]
    if not example then return nil end
    local constants = addon.Constants
    local spell = {
        name = addon.L("TUTORIAL_SPELL_" .. id:upper()),
        description = id == "hamper" and "" or addon.L("TUTORIAL_PRACTICE_" .. id:upper()),
        icon = "Interface\\Icons\\" .. example[2],
        tags = { [constants.SPELL_TAG_KIND] = "magic",
            [constants.MAGIC_TAG_TYPE] = addon.L("PRESET_MAGIC_" .. example[1]:upper()) },
    }
    if id == "shield" then spell.effects = { buff = true, duration = "2", durationRounds = 2 } end
    if id == "heal" then spell.effects = { healing = true } end
    if id == "hamper" then spell.effects = { debuff = true, duration = "5", durationRounds = 5 } end
    if id == "ritual" then
        spell.castTime = "1"
        spell.tags[constants.SPELL_TAG_CAST_ROUNDS] = "1"
    end
    return spell
end

function addon.TutorialExamples.ForPlayer()
    local token
    if type(UnitClass) == "function" then
        local ok, _, class = pcall(UnitClass, "player")
        if ok and type(class) == "string" and examples[class] then token = class end
    end
    token = token or "DEFAULT"
    local example, constants = examples[token], addon.Constants
    local tags = { [constants.SPELL_TAG_KIND] = example[1] }
    if example[2] then tags[constants.MAGIC_TAG_TYPE] = addon.L("PRESET_MAGIC_" .. example[2]:upper()) end
     
    return { name = addon.L("TUTORIAL_EXAMPLE_" .. token),
        description = "",
        icon = "Interface\\Icons\\" .. example[3], tags = tags }
end
