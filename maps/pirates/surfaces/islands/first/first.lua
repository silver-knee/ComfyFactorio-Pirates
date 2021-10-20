
local ores = require "maps.pirates.ores"

local Memory = require 'maps.pirates.memory'
local Math = require 'maps.pirates.math'
local Balance = require 'maps.pirates.balance'
local Structures = require 'maps.pirates.structures.structures'
local Common = require 'maps.pirates.common'
local Utils = require 'maps.pirates.utils_local'
local inspect = require 'utils.inspect'.inspect
local Ores = require 'maps.pirates.ores'
local IslandsCommon = require 'maps.pirates.surfaces.islands.common'
local Hunt = require 'maps.pirates.surfaces.islands.hunt'
local event = require 'utils.event'


local Public = {}
Public.Data = require 'maps.pirates.surfaces.islands.first.data'


function Public.noises(args)
	local ret = {}

	ret.height = IslandsCommon.island_height_1(args)
	ret.forest = args.noise_generator.forest
	ret.forest_abs = function (p) return Math.abs(ret.forest(p)) end
	ret.forest_abs_suppressed = function (p) return ret.forest_abs(p) - 1 * Math.slopefromto(ret.height(p), 0.35, 0.1) end
	ret.rock = args.noise_generator.rock
	ret.rock_abs = function (p) return Math.abs(ret.rock(p)) end
	ret.farness = IslandsCommon.island_farness_1(args)
	return ret
end


function Public.terrain(args)
	local noises = Public.noises(args)
	local p = args.p

	
	if IslandsCommon.place_water_tile(args) then return end

	if noises.height(p) < 0 then
		args.tiles[#args.tiles + 1] = {name = 'water', position = args.p}
		return
	end
	
	if noises.height(p) < 0.1 then
		args.tiles[#args.tiles + 1] = {name = 'sand-1', position = args.p}
		if args.specials and noises.farness(p) > 0.0001 and noises.farness(p) < 0.6 and Math.random(150) == 1 then
			args.specials[#args.specials + 1] = {name = 'buried-treasure', position = args.p}
		end
	elseif noises.height(p) < 0.16 then
		args.tiles[#args.tiles + 1] = {name = 'grass-4', position = args.p}
	else
		if noises.forest_abs_suppressed(p) > 0.5 and noises.rock(p) < 0.3 then
			args.tiles[#args.tiles + 1] = {name = 'grass-3', position = args.p}
		elseif noises.forest_abs_suppressed(p) > 0.2 and noises.rock(p) < 0.3 then
			args.tiles[#args.tiles + 1] = {name = 'grass-2', position = args.p}
		else
			args.tiles[#args.tiles + 1] = {name = 'grass-1', position = args.p}
		end
	end

	if noises.height(p) > 0.2 then
		if noises.forest_abs(p) > 0.65 then
            local treedensity = 0.4 * Math.slopefromto(noises.forest_abs_suppressed(p), 0.6, 0.85)
			if noises.forest(p) > 0.87 then
				if Math.random(1,100) < treedensity*100 then args.entities[#args.entities + 1] = {name = 'tree-01', position = args.p, visible_on_overworld = true} end
			elseif noises.forest(p) < -1.4 then
				if Math.random(1,100) < treedensity*100 then args.entities[#args.entities + 1] = {name = 'tree-03', position = args.p, visible_on_overworld = true} end
			else
				if Math.random(1,100) < treedensity*100 then args.entities[#args.entities + 1] = {name = 'tree-02', position = args.p, visible_on_overworld = true} end
			end
		end
	end

	if noises.forest_abs_suppressed(p) < 0.6 then
		if noises.height(p) > 0.12 then
			local rockdensity = 0.0018 * Math.slopefromto(noises.rock_abs(p), -0.15, 0.3)
			local rockrng = Math.random()
			if rockrng < rockdensity then
				args.entities[#args.entities + 1] = IslandsCommon.random_rock_1(args.p)
			elseif rockrng < rockdensity * 1.5 then
				args.decoratives[#args.decoratives + 1] = {name = 'rock-medium', position = args.p}
			elseif rockrng < rockdensity * 2 then
				args.decoratives[#args.decoratives + 1] = {name = 'rock-small', position = args.p}
			elseif rockrng < rockdensity * 2.5 then
				args.decoratives[#args.decoratives + 1] = {name = 'rock-tiny', position = args.p}
			end
		end
	end
	
	
end


function Public.chunk_structures(args)

	local spec = function(p)
		local noises = Public.noises{p = p, noise_generator = args.noise_generator, static_params = args.static_params, seed = args.seed}

		return {
			placeable = noises.farness(p) > 0.4,
			density_perchunk = 28 * Math.slopefromto(noises.farness(p), 0.4, 1)^2,
		}
	end

	IslandsCommon.enemies_1(args, spec, false, 0.3)
end


function Public.break_rock(surface, p, entity_name)
	return Ores.try_ore_spawn(surface, p, entity_name, 6)
end


function Public.generate_silo_position()
	local memory = Memory.get_crew_memory()
	local enemy_force_name = memory.enemy_force_name
	local destination = Common.current_destination()
	local surface = game.surfaces[destination.surface_name]
	--local boatposition = memory.boat.position
	local island_center = destination.static_params.islandcenter_position
	local i, x,	y, item
	local wall_distance
	local max_wall_distance=16
	local wall_distance_step=8
	local lawn_mower=5
	local doorway=2
	local turrets={}

	local p = {
		x = island_center.x,
		y = island_center.y,
		r = max_wall_distance*3
	}
	
	local area=surface.find_entities({{p.x-max_wall_distance-lawn_mower,p.y-max_wall_distance-lawn_mower},{p.x+max_wall_distance+lawn_mower,p.y+max_wall_distance+lawn_mower}})
	for i=1,#area
	do
		area[i].destroy()
	end

	local tiles={}
	for x=-max_wall_distance,max_wall_distance
	do
		for y=-max_wall_distance,max_wall_distance
		do
			tiles[#tiles+1]={position={p.x+x,p.y+y},name="refined-concrete"}
		end
	end	
	
	surface.set_tiles(tiles, true, true)	

	local rings={}
	for wall_distance=wall_distance_step,max_wall_distance,wall_distance_step
	do
		local ring_turrets={}
		local ring_walls={}
	
		for i=-wall_distance+1,wall_distance-1
		do
			if i>=-doorway and i<=doorway
			then
				item="gate"
			else
				item="stone-wall"
			end
			ring_walls[#ring_walls+1]=surface.create_entity{name = item, force=enemy_force_name, position = {p.x+i,p.y-wall_distance-1}, direction = defines.direction.west}
			ring_walls[#ring_walls+1]=surface.create_entity{name = item, force=enemy_force_name, position = {p.x+i,p.y-wall_distance}, direction = defines.direction.west} 
			ring_walls[#ring_walls+1]=surface.create_entity{name = item, force=enemy_force_name, position = {p.x+i,p.y+wall_distance+1}, direction = defines.direction.west}
			ring_walls[#ring_walls+1]=surface.create_entity{name = item, force=enemy_force_name, position = {p.x+i,p.y+wall_distance}, direction = defines.direction.west}
		end		

		for i=-wall_distance+1,wall_distance-1
		do
			if i>=-doorway and i<=doorway
			then
				item="gate"
			else
				item="stone-wall"
			end
		
			ring_walls[#ring_walls+1]=surface.create_entity{name = item, force=enemy_force_name, position = {p.x-wall_distance-1,p.y+i}} 
			ring_walls[#ring_walls+1]=surface.create_entity{name = item, force=enemy_force_name, position = {p.x-wall_distance,p.y+i}} 
			ring_walls[#ring_walls+1]=surface.create_entity{name = item, force=enemy_force_name, position = {p.x+wall_distance+1,p.y+i}}
			ring_walls[#ring_walls+1]=surface.create_entity{name = item, force=enemy_force_name, position = {p.x+wall_distance,p.y+i}}
		end
		--small-worm-turret
		
		ring_turrets[1] = create_turret(surface,enemy_force_name,p.x+wall_distance+1,p.y+wall_distance+1)
		ring_turrets[2] = create_turret(surface,enemy_force_name,p.x+wall_distance+1,p.y-wall_distance)
		ring_turrets[3] = create_turret(surface,enemy_force_name,p.x-wall_distance  ,p.y+wall_distance+1)
		ring_turrets[4] = create_turret(surface,enemy_force_name,p.x-wall_distance  ,p.y-wall_distance)
		
		
		for i=1,#ring_turrets
		do
			turrets[#turrets+1] = ring_turrets[i]
		end
		
		surface.create_entity {name = 'spitter-spawner', force=enemy_force_name, position = {p.x+Math.random(-wall_distance-4,wall_distance+5),p.y-wall_distance-4}}
		surface.create_entity {name = 'spitter-spawner', force=enemy_force_name, position = {p.x+Math.random(-wall_distance-4,wall_distance+5),p.y+wall_distance+5}}
		surface.create_entity {name = 'biter-spawner', force=enemy_force_name, position = {p.x-wall_distance-4,p.y+Math.random(-wall_distance-4,wall_distance+5)}}
		surface.create_entity {name = 'biter-spawner', force=enemy_force_name, position = {p.x+wall_distance+5,p.y+Math.random(-wall_distance-4,wall_distance+5)}}
		
		rings[#rings+1]={
			ring_turrets=ring_turrets,
			ring_walls=ring_walls
		}
	end
	
	destination.dynamic_data.rings=rings
	
	
	for i=1,#turrets
	do
		turrets[i].insert({name="firearm-magazine", count=200})
	end
	
	return p
end 

function create_turret(surface,enemy_force_name,x,y)
	local turret=surface.create_entity{name = "gun-turret", force=enemy_force_name, position = {x,y}}
	
	for i=-1,2
	do
		surface.create_entity{name = "stone-wall", force=enemy_force_name, position = {x+i,y-2}}
		surface.create_entity{name = "stone-wall", force=enemy_force_name, position = {x+i,y+1}}
	end
		
	for i=-1,0
	do
		surface.create_entity{name = "stone-wall", force=enemy_force_name, position = {x-1,y+i}}
		surface.create_entity{name = "stone-wall", force=enemy_force_name, position = {x+2,y+i}}
	end
	
	return turret
end

event.add(defines.events.on_entity_damaged,function (event)
	local destination = Common.current_destination()
	local memory = Memory.get_crew_memory()
	local enemy_force_name = memory.enemy_force_name
	local rings=destination.dynamic_data.rings 
	local i,j
	local stay_open=60*3
	
	if _DEBUG and rings == nil then
		game.print("No rings")
	end
	
	if rings == nil then return end
	
--	game.print("--------")
--	game.print("rings "..#rings)
--	game.print(event.entity.valid)
--	if event.entity.valid then
--		game.print(event.entity.unit_number)
--	end
	
	
	for j=1,#rings
	do
		local ring_turrets=rings[j].ring_turrets
		local ring_walls=rings[j].ring_walls
		local found=false
		for i=1,#ring_turrets
		do
			--game.print(j.." "..i..": "..((ring_turrets[i].valid and "true") or "false"))
			--if ring_turrets[i].valid then
			--	game.print(ring_turrets[i].unit_number .. " - " .. (((ring_turrets[i].valid and ring_turrets[i] == event.entity) and "true") or "false"))
			--end

			if ring_turrets[i].valid and event.entity == ring_turrets[i]
			then
				found=true
				break
			end
		end
		
		--game.print(found)
		if found then 
			for i=1,#ring_walls
			do
				if ring_walls[i].valid and ring_walls[i].name == "gate" then ring_walls[i].request_to_open(enemy_force_name,stay_open) end
			end
		end
	end
end)

return Public