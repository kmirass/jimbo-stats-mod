local https = require("SMODS.https")
local KS = SMODS.current_mod

-- #######################################
-- ######## CONFIGURACION DEL MOD ########
-- #######################################

-- URL del servidor al que se envían las estadísticas
local SERVER_URL = "https://stats.kmiras.com:1204"

-- Configuración inicial
local config = {
    api_key = nil,
    storage_mode = "api"
}

-- Función para cargar la configuración
local function load_config()
    -- Crear el directorio si no existe
    local success = love.filesystem.createDirectory("config")
    if not success then
        print("Error al crear el directorio config")
        return
    end

    local file = io.open("config/kmirastats.jkr", "r")
    if not file then
        -- Si el archivo no existe, crearlo
        file = io.open("config/kmirastats.jkr", "w")
        if file then
            file:close()
            print("Archivo de configuración creado")
        else
            print("Error al crear el archivo de configuración")
            return
        end
    else
        -- Si el archivo existe, leer el contenido
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

-- Función para guardar la configuración
local function save_config()
    love.filesystem.createDirectory("config")
    local config_data = string.format("{api_key='%s', storage_mode='%s'}", config.api_key or "", config.storage_mode or "api")
    love.filesystem.write("config/kmirastats.jkr", config_data)
end

-- ################################################
-- ######## OBTENER ESTADISTICAS DEL JUEGO ########
-- ################################################

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

-- #####################################################################################
-- ######## GENERAR API KEY SI NO ESTA CREADA Y ENVIARLA O LEERLA SI YA LO ESTÁ ########
-- #####################################################################################

-- Funcion de enviar nueva API key al servidor
local function notify_server_of_new_api_key(api_key)
    local api_url = SERVER_URL .. "/api/new_key"
    local json_data = string.format('{"api_key":"%s"}', api_key)
    local max_retries = 3
    local retry_delay = 2 -- segundos
    
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

    -- Intentar enviar con reintentos
    for attempt = 1, max_retries do
        local code, body = try_send()
        
        if code == 200 then
            print(string.format("Nueva API key enviada correctamente al servidor (intento %d)", attempt))
            return true
        else
            print(string.format("Error al enviar API key (intento %d). Código: %s", attempt, code or "nil"))
            print("Respuesta:", body or "Sin respuesta")
            
            if attempt < max_retries then
                print(string.format("Reintentando en %d segundos...", retry_delay))
                love.timer.sleep(retry_delay)
            end
        end
    end

    print("Error: No se pudo enviar la API key después de " .. max_retries .. " intentos")
    return false
end

-- Funcion para generar API key
local function generate_api_key()
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local key = ""
    for i = 1, 16 do
        local rand = math.random(1, #chars)
        key = key .. chars:sub(rand, rand)
    end

    -- Notificar al servidor sobre la nueva API key
    notify_server_of_new_api_key(key)

    return key
end

-- Funcion obtener o generar (y enviar al srv) la API key
function get_or_generate_api_key()
    -- Cargar configuración primero si existe
    load_config()
    
    -- Verificar si ya tenemos una API key válida
    if config.api_key and config.api_key ~= "" then
        print("Usando API key existente:", config.api_key)
        return config.api_key
    end
    
    -- Si no hay API key, generar una nueva
    print("Generando nueva API key...")
    config.api_key = generate_api_key()
    save_config()
    print("Nueva API key generada:", config.api_key)
    return config.api_key
end

-- Carga o crea la API Key
local api_key = get_or_generate_api_key()

-- ######################################################################
-- ######## ENVIAR ESTADÍSTICAS AL SERVIDOR O GUARDAR LOCALMENTE ########
-- ######################################################################

-- Escapar cadenas para JSON
local function escape_json(str)
    if not str then return "" end
    return tostring(str)
        :gsub('\\', '\\\\')
        :gsub('"', '\\"')
        :gsub('\n', '\\n')
        :gsub('\r', '\\r')
end

-- Generar JSON para estadísticas
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

    -- Optimizado: usar tabla para concatenación eficiente
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

-- Contar partidas por delimitador
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

-- Guardar estadísticas en archivo de texto
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
        print("Error al guardar estadísticas.") 
    end
end

-- Enviar estadísticas a la API
local function send_stats_to_api(stats)
    local json = stats_to_json(stats, get_or_generate_api_key())
    local code, body = https.request(SERVER_URL.."/api/stats", {
        method = "POST",
        headers = {["Content-Type"]="application/json",["Content-Length"]=#json},
        data = json
    })
    print(code==200 and "Datos enviados correctamente." or "Error al enviar datos: "..(code or ""))
end

-- Enviar o guardar según configuración
local function send_stats(stats)
    if config.storage_mode == "api" then
        send_stats_to_api(stats)
    elseif config.storage_mode == "local" then
        save_stats_to_local_file(stats)
    else
        print("ERROR: Modo de almacenamiento no válido: " .. tostring(config.storage_mode))
    end
end



-- #################################################################################################
-- ######## OBTENER CUANDO PIERRDE/GANA EL JUGADOR Y MANDAR LA SEÑAL DE ENVIAR ESTADISTICAS ########
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
    -- Llamar a la función original de actualización
    game_update_ref(self, dt)

    -- Verificar si los datos ya fueron enviados
    if not G.GAME.data_sent then
        -- Si G.GAME.won se convierte en true, enviar los datos
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
                                -- Bloque Storage Mode
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
                                                            opt_callback = "toggle_storage_mode", -- Esto llamará a G.FUNCS.toggle_storage_mode
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
                                -- Bloque API Key
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
-- ######## FUNCION DE COPIAR LA API KEY ########
-- ##############################################

function G.FUNCS.copy_api_key(e)
    local api_key = e.config.text:match(" (.+)")
    love.system.setClipboardText(api_key)
end

-- ##############################################
-- ######## FUNCION DE CAMBIAR STORAGE MODE #####
-- ##############################################

function G.FUNCS.toggle_storage_mode(e)
    local new_mode = e.to_key == 1 and "api" or "local"
    config.storage_mode = new_mode
    
    -- Debug print
    print(string.format("Changed to:\nconfig.storage_mode: %s\nfrom_key: %d\nto_key: %d\ncorrectly", 
        config.storage_mode, 
        e.from_key,
        e.to_key))
    
    save_config()
end