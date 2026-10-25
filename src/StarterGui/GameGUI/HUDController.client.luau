--[[
	HUDController (LocalScript)
	Ubicación: StarterGui.GameGUI.HUDController

	Controlador maestro unificado in-game.
	Maneja visibilidad Global/Game/Lobby, Timer, Anuncios,
	Retratos, Recursos (S-CELLS/FAME) y Mapeo de Habilidades.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local CAS = game:GetService("ContextActionService")

local CharacterDatabase = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("CharacterDatabase"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gameGUI = script.Parent
local AbilityLoadouts = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("AbilityLoadouts"))
local globalGUI = playerGui:WaitForChild("GlobalGUI", 5) or playerGui:WaitForChild("GameGUI", 5)
local lobbyGUI = playerGui:WaitForChild("LobbyGUI", 5)

-- == REMOTES (Con WaitForChild para evitar que queden en nil) ==
local Remotes = ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Remotes")
local MatchStateRemote = Remotes:WaitForChild("MatchState")
local AbilityResultRemote = Remotes:WaitForChild("AbilityResult")
local AbilitySyncRemote = Remotes:WaitForChild("AbilitySync")

local TaskProgressRemote = Remotes:WaitForChild("TaskProgress", 10) or Remotes:FindFirstChild("TaskProgress")
local BlindEffectRemote = Remotes:WaitForChild("BlindEffect", 10) or Remotes:FindFirstChild("BlindEffect")
local ExitTimerRemote = Remotes:WaitForChild("ExitTimer", 10) or Remotes:FindFirstChild("ExitTimer")
local LMSActivatedRemote = Remotes:WaitForChild("LMSActivated", 10) or Remotes:FindFirstChild("LMSActivated")
local MapChosenRemote = Remotes:WaitForChild("MapChosen", 10) or Remotes:FindFirstChild("MapChosen")

-- == REFERENCIAS A GLOBAL Y GAME GUI ==
local actionContainer = globalGUI and globalGUI:FindFirstChild("ActionContainer")
local emoteButton = actionContainer and actionContainer:FindFirstChild("EmoteButton")

local timerFrame = (globalGUI and globalGUI:FindFirstChild("TimerFrame")) 
	or (gameGUI and gameGUI:FindFirstChild("TimerFrame"))

local characterGUI = gameGUI:WaitForChild("Character_GUI", 5)
local characterIcon = characterGUI and characterGUI:FindFirstChild("CharacterIcon")
local skillCluster = gameGUI:WaitForChild("SkillCluster", 5)
local resourceFrame = gameGUI:WaitForChild("ResourceFrame", 5)
local allyContainer = gameGUI:WaitForChild("AllyContainer", 5)

-- Búsqueda adaptable para contenedores
local statusContainer = gameGUI:FindFirstChild("StatusContainer") 
	or gameGUI:FindFirstChild("StatusIconContainer") 
	or gameGUI:WaitForChild("StatusIconContainer", 5)

local timerLabel = timerFrame and (timerFrame:FindFirstChild("TimerLabel") or timerFrame:FindFirstChild("TimerText"))
local portrait = timerFrame and timerFrame:FindFirstChild("Portrait")
local playerNameLabel = timerFrame and timerFrame:FindFirstChild("PlayerNameLabel")

local roleBanner = gameGUI:FindFirstChild("RoleBanner")
local taskFrame = gameGUI:FindFirstChild("TaskFrame")

-- Búsqueda adaptable del Label de Tareas
local taskProgressLabel = taskFrame and (
	taskFrame:FindFirstChild("TaskProgressLabel") 
		or taskFrame:FindFirstChild("TextLabel") 
		or taskFrame:FindFirstChildOfClass("TextLabel")
)

local exitTimerLabel = gameGUI:FindFirstChild("ExitTimerLabel")
local lmsBanner = gameGUI:FindFirstChild("LMSBanner")
local statusMessageLabel = globalGUI and globalGUI:FindFirstChild("StatusMessageLabel")

-- Referencias internas de ResourceFrame
local resourceLabel = resourceFrame and (resourceFrame:FindFirstChild("ResourceLabel") or resourceFrame:FindFirstChild("AmountLabel") or resourceFrame:FindFirstChild("TextLabel"))
local barBg = resourceFrame and resourceFrame:FindFirstChild("BarBg")
local barFill = (barBg and barBg:FindFirstChild("BarFill")) or (resourceFrame and resourceFrame:FindFirstChild("BarFill")) or (resourceFrame and resourceFrame:FindFirstChild("Fill"))

-- == CONFIGURACIÓN Y ESTADOS INTERNOS ==
local abilityToSlot = {}
local activeCooldownThreads = {}
local activeStatusIcons = {}
local resourceConnections = {}
local allyConnections = {}

local matchTimerThread = nil
local statusMessageThread = nil
local resourceNameConnection = nil
local matchTimeRemaining = 0

-- CONFIGURACIÓN DE RECURSOS POR PERSONAJE
local RESOURCE_CONFIG = {
	["Trunks"] = {
		name = "S-CELLS",
		maxValue = 20,
		source = "ValueObject",
		valueName = "SCells",
		maxName = "SCellsMax",
		barColor = Color3.fromRGB(255, 215, 0),
		highColor = Color3.fromRGB(255, 100, 255),
		highThreshold = 10,
	},
	["Neuro"] = {
		name = "FAME",
		maxValue = 100,
		source = "Attribute",
		attributeName = "Fame",
		barColor = Color3.fromRGB(200, 150, 255),
		highColor = Color3.fromRGB(255, 100, 255),
		highThreshold = 50,
	},
}

-- == 1. FORMATO Y SISTEMA DE TEMPORIZADOR ==
local function formatTime(seconds)
	seconds = math.max(0, math.floor(seconds))
	local mins = math.floor(seconds / 60)
	local secs = seconds % 60
	return string.format("%02d:%02d", mins, secs)
end

-- Estado de la partida en el cliente
local currentRole = nil          -- "Toonflow" / "Devilish" (el atributo Role vive en el Character, no en el Player)
local exitActive = false         -- true mientras la salida está abierta (el reloj lo manda ExitTimer)
local progressInitialized = false -- el servidor reenvía InProgress cada 5 s: preparar la UI solo una vez

local function stopTimer()
	if matchTimerThread then
		task.cancel(matchTimerThread)
		matchTimerThread = nil
	end
end

local function startTimer(duration)
	stopTimer()

	if typeof(duration) == "table" then
		duration = duration.duration or duration.time or duration.timeRemaining or 60
	end
	duration = tonumber(duration) or 60
	matchTimeRemaining = duration

	matchTimerThread = task.spawn(function()
		while matchTimeRemaining > 0 do
			if timerLabel then
				timerLabel.Text = formatTime(matchTimeRemaining)
			end
			task.wait(1)
			matchTimeRemaining = matchTimeRemaining - 1
		end
		if timerLabel then
			timerLabel.Text = "00:00"
		end
	end)
end

-- == 2. ANUNCIOS DE ESTADO CON DESVANECIMIENTO ==
local function showStatusMessage(text, duration)
	if not statusMessageLabel then return end
	duration = duration or 4

	if statusMessageThread then
		task.cancel(statusMessageThread)
	end

	statusMessageLabel.Text = text
	statusMessageLabel.TextTransparency = 0
	statusMessageLabel.TextStrokeTransparency = 0
	statusMessageLabel.Visible = true

	statusMessageThread = task.spawn(function()
		task.wait(duration)
		if not statusMessageLabel then return end
		local tween = TweenService:Create(
			statusMessageLabel,
			TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ TextTransparency = 1, TextStrokeTransparency = 1 }
		)
		tween:Play()
		tween.Completed:Wait()
		if statusMessageLabel then
			statusMessageLabel.Visible = false
			statusMessageLabel.TextTransparency = 0
			statusMessageLabel.TextStrokeTransparency = 0
		end
	end)
end

-- == 3. GESTIÓN DE COOLDOWNS ==
local function stopCooldown(slotIndex)
	local slot = skillCluster and skillCluster:FindFirstChild("SkillSlot_" .. slotIndex)
	if not slot then return end

	local cooldownFrame = slot:FindFirstChild("CooldownFrame")
	local cdText = slot:FindFirstChild("CooldownText")

	local currentThread = activeCooldownThreads[slotIndex]
	if currentThread then
		activeCooldownThreads[slotIndex] = nil
		if currentThread ~= coroutine.running() and coroutine.status(currentThread) ~= "dead" then
			task.cancel(currentThread)
		end
	end

	if cooldownFrame then cooldownFrame.Visible = false end
	if cdText then
		cdText.Visible = false
		cdText.Text = ""
	end
end

local function startCooldown(slotIndex, duration)
	local slot = skillCluster and skillCluster:FindFirstChild("SkillSlot_" .. slotIndex)
	if not slot then return end

	stopCooldown(slotIndex)

	local cooldownFrame = slot:FindFirstChild("CooldownFrame")
	local cdText = slot:FindFirstChild("CooldownText")

	if cooldownFrame then cooldownFrame.Visible = true end
	if cdText then cdText.Visible = true end

	local remaining = math.ceil(duration)

	activeCooldownThreads[slotIndex] = task.spawn(function()
		while remaining > 0 do
			if cdText then cdText.Text = tostring(remaining) end
			task.wait(1)
			remaining = remaining - 1
		end
		stopCooldown(slotIndex)
	end)
end

-- == 4. MONITOREO DE ALIADOS ==
local function updateAllyList()
	if not allyContainer then return end

	for _, conn in ipairs(allyConnections) do conn:Disconnect() end
	allyConnections = {}

	for _, child in ipairs(allyContainer:GetChildren()) do
		if child:IsA("Frame") and child.Name:match("^AllySlot_%d+$") then
			child.Visible = false
		end
	end

	local function getAllySlot(n)
		return allyContainer:FindFirstChild("AllySlot_" .. n)
	end

	local function updateAllySlot(slotFrame, char, otherPlayer)
		if not char then
			slotFrame.Visible = false
			return
		end
		slotFrame.Visible = true

		local hpLabel = slotFrame:FindFirstChild("HealthText")
		local headshot = slotFrame:FindFirstChild("Headshot") or slotFrame:FindFirstChild("Portrait")

		if headshot then
			headshot.Visible = true
			pcall(function()
				headshot.Image = "rbxthumb://type=AvatarHeadShot&id=" .. otherPlayer.UserId .. "&w=150&h=150"
			end)
		end

		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum and hpLabel then
			local function updateText()
				local pct = math.floor((hum.Health / math.max(hum.MaxHealth, 1)) * 100)
				hpLabel.Text = math.max(0, pct) .. "%"
			end
			updateText()
			table.insert(allyConnections, hum.HealthChanged:Connect(updateText))
		end
	end

	-- Un Toonflow solo ve como aliados a otros Toonflows en partida (antes aparecía
	-- también el Devilish, con su retrato y su porcentaje de vida).
	local function isAlly(otherPlayer)
		if currentRole ~= "Toonflow" then return true end
		local otherChar = otherPlayer.Character
		return otherChar ~= nil and otherChar:GetAttribute("Role") == "Toonflow"
	end

	local index = 1
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player and isAlly(otherPlayer) then
			local slotFrame = getAllySlot(index)
			if slotFrame then
				if otherPlayer.Character then
					updateAllySlot(slotFrame, otherPlayer.Character, otherPlayer)
				end
				local capturedIndex = index
				local capturedPlayer = otherPlayer
				table.insert(allyConnections, otherPlayer.CharacterAdded:Connect(function(char)
					local sf = getAllySlot(capturedIndex)
					if sf then updateAllySlot(sf, char, capturedPlayer) end
				end))
				table.insert(allyConnections, otherPlayer.CharacterRemoving:Connect(function()
					local sf = getAllySlot(capturedIndex)
					if sf then sf.Visible = false end
				end))

				index = index + 1
				if index > 4 then break end
			end
		end
	end
end

-- == 5. MAPEO DE HABILIDADES Y ROLES ==
local function updateRoleMapping(data)
	abilityToSlot = {}
	for i = 1, 5 do stopCooldown(i) end

	currentRole = data and data.role or nil
	if not data then return end

	-- Control de visibilidad del contador de tareas según el Rol
	if taskFrame then
		taskFrame.Visible = (data.role == "Toonflow")
	end

	-- Fuente única de slots (la misma que usa AbilityClient para las teclas).
	for slotIndex, abilityName in ipairs(AbilityLoadouts.get(data.characterName, data.role)) do
		if abilityName ~= "" then
			abilityToSlot[abilityName] = slotIndex
		end
	end

	-- ANUNCIO DE ROL CENTRADO EN PANTALLA
	if roleBanner then
		roleBanner.AnchorPoint = Vector2.new(0.5, 0.5)
		roleBanner.Visible = true
		roleBanner.Position = UDim2.new(0.5, 0, -0.2, 0)
		roleBanner.Size = UDim2.new(0, 0, 0, 0)

		local title = roleBanner:FindFirstChild("RoleTitle")
		local objective = roleBanner:FindFirstChild("RoleObjective")
		if title then title.Text = string.upper(data.role or "") end
		if objective then
			local objText = ""
			if data.role == "Devilish" then objText = "Caza a los sobrevivientes"
			elseif data.role == "Toonflow" then objText = "Completa tareas y escapa" end
			objective.Text = objText
		end

		local tweenIn = TweenService:Create(
			roleBanner,
			TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = UDim2.new(0.45, 0, 0.18, 0), Position = UDim2.new(0.5, 0, 0.25, 0) }
		)
		tweenIn:Play()

		task.delay(4, function()
			local tweenOut = TweenService:Create(
				roleBanner,
				TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Size = UDim2.new(0, 0, 0, 0), Position = UDim2.new(0.5, 0, -0.2, 0) }
			)
			tweenOut:Play()
			tweenOut.Completed:Wait()
			roleBanner.Visible = false
		end)
	end
end

-- == 6. RECURSO ESPECIAL Y RETRATOS ==
local function updateResourceDisplay(val, maxVal, config)
	if not resourceFrame then return end
	local lbl = resourceLabel or resourceFrame:FindFirstChild("ResourceLabel") or resourceFrame:FindFirstChild("AmountLabel") or resourceFrame:FindFirstChild("TextLabel")
	local fill = barFill or (barBg and barBg:FindFirstChild("BarFill")) or resourceFrame:FindFirstChild("BarFill") or resourceFrame:FindFirstChild("Fill")

	val = math.max(0, tonumber(val) or 0)
	maxVal = math.max(1, tonumber(maxVal) or config.maxValue or 20)
	local ratio = math.clamp(val / maxVal, 0, 1)

	if lbl then
		lbl.Text = config.name .. ": " .. math.floor(val) .. " / " .. math.floor(maxVal)
	end

	if fill then
		fill.Size = UDim2.new(ratio, 0, 1, 0)
		fill.BackgroundColor3 = (val >= config.highThreshold) and config.highColor or config.barColor
	end
end

local function setupCharacterIcon(characterName)
	if not characterIcon then return end
	local charData = nil
	if CharacterDatabase and CharacterDatabase.GetCharacterData then
		charData = CharacterDatabase.GetCharacterData(characterName)
	end

	if charData then
		if charData.Icon and charData.Icon ~= "" then
			characterIcon.Image = charData.Icon
		else
			characterIcon.Image = "rbxasset://textures/white.png"
			characterIcon.ImageColor3 = charData.Color or Color3.fromRGB(255, 255, 255)
		end
		characterIcon.Visible = true
	end
end

local function setupResourceBar(character)
	for _, conn in ipairs(resourceConnections) do conn:Disconnect() end
	resourceConnections = {}
	if not character then return end

	local function initBar()
		for _, conn in ipairs(resourceConnections) do conn:Disconnect() end
		resourceConnections = {}

		local charName = character:GetAttribute("CharacterName") or player:GetAttribute("SelectedSurvivor") or player:GetAttribute("SelectedCharacter")
		local config = RESOURCE_CONFIG[charName]

		if not config then
			if resourceFrame then resourceFrame.Visible = false end
			return
		end

		if resourceFrame then resourceFrame.Visible = true end

		task.spawn(function()
			local stats = character:WaitForChild("Stats", 4)
			local sVal = stats and stats:WaitForChild(config.valueName or "SCells", 3)
			local sMax = stats and stats:WaitForChild(config.maxName or "SCellsMax", 3)

			local function refresh()
				local curVal = (sVal and sVal.Value) or character:GetAttribute("SCells") or character:GetAttribute(config.attributeName or "") or 0
				local curMax = (sMax and sMax.Value) or config.maxValue or 20
				updateResourceDisplay(curVal, curMax, config)
			end

			if sVal then table.insert(resourceConnections, sVal.Changed:Connect(refresh)) end
			if sMax then table.insert(resourceConnections, sMax.Changed:Connect(refresh)) end

			table.insert(resourceConnections, character:GetAttributeChangedSignal("SCells"):Connect(refresh))
			if config.attributeName then
				table.insert(resourceConnections, character:GetAttributeChangedSignal(config.attributeName):Connect(refresh))
			end

			refresh()
		end)
	end

	initBar()
	if resourceNameConnection then resourceNameConnection:Disconnect() end
	resourceNameConnection = character:GetAttributeChangedSignal("CharacterName"):Connect(initBar)
end

if emoteButton then
	emoteButton.Activated:Connect(function()
		local emoteGui = playerGui:FindFirstChild("EmoteWheelHUD", true) or playerGui:FindFirstChild("WheelFrame", true)
		if emoteGui then
			local wheelFrame = emoteGui:IsA("Frame") and emoteGui or emoteGui:FindFirstChild("WheelFrame", true)
			if wheelFrame then
				wheelFrame.Visible = not wheelFrame.Visible
			end
		end
	end)
end

-- == 8. CONEXIÓN DE EVENTOS Y REMOTES DE PARTIDA ==
MatchStateRemote.OnClientEvent:Connect(function(state, data)
	if state == "Intermission" or state == "Ending" then
		if lobbyGUI then lobbyGUI.Enabled = true end
		gameGUI.Enabled = false
		stopTimer()
		for i = 1, 5 do stopCooldown(i) end
		if exitTimerLabel then exitTimerLabel.Visible = false end
		exitActive = false
		progressInitialized = false
		if timerLabel then timerLabel.TextColor3 = Color3.fromRGB(255, 255, 255) end
		if taskProgressLabel then taskProgressLabel.Text = "TAREAS: --" end

		if data and data.message then
			showStatusMessage(data.message, 4)
		end

		if state == "Ending" and data and data.winner then
			local winMsg = (data.winner == "Toonflows") and "¡LOS TOONFLOWS GANAN!" or "¡EL DEVILISH GANA!"
			showStatusMessage(winMsg, 4)
		end

	elseif state == "RoleAssigned" then
		if lobbyGUI then lobbyGUI.Enabled = false end
		gameGUI.Enabled = true
		if exitTimerLabel then exitTimerLabel.Visible = false end
		exitActive = false
		progressInitialized = false
		if taskProgressLabel then taskProgressLabel.Text = "TAREAS: --" end
		updateRoleMapping(data)
		if data and data.characterName then
			setupCharacterIcon(data.characterName)
		end
		if player.Character then
			setupResourceBar(player.Character)
		end

	elseif state == "InProgress" then
		if lobbyGUI then lobbyGUI.Enabled = false end
		gameGUI.Enabled = true
		if timerLabel then timerLabel.TextColor3 = Color3.fromRGB(255, 255, 255) end

		if data and data.message then showStatusMessage(data.message, 4) end
		-- Con la salida abierta el reloj lo gobierna ExitTimer; antes el InProgress que llega
		-- cada 5 s pisaba la cuenta atrás de la salida con el tiempo total de la partida.
		if not exitActive and data and (data.timer or data.duration) then
			startTimer(data.timer or data.duration)
		end

		-- El servidor repite InProgress cada 5 s solo para sincronizar el reloj: la lista de
		-- aliados, la barra de recursos y el icono se preparan una vez por partida.
		if not progressInitialized then
			progressInitialized = true
			updateAllyList()

			local char = player.Character
			if char then
				setupResourceBar(char)
				local charName = char:GetAttribute("CharacterName")
				if charName then setupCharacterIcon(charName) end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function()
	if progressInitialized then
		task.delay(0.5, updateAllyList)
	end
end)

AbilityResultRemote.OnClientEvent:Connect(function(action, data)
	if action == "AbilitySuccess" and data and data.abilityName then
		local slotIndex = abilityToSlot[data.abilityName]
		if slotIndex then startCooldown(slotIndex, data.cooldown or 5) end
	end
end)

AbilitySyncRemote.OnClientEvent:Connect(function(abilityName, info)
	local slotIndex = abilityToSlot[abilityName]
	if slotIndex and info then
		if info.cooldownRemaining and info.cooldownRemaining > 0.1 then
			startCooldown(slotIndex, info.cooldownRemaining)
		else
			stopCooldown(slotIndex)
		end
	end
end)

-- Listener para Avance de Tareas
if TaskProgressRemote then
	TaskProgressRemote.OnClientEvent:Connect(function(data)
		if data and data.completed and data.total then
			-- (antes: player:GetAttribute("Role"), que siempre es nil porque el rol vive en el
			-- Character: el Devilish veía el contador de tareas tras la primera tarea)
			if taskFrame and currentRole == "Toonflow" then
				taskFrame.Visible = true
			end
			if taskProgressLabel then
				taskProgressLabel.Text = "TAREAS: " .. data.completed .. "/" .. data.total
			end
		end
	end)
end

-- Listener para Apertura de Salida
-- El servidor envía { remaining = segundos, open = bool } al abrir, cada 5 s y al cerrar.
-- Antes se leía como número: "remaining" no se reconocía, el reloj se reiniciaba a 01:00
-- cada 5 s, y al cerrar la salida el HUD seguía mostrando "¡SALIDA ABIERTA!".
if ExitTimerRemote then
	ExitTimerRemote.OnClientEvent:Connect(function(data)
		local remaining, isOpen = nil, true
		if typeof(data) == "table" then
			remaining = tonumber(data.remaining)
			isOpen = data.open ~= false
		else
			remaining = tonumber(data)
		end

		if not isOpen then
			exitActive = false
			stopTimer()
			if exitTimerLabel then exitTimerLabel.Visible = false end
			if timerLabel then
				timerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
				timerLabel.Text = "00:00"
			end
			return
		end

		local firstOpen = not exitActive
		exitActive = true
		if timerLabel then timerLabel.TextColor3 = Color3.fromRGB(255, 50, 50) end
		if exitTimerLabel then
			exitTimerLabel.Visible = true
			exitTimerLabel.Text = "¡SALIDA ABIERTA!"
		end
		startTimer(remaining or 60) -- resincroniza con el servidor
		if firstOpen then
			showStatusMessage("¡Salida abierta! Escapa ahora.", 5)
		end
	end)
end

-- Inicialización del Jugador Local
local function onCharacterAdded(char)
	task.wait(0.3)
	setupResourceBar(char)

	if portrait then
		pcall(function()
			portrait.Image = "rbxthumb://type=AvatarHeadShot&id=" .. player.UserId .. "&w=150&h=150"
		end)
	end
	if playerNameLabel then
		playerNameLabel.Text = player.DisplayName
	end

	local charName = char:GetAttribute("CharacterName")
	if charName then setupCharacterIcon(charName) end
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then onCharacterAdded(player.Character) end

print("[HUDController] Script unificado con listeners corregidos para Tareas y Salida.")