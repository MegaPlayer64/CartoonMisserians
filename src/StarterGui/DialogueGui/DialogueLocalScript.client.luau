local PPS = game:GetService("ProximityPromptService")
local player = game.Players.LocalPlayer

-- Referencias a tu UI
local frame = script.Parent:WaitForChild("Frame")
local nameLabel = frame:WaitForChild("NameLabel") 
local textLabel = frame:WaitForChild("DialogLabel") 
local closeButton = frame:WaitForChild("X")

local isDisplaying = false

local function typeWrite(label, message)
	label.Text = ""
	for i = 1, #message do
		label.Text = string.sub(message, 1, i)
		task.wait(0.04) -- Ajusta la velocidad 
	end
end

PPS.PromptTriggered:Connect(function(prompt, inputPlayer)
	if inputPlayer ~= player then return end 

	local npcName = prompt:GetAttribute("NPCName")
	local dialogueText = prompt:GetAttribute("Dialogue")

	if npcName and dialogueText and not isDisplaying then
		isDisplaying = true
		frame.Visible = true

		nameLabel.Text = npcName
		typeWrite(textLabel, dialogueText)

		closeButton.MouseButton1Click:Connect(function()
			frame.Visible = false
			isDisplaying = false
		end)	
	end
end)