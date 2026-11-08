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

local commFrame = CreateFrame("frame")
commFrame:RegisterEvent("CHAT_MSG_ADDON")
commFrame:SetScript("OnEvent", function(self, event, prefix, message, channel, sender)
	if (prefix == COMM_PREFIX and message and sender) then
		CoAPets.OnAnnouncement(sender, message)
	end
end)
