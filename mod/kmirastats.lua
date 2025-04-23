local https = require("SMODS.https")
local KS = SMODS.current_mod

-- Simple JSON encode function
local function json_encode(data)
    if type(data) == "string" then
        return string.format('"%s"', data:gsub('"', '\\"'))
    elseif type(data) == "table" then
        local parts = {}
        for k, v in pairs(data) do
            table.insert(parts, string.format('"%s":%s', k, json_encode(v)))
        end
        return "{" .. table.concat(parts, ",") .. "}"
    else
        return tostring(data)
    end
end

-- Function to check if API key contains only valid characters
local function is_valid_api_key(key)
    -- Check if key starts with "ks-"
    if not key:match("^ks%-") then return false end
    
    -- Remove prefix for length check
    local key_without_prefix = key:sub(4)
    
    -- Check length (should be 16 chars after prefix)
    if #key_without_prefix ~= 16 then return false end
    
    -- Check valid characters (a-z, A-Z, 0-9)
    local valid_pattern = "^[%w]+$"
    return key_without_prefix:match(valid_pattern) ~= nil
end

-- ###################################
-- ######## MOD CONFIGURATION ########
-- ###################################

-- Server URL to send statistics
local SERVER_URL = "http://localhost:1204"

-- Initial config
local config = {
    api_key = nil,
    storage_mode = "api"
}

-- Function to load the config or create the directory/file if it doesn't exist
local function load_config()
    -- Create the directory if it doesn't exist
    local success = love.filesystem.createDirectory("config")
    if not success then
        print("Error creating config directory")
        return
    end

    local file = io.open("config/kmirastats.jkr", "r")
    if not file then
        -- Create the file if it doesn't exist
        file = io.open("config/kmirastats.jkr", "w")
        if file then
            file:close()
            print("Config file created successfully")
        else
            print("Error creating config file")
            return
        end
    else
        -- If the file already exists, read its content
        local content = file:read("*all")
        file:close()
        if content and content ~= "" then
            local loaded_config = load("return " .. content)
            if loaded_config then
                config = loaded_config()
            else
                config.api_key = content
            end
        end
    end
end

-- Function to save the config
local function save_config()
    love.filesystem.createDirectory("config")
    local config_data = string.format("{api_key='%s', storage_mode='%s'}", config.api_key or "", config.storage_mode or "api")
    love.filesystem.write("config/kmirastats.jkr", config_data)
end

-- ###############################
-- ######## GET RUN STATS ########
-- ###############################

function gameDataFromGame(game, savedGame)
    local gameData = game.GAME
    local blind_config
    
    if savedGame then
        blind_config = G.P_BLINDS[game.BLIND.config_blind] or G.P_BLINDS.bl_small
    else
        blind_config = gameData.blind.config.blind or G.P_BLINDS.bl_small
    end
    
    local lost_to = localize({ type = "name_text", key = blind_config.key, set = "Blind" })
    local stake_names = {"White Stake", "Red Stake", "Green Stake", "Black Stake",
                         "Blue Stake", "Purple Stake", "Orange Stake", "Gold Stake"}
    
    return {
        bestHand = number_format(gameData.round_scores["hand"].amt),
        mostPlayedHand = GetMostPlayedHand(gameData),
        cardsPlayed = gameData.round_scores["cards_played"].amt,
        cardsDiscarded = gameData.round_scores["cards_discarded"].amt,
        cardsPurchased = gameData.round_scores["cards_purchased"].amt,
        timesRerolled = gameData.round_scores["times_rerolled"].amt,
        won = gameData.round_resets.ante > gameData.win_ante,
        seed = gameData.pseudorandom.seed,
        ante = gameData.round_resets.ante,
        round = gameData.round,
        lostTo = lost_to,
        deck = gameData.selected_back.name,
        stake = stake_names[gameData.stake] or tostring(gameData.stake)
    }
end

function GetMostPlayedHand(game)
    local handname, amount = localize("k_none"), 0
    for k, v in pairs(game.hand_usage) do
        if v.count > amount then
            handname = v.order
            amount = v.count
        end
    end
    return localize(handname, "poker_hands")
end

-- #######################################################################################
-- ######## GENERATE APIKEY IF IT DOESN'T EXIST AND THEREFORE SEND IT TO THE SRV  ########
-- #######################################################################################

-- Function to notify the server of a new API key
local function notify_server_of_new_api_key(api_key)
    local api_url = SERVER_URL .. "/api/new_key"
    local json_data = string.format('{"api_key":"%s"}', api_key)
    local max_retries = 1
    local retry_delay = 2

    local function try_send()
        local code, body, headers = https.request(api_url, {
            method = "POST",
            headers = {
                ["Content-Type"] = "application/json",
                ["Content-Length"] = tostring(#json_data)
            },
            data = json_data
        })
        return code, body
    end

    for attempt = 1, max_retries do
        local code, body = try_send()
        if code == 200 then
            print(string.format("New API key successfully sent to the server (attempt %d)", attempt))
            return true
        else
            print(string.format("Error sending API key (attempt %d). Code: %s", attempt, code or "nil"))
            print("Response:", body or "No response")
            if attempt < max_retries then
                print(string.format("Retrying in %d seconds...", retry_delay))
                love.timer.sleep(retry_delay)
            end
        end
    end

    print("Error: Could not send the API key after 2 attempts")
    return false
end

-- Function to notify server of API key status
local function notify_key_status(status, api_key)
    local api_url = SERVER_URL .. "/api/key/status"
    local json_data = json_encode({
        status = status,
        api_key = api_key or "None"
    })
    
    https.request(api_url, {
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = tostring(#json_data)
        },
        data = json_data
    })
end

-- Function to request a new API key from the server
local function request_new_api_key()
    local api_url = SERVER_URL .. "/api/request_key"
    local max_retries = 2
    local retry_delay = 2

    local function try_request()
        local code, body, headers = https.request(api_url, {
            method = "GET",
            headers = {
                ["Content-Type"] = "application/json"
            }
        })
        return code, body
    end

    for attempt = 1, max_retries do
        local code, body = try_request()
        if code == 200 and body then
            -- Extraer API key del JSON
            local api_key = body:match('"api_key":%s*"(.-)"')
            
            if api_key then
                -- Verificar formato
                if is_valid_api_key(api_key) then
                    print(string.format("New API key successfully received from server (attempt %d)", attempt))
                    -- Notificar éxito al servidor
                    notify_key_status("success", api_key)
                    return api_key
                else
                    print("Error: Invalid API key format received")
                    -- Notificar formato inválido
                    notify_key_status("invalid_format", api_key)
                end
            else
                print("Error: Could not find api_key in response")
                -- Notificar fallo
                notify_key_status("request_failed")
            end
        else
            print(string.format("Error requesting API key (attempt %d). Code: %s", attempt, code or "nil"))
            -- Notificar fallo
            notify_key_status("request_failed")
        end

        if attempt < max_retries then
            print(string.format("Retrying in %d seconds...", retry_delay))
            love.timer.sleep(retry_delay)
        end
    end

    return nil
end

-- Function to generate a random API key
local function generate_api_key()
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local key = ""
    for i = 1, 16 do
        local rand = math.random(1, #chars)
        key = key .. chars:sub(rand, rand)
    end

    notify_server_of_new_api_key(key)

    return key
end

-- Function to get or generate the API key
function get_or_generate_api_key()
    load_config()
    
    -- Verify if the API key already exists
    if config.api_key and config.api_key ~= "" then
        -- Check if the API key is valid (length and characters)
        if is_valid_api_key(config.api_key) then
            print("Valid API key found:", config.api_key)
            notify_key_status("loaded_valid", config.api_key)
            return config.api_key
        else
            print("Invalid API key found, requesting new one...")
            -- Notificar al servidor que la API key cargada es inválida
            notify_key_status("loaded_invalid", config.api_key)
        end
    end
    
    -- Request new API key from server
    print("Requesting new API key from server...")
    local new_api_key = request_new_api_key()
    
    if new_api_key then
        config.api_key = new_api_key
        save_config()
        print("New API key received and saved:", new_api_key)
        return new_api_key
    else
        print("Error: Could not get API key from server")
        return nil
    end
end

-- Load or generate the API key
local api_key = get_or_generate_api_key()

-- ##############################################################
-- ######## SEND STATS TO THE SRV OR GENERATE IT LOCALLY ########
-- ##############################################################

-- Escape function for JSON strings
local function escape_json(str)
    if not str then return "" end
    return tostring(str)
        :gsub('\\', '\\\\')
        :gsub('"', '\\"')
        :gsub('\n', '\\n')
        :gsub('\r', '\\r')
end

-- Generate JSON from stats
local function stats_to_json(stats, api_key)
    local t = {
        time = os.date("%Y-%m-%d %H:%M:%S"),
        seed = escape_json(stats.seed),
        deck = escape_json(stats.deck),
        stake = escape_json(stats.stake),
        won = stats.won,
        lostTo = escape_json(stats.lostTo),
        ante = stats.ante or 0,
        round = stats.round or 0,
        mostPlayedHand = escape_json(stats.mostPlayedHand),
        bestHand = escape_json(stats.bestHand),
        cardsPlayed = stats.cardsPlayed or 0,
        cardsDiscarded = stats.cardsDiscarded or 0,
        cardsPurchased = stats.cardsPurchased or 0,
        timesRerolled = stats.timesRerolled or 0
    }
    if api_key then t.api_key = escape_json(api_key) end

    local json_parts = {"{"}
    local first = true
    for k, v in pairs(t) do
        if not first then table.insert(json_parts, ",") end
        first = false
        local value_str = (type(v) == "string") and string.format('"%s"', v) or tostring(v)
        table.insert(json_parts, string.format('"%s":%s', k, value_str))
    end
    table.insert(json_parts, "}")
    return table.concat(json_parts)
end

-- Count the number of runs in the local stats file
local function get_run_count()
    local count = 0
    local f = io.open("./kmirastats.txt", "r")
    if f then
        for line in f:lines() do
            if line:find("RUN INFO") then count = count + 1 end
        end
        f:close()
    end
    return count + 1
end

-- Save stats to a local file
local function save_stats_to_local_file(stats)
    local run_number = get_run_count()
    local current_time = os.date("%Y-%m-%d %H:%M:%S")
    local template = [[
┌────────────────────────────────────────────────┐ 
│                 RUN INFO (N %03d)               │
├─────────────────────┬──────────────────────────┤
│         Date/Time   │ %s      │
│              Seed   │ %-22s   │
│              Deck   │ %-22s   │
│             Stake   │ %-22s   │
├─────────────────────┼──────────────────────────┤
│            Result   │ %-22s   │
│              Ante   │ %-22d   │
│             Round   │ %-22d   │
│  Most Played Hand   │ %-22s   │
│         Best Hand   │ %-22s   │
│      Cards Played   │ %-22d   │
│   Cards Discarded   │ %-22d   │
│   Cards Purchased   │ %-22d   │
│    Times Rerolled   │ %-22d   │
├─────────────────────┴──────────────────────────┤
│ v0.0.3                        stats.kmiras.com │
└────────────────────────────────────────────────┘
]]
    local result_text = stats.won and "Won!" or string.format("X Lost (to %s)", stats.lostTo or "-")
    local formatted_stats = string.format(template,
        run_number, current_time, stats.seed or "", stats.deck or "", stats.stake or "",
        result_text, stats.ante or 0, stats.round or 0, stats.mostPlayedHand or "",
        stats.bestHand or "", stats.cardsPlayed or 0, stats.cardsDiscarded or 0,
        stats.cardsPurchased or 0, stats.timesRerolled or 0
    )
    local f = io.open("./kmirastats.txt", "a")
    if f then 
        f:write(formatted_stats .. "\n")
        f:close()
    else 
        print("Error saving stats to local file") 
    end
end

-- Send stats to the API
local function send_stats_to_api(stats)
    local json = stats_to_json(stats, get_or_generate_api_key())
    local code, body = https.request(SERVER_URL.."/api/stats", {
        method = "POST",
        headers = {["Content-Type"]="application/json",["Content-Length"]=#json},
        data = json
    })
    print(code==200 and "Data sent successfully." or "Error sending data: "..(code or ""))
end

-- Send or save stats based on the storage mode
local function send_stats(stats)
    if config.storage_mode == "api" then
        send_stats_to_api(stats)
    elseif config.storage_mode == "local" then
        save_stats_to_local_file(stats)
    else
        print("ERROR: Invalid storage mode: " .. tostring(config.storage_mode))
    end
end



-- #################################################################################################
-- ######## OBTAIN WHEN THE PLAYER WINS/LOSES AND SEND THE SIGNAL TO SEND STATISTICS ###############
-- #################################################################################################

local game_start_run_ref = Game.start_run
function Game:start_run(args)
    game_start_run_ref(self, args)
    G.GAME.data_sent = false
end

local game_update_game_over_ref = Game.update_game_over
function Game:update_game_over(dt)
    game_update_game_over_ref(self, dt)
    if not G.GAME.data_sent then
        G.GAME.data_sent = true
        G.E_MANAGER:add_event(Event({
            trigger = "immediate",
            delay = 0,
            blocking = false,
            func = function()
                send_stats(gameDataFromGame(G, false))
                return true
            end,
        }))
    end
end

local game_update_ref = Game.update

function Game:update(dt)
    game_update_ref(self, dt)

    if not G.GAME.data_sent then
        if G.GAME.won then
            G.GAME.data_sent = true
            G.E_MANAGER:add_event(Event({
                trigger = "immediate",
                delay = 0,
                blocking = false,
                func = function()
                    send_stats(gameDataFromGame(G, false))
                    return true
                end,
            }))
        end
    end
end

-- ###########################
-- ######## UI CONFIG ########
-- ###########################

KS.extra_tabs = function()
    return {
        {
            label = 'Configuration',
            tab_definition_function = function()
                return {
                    n = G.UIT.ROOT,
                    config = {
                        align = "cm",
                        padding = 0.1,
                        colour = G.C.DARK_GREY,
                        r = 0.2,
                        outline = 0.05,
                        outline_colour = G.C.UI.OUTLINE,
                        w = 20,
                        h = 5
                    },
                    nodes = {
                        {
                            n = G.UIT.R,
                            config = {
                                align = "cm",
                                flow = "col",
                                padding = 0.5,
                                min_w = 15,
                                w = 18,
                                h = 4
                            },
                            nodes = {
                                {
                                    n = G.UIT.C,
                                    config = {
                                        align = "cm",
                                        padding = 0.4,
                                        margin = 0.3,
                                        colour = G.C.UI.BACKGROUND,
                                        r = 0.15,
                                        outline = 0.02,
                                        outline_colour = G.C.UI.OUTLINE,
                                        w = 16,
                                        h = 3
                                    },
                                    nodes = {
                                        {
                                            n = G.UIT.R,
                                            config = {
                                                flow = "col",
                                                padding = 0.2,
                                                w = 15,
                                                h = 2.5
                                            },
                                            nodes = {
                                                {
                                                    n = G.UIT.T,
                                                    config = {
                                                        text = "Statistics Storage Mode: ",
                                                        colour = G.C.UI.TEXT_LIGHT,
                                                        scale = 1.0,
                                                        w = 14,
                                                        h = 1
                                                    }
                                                },
                                                {
                                                    n = G.UIT.C,
                                                    nodes = {
                                                        create_option_cycle({
                                                            w = 6,
                                                            label = "Storage Mode",
                                                            scale = 0.8,
                                                            options = {
                                                                "API: send data to server",
                                                                "LOCAL: save data locally",
                                                            },
                                                            opt_callback = "toggle_storage_mode",
                                                            current_option = config.storage_mode == "api" and 1 or 2,
                                                        })
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            end
        },
        {
            label = 'API Key',
            tab_definition_function = function()
                return {
                    n = G.UIT.ROOT,
                    config = {
                        align = "cm",
                        padding = 0.1,
                        colour = G.C.DARK_GREY,
                        r = 0.2,
                        outline = 0.05,
                        outline_colour = G.C.UI.OUTLINE,
                        w = 20,
                        h = 5
                    },
                    nodes = {
                        {
                            n = G.UIT.R,
                            config = {
                                align = "cm",
                                flow = "col",
                                padding = 0.5,
                                min_w = 15,
                                w = 18,
                                h = 4
                            },
                            nodes = {
                                {
                                    n = G.UIT.C,
                                    config = {
                                        align = "cm",
                                        padding = 0.4,
                                        margin = 0.3,
                                        colour = G.C.UI.BACKGROUND,
                                        r = 0.15,
                                        outline = 0.02,
                                        outline_colour = G.C.UI.OUTLINE,
                                        w = 16,
                                        h = 3
                                    },
                                    nodes = {
                                        {
                                            n = G.UIT.R,
                                            config = {
                                                flow = "col",
                                                padding = 0.2,
                                                w = 15,
                                                h = 2.5
                                            },
                                            nodes = {
                                                {
                                                    n = G.UIT.T,
                                                    config = {
                                                        text = "Generated API Key:",
                                                        colour = G.C.UI.TEXT_LIGHT,
                                                        scale = 1.0,
                                                        w = 14,
                                                        h = 1
                                                    }
                                                },
                                                {
                                                    n = G.UIT.T,
                                                    config = {
                                                        text = " " .. api_key,
                                                        colour = HEX("d82934"),
                                                        scale = 1.0,
                                                        w = 14,
                                                        h = 1,
                                                        button = "copy_api_key",
                                                        tooltip = {
                                                            title = "Click to Copy",
                                                            text = {"Click to copy the API key to your clipboard."}
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            end
        }
    }
end

-- ##############################################
-- ######## FUNCTION TO COPY THE API KEY ########
-- ##############################################

function G.FUNCS.copy_api_key(e)
    local api_key = e.config.text:match(" (.+)")
    love.system.setClipboardText(api_key)
end

-- ##############################################
-- ######## FUNCTION TO CHANGE STORAGE MODE #####
-- ##############################################

function G.FUNCS.toggle_storage_mode(e)
    local new_mode = e.to_key == 1 and "api" or "local"
    config.storage_mode = new_mode
    
    print(string.format("Changed to:\nconfig.storage_mode: %s\nfrom_key: %d\nto_key: %d",
        config.storage_mode, 
        e.from_key,
        e.to_key))
    
    save_config()
end