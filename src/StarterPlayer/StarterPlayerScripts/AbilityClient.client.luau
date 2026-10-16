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

-- == FORWARD DECLARATIONS para Fame HUD y SCells HUD ==
-- createFameHUD y destroyFameHUD se definen mas abajo pero se usan aqui.
local createFameHUD
local destroyFameHUD
local createSCellsHUD
local destroySCellsHUD

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
			if destroyFameHUD then destroyFameHUD() end
			if destroySCellsHUD then destroySCellsHUD() end
			print("[AbilityClient] Partida finalizada. Habilidades desactivadas.")
		end
	elseif state == "RoleAssigned" then
		-- El servidor nos notifica nuestro rol y personaje
		currentCharacterName = data.characterName

		if data.role == "Devilish" and data.characterName == "Neuro" then
			-- NEURO (DEVILISH): Slot 1 = CallOfStardoom, Slot 2 = LightsAndAction, Slot 3 = LastShow
			abilitySlots[Enum.KeyCode.One] = "CallOfStardoom"
			abilitySlots[Enum.KeyCode.Two] = "LightsAndAction"
			abilitySlots[Enum.KeyCode.Three] = "LastShow"
			-- Mostrar HUD de Fame
			createFameHUD()
		elseif data.role == "Devilish" then
			-- El Devilish generico tiene acceso a RayosLaser en el slot 3
			abilitySlots[Enum.KeyCode.One] = nil
			abilitySlots[Enum.KeyCode.Two] = nil
			abilitySlots[Enum.KeyCode.Three] = "RayosLaser"
		elseif data.role == "Toonflow" then
			-- Diferenciar por personaje
			if data.characterName == "Trunks" then
				-- TRUNKS: Slot 1 = ZSword, Slot 2 = KiBlasts, Slot 3 = SuperSaiyan
				abilitySlots[Enum.KeyCode.One] = "ZSword"
				abilitySlots[Enum.KeyCode.Two] = "KiBlasts"
				abilitySlots[Enum.KeyCode.Three] = "SuperSaiyan"
				-- Mostrar HUD de SCells
				createSCellsHUD()
			elseif data.characterName == "TobyWilliams" then
				-- TOBY WILLIAMS: Slot 1 = YaLevantate, Slot 2 = BaraNormal, Slot 3 = RayosLaserToby
				-- BaraFantasma se activa con click derecho (Mouse.Button2)
				abilitySlots[Enum.KeyCode.One] = "YaLevantate"
				abilitySlots[Enum.KeyCode.Two] = "BaraNormal"
				abilitySlots[Enum.KeyCode.Three] = "RayosLaserToby"
			elseif data.characterName == "Takorita" then
				-- TAKORITA & ANNOUNCER: Slot 1 = EmergenciaSevera, Slot 2 = AnnouncerAttack, Slot 3 = CuracionAumentante
				abilitySlots[Enum.KeyCode.One] = "EmergenciaSevera"
				abilitySlots[Enum.KeyCode.Two] = "AnnouncerAttack"
				abilitySlots[Enum.KeyCode.Three] = "CuracionAumentante"
			else
				-- BROTHERCAT (y otros Toonflows por defecto)
				abilitySlots[Enum.KeyCode.One] = "HeredadoDeMama"
				abilitySlots[Enum.KeyCode.Two] = "Gamechild"
				abilitySlots[Enum.KeyCode.Three] = "UltimaOpcion"
			end
		else
			-- Rol desconocido: desactivar todos los slots
			abilitySlots[Enum.KeyCode.One] = nil
			abilitySlots[Enum.KeyCode.Two] = nil
			abilitySlots[Enum.KeyCode.Three] = nil
		end
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
		local blindFrame = Instance.new("Frame")
		blindFrame.Name = "BlindOverlay"
		blindFrame.Size = UDim2.new(1, 0, 1, 0)
		blindFrame.Position = UDim2.new(0, 0, 0, 0)
		blindFrame.BackgroundColor3 = Color3.new(0, 0, 0)
		blindFrame.BorderSizePixel = 0
		blindFrame.ZIndex = 10
		blindFrame.Parent = player:WaitForChild("PlayerGui")

		-- Desvanecer gradualmente
		local TweenService = game:GetService("TweenService")
		local tween = TweenService:Create(blindFrame, TweenInfo.new(duration), { BackgroundTransparency = 1 })
		tween:Play()

		tween.Completed:Connect(function()
			blindFrame:Destroy()
		end)

		print("[AbilityClient] Ceguera activada por " .. duration .. "s")
	end)
end

print("[AbilityClient] Sistema de habilidades del cliente inicializado.")

-- == FAME HUD (Neuro) ==
-- Barra de Fame que aparece cuando el personaje es Neuro.
-- Se actualiza cada 0.2s leyendo el atributo Fame del character.
local fameHUD = nil
local fameBarFill = nil
local fameTextLabel = nil

createFameHUD = function()
	-- Si ya existe, no crear de nuevo
	if fameHUD then return end

	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then return end

	-- Contenedor principal de la barra de Fame
	fameHUD = Instance.new("Frame")
	fameHUD.Name = "FameHUD"
	fameHUD.Size = UDim2.new(0, 250, 0, 50)
	fameHUD.Position = UDim2.new(0.5, -125, 0, 10)
	fameHUD.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	fameHUD.BackgroundTransparency = 0.3
	fameHUD.BorderSizePixel = 2
	fameHUD.BorderColor3 = Color3.fromRGB(200, 150, 255)
	fameHUD.ZIndex = 8
	fameHUD.Parent = playerGui

	-- Etiqueta "FAME"
	fameTextLabel = Instance.new("TextLabel")
	fameTextLabel.Name = "FameLabel"
	fameTextLabel.Size = UDim2.new(0, 60, 1, 0)
	fameTextLabel.Position = UDim2.new(0, 5, 0, 0)
	fameTextLabel.BackgroundTransparency = 1
	fameTextLabel.Text = "FAME: 0"
	fameTextLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	fameTextLabel.Font = Enum.Font.GothamBold
	fameTextLabel.TextSize = 14
	fameTextLabel.TextXAlignment = Enum.TextXAlignment.Left
	fameTextLabel.ZIndex = 9
	fameTextLabel.Parent = fameHUD

	-- Barra de fondo
	local fameBarBg = Instance.new("Frame")
	fameBarBg.Name = "BarBg"
	fameBarBg.Size = UDim2.new(1, -70, 0, 16)
	fameBarBg.Position = UDim2.new(0, 65, 0.5, -8)
	fameBarBg.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
	fameBarBg.BorderSizePixel = 1
	fameBarBg.BorderColor3 = Color3.fromRGB(100, 100, 120)
	fameBarBg.ZIndex = 9
	fameBarBg.Parent = fameHUD

	-- Barra de relleno (cambia de color segun nivel de Fame)
	fameBarFill = Instance.new("Frame")
	fameBarFill.Name = "BarFill"
	fameBarFill.Size = UDim2.new(0, 0, 1, 0)
	fameBarFill.Position = UDim2.new(0, 0, 0, 0)
	fameBarFill.BackgroundColor3 = Color3.fromRGB(200, 150, 255)
	fameBarFill.BorderSizePixel = 0
	fameBarFill.ZIndex = 10
	fameBarFill.Parent = fameBarBg

	-- Lineas de referencia para 45 y 50
	local marker45 = Instance.new("Frame")
	marker45.Name = "Marker45"
	marker45.Size = UDim2.new(0, 2, 1, 2)
	marker45.Position = UDim2.new(0.45, 0, 0, -1)
	marker45.BackgroundColor3 = Color3.fromRGB(100, 255, 100)
	marker45.BorderSizePixel = 0
	marker45.ZIndex = 11
	marker45.Parent = fameBarBg

	local marker50 = Instance.new("Frame")
	marker50.Name = "Marker50"
	marker50.Size = UDim2.new(0, 2, 1, 2)
	marker50.Position = UDim2.new(0.50, 0, 0, -1)
	marker50.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
	marker50.BorderSizePixel = 0
	marker50.ZIndex = 11
	marker50.Parent = fameBarBg

	-- Loop de actualizacion de la barra de Fame
	task.spawn(function()
		while fameHUD and fameHUD.Parent do
			task.wait(0.2)
			if player.Character then
				local fame = player.Character:GetAttribute("Fame") or 0
				if fameTextLabel then
					fameTextLabel.Text = "FAME: " .. math.floor(fame)
				end
				if fameBarFill then
					fameBarFill.Size = UDim2.new(fame / 100, 0, 1, 0)
					-- Cambiar color segun nivel
					if fame >= 50 then
						fameBarFill.BackgroundColor3 = Color3.fromRGB(255, 100, 255) -- Violeta intenso (empowered)
					elseif fame >= 45 then
						fameBarFill.BackgroundColor3 = Color3.fromRGB(100, 255, 150) -- Verde (speed buff activo)
					else
						fameBarFill.BackgroundColor3 = Color3.fromRGB(200, 150, 255) -- Violeta normal
					end
				end
			end
		end
	end)
end

-- Funcion para destruir el HUD de Fame (cuando no es Neuro o termina la partida)
destroyFameHUD = function()
	if fameHUD then
		fameHUD:Destroy()
		fameHUD = nil
		fameBarFill = nil
		fameTextLabel = nil
	end
end

-- == SCELLS HUD (Trunks) ==
-- Barra de Celulas S que aparece cuando el personaje es Trunks.
-- Se actualiza cada 0.2s leyendo el NumberValue SCells del character.
local sCellsHUD = nil
local sCellsBarFill = nil
local sCellsTextLabel = nil
local sCellsSSJLabel = nil

createSCellsHUD = function()
	-- Si ya existe, no crear de nuevo
	if sCellsHUD then return end

	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then return end

	-- Contenedor principal de la barra de SCells
	sCellsHUD = Instance.new("Frame")
	sCellsHUD.Name = "SCellsHUD"
	sCellsHUD.Size = UDim2.new(0, 250, 0, 50)
	sCellsHUD.Position = UDim2.new(0.5, -125, 0, 65)
	sCellsHUD.BackgroundColor3 = Color3.fromRGB(30, 20, 40)
	sCellsHUD.BackgroundTransparency = 0.3
	sCellsHUD.BorderSizePixel = 2
	sCellsHUD.BorderColor3 = Color3.fromRGB(255, 215, 0)
	sCellsHUD.ZIndex = 8
	sCellsHUD.Parent = playerGui

	-- Etiqueta "S-CELLS"
	sCellsTextLabel = Instance.new("TextLabel")
	sCellsTextLabel.Name = "SCellsLabel"
	sCellsTextLabel.Size = UDim2.new(0, 80, 1, 0)
	sCellsTextLabel.Position = UDim2.new(0, 5, 0, 0)
	sCellsTextLabel.BackgroundTransparency = 1
	sCellsTextLabel.Text = "S-CELLS: 0"
	sCellsTextLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	sCellsTextLabel.Font = Enum.Font.GothamBold
	sCellsTextLabel.TextSize = 14
	sCellsTextLabel.TextXAlignment = Enum.TextXAlignment.Left
	sCellsTextLabel.ZIndex = 9
	sCellsTextLabel.Parent = sCellsHUD

	-- Barra de fondo
	local sCellsBarBg = Instance.new("Frame")
	sCellsBarBg.Name = "BarBg"
	sCellsBarBg.Size = UDim2.new(1, -90, 0, 16)
	sCellsBarBg.Position = UDim2.new(0, 85, 0.5, -8)
	sCellsBarBg.BackgroundColor3 = Color3.fromRGB(40, 30, 50)
	sCellsBarBg.BorderSizePixel = 1
	sCellsBarBg.BorderColor3 = Color3.fromRGB(100, 80, 120)
	sCellsBarBg.ZIndex = 9
	sCellsBarBg.Parent = sCellsHUD

	-- Barra de relleno (cambia de color segun nivel de SCells)
	sCellsBarFill = Instance.new("Frame")
	sCellsBarFill.Name = "BarFill"
	sCellsBarFill.Size = UDim2.new(0, 0, 1, 0)
	sCellsBarFill.Position = UDim2.new(0, 0, 0, 0)
	sCellsBarFill.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
	sCellsBarFill.BorderSizePixel = 0
	sCellsBarFill.ZIndex = 10
	sCellsBarFill.Parent = sCellsBarBg

	-- Linea de referencia para 10 SCells (umbral Super Saiyan)
	local marker10 = Instance.new("Frame")
	marker10.Name = "Marker10"
	marker10.Size = UDim2.new(0, 2, 1, 2)
	marker10.Position = UDim2.new(0.5, 0, 0, -1)
	marker10.BackgroundColor3 = Color3.fromRGB(100, 150, 255)
	marker10.BorderSizePixel = 0
	marker10.ZIndex = 11
	marker10.Parent = sCellsBarBg

	-- Etiqueta de estado Super Saiyan
	sCellsSSJLabel = Instance.new("TextLabel")
	sCellsSSJLabel.Name = "SSJLabel"
	sCellsSSJLabel.Size = UDim2.new(0, 100, 0, 16)
	sCellsSSJLabel.Position = UDim2.new(1, -100, 0, 2)
	sCellsSSJLabel.BackgroundTransparency = 1
	sCellsSSJLabel.Text = ""
	sCellsSSJLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
	sCellsSSJLabel.Font = Enum.Font.GothamBold
	sCellsSSJLabel.TextSize = 12
	sCellsSSJLabel.ZIndex = 9
	sCellsSSJLabel.Parent = sCellsHUD

	-- Loop de actualizacion de la barra de SCells
	task.spawn(function()
		while sCellsHUD and sCellsHUD.Parent do
			task.wait(0.2)
			if player.Character then
				local stats = player.Character:FindFirstChild("Stats")
				if stats then
					local sCellsVal = stats:FindFirstChild("SCells")
					local sCellsMaxVal = stats:FindFirstChild("SCellsMax")
					local isSSJVal = stats:FindFirstChild("IsSuperSaiyan")
					if sCellsVal and sCellsMaxVal then
						local sCells = sCellsVal.Value
						local sCellsMax = sCellsMaxVal.Value
						if sCellsTextLabel then
							sCellsTextLabel.Text = "S-CELLS: " .. math.floor(sCells) .. "/" .. sCellsMax
						end
						if sCellsBarFill then
							sCellsBarFill.Size = UDim2.new(sCells / sCellsMax, 0, 1, 0)
							-- Cambiar color segun nivel
							if sCells >= 10 then
								sCellsBarFill.BackgroundColor3 = Color3.fromRGB(255, 215, 0) -- Dorado (puede transformarse)
							else
								sCellsBarFill.BackgroundColor3 = Color3.fromRGB(180, 130, 220) -- Purpura normal
							end
						end
						-- Mostrar estado Super Saiyan
						if sCellsSSJLabel and isSSJVal then
							if isSSJVal.Value then
								sCellsSSJLabel.Text = "[ SUPER SAIYAN ]"
								sCellsSSJLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
							else
								sCellsSSJLabel.Text = ""
							end
						end
					end
				end
			end
		end
	end)
end

-- Funcion para destruir el HUD de SCells (cuando no es Trunks o termina la partida)
destroySCellsHUD = function()
	if sCellsHUD then
		sCellsHUD:Destroy()
		sCellsHUD = nil
		sCellsBarFill = nil
		sCellsTextLabel = nil
		sCellsSSJLabel = nil
	end
end