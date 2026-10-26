--[[
	MapVoteClient (LocalScript)
	Ubicación: StarterGui.MapVoteGUI.MapVoteClient

	Muestra la UI de voto de mapa SOLO al Devilish cuando el servidor
	envía 'MapVoteRequest'. Se oculta automáticamente cuando la partida
	inicia o se elige mapa.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

local CharacterDatabase = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("CharacterDatabase"))
local Remotes = ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Remotes")
local MapVoteRequestRemote = Remotes:WaitForChild("MapVoteRequest")
local MapVoteResponseRemote = Remotes:WaitForChild("MapVoteResponse")
local MapChosenRemote = Remotes:WaitForChild("MapChosen")
local MatchStateRemote = Remotes:WaitForChild("MatchState")

local gui = script.Parent
local frame = gui:WaitForChild("VoteFrame")
local title = frame:WaitForChild("Title")
local timerLabel = frame:WaitForChild("TimerLabel")
local optionsFrame = frame:WaitForChild("OptionsFrame")

local buttons = {
	optionsFrame:WaitForChild("MapButton1"),
	optionsFrame:WaitForChild("MapButton2"),
	optionsFrame:WaitForChild("MapButton3"),
}

local voteActive = false
local countdownThread = nil

--[[
	Oculta la UI de voto.
]]
local function hideVote()
	voteActive = false
	if countdownThread then
		task.cancel(countdownThread)
		countdownThread = nil
	end
	gui.Enabled = false
end

--[[
	Muestra la UI con las opciones de mapa recibidas.
]]
-- Nombre legible de un Killer (CharacterDatabase); si no se encuentra, el nombre tal cual
local function killerDisplayName(name)
	local data = CharacterDatabase.GetDevilish(name)
	return data and data.DisplayName or name
end

-- Texto de cada opción: mapa, tamaño y salidas, y Killers recomendados
local function describeOption(opt)
	local lines = { opt.DisplayName or opt.Name }

	local exits = opt.ExitCount or 1
	table.insert(lines, string.format("%s · %d %s", opt.Category or "?", exits, exits == 1 and "salida" or "salidas"))

	if typeof(opt.RecommendedKillers) == "table" and #opt.RecommendedKillers > 0 then
		local names = {}
		for _, killer in ipairs(opt.RecommendedKillers) do
			table.insert(names, killerDisplayName(killer))
		end
		table.insert(lines, "Killers: " .. table.concat(names, ", "))
	end

	return table.concat(lines, "\n")
end

local function showVoteUI(options, duration)
	gui.Enabled = true
	if not frame:FindFirstChildOfClass("UISizeConstraint") then
		local limit = Instance.new("UISizeConstraint")
		limit.MaxSize = Vector2.new(520, 360)
		limit.Parent = frame
	end
	voteActive = true

	-- Configurar botones
	for i, btn in ipairs(buttons) do
		local opt = options[i]
		if opt then
			btn.Visible = true
			btn.Text = describeOption(opt)
			btn.TextWrapped = true
			btn.TextScaled = true
			-- El servidor valida el voto contra opt.Name: enviar siempre ese valor, no el texto mostrado
			btn:SetAttribute("MapName", opt.Name)
			btn.BackgroundColor3 = Color3.fromRGB(45, 45, 65)
			btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		else
			btn.Visible = false
		end
	end

	-- Animación de entrada
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(0, 0, 0, 0)
	TweenService:Create(frame, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.1,
		Size = UDim2.new(0.94, 0, 0.9, 0), -- con UISizeConstraint (máx. 520x360): cabe en móviles apaisados
	}):Play()

	-- Contador regresivo
	local remaining = duration
	timerLabel.Text = tostring(remaining)
	if countdownThread then task.cancel(countdownThread) end
	countdownThread = task.spawn(function()
		while voteActive and remaining > 0 do
			task.wait(1)
			remaining = remaining - 1
			timerLabel.Text = tostring(math.max(0, remaining))
		end
		if voteActive then
			hideVote()
		end
	end)
end

-- Conectar botones
for i, btn in ipairs(buttons) do
	btn.Activated:Connect(function()
		if not voteActive then return end

		btn.BackgroundColor3 = Color3.fromRGB(100, 255, 120)
		btn.TextColor3 = Color3.fromRGB(0, 0, 0)

		MapVoteResponseRemote:FireServer(btn:GetAttribute("MapName") or btn.Text)
		hideVote()
	end)
end

-- Escuchar eventos del servidor
MapVoteRequestRemote.OnClientEvent:Connect(function(data)
	if not data or not data.options then return end
	showVoteUI(data.options, data.duration or 15)
end)

-- SEGURO 1: Si el mapa ya fue elegido por el servidor, cerrar UI
MapChosenRemote.OnClientEvent:Connect(function()
	hideVote()
end)

-- SEGURO 2: Si la partida pasa a InProgress, Intermission o Ending, cerrar UI
MatchStateRemote.OnClientEvent:Connect(function(state)
	if state == "InProgress" or state == "Intermission" or state == "Ending" then
		hideVote()
	end
end)

print("[MapVoteClient] Sistema de voto de mapa inicializado correctamente.")