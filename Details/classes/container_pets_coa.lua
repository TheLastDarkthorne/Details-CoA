--Conquest of Azeroth: owners for summons spawned by server scripts.
--
--Many CoA class summons (Tinker devices, turrets and bombs, Cultist old god tentacles, and others)
--are spawned by core scripts with SummonCreature + SetOwnerGUID instead of a spell summon effect,
--so the combat log never fires SPELL_SUMMON for them and the client gives them no owner tooltip
--line. Details then can't link them to their owner and their damage gets lost.
--
--The client still marks these units in the combat log flags: AFFILIATION_MINE when the player owns
--them, AFFILIATION_PARTY or AFFILIATION_RAID when a group member does. This file uses that:
--  * a unit flagged MINE that isn't the player belongs to the player;
--  * the owning client tells the group which units are its own (addon message), so group members
--    running this version credit the right owner too.

local Details = _G.Details
local addonName, Details222 = ...

local bitBand = bit.band
local UnitGUID = _G.UnitGUID
local UnitName = _G.UnitName
local IsInRaid = _G.IsInRaid
local IsInGroup = _G.IsInGroup
local GetNumRaidMembers = _G.GetNumRaidMembers
local GetNumPartyMembers = _G.GetNumPartyMembers
local SendAddonMessage = _G.SendAddonMessage
local GUIDIsPlayer = _G.GUIDIsPlayer
local strsub = string.sub
local gmatch = string.gmatch
local pairs = pairs
local wipe = table.wipe

local AFFILIATION_MINE = 0x00000001
local AFFILIATION_GROUP = 0x00000007
local OBJECT_TYPE_PLAYER = 0x00000400
local OWNER_FLAGS = 0x514 --same flags the pet container uses for group owners

local COMM_PREFIX = "DetailsCoAPet"
local MAX_MESSAGE_LENGTH = 240
local ANNOUNCE_DELAY = 0.5
local MAX_UNRESOLVED = 50

local petContainer = Details222.PetContainer

local CoAPets = {
	---pet guid -> owner name, learned from the owner's addon message
	---@type table<guid, actorname>
	SharedOwners = {},
	---own pet guids waiting to be announced to the group
	---@type guid[]
	Outgoing = {},
	---own pet guids already announced
	---@type table<guid, boolean>
	Announced = {},
	---group-owned units whose owner couldn't be found, for /details coapets
	---@type table<guid, {name: string, flags: number}>
	Unresolved = {},
	UnresolvedCount = 0,
	bAnnounceScheduled = false,
}
Details222.CoAPets = CoAPets

local isPlayerGuid = function(guid)
	if (GUIDIsPlayer) then
		return GUIDIsPlayer(guid)
	end
	--3.3.5 guid: 0x0000... for players
	return strsub(guid, 3, 6) == "0000"
end

---true when the combat log flags say a group member (or the player) owns this non-player unit
---@param guid guid
---@param flags number
---@return boolean
function CoAPets.IsGroupOwnedUnit(guid, flags)
	if (not guid or guid == "" or not flags) then
		return false
	end
	if (bitBand(flags, OBJECT_TYPE_PLAYER) ~= 0 or bitBand(flags, AFFILIATION_GROUP) == 0) then
		return false
	end
	return not isPlayerGuid(guid)
end

---find the unit id of a group member by name
---@param name string
---@return string?
local findGroupUnit = function(name)
	if (UnitName("player") == name) then
		return "player"
	end
	if (IsInRaid()) then
		for i = 1, GetNumRaidMembers() do
			local unitId = "raid" .. i
			if (UnitName(unitId) == name) then
				return unitId
			end
		end
	else
		for i = 1, GetNumPartyMembers() do
			local unitId = "party" .. i
			if (UnitName(unitId) == name) then
				return unitId
			end
		end
	end
end

local getGroupChannel = function()
	if (IsInRaid()) then
		return "RAID"
	elseif (IsInGroup()) then
		return "PARTY"
	end
end

local flushAnnouncements = function()
	CoAPets.bAnnounceScheduled = false
	local outgoing = CoAPets.Outgoing
	local channel = getGroupChannel()
	if (#outgoing == 0) then
		return
	end
	if (not channel or not SendAddonMessage) then
		wipe(outgoing)
		return
	end

	local message = ""
	for i = 1, #outgoing do
		local guid = outgoing[i]
		if (#message + #guid + 1 > MAX_MESSAGE_LENGTH) then
			SendAddonMessage(COMM_PREFIX, message, channel)
			message = guid
		else
			message = (message == "") and guid or (message .. " " .. guid)
		end
	end
	if (message ~= "") then
		SendAddonMessage(COMM_PREFIX, message, channel)
	end
	wipe(outgoing)
end

---queue one of the player's own units to be announced to the group
---@param petGuid guid
local announceOwnPet = function(petGuid)
	if (CoAPets.Announced[petGuid] or not getGroupChannel()) then
		return
	end
	CoAPets.Announced[petGuid] = true
	CoAPets.Outgoing[#CoAPets.Outgoing+1] = petGuid
	if (not CoAPets.bAnnounceScheduled) then
		CoAPets.bAnnounceScheduled = true
		C_Timer.After(ANNOUNCE_DELAY, flushAnnouncements)
	end
end

local rememberUnresolved = function(petGuid, petName, petFlags)
	if (CoAPets.Unresolved[petGuid]) then
		return
	end
	if (CoAPets.UnresolvedCount >= MAX_UNRESOLVED) then
		wipe(CoAPets.Unresolved)
		CoAPets.UnresolvedCount = 0
	end
	CoAPets.Unresolved[petGuid] = {name = petName or "?", flags = petFlags or 0}
	CoAPets.UnresolvedCount = CoAPets.UnresolvedCount + 1
end

---find the owner of a group-owned unit from its combat log flags or from an owner's announcement
---@param petGuid guid
---@param petName actorname?
---@param petFlags number?
---@return actorname? ownerName
---@return guid? ownerGuid
---@return number? ownerFlags
function CoAPets.GetOwner(petGuid, petName, petFlags)
	if (not CoAPets.IsGroupOwnedUnit(petGuid, petFlags)) then
		return
	end

	if (bitBand(petFlags, AFFILIATION_MINE) ~= 0) then
		local playerGuid = UnitGUID("player")
		if (playerGuid and playerGuid ~= petGuid) then
			announceOwnPet(petGuid)
			return Details:GetFullName("player") or Details.playername, playerGuid, OWNER_FLAGS
		end
		return
	end

	local ownerName = CoAPets.SharedOwners[petGuid]
	if (ownerName) then
		local unitId = findGroupUnit(ownerName)
		if (unitId) then
			return Details:GetFullName(unitId), UnitGUID(unitId), OWNER_FLAGS
		end
	end

	rememberUnresolved(petGuid, petName, petFlags)
end

---a group member announced their units: remember the owner, and if Details already gave up on one
---of them, drop it from the caches so the next combat log event finds the owner
---@param ownerName actorname
---@param message string
function CoAPets.OnAnnouncement(ownerName, message)
	if (not ownerName or ownerName == UnitName("player") or not findGroupUnit(ownerName)) then
		return
	end

	for petGuid in gmatch(message, "%S+") do
		if (strsub(petGuid, 1, 2) == "0x" and #petGuid <= 18) then
			CoAPets.SharedOwners[petGuid] = ownerName
			if (petContainer.IgnoredActors[petGuid] or CoAPets.Unresolved[petGuid]) then
				petContainer.IgnoredActors[petGuid] = nil
				if (CoAPets.Unresolved[petGuid]) then
					CoAPets.Unresolved[petGuid] = nil
					CoAPets.UnresolvedCount = CoAPets.UnresolvedCount - 1
				end
				if (Details.RemoveFromPetBlackList) then
					Details:RemoveFromPetBlackList(petGuid)
				end
				if (Details.parser and Details.parser.RevomeActorFromCache) then
					Details.parser:RevomeActorFromCache(petGuid)
				end
			end
		end
	end
end

function CoAPets.Reset()
	wipe(CoAPets.SharedOwners)
	wipe(CoAPets.Announced)
	wipe(CoAPets.Unresolved)
	CoAPets.UnresolvedCount = 0
	if (CoAPets.PetLastCast) then
		wipe(CoAPets.PetLastCast)
	end
end

---print the group-owned units Details couldn't find an owner for (slash command: /details coapets)
function CoAPets.PrintUnresolved()
	if (CoAPets.UnresolvedCount == 0) then
		Details:Msg("CoA pets: every group-owned unit seen so far has an owner.")
		return
	end
	Details:Msg("CoA pets without an owner (name, guid, combat log flags):")
	for petGuid, info in pairs(CoAPets.Unresolved) do
		print(info.name, petGuid, string.format("0x%X", info.flags))
	end
end

------------------------------------------------------------------------------------------------
--pet ability names
--
--Some CoA summons deal damage with a helper spell named after the creature itself: the Tentacle of
--C'Thun channels Mental Assault (801151) and the damage ticks are spell 804999 "Tentacle of C'Thun".
--Details then lists "Tentacle of C'Thun (Tentacle of C'Thun)".
--
--For a pet spell named after the pet, every hit votes for the ability the same pet cast in the last
--few seconds. The helper gets that ability's name and icon only after VOTES_TO_ACCEPT votes with no
--vote for any other ability. A vote for a second ability means the pet mixes abilities through one
--helper spell (or the guess was wrong), so the helper keeps its plain name. Accepted pairings are
--saved in _detalhes_global and keep being checked: a conflicting vote removes them.
--Only the displayed name and icon change; each spell id keeps its own row and totals.

local GetSpellInfo = _G.GetSpellInfo
local GetTime = _G.GetTime
local gsub = string.gsub

local CAST_WINDOW = 3 --seconds a pet's last cast counts as the source of its next hits
local VOTES_TO_ACCEPT = 3
local MAX_HITS_WITHOUT_VOTES = 60 --stop checking a spell after this many hits without any vote

--verified in the core: npc_ascension_cultist_summon casts MentalAssault, whose periodic trigger is 804999
local knownHelperParents = {
	[804999] = 801151, --Tentacle of C'Thun (damage tick) -> Mental Assault
}

--names that describe a mechanic rather than an ability a player would recognize
local technicalNames = {"passive", "aura", "visual", "reticle", "proc", "trigger", "periodic", "dummy", "cosmetic", "placeholder", "immunity", "state", "scale", "scaling"}

---@type table<guid, {spellId: number, time: number}>
CoAPets.PetLastCast = {}
---spell id -> true when the parser doesn't need to call CheckPetSpell for it anymore
---@type table<number, boolean>
CoAPets.HelperChecked = {}
---spell id -> votes collected this session
---@type table<number, {votes: table<number, number>, hits: number, rejected: boolean?}>
CoAPets.HelperVotes = {}

local getSavedParents = function()
	local db = _G._detalhes_global
	if (db) then
		db.coa_pet_spell_parents = db.coa_pet_spell_parents or {}
		return db.coa_pet_spell_parents
	end
end

---return the id of the ability a helper spell is shown as, or nil
---@param spellId number
---@return number?
function CoAPets.GetHelperParent(spellId)
	local saved = getSavedParents()
	return knownHelperParents[spellId] or (saved and saved[spellId])
end

local isTechnicalName = function(spellName)
	local lowerName = spellName:lower()
	for i = 1, #technicalNames do
		if (lowerName:find(technicalNames[i], 1, true)) then
			return true
		end
	end
	return false
end

---true unless the player turned pet ability names off (spell breakdown options, or /details coapets names off)
---@return boolean
function CoAPets.IsHelperNamingEnabled()
	local settings = Details.breakdown_spell_tab
	return not settings or settings.coa_pet_ability_names ~= false
end

---a name the player gave this spell in the Details spell customization, or nil
local getUserSpellName = function(spellId)
	local customSpells = Details.savedCustomSpells
	if (customSpells) then
		for i = 1, #customSpells do
			if (customSpells[i][1] == spellId) then
				return customSpells[i]
			end
		end
	end
end

---overwrite the spell cache entry of a helper spell with the name and icon of its ability
local applyHelperName = function(helperId, parentId)
	if (not CoAPets.IsHelperNamingEnabled() or getUserSpellName(helperId)) then
		return
	end
	local parentName, _, parentIcon = GetSpellInfo(parentId)
	if (parentName and GetSpellInfo(helperId) and Details.spellcache) then
		rawset(Details.spellcache, helperId, {parentName, 1, parentIcon})
	end
end

---drop the spell cache entry so the helper shows its own name again (or the player's custom name)
local restoreHelperName = function(helperId)
	if (Details.spellcache) then
		local userSpell = getUserSpellName(helperId)
		rawset(Details.spellcache, helperId, userSpell and {userSpell[2], 1, userSpell[3]} or nil)
	end
end

---turn pet ability names on or off; off shows every spell with the name the game gives it
---saved pairings are kept, so turning it back on restores them
---@param bEnabled boolean
function CoAPets.SetHelperNamingEnabled(bEnabled)
	if (Details.breakdown_spell_tab) then
		Details.breakdown_spell_tab.coa_pet_ability_names = bEnabled and true or false
	end
	if (bEnabled) then
		wipe(CoAPets.HelperChecked) --start checking pet spells again
		CoAPets.ApplyHelperNames()
	else
		for helperId in pairs(knownHelperParents) do
			restoreHelperName(helperId)
		end
		local saved = getSavedParents()
		if (saved) then
			for helperId in pairs(saved) do
				restoreHelperName(helperId)
			end
		end
	end
end

---the spell cache gets rebuilt when segments are cleared: put the helper names back
function CoAPets.ApplyHelperNames()
	if (not CoAPets.IsHelperNamingEnabled()) then
		return
	end
	for helperId, parentId in pairs(knownHelperParents) do
		applyHelperName(helperId, parentId)
	end
	local saved = getSavedParents()
	if (saved) then
		for helperId, parentId in pairs(saved) do
			applyHelperName(helperId, parentId)
		end
	end
end

---parser: a pet cast a spell (SPELL_CAST_SUCCESS)
---@param petGuid guid
---@param spellId number
function CoAPets.OnPetCast(petGuid, spellId)
	local lastCast = CoAPets.PetLastCast[petGuid]
	if (lastCast) then
		lastCast.spellId = spellId
		lastCast.time = GetTime()
	else
		CoAPets.PetLastCast[petGuid] = {spellId = spellId, time = GetTime()}
	end
end

---the ability this pet's hit votes for, or nil when there's no usable cast
local getVote = function(spellId, petGuid)
	local lastCast = CoAPets.PetLastCast[petGuid]
	if (not lastCast or lastCast.spellId == spellId or GetTime() - lastCast.time > CAST_WINDOW) then
		return
	end
	local castName = GetSpellInfo(lastCast.spellId)
	if (not castName or castName == GetSpellInfo(spellId) or isTechnicalName(castName)) then
		return
	end
	return lastCast.spellId
end

---the helper mixes abilities or the guess was wrong: show its own name and stop checking
local rejectHelper = function(spellId, state)
	state.rejected = true
	local saved = getSavedParents()
	if (saved and saved[spellId]) then
		saved[spellId] = nil
	end
	restoreHelperName(spellId)
	CoAPets.HelperChecked[spellId] = true
end

---parser: a pet dealt damage or healed with this spell
---@param spellId number
---@param petGuid guid
---@param petActorName string pet actor name, "petName <ownerName>"
function CoAPets.CheckPetSpell(spellId, petGuid, petActorName)
	if (CoAPets.HelperChecked[spellId]) then
		return
	end

	--turned off, or set by hand: nothing to learn (turning it back on wipes HelperChecked)
	if (not CoAPets.IsHelperNamingEnabled() or knownHelperParents[spellId]) then
		CoAPets.HelperChecked[spellId] = true
		return
	end

	local state = CoAPets.HelperVotes[spellId]
	if (not state) then
		local spellName = GetSpellInfo(spellId)
		local petName = petActorName and gsub(petActorName, " <.*", "")
		if (not spellName or spellName ~= petName) then
			CoAPets.HelperChecked[spellId] = true --a normal ability name, nothing to do
			return
		end
		state = {votes = {}, hits = 0}
		CoAPets.HelperVotes[spellId] = state
	end

	state.hits = state.hits + 1
	local vote = getVote(spellId, petGuid)
	if (vote) then
		state.votes[vote] = (state.votes[vote] or 0) + 1
		for castId in pairs(state.votes) do
			if (castId ~= vote) then
				rejectHelper(spellId, state)
				return
			end
		end
		local saved = getSavedParents()
		if (saved and saved[spellId] and saved[spellId] ~= vote) then
			rejectHelper(spellId, state)
			return
		end
		if (state.votes[vote] >= VOTES_TO_ACCEPT and not (saved and saved[spellId])) then
			if (saved) then
				saved[spellId] = vote
			end
			applyHelperName(spellId, vote)
		end
	end

	--keep checking accepted pairings, a later conflicting vote removes them; give up only on helpers
	--that never got a single vote: a long channel ticks many times after its cast, and only the ticks
	--inside CAST_WINDOW vote, so a helper with votes keeps collecting them over the next casts
	if (state.hits >= MAX_HITS_WITHOUT_VOTES and next(state.votes) == nil) then
		CoAPets.HelperChecked[spellId] = true
	end
end

---print the learned pet ability names (slash command: /details coapets)
function CoAPets.PrintHelperNames()
	local saved = getSavedParents() or {}
	local lines = 0
	for helperId, parentId in pairs(knownHelperParents) do
		print(string.format("  %s (%d) -> %s (%d), set by hand", GetSpellInfo(helperId) or "?", helperId, GetSpellInfo(parentId) or "?", parentId))
		lines = lines + 1
	end
	for helperId, parentId in pairs(saved) do
		local state = CoAPets.HelperVotes[helperId]
		local votes = state and state.votes[parentId] or 0
		print(string.format("  %s (%d) -> %s (%d), %d votes this session", GetSpellInfo(helperId) or "?", helperId, GetSpellInfo(parentId) or "?", parentId, votes))
		lines = lines + 1
	end
	for helperId, state in pairs(CoAPets.HelperVotes) do
		if (state.rejected) then
			print(string.format("  %s (%d): pet uses more than one ability through it, keeps its own name", GetSpellInfo(helperId) or "?", helperId))
			lines = lines + 1
		end
	end
	if (lines == 0) then
		print("  none yet")
	end
end

---forget every learned pet ability name (slash command: /details coapets reset)
function CoAPets.ResetHelperNames()
	local saved = getSavedParents()
	if (saved) then
		for helperId in pairs(saved) do
			restoreHelperName(helperId)
			saved[helperId] = nil
		end
	end
	for helperId in pairs(CoAPets.HelperVotes) do
		restoreHelperName(helperId)
	end
	wipe(CoAPets.HelperVotes)
	wipe(CoAPets.HelperChecked)
	CoAPets.ApplyHelperNames()
end

local commFrame = CreateFrame("frame")
commFrame:RegisterEvent("CHAT_MSG_ADDON")
commFrame:SetScript("OnEvent", function(self, event, prefix, message, channel, sender)
	if (prefix == COMM_PREFIX and message and sender) then
		CoAPets.OnAnnouncement(sender, message)
	end
end)
