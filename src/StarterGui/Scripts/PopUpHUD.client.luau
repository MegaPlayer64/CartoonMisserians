local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local popUpGui = script.Parent

local Remotes = ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Remotes")
local PopupRemote = Remotes:WaitForChild("TriggerPopups")

PopupRemote.OnClientEvent:Connect(function(duration)
	local endTime = tick() + duration

	task.spawn(function()
		while tick() < endTime do
			-- Crear ventana emergente de error
			local popup = Instance.new("Frame")
			popup.Size = UDim2.new(0, math.random(180, 250), 0, math.random(120, 160))
			popup.Position = UDim2.new(math.random(10, 80) / 100, 0, math.random(10, 80) / 100, 0)
			popup.BackgroundColor3 = Color3.fromRGB(200, 200, 200)
			popup.BorderSizePixel = 2
			popup.Parent = popUpGui

			local title = Instance.new("TextLabel")
			title.Size = UDim2.new(1, 0, 0, 20)
			title.BackgroundColor3 = Color3.fromRGB(0, 0, 150)
			title.Text = " ERROR_STAN.EXE"
			title.TextColor3 = Color3.fromRGB(255, 255, 255)
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.Parent = popup

			local msg = Instance.new("TextLabel")
			msg.Size = UDim2.new(1, -10, 1, -30)
			msg.Position = UDim2.new(0, 5, 0, 25)
			msg.BackgroundTransparency = 1
			msg.Text = "CORRUPCIÓN DETECTADA EN EL SISTEMA"
			msg.TextColor3 = Color3.fromRGB(0, 0, 0)
			msg.TextWrapped = true
			msg.Parent = popup

			game:GetService("Debris"):AddItem(popup, 2.5)
			task.wait(0.25)
		end
	end)
end)