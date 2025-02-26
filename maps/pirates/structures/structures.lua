
local Memory = require 'maps.pirates.memory'
local Math = require 'maps.pirates.math'
local Balance = require 'maps.pirates.balance'
local Common = require 'maps.pirates.common'
local Loot = require 'maps.pirates.loot'
local Utils = require 'maps.pirates.utils_local'
local inspect = require 'utils.inspect'.inspect

local Public = {}
local enum = {
	BOATS = 'Boats',
	ISLANDSTRUCTURES = 'IslandStructures',
} 
Public.enum = enum
Public[enum.BOATS] = require 'maps.pirates.structures.boats.boats'
Public[enum.ISLANDSTRUCTURES] = require 'maps.pirates.structures.island_structures.island_structures'


function Public.post_creation_process(special_name, components)
	local destination = Common.current_destination()

	for _, c in pairs(components) do
		local type = c.type
		local force_name = c.force_name
		local force
		if force_name then force = game.forces[force_name] end
	
		if type == 'static' then
			for _, e in pairs(c.built_entities) do
				if e and e.valid then
					e.destructible = false
					e.minable = false
					e.rotatable = false
				end
			end
		elseif type == 'static_destructible' then
			for _, e in pairs(c.built_entities) do
				if e and e.valid then
					e.minable = false
					e.rotatable = false
				end
			end
		elseif type == 'plain' then
			for _, e in pairs(c.built_entities) do
				--
			end
		elseif type == 'static_inoperable' then
			for _, e in pairs(c.built_entities) do
				if e and e.valid then
					e.destructible = false
					e.minable = false
					e.rotatable = false
					e.operable = false
				end
			end
		elseif type == 'entities' then
			for _, e in pairs(c.built_entities) do
				if e and e.valid then
					e.minable = false
					e.rotatable = false
				end
			end
		elseif type == 'entities_minable' then
			for _, e in pairs(c.built_entities) do
				--
			end
		end


		for _, e in pairs(c.built_entities) do
			if e and e.valid then
				e.update_connections()
				if e.name == 'iron-chest' then
					local inv = e.get_inventory(defines.inventory.chest)
					local loot = Loot.iron_chest_loot()
					for i = 1, #loot do
						local l = loot[i]
						inv.insert(l)
					end
				elseif e.name == 'stone-furnace' then
					local inv = e.get_inventory(defines.inventory.fuel)
					local loot = Loot.stone_furnace_loot()
					for i = 1, #loot do
						local l = loot[i]
						inv.insert(l)
					end
				elseif e.name == 'roboport' then
					local inv = e.get_inventory(defines.inventory.roboport_robot)
					local loot = Loot.roboport_bots_loot()
					for i = 1, #loot do
						local l = loot[i]
						inv.insert(l)
					end
				elseif e.name == 'centrifuge' then
					local inv = e.get_inventory(defines.inventory.assembling_machine_input)
					e.set_recipe('kovarex-enrichment-process')
					inv.insert{name = 'uranium-235', count = 20}
				elseif e.name == 'gun-turret' and special_name == 'small_radioactive_centrifuge' then
					local memory = Memory.get_crew_memory()
					e.force = game.forces[memory.force_name]
				elseif e.name == 'storage-tank' and special_name == 'lonely_storage_tank' then
					e.insert_fluid(Loot.storage_tank_fluid_loot())
				elseif e.name == 'storage-tank' and special_name == 'swamp_lonely_storage_tank' then
					e.insert_fluid(Loot.swamp_storage_tank_fluid_loot())
				elseif e.name == 'storage-tank' and special_name == 'small_oilrig_base' then
					e.insert_fluid(Loot.storage_tank_fluid_loot(true))
				end

				if force_name and string.sub(force_name, 1, 15) and string.sub(force_name, 1, 15) == 'ancient-hostile' then
					if e.name == 'gun-turret' then
						-- TODO: make ammo type depend on x-coord
						e.insert({name = "piercing-rounds-magazine", count = 64})
					end
				elseif force_name and string.sub(force_name, 1, 16) and string.sub(force_name, 1, 16) == 'ancient-friendly' then
					if e.name == 'oil-refinery' then
						e.set_recipe('advanced-oil-processing')
					end
				end
			end
		end
	end
end


function Public.try_place(structureScope, specialsTable, left_top, areawidth, areaheight, placeability_function)
	local structureData = structureScope.Data

	local attempts = 6
	local succeeded = false

	while attempts > 0 and (not succeeded) do
		attempts = attempts - 1

		local structure_topleft = {
			x = left_top.x + Math.random(areawidth + 1 - structureData.width) - 1,
			y = left_top.y + Math.random(areaheight + 1 - structureData.height) - 1,
		}
		local structure_center = {
			x = structure_topleft.x + structureData.width/2,
			y = structure_topleft.y + structureData.height/2,
		}
		local structure_topright = {
			x = structure_topleft.x + structureData.width,
			y = structure_topleft.y,
		}
		local structure_bottomleft = {
			x = structure_topleft.x,
			y = structure_topleft.y + structureData.height,
		}
		local structure_bottomright = {
			x = structure_topleft.x + structureData.width,
			y = structure_topleft.y + structureData.height,
		}
	
		if placeability_function(structure_topleft) and placeability_function(structure_topright) and placeability_function(structure_bottomleft) and placeability_function(structure_bottomright) and placeability_function(structure_center) then
			specialsTable[#specialsTable + 1] = {
				position = structure_center,
				components = structureData.components,
				width = structureData.width,
				height = structureData.height,
				name = structureData.name,
			}
			succeeded = true
			if _DEBUG then
				log('structure_yes: ' .. structureData.name .. ' at ' .. structure_center.x .. ', ' .. structure_center.y)
			end
		else
			-- if _DEBUG then
			-- 	log('structure_no: ' .. structureData.name .. ' at ' .. structure_center.x .. ', ' .. structure_center.y)
			-- end
		end
	end
end

return Public