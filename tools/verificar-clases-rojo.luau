--[[
	Verificador de clases para Rojo. Pégalo en la barra de comandos de Studio
	(View > Command Bar) con tu place ORIGINAL abierto, SIN Rojo conectado.

	Compara la clase real de cada contenedor con la que declaran los archivos
	init.meta.json del repo, y lista los scripts que contiene (para detectar duplicados).
	Si algo sale "DISTINTA", corrige el className en el init.meta.json correspondiente
	ANTES de ejecutar rojo serve: una clase equivocada hace que Rojo reemplace el original.
]]

local expected = {
	{ game.StarterGui, "GameGUI", "ScreenGui" },
	{ game.StarterGui, "LobbyGUI", "ScreenGui" },
	{ game.StarterGui, "GlobalGUI", "ScreenGui" },
	{ game.StarterGui, "MapVoteGUI", "ScreenGui" },
	{ game.StarterGui, "AFKNotification", "ScreenGui" },
	{ game.StarterGui, "DialogueGui", "ScreenGui" },
	{ game.StarterGui.GlobalGUI, "ActionContainer", "Frame" },
	{ game.ReplicatedStorage.Characters, "Brothercat", "Model" },
	{ game.ReplicatedStorage.Characters, "Trunks", "Model" },
}

for _, entry in ipairs(expected) do
	local parent, name, className = entry[1], entry[2], entry[3]
	local matches = {}
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == name then
			table.insert(matches, child)
		end
	end

	local label = parent:GetFullName() .. "." .. name
	if #matches == 0 then
		warn(label .. ": NO EXISTE")
	else
		if #matches > 1 then
			warn(label .. ": " .. #matches .. " instancias con el mismo nombre (duplicado)")
		end
		for _, inst in ipairs(matches) do
			local scripts = {}
			for _, d in ipairs(inst:GetChildren()) do
				if d:IsA("LuaSourceContainer") then
					table.insert(scripts, d.ClassName .. ":" .. d.Name)
				end
			end
			local status = (inst.ClassName == className) and "OK" or ("DISTINTA (esperada " .. className .. ")")
			print(label, "->", inst.ClassName, status, "| hijos:", #inst:GetChildren(), "| scripts:", table.concat(scripts, ", "))
		end
	end
end
