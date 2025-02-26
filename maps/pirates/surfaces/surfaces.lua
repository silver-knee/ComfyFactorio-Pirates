
local Memory = require 'maps.pirates.memory'
local Math = require 'maps.pirates.math'
local Balance = require 'maps.pirates.balance'
local Common = require 'maps.pirates.common'
local CoreData = require 'maps.pirates.coredata'
local Utils = require 'maps.pirates.utils_local'
local inspect = require 'utils.inspect'.inspect
local Boats = require 'maps.pirates.structures.boats.boats'
local Lobby = require 'maps.pirates.surfaces.lobby'
local Dock = require 'maps.pirates.surfaces.dock'
local Hold = require 'maps.pirates.surfaces.hold'
local Cabin = require 'maps.pirates.surfaces.cabin'
local Sea = require 'maps.pirates.surfaces.sea.sea'
local Islands = require 'maps.pirates.surfaces.islands.islands'
local Crowsnest = require 'maps.pirates.surfaces.crowsnest'
local Quest = require 'maps.pirates.quest'
local Parrot = require 'maps.pirates.parrot'
local ShopMerchants = require 'maps.pirates.shop.merchants'
local SurfacesCommon = require 'maps.pirates.surfaces.common'

local Server = require 'utils.server'

local Public = {}
local enum = SurfacesCommon.enum
Public.enum = enum

Public[enum.SEA] = require 'maps.pirates.surfaces.sea.sea'
Public[enum.ISLAND] = require 'maps.pirates.surfaces.islands.islands'
Public[enum.DOCK] = require 'maps.pirates.surfaces.dock'
Public[enum.CROWSNEST] = require 'maps.pirates.surfaces.crowsnest'
Public[enum.LOBBY] = require 'maps.pirates.surfaces.lobby'
Public[enum.HOLD] = require 'maps.pirates.surfaces.hold'
Public[enum.CABIN] = require 'maps.pirates.surfaces.cabin'
Public[enum.CHANNEL] = require 'maps.pirates.surfaces.channel.channel'
Public['SurfacesCommon'] = require 'maps.pirates.surfaces.common'




function Public.initialise_destination(o)
	o = o or {}

	local memory = Memory.get_crew_memory()
	assert(memory.destinations, o.overworld_position)

	local scope = Public.get_scope(o)

	o.destination_index = #memory.destinations + 1 --assuming none are deleted
	memory.destinations[o.destination_index] = o

	o.dynamic_data = o.dynamic_data or {}
	o.static_params = o.static_params or Utils.deepcopy(Public.get_scope(o).Data.static_params_default)

	o.seed = o.seed or Math.random(1, 10000000)
	o.iconized_map = o.iconized_map or {}
	o.boat_extra_distance_from_shore = o.boat_extra_distance_from_shore or 0
	o.surface_name = o.surface_name or SurfacesCommon.encode_surface_name(memory.id, o.destination_index, o.type, o.subtype)

	o.dynamic_data.chunks_loaded = o.dynamic_data.chunks_loaded or {}

	if o.type == enum.ISLAND then
	
		o.init_boat_state = Boats.enum_state.APPROACHING
	
		Public.generate_detailed_island_data(o)

	elseif o.type == enum.DOCK then

		o.init_boat_state = Boats.enum_state.APPROACHING

		o.iconized_map_width = scope.Data.iconized_map_width
		o.iconized_map_height = scope.Data.iconized_map_height
	end

	return o
end


function Public.get_scope(destination)
	if destination.type then
		if destination.subtype then
			return Public[destination.type][destination.subtype]
		else
			return Public[destination.type]
		end
	else
		return {}
	end
end






function Public.on_surface_generation(destination)
	local memory = Memory.get_crew_memory()

	-- game.map_settings.pollution.enemy_attack_pollution_consumption_modifier = Balance.defaultai_attack_pollution_consumption_modifier()
		-- Event_functions.flamer_nerfs()

	if destination.type == enum.ISLAND then
		local subtype = destination.subtype

		destination.dynamic_data.rocketsilomaxhp = Balance.silo_max_hp
		destination.dynamic_data.rocketsilohp = Balance.silo_max_hp
		destination.dynamic_data.rocketsilochargedbools = {}
		destination.dynamic_data.rocketsiloenergyconsumed = 0
		destination.dynamic_data.rocketsiloenergyconsumedwithinlasthalfsecond = 0
		destination.dynamic_data.energychargedinsilosincelastcheck = 0
		destination.dynamic_data.silocharged = false
		destination.dynamic_data.rocketlaunched = false

		if subtype ~= Islands.enum.STANDARD and subtype ~= Islands.enum.STANDARD_VARIANT and subtype ~= Islands.enum.RADIOACTIVE and subtype ~= Islands.enum.RED_DESERT then
			destination.dynamic_data.hidden_ore_remaining_abstract = Utils.deepcopy(destination.static_params.abstract_ore_amounts)
		end
		destination.dynamic_data.wood_remaining = destination.static_params.starting_wood
		destination.dynamic_data.rock_material_remaining = destination.static_params.starting_rock_material
		destination.dynamic_data.treasure_remaining = destination.static_params.starting_treasure
		destination.dynamic_data.ore_types_spawned = {}

		destination.dynamic_data.buried_treasure = {}
	
	elseif destination.type == enum.DOCK then

	end
end


function Public.destination_on_collide(destination)
	local memory = Memory.get_crew_memory()

	local name = destination.static_params.name and destination.static_params.name or 'NameNotFound'
	local message = '[' .. memory.name .. '] Loading destination ' .. (memory.destinationsvisited_indices and (#memory.destinationsvisited_indices + 1) or 0) .. ', ' .. name .. '.'
	Common.notify_game(message)

	if destination.type ~= Public.enum.DOCK then
		local index = destination.destination_index
		Crowsnest.paint_around_destination(index, CoreData.overworld_loading_tile)
	end

	if destination and destination.static_params and destination.static_params.cost_to_leave then
		local replace = {}
		for item, count in pairs(destination.static_params.cost_to_leave) do
			if item == 'uranium-235' then
				replace[item] = count
			else
				replace[item] = Math.ceil(count * Public.cost_to_leave_multiplier())
			end
		end
		destination.static_params.cost_to_leave = replace
	end

	if destination.type == Public.enum.ISLAND then
		local index = destination.destination_index
		Crowsnest.paint_around_destination(index, CoreData.overworld_loading_tile)

		-- local scheduled_raft_raids
		-- local playercount = Common.activecrewcount()
		-- local max_evo = 0.85
		-- if Common.difficulty() < 1 then max_evo = 0.68 end
		-- if memory.overworldx > 200 then
		-- 	scheduled_raft_raids = {}
		-- 	local times = {600, 360, 215, 210, 120, 30, 10, 5}
		-- 	for i = 1, #times do
		-- 		local t = times[i]
		-- 		if Math.random(7) == 1 and #scheduled_raft_raids < 6 then
		-- 			scheduled_raft_raids[#scheduled_raft_raids + 1] = {timeinseconds = t, max_evo = max_evo}
		-- 			-- scheduled_raft_raids[#scheduled_raft_raids + 1] = {timeinseconds = t, max_bonus_evolution = 0.52}
		-- 		end
		-- 	end
		-- elseif memory.overworldx == 200 then
		-- 	local times
		-- 	if playercount <= 2 then
		-- 		times = {1, 5, 10, 15}
		-- 	elseif playercount <= 7 then
		-- 		times = {1, 5, 10, 15, 20}
		-- 	elseif playercount <= 15 then
		-- 		times = {1, 5, 10, 15, 20, 25}
		-- 	else
		-- 		times = {1, 5, 10, 15, 20, 25, 30, 35}
		-- 	end
		-- 	scheduled_raft_raids = {}
		-- 	for _, t in pairs(times) do
		-- 		-- scheduled_raft_raids[#scheduled_raft_raids + 1] = {timeinseconds = t, max_bonus_evolution = 0.62}
		-- 		scheduled_raft_raids[#scheduled_raft_raids + 1] = {timeinseconds = t, max_evo = max_evo}
		-- 	end
		-- end
		-- destination.static_params.scheduled_raft_raids = scheduled_raft_raids
	end

	if memory.overworldx == 40*4 then Parrot.parrot_boats_warning() end
	if memory.overworldx == 600 then
		Parrot.parrot_radioactive_tip_1()
	elseif memory.overworldx == 800 then
		Parrot.parrot_800_tip()
	end
end



function Public.destination_on_arrival(destination)
	local memory = Memory.get_crew_memory()

	-- game.map_settings.pollution.enemy_attack_pollution_consumption_modifier = Balance.defaultai_attack_pollution_consumption_modifier()
		-- Event_functions.flamer_nerfs()

	memory.floating_pollution = 0

	if destination.type == enum.ISLAND then

		destination.dynamic_data.rocketsiloenergyneeded = Balance.silo_energy_needed_MJ() * 1000000
		destination.dynamic_data.rocketcoalreward = Balance.launch_fuel_reward()

		if destination.subtype == Islands.enum.RADIOACTIVE then
			destination.dynamic_data.time_remaining = -1
		else
			destination.dynamic_data.time_remaining = Math.ceil(Balance.max_time_on_island())
		end

		if destination.subtype ~= Islands.enum.FIRST and destination.subtype ~= Islands.enum.RADIOACTIVE then
			Quest.initialise_random_quest()
		else
			-- if _DEBUG then
			-- 	Quest.initialise_random_quest()
			-- end
		end

		game.forces[memory.enemy_force_name].reset_evolution()
		local base_evo = Balance.base_evolution()
		game.forces[memory.enemy_force_name].evolution_factor = base_evo
		destination.dynamic_data.evolution_accrued_leagues = base_evo
		destination.dynamic_data.evolution_accrued_time = 0
		destination.dynamic_data.evolution_accrued_nests = 0
		destination.dynamic_data.evolution_accrued_silo = 0

		memory.scripted_biters = {}
		memory.scripted_unit_groups = {}
		memory.floating_pollution = 0

		if destination.subtype == Islands.enum.RADIOACTIVE then
			Islands[Islands.enum.RADIOACTIVE].spawn_structures()
		end

		if destination and destination.surface_name and game.surfaces[destination.surface_name] and game.surfaces[destination.surface_name].valid and (not (destination.dynamic_data and destination.dynamic_data.initial_spawner_count)) then
			--Note: This gives the wrong answer on the first island. Because the terrain hasn't finished generating yet.
			destination.dynamic_data.initial_spawner_count = Common.spawner_count(game.surfaces[destination.surface_name])
		end

		-- -- invulnerable bases on islands 21-25
		-- if memory.overworldx >= 21 and memory.overworldx < 25 then
		-- 	local surface = game.surfaces[destination.surface_name]
		-- 	if not (surface and surface.valid) then return end
		-- 	local spawners = surface.find_entities_filtered({type = 'unit-spawner', force = memory.enemy_force_name})
		-- 	for _, s in pairs(spawners) do
		-- 		s.destructible = false
		-- 	end
		-- end
	
	elseif destination.type == enum.DOCK then

		-- -- kick players out of crow's nest
		-- local crowsnestname = SurfacesCommon.encode_surface_name(memory.id, 0, enum.CROWSNEST, nil)
		-- for _, player in pairs(game.connected_players) do
		-- 	if player.surface.name == crowsnestname then
		-- 		Public.player_exit_crows_nest(player, {x = 5, y = 0})
		-- 	end
		-- end

		-- heal all cannons:
		local cannons = game.surfaces[destination.surface_name].find_entities_filtered({type = 'artillery-turret'})
		for _, c in pairs(cannons) do
			c.health = c.prototype.max_health
		end
	end

	local name = destination.static_params.name and destination.static_params.name or 'NameNotFound'
	local message = 'Approaching destination ' .. (memory.destinationsvisited_indices and #memory.destinationsvisited_indices or 0) .. ', ' .. name .. '.'
	if not (#memory.destinationsvisited_indices and #memory.destinationsvisited_indices == 1) then --don't need to notify for the first island
		Server.to_discord_embed_raw((destination.static_params.discord_emoji or CoreData.comfy_emojis.wut) .. '[' .. memory.name .. '] ' .. message)
	end
	if destination.static_params.name == 'Dock' then
		message = message .. ' ' .. 'Extra trades are available in the shop.'
	end
	Common.notify_force(game.forces[memory.force_name], message)

	if destination.type == enum.ISLAND then

		local points_to_avoid = {}

		if destination.subtype ~= Islands.enum.RADIOACTIVE then
			local silo_position = Islands.spawn_silo_setup()
			points_to_avoid[#points_to_avoid + 1] = {x = silo_position.x, y = silo_position.y, r = 22}
		end

		Islands.spawn_ores_on_shorehit(destination, points_to_avoid)

		if memory.overworldx >= Balance.covered_first_appears_at or _DEBUG then
			local covered = Islands.spawn_covered(destination, points_to_avoid)
			points_to_avoid[#points_to_avoid + 1] = {x = covered.x, y = covered.y, r = 25}
		end
		
		Islands.spawn_treasure_maps(destination, points_to_avoid)
		Islands.spawn_ghosts(destination, points_to_avoid)
	end
end




function Public.destination_on_crewboat_hits_shore(destination)
	local memory = Memory.get_crew_memory()
	local boat = memory.boat

	destination.dynamic_data.timeratlandingtime = Common.current_destination().dynamic_data.timer

	Boats.place_landingtrack(boat, CoreData.landing_tile)

	Boats.place_boat(boat, CoreData.static_boat_floor, false, false)

	if destination.type == enum.ISLAND then

		if memory.overworldx == 0 then
			Parrot.parrot_0()
		elseif memory.overworldx == 80 then
			Parrot.parrot_80()
		end

		if destination.subtype == Islands.enum.RADIOACTIVE then
			-- replace all miners, so that they sit on uranium properly:
			local surface = game.surfaces[destination.surface_name]
			local miners = surface.find_entities_filtered({name = 'electric-mining-drill'})
			for _, m in pairs(miners) do
				local direction = m.direction
				local position = m.position
				m.destroy()
				surface.create_entity{name = 'electric-mining-drill', direction = direction, position = position}
			end
			
			Parrot.parrot_radioactive_tip_2()
		end

		if memory.merchant_ships_unlocked or _DEBUG then
			Islands.spawn_merchant_ship(destination)

			ShopMerchants.generate_merchant_trades(destination.dynamic_data.merchant_market)
		end
	end
end







function Public.generate_detailed_island_data(destination)

	local scope = Public.get_scope(destination)

	local frame_width = scope.Data.terraingen_frame_width
	local frame_height = scope.Data.terraingen_frame_height
	local boat_extra_distance_from_shore = destination.boat_extra_distance_from_shore

	-- scale 1:32
	local chunks_horizontal = 2 * Math.floor(frame_width/64)
	local chunks_vertical = 2 * Math.floor(frame_height/64)

	local entities = {}
	local entitymap = {}
	local tiles = {}
	local tiles2 = {}
	local leftboundary, rightboundary, topboundary, bottomboundary = chunks_horizontal/2 + 1, -chunks_horizontal/2 - 1, chunks_vertical/2 + 1, -chunks_vertical/2 - 1 -- reversed, because we'll iterate

	-- local subtype = destination.subtype

	local terrain_fn = scope.terrain
	
	local noise_generator = Utils.noise_generator(scope.Data.noiseparams, destination.seed)

	for y = -chunks_vertical/2, chunks_vertical/2 - 1, 1 do
		for x = -chunks_horizontal/2, chunks_horizontal/2 - 1, 1 do
			local macroposition = {x = x + 0.5, y = y + 0.5}
			local chunk_frameposition_topleft = {x = x * 32, y = y * 32}

			-- average over the chunk
			local modalcounts = {}
			for y2 = 5, 27, 11 do
				for x2 = 5, 27, 11 do
					local p2 = {x = chunk_frameposition_topleft.x + x2, y = chunk_frameposition_topleft.y + y2}

					local tiles3, entities3 = {}, {}
					terrain_fn{p = p2, noise_generator = noise_generator, static_params = destination.static_params, tiles = tiles3, entities = entities3, decoratives = {}, seed = destination.seed}
					local tile = tiles3[1]
					if modalcounts[tile.name] then
						modalcounts[tile.name] = modalcounts[tile.name] + 1
					else
						modalcounts[tile.name] = 1
					end

					if y2 == 16 and x2 == 16 and #entities3 > 0 and entities3[1] and entities3[1].visible_on_overworld then
						entitymap[macroposition] = entities3[1].name
					end
				end
			end
			local modaltile, max = 'hazard-concrete-left', 0
			for k, v in pairs(modalcounts) do
				if v > max then
					modaltile, max = k, v
				end
			end
			tiles[#tiles + 1] = {name = modaltile, position = macroposition}

			if (not Utils.contains(CoreData.water_tile_names, modaltile)) then
				leftboundary, rightboundary, topboundary, bottomboundary = Math.min(leftboundary, x), Math.max(rightboundary, x + 1), Math.min(topboundary, y), Math.max(bottomboundary, y + 1)
			end
		end
	end

	leftboundary, rightboundary, topboundary, bottomboundary = leftboundary - 1, rightboundary + 1, topboundary - 1, bottomboundary + 1 --push out by one step to get some water

	-- construct image, and record where entities can be placed:
	local positions_free_to_hold_resources = {}
	for _, tile in pairs(tiles) do
		local x = tile.position.x
		local y = tile.position.y
		if tile.name ~= 'water' and x >= leftboundary and x <= rightboundary and y >= topboundary and y <= bottomboundary then --nil represents water
			--arrange image so that {0,0} is on the centre of the left edge:
			local p = {x = x - leftboundary, y = y - (topboundary + bottomboundary)/2}
			if (topboundary + bottomboundary)/2 % 1 ~= 0 then
				p.y = p.y + 0.5 --adjust so that tiles land on half-integer positions
			end

			tiles2[#tiles2 + 1] = {name = tile.name, position = p}

			if (not Utils.contains(CoreData.tiles_that_conflict_with_resource_layer, tile.name)) then
				
				local ename = entitymap[tile.position]
				if ename then
					entities[#entities + 1] = {name = ename, position = p}
				else
					if (p.x + 2) % 4 <= 2 and (p.y) % 4 <= 2 then --for the ingame minimap, the ore texture checker only colors these squares
						local nearby_es = {
							entitymap[{x = tile.position.x + 1, y = tile.position.y}],
							entitymap[{x = tile.position.x - 1, y = tile.position.y}],
							entitymap[{x = tile.position.x, y = tile.position.y + 1}],
							entitymap[{x = tile.position.x, y = tile.position.y - 1}],
						}
						if not (nearby_es[1] or nearby_es[2] or nearby_es[3] or nearby_es[4]) then
							positions_free_to_hold_resources[#positions_free_to_hold_resources + 1] = p
							-- if destination.destination_index == 3 then
							-- 	game.print(p)
							-- end
						end
					end
				end
			end
		end
	end

	if #positions_free_to_hold_resources > 0 then
		local orestoadd = {}
		for k, v in pairs(destination.static_params.abstract_ore_amounts) do
			local count = Math.ceil(v^(1/2))
			if k == 'crude-oil' then
				orestoadd[k] = {count = count, sizing_each = Common.oil_abstract_to_real(v)/count}
			else
				orestoadd[k] = {count = count, sizing_each = Common.ore_abstract_to_real(v)/count}
			end
		end
		for k, v in pairs(orestoadd) do
			for i = 1, v.count do
				if #positions_free_to_hold_resources > 0 then
					local random_index = Math.random(#positions_free_to_hold_resources)
					local p = positions_free_to_hold_resources[random_index]
			
					entities[#entities + 1] = {name = k, position = p, amount = v.sizing_each}
		
					for j = random_index, #positions_free_to_hold_resources - 1 do
						positions_free_to_hold_resources[j] = positions_free_to_hold_resources[j+1]
					end
					positions_free_to_hold_resources[#positions_free_to_hold_resources] = nil
				end
			end
		end
	end

	-- get more precise understanding of left-hand shore
	local xcorrection = 0
	for ystep = -10, 10, 10 do
		for xstep = 0,300,3 do
			local x = leftboundary * 32 + 16 + xstep
			local y = (topboundary*32 + bottomboundary*32)/2 + ystep
			local tiles3 = {}
			terrain_fn{p = {x = x, y = y}, noise_generator = noise_generator, static_params = destination.static_params, tiles = tiles3, entities = {}, decoratives = {}, seed = destination.seed}
			local tile = tiles3[1]
			if (not Utils.contains(CoreData.water_tile_names, tile.name)) then
				xcorrection = Math.max(xcorrection, xstep + Math.abs(ystep))
				break
			end
		end
	end
	-- if xcorrection == 0 then xcorrection = 300 end

	local iconwidth, iconheight = rightboundary - leftboundary, bottomboundary - topboundary
	iconwidth = iconwidth > 0 and iconwidth or 0 --make them 0 if negative
	iconheight = iconheight > 0 and iconheight or 0

	local extension_to_left = Math.ceil(Common.boat_default_starting_distance_from_shore + boat_extra_distance_from_shore + Common.mapedge_distance_from_boat_starting_position - xcorrection)

	local terraingen_coordinates_offset = {x = (leftboundary*32 + rightboundary*32)/2 - extension_to_left/2, y = (topboundary*32 + bottomboundary*32)/2}
	local width = rightboundary*32 - leftboundary*32 + extension_to_left
	local height = bottomboundary*32 - topboundary*32

	local deepwater_terraingenframe_xposition = leftboundary*32 - Common.deepwater_distance_from_leftmost_shore
	local islandcenter_position = {x = extension_to_left/2, y = 0}
	local deepwater_xposition = deepwater_terraingenframe_xposition - terraingen_coordinates_offset.x
	
	-- -- must ceil this, because if it's a half integer big things will teleport badly:
	-- local boat_starting_xposition = Math.ceil(- width/2 + Common.mapedge_distance_from_boat_starting_position)
	-- worse, must make this even due to rails:
	local boat_starting_xposition = 2*Math.ceil(
		(- width/2 + Common.mapedge_distance_from_boat_starting_position)/2
	)

	destination.static_params.terraingen_coordinates_offset = terraingen_coordinates_offset
	destination.static_params.width = width
	destination.static_params.height = height

	destination.static_params.islandcenter_position = islandcenter_position
	destination.static_params.deepwater_xposition = deepwater_xposition
	destination.static_params.deepwater_terraingenframe_xposition = deepwater_terraingenframe_xposition
	destination.static_params.boat_starting_xposition = boat_starting_xposition

	destination.iconized_map.tiles = tiles2
	destination.iconized_map.entities = entities
	
	destination.iconized_map_width = iconwidth
	destination.iconized_map_height = iconheight
end




function Public.create_surface(destination)

	local surface_name = destination.surface_name
	if game.surfaces[surface_name] then return end

	-- maybe can set width and height to be 0 here? if so, will need to change references to map_gen_settings.width elsewhere in code
	-- local mgs = Utils.deepcopy(Common.default_map_gen_settings(
	-- 	self.static_params.width or 512,
	-- 	self.static_params.height or 512,
	-- 	self.seed or Math.random(1, 1000000)
	-- ))

	local mgs = Utils.deepcopy(Common.default_map_gen_settings(
		Math.max(0,destination.static_params.width) or 128,
		Math.max(0,destination.static_params.height) or 128,
		destination.seed or Math.random(1, 1000000)
	))

	--todo: put into static_params

	mgs.autoplace_settings.decorative.treat_missing_as_default = destination.static_params.default_decoratives

	local surface = game.create_surface(surface_name, mgs)

	surface.solar_power_multiplier = destination.static_params.solar_power_multiplier or 1
	surface.show_clouds = destination.static_params.clouds or false
	surface.min_brightness = destination.static_params.min_brightness or 0
	surface.brightness_visual_weights = destination.static_params.brightness_visual_weights or {1, 1, 1}
	surface.daytime = destination.static_params.starting_time_of_day or 0
	
	local daynightcycletype = destination.static_params.daynightcycletype or 1

	local ticksperday = CoreData.daynightcycle_types[daynightcycletype].ticksperday or 0

	if ticksperday == 0 then
		surface.freeze_daytime = true
		ticksperday = ticksperday + 1 -- avoid divide by zero
	else
		surface.freeze_daytime = false
	end
	surface.ticks_per_day = ticksperday

	Public.on_surface_generation(destination)
end









function Public.clean_up(destination)
	local memory = Memory.get_crew_memory()

	local oldsurface = game.surfaces[destination.surface_name]

	if not (oldsurface and oldsurface.valid) then return end

	-- assuming sea is always default subtype:
	local seasurface = game.surfaces[memory.sea_name]
	
	Quest.try_resolve_quest()
	destination.dynamic_data.quest_type = nil
	destination.dynamic_data.quest_reward = nil
	destination.dynamic_data.quest_progress = nil
	destination.dynamic_data.quest_progressneeded = nil
	destination.dynamic_data.quest_complete = nil

	-- handle players that were left on the island
	-- if there is more than one crew on a surface, this will need to be generalised
	for _, player in pairs(game.connected_players) do
		if (player.surface == oldsurface) then
			if player.character and player.character.valid then player.character.die(game.forces[memory.force_name]) end
			player.teleport(memory.spawnpoint, seasurface)
		end
	end

	destination.dynamic_data = {}

	memory.scripted_biters = nil
	memory.scripted_unit_groups = nil
	memory.floating_pollution = nil

	if memory.enemy_force_name then
		local ef = game.forces[memory.enemy_force_name]
		if ef and ef.valid then
			game.forces[memory.enemy_force_name].reset_evolution()
			local base_evo = Balance.base_evolution()
			game.forces[memory.enemy_force_name].evolution_factor = base_evo
		end
	end
	
	game.delete_surface(oldsurface)
end








-- function Public.crowsnest_init_destinations()
-- 	local memory = Memory.get_crew_memory()
-- 	local tiles, entities = {}, {}

-- 	Overworld.try_overworld_move{x = 0, y = 0}

-- 	-- for _, destination_data in pairs(memory.destinations) do
-- 	-- 	local iconized_map = SurfacesCommon.fetch_iconized_map(destination_data.destination_index)

-- 	-- 	for _, t in pairs(iconized_map.tiles) do
-- 	-- 		local x = Crowsnest.platformrightmostedge + destination_data.overworld_position.x + t.position.x
-- 	-- 		local y = destination_data.overworld_position.y + t.position.y

-- 	-- 		if Math.abs(x) < Crowsnest.Data.width/2 and Math.abs(y) < Crowsnest.Data.height/2 then
-- 	-- 			tiles[#tiles+1] = {name = t.name, position = {x = x, y = y}}
-- 	-- 		end
-- 	-- 	end

-- 	-- 	for _, e in pairs(iconized_map.entities) do
-- 	-- 		local x = Crowsnest.platformrightmostedge + destination_data.overworld_position.x + e.position.x
-- 	-- 		local y = destination_data.overworld_position.y + e.position.y
-- 	-- 		if Math.abs(x) < Crowsnest.Data.width/2 then
-- 	-- 			local e2 = Utils.deepcopy(e)
-- 	-- 			e2.position = {x = x, y = y}
-- 	-- 			entities[#entities+1] = e2
-- 	-- 		end
-- 	-- 	end
-- 	-- end
-- 	-- Crowsnest.update_surface(tiles, entities)
-- end


function Public.player_goto_crows_nest(player, player_relative_pos)
	local memory = Memory.get_crew_memory()

	local surface = game.surfaces[SurfacesCommon.encode_surface_name(memory.id, 0, enum.CROWSNEST, nil)]
	
	local carpos
	if player_relative_pos.x < 0 then
		carpos = {x = -2.29687, y = 0}
	else
		carpos = {x = 3.29687, y = 0}
	end

	local newpos = {x = memory.overworldx + carpos.x - player_relative_pos.x, y = memory.overworldy + carpos.y + player_relative_pos.y}

	local newpos2 = surface.find_non_colliding_position('character', newpos, 5, 0.2) or newpos

	if newpos2 then player.teleport(newpos2, surface) end

	-- player.minimap_enabled = false
end


function Public.player_exit_crows_nest(player, player_relative_pos)
	local memory = Memory.get_crew_memory()
	local surface

	if memory.boat and (memory.boat.state == Boats.enum_state.ATSEA_SAILING or memory.boat.state == Boats.enum_state.ATSEA_LOADING_MAP) then
		surface = game.surfaces[SurfacesCommon.encode_surface_name(memory.id, 0, Public.enum.SEA, Public.Sea.enum.DEFAULT)]
	else
		surface = game.surfaces[Common.current_destination().surface_name]
	end

	local carpos
	if player_relative_pos.x > 0 then
		carpos = Boats.get_scope(memory.boat).Data.entercrowsnest_cars.right
	else
		carpos = Boats.get_scope(memory.boat).Data.entercrowsnest_cars.left
	end
	local newpos = {x = memory.boat.position.x + carpos.x - player_relative_pos.x, y = memory.boat.position.y + carpos.y + player_relative_pos.y}

	local newpos2 = surface.find_non_colliding_position('character', newpos, 10, 0.2) or newpos

	if newpos2 then player.teleport(newpos2, surface) end

	-- player.minimap_enabled = true
end


function Public.player_goto_hold(player, relative_pos, nth)
	local memory = Memory.get_crew_memory()

	local surface = Hold.get_hold_surface(nth)
	
	local newpos = {x = Hold.Data.loco_offset.x + 1 + relative_pos.x, y = Hold.Data.loco_offset.y + relative_pos.y}

	local newpos2 = surface.find_non_colliding_position('character', newpos, 5, 0.2) or newpos

	if newpos2 then player.teleport(newpos2, surface) end
end


function Public.player_exit_hold(player, relative_pos)
	local memory = Memory.get_crew_memory()
	local surface

	if memory.boat and (memory.boat.state == Boats.enum_state.ATSEA_SAILING or memory.boat.state == Boats.enum_state.ATSEA_LOADING_MAP) then
		surface = game.surfaces[SurfacesCommon.encode_surface_name(memory.id, 0, Public.enum.SEA, Public.Sea.enum.DEFAULT)]
	else
		surface = game.surfaces[Common.current_destination().surface_name]
	end

	local locopos = Boats.get_scope(memory.boat).Data.loco_pos
	local newpos = {x = memory.boat.position.x + locopos.x + relative_pos.x, y = memory.boat.position.y + locopos.y + relative_pos.y}

	local newpos2 = surface.find_non_colliding_position('character', newpos, 10, 0.2) or newpos

	if newpos2 then player.teleport(newpos2, surface) end
end



function Public.player_goto_cabin(player, relative_pos)
	local memory = Memory.get_crew_memory()

	local surface = Cabin.get_cabin_surface()
	
	local newpos = {x = Cabin.Data.car_pos.x - relative_pos.x, y = Cabin.Data.car_pos.y + relative_pos.y}

	local newpos2 = surface.find_non_colliding_position('character', newpos, 5, 0.2) or newpos

	if newpos2 then player.teleport(newpos2, surface) end
end


function Public.player_exit_cabin(player, relative_pos)
	local memory = Memory.get_crew_memory()
	local surface

	if memory.boat and (memory.boat.state == Boats.enum_state.ATSEA_SAILING or memory.boat.state == Boats.enum_state.ATSEA_LOADING_MAP) then
		surface = game.surfaces[SurfacesCommon.encode_surface_name(memory.id, 0, Public.enum.SEA, Public.Sea.enum.DEFAULT)]
	else
		surface = game.surfaces[Common.current_destination().surface_name]
	end

	local carpos = Boats.get_scope(memory.boat).Data.cabin_car
	local newpos = {x = memory.boat.position.x + carpos.x - relative_pos.x, y = memory.boat.position.y + carpos.y + relative_pos.y}

	local newpos2 = surface.find_non_colliding_position('character', newpos, 10, 0.2) or newpos

	if newpos2 then player.teleport(newpos2, surface) end
end







return Public