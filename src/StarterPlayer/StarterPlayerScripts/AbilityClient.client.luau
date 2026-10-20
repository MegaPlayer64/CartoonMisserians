--[[
	AbilityClient (LocalScript)
	Ubicacion: StarterPlayer.StarterPlayerScripts.AbilityClient

	Maneja el input del cliente para activar habilidades mediante teclas.
	Muestra feedback visual del estado de cooldown y resultados.

	Mapeo de teclas por defecto:
	  Tecla 1 -> Habilidad slot 1 (ej. HeredadoDeMama)
	  Tecla 2 -> Habilidad slot 2 (ej. Gamechild)
	  Tecla 3 -> Habilidad slot 3 (ej. RayosLaser)

	Dependencias:
	  - ReplicatedStorage.Framework.Remotes.UseAbility (RemoteEvent)
	  - ReplicatedStorage.Framework.Remotes.AbilityResult (RemoteEvent)
	  - ReplicatedStorage.Framework.Remotes.AbilitySync (RemoteEvent)
	  - ReplicatedStorage.Framework.Remotes.MatchState (RemoteEvent)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local Remotes = ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Remotes")
local UseAbilityRemote = Remotes:WaitForChild("UseAbility")
local AbilityResultRemote = Remotes:WaitForChild("AbilityResult")
local AbilitySyncRemote = Remotes:WaitForChild("AbilitySync")
local MatchStateRemote = Remotes:WaitForChild("MatchState")

-- Requerir VFXModule para efectos visuales/sonoros locales
local VFXModule = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("VFXModule"))

-- == CONFIGURACION DE SLOTS DE HABILIDADES ==
-- Mapeo de teclas a nombres de habilidades.
-- Estas se pueden ajustar segun el rol del jugador.
local AbilityLoadouts = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityLoadouts"))
local ABILITY_KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four }

local abilitySlots = {
	[Enum.KeyCode.One] = "HeredadoDeMama",
	[Enum.KeyCode.Two] = "Gamechild",
	[Enum.KeyCode.Three] = "UltimaOpcion",
}

-- Estado local de cooldowns para UI: [abilityName] = { charges, cooldownRemaining, isCasting }
local localCooldownState = {}

-- Flag: el jugador esta en partida?
local inMatch = false

-- Personaje actual del jugador (para diferenciar Brothercat vs Toby, etc.)
local currentCharacterName = nil

--[[
	Obtiene el punto de objetivo para habilidades con direccion.
	Para skillshots, usa la posicion del raton en el mundo 3D.
]]
local function getTargetData()
	local mouse = player:GetMouse()
	local mouseHit = mouse.Hit.Position

	-- Para habilidades que requieren una direccion (como RayosLaser),
	-- enviamos el punto donde el jugador esta apuntando.
	return mouseHit
end

--[[
	Solicita usar una habilidad al servidor.
]]
local function useAbility(abilityName)
	if not inMatch then return end
	if not player.Character then return end

	local targetData = getTargetData()
	UseAbilityRemote:FireServer(abilityName, targetData)
end

-- == DETECCION DE INPUT ==

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	-- Verificar si la tecla presionada corresponde a un slot de habilidad
	local abilityName = abilitySlots[input.KeyCode]
	if abilityName then
		useAbility(abilityName)
	end
end)

-- == RECEPCION DE RESULTADOS DEL SERVIDOR ==

-- Recibir resultados de habilidades
AbilityResultRemote.OnClientEvent:Connect(function(action, data)
	if action == "AbilitySuccess" then
		print("[AbilityClient] Habilidad ejecutada: " .. (data.abilityName or "?"))

		-- == EFECTOS VISUALES/SONOROS LOCALES POR HABILIDAD ==
		-- El servidor ya crea los VFX principales (se replican a todos),
		-- pero podemos anadir feedback local adicional aqui.
		local abilityName = data.abilityName
		if abilityName == "HeredadoDeMama" then
			-- Sonido de buff local (adicional al del servidor)
			if player.Character then
				local hrp = player.Character:FindFirstChild("HumanoidRootPart")
				if hrp then
					VFXModule.PlaySound3D(hrp, VFXModule.Sounds.Buff, 0.3)
				end
			end
		elseif abilityName == "Gamechild" then
			-- Sonido de curacion local
			if player.Character then
				local hrp = player.Character:FindFirstChild("HumanoidRootPart")
				if hrp then
					VFXModule.PlaySound3D(hrp, VFXModule.Sounds.Heal, 0.4)
				end
			end
		elseif abilityName == "UltimaOpcion" then
			-- Sonido de proyectil local
			VFXModule.PlaySound2D(VFXModule.Sounds.Projectile, 0.3)

		-- == HABILIDADES DE TOBY WILLIAMS ==
		elseif abilityName == "YaLevantate" then
			-- Sonido de colocacion de trampa
			VFXModule.PlaySound2D(VFXModule.Sounds.Buff, 0.3)
		elseif abilityName == "BaraNormal" then
			-- Sonido de golpe melee
			if player.Character then
				local hrp = player.Character:FindFirstChild("HumanoidRootPart")
				if hrp then
					VFXModule.PlaySound3D(hrp, VFXModule.Sounds.MeleeHit, 0.4)
				end
			end
		elseif abilityName == "BaraFantasma" then
			-- Sonido de golpe fantasmal
			if player.Character then
				local hrp = player.Character:FindFirstChild("HumanoidRootPart")
				if hrp then
					VFXModule.PlaySound3D(hrp, VFXModule.Sounds.MeleeHit, 0.4)
				end
			end
		elseif abilityName == "RayosLaserToby" then
			-- Sonido de rayo laser
			VFXModule.PlaySound2D(VFXModule.Sounds.Projectile, 0.5)

		-- == HABILIDADES DE TAKORITA & ANNOUNCER ==
		elseif abilityName == "EmergenciaSevera" then
			-- Sonido de canalizacion de curacion
			if player.Character then
				local hrp = player.Character:FindFirstChild("HumanoidRootPart")
				if hrp then
					VFXModule.PlaySound3D(hrp, VFXModule.Sounds.Heal, 0.4)
				end
			end
		elseif abilityName == "AnnouncerAttack" then
			-- Sonido de onda sonora / megafono
			if player.Character then
				local hrp = player.Character:FindFirstChild("HumanoidRootPart")
				if hrp then
					VFXModule.PlaySound3D(hrp, VFXModule.Sounds.SoundWave, 0.5)
				end
			end
		elseif abilityName == "CuracionAumentante" then
			-- Sonido de despliegue de botiquin
			VFXModule.PlaySound2D(VFXModule.Sounds.Medkit, 0.3)

		-- == HABILIDADES DE NEURO (DEVILISH) ==
		elseif abilityName == "CallOfStardoom" then
			-- Sonido de hover/dash energetico
			if player.Character then
				local hrp = player.Character:FindFirstChild("HumanoidRootPart")
				if hrp then
					VFXModule.PlaySound3D(hrp, VFXModule.Sounds.Stardoom, 0.5)
				end
			end
		elseif abilityName == "LightsAndAction" then
			-- Sonido de proyectil de plasma
			VFXModule.PlaySound2D(VFXModule.Sounds.Plasma, 0.5)
		elseif abilityName == "LastShow" then
			-- Sonido de carga/dash
			if player.Character then
				local hrp = player.Character:FindFirstChild("HumanoidRootPart")
				if hrp then
					VFXModule.PlaySound3D(hrp, VFXModule.Sounds.LastShow, 0.5)
				end
			end

		-- == HABILIDADES DE TRUNKS (TOONFLOW) ==
		elseif abilityName == "ZSword" then
			-- Sonido de swing de espada
			if player.Character then
				local hrp = player.Character:FindFirstChild("HumanoidRootPart")
				if hrp then
					VFXModule.PlaySound3D(hrp, VFXModule.Sounds.SwordSwing, 0.5)
				end
			end
		elseif abilityName == "KiBlasts" then
			-- Sonido de ki blast
			VFXModule.PlaySound2D(VFXModule.Sounds.KiBlast, 0.5)
		elseif abilityName == "SuperSaiyan" then
			-- Sonido de transformacion
			if player.Character then
				local hrp = player.Character:FindFirstChild("HumanoidRootPart")
				if hrp then
					VFXModule.PlaySound3D(hrp, VFXModule.Sounds.SuperSaiyan, 0.6)
				end
			end
		end

	elseif action == "AbilityFailed" then
		local reasonMessages = {
			["OnCooldown"] = "La habilidad esta en cooldown",
			["NoCharges"] = "No tienes cargas disponibles",
			["InsufficientAbsorption"] = "Absorcion insuficiente",
			["InsufficientHealth"] = "Salud insuficiente",
			["OutOfRange"] = "Objetivo fuera de rango",
			["AlreadyCasting"] = "Ya estas canalizando una habilidad",
			["InvalidState"] = "No puedes usar habilidades en este estado",
			["InsufficientFame"] = "Fama insuficiente (requiere Fame >= 25)",
			["ExecutionError"] = "La habilidad fallo; no se gasto cooldown",
			["NotExecuted"] = "La habilidad no se pudo ejecutar",
			["NoRootPart"] = "No se pudo ejecutar la habilidad",
			["NoCharacter"] = "No se pudo ejecutar la habilidad",
			["InsufficientSCells"] = "Celulas S insuficientes (requiere 10+)",
		}
		local msg = reasonMessages[data.reason] or data.reason or "Error desconocido"
		print("[AbilityClient] Habilidad fallida: " .. (data.abilityName or "?") .. " - " .. msg)
		-- Aqui se puede mostrar un mensaje en la UI del jugador
	end
end)

-- Recibir sincronizacion de cooldown desde el servidor
AbilitySyncRemote.OnClientEvent:Connect(function(abilityName, cooldownInfo)
	localCooldownState[abilityName] = cooldownInfo
	-- Aqui se puede actualizar la UI de cooldown:
	-- cooldownInfo.charges, cooldownInfo.maxCharges, cooldownInfo.cooldownRemaining, cooldownInfo.isCasting
	print(string.format("[AbilityClient] %s - Cargas: %d/%d | CD: %.1fs | Casting: %s",
		abilityName,
		cooldownInfo.charges,
		cooldownInfo.maxCharges,
		cooldownInfo.cooldownRemaining,
		tostring(cooldownInfo.isCasting)
	))
end)


-- Recibir cambios de estado de partida
MatchStateRemote.OnClientEvent:Connect(function(state, data)
	if state == "InProgress" then
		-- Solo imprimir y activar si NO estaba ya en partida
		-- Esto evita el spam del mensaje cuando el servidor envia
		-- el estado InProgress multiples veces
		if not inMatch then
			inMatch = true
			print("[AbilityClient] Partida en progreso. Habilidades activadas.")
		end
	elseif state == "Ending" or state == "Intermission" then
		-- Solo imprimir y desactivar si estaba en partida
		if inMatch then
			inMatch = false
			localCooldownState = {}
			print("[AbilityClient] Partida finalizada. Habilidades desactivadas.")
		end
	elseif state == "RoleAssigned" then
		-- El servidor nos notifica nuestro rol y personaje
		currentCharacterName = data.characterName

		-- Fuente única (compartida con el HUD y el servidor). Antes este bloque solo
		-- conocía a Neuro, Trunks, Toby, Takorita y Brothercat: los demás personajes
		-- no podían usar sus habilidades con el teclado.
		for _, keyCode in ipairs(ABILITY_KEYS) do
			abilitySlots[keyCode] = nil
		end
		for index, abilityName in ipairs(AbilityLoadouts.get(data.characterName, data.role)) do
			local keyCode = ABILITY_KEYS[index]
			if keyCode and abilityName ~= "" then
				abilitySlots[keyCode] = abilityName
			end
		end
		-- Los HUD propios de Fame/S-Cells se quitaron: al estar parentados directo a PlayerGui
		-- (sin ScreenGui) nunca se dibujaban; el HUDController ya muestra esos recursos.
		print("[AbilityClient] Rol asignado: " .. tostring(data.role) .. " | Personaje: " .. tostring(data.characterName))
	end
end)

-- == SISTEMA DE ANIMACIONES (FUTURE-PROOF) ==
-- Tabla vacia de referencias a AnimationTrack.
-- Cuando los Rigs y animaciones definitivas esten listos, se cargaran aqui.
local loadedAnimations = {}

--[[
	Reproduce una animacion de habilidad si existe en loadedAnimations.
	Verifica que el track este cargado antes de ejecutar :Play()
	para que el codigo no falle si el ID de animacion aun no ha sido colocado.

	Parametros:
		animName -> string: clave de la animacion en loadedAnimations
]]
local function playAbilityAnimation(animName)
	local track = loadedAnimations[animName]
	if track and typeof(track) == "Instance" and track:IsA("AnimationTrack") then
		track:Play()
		return true
	else
		-- La animacion no esta cargada aun (placeholder)
		print("[AbilityClient] Animacion '" .. tostring(animName) .. "' no disponible (placeholder).")
		return false
	end
end

-- == MANEJO DE ANIMACIONES POR HABILIDAD ==
-- Cuando se ejecuta una habilidad con exito, intentar reproducir la animacion.
AbilityResultRemote.OnClientEvent:Connect(function(action, data)
	if action == "AbilitySuccess" then
		local abilityName = data.abilityName

		-- Mapeo de habilidades a nombres de animacion
		local animMap = {
			["HeredadoDeMama"] = "HeredadoDeMama_Anim",
			["Gamechild"] = "Gamechild_Anim",
			["UltimaOpcion"] = "UltimaOpcion_Anim",
			["RayosLaser"] = "RayosLaser_Anim",
			-- Animaciones de Toby Williams
			["YaLevantate"] = "YaLevantate_Anim",
			["BaraNormal"] = "BaraNormal_Anim",
			["BaraFantasma"] = "BaraFantasma_Anim",
			["RayosLaserToby"] = "RayosLaserToby_Anim",
			-- Animaciones de Takorita & Announcer
			["EmergenciaSevera"] = "EmergenciaSevera_Anim",
			["AnnouncerAttack"] = "AnnouncerAttack_Anim",
			["CuracionAumentante"] = "CuracionAumentante_Anim",
			-- Animaciones de Neuro
			["CallOfStardoom"] = "CallOfStardoom_Anim",
			["LightsAndAction"] = "LightsAndAction_Anim",
			["LastShow"] = "LastShow_Anim",
			-- Animaciones de Trunks
			["ZSword"] = "ZSword_Anim",
			["KiBlasts"] = "KiBlasts_Anim",
			["SuperSaiyan"] = "SuperSaiyan_Anim",
		}

		local animName = animMap[abilityName]
		if animName then
			playAbilityAnimation(animName)
		end
	end
end)

-- == MOUSE INPUT PARA TOBY WILLIAMS (M1/M2) ==
-- BaraFantasma se activa con click derecho cuando el personaje es Toby
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if not inMatch then return end

	-- Click derecho = BaraFantasma (solo para Toby Williams)
	if input.UserInputType == Enum.UserInputType.MouseButton2 and currentCharacterName == "TobyWilliams" then
		useAbility("BaraFantasma")
	end
end)

-- == BLIND EFFECT (RayosLaserToby) ==
-- Cuando el servidor nos ciega, mostrar overlay negro temporal
local BlindEffectRemote = Remotes:FindFirstChild("BlindEffect")
if BlindEffectRemote then
	BlindEffectRemote.OnClientEvent:Connect(function(duration)
		duration = duration or 3

		-- Crear overlay negro en el PlayerGui
		if typeof(duration) ~= "number" or duration ~= duration then duration = 3 end
		duration = math.clamp(duration, 0.1, 15)

		-- Un Frame colgado directamente de PlayerGui NO se dibuja: hace falta un ScreenGui.
		local blindGui = Instance.new("ScreenGui")
		blindGui.Name = "BlindEffectGui"
		blindGui.IgnoreGuiInset = true
		blindGui.ResetOnSpawn = false
		blindGui.DisplayOrder = 100

		local blindFrame = Instance.new("Frame")
		blindFrame.Name = "BlindOverlay"
		blindFrame.Size = UDim2.new(1, 0, 1, 0)
		blindFrame.Position = UDim2.new(0, 0, 0, 0)
		blindFrame.BackgroundColor3 = Color3.new(0, 0, 0)
		blindFrame.BorderSizePixel = 0
		blindFrame.ZIndex = 10
		blindFrame.Parent = blindGui
		blindGui.Parent = player:WaitForChild("PlayerGui")

		-- Desvanecer gradualmente
		local TweenService = game:GetService("TweenService")
		local tween = TweenService:Create(blindFrame, TweenInfo.new(duration), { BackgroundTransparency = 1 })
		tween:Play()

		tween.Completed:Connect(function()
			blindGui:Destroy()
		end)

		print("[AbilityClient] Ceguera activada por " .. duration .. "s")
	end)
end

print("[AbilityClient] Sistema de habilidades del cliente inicializado.")
