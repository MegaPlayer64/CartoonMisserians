--[[
	MatchResultClient (LocalScript)
	Ubicación: StarterPlayer.StarterPlayerScripts.MatchResultClient

	Muestra la calificación de fin de partida (SUPER F ... SS+), los puntos, su desglose y la Maldad
	ganada. El servidor envía MatchResult solo si MatchScoring.Enabled está activo, así que mientras
	el sistema esté apagado este panel no aparece nunca.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Remotes = ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Remotes")
local MatchResultRemote = Remotes:WaitForChild("MatchResult")
local MatchStateRemote = Remotes:WaitForChild("MatchState")

local SHOW_SECONDS = 9
local MAX_BREAKDOWN_LINES = 9

local GRADE_COLORS = {
	["SS+"] = Color3.fromRGB(255, 215, 0),
	["SS"] = Color3.fromRGB(255, 190, 40),
	["S"] = Color3.fromRGB(255, 160, 60),
	["A"] = Color3.fromRGB(110, 220, 120),
	["B"] = Color3.fromRGB(90, 190, 230),
	["C"] = Color3.fromRGB(180, 180, 200),
	["D"] = Color3.fromRGB(190, 150, 110),
	["F"] = Color3.fromRGB(220, 110, 90),
	["SUPER F"] = Color3.fromRGB(200, 50, 60),
}

local gui = Instance.new("ScreenGui")
gui.Name = "MatchResultGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 45
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
gui.Enabled = false
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromScale(0.6, 0.8) -- con UISizeConstraint: cabe en móviles apaisados
panel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
panel.BackgroundTransparency = 0.1
panel.BorderSizePixel = 0
panel.Parent = gui

local limit = Instance.new("UISizeConstraint")
limit.MaxSize = Vector2.new(420, 380)
limit.Parent = panel
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 14)
corner.Parent = panel
local stroke = Instance.new("UIStroke")
stroke.Thickness = 2
stroke.Color = Color3.fromRGB(235, 235, 245)
stroke.Transparency = 0.4
stroke.Parent = panel

local function makeLabel(name, size, position, font, maxTextSize)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = size
	label.Position = position
	label.Font = font
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Parent = panel
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = maxTextSize
	constraint.MinTextSize = 8
	constraint.Parent = label
	return label
end

local titleLabel = makeLabel("Title", UDim2.fromScale(0.9, 0.09), UDim2.fromScale(0.05, 0.03), Enum.Font.GothamBold, 22)
titleLabel.Text = "CALIFICACIÓN"
local gradeLabel = makeLabel("Grade", UDim2.fromScale(0.9, 0.3), UDim2.fromScale(0.05, 0.12), Enum.Font.GothamBlack, 90)
local pointsLabel = makeLabel("Points", UDim2.fromScale(0.9, 0.08), UDim2.fromScale(0.05, 0.43), Enum.Font.GothamMedium, 20)
local maldadLabel = makeLabel("Maldad", UDim2.fromScale(0.9, 0.08), UDim2.fromScale(0.05, 0.51), Enum.Font.GothamBold, 20)
maldadLabel.TextColor3 = Color3.fromRGB(190, 120, 255)

-- Desglose: texto normal (no escalado) para que las líneas mantengan un tamaño legible
local breakdownLabel = Instance.new("TextLabel")
breakdownLabel.Name = "Breakdown"
breakdownLabel.BackgroundTransparency = 1
breakdownLabel.Size = UDim2.fromScale(0.86, 0.34)
breakdownLabel.Position = UDim2.fromScale(0.07, 0.61)
breakdownLabel.Font = Enum.Font.Gotham
breakdownLabel.TextColor3 = Color3.new(1, 1, 1)
breakdownLabel.TextSize = 15
breakdownLabel.TextWrapped = true
breakdownLabel.TextXAlignment = Enum.TextXAlignment.Left
breakdownLabel.TextYAlignment = Enum.TextYAlignment.Top
breakdownLabel.Parent = panel

local hideToken = 0

local function hide()
	hideToken += 1
	gui.Enabled = false
end

MatchResultRemote.OnClientEvent:Connect(function(result)
	if typeof(result) ~= "table" or typeof(result.grade) ~= "string" then return end

	gradeLabel.Text = result.grade
	gradeLabel.TextColor3 = GRADE_COLORS[result.grade] or Color3.new(1, 1, 1)
	pointsLabel.Text = string.format("%d puntos", tonumber(result.points) or 0)

	local gained = tonumber(result.maldad) or 0
	local total = tonumber(result.totalMaldad)
	maldadLabel.Text = total and string.format("+%d Maldad  (total: %d)", gained, total) or string.format("+%d Maldad", gained)

	local lines = {}
	if typeof(result.breakdown) == "table" then
		for index, entry in ipairs(result.breakdown) do
			if index > MAX_BREAKDOWN_LINES then break end
			if typeof(entry) == "table" then
				table.insert(lines, string.format("%s  %+d", tostring(entry.label), tonumber(entry.points) or 0))
			end
		end
	end
	breakdownLabel.Text = table.concat(lines, "\n")

	hideToken += 1
	local myToken = hideToken
	gui.Enabled = true
	panel.BackgroundTransparency = 1
	TweenService:Create(panel, TweenInfo.new(0.25), { BackgroundTransparency = 0.1 }):Play()

	task.delay(SHOW_SECONDS, function()
		if myToken == hideToken then hide() end
	end)
end)

-- Al empezar otra partida o volver al lobby el panel se cierra
MatchStateRemote.OnClientEvent:Connect(function(state)
	if state == "Intermission" or state == "RoleAssigned" then
		hide()
	end
end)
