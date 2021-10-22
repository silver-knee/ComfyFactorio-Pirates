
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
local Fortress = require 'maps.pirates.structures.island_structures.fortress.fortress'


local Public = {}
Public.Data = require 'maps.pirates.surfaces.islands.fortress.data'

local prizes={
	{"power-armor",1},
	{"steel-plate",100*50},
	{"plastic-bar",100*50},
	{"defender-capsule",50},
	{"distractor-capsule",20},
	{"advanced-circuit",100},
	{"processing-unit",20},
	{"personal-laser-defense-equipment",1},
	{"modular-armor",5},
	{"artillery-shell",5},
}

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
	local destination = Common.current_destination()
	local surface = game.surfaces[destination.surface_name]

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
	--local boatposition = memory.boat.position
	local memory = Memory.get_crew_memory()
	local destination = Common.current_destination()
	local island_center = destination.static_params.islandcenter_position
	local width = destination.static_params.width
	local height = destination.static_params.height
	local surface = game.surfaces[destination.surface_name]
	-- TODO: export this into memory.ancient_force
	local ancient_force = string.format('ancient-friendly-%03d', memory.id) 
	local max_wall_distance=9
	local p
	local corner = {}
	local layers=2
	local i
	local specials = 2

	
--	local p = Hunt.position_away_from_players_1(destination)
--	p.r=max_wall_distance*3
--[[	
	local tries=0
	local valid_place
	repeat
		valid_place=true
		p = {
			x = math.floor(math.min(island_center.x+width/4+math.random(-max_wall_distance*layers,0),island_center.x+width/2)),
			y = math.floor(island_center.y+math.random(-max_wall_distance*layers,max_wall_distance*layers)),
			r = max_wall_distance*3
		}
		
		if valid_place and p.x+max_wall_distance*layers > island_center.x+width/2 then valid_place=false end
		game.print(valid_place and ("valid: " .. p.x) or ("invalid: " .. p.x))

		if valid_place
		then
			corner[1]=surface.get_tile(p.x+max_wall_distance*layers,p.y-max_wall_distance*layers)
			corner[2]=surface.get_tile(p.x-max_wall_distance*layers,p.y+max_wall_distance*layers)
			corner[3]=surface.get_tile(p.x+max_wall_distance*layers,p.y+max_wall_distance*layers)
			corner[4]=surface.get_tile(p.x-max_wall_distance*layers,p.y-max_wall_distance*layers)
			
			for i=1,#corner
			do
				if valid_place and (corner[i] == nil or corner[i].valid) then valid_place=false end
				game.print(valid_place and corner[i].name or "invalid")
				if valid_place and not corner[i].collides_with("ground-tile") then valid_place=false end
			end
		end
				
		tries=tries+1
	until tries>500 or valid_place
	
	if tries>500 
	then
		if _DEBUG 
		then
			game.print("Tried to place silo fortress 500 times and failed")
		end
		

	end
]]--	

	p=Hunt.free_position_1(0.75,0)
	
	p = {
		x = math.floor(p.x),
		y = math.floor(p.y),
		r = max_wall_distance*3
	}
	
	Fortress.create_fortress(p.x,p.y,max_wall_distance,layers)
	
	for i=1,specials
	do
		local x=math.floor(island_center.x+math.random(-20,20))
		local y=math.floor(island_center.y+math.random(-height/4,height/4))
		
		Fortress.create_fortress(x,y,5,1)
		local chest = surface.create_entity {name="wooden-chest", force=ancient_force, position = {x,y}}
		local prize = prizes[math.floor(math.random(1,#prizes))]
		
		chest.insert({name=prize[1],count=prize[2]})
	end

	return p
end 


return Public