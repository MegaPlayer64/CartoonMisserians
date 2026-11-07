--[[
	KillerOptionClient (LocalScript)
	Ubicación: StarterPlayer.StarterPlayerScripts.KillerOptionClient

	Panel mínimo de Opciones con "Poder ser Killer". Es una UI provisional: el botón "Options" que ya
	existe en el lobby abre hoy el menú de depuración (DebugMenuClient), no unas opciones de jugador.
	Para integrarlo en tu propia UI basta con:
	  - leer/escuchar el atributo del jugador   KillerOptIn   (nil o true = puede ser Killer)
	  - pedir el cambio con                      Remotes.SetKillerOptIn:FireServer(true | false)

	Regla de selección (servidor, KillerSelection): el jugador con MÁS Maldad entre quienes pueden ser
	Killer; al tocarle, su Maldad vuelve a 0. Este panel muestra tu Maldad y quién es hoy el candidato
	(calculado con los atributos Maldad y KillerOptIn, que se replican a todos los jugadores).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Remotes = ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Remotes")
local SetKillerOptInRemote = Remotes:WaitForChild("SetKillerOptIn")
local MatchStateRemote = Remotes:WaitForChild("MatchState")

-- == AJUSTES DE DISEÑO ==
local BUTTON_SIZE = 46
local EDGE_MARGIN = 14
local COLOR_PANEL = Color3.fromRGB(24, 24, 36)
local COLOR_ON = Color3.fromRGB(50, 170, 90)
local COLOR_OFF = Color3.fromRGB(110, 60, 60)
local COLOR_MALDAD = Color3.fromRGB(190, 120, 255)

local gui = Instance.new("ScreenGui")
gui.Name = "KillerOptionGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 26
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
gui.Parent = playerGui

local function round(instance, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

-- Botón de engranaje (arriba a la derecha; muévelo con BUTTON_SIZE / EDGE_MARGIN)
local gear = Instance.new("TextButton")
gear.Name = "OptionsButton"
gear.AnchorPoint = Vector2.new(1, 0)
gear.Position = UDim2.new(1, -EDGE_MARGIN, 0, EDGE_MARGIN)
gear.Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE)
gear.BackgroundColor3 = COLOR_PANEL
gear.BackgroundTransparency = 0.15
gear.Text = "⚙"
gear.TextColor3 = Color3.new(1, 1, 1)
gear.TextSize = 26
gear.Font = Enum.Font.GothamBold
gear.AutoButtonColor = true
gear.Parent = gui
round(gear, 10)

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromScale(0.8, 0.7) -- con UISizeConstraint: cabe en móviles apaisados
panel.BackgroundColor3 = COLOR_PANEL
panel.BackgroundTransparency = 0.05
panel.Visible = false
panel.Active = true -- no deja pasar los toques a lo que haya detrás
panel.Parent = gui
round(panel, 14)
local limit = Instance.new("UISizeConstraint")
limit.MaxSize = Vector2.new(400, 270)
limit.Parent = panel
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(235, 235, 245)
stroke.Transparency = 0.4
stroke.Thickness = 2
stroke.Parent = panel

local function makeText(name, text, position, size, font, textSize, color)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = position
	label.Size = size
	label.Font = font
	label.Text = text
	label.TextSize = textSize
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Parent = panel
	return label
end

makeText("Title", "Opciones", UDim2.fromScale(0.05, 0.04), UDim2.fromScale(0.7, 0.14), Enum.Font.GothamBold, 22)

local closeButton = Instance.new("TextButton")
closeButton.Name = "Close"
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -10, 0, 8)
closeButton.Size = UDim2.fromOffset(34, 34)
closeButton.BackgroundColor3 = Color3.fromRGB(70, 70, 90)
closeButton.Text = "X"
closeButton.TextColor3 = Color3.new(1, 1, 1)
closeButton.TextSize = 18
closeButton.Font = Enum.Font.GothamBold
closeButton.Parent = panel
round(closeButton, 8)

makeText("ToggleLabel", "Poder ser Killer", UDim2.fromScale(0.05, 0.24), UDim2.fromScale(0.58, 0.14), Enum.Font.GothamMedium, 18)

local toggle = Instance.new("TextButton")
toggle.Name = "Toggle"
toggle.AnchorPoint = Vector2.new(1, 0)
toggle.Position = UDim2.fromScale(0.95, 0.22)
toggle.Size = UDim2.fromOffset(86, 38)
toggle.Font = Enum.Font.GothamBold
toggle.TextSize = 16
toggle.TextColor3 = Color3.new(1, 1, 1)
toggle.Parent = panel
round(toggle, 10)

local maldadLabel = makeText("Maldad", "", UDim2.fromScale(0.05, 0.43), UDim2.fromScale(0.9, 0.11), Enum.Font.GothamBold, 17, COLOR_MALDAD)
local candidateLabel = makeText("Candidate", "", UDim2.fromScale(0.05, 0.55), UDim2.fromScale(0.9, 0.14), Enum.Font.GothamMedium, 15)
makeText("Help", "El jugador con más Maldad es el próximo Killer; al serlo, su Maldad vuelve a 0 y el puesto rota.\nSi no quieres ser Killer, desactívalo aquí.",
	UDim2.fromScale(0.05, 0.72), UDim2.fromScale(0.9, 0.24), Enum.Font.Gotham, 13, Color3.fromRGB(190, 190, 205))

-- == ESTADO ==
local function isOptedIn(target)
	return target:GetAttribute("KillerOptIn") ~= false
end

local function currentMaldad(target)
	local value = target:GetAttribute("Maldad")
	return type(value) == "number" and value or 0
end

local function refreshToggle()
	local on = isOptedIn(player)
	toggle.Text = on and "SÍ" or "NO"
	toggle.BackgroundColor3 = on and COLOR_ON or COLOR_OFF
end

-- Candidato = más Maldad entre quienes pueden ser Killer (si nadie puede, entre todos); empate = sorteo
local function refreshCandidate()
	maldadLabel.Text = string.format("Tu Maldad: %d", currentMaldad(player))

	local pool = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if isOptedIn(other) then
			table.insert(pool, other)
		end
	end
	if #pool == 0 then
		pool = Players:GetPlayers()
	end

	local best, bestMaldad = {}, -1
	for _, other in ipairs(pool) do
		local maldad = currentMaldad(other)
		if maldad > bestMaldad then
			best, bestMaldad = { other }, maldad
		elseif maldad == bestMaldad then
			table.insert(best, other)
		end
	end

	if #best == 1 then
		candidateLabel.Text = string.format("Próximo Killer: %s (%d)", best[1].DisplayName, bestMaldad)
	elseif #best > 1 then
		candidateLabel.Text = string.format("Próximo Killer: sorteo entre %d jugadores (%d)", #best, bestMaldad)
	else
		candidateLabel.Text = ""
	end
end

local function refreshAll()
	refreshToggle()
	refreshCandidate()
end

local function watchPlayer(other)
	other:GetAttributeChangedSignal("Maldad"):Connect(refreshAll)
	other:GetAttributeChangedSignal("KillerOptIn"):Connect(refreshAll)
end
for _, other in ipairs(Players:GetPlayers()) do
	watchPlayer(other)
end
Players.PlayerAdded:Connect(function(other)
	watchPlayer(other)
	refreshAll()
end)
Players.PlayerRemoving:Connect(function()
	task.defer(refreshAll)
end)

-- == INTERACCIÓN ==
gear.Activated:Connect(function()
	refreshAll()
	panel.Visible = not panel.Visible
end)
closeButton.Activated:Connect(function()
	panel.Visible = false
end)

toggle.Activated:Connect(function()
	local newValue = not isOptedIn(player)
	SetKillerOptInRemote:FireServer(newValue)

	-- Optimista: se ve al momento; si el servidor lo descarta (límite de frecuencia, perfil sin cargar)
	-- se vuelve al valor real
	toggle.Text = newValue and "SÍ" or "NO"
	toggle.BackgroundColor3 = newValue and COLOR_ON or COLOR_OFF
	task.delay(1.2, refreshToggle)
end)

-- El engranaje solo se ve en el lobby: durante la partida se oculta (y el panel se cierra)
MatchStateRemote.OnClientEvent:Connect(function(state)
	local inMatch = state == "RoleAssigned" or state == "InProgress"
	gear.Visible = not inMatch
	if inMatch then
		panel.Visible = false
	end
end)

refreshAll()
