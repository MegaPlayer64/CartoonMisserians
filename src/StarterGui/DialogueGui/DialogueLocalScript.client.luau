local PPS = game:GetService("ProximityPromptService")
local player = game.Players.LocalPlayer

-- Referencias a tu UI
local frame = script.Parent:WaitForChild("Frame")
local nameLabel = frame:WaitForChild("NameLabel") 
local textLabel = frame:WaitForChild("DialogLabel") 
local closeButton = frame:WaitForChild("X")

local isDisplaying = false
local typeThread = nil

local function typeWrite(label, message)
	label.Text = ""
	for i = 1, #message do
		label.Text = string.sub(message, 1, i)
		task.wait(0.04) -- Ajusta la velocidad
	end
end

local function closeDialogue()
	-- Cancelar la máquina de escribir: antes seguía escribiendo en la etiqueta oculta y se
	-- mezclaba con el diálogo siguiente.
	if typeThread then
		task.cancel(typeThread)
		typeThread = nil
	end
	frame.Visible = false
	isDisplaying = false
end

-- Se conecta UNA vez (antes se añadía una conexión nueva en cada diálogo, sin soltarla jamás)
closeButton.MouseButton1Click:Connect(closeDialogue)

PPS.PromptTriggered:Connect(function(prompt, inputPlayer)
	if inputPlayer ~= player then return end

	local npcName = prompt:GetAttribute("NPCName")
	local dialogueText = prompt:GetAttribute("Dialogue")

	if npcName and dialogueText and not isDisplaying then
		isDisplaying = true
		frame.Visible = true

		nameLabel.Text = npcName
		typeThread = task.spawn(function()
			typeWrite(textLabel, dialogueText)
			typeThread = nil
		end)
	end
end)
