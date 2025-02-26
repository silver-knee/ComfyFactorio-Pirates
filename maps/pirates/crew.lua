
local Balance = require 'maps.pirates.balance'
local inspect = require 'utils.inspect'.inspect
local Memory = require 'maps.pirates.memory'
local Math = require 'maps.pirates.math'
local Common = require 'maps.pirates.common'
local Parrot = require 'maps.pirates.parrot'
local CoreData = require 'maps.pirates.coredata'
local Server = require 'utils.server'
local Utils = require 'maps.pirates.utils_local'
local Surfaces = require 'maps.pirates.surfaces.surfaces'
local Structures = require 'maps.pirates.structures.structures'
local Boats = require 'maps.pirates.structures.boats.boats'
local Crowsnest = require 'maps.pirates.surfaces.crowsnest'
local Hold = require 'maps.pirates.surfaces.hold'
local Lobby = require 'maps.pirates.surfaces.lobby'
local Cabin = require 'maps.pirates.surfaces.cabin'
local Roles = require 'maps.pirates.roles.roles'
local Token = require 'utils.token'
local Task = require 'utils.task'
local SurfacesCommon = require 'maps.pirates.surfaces.common'

local Public = {}
local enum = {
		ADVENTURING = 'adventuring',
		LEAVING_INITIAL_DOCK = 'leavinginitialdock'
}
Public.enum = enum


function Public.difficulty_vote(player_index, difficulty_id)
	local memory = Memory.get_crew_memory()

	local player = game.players[player_index]
	if not (player and player.valid) then return end
	local option = CoreData.difficulty_options[difficulty_id]
	if not option then return end

	Common.notify_force(game.forces[memory.force_name], player.name .. ' voted for difficulty ' .. option.text, option.associated_color)

	if not (memory.difficulty_votes) then memory.difficulty_votes = {} end
	memory.difficulty_votes[player_index] = difficulty_id

	Public.update_difficulty()
end


function Public.update_difficulty()
	local memory = Memory.get_crew_memory()

	local vote_counts = {}
	for _, difficulty_id in pairs(memory.difficulty_votes) do
		if not vote_counts[difficulty_id] then
			vote_counts[difficulty_id] = 1
		else
			vote_counts[difficulty_id] = vote_counts[difficulty_id] + 1
		end
	end

	local modal_id = 1
	local modal_count = 0
	for difficulty_id, votes in pairs(vote_counts) do
		if votes > modal_count or (votes == modal_count and difficulty_id < modal_id) then
			modal_count = votes
			modal_id = difficulty_id
		end
	end

	if modal_id ~= memory.difficulty_option then
		local message = 'Difficulty changed to ' .. CoreData.difficulty_options[modal_id].text .. '.'

		Common.notify_force(game.forces[memory.force_name], message)
		Server.to_discord_embed_raw(CoreData.comfy_emojis.kewl .. '[' .. memory.name .. '] ' .. message)

		memory.difficulty_option = modal_id
		memory.difficulty = CoreData.difficulty_options[modal_id].value
	end
end


function Public.try_add_extra_time_at_sea(ticks)
	local memory = Memory.get_crew_memory()

	if not memory.extra_time_at_sea then memory.extra_time_at_sea = 0 end
	
	if memory.extra_time_at_sea > 4*60*60 then return false end

	-- if memory.boat and memory.boat.state and memory.boat.state == Boats.enum_state.ATSEA_LOADING_MAP then return false end
	
	memory.extra_time_at_sea = memory.extra_time_at_sea + ticks
	return true
end

function Public.try_lose(reason)
	local memory = Memory.get_crew_memory()
	
	if (not memory.game_lost) then
		memory.game_lost = true
		memory.crew_disband_tick = game.tick + 360

		local playtimetext = Utils.time_longform((memory.age or 0)/60)
		
		Server.to_discord_embed_raw(CoreData.comfy_emojis.trashbin .. '[' .. memory.name .. '] Game over — ' .. reason ..'. Playtime: ' .. playtimetext .. ' since 1st island.')
		Common.notify_game('[' .. memory.name .. '] Game over — ' .. reason ..'. Playtime: [font=default-large-semibold]' .. playtimetext .. ' since 1st island[/font].', CoreData.colors.notify_gameover)
	
		local force = game.forces[memory.force_name]
		if not (force and force.valid) then return end
		force.play_sound{path='utility/game_lost', volume_modifier=0.75}
	end
end


function Public.choose_crew_members()
	local global_memory = Memory.get_global_memory()
	local memory = Memory.get_crew_memory()
	local capacity = memory.capacity
	local boat = memory.boat

	-- if the boat is over capacity, should prefer original endorsers over everyone else:
	local crew_members = {}
	local crew_members_count = 0
	for _, player in pairs(game.connected_players) do
		if crew_members_count < capacity and player.surface.name == CoreData.lobby_surface_name and Boats.on_boat(boat, player.position) then
			-- check if they were an endorser
			local endorser = false
			for _, index in pairs(memory.original_proposal.endorserindices) do
				if player.index == index then endorser = true end
			end
			if endorser then
				crew_members[player.index] = player
				crew_members_count = crew_members_count + 1
			end
		end
	end
	
	if crew_members_count < capacity then
		for _, player in pairs(game.connected_players) do
			if crew_members_count < capacity and (not crew_members[player.index]) and player.surface.name == CoreData.lobby_surface_name and Boats.on_boat(boat, player.position) then
				crew_members[player.index] = player
				crew_members_count = crew_members_count + 1
			end
		end
	end

	for _, player in pairs(crew_members) do
		player.force = game.forces[memory.force_name]
		memory.crewplayerindices[#memory.crewplayerindices + 1] = player.index
	end

	return crew_members
end


function Public.join_spectators(player, crewid)
	if crewid > 0 then
		Memory.set_working_id(crewid)
		local memory = Memory.get_crew_memory()

		local force = game.forces[string.format('crew-%03d', crewid)]
		if not (force and force.valid and Common.validate_player(player)) then return end

		local surface = game.surfaces[CoreData.lobby_surface_name]

		local adventuring = false
		local spectating = false
		if memory.crewstatus and memory.crewstatus == enum.ADVENTURING then
			for _, playerindex in pairs(memory.crewplayerindices) do
				if player.index == playerindex then adventuring = true end
			end
			for _, playerindex in pairs(memory.spectatorplayerindices) do
				if player.index == playerindex then spectating = true end
			end
		end
		if not spectating then
			if adventuring then
				local char = player.character

				if char and char.valid then
					local p = char.position
					local surface_name = char.surface.name
					local message = player.name .. ' left the crew'
					if p then
						Common.notify_force(force, message .. ' to become a spectator.' .. ' [gps=' .. Math.ceil(p.x) .. ',' .. Math.ceil(p.y) .. ',' .. surface_name ..']')
						-- Server.to_discord_embed_raw(CoreData.comfy_emojis.feel .. '[' .. memory.name .. '] ' .. message)
					end
					player.set_controller{type = defines.controllers.spectator}
					char.die(memory.force_name)
				else
					local message = player.name .. ' left the crew'
					Common.notify_force(force, message .. ' to become a spectator.')
					-- Server.to_discord_embed_raw(CoreData.comfy_emojis.feel .. '[' .. memory.name .. '] ' .. message)
					player.set_controller{type = defines.controllers.spectator}
				end
		
				local c = surface.create_entity{name = 'character', position = surface.find_non_colliding_position('character', Common.lobby_spawnpoint, 32, 0.5) or Common.lobby_spawnpoint, force = 'player'}

				player.associate_character(c)
		
				player.set_controller{type = defines.controllers.spectator}
		
				memory.crewplayerindices = Utils.ordered_table_with_values_removed(memory.crewplayerindices, player.index)

				Roles.player_left_so_redestribute_roles(player)
			else
				Public.player_abandon_endorsements(player)
				local c = player.character
				player.set_controller{type = defines.controllers.spectator}
				player.teleport(memory.spawnpoint, game.surfaces[Common.current_destination().surface_name])
				player.force = force
				player.associate_character(c)

				Common.notify_force(force, player.name .. ' joined as a spectator.')
				Common.notify_lobby(player.name .. ' left the lobby to spectate ' .. memory.name .. '.')
			end
			memory.spectatorplayerindices[#memory.spectatorplayerindices + 1] = player.index
			memory.tempbanned_from_joining_data[player.index] = game.tick
			if #Common.crew_get_crew_members() == 0 then
				memory.crew_disband_tick = game.tick + 30
				-- memory.crew_disband_tick = game.tick + 60*60*2 --give players time to log back in after a crash or save
			end
			if not (memory.difficulty_votes) then memory.difficulty_votes = {} end
			memory.difficulty_votes[player.index] = nil
		end
	end
end


function Public.leave_spectators(player, quiet)
	quiet = quiet or false
	local memory = Memory.get_crew_memory()
	local surface = game.surfaces[CoreData.lobby_surface_name]
	
	if not Common.validate_player(player) then return end

	if not quiet then
		Common.notify_force(player.force, player.name .. ' stopped spectating and returned to the lobby.')
	end

	local chars = player.get_associated_characters()
	if #chars > 0 then
		player.teleport(chars[1].position, surface)
		player.set_controller{type = defines.controllers.character, character = chars[1]}
	else
		player.set_controller{type = defines.controllers.god}
		player.teleport(surface.find_non_colliding_position('character', Common.lobby_spawnpoint, 32, 0.5) or Common.lobby_spawnpoint, surface)
		player.create_character()
	end

	memory.spectatorplayerindices = Utils.ordered_table_with_values_removed(memory.spectatorplayerindices, player.index)

	if #Common.crew_get_crew_members() == 0 then
		Public.disband_crew()
	end

	player.force = 'player'
end


function Public.join_crew(player, crewid)
	if crewid then
		Memory.set_working_id(crewid)
		local memory = Memory.get_crew_memory()

		if not Common.validate_player(player) then return end

		local startsurface = game.surfaces[CoreData.lobby_surface_name]

		local boat = memory.boat
		local surface
		if boat and boat.surface_name and game.surfaces[boat.surface_name] and game.surfaces[boat.surface_name].valid then
			surface = game.surfaces[boat.surface_name]
		else
			surface = game.surfaces[Common.current_destination().surface_name]
		end

		local adventuring = false
		local spectating = false
		if memory.crewstatus and memory.crewstatus == enum.ADVENTURING then
		for _, playerindex in pairs(memory.crewplayerindices) do
			if player.index == playerindex then adventuring = true end
		end
		for _, playerindex in pairs(memory.spectatorplayerindices) do
			if player.index == playerindex then spectating = true end
		end
		end

		if spectating then
			local chars = player.get_associated_characters()
			for _, char in pairs(chars) do
					char.destroy()
			end

			player.teleport(surface.find_non_colliding_position('character', memory.spawnpoint, 32, 0.5) or memory.spawnpoint, surface)

			player.set_controller{type = defines.controllers.god}
			player.create_character()
			
			memory.spectatorplayerindices = Utils.ordered_table_with_values_removed(memory.spectatorplayerindices, player.index)
		else
			Public.player_abandon_endorsements(player)
			player.force = game.forces[string.format('crew-%03d', memory.id)]
			player.teleport(surface.find_non_colliding_position('character', memory.spawnpoint, 32, 0.5) or memory.spawnpoint, surface)
		end

		local message = player.name .. ' joined the crew.'
		Common.notify_force(player.force, message)
		-- Server.to_discord_embed_raw(CoreData.comfy_emojis.yum1 .. '[' .. memory.name .. '] ' .. message)
		Common.notify_lobby(player.name .. ' left the lobby to join ' .. memory.name .. '.')

		memory.crewplayerindices[#memory.crewplayerindices + 1] = player.index

		-- don't give them items if they've been in the crew recently:
		if not (memory.tempbanned_from_joining_data and memory.tempbanned_from_joining_data[player.index] and game.tick < memory.tempbanned_from_joining_data[player.index] + 8 * Common.ban_from_rejoining_crew_ticks) then
			for item, amount in pairs(Balance.starting_items_player_late) do
				player.insert({name = item, count = amount})
			end
		end

		if #Common.crew_get_crew_members() == 1 and memory.crew_disband_tick then
			memory.crew_disband_tick = nil --to prevent disbanding the crew after saving the game (booting everyone) and loading it again (joining the crew as the only member)
		end
	end
end

function Public.leave_crew(player, quiet)
	quiet = quiet or false
	local memory = Memory.get_crew_memory()
	local surface = game.surfaces[CoreData.lobby_surface_name]
	
	if not Common.validate_player(player) then return end

	local char = player.character
	player.set_controller{type = defines.controllers.god}
	if char and char.valid then
		local p = char.position
		local surface_name = char.surface.name
		local message
		if quiet then
			message = player.name .. ' left.'
		else
			message = player.name .. ' left the crew.'
		end
		if p then
			Common.notify_force(player.force, message .. ' [gps=' .. Math.ceil(p.x) .. ',' .. Math.ceil(p.y) .. ',' .. surface_name ..']')
			-- Server.to_discord_embed_raw(CoreData.comfy_emojis.feel .. '[' .. memory.name .. '] ' .. message)
		end
		char.die(memory.force_name)
	else
		if not quiet then
			local message = player.name .. ' left the crew.'
			Common.notify_force(player.force, message)
		end
	end

	player.teleport(surface.find_non_colliding_position('character', Common.lobby_spawnpoint, 32, 0.5) or Common.lobby_spawnpoint, surface)
	player.force = 'player'
	player.create_character()

	memory.crewplayerindices = Utils.ordered_table_with_values_removed(memory.crewplayerindices, player.index)

	-- setting it to this won't ban them from rejoining, it just affects the loot they spawn in with:
	memory.tempbanned_from_joining_data[player.index] = game.tick - Common.ban_from_rejoining_crew_ticks

	if not (memory.difficulty_votes) then memory.difficulty_votes = {} end
	memory.difficulty_votes[player.index] = nil

	if #Common.crew_get_crew_members() == 0 then
		memory.crew_disband_tick = game.tick + 30
		-- memory.crew_disband_tick = game.tick + 60*60*2 --give players time to log back in after a crash or save
	else
		Roles.player_left_so_redestribute_roles(player)
	end
end



function Public.get_unaffiliated_players()
	local global_memory = Memory.get_global_memory()

	local playerlist = {}
	for _, player in pairs(game.connected_players) do
		local found = false
		for _, id in pairs(global_memory.crew_active_ids) do
			Memory.set_working_id(id)
			for _, player2 in pairs(Common.crew_get_crew_members_and_spectators()) do
				if player == player2 then found = true end
			end
		end
		if not found then playerlist[#playerlist + 1] = player end
	end
	return playerlist
end




function Public.disband_crew(donotprint)
	local global_memory = Memory.get_global_memory()
	local memory = Memory.get_crew_memory()
	
	if not memory.name then return end

	local id = memory.id
	local players = Common.crew_get_crew_members_and_spectators()

	for _,player in pairs(players) do
		if player.controller_type == defines.controllers.editor then player.toggle_map_editor() end
		player.force = 'player'
	end

	if (not donotprint) then

		local message = '[' .. memory.name .. '] Disbanded after ' .. Utils.time_longform((memory.real_age or 0)/60) .. '.'
		Common.notify_game(message)
		Server.to_discord_embed_raw(CoreData.comfy_emojis.monkas .. message)
	
		-- if memory.game_won then
		--		 game.print({'chronosphere.message_game_won_restart'}, {r=0.98, g=0.66, b=0.22})
		-- end
	end


	Public.reset_crew_and_enemy_force(id)

	local lobby = game.surfaces[CoreData.lobby_surface_name]
	for _, player in pairs(players) do

		if player.character then
			player.character.destroy()
			player.character = nil
		end
		
		player.set_controller({type=defines.controllers.god})

		if player.get_associated_characters() and #player.get_associated_characters() == 1 then
			local char = player.get_associated_characters()[1]
			player.teleport(char.position, char.surface)

			player.set_controller({type=defines.controllers.character, character=char})
		else
			local pos = lobby.find_non_colliding_position('character', Common.lobby_spawnpoint, 32, 0.5) or Common.lobby_spawnpoint
			player.teleport(pos, lobby)
			player.create_character()
		end
	end

	if memory.sea_name then
		local seasurface = game.surfaces[memory.sea_name]
		if seasurface then game.delete_surface(seasurface) end
	end

	for i = 1, memory.hold_surface_count do
		local holdname = Hold.get_hold_surface_name(i)
		if game.surfaces[holdname] then
			game.delete_surface(game.surfaces[holdname])
		end
	end
	
	local cabinname = Cabin.get_cabin_surface_name()
	if game.surfaces[cabinname] then
		game.delete_surface(game.surfaces[cabinname])
	end

	local s = Hold.get_hold_surface(1)
	if s and s.valid then
		log('hold failed to delete')
	end

	s = Cabin.get_cabin_surface()
	if s and s.valid then
		log(inspect(cabinname))
		log('cabin failed to delete')
	end

	local crowsnestname = SurfacesCommon.encode_surface_name(memory.id, 0, Surfaces.enum.CROWSNEST, nil)
	if game.surfaces[crowsnestname] then game.delete_surface(game.surfaces[crowsnestname]) end

	for _, destination in pairs(memory.destinations) do
		if game.surfaces[destination.surface_name] then game.delete_surface(game.surfaces[destination.surface_name]) end
	end

	global_memory.crew_memories[id] = nil
	for k, idd in pairs(global_memory.crew_active_ids) do
		if idd == id then table.remove(global_memory.crew_active_ids, k) end
	end

	Lobby.place_starting_dock_showboat(id)
end


function Public.generate_new_crew_id()
	local global_memory = Memory.get_global_memory()

	if not global_memory.crew_memories[1] then return 1
	elseif not global_memory.crew_memories[2] then return 2
	elseif not global_memory.crew_memories[3] then return 3
	else return end
end


function Public.player_abandon_proposal(player)
	local global_memory = Memory.get_global_memory()

	for k, proposal in pairs(global_memory.crewproposals) do
		if proposal.endorserindices and proposal.endorserindices[1] and proposal.endorserindices[1] == player.index then
			proposal.endorserindices[k] = nil
			Common.notify_lobby('Proposal ' .. proposal.name .. ' retracted.')
			-- Server.to_discord_embed(message)
			global_memory.crewproposals[k] = nil
		end
	end
end

function Public.player_abandon_endorsements(player)
	local global_memory = Memory.get_global_memory()

	for k, proposal in pairs(global_memory.crewproposals) do
		for k2, i in pairs(proposal.endorserindices) do
			if i == player.index then
				proposal.endorserindices[k2] = nil
				if #proposal.endorserindices == 0 then
					Common.notify_lobby('Proposal ' .. proposal.name .. ' abandoned.')
					-- Server.to_discord_embed(message)
					global_memory.crewproposals[k] = nil
				end
			end
		end
	end
end


local crowsnest_delayed = Token.register(
	function(data)
		Crowsnest.crowsnest_surface_delayed_init()
	end
)
function Public.initialise_crowsnest()
	Crowsnest.create_crowsnest_surface()
	Task.set_timeout_in_ticks(5, crowsnest_delayed, {})
end

function Public.initialise_crowsnest_1()
	Crowsnest.create_crowsnest_surface()
end
function Public.initialise_crowsnest_2()
	Crowsnest.crowsnest_surface_delayed_init()
end


function Public.initialise_crew(accepted_proposal)
	local global_memory = Memory.get_global_memory()

	local new_id = Public.generate_new_crew_id()

	global_memory.crew_active_ids[#global_memory.crew_active_ids + 1] = new_id

	Memory.reset_crew_memory(new_id)
	Memory.set_working_id(new_id)

	local memory = Memory.get_crew_memory()

    local secs = Server.get_current_time()
	if not secs then secs = 0 end
	memory.secs_id = secs
	
	memory.id = new_id
	memory.force_name = string.format('crew-%03d', new_id)
	memory.enemy_force_name = string.format('enemy-%03d', new_id)

	memory.delayed_tasks = {}
	memory.buffered_tasks = {}
	memory.crewplayerindices = {}
	memory.spectatorplayerindices = {}
	memory.tempbanned_from_joining_data = {}
	memory.destinations = {}

	memory.hold_surface_count = 1

	memory.speed_boost_characters = {}

	memory.original_proposal = accepted_proposal
	memory.name = accepted_proposal.name
	memory.difficulty_option = accepted_proposal.difficulty_option
	memory.capacity_option = accepted_proposal.capacity_option
	-- memory.mode_option = accepted_proposal.mode_option
	memory.difficulty = CoreData.difficulty_options[accepted_proposal.difficulty_option].value
	memory.capacity = CoreData.capacity_options[accepted_proposal.capacity_option].value
	-- memory.mode = CoreData.mode_options[accepted_proposal.mode_option].value

	memory.destinationsvisited_indices = {}
	memory.stored_fuel = 8000

	memory.captain_accrued_time_data = {}

	memory.classes_table = {}
	memory.officers_table = {}
	memory.spare_classes = {}

	memory.healthbars = {}
	memory.overworld_krakens = {}
	memory.kraken_stream_registrations = {}
	
	memory.overworldx = 0
	memory.overworldy = 0

	memory.seaname = SurfacesCommon.encode_surface_name(memory.id, 0, SurfacesCommon.enum.SEA, enum.DEFAULT)

	local surface = game.surfaces[CoreData.lobby_surface_name]
	memory.spawnpoint = Common.lobby_spawnpoint
	
	local crew_force = game.forces[string.format('crew-%03d', new_id)]
	crew_force.set_spawn_position(memory.spawnpoint, surface)
				
	local message = '[' .. accepted_proposal.name .. '] Launched.'
	Common.notify_game(message)
	Server.to_discord_embed_raw(CoreData.comfy_emojis.pogkot .. message .. ' Difficulty: ' .. CoreData.difficulty_options[memory.difficulty_option].text .. ', Capacity: ' .. CoreData.capacity_options[memory.capacity_option].text3 .. '.')
	game.surfaces[CoreData.lobby_surface_name].play_sound{path='utility/new_objective', volume_modifier=0.75}

	memory.boat = global_memory.lobby_boats[new_id]
	local boat = memory.boat

	boat.dockedposition = boat.position
	boat.speed = 0
	boat.cannonscount = 2
end


function Public.summon_crew(tickinterval)
	local memory = Memory.get_crew_memory()
	local boat = memory.boat

	local print = false
	for _, player in pairs(game.connected_players) do
		if player.surface and player.surface.valid and boat.surface_name and player.surface.name == boat.surface_name and (not Boats.on_boat(boat, player.position)) then
			player.teleport(memory.spawnpoint)
			print = true
		end
	end
	if print then 
		Common.notify_force(game.forces[memory.force_name], 'Crew summoned.')
	end
end


function Public.reset_crew_and_enemy_force(id)
	local crew_force = game.forces[string.format('crew-%03d', id)]
	local enemy_force = game.forces[string.format('enemy-%03d', id)]
	local ancient_friendly_force = game.forces[string.format('ancient-friendly-%03d', id)]
	local ancient_enemy_force = game.forces[string.format('ancient-hostile-%03d', id)]

	crew_force.reset()
	enemy_force.reset()
	ancient_friendly_force.reset()
	ancient_enemy_force.reset()

    ancient_enemy_force.set_turret_attack_modifier('gun-turret', 0.2)

	enemy_force.reset_evolution()
	for _, tech in pairs(crew_force.technologies) do 
		crew_force.set_saved_technology_progress(tech, 0)
	end
	local lobby = game.surfaces[CoreData.lobby_surface_name]
	crew_force.set_spawn_position(Common.lobby_spawnpoint, lobby)

	enemy_force.ai_controllable = true

	
		
	crew_force.set_friend('player', true)
	game.forces['player'].set_friend(crew_force, true)
	crew_force.set_friend(ancient_friendly_force, true)
	ancient_friendly_force.set_friend(crew_force, true)
	enemy_force.set_friend(ancient_friendly_force, true)
	ancient_friendly_force.set_friend(enemy_force, true)
	enemy_force.set_friend(ancient_enemy_force, true)
	ancient_enemy_force.set_friend(enemy_force, true)

	-- enemy_force.set_friend(environment_force, true)
	-- environment_force.set_friend(enemy_force, true)

	-- environment_force.set_friend(ancient_enemy_force, true)
	-- ancient_enemy_force.set_friend(environment_force, true)

	-- environment_force.set_friend(ancient_friendly_force, true)
	-- ancient_friendly_force.set_friend(environment_force, true)
	
	-- maybe make these dependent on map... it could be slower to mine on poor maps, so that players jump more often rather than getting every last drop
	crew_force.mining_drill_productivity_bonus = 1
	-- crew_force.mining_drill_productivity_bonus = 1.25
	crew_force.manual_mining_speed_modifier = 3
	crew_force.character_inventory_slots_bonus = 10
	crew_force.character_running_speed_modifier = Balance.base_extra_character_speed
	crew_force.laboratory_productivity_bonus = 0
	crew_force.ghost_time_to_live = 9 * 60 * 60

	for k, v in pairs(Balance.player_ammo_damage_modifiers()) do
		crew_force.set_ammo_damage_modifier(k, v)
	end
	for k, v in pairs(Balance.player_gun_speed_modifiers()) do
		crew_force.set_gun_speed_modifier(k, v)
	end
	for k, v in pairs(Balance.player_turret_attack_modifiers()) do
		crew_force.set_turret_attack_modifier(k, v)
	end

	crew_force.technologies['circuit-network'].researched = true
	crew_force.technologies['uranium-processing'].researched = true
	crew_force.technologies['kovarex-enrichment-process'].researched = true
	crew_force.technologies['gun-turret'].researched = true
	crew_force.technologies['electric-energy-distribution-1'].researched = true
	crew_force.technologies['electric-energy-distribution-2'].researched = true
	crew_force.technologies['advanced-material-processing'].researched = true
	crew_force.technologies['advanced-material-processing-2'].researched = true
	crew_force.technologies['solar-energy'].researched = true
	crew_force.technologies['inserter-capacity-bonus-1'].researched = true
	crew_force.technologies['inserter-capacity-bonus-2'].researched = true

	--@TRYING this out:
	crew_force.technologies['coal-liquefaction'].enabled = true
	crew_force.technologies['coal-liquefaction'].researched = true

	crew_force.technologies['automobilism'].enabled = false

	-- note: some of these are overwritten after tech researched!!!!!!! like pistol

	crew_force.recipes['pistol'].enabled = false

	-- these are redundant I think...?:
	crew_force.recipes['centrifuge'].enabled = false
	crew_force.recipes['flamethrower-turret'].enabled = false
	crew_force.recipes['locomotive'].enabled = false
	crew_force.recipes['car'].enabled = false
	crew_force.recipes['cargo-wagon'].enabled = false
	crew_force.recipes['rail'].enabled = true

	-- crew_force.recipes['underground-belt'].enabled = false
	-- crew_force.recipes['fast-underground-belt'].enabled = false
	-- crew_force.recipes['express-underground-belt'].enabled = false

	crew_force.technologies['land-mine'].enabled = false
	crew_force.technologies['landfill'].enabled = false
	crew_force.technologies['cliff-explosives'].enabled = false

	crew_force.technologies['rail-signals'].enabled = false

	crew_force.technologies['logistic-system'].enabled = false


	crew_force.technologies['tank'].enabled = false
	crew_force.technologies['rocketry'].enabled = false
	crew_force.technologies['artillery'].enabled = false
	crew_force.technologies['destroyer'].enabled = false
	crew_force.technologies['spidertron'].enabled = false
	crew_force.technologies['atomic-bomb'].enabled = false
	crew_force.technologies['explosive-rocketry'].enabled = false
	crew_force.technologies['artillery-shell-range-1'].enabled = false
	crew_force.technologies['artillery-shell-speed-1'].enabled = false
	crew_force.technologies['worker-robots-storage-1'].enabled = false
	crew_force.technologies['worker-robots-storage-2'].enabled = false
	crew_force.technologies['worker-robots-storage-3'].enabled = false
	crew_force.technologies['research-speed-1'].enabled = false
	crew_force.technologies['research-speed-2'].enabled = false
	crew_force.technologies['research-speed-3'].enabled = false
	crew_force.technologies['research-speed-4'].enabled = false
	crew_force.technologies['research-speed-5'].enabled = false
	crew_force.technologies['research-speed-6'].enabled = false
	crew_force.technologies['follower-robot-count-1'].enabled = false
	crew_force.technologies['follower-robot-count-2'].enabled = false
	crew_force.technologies['follower-robot-count-3'].enabled = false
	crew_force.technologies['follower-robot-count-4'].enabled = false
	crew_force.technologies['follower-robot-count-5'].enabled = false
	crew_force.technologies['follower-robot-count-6'].enabled = false
	crew_force.technologies['follower-robot-count-7'].enabled = false
	crew_force.technologies['inserter-capacity-bonus-3'].enabled = false
	crew_force.technologies['inserter-capacity-bonus-4'].enabled = false
	crew_force.technologies['inserter-capacity-bonus-5'].enabled = false
	crew_force.technologies['inserter-capacity-bonus-6'].enabled = false
	crew_force.technologies['inserter-capacity-bonus-7'].enabled = false
	crew_force.technologies['refined-flammables-3'].enabled = false
	crew_force.technologies['refined-flammables-4'].enabled = false
	crew_force.technologies['refined-flammables-5'].enabled = false
	crew_force.technologies['refined-flammables-6'].enabled = false

	crew_force.technologies['steel-axe'].enabled = false

	crew_force.technologies['concrete'].enabled = false
	crew_force.technologies['nuclear-power'].enabled = false

	crew_force.technologies['effect-transmission'].enabled = true

	crew_force.technologies['gate'].enabled = false

	crew_force.technologies['productivity-module-2'].enabled = false
	crew_force.technologies['productivity-module-3'].enabled = false
	crew_force.technologies['speed-module'].enabled = false
	crew_force.technologies['speed-module-2'].enabled = false
	crew_force.technologies['speed-module-3'].enabled = false
	crew_force.technologies['effectivity-module'].enabled = false
	crew_force.technologies['effectivity-module-2'].enabled = false
	crew_force.technologies['effectivity-module-3'].enabled = false
	crew_force.technologies['automation-3'].enabled = true
	crew_force.technologies['rocket-control-unit'].enabled = false
	crew_force.technologies['rocket-silo'].enabled = false
	crew_force.technologies['space-science-pack'].enabled = false
	crew_force.technologies['mining-productivity-4'].enabled = false
	crew_force.technologies['worker-robots-speed-6'].enabled = false
	crew_force.technologies['energy-weapons-damage-7'].enabled = false
	crew_force.technologies['physical-projectile-damage-7'].enabled = false
	crew_force.technologies['refined-flammables-7'].enabled = false
	crew_force.technologies['stronger-explosives-7'].enabled = false
	crew_force.technologies['logistics-3'].enabled = true
	crew_force.technologies['nuclear-fuel-reprocessing'].enabled = false

	crew_force.technologies['railway'].enabled = false
	crew_force.technologies['automated-rail-transportation'].enabled = false
	crew_force.technologies['braking-force-1'].enabled = false
	crew_force.technologies['braking-force-2'].enabled = false
	crew_force.technologies['braking-force-3'].enabled = false
	crew_force.technologies['braking-force-4'].enabled = false
	crew_force.technologies['braking-force-5'].enabled = false
	crew_force.technologies['braking-force-6'].enabled = false
	crew_force.technologies['braking-force-7'].enabled = false
	crew_force.technologies['fluid-wagon'].enabled = false

	crew_force.technologies['production-science-pack'].enabled = true
	crew_force.technologies['utility-science-pack'].enabled = false

	crew_force.technologies['modular-armor'].enabled = false
	crew_force.technologies['power-armor'].enabled = false
	crew_force.technologies['solar-panel-equipment'].enabled = false
	crew_force.technologies['personal-roboport-equipment'].enabled = false
	crew_force.technologies['personal-laser-defense-equipment'].enabled = false
	crew_force.technologies['night-vision-equipment'].enabled = false
	crew_force.technologies['energy-shield-equipment'].enabled = false
	crew_force.technologies['belt-immunity-equipment'].enabled = false
	crew_force.technologies['exoskeleton-equipment'].enabled = false
	crew_force.technologies['battery-equipment'].enabled = false
	crew_force.technologies['fusion-reactor-equipment'].enabled = false
	crew_force.technologies['power-armor-mk2'].enabled = false
	crew_force.technologies['energy-shield-mk2-equipment'].enabled = false
	crew_force.technologies['personal-roboport-mk2-equipment'].enabled = false
	crew_force.technologies['battery-mk2-equipment'].enabled = false
	crew_force.technologies['discharge-defense-equipment'].enabled = false

	crew_force.technologies['distractor'].enabled = false
	crew_force.technologies['military-4'].enabled = false
	crew_force.technologies['uranium-ammo'].enabled = false
end



return Public