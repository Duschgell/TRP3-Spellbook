local _, private = ...
local addon = private.Shared or private
local en = {
    ABILITY = "Ability",

    AREA = "Area",

    ASSIGN_ABILITIES = "Assign abilities",
    ASSIGN_FULL = "An NPC can have up to 24 abilities.",

    BACK = "Back",

    BOOK = "NPC spellbook",
    BOOK_COPIED = "Copied into the shared NPC spellbook.",
    BOOK_EMPTY = "No abilities in this tab.",
    BOOK_FULL = "The shared NPC book is full (32 tabs, 1500 abilities).",

    BUSY = "Too many pending spell requests. Retry shortly.",

    CAPTURE = "Capture target",

    CAST = "Cast time (rounds)",

    CHARACTER = "NPC",

    CONFIRM_DELETE = "Delete this archive entry? This cannot be undone.",
    CONFIRM_REVIEW = "Have you checked the NPC assignment and RP fields? The original text won't be copied.",

    COPIED = "Copied into active profile spellbook",

    COPY = "Copy to spellbook",
    COPY_OWN = "From my spellbook",

    CREATE_NPC = "Create NPC",

    DELETE = "Delete ability",

    DELETED = "Deleted",

    DELETE_NPC = "Delete NPC",

    DESCRIPTION = "RP description (no damage or cost values)",

    DISCARD = "Discard unsaved profile changes?",

    DRAFT = "Needs RP review",
    DRAFT_SHORT = "Draft: review in editor",

    EDIT = "Review / edit",
    EDIT_TAB = "Edit tab",

    EMPTY = "No NPCs yet. Create an NPC, or target one in the world and capture it.",

    EVIDENCE = "Source or reason (required)",

    FIELDS = "Resources have no numbers. Add further effects in the spellbook after copying.",

    FRIENDLY = "Friendly",

    FULL = "Archive limit reached (50 entries, 24 abilities each). Delete an entry first.",

    GENERAL = "General",

    HOSTILE = "Hostile",

    ICON = "Icon file ID or path",

    INVALID = "Invalid input or missing entry.",

    KIND = "Type",

    LIMITATION = "Only accessible data is collected. Ability lists may be incomplete; manual associations are unverified.",

    LOADING = "Loading metadata",

    MAGIC = "Magic",

    MANUAL = "Add spell ID",
    MANUAL_ONLY = "Manual association, unverified",

    NAME = "RP name",

    NEED_REVIEW = "Write a description, choose a type and approve the RP draft.",

    NEUTRAL = "Neutral",

    NEXT = "Next",

    NOT_READY = "NPC archive is not initialized or the saved schema is unsupported.",

    NO_ABILITIES = "No abilities assigned.",
    NO_CAST = "No readable cast active. The NPC may still have abilities.",
    NO_SEARCH_RESULTS = "No matches. Change your search.",
    NO_TABS = "Create a spellbook tab first.",

    OBSERVE = "Capture spell",

    OBSERVED = "Observed cast",

    OK = "Saved",

    PREFERENCES_FAILED = "Window size wasn't saved. The change will last only until you reload.",

    PREVIOUS = "Previous",

    PROFILE = "NPC profile",
    PROFILE_DESCRIPTION = "Description",
    PROFILE_NAME = "Name",
    PROFILE_SAVED = "Profile saved",
    PROFILE_TITLE = "Title",

    QUICK_EDIT = "Edit",

    RANGE = "Range (engine yards; review for RP)",

    READY = "Metadata loaded",

    REGISTER = "NPC register",

    RELATIONSHIP = "Relationship",

    RESOURCE = "Resource type",

    RETRY = "Load metadata",

    REVIEW = "Approve RP draft",

    REVIEWED = "RP reviewed",

    REVIEW_HELP = "Check the NPC, type, range, rounds and RP description. Approve it again after making changes.",

    SAVE = "Save draft",
    SAVE_FAILED = "Not saved. Check the fields.",

    SCALE = "Scale %d%%",
    SCALE_HELP = "+/-: scale. Click percentage: reset. Drag corner: resize. Small screens are fitted automatically.",

    SEARCH = "Search",

    SECRET = "The game isn't providing the data needed. Nothing was captured.",

    SOURCE = "Original text (not copied)",
    SOURCE_CHANGED = "Your active spellbook changed. Open the selection again.",

    SPELL_ID = "Spell ID",

    TAB = "Choose destination tab in the current profile",

    TARGET = "Choose an NPC that doesn't belong to a player.",

    TITLE = "NPC register",

    TRACK_ACTIVE = "Recording accessible combat casts; saved after combat.",
    TRACK_BACKGROUND = "Continuous tracking",
    TRACK_BACKGROUND_HELP = "Collect readable casts from your target and nameplates; save after combat. Lists may be incomplete.",
    TRACK_IDLE = "Waiting for combat; observations are saved after combat.",
    TRACK_LIMIT = "Combat collection limit reached; some observations may be missing.",
    TRACK_OFF = "Tracking off",
    TRACK_OFF_HELP = "Stop automatic collection and save collected spells where archive space allows.",
    TRACK_PENDING = "Collected: %d NPCs / %d spells",
    TRACK_RESTRICTED = "WoW hides some spell data. That data is skipped.",
    TRACK_STOPPED = "No automatic collection.",
    TRACK_TARGET = "Target in combat",
    TRACK_TARGET_HELP = "Collect this NPC's readable casts while targeted. Reselect after changing NPCs. Lists may be incomplete.",
    TRACK_TARGET_MISSING = "The current target must match the NPC chosen for tracking.",
    TRACK_UNAVAILABLE = "Combat tracking is unavailable. Manual collection still works.",
    TRACK_WAITING = "Waiting for readable spells in combat.",

    TRANSFER_CONFIRM_MERGE = "Add %d NPCs; replace %d. Conflicting IDs are remapped. Existing NPCs and spells remain unchanged. Import?",
    TRANSFER_CONFIRM_REPLACE = "Add %d NPCs; replace %d matching NPC IDs and their assignments. Unrelated NPCs and existing spells remain. This cannot be undone. Import?",
    TRANSFER_DONE = "NPC transfer imported.",
    TRANSFER_EDITOR = "Save or close the NPC editor before importing.",
    TRANSFER_EXPORT_ALL = "Export all NPCs",
    TRANSFER_EXPORT_ONE = "Export NPC",
    TRANSFER_HELP = "Copy or paste saved NPC profiles, assigned abilities and flags. All-NPC exports include the shared book. This is not a full backup. Descriptions may be private; share with care. Close NPC editors before importing.",
    TRANSFER_IMPORT = "Import NPCs",
    TRANSFER_INVALID = "Invalid, oversized or unsupported NPC transfer data. Nothing was imported.",
    TRANSFER_MERGE = "Merge (keep existing)",
    TRANSFER_REPLACE = "Replace matching NPC IDs",
    TRANSFER_STALE = "The NPC register changed. Check the import again.",
    TRANSFER_TITLE = "NPC transfer",

    UNAVAILABLE = "Metadata unavailable; retry manually",

    UNKNOWN = "Choose a type",

    UNSAVED = "Unsaved changes",

    UNSPECIFIED = "Not specified",

    VARIANTS = "%d observed variants",
    VARIANTS_HELP = "NPC variants with matching observed casts. Lists may be incomplete.",
    VARIANTS_MORE = "%d more variants",
}
local de = {
    ABILITY = "Fähigkeit",

    AREA = "Gebiet",

    ASSIGN_ABILITIES = "Fähigkeiten zuweisen",
    ASSIGN_FULL = "Ein NPC kann bis zu 24 Fähigkeiten haben.",

    BACK = "Zurück",

    BOOK = "NPC-Zauberbuch",
    BOOK_COPIED = "Ins gemeinsame NPC-Zauberbuch kopiert.",
    BOOK_EMPTY = "Keine Fähigkeiten in diesem Reiter.",
    BOOK_FULL = "Das NPC-Zauberbuch ist voll (32 Reiter, 1500 Fähigkeiten).",

    BUSY = "Zu viele offene Zauberabfragen. Versuche es gleich noch einmal.",

    CAPTURE = "Ziel aufnehmen",

    CAST = "Wirkzeit (Runden)",

    CHARACTER = "NPC",

    CONFIRM_DELETE = "Archiveintrag unwiderruflich löschen?",
    CONFIRM_REVIEW = "NPC-Zuordnung und RP-Felder geprüft? Der Originaltext wird nicht übernommen.",

    COPIED = "Ins Zauberbuch des aktiven Profils kopiert",

    COPY = "Ins Zauberbuch",
    COPY_OWN = "Aus meinem Zauberbuch",

    CREATE_NPC = "NPC erstellen",

    DELETE = "Fertigkeit löschen",

    DELETED = "Gelöscht",

    DELETE_NPC = "NPC löschen",

    DESCRIPTION = "RP-Beschreibung (ohne Schadens- und Kostenwerte)",

    DISCARD = "Ungespeicherte Profiländerungen verwerfen?",

    DRAFT = "RP-Prüfung offen",
    DRAFT_SHORT = "Entwurf: im Editor prüfen",

    EDIT = "Prüfen / bearbeiten",
    EDIT_TAB = "Reiter bearbeiten",

    EMPTY = "Noch keine NPCs. Erstelle einen NPC oder wähle einen in der Spielwelt und nimm dein Ziel auf.",

    EVIDENCE = "Quelle oder Begründung (Pflicht)",

    FIELDS = "Ressourcen ohne Zahlen. Weitere Effekte ergänzt du nach der Übernahme im Zauberbuch.",

    FRIENDLY = "Freundlich",

    FULL = "Archiv voll (50 Einträge, je 24 Fertigkeiten). Lösche zuerst einen Eintrag.",

    GENERAL = "Allgemein",

    HOSTILE = "Feindlich",

    ICON = "Icon-Datei-ID oder Pfad",

    INVALID = "Ungültige Eingabe oder fehlender Eintrag.",

    KIND = "Art",

    LIMITATION = "Nur zugängliche Daten werden erfasst. Zauberlisten können unvollständig sein; manuelle Zuordnungen sind ungeprüft.",

    LOADING = "Metadaten laden",

    MAGIC = "Magie",

    MANUAL = "Zauber-ID ergänzen",
    MANUAL_ONLY = "Manuell zugeordnet, ungeprüft",

    NAME = "RP-Name",

    NEED_REVIEW = "Schreibe eine Beschreibung, wähle die Art und gib den RP-Entwurf frei.",

    NEUTRAL = "Neutral",

    NEXT = "Weiter",

    NOT_READY = "NPC-Archiv nicht initialisiert oder unbekannte Speicherversion.",

    NO_ABILITIES = "Noch keine Fähigkeiten zugewiesen.",
    NO_CAST = "Kein lesbarer Zauber aktiv. Der NPC kann trotzdem Fertigkeiten besitzen.",
    NO_SEARCH_RESULTS = "Keine Treffer. Ändere die Suche.",
    NO_TABS = "Erstelle zuerst einen Zauberbuchreiter.",

    OBSERVE = "Zauber erfassen",

    OBSERVED = "Zauber beobachtet",

    OK = "Gespeichert",

    PREFERENCES_FAILED = "Fenstergröße nicht gespeichert. Die Änderung gilt nur bis zum Neuladen.",

    PREVIOUS = "Zurück",

    PROFILE = "NPC-Profil",
    PROFILE_DESCRIPTION = "Beschreibung",
    PROFILE_NAME = "Name",
    PROFILE_SAVED = "Profil gespeichert",
    PROFILE_TITLE = "Titel",

    QUICK_EDIT = "Bearbeiten",

    RANGE = "Reichweite (Engine-Yards; für RP prüfen)",

    READY = "Metadaten geladen",

    REGISTER = "NPC-Register",

    RELATIONSHIP = "Beziehung",

    RESOURCE = "Ressourcenart",

    RETRY = "Metadaten laden",

    REVIEW = "RP freigeben",

    REVIEWED = "RP geprüft",

    REVIEW_HELP = "NPC, Art, Reichweite, Runden und RP-Beschreibung prüfen. Nach Änderungen erneut freigeben.",

    SAVE = "Entwurf speichern",
    SAVE_FAILED = "Nicht gespeichert. Prüfe die Felder.",

    SCALE = "Skala %d%%",
    SCALE_HELP = "+/-: skalieren. Prozentzahl: zurücksetzen. Ecke ziehen: Größe ändern. Kleine Bildschirme werden automatisch angepasst.",

    SEARCH = "Suche",

    SECRET = "Das Spiel gibt die nötigen Daten nicht frei. Nichts wurde erfasst.",

    SOURCE = "Originaltext (wird nicht übernommen)",
    SOURCE_CHANGED = "Dein aktives Zauberbuch hat gewechselt. Öffne die Auswahl erneut.",

    SPELL_ID = "Zauber-ID",

    TAB = "Zielreiter im aktuellen Profil wählen",

    TARGET = "Wähle einen NPC, der keinem Spieler gehört.",

    TITLE = "NPC-Register",

    TRACK_ACTIVE = "Erfasst zugängliche Kampfzauber; Speicherung nach dem Kampf.",
    TRACK_BACKGROUND = "Dauererfassung",
    TRACK_BACKGROUND_HELP = "Lesbare Zauber von Ziel und Namensplaketten sammeln; nach dem Kampf speichern. Die Liste kann unvollständig sein.",
    TRACK_IDLE = "Wartet auf den Kampf; Beobachtungen werden danach gespeichert.",
    TRACK_LIMIT = "Erfassungsgrenze im Kampf erreicht; Beobachtungen können fehlen.",
    TRACK_OFF = "Erfassung aus",
    TRACK_OFF_HELP = "Stoppt die Erfassung und speichert die gesammelten Zauber, soweit Platz ist.",
    TRACK_PENDING = "Gesammelt: %d NPCs / %d Zauber",
    TRACK_RESTRICTED = "WoW verbirgt einige Zauberdaten. Diese werden ausgelassen.",
    TRACK_STOPPED = "Keine automatische Erfassung.",
    TRACK_TARGET = "Ziel im Kampf",
    TRACK_TARGET_HELP = "Lesbare Zauber dieses Ziel-NPCs sammeln. Nach NPC-Wechsel erneut wählen. Die Liste kann unvollständig sein.",
    TRACK_TARGET_MISSING = "Das aktuelle Ziel muss dem für die Erfassung gewählten NPC entsprechen.",
    TRACK_UNAVAILABLE = "Kampferfassung nicht verfügbar. Manuelles Sammeln bleibt möglich.",
    TRACK_WAITING = "Wartet auf lesbare Zauber im Kampf.",

    TRANSFER_CONFIRM_MERGE = "%d NPCs hinzufügen; %d ersetzen. Konflikte erhalten neue IDs. Bestehende NPCs und Zauber bleiben unverändert. Importieren?",
    TRANSFER_CONFIRM_REPLACE = "%d NPCs hinzufügen; %d gleiche NPC-IDs samt Zuweisungen ersetzen. Andere NPCs und bestehende Zauber bleiben erhalten. Nicht rückgängig zu machen. Importieren?",
    TRANSFER_DONE = "NPC-Transfer importiert.",
    TRANSFER_EDITOR = "NPC-Editor vor dem Import speichern oder schließen.",
    TRANSFER_EXPORT_ALL = "Alle NPCs exportieren",
    TRANSFER_EXPORT_ONE = "NPC exportieren",
    TRANSFER_HELP = "Gespeicherte NPC-Profile, zugewiesene Fähigkeiten und Kennzeichen kopieren oder einfügen. Alle NPCs enthalten das gemeinsame Buch. Kein vollständiges Backup. Beschreibungen können privat sein. NPC-Editoren vor dem Import schließen.",
    TRANSFER_IMPORT = "NPCs importieren",
    TRANSFER_INVALID = "Ungültige, zu große oder unbekannte NPC-Transferdaten. Nichts importiert.",
    TRANSFER_MERGE = "Zusammenführen (behalten)",
    TRANSFER_REPLACE = "Gleiche NPC-IDs ersetzen",
    TRANSFER_STALE = "Das NPC-Register wurde geändert. Import erneut prüfen.",
    TRANSFER_TITLE = "NPC-Transfer",

    UNAVAILABLE = "Metadaten fehlen; manuell erneut laden",

    UNKNOWN = "Art wählen",

    UNSAVED = "Ungespeicherte Änderungen",

    UNSPECIFIED = "Keine Angabe",

    VARIANTS = "%d Varianten (beobachtet)",
    VARIANTS_HELP = "NPC-Varianten mit gleichen beobachteten Zaubern. Die Listen können unvollständig sein.",
    VARIANTS_MORE = "%d weitere Varianten",
}
local fr = {
    ABILITY = "Capacité",

    AREA = "Zone",

    ASSIGN_ABILITIES = "Attribuer des capacités",
    ASSIGN_FULL = "Un PNJ peut avoir jusqu'à 24 capacités.",

    BACK = "Retour",

    BOOK = "Grimoire des PNJ",
    BOOK_COPIED = "Copié dans le grimoire partagé des PNJ.",
    BOOK_EMPTY = "Aucune capacité dans cet onglet.",
    BOOK_FULL = "Le grimoire partagé est plein (32 onglets, 1500 capacités).",

    BUSY = "Trop de demandes de sorts en attente. Réessayez dans un instant.",

    CAPTURE = "Collecter la cible",

    CAST = "Incantation (tours)",

    CHARACTER = "PNJ",

    CONFIRM_DELETE = "Supprimer cette entrée ? Cette action est irréversible.",
    CONFIRM_REVIEW = "Avez-vous vérifié l'association au PNJ et les champs RP ? Le texte d'origine n'est pas repris.",

    COPIED = "Copié dans le grimoire du profil actif",

    COPY = "Copier dans le grimoire",
    COPY_OWN = "Depuis mon grimoire",

    CREATE_NPC = "Créer un PNJ",

    DELETE = "Supprimer la capacité",

    DELETED = "Supprimé",

    DELETE_NPC = "Supprimer le PNJ",

    DESCRIPTION = "Description RP (sans valeurs de dégâts ni de coût)",

    DISCARD = "Abandonner les modifications non enregistrées ?",

    DRAFT = "RP à vérifier",
    DRAFT_SHORT = "Brouillon : vérifier dans l'éditeur",

    EDIT = "Vérifier / modifier",
    EDIT_TAB = "Modifier l'onglet",

    EMPTY = "Aucun PNJ pour le moment. Créez un PNJ ou sélectionnez-en un dans le monde et collectez votre cible.",

    EVIDENCE = "Source ou justification (obligatoire)",

    FIELDS = "Ressources sans valeurs numériques. Ajoutez les autres effets dans le grimoire après la copie.",

    FRIENDLY = "Amical",

    FULL = "Limite atteinte (50 entrées, 24 capacités chacune). Supprimez d'abord une entrée.",

    GENERAL = "Général",

    HOSTILE = "Hostile",

    ICON = "ID de fichier ou chemin de l'icône",

    INVALID = "Saisie invalide ou entrée absente.",

    KIND = "Type",

    LIMITATION = "Seules les données accessibles sont collectées. Les listes peuvent être incomplètes ; les associations manuelles ne sont pas vérifiées.",

    LOADING = "Chargement des données",

    MAGIC = "Magie",

    MANUAL = "Ajouter un ID de sort",
    MANUAL_ONLY = "Association manuelle non vérifiée",

    NAME = "Nom RP",

    NEED_REVIEW = "Ajoutez une description, choisissez le type et validez le brouillon RP.",

    NEUTRAL = "Neutre",

    NEXT = "Suivant",

    NOT_READY = "Le registre des PNJ n'est pas initialisé ou son format est incompatible.",

    NO_ABILITIES = "Aucune capacité attribuée pour le moment.",
    NO_CAST = "Aucun sort lisible en cours. Le PNJ peut toutefois avoir des capacités.",
    NO_SEARCH_RESULTS = "Aucun résultat. Modifiez la recherche.",
    NO_TABS = "Créez d'abord un onglet dans le grimoire.",

    OBSERVE = "Observer le sort",

    OBSERVED = "Sort observé",

    OK = "Enregistré",

    PREFERENCES_FAILED = "La taille de la fenêtre n'a pas été sauvée. Ce changement ne dure que jusqu'au rechargement.",

    PREVIOUS = "Précédent",

    PROFILE = "Profil du PNJ",
    PROFILE_DESCRIPTION = "Description",
    PROFILE_NAME = "Nom",
    PROFILE_SAVED = "Profil enregistré",
    PROFILE_TITLE = "Titre",

    QUICK_EDIT = "Modifier",

    RANGE = "Portée (yards du jeu ; à vérifier pour le RP)",

    READY = "Données chargées",

    REGISTER = "Registre des PNJ",

    RELATIONSHIP = "Relation",

    RESOURCE = "Type de ressource",

    RETRY = "Recharger les données",

    REVIEW = "Valider le brouillon RP",

    REVIEWED = "RP validé",

    REVIEW_HELP = "Vérifiez le PNJ, le type, la portée, les tours et la description RP. Toute modification nécessite une nouvelle validation.",

    SAVE = "Sauver le brouillon",
    SAVE_FAILED = "Non enregistré. Vérifiez les champs.",

    SCALE = "Échelle %d%%",
    SCALE_HELP = "+/- : échelle. Pourcentage : réinitialiser. Tirer le coin : redimensionner. Adaptation automatique aux petits écrans.",

    SEARCH = "Rechercher",

    SECRET = "Le jeu ne donne pas accès aux données nécessaires. Rien n'a été collecté.",

    SOURCE = "Texte d'origine (non repris)",
    SOURCE_CHANGED = "Votre grimoire actif a changé. Rouvrez la sélection.",

    SPELL_ID = "ID de sort",

    TAB = "Choisir l'onglet de destination du profil actif",

    TARGET = "Choisissez un PNJ qui n'appartient pas à un joueur.",

    TITLE = "Registre des PNJ",

    TRACK_ACTIVE = "Collecte des sorts de combat accessibles ; enregistrement après le combat.",
    TRACK_BACKGROUND = "Collecte continue",
    TRACK_BACKGROUND_HELP = "Collecte les sorts lisibles de la cible et des barres d'info ; enregistrement après le combat. Listes parfois incomplètes.",
    TRACK_IDLE = "En attente du combat ; observations enregistrées après le combat.",
    TRACK_LIMIT = "Limite de collecte en combat atteinte ; certaines observations peuvent manquer.",
    TRACK_OFF = "Collecte désactivée",
    TRACK_OFF_HELP = "Arrête la collecte et enregistre les sorts si le registre a assez de place.",
    TRACK_PENDING = "Collectés : %d PNJ / %d sorts",
    TRACK_RESTRICTED = "WoW masque certaines données de sorts. Elles ne sont pas collectées.",
    TRACK_STOPPED = "Aucune collecte automatique.",
    TRACK_TARGET = "Combat de la cible",
    TRACK_TARGET_HELP = "Collecte les sorts lisibles de ce PNJ ciblé. Choisissez à nouveau après un changement de PNJ. Listes parfois incomplètes.",
    TRACK_TARGET_MISSING = "La cible doit correspondre au PNJ choisi pour la collecte.",
    TRACK_UNAVAILABLE = "Collecte en combat indisponible. La collecte manuelle reste possible.",
    TRACK_WAITING = "En attente de sorts lisibles en combat.",

    TRANSFER_CONFIRM_MERGE = "Ajouter %d PNJ ; remplacer %d. Les ID en conflit sont réattribués. Les PNJ et sorts existants restent inchangés. Importer ?",
    TRANSFER_CONFIRM_REPLACE = "Ajouter %d PNJ ; remplacer %d ID de PNJ identiques et leurs attributions. Les autres PNJ et sorts restent. Action irréversible. Importer ?",
    TRANSFER_DONE = "Transfert de PNJ importé.",
    TRANSFER_EDITOR = "Sauvez ou fermez l'éditeur de PNJ avant l'importation.",
    TRANSFER_EXPORT_ALL = "Exporter tous les PNJ",
    TRANSFER_EXPORT_ONE = "Exporter le PNJ",
    TRANSFER_HELP = "Copiez ou collez les profils enregistrés, capacités attribuées et indicateurs. Tous les PNJ incluent le grimoire partagé. Pas une sauvegarde complète. Les descriptions peuvent être privées. Fermez les éditeurs de PNJ avant l'import.",
    TRANSFER_IMPORT = "Importer des PNJ",
    TRANSFER_INVALID = "Données de transfert invalides, trop volumineuses ou incompatibles. Aucun import.",
    TRANSFER_MERGE = "Fusionner (conserver)",
    TRANSFER_REPLACE = "Remplacer les ID de PNJ identiques",
    TRANSFER_STALE = "Le registre des PNJ a changé. Vérifiez à nouveau l'import.",
    TRANSFER_TITLE = "Transfert de PNJ",

    UNAVAILABLE = "Données indisponibles ; réessayez manuellement",

    UNKNOWN = "Choisir un type",

    UNSAVED = "Modifications non enregistrées",

    UNSPECIFIED = "Non précisé",

    VARIANTS = "%d variantes observées",
    VARIANTS_HELP = "Variantes de PNJ avec les mêmes sorts observés. Les listes peuvent être incomplètes.",
    VARIANTS_MORE = "%d autres variantes",
}
local translations = { enUS = en, deDE = de, frFR = fr }
function addon.NPCArchive.L(key)
    local locale = type(GetLocale) == "function" and GetLocale() or "enUS"
    local selected = translations[locale]
    return (selected and selected[key]) or en[key] or key
end
