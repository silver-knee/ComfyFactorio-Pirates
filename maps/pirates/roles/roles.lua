
local Session = require 'utils.datastore.session_data'
local Antigrief = require 'utils.antigrief'
local Balance = require 'maps.pirates.balance'
local inspect = require 'utils.inspect'.inspect
local Memory = require 'maps.pirates.memory'
local Math = require 'maps.pirates.math'
local Common = require 'maps.pirates.common'
local Utils = require 'maps.pirates.utils_local'
local CoreData = require 'maps.pirates.coredata'
local Server = require 'utils.server'
local Classes = require 'maps.pirates.roles.classes'

local Public = {}
local privilege = {
	NORMAL = 1,
	OFFICER = 2,
	CAPTAIN = 3
}
Public.privilege = privilege


--== Roles — General ==--

function Public.tag_text(player)
	local memory = Memory.get_crew_memory()


	local tags = {}

	if memory.id ~= 0 and memory.playerindex_captain and player.index == memory.playerindex_captain then
		tags[#tags + 1] = "Cap'n"
	elseif player.controller_type == defines.controllers.spectator then
		tags[#tags + 1] = 'Spectating'
	elseif memory.officers_table and memory.officers_table[player.index] then
		tags[#tags + 1] = "Officer"
	end


	if memory.classes_table and memory.classes_table[player.index] then

		if not str == '' then str = str .. ' ' end
		tags[#tags + 1] = Classes.display_form[memory.classes_table[player.index]]
	end

	local str = ''
	for i, t in ipairs(tags) do
		if i>1 then str = str .. ', ' end
		str = str .. t
	end

	if (not (str == '')) then str = '[' .. str .. ']' end

	return str
end

function Public.update_tags(player)
	local str = Public.tag_text(player)

	player.tag = str
end

function Public.player_privilege_level(player)
	local memory = Memory.get_crew_memory()

	if memory.id ~= 0 and memory.playerindex_captain and player.index == memory.playerindex_captain then
		return Public.privilege.CAPTAIN
	elseif memory.officers_table and memory.officers_table[player.index] then
		return Public.privilege.OFFICER
	else
		return Public.privilege.NORMAL
	end
end

function Public.try_accept_captainhood(player)
	local memory = Memory.get_crew_memory()
	local captain_index = memory.playerindex_captain

	if not (player.index == captain_index) then
		Common.notify_player(player, 'You\'re not the captain.')
	else
		if memory.captain_acceptance_timer then
			memory.captain_acceptance_timer = nil

			local force = player.force
			if force and force.valid then
				local message = (player.name .. ' accepted the role of captain.')
				Common.notify_force(force, message)
				Server.to_discord_embed_raw(CoreData.comfy_emojis.derp .. '[' .. memory.name .. '] ' .. message)
			end
		else
			Common.notify_player(player, 'You\'re not temporary, so you don\'t need to accept.')
		end
	end
end

function Public.player_left_so_redestribute_roles(player)
	local memory = Memory.get_crew_memory()
	
	if player and player.index and player.index == memory.playerindex_captain then
		Public.assign_captain_based_on_priorities()
	end
	
	Public.try_renounce_class(player, "A %s class is now spare.")
end


function Public.renounce_captainhood(player)
	local global_memory = Memory.get_global_memory()
	local memory = Memory.get_crew_memory()

	if #Common.crew_get_crew_members() == 1 then
		Common.notify_player(player, 'But you\'re the only crew member...')
	else

		local force = game.forces[memory.force_name]
		global_memory.playerindex_to_priority[player.index] = nil
		if force and force.valid then
			local message = (player.name .. ' renounces their title of captain.')
			Common.notify_force(force, message)
			Server.to_discord_embed_raw(CoreData.comfy_emojis.ree1 .. '[' .. memory.name .. '] ' .. message)
		end
		
		Public.assign_captain_based_on_priorities(player.index)
	end
end


function Public.assign_class(player_index, class, self_assigned)
	local memory = Memory.get_crew_memory()

	if not memory.classes_table then memory.classes_table = {} end

	if Utils.contains(memory.spare_classes, class) then -- verify that one is spare
	
		memory.classes_table[player_index] = class
	
		local force = game.forces[memory.force_name]
		if force and force.valid then
			local message
			if self_assigned then
				message = '%s took the spare class %s. ([font=scenario-message-dialog]%s[/font])'
				Common.notify_force_light(force,string.format(message, game.players[player_index].name, Classes.display_form[memory.classes_table[player_index]], Classes.explanation[memory.classes_table[player_index]]))
			else
				message = 'A spare %s class was given to %s. [font=scenario-message-dialog](%s)[/font]'
				Common.notify_force_light(force,string.format(message, Classes.display_form[memory.classes_table[player_index]], game.players[player_index].name, Classes.explanation[memory.classes_table[player_index]]))
			end
		end
	
		memory.spare_classes = Utils.ordered_table_with_single_value_removed(memory.spare_classes, class)
	end
end

function Public.try_renounce_class(player, override_message)
	local memory = Memory.get_crew_memory()

	local force = game.forces[memory.force_name]
	if force and force.valid then
		if player and player.index and memory.classes_table and memory.classes_table[player.index] then
			if force and force.valid then
				if override_message then
					Common.notify_force_light(force,string.format(override_message, Classes.display_form[memory.classes_table[player.index]]))
				else
					Common.notify_force_light(force,string.format('%s gave up the class %s.', player.name, Classes.display_form[memory.classes_table[player.index]]))
				end
			end

			memory.spare_classes[#memory.spare_classes + 1] = memory.classes_table[player.index]
			memory.classes_table[player.index] = nil
		end
	end
end

function Public.make_captain(player)
	local global_memory = Memory.get_global_memory()
	local memory = Memory.get_crew_memory()

	memory.playerindex_captain = player.index
	global_memory.playerindex_to_priority[player.index] = nil
	memory.captain_acceptance_timer = nil
end

function Public.pass_captainhood(player, player_to_pass_to)
	local global_memory = Memory.get_global_memory()
	local memory = Memory.get_crew_memory()

	local force = game.forces[memory.force_name]
	if not (force and force.valid) then return end
	local message = string.format("%s has passed their captainhood to %s.", player.name, player_to_pass_to.name)
	Common.notify_force(force, message)
	Server.to_discord_embed_raw(CoreData.comfy_emojis.spurdo .. '[' .. memory.name .. '] ' .. message)

	Public.make_captain(player_to_pass_to)
end

function Public.afk_player_tick(player)
	local global_memory = Memory.get_global_memory()
	local memory = Memory.get_crew_memory()
	
	if player.index == memory.playerindex_captain and #Common.crew_get_nonafk_crew_members() > 0 then

		local force = game.forces[memory.force_name]
		if force and force.valid then
			local message = string.format(player.name .. ' was afk.')
			Common.notify_force(force, message)
			Server.to_discord_embed_raw(CoreData.comfy_emojis.loops .. '[' .. memory.name .. '] ' .. message)
		end

		if #Common.crew_get_nonafk_crew_members() == 1 then --don't need to bounce it around
			Public.make_captain(Common.crew_get_nonafk_crew_members()[1])
		else
			Public.assign_captain_based_on_priorities()
		end
	end
end


function Public.assign_captain_based_on_priorities(excluded_player_index)
	excluded_player_index = excluded_player_index or nil

	local global_memory = Memory.get_global_memory()
	local memory = Memory.get_crew_memory()

	local crew_members = memory.crewplayerindices

	if not (crew_members and #crew_members > 0) then return end

	local only_found_afk_players = true
	local best_priority_so_far = -1
	local captain_index = nil
	local captain_name = nil

	for _, player_index in pairs(crew_members) do
		local player = game.players[player_index]

		if Common.validate_player(player) and not (player.index == excluded_player_index) then

			local player_active = Utils.contains(Common.crew_get_nonafk_crew_members(), player)

			-- prefer non-afk players:
			if only_found_afk_players or player_active then
				only_found_afk_players = player_active
	
				local player_priority = global_memory.playerindex_to_priority[player_index]
				if player_priority and player_priority > best_priority_so_far then
					best_priority_so_far = player_priority
					captain_index = player_index
					captain_name = player.name
				end
			end
		end
	end

	local force = game.forces[memory.force_name]
	if not (force and force.valid) then return end

	if not captain_index then
		captain_index = crew_members[1]
		captain_name = game.players[captain_index].name
		Common.notify_force(force,'Looking for a suitable captain...')
	end

	if captain_index then
		local player = game.players[captain_index]
		if player and Common.validate_player(player) then
			Public.make_captain(player)
			-- this sets memory.captain_acceptance_timer = nil so now we must reset that after this function
		end
	end

	if #Common.crew_get_crew_members() > 1 then
		local messages = {
			"would you like to be captain?",
			"would you like to be captain?",
			"captain?",
			"is it your turn to be captain?",
		}
		local message = captain_name .. ', ' .. messages[Math.random(#messages)]
		Common.notify_force_light(force, message .. ' If yes say /ok')
		-- Server.to_discord_embed_raw('[' .. memory.name .. ']' .. CoreData.comfy_emojis.spurdo .. ' ' .. message)
		memory.captain_acceptance_timer = 72 --tuned
	else
		memory.captain_acceptance_timer = nil
	end
end


function Public.captain_requisition_coins(captain_index)
	local memory = Memory.get_crew_memory()
	local print = true
	if print then 
		Common.notify_force(game.forces[memory.force_name], 'Coins requisitioned by captain.')
	end

	local crew_members = memory.crewplayerindices
	local captain = game.players[captain_index]
	if not (captain and crew_members and #crew_members > 1) then return end
	
	local captain_inv = captain.get_inventory(defines.inventory.character_main)

	for _, player_index in pairs(crew_members) do
		if player_index ~= captain_index then
			local player = game.players[player_index]
			if player then
				local inv = player.get_inventory(defines.inventory.character_main)
				if not inv then return end
				local coin_amount = inv.get_item_count('coin')
				if coin_amount and coin_amount > 0 then
					inv.remove{name='coin', count=coin_amount}
					captain_inv.insert{name='coin', count=coin_amount}
				end
			end
		end
	end
end






function Public.add_player_to_permission_group(player, group_override)
    -- local jailed = Jailed.get_jailed_table()
    -- local enable_permission_group_disconnect = WPT.get('disconnect_wagon')
    local session = Session.get_session_table()
    local AG = Antigrief.get()

    local gulag = game.permissions.get_group('gulag')
    local tbl = gulag and gulag.players
    for i = 1, #tbl do
        if tbl[i].index == player.index then
            return
        end
    end

    -- if player.admin then
    --     return
    -- end

    local playtime = player.online_time
    if session and session[player.name] then
        playtime = player.online_time + session[player.name]
    end

    -- if jailed[player.name] then
    --     return
    -- end

    if not game.permissions.get_group('restricted_area') then
		local group = game.permissions.create_group('restricted_area')
        group.set_allows_action(defines.input_action.edit_permission_group, false)
        group.set_allows_action(defines.input_action.import_permissions_string, false)
        group.set_allows_action(defines.input_action.delete_permission_group, false)
        group.set_allows_action(defines.input_action.add_permission_group, false)
        group.set_allows_action(defines.input_action.admin_action, false)

        group.set_allows_action(defines.input_action.cancel_craft, false)
        group.set_allows_action(defines.input_action.drop_item, false)
        group.set_allows_action(defines.input_action.drop_blueprint_record, false)
        group.set_allows_action(defines.input_action.build, false)
        group.set_allows_action(defines.input_action.build_rail, false)
        group.set_allows_action(defines.input_action.build_terrain, false)
        group.set_allows_action(defines.input_action.begin_mining, false)
        group.set_allows_action(defines.input_action.begin_mining_terrain, false)
        group.set_allows_action(defines.input_action.deconstruct, false)
        group.set_allows_action(defines.input_action.activate_copy, false)
        group.set_allows_action(defines.input_action.activate_cut, false)
        group.set_allows_action(defines.input_action.activate_paste, false)
        group.set_allows_action(defines.input_action.upgrade, false)

		group.set_allows_action(defines.input_action.grab_blueprint_record, false)
		group.set_allows_action(defines.input_action.import_blueprint_string, false)
		group.set_allows_action(defines.input_action.import_blueprint, false)

        group.set_allows_action(defines.input_action.open_gui, false)
        group.set_allows_action(defines.input_action.fast_entity_transfer, false)
        group.set_allows_action(defines.input_action.fast_entity_split, false)
    end

    if not game.permissions.get_group('restricted_area_privileged') then
		local group = game.permissions.create_group('restricted_area_privileged')
        group.set_allows_action(defines.input_action.edit_permission_group, false)
        group.set_allows_action(defines.input_action.import_permissions_string, false)
        group.set_allows_action(defines.input_action.delete_permission_group, false)
        group.set_allows_action(defines.input_action.add_permission_group, false)
        group.set_allows_action(defines.input_action.admin_action, false)

        group.set_allows_action(defines.input_action.cancel_craft, false)
        group.set_allows_action(defines.input_action.drop_item, false)
        group.set_allows_action(defines.input_action.drop_blueprint_record, false)
        group.set_allows_action(defines.input_action.build, false)
        group.set_allows_action(defines.input_action.build_rail, false)
        group.set_allows_action(defines.input_action.build_terrain, false)
        group.set_allows_action(defines.input_action.begin_mining, false)
        group.set_allows_action(defines.input_action.begin_mining_terrain, false)
        group.set_allows_action(defines.input_action.deconstruct, false)
        group.set_allows_action(defines.input_action.activate_copy, false)
        group.set_allows_action(defines.input_action.activate_cut, false)
        group.set_allows_action(defines.input_action.activate_paste, false)
        group.set_allows_action(defines.input_action.upgrade, false)

		group.set_allows_action(defines.input_action.grab_blueprint_record, false)
		group.set_allows_action(defines.input_action.import_blueprint_string, false)
		group.set_allows_action(defines.input_action.import_blueprint, false)
    end

    if not game.permissions.get_group('plebs') then
        local plebs_group = game.permissions.create_group('plebs')
		if not _DEBUG then
			plebs_group.set_allows_action(defines.input_action.edit_permission_group, false)
			plebs_group.set_allows_action(defines.input_action.import_permissions_string, false)
			plebs_group.set_allows_action(defines.input_action.delete_permission_group, false)
			plebs_group.set_allows_action(defines.input_action.add_permission_group, false)
			plebs_group.set_allows_action(defines.input_action.admin_action, false)
	
			plebs_group.set_allows_action(defines.input_action.grab_blueprint_record, false)
			-- plebs_group.set_allows_action(defines.input_action.import_blueprint_string, false)
			-- plebs_group.set_allows_action(defines.input_action.import_blueprint, false)
		end
    end

    if not game.permissions.get_group('not_trusted') then
        local not_trusted = game.permissions.create_group('not_trusted')
        -- not_trusted.set_allows_action(defines.input_action.cancel_craft, false)
        not_trusted.set_allows_action(defines.input_action.edit_permission_group, false)
        not_trusted.set_allows_action(defines.input_action.import_permissions_string, false)
        not_trusted.set_allows_action(defines.input_action.delete_permission_group, false)
        not_trusted.set_allows_action(defines.input_action.add_permission_group, false)
        not_trusted.set_allows_action(defines.input_action.admin_action, false)
        -- not_trusted.set_allows_action(defines.input_action.drop_item, false)
        not_trusted.set_allows_action(defines.input_action.disconnect_rolling_stock, false)
        not_trusted.set_allows_action(defines.input_action.connect_rolling_stock, false)
        not_trusted.set_allows_action(defines.input_action.open_train_gui, false)
        not_trusted.set_allows_action(defines.input_action.open_train_station_gui, false)
        not_trusted.set_allows_action(defines.input_action.open_trains_gui, false)
        not_trusted.set_allows_action(defines.input_action.change_train_stop_station, false)
        not_trusted.set_allows_action(defines.input_action.change_train_wait_condition, false)
        not_trusted.set_allows_action(defines.input_action.change_train_wait_condition_data, false)
        not_trusted.set_allows_action(defines.input_action.drag_train_schedule, false)
        not_trusted.set_allows_action(defines.input_action.drag_train_wait_condition, false)
        not_trusted.set_allows_action(defines.input_action.go_to_train_station, false)
        not_trusted.set_allows_action(defines.input_action.remove_train_station, false)
        not_trusted.set_allows_action(defines.input_action.set_trains_limit, false)
        not_trusted.set_allows_action(defines.input_action.set_train_stopped, false)

		not_trusted.set_allows_action(defines.input_action.grab_blueprint_record, false)
		-- not_trusted.set_allows_action(defines.input_action.import_blueprint_string, false)
		-- not_trusted.set_allows_action(defines.input_action.import_blueprint, false)
    end

	local group
	if group_override then
		group = game.permissions.get_group(group_override)
	else
		if AG.enabled and not player.admin and playtime < 5184000 then -- 24 hours
			group = game.permissions.get_group('not_trusted')
		else
			group = game.permissions.get_group('plebs')
		end
	end
	group.add_player(player)
end

function Public.update_privileges(player)
    if not Common.validate_player_and_character(player) then
        return
    end

    if string.sub(player.surface.name, 9, 17) == 'Crowsnest' or string.sub(player.surface.name, 9, 13) == 'Cabin' then
		if Public.player_privilege_level(player) >= Public.privilege.OFFICER then
			return Public.add_player_to_permission_group(player, 'restricted_area_privileged')
		else
			return Public.add_player_to_permission_group(player, 'restricted_area')
		end
    else
        return Public.add_player_to_permission_group(player)
    end
end


return Public