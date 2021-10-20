
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
	-- local boatposition = memory.boat.position
	-- local boatposition = memory.boat.position
	local island_center = destination.static_params.islandcenter_position
	local i
	local x
	local y
	local wall_distance
	local max_wall_distance=14
	local wall_distance_step=7

	local p = {
		x = island_center.x,
		y = island_center.y,
		r = 50
	}
	
	local turrets={}
	
	local area=surface.find_entities({{p.x-20,p.y-20},{p.x+20,p.y+20}})
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
	
	for wall_distance=wall_distance_step,max_wall_distance,wall_distance_step
	do
		for i=-wall_distance+1,wall_distance-1
		do
			surface.create_entity{name = "stone-wall", force=enemy_force_name, position = {p.x+i,p.y-wall_distance-1}}
			surface.create_entity{name = "stone-wall", force=enemy_force_name, position = {p.x+i,p.y-wall_distance}} 
			surface.create_entity{name = "stone-wall", force=enemy_force_name, position = {p.x+i,p.y+wall_distance+1}}
			surface.create_entity{name = "stone-wall", force=enemy_force_name, position = {p.x+i,p.y+wall_distance}}
		end		

		for i=-wall_distance+1,wall_distance-1
		do
			surface.create_entity{name = "stone-wall", force=enemy_force_name, position = {p.x-wall_distance-1,p.y+i}} 
			surface.create_entity{name = "stone-wall", force=enemy_force_name, position = {p.x-wall_distance,p.y+i}} 
			surface.create_entity{name = "stone-wall", force=enemy_force_name, position = {p.x+wall_distance+1,p.y+i}}
			surface.create_entity{name = "stone-wall", force=enemy_force_name, position = {p.x+wall_distance,p.y+i}}
		end
		
		turrets[#turrets+1] = surface.create_entity{name = "gun-turret", force=enemy_force_name, position = {p.x+wall_distance+1,p.y+wall_distance+1}}
		turrets[#turrets+1] = surface.create_entity{name = "gun-turret", force=enemy_force_name, position = {p.x+wall_distance+1,p.y-wall_distance}}
		turrets[#turrets+1] = surface.create_entity{name = "gun-turret", force=enemy_force_name, position = {p.x-wall_distance,p.y+wall_distance+1}}
		turrets[#turrets+1] = surface.create_entity{name = "gun-turret", force=enemy_force_name, position = {p.x-wall_distance,p.y-wall_distance}}
	end
	
	for i=1,#turrets
	do
		turrets[i].insert({name="firearm-magazine", count=200})
	end
	
	return p
end


return Public