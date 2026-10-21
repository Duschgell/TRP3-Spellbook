local _, addon = ...

addon.GameMasterPreparation = {}

local advancing = false

local function getContext()
    return addon.GameMasterService.GetSubmissionContext()
end

local function getOwnedSpell(spellID)
    if addon.GameMasterService.IsTutorialActive and addon.GameMasterService.IsTutorialActive() then
        local book = addon.GameMasterService.GetActionSpellbook()
        return book and book.spells[spellID]
    end
    local spellbook = addon.Database.GetActiveSpellbook()
    return type(spellbook) == "table"
        and type(spellbook.spells) == "table"
        and spellbook.spells[spellID]
        or nil
end

local function clear(message)
    addon.GameMasterPlayerState.ClearPreparation()
    if message then
        addon.GameMasterService.NotifyPlayer(message)
    end
    if addon.GameMasterActionStatus then
        addon.GameMasterActionStatus.Refresh()
    end
end

function addon.GameMasterPreparation.OnAccepted(submission, sessionID, roundNumber)
    if type(submission) ~= "table" then return end
    local current = addon.GameMasterPlayerState.GetPreparation()
    if submission.action == "prepare"
        and type(submission.preparation) == "table"
    then
        local required = tonumber(submission.preparation.required)
        if not required or required < 1 then return end
        if submission.preparation.automated ~= true then
            if current and current.sessionID == sessionID then
                clear()
            end
            return
        end
        local suppliedProgress = tonumber(submission.preparation.progress)
        local continues = current
            and current.sessionID == sessionID
            and current.spellID == submission.spell.id
            and current.required == required
            and current.progress < required
            and (current.lastSubmittedRound == roundNumber
                or current.lastSubmittedRound == roundNumber - 1)
        if not current
            or not continues
        then
            current = {
                progress = 1,
                required = required,
                sessionID = sessionID,
                spellID = submission.spell.id,
                startedRound = roundNumber,
                status = "preparing",
            }
        elseif current.lastSubmittedRound ~= roundNumber then
            current.progress = math.min(required, current.progress + 1)
        end
        if suppliedProgress
            and suppliedProgress >= 1
            and suppliedProgress <= required
        then
            current.progress = math.floor(suppliedProgress)
        end
        current.status = current.progress >= required
            and "waiting"
            or "preparing"
        current.lastSubmittedRound = roundNumber
        current.readyPromptedRound = nil
        addon.GameMasterPlayerState.SetPreparation(current)
    elseif current and submission.action ~= "prepare" then
        clear()
    end
end

function addon.GameMasterPreparation.OnRejected()
    advancing = false
end

function addon.GameMasterPreparation.Interrupted(reason)
    local current = addon.GameMasterPlayerState.GetPreparation()
    local spell = current and getOwnedSpell(current.spellID)
    clear(reason or addon.L(
        "GAMEMASTER_PREPARATION_INTERRUPTED",
        spell and spell.name or addon.L("UNKNOWN_ABILITY")
    ))
end

function addon.GameMasterPreparation.Cancel()
    local current = addon.GameMasterPlayerState.GetPreparation()
    if not current then return false end
    local cancelled, errorMessage =
        addon.GameMasterService.CancelOwnPreparation()
    if not cancelled then
        addon.Logger.Error(
            errorMessage or addon.L("GAMEMASTER_SUBMISSION_REJECTED")
        )
        return false
    end
    clear(addon.L("GAMEMASTER_PREPARATION_CANCELLED"))
    return true
end

function addon.GameMasterPreparation.Reconcile(authoritative, sessionID)
    local current = addon.GameMasterPlayerState.GetPreparation()
    if authoritative == false then
        if current and current.sessionID == sessionID then
            addon.GameMasterPreparation.Interrupted()
        end
        return
    end
    if type(authoritative) ~= "table" then return end
    if authoritative.automated ~= true then
        if current and current.sessionID == sessionID then clear() end
        return
    end
    local required = tonumber(authoritative.required)
    local progress = tonumber(authoritative.progress)
    local startedRound = tonumber(authoritative.startedRound)
    local lastPreparedRound = tonumber(authoritative.lastPreparedRound)
    local spellID = authoritative.spellID
    if not required or required < 1 or required > 100
        or required ~= math.floor(required)
        or not progress or progress < 0 or progress > required
        or progress ~= math.floor(progress)
        or not startedRound or startedRound < 1
        or startedRound ~= math.floor(startedRound)
        or not lastPreparedRound or lastPreparedRound < startedRound
        or lastPreparedRound ~= math.floor(lastPreparedRound)
        or type(spellID) ~= "string"
        or not getOwnedSpell(spellID)
    then
        if current and current.sessionID == sessionID then
            clear()
        end
        return
    end
    addon.GameMasterPlayerState.SetPreparation({
        lastSubmittedRound = math.floor(lastPreparedRound),
        progress = math.min(required, math.floor(progress)),
        readyPromptedRound = current
            and current.sessionID == sessionID
            and current.spellID == spellID
            and current.readyPromptedRound
            or nil,
        required = math.floor(required),
        sessionID = sessionID,
        spellID = spellID,
        startedRound = math.floor(startedRound),
        status = progress >= required and "waiting" or "preparing",
    })
end

local function advance()
    if advancing then return end
    if addon.GameMasterService.GetPhase and addon.GameMasterService.GetPhase() == "enemies" then return end
    local preparation = addon.GameMasterPlayerState.GetPreparation()
    local context = getContext()
    if not preparation or not context
        or preparation.sessionID ~= context.sessionID
    then
        return
    end
    if context.pendingSubmission ~= nil
        or preparation.lastSubmittedRound == context.roundNumber
    then return end
    if preparation.progress < preparation.required then
        local spell = getOwnedSpell(preparation.spellID)
        if not spell then
            clear(addon.L("ABILITY_NOT_FOUND"))
            return
        end
        advancing = true
        local sent, errorMessage = addon.GameMasterService.Submit(
            spell,
            "prepare",
            nil,
            { automatedPreparation = true }
        )
        advancing = false
        if not sent then
            addon.Logger.Error(errorMessage or addon.L("GAMEMASTER_SUBMISSION_REJECTED"))
        end
        return
    end

    if preparation.readyPromptedRound == context.roundNumber then return end
    preparation.progress = preparation.required
    preparation.status = "ready"
    preparation.readyPromptedRound = context.roundNumber
    addon.GameMasterPlayerState.SetPreparation(preparation)
    local spell = getOwnedSpell(preparation.spellID)
    if spell and addon.GameMasterActionDialog then
        addon.GameMasterService.NotifyPlayer(addon.L(
            "GAMEMASTER_PREPARATION_READY",
            spell.name or addon.L("UNKNOWN_ABILITY")
        ))
        addon.GameMasterActionDialog.Open(spell, {
            forcedAction = "cast",
            preparationReady = true,
        })
    end
    if addon.GameMasterActionStatus then addon.GameMasterActionStatus.Open() end
end

local function onServiceChanged(reason)
    if reason == "round" or reason == "remote" then
        advance()
    elseif reason == "stopped" then
        clear()
    end
end

addon.GameMasterService.RegisterListener(onServiceChanged)
