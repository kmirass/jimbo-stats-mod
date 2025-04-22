local https = require("SMODS.https") -- Usar SMODS.https para solicitudes HTTP
local ltn12 = require("ltn12") -- Para manejar el cuerpo de la solicitud

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

function write_stats_to_local(stats)
    local file = io.open("jimbostats_local.txt", "a")
    if file then
        local output = string.format(
            '{"time":"%s","seed":"%s","deck":"%s","stake":"%s","won":%s,"lostTo":"%s","ante":%d,"round":%d,"mostPlayedHand":"%s","bestHand":"%s","cardsPlayed":%d,"cardsDiscarded":%d,"cardsPurchased":%d,"timesRerolled":%d}\n',
            os.date("%Y-%m-%d %H:%M:%S"),
            stats.seed or "",
            stats.deck or "",
            stats.stake or "",
            tostring(stats.won),
            stats.lostTo or "",
            stats.ante or 0,
            stats.round or 0,
            stats.mostPlayedHand or "",
            stats.bestHand or "",
            stats.cardsPlayed or 0,
            stats.cardsDiscarded or 0,
            stats.cardsPurchased or 0,
            stats.timesRerolled or 0
        )
        file:write(output)
        file:close()
    end
end

-- Enviar estadísticas a la API local
local function send_stats_to_api(stats)
    local api_url = "http://localhost:8080/api/stats" -- Cambia el puerto si es necesario
    local api_key = get_or_generate_api_key()

    local json_data = string.format(
        '{"api_key":"%s","time":"%s","seed":"%s","deck":"%s","stake":"%s","won":%s,"lostTo":"%s","ante":%d,"round":%d,"mostPlayedHand":"%s","bestHand":"%s","cardsPlayed":%d,"cardsDiscarded":%d,"cardsPurchased":%d,"timesRerolled":%d}',
        api_key,
        os.date("%Y-%m-%d %H:%M:%S"),
        stats.seed or "",
        stats.deck or "",
        stats.stake or "",
        tostring(stats.won),
        stats.lostTo or "",
        stats.ante or 0,
        stats.round or 0,
        stats.mostPlayedHand or "",
        stats.bestHand or "",
        stats.cardsPlayed or 0,
        stats.cardsDiscarded or 0,
        stats.cardsPurchased or 0,
        stats.timesRerolled or 0
    )

    -- Realizar la solicitud HTTP POST
    local code, body, headers = https.request(api_url, {
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = tostring(#json_data)
        },
        data = json_data
    })

    -- Manejar la respuesta
    if code == 200 then
        print("Datos enviados correctamente a la API local.")
    else
        print("Error al enviar datos a la API local. Código de estado:", code)
        print("Respuesta:", body or "Sin respuesta")
    end
end

local function send_stats_to_api_async(stats)
    local api_url = "http://localhost:8080/api/stats" -- Cambia el puerto si es necesario
    local api_key = get_or_generate_api_key()

    local json_data = string.format(
        '{"api_key":"%s","time":"%s","seed":"%s","deck":"%s","stake":"%s","won":%s,"lostTo":"%s","ante":%d,"round":%d,"mostPlayedHand":"%s","bestHand":"%s","cardsPlayed":%d,"cardsDiscarded":%d,"cardsPurchased":%d,"timesRerolled":%d}',
        api_key,
        os.date("%Y-%m-%d %H:%M:%S"),
        stats.seed or "",
        stats.deck or "",
        stats.stake or "",
        tostring(stats.won),
        stats.lostTo or "",
        stats.ante or 0,
        stats.round or 0,
        stats.mostPlayedHand or "",
        stats.bestHand or "",
        stats.cardsPlayed or 0,
        stats.cardsDiscarded or 0,
        stats.cardsPurchased or 0,
        stats.timesRerolled or 0
    )

    -- Crear un hilo para manejar la solicitud
    local thread = love.thread.newThread(function()
        local code, body, headers = https.request(api_url, {
            method = "POST",
            headers = {
                ["Content-Type"] = "application/json",
                ["Content-Length"] = tostring(#json_data)
            },
            data = json_data
        })

        -- Manejar la respuesta
        if code == 200 then
            print("Datos enviados correctamente a la API local.")
        else
            print("Error al enviar datos a la API local. Código de estado:", code)
            print("Respuesta:", body or "Sin respuesta")
        end
    end)

    thread:start()
end

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
                send_stats_to_api(gameDataFromGame(G, false))
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
                    send_stats_to_api(gameDataFromGame(G, false))
                    return true
                end,
            }))
        end
    end
end


local config_dir = love.filesystem.getSaveDirectory() .. "/config"
local config_file = config_dir .. "/kmirastats.jkr"

-- Crear directorio si no existe
local function ensure_config_dir()
    love.filesystem.createDirectory("config")
end

-- URL del servidor (puedes cambiarla según sea necesario)
local SERVER_URL = "http://localhost:8080"

-- Enviar nueva API key al servidor
local function notify_server_of_new_api_key(api_key)
    local api_url = SERVER_URL .. "/api/new_key"
    local json_data = string.format('{"api_key":"%s"}', api_key)

    -- Realizar la solicitud HTTP POST
    local code, body, headers = https.request(api_url, {
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = tostring(#json_data)
        },
        data = json_data
    })

    -- Manejar la respuesta
    if code == 200 then
        print("Nueva API key enviada correctamente al servidor.")
    else
        print("Error al enviar la nueva API key al servidor. Código de estado:", code)
        print("Respuesta:", body or "Sin respuesta")
    end
end

-- Generar API key
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

-- Guardar API key en archivo
local function save_api_key(api_key)
    ensure_config_dir()
    local file = io.open(config_file, "w")
    if file then
        file:write(api_key)
        file:close()
    end
end

-- Cargar API key desde archivo
local function load_api_key()
    local file = io.open(config_file, "r")
    if file then
        local api_key = file:read("*a")
        file:close()
        return api_key
    end
    return nil
end

-- Obtener o generar API key
function get_or_generate_api_key()
    local api_key = load_api_key()
    if not api_key then
        api_key = generate_api_key()
        save_api_key(api_key)
    end
    return tostring(api_key) -- Asegúrate de que sea una cadena
end

-- Obtener la API key
local api_key = get_or_generate_api_key()

SMODS.current_mod.extra_tabs = function()
    return {
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
                    },
                    nodes = {
                        {
                            n = G.UIT.C,
                            config = {
                                align = "cm",
                                padding = 0.1,
                                colour = G.C.UI.BACKGROUND,
                                r = 0.15,
                                outline = 0.03,
                                outline_colour = G.C.UI.OUTLINE,
                                shadow = true,
                            },
                            nodes = {
                                {
                                    n = G.UIT.R,
                                    config = {
                                        align = "cm",
                                    },
                                    nodes = {
                                        {
                                            n = G.UIT.T,
                                            config = {
                                                text = "Generated API Key:",
                                                colour = G.C.UI.TEXT_LIGHT,
                                                scale = 1.0,
                                                align = "cm",
                                            },
                                        },
                                        {
                                            n = G.UIT.T,
                                            config = {
                                                text = " " .. api_key,
                                                colour = HEX("d82934"),
                                                scale = 1.0,
                                                align = "cm",
                                                button = "copy_api_key",
                                                tooltip = {
                                                    title = "Click to Copy",
                                                    text = {"Click to copy the API key to your clipboard."},
                                                },
                                            },
                                        },
                                    },
                                },
                            },
                        },
                    },
                }
            end,
        },
    }
end

function G.FUNCS.copy_api_key(e)
    local api_key = e.config.text:match(" (.+)")
    love.system.setClipboardText(api_key)
end