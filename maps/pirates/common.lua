
local Math = require 'maps.pirates.math'
local Utils = require 'maps.pirates.utils_local'
local CoreData = require 'maps.pirates.coredata'
local Memory = require 'maps.pirates.memory'
local inspect = require 'utils.inspect'.inspect
local simplex_noise = require 'utils.simplex_noise'.d2
local perlin_noise = require 'utils.perlin_noise'

local Public = {}

Public.active_crews_cap = 2
Public.minimum_capacity_slider_value = 1

Public.boat_steps_at_a_time = 1

Public.seconds_after_landing_to_enable_AI = 45

Public.boat_default_starting_distance_from_shore = 22
-- Public.mapedge_distance_from_boat_starting_position = 136
Public.mapedge_distance_from_boat_starting_position = 272 -- to accommodate horseshoe
Public.deepwater_distance_from_leftmost_shore = 32
Public.lobby_spawnpoint = {x = -72, y = -8}

Public.fraction_of_map_loaded_atsea = 1
Public.map_loading_ticks_atsea = 70 * 60
Public.map_loading_ticks_onisland = 2 * 60 * 60
Public.loading_interval = 5

Public.minimum_ore_placed_per_tile = 10

Public.total_max_biters = 2048

Public.ban_from_rejoining_crew_ticks = 45 * 60 --to prevent observing map and rejoining

Public.afk_time = 60 * 60 * 4.5
Public.afk_warning_time = 60 * 60 * 4

-- Public.mainshop_rate_limit_ticks = 11


function Public.ore_real_to_abstract(amount)
	return amount/1800
end
function Public.ore_abstract_to_real(amount)
	return Math.ceil(amount*1800)
end

-- big buff, to crush recurring problem. hopefully rebalance down from here?:
function Public.oil_real_to_abstract(amount)
	return amount/(75000)
end
function Public.oil_abstract_to_real(amount)
	return Math.ceil(amount*75000)
end

function Public.difficulty() return Memory.get_crew_memory().difficulty end
function Public.capacity() return Memory.get_crew_memory().capacity end
-- function Public.mode() return Memory.get_crew_memory().mode end
function Public.overworldx() return Memory.get_crew_memory().overworldx end
function Public.game_completion_progress() return Public.overworldx()/CoreData.victory_x end
function Public.capacity_scale()
	local capacity = Public.capacity()
	if not capacity then --e.g. for EE wattage on boats not owned by a crew
		return 1
	elseif capacity <= 1 then
		return 0.5
	elseif capacity <= 4 then
		return 0.75
	elseif capacity <= 8 then
		return 1
	elseif capacity <= 16 then
		return 1.3
	else
		return 1.5
	end
end

function Public.activecrewcount()
	local global_memory = Memory.get_global_memory()
	local memory = Memory.get_crew_memory()
	if memory.id == 0 then return 0 end

	local count = 0
	for _, id in pairs(memory.crewplayerindices) do
		local player = game.players[id]
		if player and player.valid and not Utils.contains(global_memory.afk_player_indices, player.index) then
			count = count + 1
		end
	end

	return count
end


function Public.notify_game(message, color_override)
	color_override = color_override or CoreData.colors.notify_game
	game.print('>> ' .. message, color_override)
end

function Public.notify_force(force, message, color_override)
	color_override = color_override or CoreData.colors.notify_force
	force.print('>> ' .. message, color_override)
end

function Public.notify_force_light(force, message, color_override)
	color_override = color_override or CoreData.colors.notify_force_light
	force.print('>> ' .. message, color_override)
end

function Public.notify_lobby(message, color_override)
	color_override = color_override or CoreData.colors.notify_lobby
	game.forces['player'].print('>> ' .. message, color_override)
end

function Public.notify_player(player, message, color_override)
	color_override = color_override or CoreData.colors.notify_player
	player.print('>> ' .. message, color_override)
end

function Public.parrot_speak(force, message)
	force.print('Parrot: ' .. message, CoreData.colors.parrot)
end

function Public.parrot_whisper(player, message)
	player.print('Parrot (whisper): ' .. message, CoreData.colors.parrot)
end


function Public.flying_text(surface, position, text)
	surface.create_entity(
		{
			name = 'flying-text',
			position = {position.x - 0.7, position.y - 3.05},
			text = text,
		}
	)
end


function Public.flying_text_small(surface, position, text)
	surface.create_entity(
		{
			name = 'flying-text',
			position = {position.x - 0.06, position.y - 1.5},
			text = text,
		}
	)
end




function Public.give(player, stacks, spill_position, spill_surface)
	-- stack elements of form {name = '', count = '', color = {r = , g = , b = }}
	-- to just spill on the ground, pass player and nill and give a position and surface directly
	spill_position = spill_position or player.position
	spill_surface = spill_surface or player.surface

	local text1 = ''
	local text2 = ''

	local stacks2 = stacks
	table.sort(stacks2, function(a,b) return a.name < b.name end)

	if not (spill_surface and spill_surface.valid) then return end
	local inv

	if player then
		inv = player.get_inventory(defines.inventory.character_main)
		if not inv then return end
	end

	for j = 1, #stacks2 do
		local stack = stacks2[j]
		local itemname, itemcount, flying_text_color = stack.name, stack.count or 1, stack.color or (CoreData.colors[stack.name] or {r = 1, g = 1, b = 1})
		local itemcount_remember = itemcount
	
		if not itemname then return end

		if itemcount > 0 then
			if player then
				local a = inv.insert{name = itemname, count = itemcount}
				itemcount = itemcount - a
				if itemcount >= 50 then
					for i = 1, Math.floor(itemcount / 50), 1 do
						local e = spill_surface.create_entity{name = 'item-on-ground', position = spill_position, stack = {name = itemname, count = 50}}
						if e and e.valid then
							e.to_be_looted = true
						end
						itemcount = itemcount - 50
					end
				end
				if itemcount > 0 then
					if itemcount < 5 then
						spill_surface.spill_item_stack(spill_position, {name = itemname, count = itemcount}, true)
					else
						local e = spill_surface.create_entity{name = 'item-on-ground', position = spill_position, stack = {name = itemname, count = itemcount}}
						if e and e.valid then
							e.to_be_looted = true
						end
					end
				end
			else
				local e = spill_surface.create_entity{name = 'item-on-ground', position = spill_position, stack = {name = itemname, count = itemcount}}
				if e and e.valid then
					e.to_be_looted = true
				end
			end
		end

		text1 = text1 .. '[color=1,1,1]'
		if itemcount_remember > 0 then
			text1 = text1 .. '+'
			text1 = text1 .. itemcount_remember .. '[/color] [item=' .. itemname .. ']'
		else
			text1 = text1 .. '-'
			text1 = text1 .. -itemcount_remember .. '[/color] [item=' .. itemname .. ']'
		end

		if inv then
			if #stacks2 > 1 then
				text2 = text2 .. '[color=' .. flying_text_color.r .. ',' .. flying_text_color.g .. ',' .. flying_text_color.b .. ']' .. inv.get_item_count(itemname) .. '[/color]'
			else
				text2 = '[color=' .. flying_text_color.r .. ',' .. flying_text_color.g .. ',' .. flying_text_color.b .. '](' .. inv.get_item_count(itemname) .. ')[/color]'
			end
			if j < #stacks2 then
				text2 = text2 .. ', '
			end
		end

		if j < #stacks2 then
			text1 = text1 .. ', '
		end
	end

	if text2 ~= '' then
		if #stacks2 > 1 then
			text2 = '(' .. text2 .. ')'
		end
		Public.flying_text(spill_surface, spill_position, text1 .. ' [font=count-font]' .. text2 .. '[/font]')
	else
		Public.flying_text(spill_surface, spill_position, text1)
	end
end



function Public.current_destination()
	local memory = Memory.get_crew_memory()
	
	if memory.currentdestination_index then
		return memory.destinations[memory.currentdestination_index]
	else
		return CoreData.fallthrough_destination
	end
end


function Public.query_sufficient_resources_to_leave()
	local memory = Memory.get_crew_memory()
	local boat = memory.boat
	local destination = Public.current_destination()
	if not (boat and destination) then return end

	local cost = destination.static_params.cost_to_leave
	if not cost then return true end

	local sufficient = true
	for name, count in pairs(cost) do
		local stored = (memory.boat.stored_resources and memory.boat.stored_resources[name]) or 0
		if stored < count then
			sufficient = false
		end
	end

	return sufficient
end




function Public.update_boat_stored_resources()
	local memory = Memory.get_crew_memory()
	local boat = memory.boat
	if not memory.boat.stored_resources then return end
	local input_chests = boat.input_chests

	if not input_chests then return end
	
	for i, chest in ipairs(input_chests) do
		if i>1 and CoreData.cost_items[i-1] then
			local inv = chest.get_inventory(defines.inventory.chest)
			local contents = inv.get_contents()
	
			local item_type = CoreData.cost_items[i-1].name
			local count = contents[item_type] or 0
	
			memory.boat.stored_resources[item_type] = count
		end
	end
end



function Public.spend_stored_resources(to_spend)
	to_spend = to_spend or {}
	local memory = Memory.get_crew_memory()
	local boat = memory.boat
	if not memory.boat.stored_resources then return end
	local input_chests = boat.input_chests

	if not input_chests then return end
	
	for i, chest in ipairs(input_chests) do
		if i>1 then
			local inv = chest.get_inventory(defines.inventory.chest)
			local item_type = CoreData.cost_items[i-1].name
			local to_spend_i = to_spend[item_type] or 0
	
			if to_spend_i > 0 then
				inv.remove{name = item_type, count = to_spend_i}
			end
		end
	end

	Public.update_boat_stored_resources()
end


function Public.new_healthbar(id, text, target_entity, max_health, health, size)
	health = health or max_health
	size = size or 0.5
	text = text or false

	local memory = Memory.get_crew_memory()

	local render1 = rendering.draw_sprite(
		{
			sprite = 'virtual-signal/signal-white',
			tint = {0, 200, 0},
			x_scale = size * 15,
			y_scale = size,
			render_layer = 'light-effect',
			target = target_entity,
			target_offset = {0, -2.5},
			surface = target_entity.surface,
		}
	)
	local render2
	if text then
		render2 = rendering.draw_text(
		{
			color = {255, 255, 255},
			scale = 2,
			render_layer = 'light-effect',
			target = target_entity,
			target_offset = {0, -4},
			surface = target_entity.surface,
			alignment = 'center'
		}
	)
	end

	local new_healthbar = {
		health = max_health,
		max_health = max_health,
		render1 = render1,
		render2 = render2,
		id = id,
	}

	memory.healthbars[target_entity.unit_number] = new_healthbar

	Public.update_healthbar_rendering(new_healthbar, health)

	return new_healthbar
end

function Public.update_healthbar_rendering(new_healthbar, health)
	local max_health = new_healthbar.max_health
	local render1 = new_healthbar.render1
	local render2 = new_healthbar.render2

	if health > 0 then
		local m = health / max_health
		local x_scale = rendering.get_y_scale(render1) * 15
		rendering.set_x_scale(render1, x_scale * m)
		rendering.set_color(render1, {Math.floor(255 - 255 * m), Math.floor(200 * m), 0})
	
		if render2 then
			rendering.set_text(render2, string.format('HP: %d/%d',Math.ceil(health),Math.ceil(max_health)))
		end
	else
		rendering.destroy(render1)
		if render2 then
			rendering.destroy(render2)
		end
	end
end

function Public.spawner_count(surface)
	local memory = Memory.get_crew_memory()
	
	local spawners = surface.find_entities_filtered({type = 'unit-spawner', force = memory.enemy_force_name})
	local spawnerscount = #spawners or 0
	return spawnerscount
end



function Public.create_poison_clouds(surface, position)

    local random_angles = {Math.rad(Math.random(359)), Math.rad(Math.random(359))}

	surface.create_entity({name = 'poison-cloud', position = {x = position.x, y = position.y}})
	surface.create_entity({name = 'poison-cloud', position = {x = position.x + 12 * Math.cos(random_angles[1]), y = position.y + 12 * Math.sin(random_angles[1])}})
	surface.create_entity({name = 'poison-cloud', position = {x = position.x + 12 * Math.cos(random_angles[2]), y = position.y + 12 * Math.sin(random_angles[2])}})
end


function Public.crew_get_crew_members()
	local memory = Memory.get_crew_memory()
	if memory.id == 0 then return {} end

	local playerlist = {}
	for _, id in pairs(memory.crewplayerindices) do
		local player = game.players[id]
		if player and player.valid then playerlist[#playerlist + 1] = player end
	end
	return playerlist
end


function Public.crew_get_crew_members_and_spectators()
	local memory = Memory.get_crew_memory()
	if memory.id == 0 then return {} end

	local playerlist = {}
	for _, id in pairs(memory.crewplayerindices) do
		local player = game.players[id]
		if player and player.valid then playerlist[#playerlist + 1] = player end
	end
	for _, id in pairs(memory.spectatorplayerindices) do
		local player = game.players[id]
		if player and player.valid then playerlist[#playerlist + 1] = player end
	end
	return playerlist
end




function Public.crew_get_nonafk_crew_members()
	local global_memory = Memory.get_global_memory()
	local memory = Memory.get_crew_memory()
	if memory.id == 0 then return {} end

	local playerlist = {}
	for _, id in pairs(memory.crewplayerindices) do
		local player = game.players[id]
		if player and player.valid and not Utils.contains(global_memory.afk_player_indices, player.index) then
			playerlist[#playerlist + 1] = player
		end
	end

	return playerlist
end


function Public.destroy_decoratives_in_area(surface, area, offset)
	local area2 = {{area[1][1] + offset.x, area[1][2] + offset.y}, {area[2][1] + offset.x, area[2][2] + offset.y}}

	surface.destroy_decoratives{area = area2}
end

function Public.can_place_silo_setup(surface, p, silo_count, build_check_type_name)

	Public.ensure_chunks_at(surface, p, 0.2)

	build_check_type_name = build_check_type_name or 'manual'
	local build_check_type = defines.build_check_type[build_check_type_name]
	local s = true
	for i=1,silo_count do
		s = surface.can_place_entity{name = 'rocket-silo', position = {p.x + 9 * (i-1), p.y}, build_check_type = build_check_type} and s
	end

	return s
end

function Public.ensure_chunks_at(surface, pos, radius) --WARNING: THIS DOES NOT PLAY NICELY WITH DELAYED TASKS. log(inspect{global_memory.working_id}) was observed to vary before and after this function.
	local global_memory = Memory.get_global_memory()
	if surface and surface.valid then
		surface.request_to_generate_chunks(pos, radius)
		surface.force_generate_chunk_requests() --WARNING: THIS DOES NOT PLAY NICELY WITH DELAYED TASKS. log(inspect{global_memory.working_id}) was observed to vary before and after this function.
	end
	
	
end


function Public.default_map_gen_settings(width, height, seed)
	width = width or 512
	height = height or 512
	seed = seed or Math.random(1, 1000000)
	
	local map_gen_settings = {
		['seed'] = seed,
		['width'] = width,
		['height'] = height,
		['water'] = 0,
		--FIXME: Back when this was at x=2000, a crash was caused once by a player spawning at x=2000. So there will be a crash in future under unknown circumstances if there is no space at x=0,y=0.
		['starting_points'] = {{x = 0, y = 0}},
		['cliff_settings'] = {cliff_elevation_interval = 0, cliff_elevation_0 = 0},
		['default_enable_all_autoplace_controls'] = true,
		['autoplace_settings'] = {
			['entity'] = {treat_missing_as_default = false},
			['tile'] = {treat_missing_as_default = true},
			['decorative'] = {treat_missing_as_default = true},
		},
		['property_expression_names'] = {},
	}

	return map_gen_settings
end

function Public.build_from_blueprint(bp_string, surface, pos, force, flipped)
	flipped = flipped or false

	local bp_entity = game.surfaces['nauvis'].create_entity{name = 'item-on-ground', position = {x = 158.5, y = 158.5}, stack = 'blueprint'}
	bp_entity.stack.import_stack(bp_string)

	local direction = flipped and defines.direction.south or defines.direction.north

	local entities = bp_entity.stack.build_blueprint{surface = surface, force = force, position = {x = pos.x, y = pos.y}, force_build = true, skip_fog_of_war = false, direction = direction}

	bp_entity.destroy()

	local rev_entities = {}
	for _, e in pairs(entities) do
		if e and e.valid then
			local collisions, revived_entity = e.silent_revive()
			rev_entities[#rev_entities + 1] = revived_entity
		end
	end

	-- once again, to revive wagons:
	for _, e in pairs(entities) do
		if e and e.valid and e.type and e.type == 'entity-ghost' then
			local collisions, revived_entity = e.silent_revive()
			rev_entities[#rev_entities + 1] = revived_entity

			if revived_entity and revived_entity.valid and revived_entity.name == 'locomotive' then
				revived_entity.color = {255, 106, 52}
				revived_entity.get_inventory(defines.inventory.fuel).insert({name = 'wood', count = 16})
				revived_entity.operable = false
			end
		end
	end
	
	return rev_entities
end

function Public.build_small_loco(surface, pos, force, color)
	local p1 = {x = pos.x, y = pos.y}
	local p2 = {x = pos.x, y = pos.y -2}
	local p3 = {x = pos.x, y = pos.y + 2}
	local es = {}
	es[1] = surface.create_entity({name = 'straight-rail', position = p1, force = force, create_build_effect_smoke = false})
	es[2] = surface.create_entity({name = 'straight-rail', position = p2, force = force, create_build_effect_smoke = false})
	es[3] = surface.create_entity({name = 'straight-rail', position = p3, force = force, create_build_effect_smoke = false})
	es[4] = surface.create_entity({name = 'locomotive', position = p1, force = force, create_build_effect_smoke = false})
	for _, e in pairs(es) do
		if e and e.valid then
			e.destructible = false
			e.minable = false
			e.rotatable = false
			e.operable = false
		end
	end
	if es[4] and es[4].valid then
		es[4].color = color
		es[4].get_inventory(defines.inventory.fuel).insert({name = 'wood', count = 16})
	end
end

function Public.tile_positions_from_blueprint(bp_string, offset)

	local bp_entity = game.surfaces['nauvis'].create_entity{name = 'item-on-ground', position = {x = 158.5, y = 158.5}, stack = 'blueprint'}
	bp_entity.stack.import_stack(bp_string)

	local bp_tiles = bp_entity.stack.get_blueprint_tiles()

	local positions = {}
	if bp_tiles then
		for _, tile in pairs(bp_tiles) do
			positions[#positions + 1] = {x = tile.position.x + offset.x, y = tile.position.y + offset.y}
		end
	end
	
	bp_entity.destroy()
	
	return positions
end

function Public.tile_positions_from_blueprint_arrayform(bp_string, offset)

	local bp_entity = game.surfaces['nauvis'].create_entity{name = 'item-on-ground', position = {x = 158.5, y = 158.5}, stack = 'blueprint'}
	bp_entity.stack.import_stack(bp_string)

	local bp_tiles = bp_entity.stack.get_blueprint_tiles()

	local positions = {}
	if bp_tiles then
		for _, tile in pairs(bp_tiles) do
			local x = tile.position.x+ offset.x
			local y = tile.position.y + offset.y
			if not positions[x] then positions[x] = {} end
			positions[x][y] = true
		end
	end
	
	bp_entity.destroy()
	
	return positions
end

function Public.entity_positions_from_blueprint(bp_string, offset)

	local bp_entity = game.surfaces['nauvis'].create_entity{name = 'item-on-ground', position = {x = 158.5, y = 158.5}, stack = 'blueprint'}
	bp_entity.stack.import_stack(bp_string)

	local es = bp_entity.stack.get_blueprint_entities()

	local positions = {}
	if es then
		for _, e in pairs(es) do
			positions[#positions + 1] = {x = e.position.x + offset.x, y = e.position.y + offset.y}
		end
	end
	
	bp_entity.destroy()
	
	return positions
end

function Public.get_random_unit_type(evolution)
	-- approximating graphs from https://wiki.factorio.com/Enemies
	local r = Math.random()

	if Math.random(5) == 1 then
		if r < 1 - 1/0.15*(evolution - 0.25) then
			return 'small-biter'
		elseif r < 1 - 1/0.3*(evolution - 0.4) then
			return 'small-spitter'
		elseif r < 1 - 0.85/0.5*(evolution - 0.5) then
			return 'medium-spitter'
		elseif r < 1 - 0.4/0.1*(evolution - 0.9) then
			return 'big-spitter'
		else
			return 'behemoth-spitter'
		end
	else
		if r < 1 - 1/0.4*(evolution - 0.2) then
			return 'small-biter'
		elseif r < 1 - 0.8/0.5*(evolution - 0.5) then
			return 'medium-biter'
		elseif r < 1 - 0.4/0.1*(evolution - 0.9) then
			return 'big-biter'
		else
			return 'behemoth-biter'
		end
	end
end

function Public.get_random_biter_type(evolution)
	-- approximating graphs from https://wiki.factorio.com/Enemies
	local r = Math.random()

	if r < 1 - 1/0.4*(evolution - 0.2) then
		return 'small-biter'
	elseif r < 1 - 0.8/0.5*(evolution - 0.5) then
		return 'medium-biter'
	elseif r < 1 - 0.4/0.1*(evolution - 0.9) then
		return 'big-biter'
	else
		return 'behemoth-biter'
	end
end

function Public.get_random_spitter_type(evolution)
	-- approximating graphs from https://wiki.factorio.com/Enemies
	local r = Math.random()

	if r < 1 - 1/0.3*(evolution - 0.4) then
		return 'small-spitter'
	elseif r < 1 - 0.85/0.5*(evolution - 0.5) then
		return 'medium-spitter'
	elseif r < 1 - 0.4/0.1*(evolution - 0.9) then
		return 'big-spitter'
	else
		return 'behemoth-spitter'
	end
end

function Public.get_random_worm_type(evolution)
	-- custom
	local r = Math.random()

	if r < 1 - 1/0.7*(evolution + 0.1) then
		return 'small-worm-turret'
	elseif r < 1 - 0.8/0.8*(evolution - 0.2) then
		return 'medium-worm-turret'
	elseif r < 1 - 0.4/0.4*(evolution - 0.6) then
		return 'big-worm-turret'
	else
		return 'behemoth-worm-turret'
	end
end

function Public.maximumUnitPollutionCost(evolution)
	if evolution < 0.2 then return 4
	elseif evolution < 0.5 then return 20
	elseif evolution < 0.9 then return 80
	else return 400
	end
end

function Public.averageUnitPollutionCost(evolution)

	local sum_biters = 0
	local f1 = Math.slopefromto(1 - 1/0.4*(evolution - 0.2), 0, 1)
	local f2 = Math.slopefromto(1 - 0.8/0.5*(evolution - 0.5), 0, 1)
	local f3 = Math.slopefromto(1 - 0.4/0.1*(evolution - 0.9), 0, 1)
	sum_biters = sum_biters + 4 * f1
	sum_biters = sum_biters + 20 * (f2 - f1)
	sum_biters = sum_biters + 80 * (f3 - f2)
	sum_biters = sum_biters + 400 * (1 - f3)

	local sum_spitters = 0
	local f1 = Math.slopefromto(1 - 1/0.15*(evolution - 0.25), 0, 1)
	local f2 = Math.slopefromto(1 - 1/0.3*(evolution - 0.4), 0, 1)
	local f3 = Math.slopefromto(1 - 0.85/0.5*(evolution - 0.5), 0, 1)
	local f4 = Math.slopefromto(1 - 0.4/0.1*(evolution - 0.9), 0, 1)
	sum_spitters = sum_spitters + 4 * f1
	sum_spitters = sum_spitters + 4 * (f2 - f1)
	sum_spitters = sum_spitters + 12 * (f3 - f2)
	sum_spitters = sum_spitters + 30 * (f4 - f3)
	sum_spitters = sum_spitters + 200 * (1 - f4)

	return (5 * sum_biters + sum_spitters)/6
end

function Public.orthog_positions_in_orthog_area(area)
	local positions = {}
		for y = area[1][2] + 0.5, area[2][2] - 0.5, 1 do
				for x = area[1][1] + 0.5, area[2][1] - 0.5, 1 do
						positions[#positions + 1] = {x = x, y = y}
				end
		end
		return positions
end

function Public.tileslist_add_area_offset(tiles_list_to_add_to, area, offset, tile_type)
	for _, p in pairs(Public.orthog_positions_in_orthog_area(area)) do
		tiles_list_to_add_to[#tiles_list_to_add_to + 1] = {name = tile_type, position = {x = offset.x + p.x, y = offset.y + p.y}}
	end
end

function Public.central_positions_within_area(area, offset)
	local offsetx = offset.x or 0
	local offsety = offset.y or 0
	local xr1, xr2, yr1, yr2 = offsetx + Math.ceil(area[1][1] - 0.5), offsetx + Math.floor(area[2][1] + 0.5), offsety + Math.ceil(area[1][2] - 0.5), offsety + Math.floor(area[2][2] + 0.5)

	local positions = {}
		for y = yr1 + 0.5, yr2 - 0.5, 1 do
				for x = xr1 + 0.5, xr2 - 0.5, 1 do
						positions[#positions + 1] = {x = x, y = y}
				end
		end
		return positions
end

function Public.tiles_from_area(tiles_list_to_add_to, area, offset, tile_type)
	for _, p in pairs(Public.central_positions_within_area(area, offset)) do
		tiles_list_to_add_to[#tiles_list_to_add_to + 1] = {name = tile_type, position = {x = p.x, y = p.y}}
	end
end

function Public.tiles_horizontally_flipped(tiles, x_to_flip_about)
	local tiles2 = {}
	for _, t in pairs(tiles) do
		local t2 = Utils.deepcopy(t)
		t2.position = {x = 2 * x_to_flip_about - t2.position.x, y = t2.position.y}
		tiles2[#tiles2 + 1] = t2
	end
	return tiles2
end


function Public.validate_player(player)
	local ret = false
	if player and player.valid and player.connected and game.players[player.name] then
		ret = true
	end
	if not ret and _DEBUG then
		log('player validation fail: ' .. (player.name or 'noname'))
	end
    return ret
end


function Public.validate_player_and_character(player)
	local ret = Public.validate_player(player)
	ret = ret and player.character and player.character.valid
    return ret
end


function Public.give_reward_items(items)
	local memory = Memory.get_crew_memory()

	local boat = memory.boat
	if not boat then return end
	local surface_name = boat.surface_name
	if not surface_name then return end
	local surface = game.surfaces[surface_name]
	if not (surface and surface.valid) then return end
	local chest = boat.output_chest
	if not (chest and chest.valid) then return end

	local inventory = chest.get_inventory(defines.inventory.chest)
	for _, i in pairs(items) do
		if not (i.count and i.count>0) then return end
		local inserted = inventory.insert{name = i.name, count = Math.ceil(i.count)}
		if i.count - inserted > 0 then
			local chest2 = boat.backup_output_chest
			if not (chest2 and chest2.valid) then return end
			local inventory2 = chest2.get_inventory(defines.inventory.chest)
			local inserted2 = inventory2.insert{name = i.name, count = Math.ceil(i.count - inserted)}
			if i.count - inserted - inserted2 > 0 then
				local force = game.forces[memory.force_name]
				if not (force and force.valid) then return end
				Public.notify_force(force, 'Warning: captain\'s cabin chests are full!')
			end
		end
	end
end



function Public.init_game_settings(technology_price_multiplier)

	--== Tuned for Pirate Ship ==--
	
	global.friendly_fire_history = {}
	global.landfill_history = {}
	global.mining_history = {}

	game.difficulty_settings.technology_price_multiplier = technology_price_multiplier

	game.map_settings.enemy_evolution.pollution_factor = 0
	game.map_settings.enemy_evolution.time_factor = 0
	game.map_settings.enemy_evolution.destroy_factor = 0

	game.map_settings.unit_group.min_group_gathering_time = 60 * 5
	game.map_settings.unit_group.max_group_gathering_time = 60 * 210
	game.map_settings.unit_group.max_wait_time_for_late_members = 60 * 15
	game.map_settings.unit_group.member_disown_distance = 5000
	game.map_settings.unit_group.max_group_radius = 70
	game.map_settings.unit_group.min_group_radius = 0.5 --seems to govern biter 'attack area' stopping distance

	-- (0,2) for a symmetric search:
	game.map_settings.path_finder.goal_pressure_ratio = -0.1 --small pressure for stupid paths
	game.map_settings.path_finder.fwd2bwd_ratio = 2 -- on experiments I found that only this value was symmetric...
	game.map_settings.max_failed_behavior_count = 2
	game.map_settings.path_finder.max_work_done_per_tick = 20000
	game.map_settings.path_finder.short_cache_min_algo_steps_to_cache = 100
	game.map_settings.path_finder.cache_accept_path_start_distance_ratio = 0.1


	game.map_settings.enemy_expansion.enabled = true
	-- faster expansion:
	game.map_settings.enemy_expansion.min_expansion_cooldown = 1.2 * 3600
	game.map_settings.enemy_expansion.max_expansion_cooldown = 20 * 3600
	game.map_settings.enemy_expansion.settler_group_max_size = 24
	game.map_settings.enemy_expansion.settler_group_min_size = 6
	-- maybe should be 3.5 if possible:
	game.map_settings.enemy_expansion.max_expansion_distance = 4

	-- could turn off default AI attacks:
	game.map_settings.pollution.enemy_attack_pollution_consumption_modifier = 1
	-- 
	game.map_settings.pollution.enabled = true
	game.map_settings.pollution.expected_max_per_chunk = 120
	game.map_settings.pollution.min_to_show_per_chunk = 10
	game.map_settings.pollution.min_pollution_to_damage_trees = 20
	game.map_settings.pollution.pollution_per_tree_damage = 0.2
	game.map_settings.pollution.max_pollution_to_restore_trees = 0.04
	game.map_settings.pollution.pollution_restored_per_tree_damage = 0.01
	game.map_settings.pollution.pollution_with_max_forest_damage = 80
	game.map_settings.pollution.ageing = 0.1

	game.map_settings.pollution.diffusion_ratio = 0.035
	--
	-- game.forces.neutral.character_inventory_slots_bonus = 500
	game.forces.enemy.evolution_factor = 0
end


return Public