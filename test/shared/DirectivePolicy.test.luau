--!strict
-- Luau directive policy tests.

local Env = _G.TestEnv or require(script.Parent.TestEnv)

local frktest = Env.frktest
local test = frktest.test
local check = frktest.assert.check

local ROOTS = { "src", "test" }
local IS_ROBLOX = typeof(game) ~= "nil"

return function()
	test.suite("Luau directive policy", function()
		if IS_ROBLOX then
			test.case("filesystem scan is enforced by the Lune test suite", function()
				check.equal(true, true)
			end)
			return
		end

		local fs = require("@lune/fs")

		local function collectLuauFiles(root: string, out: { string })
			for _, childName in ipairs(fs.readDir(root)) do
				local path = root .. "/" .. childName
				if fs.isDir(path) then
					collectLuauFiles(path, out)
				elseif fs.isFile(path) and (string.match(path, "%.lua$") or string.match(path, "%.luau$")) then
					table.insert(out, path)
				end
			end
		end

		test.case("src and test Luau files should start with --!strict", function()
			local files: { string } = {}
			for _, root in ipairs(ROOTS) do
				collectLuauFiles(root, files)
			end
			table.sort(files)

			local failures: { string } = {}
			for _, path in ipairs(files) do
				local contents = fs.readFile(path)
				local firstLine = string.match(contents, "^[^\r\n]*") or ""
				if firstLine ~= "--!strict" then
					table.insert(failures, path)
				end
			end

			check.equal(table.concat(failures, "\n"), "")
		end)
	end)
end
