-- Adapted from mountain_fortress_v3 highscores.lua

local Event = require 'utils.event'
local Global = require 'utils.global'
local Server = require 'utils.server'
local Math = require 'maps.pirates.math'
local Token = require 'utils.token'
local Tabs = require 'comfy_panel.main'
local Core = require 'utils.core'
local inspect = require 'utils.inspect'.inspect
local SpamProtection = require 'utils.spam_protection'
local Memory = require 'maps.pirates.memory'
local Utils = require 'maps.pirates.utils_local'

local module_name = 'Highscore'
local score_dataset = 'highscores'
local score_key = 'pirate_ship_scores'
local score_key_debug = 'pirate_ship_scores_debug'
local score_key_modded = 'pirate_ship_scores_modded'

local Public = {}
local insert = table.insert
local this = {
    score_table = {player = {}},
    sort_by = {}
}

Global.register(
    this,
    function(t)
        this = t
    end
)

local function sort_list(method, column_name, score_list)
    local comparators = {
        ['ascending'] = function(a, b)
            return a[column_name] < b[column_name]
        end,
        ['descending'] = function(a, b)
            return a[column_name] > b[column_name]
        end
    }
	Utils.stable_sort(score_list, comparators[method])
    -- table.sort(score_list, comparators[method])
    return score_list
end


local function saved_scores_trim(scores)
	-- the goal here is to trim away highscores so we don't have too many.

	local completion_times = {}
	local leagues_travelled = {}
	local completion_times_mediump_latestv = {}
	local leagues_travelled_mediump_latestv = {}
	local completion_times_hard = {}
	local leagues_travelled_hard = {}
	local completion_times_nightmare = {}
	local leagues_travelled_nightmare = {}
	local completion_times_latestv = {}
	local leagues_travelled_latestv = {}
	local versions = {}

	for _, score in pairs(scores) do
		if score.version and score.version > 0 then
			versions[#versions + 1] = score.version
		end
		if score.completion_time and score.completion_time > 0 then
			completion_times[#completion_times + 1] = score.completion_time
		end
		if score.leagues_travelled and score.leagues_travelled > 0 then
			leagues_travelled[#leagues_travelled + 1] = score.leagues_travelled
		end
		if score.difficulty and score.difficulty >= 1.5 then
			if score.completion_time and score.completion_time > 0 then
				completion_times_hard[#completion_times_hard + 1] = score.completion_time
			end
			if score.leagues_travelled and score.leagues_travelled > 0 then
				leagues_travelled_hard[#leagues_travelled_hard + 1] = score.leagues_travelled
			end
		end
		if score.difficulty and score.difficulty >= 3 then
			if score.completion_time and score.completion_time > 0 then
				completion_times_nightmare[#completion_times_nightmare + 1] = score.completion_time
			end
			if score.leagues_travelled and score.leagues_travelled > 0 then
				leagues_travelled_nightmare[#leagues_travelled_nightmare + 1] = score.leagues_travelled
			end
		end
	end

	local latest_version = 0
	for _, v in pairs(versions) do
		if v > latest_version then latest_version = v end
	end
	
	for _, score in pairs(scores) do
		if score.version and score.version == latest_version then
			if score.completion_time and score.completion_time > 0 then
				completion_times_latestv[#completion_times_latestv + 1] = score.completion_time
			end
			if score.leagues_travelled and score.leagues_travelled > 0 then
				leagues_travelled_latestv[#leagues_travelled_latestv + 1] = score.leagues_travelled
			end
			if score.difficulty and score.difficulty >= 1 then
				if score.completion_time and score.completion_time > 0 then
					completion_times_mediump_latestv[#completion_times_mediump_latestv + 1] = score.completion_time
				end
				if score.leagues_travelled and score.leagues_travelled > 0 then
					leagues_travelled_mediump_latestv[#leagues_travelled_mediump_latestv + 1] = score.leagues_travelled
				end
			end
		end
	end

	table.sort(completion_times)
	table.sort(leagues_travelled)
	table.sort(completion_times_mediump_latestv)
	table.sort(leagues_travelled_mediump_latestv)
	table.sort(completion_times_hard)
	table.sort(leagues_travelled_hard)
	table.sort(completion_times_nightmare)
	table.sort(leagues_travelled_nightmare)
	table.sort(completion_times_latestv)
	table.sort(leagues_travelled_latestv)

	local completion_times_cutoff = #completion_times > 8 and completion_times[8] or 9999999
	local completion_times_mediump_latestv_cutoff = #completion_times_mediump_latestv > 4 and completion_times_mediump_latestv[4] or 9999999
	local completion_times_hard_cutoff = #completion_times_hard > 4 and completion_times_hard[4] or 9999999
	local completion_times_nightmare_cutoff = #completion_times_hard > 2 and completion_times_hard[2] or 9999999
	local completion_times_latestv_cutoff = #completion_times_latestv > 8 and completion_times_latestv[8] or 9999999

	local leagues_travelled_cutoff = #leagues_travelled > 8 and leagues_travelled[-8] or 0
	local leagues_travelled_mediump_latestv_cutoff = #leagues_travelled_mediump_latestv > 4 and leagues_travelled_mediump_latestv[-4] or 0
	local leagues_travelled_hard_cutoff = #leagues_travelled_hard > 4 and leagues_travelled_hard[-4] or 0
	local leagues_travelled_nightmare_cutoff = #leagues_travelled_hard > 2 and leagues_travelled_hard[-2] or 0
	local leagues_travelled_latestv_cutoff = #leagues_travelled_latestv > 86 and leagues_travelled_latestv[-8] or 0

	-- log(inspect{completion_times_cutoff,completion_times_mediump_latestv_cutoff,completion_times_hard_cutoff,completion_times_latestv_cutoff,leagues_travelled_cutoff,leagues_travelled_mediump_latestv_cutoff,leagues_travelled_hard_cutoff,leagues_travelled_latestv_cutoff})

	local delete = {}
	
	for secs_id, score in pairs(scores) do
		local include = false
		
		if completion_times_cutoff and score.completion_time and score.completion_time < completion_times_cutoff then include = true
		elseif completion_times_mediump_latestv_cutoff and score.completion_time and score.completion_time < completion_times_mediump_latestv_cutoff and score.version == latest_version and score.difficulty >= 1 then include = true
		elseif completion_times_hard_cutoff and score.completion_time and score.completion_time < completion_times_hard_cutoff and score.difficulty >= 1.5 then include = true
		elseif completion_times_nightmare_cutoff and score.completion_time and score.completion_time < completion_times_nightmare_cutoff and score.difficulty >=3 then include = true
		elseif completion_times_latestv_cutoff and score.completion_time and score.completion_time < completion_times_latestv_cutoff and score.version == latest_version then include = true

		elseif leagues_travelled_cutoff and score.leagues_travelled and score.leagues_travelled > leagues_travelled_cutoff then include = true
		elseif leagues_travelled_mediump_latestv_cutoff and score.leagues_travelled and score.leagues_travelled > leagues_travelled_mediump_latestv_cutoff and score.version == latest_version and score.difficulty >= 1 then include = true
		elseif leagues_travelled_hard_cutoff and score.leagues_travelled and score.leagues_travelled > leagues_travelled_hard_cutoff and score.difficulty >= 1.5 then include = true
		elseif leagues_travelled_nightmare_cutoff and score.leagues_travelled and score.leagues_travelled > leagues_travelled_nightmare_cutoff and score.difficulty >= 3 then include = true
		elseif leagues_travelled_latestv_cutoff and score.leagues_travelled and score.leagues_travelled > leagues_travelled_latestv_cutoff and score.version == latest_version then include = true
		end

		if not include then delete[#delete + 1] = secs_id end
	end
	-- log(inspect(delete))

	for _, secs_id in pairs(delete) do
		scores[secs_id] = nil
	end

	return scores
end



local function local_highscores_write_stats(crew_secs_id, name, captain_name, completion_time, leagues_travelled, version, difficulty, capacity)

	if not this.score_table['player'] then this.score_table['player'] = {} end
	if not this.score_table['player'].runs then this.score_table['player'].runs = {} end

    local t = this.score_table['player']

    if t then
        -- if name then
        --     t.name = name
        -- end
        -- if version then
        --     t.version = version
        -- end
        -- if completion_time then
        --     t.completion_time = completion_time
        -- end
        -- if leagues_travelled then
        --     t.leagues_travelled = leagues_travelled
        -- end
        -- if difficulty then
        --     t.difficulty = difficulty
        -- end
        -- if capacity then
        --     t.capacity = capacity
        -- end
		
		if crew_secs_id then
			t.runs[crew_secs_id] = {name = name, captain_name = captain_name, version = version, completion_time = completion_time, leagues_travelled = leagues_travelled, difficulty = difficulty, capacity = capacity}

			-- log(inspect(t))

			saved_scores_trim(t.runs)
		end
    end

    this.score_table['player'] = t
	-- log(inspect(t))
end


local load_in_scores =
    Token.register(
    function(data)
        local value = data.value
        if not this.score_table['player'] then
            this.score_table['player'] = {}
        end

        this.score_table['player'] = value
    end
)
function Public.load_in_scores()
    local secs = Server.get_current_time()
	-- if secs then game.print('secs2: ' .. secs) else game.print('secs: false') end
    if not secs then
        return
    else
		-- FULL CLEAN task (erases everything...):
		-- server_set_data(score_dataset, score_key, {})

        if is_game_modded() then
			Server.try_get_data(score_dataset, score_key_modded, load_in_scores)
		elseif _DEBUG then
			Server.try_get_data(score_dataset, score_key_debug, load_in_scores)
        else
			Server.try_get_data(score_dataset, score_key, load_in_scores)
		end
    end
end

function Public.write_score(crew_secs_id, name, captain_name, completion_time, leagues_travelled, version, difficulty, capacity)
    local secs = Server.get_current_time()
	-- if secs then game.print('secs1: ' .. secs) else game.print('secs: false') end
    if not secs then
        return
    else
        local_highscores_write_stats(crew_secs_id, name, captain_name, completion_time, leagues_travelled, version, difficulty, capacity)

        if is_game_modded() then
			Server.set_data(score_dataset, score_key_modded, this.score_table['player'])
		elseif _DEBUG then
			Server.set_data(score_dataset, score_key_debug, this.score_table['player'])
        else
			Server.set_data(score_dataset, score_key, this.score_table['player'])
		end
    end
end

local function on_init()
    local secs = Server.get_current_time()
    if not secs then
        local_highscores_write_stats() --just to init tables presumably
        return
    end
end


local sorting_symbol = {ascending = '▲', descending = '▼'}

local function get_saved_scores_for_displaying()
    local score_data = this.score_table['player']
    local score_list = {}

	if score_data and score_data.runs then
		for _, score in pairs(score_data.runs or {}) do
			insert(
				score_list,
				{
					name = score and score.name,
					captain_name = score and score.captain_name,
					completion_time = score and score.completion_time or 99999,
					leagues_travelled = score and score.leagues_travelled or 0,
					version = score and score.version or 0,
					difficulty = score and score.difficulty or 0,
					capacity = score and score.capacity or 0,
				}
			)
		end
	else
		score_list[#score_list + 1] = {
			name = 'Nothing here yet',
			captain_name = '',
			completion_time = 0,
			leagues_travelled = 0,
			version = 0,
			difficulty = 0,
			capacity = 0,
		}
	end

    return score_list
end

local function score_gui(data)
    local player = data.player
    local frame = data.frame
    frame.clear()

	local columnwidth = 96

    -- local flow = frame.add {type = 'flow'}
    -- local sFlow = flow.style
    -- sFlow.horizontally_stretchable = true
    -- sFlow.horizontal_align = 'center'
    -- sFlow.vertical_align = 'center'

    -- local stats = flow.add {type = 'label', caption = 'Highest score so far:'}
    -- local s_stats = stats.style
    -- s_stats.font = 'heading-1'
    -- s_stats.font_color = {r = 0.98, g = 0.66, b = 0.22}
    -- s_stats.horizontal_align = 'center'
    -- s_stats.vertical_align = 'center'

    -- -- Global stats : rockets, biters kills
    -- add_global_stats(frame)

    -- -- Separator
    -- local line = frame.add {type = 'line'}
    -- line.style.top_margin = 8
    -- line.style.bottom_margin = 8

    -- Score per player
    local t = frame.add {type = 'table', column_count = 7}

    -- Score headers
    local headers = {
        {name = '_name', caption = 'Crew'},
        {name = '_captain_name', caption = 'Captain'},
        {column = 'completion_time', name = '_completion_time', caption = 'Completion'},
        {column = 'leagues_travelled', name = '_leagues_travelled', caption = 'Leagues'},
        {column = 'version', name = '_version', caption = 'Version'},
        {column = 'difficulty', name = '_difficulty', caption = 'Difficulty'},
        {column = 'capacity', name = '_capacity', caption = 'Capacity'},
    }

    local sorting_pref = this.sort_by[player.index] or {}
    for _, header in ipairs(headers) do
        local cap = header.caption

		-- log(header.caption)

        -- Add sorting symbol if any
        if header.column and sorting_pref[1] and sorting_pref[1].column == header.column then
			local symbol = sorting_symbol[sorting_pref[1].method]
			cap = symbol .. cap
        end

        -- Header
        local label =
            t.add {
            type = 'label',
            caption = cap,
            name = header.name
        }
        label.style.font = 'default-listbox'
        label.style.font_color = {r = 0.98, g = 0.66, b = 0.22} -- yellow
        label.style.minimal_width = columnwidth
        label.style.horizontal_align = 'right'
    end

    -- Score list
    local score_list = get_saved_scores_for_displaying()
	-- log(inspect(score_list))

	for i = #sorting_pref, 1, -1 do
		local sort = sorting_pref[i]
		if sort then
			score_list = sort_list(sort.method, sort.column, score_list)
		end
	end

    -- New pane for scores (while keeping headers at same position)
    local scroll_pane =
        frame.add(
        {
            type = 'scroll-pane',
            name = 'score_scroll_pane',
            direction = 'vertical',
            horizontal_scroll_policy = 'never',
            vertical_scroll_policy = 'auto'
        }
    )
    scroll_pane.style.maximal_height = 400
    t = scroll_pane.add {type = 'table', column_count = 7}

    -- Score entries
    for _, entry in pairs(score_list) do
		local p = {color = {r = Math.random(1, 255), g = Math.random(1, 255), b = Math.random(1, 255)}}
        -- local p
        -- if not (entry and entry.name) then
        --     p = {color = {r = random(1, 255), g = random(1, 255), b = random(1, 255)}}
        -- else
        --     p = game.players[entry.name]
        --     if not p then
        --         p = {color = {r = random(1, 255), g = random(1, 255), b = random(1, 255)}}
        --     end
        -- end
        local special_color = {
            r = p.color.r * 0.6 + 0.4,
            g = p.color.g * 0.6 + 0.4,
            b = p.color.b * 0.6 + 0.4,
            a = 1,
        }

        local n = entry.completion_time > 0 and Utils.time_mediumform(entry.completion_time or 0) or 'N/A'
        local l = entry.leagues_travelled > 0 and entry.leagues_travelled or 'N/A'
        local v = entry.version > 0 and entry.version or 'N/A'
        local d = entry.difficulty > 0 and entry.difficulty or 'N/A'
        local c = entry.capacity > 0 and entry.capacity or 'N/A'
        local line = {
            {caption = entry.name, color = special_color},
            {caption = entry.captain_name or '?'},
            {caption = tostring(n)},
            {caption = tostring(l)},
            {caption = tostring(v)},
            {caption = tostring(d)},
            {caption = tostring(c)},
        }
        local default_color = {r = 0.9, g = 0.9, b = 0.9}

        for _, column in ipairs(line) do
            local label =
                t.add {
                type = 'label',
                caption = column.caption,
                color = column.color or default_color,
            }
            label.style.font = 'default'
            label.style.minimal_width = columnwidth
            label.style.maximal_width = columnwidth
            label.style.horizontal_align = 'right'
        end -- foreach column
    end -- foreach entry
end

local score_gui_token = Token.register(score_gui)

local function on_gui_click(event)
    if not event then
        return
    end
    if not event.element then
        return
    end
    if not event.element.valid then
        return
    end

    local player = game.players[event.element.player_index]
    local frame = Tabs.comfy_panel_get_active_frame(player)
    if not frame then
        return
    end
    if frame.name ~= module_name then
        return
    end

    local is_spamming = SpamProtection.is_spamming(player, nil, 'HighScore Gui Click')
    if is_spamming then
        return
    end

    local name = event.element.name

    -- Handles click on a score header
    local element_to_column = {
        ['_version'] = 'version',
        ['_completion_time'] = 'completion_time',
        ['_leagues_travelled'] = 'leagues_travelled',
        ['_difficulty'] = 'difficulty',
        ['_capacity'] = 'capacity',
    }
    if element_to_column[name] then
		--@TODO: Extend
        local sorting_pref = this.sort_by[player.index]
		local found_index = nil
		local new_method = 'descending'

		for i, sort in ipairs(sorting_pref) do
			if sort.column == element_to_column[name] then
				found_index = i
				if sort.method == 'descending' and i==1 then new_method = 'ascending' end
			end
		end
		if found_index then
			--remove this and shuffle everything before it up by 1:
			for j = found_index, 2, -1 do
				sorting_pref[j] = Utils.deepcopy(sorting_pref[j-1]) --deepcopy just as I'm slightly unsure about refernces here
			end
		else
			--prepend:
			for j = #sorting_pref + 1, 2, -1 do
				sorting_pref[j] = Utils.deepcopy(sorting_pref[j-1]) --deepcopy just as I'm slightly unsure about references here
			end
		end
		sorting_pref[1] = {column = element_to_column[name], method = new_method}

        score_gui({player = player, frame = frame})
        return
    end
end

local function on_player_joined_game(event)
    local player = game.players[event.player_index]
    if player.index and this.sort_by and (not this.sort_by[player.index]) then
        this.sort_by[player.index] = {{method = 'ascending', column = 'completion_time'}, {method = 'descending', column = 'leagues_travelled'}, {method = 'descending', column = 'version'}, {method = 'descending', column = 'difficulty'}}
    end
end

local function on_player_left_game(event)
    local player = game.players[event.player_index]
    if this.sort_by[player.index] then
        this.sort_by[player.index] = nil
    end
end

Server.on_data_set_changed(
    score_dataset,
    function(data)
		local key
        if is_game_modded() then
			key = score_key_modded
		elseif _DEBUG then
			key = score_key_debug
        else
			key = score_key
		end
        if data.key == key then
            if data.value then
                this.score_table['player'] = data.value
            end
        end
    end
)


Tabs.add_tab_to_gui({name = module_name, id = score_gui_token, admin = false, only_server_sided = false})

Event.on_init(on_init)
Event.add(defines.events.on_player_left_game, on_player_left_game)
Event.add(defines.events.on_player_joined_game, on_player_joined_game)
Event.add(defines.events.on_gui_click, on_gui_click)
Event.add(Server.events.on_server_started, Public.load_in_scores)

return Public