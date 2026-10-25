--[[
	UIManager (LocalScript)
	Ubicacion: StarterPlayer.StarterPlayerScripts.UIManager

	Gestiona la visibilidad automatica de LobbyGUI, GameGUI y GlobalGUI
	en sincronia con el estado de la partida enviado por MatchManager.

	Reglas de visibilidad:
	  - GlobalGUI               -> Siempre activo (Enabled = true)
	  - Intermission / Lobby    -> LobbyGUI visible, GameGUI oculta
	  - RoleAssigned / RoleSel. -> LobbyGUI oculta, GameGUI visible
	  - InProgress              -> LobbyGUI oculta, GameGUI visible
	  - Ending                  -> LobbyGUI oculta, GameGUI visible
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local Remotes = ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Remotes")
local MatchStateRemote = Remotes:WaitForChild("MatchState")

-- == REFERENCIAS A LAS GUIS ==
local function getGUI(name)
	return PlayerGui:FindFirstChild(name) or PlayerGui:WaitForChild(name, 5)
end

local LobbyGUI = getGUI("LobbyGUI")
local GameGUI = getGUI("GameGUI")
local GlobalGUI = getGUI("GlobalGUI")

-- Asegurar que GlobalGUI esté siempre habilitado
if GlobalGUI then
	GlobalGUI.Enabled = true
end

-- == ESTADO ACTUAL DE LA PARTIDA ==
local currentMatchState = "Intermission"

--[[
	Aplica la visibilidad de las GUIS segun el estado de la partida.
]]
local function applyUIVisibility(matchState)
	currentMatchState = matchState

	-- Re-resolver las GUI en cada llamada: si alguna tiene ResetOnSpawn = true se reclona al
	-- reaparecer el personaje (el servidor reemplaza el Character en cada partida) y las
	-- referencias guardadas al inicio apuntarían a instancias destruidas.
	local LobbyGUI = PlayerGui:FindFirstChild("LobbyGUI")
	local GameGUI = PlayerGui:FindFirstChild("GameGUI")
	local GlobalGUI = PlayerGui:FindFirstChild("GlobalGUI")

	-- Mantener GlobalGUI siempre activo para temporizadores y controles táctiles
	if GlobalGUI then
		GlobalGUI.Enabled = true
	end

	if matchState == "Intermission" then
		-- Lobby: mostrar LobbyGUI, ocultar GameGUI
		if LobbyGUI then LobbyGUI.Enabled = true end
		if GameGUI then GameGUI.Enabled = false end

	elseif matchState == "RoleAssigned" or matchState == "RoleSelection" then
		-- Seleccion/Asignacion de roles: ocultar LobbyGUI, mostrar GameGUI
		if LobbyGUI then LobbyGUI.Enabled = false end
		if GameGUI then GameGUI.Enabled = true end

	elseif matchState == "InProgress" then
		-- En juego: ocultar LobbyGUI, mostrar GameGUI
		if LobbyGUI then LobbyGUI.Enabled = false end
		if GameGUI then GameGUI.Enabled = true end

	elseif matchState == "Ending" then
		-- Fin de partida: mantener GameGUI visible para mostrar resultados
		if LobbyGUI then LobbyGUI.Enabled = false end
		if GameGUI then GameGUI.Enabled = true end
	end
end

-- == ESCUCHAR CAMBIOS DE ESTADO DE PARTIDA ==
MatchStateRemote.OnClientEvent:Connect(function(state, data)
	applyUIVisibility(state)
end)

-- == MANEJO DE MUERTE DEL JUGADOR ==
player.CharacterAdded:Connect(function(character)
	-- Re-sincronizar la visibilidad por si las GUI se reclonaron con el nuevo personaje
	task.delay(0.3, function()
		applyUIVisibility(currentMatchState)
	end)

	local humanoid = character:WaitForChild("Humanoid", 5)
	if humanoid then
		humanoid.Died:Connect(function()
			print("[UIManager] Jugador murio. Estado actual: " .. currentMatchState)
		end)
	end
end)

-- == INICIALIZACION ==
applyUIVisibility("Intermission")

print("[UIManager] Gestor de visibilidad de UIs (con soporte para GlobalGUI y RoleAssigned) inicializado.")