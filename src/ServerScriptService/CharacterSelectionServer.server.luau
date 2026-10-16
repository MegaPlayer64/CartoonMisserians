--[[
	CharacterSelectionServer (Script)
	Ubicacion: ServerScriptService.CharacterSelectionServer

	Maneja las solicitudes de seleccion de personajes desde el cliente.
	Valida que el personaje exista en CharacterDatabase y guarda la
	eleccion como Atributos seguros en el Player del servidor.

	Atributos asignados:
	  - SelectedToonflow   -> string (nombre del Toonflow elegido)
	  - SelectedDevilish   -> string (nombre del Devilish elegido)

	Dependencias:
	  - ReplicatedStorage.Framework.CharacterDatabase
	  - ReplicatedStorage.Framework.Remotes.SelectCharacterRemote (RemoteEvent)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterDatabase = require(ReplicatedStorage.Framework.CharacterDatabase)

local Remotes = ReplicatedStorage.Framework.Remotes
local SelectCharacterRemote = Remotes:WaitForChild("SelectCharacterRemote")

--[[
	Inicializa los atributos de seleccion por defecto en un jugador.
	Se llama al unirse el jugador y garantiza que siempre tenga un valor.
]]
local function initDefaultSelections(player)
	if not player:GetAttribute("SelectedToonflow") then
		player:SetAttribute("SelectedToonflow", CharacterDatabase.DefaultToonflow)
	end
	if not player:GetAttribute("SelectedDevilish") then
		player:SetAttribute("SelectedDevilish", CharacterDatabase.DefaultDevilish)
	end
end

--[[
	Maneja la solicitud de seleccion de personaje desde el cliente.

	Parametros recibidos:
	  characterType -> string: "Toonflow" o "Devilish"
	  characterName -> string: nombre del personaje en CharacterDatabase

	Validaciones del servidor (anti-exploit):
	  1. characterType debe ser "Toonflow" o "Devilish"
	  2. characterName debe existir en la base de datos
	  3. No se confia en ningun dato del cliente sin validacion
]]
SelectCharacterRemote.OnServerEvent:Connect(function(player, characterType, characterName)
	-- Validar tipos de argumentos
	if typeof(characterType) ~= "string" or typeof(characterName) ~= "string" then
		return
	end

	-- Validar characterType
	if characterType ~= CharacterDatabase.CharacterType.Toonflow and characterType ~= CharacterDatabase.CharacterType.Devilish then
		return
	end

	-- Validar que el personaje exista en la base de datos
	if characterType == CharacterDatabase.CharacterType.Toonflow then
		if not CharacterDatabase.IsValidToonflow(characterName) then
			return
		end
		-- Asignar el atributo seguro en el servidor
		player:SetAttribute("SelectedToonflow", characterName)
		print("[CharacterSelection] " .. player.Name .. " selecciono Toonflow: " .. characterName)

	elseif characterType == CharacterDatabase.CharacterType.Devilish then
		if not CharacterDatabase.IsValidDevilish(characterName) then
			return
		end
		-- Asignar el atributo seguro en el servidor
		player:SetAttribute("SelectedDevilish", characterName)
		print("[CharacterSelection] " .. player.Name .. " selecciono Devilish: " .. characterName)
	end
end)

-- == INICIALIZACION DE JUGADORES ==

-- Inicializar selecciones por defecto para jugadores que ya estan en el juego
for _, player in ipairs(Players:GetPlayers()) do
	initDefaultSelections(player)
end

-- Inicializar selecciones por defecto para nuevos jugadores
Players.PlayerAdded:Connect(function(player)
	initDefaultSelections(player)
end)

print("[CharacterSelectionServer] Sistema de seleccion de personajes inicializado correctamente.")