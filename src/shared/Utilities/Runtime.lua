--!strict
type TaskLibrary = typeof(task)
local task = task
if not task then
	local loadTask: (string) -> TaskLibrary = require
	task = loadTask("@lune/task") :: any
end

return {
	task = task,
}
