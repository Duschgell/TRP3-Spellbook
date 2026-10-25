local _, addon = ...

local constants = addon.Constants

constants.COMMUNICATION_PROTOCOL_VERSION = 1
constants.COMMUNICATION_OBJECT_PREFIX = "RPSB_P1"
constants.COMMUNICATION_BROADCAST_COMMAND = "RPSBHI1"
constants.COMMUNICATION_PRESENCE_COMMAND = "RPSBHI2"
constants.COMMUNICATION_MESSAGE_ID_LENGTH = 64
constants.COMMUNICATION_MESSAGE_TYPE_LENGTH = 40
constants.COMMUNICATION_MAX_PAYLOAD_DEPTH = 8
constants.COMMUNICATION_MAX_PAYLOAD_ENTRIES = 2048
constants.COMMUNICATION_MAX_PAYLOAD_STRING_LENGTH = 4096
constants.COMMUNICATION_MAX_PAYLOAD_BYTES = 65536
constants.COMMUNICATION_MAX_CAPABILITIES = 17
constants.COMMUNICATION_MAX_CAPABILITY_LENGTH = 40
constants.COMMUNICATION_MAX_PEERS = 256
constants.COMMUNICATION_MAX_SEEN_MESSAGES = 1024
constants.COMMUNICATION_PEER_TTL = 1800
constants.COMMUNICATION_RATE_WINDOW = 5
constants.COMMUNICATION_MAX_MESSAGES_PER_WINDOW = 40
constants.COMMUNICATION_MAX_CHUNK_MESSAGES_PER_WINDOW = 96
constants.COMMUNICATION_ANNOUNCE_DELAY = 20
constants.COMMUNICATION_ANNOUNCE_COOLDOWN = 30
constants.COMMUNICATION_QUERY_COOLDOWN = 10
constants.VERSION_CHECK_REQUIRED_REPORTS = 2
constants.VERSION_CHECK_LOGIN_DELAY = 25
constants.VERSION_CHECK_HISTORY_LIMIT = 8
constants.VERSION_CHECK_MAX_VERSION_BYTES = 24
constants.VERSION_CHECK_MAX_NOTE_BYTES = 1200
constants.VERSION_CHECK_MAX_NOTES_BYTES = 3600
constants.VERSION_CHECK_MAX_NOTE_LINES = 12
constants.VERSION_CHECK_MAX_NOTE_LINE_BYTES = 400
constants.GAMEMASTER_SUBMISSION_PENDING_TIMEOUT = 10
 
constants.GAMEMASTER_ORIGIN_OUTBOX_LIMIT = 5
constants.PLAYER_TOOLTIP_QUERY_COOLDOWN = 15
constants.PLAYER_TOOLTIP_VERSION_MAX_LENGTH = 40
constants.COMMUNICATION_CAPABILITIES = {
    "hidden-effects-v1",
    "timed-effects-v1",
    "aura-display-v1",
    "gamemaster-companions-v1",
    "gamemaster-permanent-v1",
    "gamemaster-debuff-v1",
    "gamemaster-incoming-v1",
    "gamemaster-npc-v1",
    "gamemaster-phases-v1",
    "gamemaster-delegation-v1",
    "gamemaster-origin-queue-v2",
    "gamemaster-turns-v2",
    "gamemaster-visibility-v2",
    "peer-handshake-v1",
    "spell-hover-v1",
    "gamemaster-v1",
    "companion-discovery-v1",
}
constants.COMMUNICATION_HOVER_CAPABILITY = "spell-hover-v1"
constants.COMMUNICATION_HOVER_REQUEST_TYPE = "spell_hover_request"
constants.COMMUNICATION_HOVER_RESPONSE_TYPE = "spell_hover_response"

constants.GAMEMASTER_CAPABILITY = "gamemaster-v1"
constants.GAMEMASTER_COMPANION_DISCOVERY_CAPABILITY = "companion-discovery-v1"
constants.GAMEMASTER_DEBUFF_CAPABILITY = "gamemaster-debuff-v1"
constants.GAMEMASTER_PERMANENT_CAPABILITY = "gamemaster-permanent-v1"
constants.GAMEMASTER_INCOMING_CAPABILITY = "gamemaster-incoming-v1"
constants.GAMEMASTER_DELEGATION_CAPABILITY = "gamemaster-delegation-v1"
constants.GAMEMASTER_ORIGIN_QUEUE_CAPABILITY = "gamemaster-origin-queue-v2"
constants.GAMEMASTER_TURN_CAPABILITY = "gamemaster-turns-v2"
constants.GAMEMASTER_SEGMENTED_VISIBILITY_CAPABILITY = "gamemaster-visibility-v2"
constants.GAMEMASTER_MESSAGE_SESSION = "gm_session"
constants.GAMEMASTER_MESSAGE_ROUND = "gm_round"
constants.GAMEMASTER_MESSAGE_LOCK = "gm_lock"
constants.GAMEMASTER_MESSAGE_STOP = "gm_stop"
constants.GAMEMASTER_MESSAGE_SUBMIT = "gm_submit"
constants.GAMEMASTER_MESSAGE_ACK = "gm_ack"
constants.GAMEMASTER_MESSAGE_SYNC_REQUEST = "gm_sync_request"
constants.GAMEMASTER_MESSAGE_PREPARATION_INTERRUPT = "gm_prep_interrupt"
constants.GAMEMASTER_MESSAGE_PREPARATION_CANCEL = "gm_prep_cancel"
constants.GAMEMASTER_MESSAGE_VISIBILITY = "gm_visibility"
constants.GAMEMASTER_MESSAGE_VISIBILITY_CHUNK = "gm_visibility_chunk"
constants.GAMEMASTER_MESSAGE_TURN_COMPLETE = "gm_turn_complete"
constants.GAMEMASTER_MESSAGE_ASSISTANT_STATE = "gm_assistant_state"
constants.GAMEMASTER_MAX_ACTIVE_BUFFS_PER_PLAYER = 12
constants.GAMEMASTER_EFFECT_WHISPER_BUDGET = 20
constants.GAMEMASTER_EFFECT_WHISPER_COOLDOWN = 2
constants.GAMEMASTER_MESSAGE_ASSISTANT_COMMAND = "gm_assistant_command"
constants.GAMEMASTER_MAX_SESSION_ID_LENGTH = 96
constants.GAMEMASTER_MAX_SESSION_NAME_LENGTH = 80
constants.GAMEMASTER_MAX_TARGET_LENGTH = 120
constants.GAMEMASTER_MAX_RP_NAME_LENGTH = 120
constants.GAMEMASTER_MAX_TARGETS = 20
constants.GAMEMASTER_MAX_ACTIONS_PER_PLAYER = 5
constants.GAMEMASTER_MAX_PARTICIPANTS = 40
constants.GAMEMASTER_MAX_VISIBLE_ACTORS = 60
constants.GAMEMASTER_MAX_INCOMING_ACTIONS = 600
constants.GAMEMASTER_MAX_INCOMING_ID_LENGTH = 384
constants.GAMEMASTER_MAX_VISIBILITY_CHUNKS = 64
constants.GAMEMASTER_VISIBILITY_TRANSFER_TTL = 15
constants.GAMEMASTER_MAX_ASSISTANTS = 5
constants.GAMEMASTER_MAX_VISIBILITY_OVERRIDES = 5
constants.GAMEMASTER_MAX_EMOTE_LENGTH = 400
constants.GAMEMASTER_MAX_HISTORY = 100
constants.GAMEMASTER_DEFAULT_HISTORY = 20
constants.GAMEMASTER_COMPATIBILITY_DELAY = 3
constants.GAMEMASTER_CHAT_BURST_SECONDS = 5
constants.GAMEMASTER_TURN_RETRY_SECONDS = 5
constants.GAMEMASTER_TURN_RETRY_ATTEMPTS = 2
constants.GAMEMASTER_TURN_HINT_SECONDS = 5
constants.GAMEMASTER_ACTIONS = {
    prepare = true,
    cast = true,
    channel = true,
}
constants.GAMEMASTER_TARGET_TYPES = {
    npc = true,
    player = true,
    text = true,
    marker = true,
}
constants.GAMEMASTER_SETTINGS_PAGE_ID = "trp3_rpspellbook"
constants.GAMEMASTER_VISIBILITY_MODES = {
    full = true,
    targets = true,
    hidden = true,
}
constants.GAMEMASTER_SETTING_OPACITY = "TRP3_RPSpellbook_GMOpacity"
constants.GAMEMASTER_SETTING_FONT_SIZE = "TRP3_RPSpellbook_GMFontSize"
constants.GAMEMASTER_SETTING_HISTORY = "TRP3_RPSpellbook_GMHistory"
constants.GAMEMASTER_SETTING_STYLE = "TRP3_RPSpellbook_GMStyle"
constants.GAMEMASTER_SETTING_CONFIRM_CLOSE = "TRP3_RPSpellbook_GMConfirmClose"
constants.GAMEMASTER_SETTING_NAME_MODE = "TRP3_RPSpellbook_GMNameMode"
constants.GAMEMASTER_SETTING_PROFILE_COLORS = "TRP3_RPSpellbook_GMProfileColors"
constants.GAMEMASTER_SETTING_PROFILE_ICONS = "TRP3_RPSpellbook_GMProfileIcons"
constants.GAMEMASTER_SETTING_COMPACT_OPACITY = "TRP3_RPSpellbook_GMCompactOpacity"
constants.GAMEMASTER_SETTING_COMPACT_FONT_SIZE = "TRP3_RPSpellbook_GMCompactFontSize"
constants.GAMEMASTER_SETTING_COMPACT_STYLE = "TRP3_RPSpellbook_GMCompactStyle"
constants.GAMEMASTER_SETTING_FEEDBACK_CHAT = "TRP3_RPSpellbook_GMFeedbackChat"
constants.GAMEMASTER_SETTING_FEEDBACK_SCREEN = "TRP3_RPSpellbook_GMFeedbackScreen"
constants.GAMEMASTER_SETTING_FEEDBACK_SOUND = "TRP3_RPSpellbook_GMFeedbackSound"
constants.SPELL_CREATION_SETTING_TIME_MODE = "TRP3_RPSpellbook_CreationTimeMode"
constants.SPELL_CREATION_SETTING_EDITOR_THEME = "TRP3_RPSpellbook_CreationEditorTheme"
constants.SPELLBOOK_SETTING_PRESENTATION = "TRP3_RPSpellbook_BookPresentation"
constants.CHAT_FALLBACK_SETTING_AUTO_SPELL = "TRP3_RPSpellbook_AutoSpellFallback"
constants.GAMEMASTER_SETTING_CHAT_FALLBACK = "TRP3_RPSpellbook_GMChatFallback"
constants.GAMEMASTER_SETTING_DEFAULT_VISIBILITY = "TRP3_RPSpellbook_GMDefaultVisibility"
constants.SPELL_CREATION_SETTING_MAGIC_SUBTYPES = "TRP3_RPSpellbook_CreationMagicSubtypes"
