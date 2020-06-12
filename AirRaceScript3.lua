----------------------------------------------------------------------------------------------------------------------
-- Script       : CrossCountryRace.lua - Multiplayer Cross-country airrace script                                   --
-- Version      : 1.1                                                                                               --
-- Requirements : - DCS World 2.5.6                                                                                 --
--                - Mist 4.4.83                                                                                        --
-- Author       : Bas 'Joe Kurr' Weijers                                                                            --
--                Dutch Flanker Display Team                                                                        --
----------------------------------------------------------------------------------------------------------------------
-- This script enables mission builders to create a cross-country airrace course.                                   --
-- The course consists of two or more gates, and can run from one airbase to another.                               --
-- Each time a player enters the course through gate 1, the timer for that player is                                --
-- started, and will run until he either finishes the course, or leaves the route.                                  --
--                                                                                                                  --
-- Usage of this script:                                                                                            --
-- * Create a mission with one or more large overlapping trigger zones, named "racezone #001", "racezone #002", etc --
-- * Create two or more small trigger zones inside the large ones, named "gate #001", "gate #002", etc              --
-- * Place some static objects inside the Gate trigger zones so the players can see the gates                       --
--   These objects can be of any type, and can have any name, they are just there for visual reference.             --
-- * Add one or more aircraft or helicopters so clients can race with them                                          --
-- * Create three triggers:                                                                                         --
--                                                                                                                  --
--   1. Mission Start --> <empty>      --> Do Script                                                                --
--                                         NumberRaceZones = <total number of RaceZone triggerzones>                --
--                                         NumberGates = <total number of Gate triggerzones>                        --
--                                         NewPlayerCheckInterval = <number of seconds between checks>    [optional]--
--                                         RemovePlayerCheckInterval = <number of seconds between checks> [optional]--
--                                         HorizontalGates = <list of gate numbers requiring level flight>[optional]--
--                                         GateHeight = <global height of the gates in meters>            [optional]--
--                                         StartSpeedLimit = <first gate speed limit in km/h>             [optional]--
--                                                                                                                  --
--   2. Once          --> Time more(1) --> Do Script File                                                           --
--                                         mist_4_4_83.lua                                                          --
--                                                                                                                  --
--   3. Once          --> Time more(2) --> Do Script File                                                           --
--                                         AirRaceScript3.lua                                                       --
--                                                                                                                  --
----------------------------------------------------------------------------------------------------------------------

----------------------------------------------------------------------------------------------------------------------
-- PLAYER CLASS
----------------------------------------------------------------------------------------------------------------------

-----------------------------------------------------------------------------------------
-- Player Properties
--
Player = {
	Name = '',
	Unit = nil,
	UnitName = '',
	CurrentGateNumber = 0,
	StartTime = 0,
	Penalty = 0,
	HitPylon = 0,
	TotalTime = 0,
	IntermediateTimes = {},
	DNF = false,
	PylonFlag = false,
	Started = false,
	Finished = false,
	StatusText = ''
}

-----------------------------------------------------------------------------------------
-- Player Constructor
-- Parameter playerUnit: A unit from a Mist Unit Table representing a single aircraft
--                       or helicopters
--
function Player:New(playerUnit)
	local unitName = playerUnit:getName()
	local playerName = ''

	if playerUnit:getPlayerName() then
		playerName = playerUnit:getPlayerName()
	else
		playerName = playerUnit:getName()
	end

	local obj = {
		Name = playerName,
		Unit = Unit.getByName(unitName),
		UnitName = unitName,
		CurrentGateNumber = 0,
		StartTime = 0,
		Penalty = 0,
		HitPylon = 0,
		TotalTime = 0,
		IntermediateTimes = {},
		DNF = false,
		PylonFlag = false,
		Started = false,
		Finished = false,
		StatusText = 'New entry'
	}
	setmetatable(obj, { __index = Player })

	return obj
end

-----------------------------------------------------------------------------------------
-- Start the timer for the current player
--
function Player:StartTimer()
	if not self.Started then
		self.StartTime = timer.getTime()
		self.TotalTime = 0
		self.IntermediateTimes = {}
		self.Started = true
		self.Finished = false
	end
end

-----------------------------------------------------------------------------------------
-- Stop the timer for the current player and save the timer value in the Time field
--
function Player:StopTimer()
	if self.Started then
		self.TotalTime = timer.getTime() - self.StartTime
		self.Started = false
		self.Finished = true
	end
end

-----------------------------------------------------------------------------------------
-- Return the time for the current player and save it in the IntermediateTime field
--
function Player:GetIntermediateTime()
	local intermediate = 0
	if self.Started and not self.Finished then
		intermediate = timer.getTime() - self.StartTime
		table.insert(self.IntermediateTimes, intermediate)
	end
	return intermediate
end

----------------------------------------------------------------------------------------------------------------------
-- COURSE CLASS
----------------------------------------------------------------------------------------------------------------------

-----------------------------------------------------------------------------------------
-- Course Properties
--
Course = {
	Gates = {}
}

-----------------------------------------------------------------------------------------
-- Course Constructor
--
function Course:New()
	local obj = {
		Gates = {}
	}
	setmetatable(obj, { __index = Course })
	return obj
end

-----------------------------------------------------------------------------------------
-- Adds a gate to the course.
-- Parameter gateNumber: the number of the trigger zone that defines a gate.
--                       e.g. for "gate #012" this is 12
--
function Course:AddGate(gateNumber)
	local gateName = string.format("gate #%03d", gateNumber)
	local triggerZone = trigger.misc.getZone(gateName)
	-- logMessage(string.format("Looking up gate %s", gateName))
	if triggerZone then
		table.insert(self.Gates, gateName)
		-- logMessage(string.format("gate %s added to course", gateName))
	else
		logMessage(string.format("Could not find trigger zone '%s'", gateName))
	end
end

-----------------------------------------------------------------------------------------
-- Return all units currently flying through a gate on the course
--
function Course:GetUnitsInGates()
	local allUnits = mist.makeUnitTable( { '[blue][plane]' } )
	local units = mist.getUnitsInZones(allUnits, self.Gates)
	return units
end


----------------------------------------------------------------------------------------------------------------------
-- AIRRACE CLASS
----------------------------------------------------------------------------------------------------------------------

-----------------------------------------------------------------------------------------
-- Airrace Properties
--
Airrace = {
	RaceZones = {},
	Course = {},
	Players = {},
	FastestTime = 0,
	FastestPlayer = '',
	LastMessage = '',
	LastMessageId = 0,
	GateHeight = 100,
	HorizontalGates = {},
	StartSpeedLimit = 300,
	MessageLogged = false
}

-----------------------------------------------------------------------------------------
-- Airrace Constructor
-- Parameter triggerZoneNames: A table containing the names of one or more trigger zones
--                             covering the entire race course
-- Parameter course          : A reference to the Course object containing all the gates
--
function Airrace:New(triggerZoneNames, triggerZonePylonNames, course, gateHeight, horizontalGates, startSpeedLimit)
	local obj = {
		RaceZones = triggerZoneNames,
		PylonZones = triggerZonePylonNames,
		Course = course,
		Players = {},
		FastestTime = 0,
		FastestPlayer = '',
		FastestIntermediates = {},
		GateHeight = gateHeight,
		HorizontalGates = horizontalGates or {},
		StartSpeedLimit = startSpeedLimit
	}
	setmetatable(obj, { __index = Airrace })
	return obj
end

-----------------------------------------------------------------------------------------
-- Check if any new players have entered one of the RaceZone trigger zones
-- and add them to the list of active players
--
function Airrace:CheckForNewPlayers()
	local allUnits = mist.makeUnitTable( { '[blue][plane]' } )
	local unitsInZone = mist.getUnitsInZones(allUnits, self.RaceZones)
	local playerExists = false

	for unitIndex, unit in ipairs(unitsInZone) do
		if unit:getLife() > 1 then	-- Only check for alive units
			playerExists = false
			if #self.Players > 0 then
				for playerIndex, player in ipairs(self.Players) do
					local unitName = ''
					if unit:getPlayerName() then
						unitName = unit:getPlayerName()
					else
						unitName = unit:getName()
					end
					if player.Name == unitName then
						playerExists = true
						break
					end
				end
			end
			if not playerExists then
				env.info(string.format("Player %s added to player list", unit:getPlayerName() or unit:getName()))
				table.insert(self.Players, Player:New(unit))
				trigger.action.outSound('smoke on.ogg')
			end
		end
	end
end

-----------------------------------------------------------------------------------------
-- Check if any players have left the RaceZone trigger zones, and remove them from
-- the list of active players
--
function Airrace:RemoveExitedPlayers()
	if #self.Players > 0 then
		local allUnits = mist.makeUnitTable( { '[blue][plane]' } )
		local unitsInZone = mist.getUnitsInZones(allUnits, self.RaceZones)
		local playerExists = false

		for playerIndex, player in ipairs(self.Players) do
			playerExists = false
			if player.Unit:getLife() > 1 then	-- Only check for alive units
				for unitIndex, unit in ipairs(unitsInZone) do
					local unitName = ''
					if unit:getPlayerName() then
						unitName = unit:getPlayerName()
					else
						unitName = unit:getName()
					end
					if player.Name == unitName then
						playerExists = true
						break
					end
				end
			end
			if not playerExists then
				env.info(string.format("Player %s removed from player list", player.Name))
				table.remove(self.Players, playerIndex)
			end
		end
	end
end

-----------------------------------------------------------------------------------------
-- Return a list of players currently flying through a gate
--
function Airrace:GetPlayersInGates()
	local result = {}
	if #self.Players > 0 then
		local unitsInGates = self.Course:GetUnitsInGates()
		if #unitsInGates > 0 then
			for unitIndex, unit in ipairs(unitsInGates) do
				local unitName = unit:getName()
				for playerIndex, player in ipairs(self.Players) do
					if player.UnitName == unitName then
						table.insert(result, player)
					end
				end
			end
		end
	end
	return result
end

-----------------------------------------------------------------------------------------
-- Return the number of the gate the given player is flying through, or 0 if not in gate
-- Parameter player: Reference to a player in the active players List
--
function Airrace:GetGateNumberForPlayer(player)
	local result = 0
	local playerUnitTable = mist.makeUnitTable( { player.UnitName } )
	for gateIndex, gateName in ipairs(self.Course.Gates) do
		local playersInsideZone = mist.getUnitsInZones(playerUnitTable, { gateName })
		if #playersInsideZone > 0 and gateIndex == player.CurrentGateNumber + 1 then
			result = gateIndex
			break
		end
	end
	return result
end
-----------------------------------------------------------------------------------------
-- Check if the player hit the pylon
-- Player parameter: link to the player in the list of active players
-- Gives a penalty for a downed pylon, and gives a DNF if 3 pylons are downed
-----------------------------------------------------------------------------------------
function Airrace:CheckPylonHitForPlayer(player)
	local playerUnitTable = mist.makeUnitTable( { player.UnitName } )
	for pylonIndex, pylonName in ipairs(self.PylonZones) do
		local playersInsideZone = mist.getUnitsInZones(playerUnitTable, { pylonName })
		if #playersInsideZone > 0 and player.PylonFlag == false then
			local gateAltitudeOk = self:CheckPylonAltitudeForPlayer(player)
			if  gateAltitudeOk == true then
				logMessage(string.format("PYLON HIT!!! pylon %d ", pylonIndex))
				trigger.action.outSound('penalty.ogg')
				player.Penalty = player.Penalty + 3
				player.HitPylon = player.HitPylon + 1
				player.PylonFlag = true
			end
			if player.HitPylon == 3 then
				player.DNF = true
				player.StatusText = string.format("3rd pylon hit !!! DNF!!!")
			end
			break
		end
	end
end
-----------------------------------------------------------------------------------------
function Airrace:CheckPylonAltitudeForPlayer(player)
	local result = true
	local pos = Unit.getByName(player.UnitName):getPosition().p
	local playerPos = { 
	   x = pos["x"], 
	   y = pos["y"], 
	   z = pos["z"] 
	} 
	local TerrainPos = land.getHeight({x = playerPos.x, y = playerPos.z})
	playerAgl = playerPos.y - TerrainPos		
	if playerAgl <= self.GateHeight then
		result = true
	else
		result = false
	end
	return result
end
-----------------------------------------------------------------------------------------
-- Check whether the given player is flying below the gate height
-- Parameter player: Reference to a player in the active players list
-- Returns true if the player is below the gate height, or false when flying too high
--
function Airrace:CheckGateAltitudeForPlayer(player)
	local result = true
	local pos = Unit.getByName(player.UnitName):getPosition().p
	local playerPos = { 
	   x = pos["x"], 
	   y = pos["y"], 
	   z = pos["z"] 
	} 
	local TerrainPos = land.getHeight({x = playerPos.x, y = playerPos.z})
	playerAgl = playerPos.y - TerrainPos		
	if playerAgl <= self.GateHeight then
		result = true
	else
		result = false
		logMessage(string.format("FLYING TOO HIGH/LOW !!! Player altitude = %d meters", playerAgl))
	end
	return result
end
-----------------------------------------------------------------------------------------
-- Check whether this player is flying faster than the speed limit on the first gate
-- Player parameter: link to the player in the list of active players
-- Returns true if the speed is less than 300 km / h, or false if the speed is greater than 300 km / h
--
function Airrace:CheckGateSpeedForPlayer(player)
	local result = true
	local unitspeed = Unit.getByName(player.UnitName):getVelocity()
	speed = math.sqrt(unitspeed.x^2 + unitspeed.y^2 + unitspeed.z^2)
	-- logMessage(string.format("sped %d km/h", speed * 3.6))
	if speed * 3.6 <= self.StartSpeedLimit then
		result = true
		logMessage(string.format("Player start speed = %d km/h", speed * 3.6))
	else
		result = false
		logMessage(string.format("EXCEEDING START SPEED LIMIT of %d km/h !!! Player speed = %s km/h", self.StartSpeedLimit, speed * 3.6))
	end
	return result
end
-----------------------------------------------------------------------------------------
-- Check the player's roll
-- Player parameter: link to the player in the list of active players
-- Returns true if the roll is in the range of -10 ~ +10 deg.
--
function Airrace:CheckGateRollForPlayer(player)
	local result = true
	local myUnit = Unit.getByName(player.UnitName)
	roll = 180 * mist.getRoll(myUnit) / math.pi
	-- logMessage(string.format("Roll %s gr, %s rad", roll, mist.getRoll(myUnit)))
	if roll >= -10 and roll <= 10 then
		result = true
	else
		result = false
		logMessage(string.format("INCORRECT LEVEL FLYING !!! Player roll = %d degrees", roll))
	end
	return result
end
-----------------------------------------------------------------------------------------
-- Update the status and timer for the given player
-- Parameter player: Reference to a player in the active player List
--
function Airrace:UpdatePlayerStatus(player)
	local gateNumber = self:GetGateNumberForPlayer(player)
	if gateNumber ~= player.CurrentGateNumber or gateNumber == 1 then
		if gateNumber == player.CurrentGateNumber + 1 or gateNumber == 1 then
			if gateNumber == 1 then
				local gateAltitudeOk = self:CheckGateAltitudeForPlayer(player)
				local gateSpeedOk = self:CheckGateSpeedForPlayer(player)
				local gateRollOk = self:CheckGateRollForPlayer(player)
-- Player is passing gate 1, start timer
				-- player.Started = false -- Passing gate 1 always resets the timer
				trigger.action.outSound('pik.ogg')
				player:StartTimer()
				player.StatusText = "Started"
				player.CurrentGateNumber = gateNumber
				player.PylonFlag = false
				if gateSpeedOk == false then
					trigger.action.outSound('penalty.ogg')
					player:StopTimer()
					player.StatusText = string.format("EXCEEDING START SPEED LIMIT !!! DNF!!!")
					player.DNF = true
				end
				if gateRollOk == false then
					trigger.action.outSound('penalty.ogg')
					player.Penalty = player.Penalty + 2
					-- logMessage(string.format("PENALTY: + 2 seconds "))
				end
				if gateAltitudeOk == false then
					trigger.action.outSound('penalty.ogg')
					player.Penalty = player.Penalty + 2
					-- logMessage(string.format("PENALTY: + 2 seconds "))
				end
			elseif gateNumber == #self.Course.Gates then
				local gateAltitudeOk = self:CheckGateAltitudeForPlayer(player)
				local gateRollOk = self:CheckGateRollForPlayer(player)
-- Player is passing the last gate, stop timer
				player.PylonFlag = false
				if gateRollOk == false then
					trigger.action.outSound('penalty.ogg')
					player.Penalty = player.Penalty + 2
					-- logMessage(string.format("PENALTY: + 2 seconds "))
				end
				if gateAltitudeOk == false then
					trigger.action.outSound('penalty.ogg')
					player.Penalty = player.Penalty + 2
					-- logMessage(string.format("PENALTY: + 2 seconds "))
				end
				player.PylonFlag = false
				player:StopTimer()
				player.StatusText = string.format("Finished. Race time:  %s. Penalty: %s second. Total time: %s ", formatTime(player.TotalTime), player.Penalty, formatTime(player.TotalTime + player.Penalty))
				env.info(string.format("Player %s finished the course. Race time: %s. Penalty: %s. Total time: %s", player.Name, formatTime(player.TotalTime), player.Penalty, formatTime(player.TotalTime + player.Penalty)))
				trigger.action.outSound('pik.ogg')
				player.CurrentGateNumber = gateNumber
				if self.FastestTime == 0 or self.FastestTime > player.TotalTime + player.Penalty then
					self.FastestTime = player.TotalTime + player.Penalty
					self.FastestPlayer = player.Name
					player.StatusText = string.format("%s - Fastest time!", player.StatusText)
					self.FastestIntermediates = player.IntermediateTimes
				else
					player.StatusText = string.format("%s (+%s)", player.StatusText, formatTime(player.TotalTime - self.FastestTime))
				end
			else
-- Player is passing intermediate gate, set intermediate time
				local gateAltitudeOk = self:CheckGateAltitudeForPlayer(player)
				local intermediate = player:GetIntermediateTime()
				trigger.action.outSound('pik.ogg')
				player.StatusText = string.format("Intermediate: %s", formatTime(intermediate))
				for i = 1 , #self.HorizontalGates do
					if self.HorizontalGates[i] == gateNumber then
						local gateRollOk = self:CheckGateRollForPlayer(player)
						if gateRollOk == false then
							trigger.action.outSound('penalty.ogg')
							player.Penalty = player.Penalty + 2
							-- logMessage(string.format("PENALTY: + 2 seconds "))
						end
						break
					end
				end
				player.PylonFlag = false
				if gateAltitudeOk == false then
					trigger.action.outSound('penalty.ogg')
					player.Penalty = player.Penalty + 2
					-- logMessage(string.format("PENALTY: + 2 seconds "))
				end
				if self.FastestTime ~= 0 then
					local fastestIntermediate = self.FastestIntermediates[gateNumber - 1]
					local difference = intermediate - fastestIntermediate
					local sign = "+"
					if difference < 0 then
						sign = "-"
					end
					player.StatusText = string.format("%s (%s%s)", player.StatusText, sign, formatTime(math.abs(difference)))
				end
				player.CurrentGateNumber = gateNumber
			end
		else
			if player.CurrentGateNumber == 0 and not player.Finished then
				-- Player is entering the course half-way
				player.StatusText = "Wrong start gate, go to gate 1 to start"
				env.info(string.format("Player %s entered the course half-way", player.Name))
			elseif not player.Finished then
				-- Player has missed a gate or is going the wrong way
				if gateNumber > player.CurrentGateNumber + 1 then
					-- Player has missed one or more gates
					missedGates = gateNumber - (player.CurrentGateNumber + 1)
					if missedGates == 1 then
						player.StatusText = string.format("Missed gate %d", player.CurrentGateNumber + 1)
						env.info(string.format("Player %s missed gate %d", player.Name, player.CurrentGateNumber + 1))
					else
						player.StatusText = string.format("Missed gates %d to %d", player.CurrentGateNumber + 1, gateNumber - 1)
						env.info(string.format("Player %s missed gates %d to %d", player.Name, player.CurrentGateNumber + 1, gateNumber - 1))
					end
					player.Penalty = player.Penalty + (5 * missedGates)
					player.CurrentGateNumber = gateNumber
				else
					-- Player is going the wrong way
					-- player.StatusText = string.format("Wrong way! Last known gate: %d", player.CurrentGateNumber)
				end
			end
		end
	end
end
-----------------------------------------------------------------------------------------
-- Display all active players on screen, with their current status
--
function Airrace:ListPlayers()
	local text = string.format("%d players in course", #self.Players)
	local playerNames = {}
	if self.FastestTime > 0 then
		text = string.format("%s - Fastest time: %s by %s", text, formatTime(self.FastestTime), self.FastestPlayer)
	end
	text = string.format("%s\n---------------------------------------", text)
	if #self.Players > 0 then
		local playersInGates = self:GetPlayersInGates()
		if #playersInGates > 0 then
			for playerIndex, player in ipairs(playersInGates) do
				if player.DNF == false then
					self:CheckPylonHitForPlayer(player)
					self:UpdatePlayerStatus(player)
				end
			end
		end
		for playerIndex, player in ipairs(self.Players) do
			text = string.format("%s\nPlayer: %s", text, player.Name)
			playerNames[playerIndex] = player.UnitName
			if player.CurrentGateNumber > 0 then
				text = string.format("%s\tGate %d - %s", text, player.CurrentGateNumber, player.StatusText)
			else
				text = string.format("%s - %s", text, player.StatusText)
			end
		end
	end
-- --	if self.LastMessage ~= text then
-- 		local msg = {} 
-- 		msg.text = text 
-- 		msg.displayTime = 25  
-- 		msg.msgFor = {units = playerNames} 
-- --		msg.msgFor = {coa = {'all'}} 
-- 		mist.message.removeById(self.LastMessageId)
-- 		self.LastMessageId = mist.message.add(msg)
-- 		self.LastMessage = text
-- --	end
	trigger.action.outText(text, 10, true)
end

----------------------------------------------------------------------------------------------------------------------
-- MAIN SCRIPT
----------------------------------------------------------------------------------------------------------------------

-----------------------------------------------------------------------------------------
-- Periodically check status for all players and display a list on screen
-- Parameter race: reference to the current Airrace object
--
function RaceTimer(race)
	race:ListPlayers()
end

-----------------------------------------------------------------------------------------
-- Periodically check for new players inside the RaceZone trigger zones
-- Parameter race: reference to the current Airrace object
--
function NewPlayerTimer(race)
	race:CheckForNewPlayers()
end

-----------------------------------------------------------------------------------------
-- Periodically check for players who are no longer inside the RaceZone trigger zones
-- Parameter race: reference to the current Airrace object
--
function RemovePlayerTimer(race)
	race:RemoveExitedPlayers()
end

-----------------------------------------------------------------------------------------
-- Write a message in dcs.log and show it on screen (for debugging purposes)
-- Parameter message: the message to be written
--
function logMessage(message)
	env.info(message)
	local msg = {} 
	msg.text = message
	msg.displayTime = 25  
	msg.msgFor = {coa = {'all'}} 
	mist.message.add(msg)
--	trigger.action.outText(message, 10)
end

-----------------------------------------------------------------------------------------
-- Format the given time in seconds to HH:mm:ss.mil (e.g. 01:42:38.382)
-- Parameter seconds: a float containing the number of seconds (from timer.getTime())
--
function formatTime(seconds)
	return string.format("%02d:%02d:%06.3f", seconds / (60 * 60), seconds / 60 % 60, seconds % 60)
end

-----------------------------------------------------------------------------------------
-- Initialize the script
--
function Init()
	local raceZones = {}
	local racePylons = {}
	local horizontalGates = HorizontalGates
	local course = Course:New()
	local race = nil
	local numberRaceZones = NumberRaceZones or 0
	local numberPylons = NumberPylons or 0
	local numberGates = NumberGates or 0
	local newPlayerCheckInterval = NewPlayerCheckInterval or 1
	local removePlayerCheckInterval = RemovePlayerCheckInterval or 30
	local gateHeight = GateHeight or 25
	local startSpeedLimit = StartSpeedLimit or 300
	
	if numberRaceZones > 0 and numberGates > 0 then
		for idx = 1, numberRaceZones do
			-- logMessage(string.format("Adding zone: RaceZone #%03d", idx))
			table.insert(raceZones, string.format("racezone #%03d", idx))
		end
		for idx = 1, numberPylons do
			-- logMessage(string.format("Adding zone: Pylons #%03d", idx))
			table.insert(racePylons, string.format("pilone #%03d", idx))
		end
		for idx = 1, numberGates do
			course:AddGate(idx)
		end
		race = Airrace:New(raceZones, racePylons, course, gateHeight, horizontalGates, startSpeedLimit)
		mist.scheduleFunction(RaceTimer, { race }, timer.getTime(), 0.1)
		mist.scheduleFunction(NewPlayerTimer, { race }, timer.getTime(), newPlayerCheckInterval)
		mist.scheduleFunction(RemovePlayerTimer, { race }, timer.getTime(), removePlayerCheckInterval)
	else
		logMessage("Variables 'NumberRaceZones' or 'NumberGates' not set")
	end
end

env.info("-----------------------------------------------------------------------------------------")
env.info("Start Airrace script")

Init()
