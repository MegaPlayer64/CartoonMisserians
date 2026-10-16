--!strict
-- ÚNICO Script del servidor. Todo lo demás son ModuleScripts.

local Net = require(script.Net)

-- 1) Los remotes existen antes de que cualquier sistema los use.
Net.init()

-- 2) Arranque en dos fases: init de TODOS, luego start de TODOS.
local loaded: { [string]: any } = {}
for _, child in script.Systems:GetChildren() do
	if child:IsA("ModuleScript") then
		loaded[child.Name] = require(child)
	end
end

for _, system in loaded do
	if typeof(system.init) == "function" then
		system.init()
	end
end

for _, system in loaded do
	if typeof(system.start) == "function" then
		task.spawn(system.start)
	end
end
