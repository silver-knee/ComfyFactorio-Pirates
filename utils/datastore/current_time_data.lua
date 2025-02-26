local Server = require 'utils.server'
local Event = require 'utils.event'
local ComfyGui = require 'comfy_panel.main'
local Color = require 'utils.color_presets'

local current_time_label = 'current_time_label'

local function validate_player(player)
    if not player then
        return false
    end
    if not player.valid then
        return false
    end
    return true
end

local function set_location(player)
    local gui = player.gui
    local label = gui.screen[current_time_label]
    if not label or not label.valid then
        return
    end
    local res = player.display_resolution
    local uis = player.display_scale
    label.location = {x = res.width - 423 * uis, y = 50 * uis}
end

local function create_label(player)
    local date = Server.get_current_date_with_time()
    if not date then
        date = '1970-01-01'
    end

    local label =
        player.gui.screen.add(
        {
            type = 'label',
            name = current_time_label,
            caption = date
        }
    )
    local style = label.style
    style.font = 'default-game'
    return label
end

Event.add(
    defines.events.on_player_joined_game,
    function(event)
        local player = game.get_player(event.player_index)

        local label = player.gui.screen[current_time_label]

        if not label or not label.valid then
            label = create_label(player)
        end
        set_location(player)
        label.visible = false
    end
)

-- Update the value each second
Event.on_nth_tick(
    60,
    function()
        local date = Server.get_current_date_with_time()
        if not date then
            date = '1969-01-01 00:00'
        end

        local players = game.connected_players
        for i = 1, #players do
            local player = players[i]
            local label = player.gui.screen[current_time_label]
            if label and label.valid then
                label.caption = date
                set_location(player)
            end
        end
    end
)

commands.add_command(
    'server-date',
    'Toggle to show the date',
    function()
        local player = game.player

        local secs = Server.get_current_time()

        if validate_player(player) then
            if not secs then
                return player.print('Not running on Comfy backend.', Color.warning)
            end

            local label = player.gui.screen[current_time_label]
            if not label or not label.valid then
                label = create_label(player)
            end

            if label.visible then
                label.visible = false
                player.print('Removed date-label.', Color.warning)
            else
                label.visible = true
                set_location(player)
                player.print('Added date-label.', Color.success)
            end
        end
    end
)

ComfyGui.screen_to_bypass(current_time_label)

Event.add(
    defines.events.on_player_display_resolution_changed,
    function(event)
        local player = game.get_player(event.player_index)
        set_location(player)
    end
)

Event.add(
    defines.events.on_player_display_scale_changed,
    function(event)
        local player = game.get_player(event.player_index)
        set_location(player)
    end
)
