
local Memory = require 'maps.pirates.memory'
local Balance = require 'maps.pirates.balance'
local Common = require 'maps.pirates.common'
local CoreData = require 'maps.pirates.coredata'
local Utils = require 'maps.pirates.utils_local'
local Math = require 'maps.pirates.math'
local inspect = require 'utils.inspect'.inspect

local Structures = require 'maps.pirates.structures.structures'
local Boats = require 'maps.pirates.structures.boats.boats'
local Surfaces = require 'maps.pirates.surfaces.surfaces'
local Islands = require 'maps.pirates.surfaces.islands.islands'
local Sea = require 'maps.pirates.surfaces.sea.sea'
local Crew = require 'maps.pirates.crew'
local Quest = require 'maps.pirates.quest'

local Public = {}

local function fake_boat_target()
	local memory = Memory.get_crew_memory()
    if memory.boat and memory.boat.position then
	    return {valid = true, position = {x = memory.boat.position.x - 60, y = memory.boat.position.y} or nil, name = 'boatarea'}
    end
end

-- fff 283 discussed pollution mechanics: https://factorio.com/blog/post/fff-283

local side_attack_target_names = {
	'character',
	'pumpjack',
	'radar',
	'burner-mining-drill',
	'electric-mining-drill',
	'nuclear-reactor',
	'boiler',
	'oil-refinery',
	'centrifuge',
}


--=== Tick Actions

function Public.Tick_actions(tickinterval)
	local memory = Memory.get_crew_memory()
    local destination = Common.current_destination()

	if (not destination.type) or (not destination.type == Surfaces.enum.ISLAND) then return end
	if (not memory.boat.state) or (not (memory.boat.state == Boats.enum_state.LANDED or memory.boat.state == Boats.enum_state.RETREATING)) then return end
	
    if (memory.gamelost or memory.gamewon) or (not destination.dynamic_data.timeratlandingtime) or destination.dynamic_data.timer < destination.dynamic_data.timeratlandingtime + Common.seconds_after_landing_to_enable_AI then return end

	if memory.boat.state == Boats.enum_state.LANDED then
		local ef = game.forces[memory.enemy_force_name]
		local extra_evo = tickinterval/60 * Balance.evolution_per_second()
		ef.evolution_factor = ef.evolution_factor + extra_evo
		destination.dynamic_data.evolution_accrued_time = destination.dynamic_data.evolution_accrued_time + extra_evo
	end
    


    -- if destination.subtype and destination.subtype == Islands.enum.RED_DESERT then return end -- This was a hack to stop biter boats causing attacks, but, it has the even worse effect of stopping all floating_pollution gathering.


    local minute_cycle = {-- even seconds only
        [2] = Public.eat_up_fraction_of_all_pollution_wrapped,
        [4] = Public.try_rogue_attack,
        [6] = Public.poke_script_groups,
        [12] = Public.try_main_attack,
        [16] = Public.poke_script_groups,
        -- [18] = Public.try_secondary_attack, --commenting out: less attacks per minute, but stronger. @TODO need to do more here
        [20] = Public.tell_biters_near_silo_to_attack_it,
        [26] = Public.poke_script_groups,
        [28] = Public.eat_up_fraction_of_all_pollution_wrapped,
        [30] = Public.try_secondary_attack,
        [36] = Public.poke_script_groups,
        [46] = Public.poke_script_groups,
        [50] = Public.tell_biters_near_silo_to_attack_it,
        [52] = Public.create_mail_delivery_biters,
        [56] = Public.poke_script_groups,
        [58] = Public.poke_inactive_scripted_biters,
    }

    if minute_cycle[(game.tick / 60) % 60] then
        minute_cycle[(game.tick / 60) % 60]()
    end
end


function Public.eat_up_fraction_of_all_pollution_wrapped()
	local memory = Memory.get_crew_memory()
    local surface = game.surfaces[Common.current_destination().surface_name]
    Public.eat_up_fraction_of_all_pollution(surface, 0.05)
end

function Public.eat_up_fraction_of_all_pollution(surface, fraction_of_global_pollution)
	
	local memory = Memory.get_crew_memory()
	local enemy_force_name = memory.enemy_force_name

    local pollution_available = memory.floating_pollution

    local chunk_positions = {}
    for i = 1, Math.ceil(surface.map_gen_settings.width/32),1 do
        for j = 1, Math.ceil(surface.map_gen_settings.height/32),1 do
            chunk_positions[#chunk_positions + 1] = {x = 16 + i * 32 - surface.map_gen_settings.width/2, y = 16 + j * 32 - surface.map_gen_settings.height/2}
        end
    end

    for i = 1, #chunk_positions do
        local p = chunk_positions[i]
        local pollution = surface.get_pollution(p)
        local pollution_to_eat = pollution * fraction_of_global_pollution

        surface.pollute(p, - pollution_to_eat)
		-- Radioactive world doesn't absorb map pollution:
		if not (Common.current_destination().subtype and Common.current_destination().subtype == Islands.enum.RADIOACTIVE) then
        	pollution_available = pollution_available + pollution_to_eat
		end
    end

	-- if _DEBUG then
	-- 	game.print(string.format('ate %f pollution', pollution_available))
	-- end

    memory.floating_pollution = pollution_available
end

function Public.try_main_attack()
	local wave_size_multiplier = 1
    if Math.random(2) == 2 then return end --variance in attack sizes
    if Math.random(10) == 1 then wave_size_multiplier = 2 end --variance in attack sizes
    if Math.random(45) == 1 then wave_size_multiplier = 3.2 end --variance in attack sizes

	local memory = Memory.get_crew_memory()
    local surface = game.surfaces[Common.current_destination().surface_name]


    local group = Public.spawn_group_of_scripted_biters(2/3, 6, 128, wave_size_multiplier)
    local target = Public.generate_main_attack_target()
    if not group or not group.valid or not target or not target.valid then return end

	-- group.set_command(Public.attack_target(target))

    Public.group_set_commands(group, Public.attack_target(target))

	-- if _DEBUG then game.print(game.tick .. string.format(": sending main attack of %s units from {%f,%f} to %s", #group.members, group.position.x, group.position.y, target.name)) end
end

function Public.try_secondary_attack()
	local wave_size_multiplier = 1
    if Math.random(2) == 2 then return end --variance in attack sizes
    if Math.random(10) == 1 then wave_size_multiplier = 2 end --variance in attack sizes
    if Math.random(45) == 1 then wave_size_multiplier = 3.2 end --variance in attack sizes

	local memory = Memory.get_crew_memory()
    local surface = game.surfaces[Common.current_destination().surface_name]


    local group = Public.spawn_group_of_scripted_biters(2/3, 12, 128, wave_size_multiplier)
	if not (group and group.valid) then return end
	
	local target
	if Math.random(2) == 1 then
		target = Public.generate_main_attack_target()
	else
		target = Public.generate_side_attack_target(surface, group.position)
	end
    if not group or not group.valid or not target or not target.valid then return end

	-- group.set_command(Public.attack_target(target))

    Public.group_set_commands(group, Public.attack_target(target))

	-- if _DEBUG then game.print(game.tick .. string.format(": sending main attack of %s units from {%f,%f} to %s", #group.members, group.position.x, group.position.y, target.name)) end
end

function Public.try_rogue_attack()
	local wave_size_multiplier = 1
    if Math.random(2) == 2 then return end --variance in attack sizes
    if Math.random(10) == 1 then wave_size_multiplier = 2 end --variance in attack sizes
    if Math.random(45) == 1 then wave_size_multiplier = 3.2 end --variance in attack sizes

	local memory = Memory.get_crew_memory()
	local surface = game.surfaces[Common.current_destination().surface_name]

	local group = Public.spawn_group_of_scripted_biters(1/2, 6, 128, wave_size_multiplier)
	if not (group and group.valid) then return end
	local target = Public.generate_side_attack_target(surface, group.position)
	if not (target and target.valid) then return end

	-- group.set_command(Public.attack_target(target))

    Public.group_set_commands(group, Public.attack_target(target))

	-- if _DEBUG then game.print(game.tick .. string.format(": sending rogue attack of %s units from {%f,%f} to %s", #group.members, group.position.x, group.position.y, target.name)) end
end


function Public.tell_biters_near_silo_to_attack_it()
	-- careful with this function, you don't want to pull biters onto the silo before any aggro has happened
	local memory = Memory.get_crew_memory()
    local destination = Common.current_destination()
	local surface = game.surfaces[destination.surface_name]
	local enemy_force_name = memory.enemy_force_name

    -- don't do this too early
    if destination.dynamic_data.timer < destination.dynamic_data.timeratlandingtime + Common.seconds_after_landing_to_enable_AI * 4 then return end
    if not (destination.dynamic_data.rocketsilos and destination.dynamic_data.rocketsilos[1] and destination.dynamic_data.rocketsilos[1].valid and destination.dynamic_data.rocketsilos[1].destructible) then return end

    local attackcommand = Public.attack_target_entity(destination.dynamic_data.rocketsilos[1])

    if attackcommand then
        surface.set_multi_command(
            {
                command = attackcommand,
                unit_count = Math.random(1, Math.floor(1 + game.forces[enemy_force_name].evolution_factor * 100)),
                force = enemy_force_name,
                unit_search_distance = 10
            }
        )
    end

end

function Public.poke_script_groups()
	local memory = Memory.get_crew_memory()
    for index, group in pairs(memory.scripted_unit_groups) do
        local groupref = group.ref
        if not groupref.valid or groupref.surface.index ~= game.surfaces[Common.current_destination().surface_name].index or #groupref.members < 1 then
            memory.scripted_unit_groups[index] = nil
        else
            if groupref.state == defines.group_state.finished then
                if Math.random(20) == 20 then
                    local command = Public.attack_obstacles(groupref.surface, {x = groupref.position.x, y = groupref.position.y})
                    groupref.set_command(command)
                else
                    groupref.set_autonomous() --means go home, really
                end
            elseif group.state == defines.group_state.gathering then
                groupref.start_moving()
            -- elseif group.state == defines.group_state.wander_in_group then
            --     groupref.set_autonomous() --means go home, really
            end
        end
    end
end

function Public.poke_inactive_scripted_biters()
	local memory = Memory.get_crew_memory()
    for unit_number, biter in pairs(memory.scripted_biters) do
        if Public.is_biter_inactive(biter) then
            memory.scripted_biters[unit_number] = nil
            if biter.entity and biter.entity.valid then
                local target = Public.nearest_target()
                if target and target.valid then
                    Public.group_set_commands(biter.entity, Public.attack_target(target))
                end
            end
        end
    end
end

function Public.create_mail_delivery_biters()
	local memory = Memory.get_crew_memory()
	local surface = game.surfaces[Common.current_destination().surface_name]
	local enemy_force_name = memory.enemy_force_name

    local spawners = surface.find_entities_filtered{name = 'biter-spawner', force = enemy_force_name}

    local try_how_many_groups = Math.min(Math.max(0, (#spawners - 8) / 100), 4)

    for i = 1, try_how_many_groups do
        if Math.random(2) == 1 then
            local s1 = spawners[Math.random(#spawners)]

            local far_spawners = {}
            for j = 1, #spawners do
                local s2 = spawners[i]
                if not (i == j or Math.distance(s1.position, s2.position) < 250) then
                    far_spawners[#far_spawners + 1] = s2
                end
            end

            if #far_spawners > 0 then
                local s2 = far_spawners[Math.random(#far_spawners)]

                memory.floating_pollution = memory.floating_pollution + 64
                local units = Public.try_spawner_spend_fraction_of_available_pollution_on_biters(s1, 1/4, 4, 32, 1, 'small-biter')
                memory.floating_pollution = memory.floating_pollution - 64
                
                if (not units) or (not #units) or (#units == 0) then return end

                local start_p = surface.find_non_colliding_position('rocket-silo', s1.position, 256, 2) or s1.position

                local unit_group = surface.create_unit_group({position = start_p, force = enemy_force_name})
                for _, unit in pairs(units) do
                    unit_group.add_member(unit)
                end
                memory.scripted_unit_groups[unit_group.group_number] = {ref = unit_group, script_type = 'mail-delivery'}

                Public.group_set_commands(unit_group, {
                    Public.move_to(s2.position),
                    Public.wander_around(),
                })

                -- game.print(string.format('%f biters delivering mail from %f, %f to %f, %f', #units, s1.position.x, s1.position.y, s2.position.x, s2.position.y))
            end
        end
    end
end


--=== Spawn scripted biters


function Public.spawn_group_of_scripted_biters(fraction_of_floating_pollution, minimum_avg_units, maximum_units, wave_size_multiplier)
	local memory = Memory.get_crew_memory()
	local surface = game.surfaces[Common.current_destination().surface_name]
	local enemy_force_name = memory.enemy_force_name
	
	-- @TODO: bring this 512 constant out into a variable somewhere
    if Public.get_scripted_biter_count() > 512 * memory.difficulty then
        return nil
    end
    local spawner = Public.get_random_spawner(surface)
    if not spawner then return end

    local units = Public.try_spawner_spend_fraction_of_available_pollution_on_biters(spawner, fraction_of_floating_pollution, minimum_avg_units, maximum_units, 1/wave_size_multiplier)

    if (not units) or (not #units) or (#units == 0) then return end

    local position = surface.find_non_colliding_position('rocket-silo', spawner.position, 256, 2) or spawner.position

    local unit_group = surface.create_unit_group({position = position, force = enemy_force_name})
    for _, unit in pairs(units) do
        unit_group.add_member(unit)
    end
    memory.scripted_unit_groups[unit_group.group_number] = {ref = unit_group, script_type = 'attacker'}
    return unit_group
end


function Public.try_spawner_spend_fraction_of_available_pollution_on_biters(spawner, fraction_of_floating_pollution, minimum_avg_units, maximum_units, unit_pollutioncost_multiplier, enforce_type)
    maximum_units = maximum_units or 256
	
	local memory = Memory.get_crew_memory()
	local surface = spawner.surface
	local spawnerposition = spawner.position
    local difficulty = memory.difficulty
	local enemy_force_name = memory.enemy_force_name
	local evolution = game.forces[enemy_force_name].evolution_factor

	local units_created_count = 0
	local units_created = {}

    local temp_floating_pollution = memory.floating_pollution
    local budget = fraction_of_floating_pollution * temp_floating_pollution
    local initialbudget = budget

	local base_pollution_cost_multiplier = 1
	local destination = Common.current_destination()
	if destination.dynamic_data then
		local spawnerscount = Common.spawner_count(surface)

		local initial_spawner_count = destination.dynamic_data.initial_spawner_count
		if initial_spawner_count and initial_spawner_count > 0 then
			if spawnerscount > 0 then
				-- if Common.current_destination().subtype and Common.current_destination().subtype == Islands.enum.RADIOACTIVE then
				-- 	-- destroying spawners doesn't do quite as much here:
				-- 	base_pollution_cost_multiplier = (initial_spawner_count/spawnerscount)^(1/3)
				-- else
				-- 	base_pollution_cost_multiplier = (initial_spawner_count/spawnerscount)^(1/2)
				-- end
				-- base_pollution_cost_multiplier = (initial_spawner_count/spawnerscount)^(1/2)
				-- Now directly proportional:
				base_pollution_cost_multiplier = Math.max(1, initial_spawner_count/spawnerscount) -- Can't be less than 1. (The first map not being fully loaded when you get there commonly means it records too few initial spawners, which this helps fix)
			else
				base_pollution_cost_multiplier = 1000000
			end
		end
	end

	if memory.overworldx == 0 then
		-- less biters:
		base_pollution_cost_multiplier = base_pollution_cost_multiplier * 2.5
	end

	base_pollution_cost_multiplier = base_pollution_cost_multiplier * unit_pollutioncost_multiplier
	
	base_pollution_cost_multiplier = base_pollution_cost_multiplier * Balance.scripted_biters_pollution_cost_multiplier()

    if budget >= minimum_avg_units * Common.averageUnitPollutionCost(evolution) * base_pollution_cost_multiplier then

        local function spawn(name2)
            units_created_count = units_created_count + 1

			local unittype_pollutioncost = CoreData.biterPollutionValues[name2] * base_pollution_cost_multiplier

            local p = surface.find_non_colliding_position(name2, spawnerposition, 50, 2)
            if not p then return end

            local biter = surface.create_entity({name = name2, force = enemy_force_name, position = p})

            units_created[#units_created + 1] = biter
            memory.scripted_biters[biter.unit_number] = {entity = biter, created_at = game.tick}

			temp_floating_pollution = temp_floating_pollution - unittype_pollutioncost
			budget = budget - unittype_pollutioncost
			-- flow statistics should reflect the number of biters generated, without factors for extra expenditure:
			game.pollution_statistics.on_flow(name2, - CoreData.biterPollutionValues[name2] * Balance.scripted_biters_pollution_cost_multiplier())

            return biter.unit_number
        end

		local mixed = (Math.random(2) == 1)
		if mixed then

			local whilesafety = 1000
			local next_name = enforce_type or Common.get_random_unit_type(evolution)

			while units_created_count < maximum_units and budget >= CoreData.biterPollutionValues[next_name] * base_pollution_cost_multiplier and #memory.scripted_biters < Common.total_max_biters and whilesafety > 0 do
				whilesafety = whilesafety - 1
				spawn(next_name)
				next_name = enforce_type or Common.get_random_unit_type(evolution)
			end
		else
			local name = enforce_type or Common.get_random_unit_type(evolution)

			local whilesafety = 1000
			while units_created_count < maximum_units and budget >= CoreData.biterPollutionValues[name] * base_pollution_cost_multiplier and #memory.scripted_biters < Common.total_max_biters and whilesafety > 0 do
				whilesafety = whilesafety - 1
				spawn(name)
			end
		end

        memory.floating_pollution = temp_floating_pollution
    end
	
    return units_created
end


--=== Misc Functions

function Public.generate_main_attack_target()
	local memory = Memory.get_crew_memory()
    local destination = Common.current_destination()
    local target = nil
    local fractioncharged = 0
    if (not destination.dynamic_data.rocketlaunched) and destination.dynamic_data.rocketsilos and destination.dynamic_data.rocketsilos[1] and destination.dynamic_data.rocketsilos[1].valid and destination.dynamic_data.rocketsilos[1].destructible and destination.dynamic_data.rocketsiloenergyconsumed and destination.dynamic_data.rocketsiloenergyneeded and destination.dynamic_data.rocketsiloenergyneeded > 0 then
        fractioncharged = destination.dynamic_data.rocketsiloenergyconsumed / destination.dynamic_data.rocketsiloenergyneeded
    end
    
    local rng = Math.random()
	if rng <= fractioncharged^(1/2) then
		target = destination.dynamic_data.rocketsilos[1]
	else
		target = fake_boat_target()
	end
    return target
end

function Public.generate_side_attack_target(surface, position)
    local entities = surface.find_entities_filtered{name = side_attack_target_names}
    if not entities then return end
    if Math.random(20) >= #entities then return end

    entities = Math.shuffle(entities)
    entities = Math.shuffle_distancebiased(entities, position)
    local weights = {}
    for index, _ in pairs(entities) do
        weights[#weights + 1] = 1 + Math.floor((#entities - index) / 2)
    end
    return Math.raffle(entities, weights)
end

function Public.nearest_target(surface, position)
    local names = {'rocket-silo'}
    for _, name in pairs(side_attack_target_names) do
        names[#names + 1] = name
    end
    local entities = surface.find_entities_filtered{name = names}
    local d = 9999
    local nearest = nil
    for i = 1, #entities do
        local e = entities[i]
        if e and e.valid and Math.distance(e.position, position) < d then
            nearest = e
        end
    end
    return nearest
end

-- function Public.try_spend_pollution(surface, position, amount, flow_statistics_source)
-- 	local memory = Memory.get_crew_memory()
-- 	local force_name = memory.force_name

-- 	flow_statistics_source = flow_statistics_source or 'medium-biter'
--     if not (position and surface and surface.valid) then return end

--     local pollution = surface.get_pollution(position)
--     if pollution > amount then
--         surface.pollute(position, -amount)
--         game.forces[force_name].pollution_statistics.on_flow(flow_statistics_source, -amount)
--         return true
--     end
--     return false
-- end

function Public.get_random_spawner(surface)
	local memory = Memory.get_crew_memory()

    local spawners = surface.find_entities_filtered({type = 'unit-spawner', force = memory.enemy_force_name})
    if (not spawners) or (not spawners[1]) then return end
	return spawners[Math.random(#spawners)]
end

function Public.is_biter_inactive(biter)
    if (not biter.entity) or (not biter.entity.valid) then
		return true
	end
    if game.tick - biter.created_at > 30*60*60 then
        biter.entity.destroy()
        return true
    end
    return false
end

function Public.get_scripted_biter_count()
	local memory = Memory.get_crew_memory()
    local count = 0
    for k, biter in pairs(memory.scripted_biters) do
        if biter.entity and biter.entity.valid then
            count = count + 1
        else
            memory.scripted_biters[k] = nil
        end
    end
    return count
end


-----------commands-----------

function Public.stop()
    local command = {
        type = defines.command.stop,
        distraction = defines.distraction.stop
    }
    return command
end

function Public.move_to(position)
    local command = {
        type = defines.command.go_to_location,
        destination = position,
        distraction = defines.distraction.anything
    }
    return command
end

function Public.attack_target_entity(target)
    if not target and target.valid then return end
    local command = {
        type = defines.command.attack,
        target = target,
        distraction = defines.distraction.by_anything
    }
    return command
end

function Public.attack_area(position, radius)
    local command = {
        type = defines.command.attack_area,
        destination = position,
        radius = radius or 25,
        distraction = defines.distraction.by_anything
    }
    return command
end

function Public.attack_obstacles(surface, position)
    local commands = {}
    local obstacles = surface.find_entities_filtered {position = position, radius = 25, type = {'simple-entity', 'tree', 'simple-entity-with-owner'}, limit = 100}
    if obstacles then
        Math.shuffle(obstacles)
        Math.shuffle_distancebiased(obstacles, position)
        for i = 1, #obstacles, 1 do
            if obstacles[i].valid then
                commands[#commands + 1] = {
                    type = defines.command.attack,
                    target = obstacles[i],
                    distraction = defines.distraction.by_anything
                }
            end
        end
    end
    commands[#commands + 1] = Public.move_to(position)
    local command = {
        type = defines.command.compound,
        structure_type = defines.compound_command.return_last,
        commands = commands
    }
    return command
end

function Public.wander_around(ticks_to_wait) --wander individually inside group radius
    local command = {
        type = defines.command.wander,
        distraction = defines.distraction.anything,
        ticks_to_wait = ticks_to_wait,
    }
    return command
end

function Public.group_set_commands(group, commands)
    if #commands > 0 then
        local command = {
            type = defines.command.compound,
            structure_type = defines.compound_command.return_last,
            commands = commands
        }
        group.set_command(command)
    end
end

function Public.attack_target(target)
	if not target then return end

    local commands
	if target.name == 'boatarea' then
        commands = {
            Public.attack_area(target.position, 32),
            Public.attack_area(target.position, 32),
        }
	else
        commands = {
            Public.attack_area(target.position, 8),
            Public.attack_target_entity(target),
        }
	end
	-- if Math.random(20) == 20 then
	-- 	commands = {
	-- 		Public.attack_obstacles(group.surface, {x = (group.position.x * 0.90 + target.position.x * 0.10), y = (group.position.y * 0.90 + target.position.y * 0.10)}),
    --         attackcommand,
	-- 	}
	-- else
	-- 	commands = {attackcommand}
	-- end
    return commands
end







--- small group of revenge biters ---


function Public.revenge_group(surface, p, target, type)
	type = type or 'biter'
	local memory = Memory.get_crew_memory()
	local enemy_force_name = memory.enemy_force_name

	local name, count
	if type == 'biter' then
		name = Common.get_random_biter_type(game.forces[memory.enemy_force_name].evolution_factor)

		if name == 'small-biter' then
			count = 6
		elseif name == 'medium-biter' then
			count = 3
		elseif name == 'big-biter' then
			count = 2
		elseif name == 'behemoth-biter' then
			count = 1
		end
	elseif type == 'spitter' then
		name = Common.get_random_spitter_type(game.forces[memory.enemy_force_name].evolution_factor)

		if name == 'small-spitter' then
			count = 10
		elseif name == 'medium-spitter' then
			count = 6
		elseif name == 'big-spitter' then
			count = 4
		elseif name == 'behemoth-spitter' then
			count = 2
		end
	end

	if (not (name and count and count>0)) then return end

    local units = {}
	for i = 1, count do
		local p2 = surface.find_non_colliding_position('wooden-chest', p, 5, 0.5)
		if p2 then
            local biter = surface.create_entity({name = name, force = enemy_force_name, position = p})
            -- local biter = surface.create_entity({name = name, force = enemy_force_name, position = p2})
            units[#units + 1] = biter
        end
    end

	if #units > 0 then
		local unit_group = surface.create_unit_group({position = p, force = enemy_force_name})
		for _, unit in pairs(units) do
			unit_group.add_member(unit)
		end

		if target and target.valid then
			Public.group_set_commands(unit_group, Public.attack_target(target))
		end
		unit_group.set_autonomous()
	end
end





----------- biter raiding parties -----------


function Public.spawn_boat_biters(boat, max_evo)
	-- max_evolution_bonus = max_evolution_bonus or 0.3
	local memory = Memory.get_crew_memory()
	local surface = game.surfaces[boat.surface_name]
    local difficulty = memory.difficulty
	local enemy_force_name = boat.force_name
	-- local evolution = game.forces[enemy_force_name].evolution_factor

    local p = {boat.position.x - 4.5, boat.position.y}

    local units = {}
	for i = 1, 12 do
        local name = Common.get_random_unit_type(max_evo - i * 0.04)
        -- local name = Common.get_random_unit_type(evolution + i/15 * max_evolution_bonus)
        -- local name = Common.get_random_unit_type(evolution + 3 * i/100)

		local p2 = surface.find_non_colliding_position('wooden-chest', p, 5, 0.5)
		if p2 then
            local biter = surface.create_entity({name = name, force = enemy_force_name, position = p2})
    
            memory.scripted_biters[biter.unit_number] = {entity = biter, created_at = game.tick}
    
            units[#units + 1] = biter
        end
    end

    local target = Public.generate_main_attack_target()

    if #units > 0 and target and target.valid then
        local unit_group = surface.create_unit_group({position = p, force = enemy_force_name})
        for _, unit in pairs(units) do
            unit_group.add_member(unit)
        end
        boat.unit_group = {ref = unit_group, script_type = 'landing-party'}
    end
end

function Public.update_landing_party_unit_groups(boat, step_distance)
	local memory = Memory.get_crew_memory()

    -- move unit groups:
    local group = boat.unit_group
    local surface = game.surfaces[boat.surface_name]
    if not (group and surface and surface.valid) then return end

    local groupref = group.ref
    if not (groupref and groupref.valid) then return end

    local p2 = groupref.position
    if not p2 then return end

	local enemy_force_name = memory.enemy_force_name
	local m = groupref.members
	groupref.destroy()

	local new_group = surface.create_unit_group({position = {x = p2.x + step_distance, y = p2.y}, force = enemy_force_name})

	boat.unit_group = {ref = new_group, script_type = 'landing-party'}
	for i = 1, #m do
		local b = m[i]
		new_group.add_member(b)
	end

	if boat.spawner and boat.spawner.valid then
		new_group.set_command(Public.move_to(boat.spawner.position))
	end
end










-- function Public.destroy_inactive_scripted_biters()
-- 	local memory = Memory.get_crew_memory()
-- 	local floating_pollution_accrued = 0
--     for unit_number, biter in pairs(memory.scripted_biters) do
--         if Public.is_biter_inactive(biter) then
--             memory.floating_pollution = memory.floating_pollution + CoreData.biterPollutionValues[biter.entity.name]
-- 			floating_pollution_accrued = floating_pollution_accrued + CoreData.biterPollutionValues[biter.entity.name]
--             memory.scripted_biters[unit_number] = nil
--         end
--     end
-- 	if _DEBUG and floating_pollution_accrued > 0 then game.print(game.tick .. string.format(":%f of spare pollution accrued", floating_pollution_accrued)) end
-- end

--=== Data



return Public
