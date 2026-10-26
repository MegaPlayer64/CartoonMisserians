--[[
	MobileControls (LocalScript)
	Ubicación: StarterPlayer.StarterPlayerScripts.MobileControls

	Controles táctiles de partida. Antes en móvil NO había forma de usar habilidades ni de
	correr (solo existía un contenedor sin lógica) y cualquier toque en pantalla lanzaba un
	ataque melee, incluso al arrastrar para girar la cámara.

	Botones (a la derecha, fuera de la zona del joystick de Roblox; el salto está desactivado):
	  - Habilidades 1-4: según el personaje (AbilityLoadouts), con cuenta atrás de cooldown.
	  - ATACAR (solo Devilish): mantener pulsado repite el ataque.
	  - CORRER: interruptor (activar/desactivar). Corre mientras te mueves y queda stamina.

	Se muestran SOLO cuando se juega con táctil (último input = Touch). Las habilidades y el
	ataque solo durante la partida; el sprint también en el lobby.

	Cómo se conecta:
	  - Habilidades -> BindableEvent "AbilityInputRequest" (AbilityClient)
	  - Ataque      -> BindableEvent "MeleeInputRequest"   (CombatClient)
	  - Sprint      -> atributo de jugador "MobileSprint"   (Bars)

	Para probar en Studio con el emulador de dispositivo: toca una vez la pantalla, o ejecuta en
	el cliente: game.Players.LocalPlayer:SetAttribute("ForceMobileControls", true)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Remotes = Framework:WaitForChild("Remotes")
local AbilityLoadouts = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityLoadouts"))

local MatchStateRemote = Remotes:WaitForChild("MatchState")
local AbilityResultRemote = Remotes:WaitForChild("AbilityResult")

local abilityRequest = script.Parent:WaitForChild("AbilityInputRequest", 15)
local meleeRequest = script.Parent:WaitForChild("MeleeInputRequest", 15)

-- == AJUSTES DE DISEÑO (en píxeles de referencia; se escalan según la pantalla) ==
local ABILITY_SIZE = 66
local ACTION_SIZE = 74
local GAP = 12
local EDGE_MARGIN = 22
local MELEE_REPEAT_SECONDS = 0.2

local COLOR_IDLE = Color3.fromRGB(36, 38, 52)
local COLOR_ACTIVE = Color3.fromRGB(190, 60, 60)
local COLOR_SPRINT_ON = Color3.fromRGB(60, 150, 90)
local COLOR_STROKE = Color3.fromRGB(235, 235, 245)

-- == ESTADO ==
local inMatch = false
local currentRole = nil
local loadout = {}
local cooldownEnd = {} -- [slot] = os.clock() cuando termina
local cooldownThread = nil
local meleeHeld = false

-- == GUI ==
local gui = Instance.new("ScreenGui")
gui.Name = "MobileControls"
gui.ResetOnSpawn = false
gui.DisplayOrder = 30
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets -- respeta notch y esquinas
gui.Enabled = false
gui.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.Size = UDim2.fromScale(1, 1)
root.Parent = gui

local function makeButton(name, text)
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(1, 1)
	button.AutoButtonColor = false
	button.BackgroundColor3 = COLOR_IDLE
	button.BackgroundTransparency = 0.25
	button.BorderSizePixel = 0
	button.Text = ""
	button.Parent = root

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLOR_STROKE
	stroke.Thickness = 2
	stroke.Transparency = 0.35
	stroke.Parent = button

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(0.82, 0.62)
	label.Position = UDim2.fromScale(0.09, 0.19)
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.TextWrapped = true
	label.Text = text or ""
	label.Parent = button

	local textConstraint = Instance.new("UITextSizeConstraint")
	textConstraint.MaxTextSize = 16
	textConstraint.MinTextSize = 7
	textConstraint.Parent = label

	-- Velo de cooldown (circular, encima de todo)
	local veil = Instance.new("Frame")
	veil.Name = "CooldownVeil"
	veil.BackgroundColor3 = Color3.new(0, 0, 0)
	veil.BackgroundTransparency = 0.35
	veil.Size = UDim2.fromScale(1, 1)
	veil.Visible = false
	veil.ZIndex = 5
	veil.Parent = button
	local veilCorner = Instance.new("UICorner")
	veilCorner.CornerRadius = UDim.new(1, 0)
	veilCorner.Parent = veil

	local seconds = Instance.new("TextLabel")
	seconds.Name = "Seconds"
	seconds.BackgroundTransparency = 1
	seconds.Size = UDim2.fromScale(1, 1)
	seconds.Font = Enum.Font.GothamBlack
	seconds.TextColor3 = Color3.new(1, 1, 1)
	seconds.TextScaled = true
	seconds.ZIndex = 6
	seconds.Parent = veil
	local secondsConstraint = Instance.new("UITextSizeConstraint")
	secondsConstraint.MaxTextSize = 26
	secondsConstraint.Parent = seconds

	return button
end

local sprintButton = makeButton("Sprint", "CORRER")
local meleeButton = makeButton("Melee", "ATACAR")
local abilityButtons = {}
for slot = 1, 4 do
	abilityButtons[slot] = makeButton("Ability" .. slot, "")
end

-- == LAYOUT (se recalcula si cambia el tamaño de pantalla / orientación) ==
local function layout()
	local size = root.AbsoluteSize
	local scale = math.clamp(math.min(size.X, size.Y) / 420, 0.85, 1.7)
	local function px(value)
		return math.floor(value * scale)
	end

	local ability = px(ABILITY_SIZE)
	local action = px(ACTION_SIZE)
	local margin = px(EDGE_MARGIN)
	local gap = px(GAP)

	-- Sin salto (QNA) la esquina inferior derecha queda libre: ATACAR (Devilish) abajo y CORRER encima.
	-- Sin botón de ataque (Toonflow), CORRER ocupa la esquina.
	meleeButton.Size = UDim2.fromOffset(action, action)
	meleeButton.Position = UDim2.new(1, -margin, 1, -margin)

	sprintButton.Size = UDim2.fromOffset(action, action)
	local sprintBottom = meleeButton.Visible and (margin + action + gap) or margin
	sprintButton.Position = UDim2.new(1, -margin, 1, -sprintBottom)

	-- Cuadrícula 2x2 de habilidades a la izquierda de esa columna
	local gridRight = margin + action + gap
	local col2Right = gridRight + ability + gap
	local row2Bottom = margin + ability + gap
	local positions = {
		[1] = UDim2.new(1, -gridRight, 1, -margin),
		[2] = UDim2.new(1, -col2Right, 1, -margin),
		[3] = UDim2.new(1, -gridRight, 1, -row2Bottom),
		[4] = UDim2.new(1, -col2Right, 1, -row2Bottom),
	}
	for slot, button in ipairs(abilityButtons) do
		button.Size = UDim2.fromOffset(ability, ability)
		button.Position = positions[slot]
	end
end

root:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
layout()

-- == VISIBILIDAD ==
local function wantsTouchUI()
	if player:GetAttribute("ForceMobileControls") then
		return true
	end
	if not UserInputService.TouchEnabled then
		return false
	end
	local last = UserInputService.LastInputType
	if last == Enum.UserInputType.Touch then
		return true
	end
	if last == Enum.UserInputType.Keyboard
		or last == Enum.UserInputType.MouseButton1
		or last == Enum.UserInputType.MouseButton2
		or last == Enum.UserInputType.MouseMovement
		or last == Enum.UserInputType.MouseWheel
		or last == Enum.UserInputType.Gamepad1 then
		return false
	end
	return not UserInputService.KeyboardEnabled and not UserInputService.MouseEnabled
end

local function isEscaped()
	local character = player.Character
	return character ~= nil and character:GetAttribute("Escaped") == true
end

local function refreshVisibility()
	local touch = wantsTouchUI()
	gui.Enabled = touch

	if not touch then
		-- Un teclado/ratón no debe heredar un sprint activado desde el móvil
		player:SetAttribute("MobileSprint", false)
	end

	local inAction = inMatch and not isEscaped()
	meleeButton.Visible = inAction and currentRole == "Devilish"
	for slot, button in ipairs(abilityButtons) do
		local abilityName = loadout[slot]
		button.Visible = inAction and abilityName ~= nil and abilityName ~= ""
	end

	layout() -- CORRER sube o baja según el botón de ataque esté o no visible
end

UserInputService.LastInputTypeChanged:Connect(refreshVisibility)
player:GetAttributeChangedSignal("ForceMobileControls"):Connect(refreshVisibility)

-- == COOLDOWNS ==
local function startCooldownLoop()
	if cooldownThread then return end
	cooldownThread = task.spawn(function()
		while true do
			local now = os.clock()
			local anyActive = false
			for slot, button in ipairs(abilityButtons) do
				local finishesAt = cooldownEnd[slot]
				local veil = button.CooldownVeil
				if finishesAt and finishesAt > now then
					anyActive = true
					veil.Visible = true
					veil.Seconds.Text = tostring(math.ceil(finishesAt - now))
				else
					cooldownEnd[slot] = nil
					veil.Visible = false
				end
			end
			if not anyActive then break end
			task.wait(0.1)
		end
		cooldownThread = nil
	end)
end

local function startCooldown(abilityName, duration)
	if typeof(duration) ~= "number" or duration ~= duration or duration <= 0 then return end
	for slot, name in ipairs(loadout) do
		if name == abilityName then
			cooldownEnd[slot] = os.clock() + duration
			startCooldownLoop()
		end
	end
end

local function clearCooldowns()
	table.clear(cooldownEnd)
	for _, button in ipairs(abilityButtons) do
		button.CooldownVeil.Visible = false
	end
end

-- Texto legible: "HeredadoDeMama" -> "Heredado De Mama"
local function prettyName(abilityName)
	return (abilityName:gsub("(%l)(%u)", "%1 %2"))
end

local function applyLoadout(characterName, role)
	loadout = AbilityLoadouts.get(characterName, role)
	for slot, button in ipairs(abilityButtons) do
		local abilityName = loadout[slot]
		button.Label.Text = (abilityName and abilityName ~= "") and prettyName(abilityName) or ""
	end
end

-- == EFECTO DE PULSACIÓN ==
local function pressFeedback(button, pressed)
	TweenService:Create(button, TweenInfo.new(0.08), {
		BackgroundColor3 = pressed and COLOR_ACTIVE or COLOR_IDLE,
	}):Play()
end

-- == ACCIONES ==
for slot, button in ipairs(abilityButtons) do
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			pressFeedback(button, true)
		end
	end)
	button.InputEnded:Connect(function()
		pressFeedback(button, false)
	end)
	button.Activated:Connect(function()
		local abilityName = loadout[slot]
		if not abilityName or abilityName == "" then return end
		if cooldownEnd[slot] and cooldownEnd[slot] > os.clock() then return end -- ya en cooldown
		if abilityRequest then
			abilityRequest:Fire(abilityName)
		end
	end)
end

-- ATACAR: mantener pulsado repite el ataque (CombatClient limita la frecuencia real)
meleeButton.InputBegan:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	if meleeHeld then return end
	meleeHeld = true
	pressFeedback(meleeButton, true)
	task.spawn(function()
		while meleeHeld and meleeRequest and gui.Enabled and meleeButton.Visible do
			meleeRequest:Fire()
			task.wait(MELEE_REPEAT_SECONDS)
		end
		meleeHeld = false
	end)
end)
meleeButton.InputEnded:Connect(function()
	meleeHeld = false
	pressFeedback(meleeButton, false)
end)

-- CORRER: interruptor
local function setSprint(on)
	player:SetAttribute("MobileSprint", on)
	sprintButton.BackgroundColor3 = on and COLOR_SPRINT_ON or COLOR_IDLE
	sprintButton.Label.Text = on and "CORRIENDO" or "CORRER"
end
sprintButton.Activated:Connect(function()
	setSprint(player:GetAttribute("MobileSprint") ~= true)
end)
setSprint(false)

-- == EVENTOS DE PARTIDA ==
MatchStateRemote.OnClientEvent:Connect(function(state, data)
	if state == "RoleAssigned" then
		inMatch = true
		currentRole = data and data.role
		clearCooldowns()
		applyLoadout(data and data.characterName, currentRole)
	elseif state == "InProgress" then
		inMatch = true
	elseif state == "Intermission" or state == "Ending" then
		inMatch = false
		currentRole = nil
		meleeHeld = false
		clearCooldowns()
	end
	refreshVisibility()
end)

AbilityResultRemote.OnClientEvent:Connect(function(action, data)
	if action == "AbilitySuccess" and typeof(data) == "table" then
		startCooldown(data.abilityName, data.cooldown)
	end
end)

-- Si el personaje escapa (invulnerable en la zona segura) se ocultan habilidades y ataque
local escapedConnection = nil
local function watchCharacter(character)
	if escapedConnection then
		escapedConnection:Disconnect()
	end
	escapedConnection = character:GetAttributeChangedSignal("Escaped"):Connect(refreshVisibility)
	refreshVisibility()
end
player.CharacterAdded:Connect(watchCharacter)
if player.Character then
	watchCharacter(player.Character)
end

refreshVisibility()
