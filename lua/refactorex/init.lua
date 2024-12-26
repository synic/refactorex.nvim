-- LSP client configuration
local lspconfig = require("lspconfig")
local configs = require("lspconfig.configs")
local Job = require("plenary.job")
local Path = require("plenary.path")

local refactorex_version =
	vim.fn.readfile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h") .. "/version.txt")[1]
local default_port = 6890

local M = {}

-- Get the data directory for the plugin
local function get_install_dir()
	return Path:new(vim.fn.stdpath("data")):joinpath("refactorex")
end

-- Check if a port is available
-- Check if a port is available
local function is_port_available(port)
	---@diagnostic disable-next-line: missing-fields
	local result = Job:new({
		command = "lsof",
		args = { "-i", ":" .. tostring(port) },
	}):sync()

	-- If lsof returns any output, the port is in use
	return #result == 0
end

-- Find an available port starting from default
local function find_available_port()
	if is_port_available(default_port) then
		return default_port
	end

	-- Try ports from default_port + 1 to default_port + 100
	for port = default_port + 1, default_port + 100 do
		if is_port_available(port) then
			return port
		end
	end

	error("No available ports found")
end

-- Default config
M.config = {
	filetypes = { "elixir" },
	cmd = vim.lsp.rpc.connect("127.0.0.1", default_port),
	transport = "tcp",
	port = default_port,
	root_dir = function(fname)
		return require("lspconfig").util.root_pattern("mix.exs")(fname)
	end,
	settings = {},
}

-- Download and extract RefactorEx source
function M.ensure_refactorex()
	local install_dir = get_install_dir()
	local tar_file = install_dir:joinpath(string.format("refactorex-%s.tar.gz", refactorex_version))

	-- Create install directory if it doesn't exist
	if not install_dir:exists() then
		install_dir:mkdir({ parents = true })
	end

	-- Check if already downloaded and extracted
	if install_dir:joinpath(string.format("refactorex-%s", refactorex_version)):exists() then
		return
	end

	-- Download the tar.gz file
	---@diagnostic disable-next-line: missing-fields
	local download_job = Job:new({
		command = "curl",
		args = {
			"--fail",
			"-L",
			"--create-dirs",
			"-o",
			tar_file:absolute(),
			string.format("https://github.com/gp-pereira/refactorex/archive/refs/tags/%s.tar.gz", refactorex_version),
		},
		on_exit = function(_, retval)
			if retval ~= 0 then
				vim.notify("Failed to download RefactorEx", vim.log.levels.ERROR)
				return
			end

			-- Extract the tar.gz file
			---@diagnostic disable-next-line: missing-fields
			Job:new({
				command = "tar",
				args = { "xzf", tar_file:absolute(), "-C", install_dir:absolute() },
				on_exit = function(_, retval2)
					if retval2 ~= 0 then
						vim.notify("Failed to extract RefactorEx", vim.log.levels.ERROR)
						return
					end
					-- Remove the tar file after successful extraction
					tar_file:rm()

					-- Run mix deps.get in the extracted directory
					---@diagnostic disable-next-line: missing-fields
					Job:new({
						command = "mix",
						args = { "deps.get" },
						cwd = install_dir:joinpath(string.format("refactorex-%s", refactorex_version)):absolute(),
						on_exit = function(_, retval3)
							if retval3 ~= 0 then
								vim.notify("Failed to run mix deps.get", vim.log.levels.ERROR)
								return
							end
						end,
					}):start()
				end,
			}):start()
		end,
	})

	download_job:start()
end

local function create_commands()
	vim.api.nvim_create_user_command("RefactorExDownload", function()
		M.ensure_refactorex()
	end, {
		desc = "Download or update the RefactorEx binary",
	})
end

local function start_server(port)
	local start_script =
		Path:new(get_install_dir()):joinpath("refactorex-" .. refactorex_version .. "/bin/start"):absolute()

	---@diagnostic disable-next-line: missing-fields
	Job:new({
		command = start_script,
		args = { "--port", tostring(port) },
		on_exit = function(_, return_val)
			if return_val ~= 0 then
				vim.notify(string.format("Failed to start RefactorEx server on port %d", port), vim.log.levels.ERROR)
				return
			end
		end,
	}):start()
end

function M.setup(opts)
	create_commands()

	-- Check if RefactorEx is installed
	local start_script = Path:new(get_install_dir()):joinpath("refactorex-" .. refactorex_version .. "/bin/start")

	if not start_script:exists() then
		vim.notify("RefactorEx binary not found. Please run :RefactorExDownload first", vim.log.levels.WARN)
		return
	end

	-- Find an available port
	local port = find_available_port()

	-- Update the config with the selected port
	M.config.cmd = vim.lsp.rpc.connect("127.0.0.1", port)
	M.config.port = port

	-- Start the server
	start_server(port)

	-- Merge user config with defaults
	opts = vim.tbl_deep_extend("force", M.config, opts or {})

	-- Register the server configuration
	if not configs.refactorex then
		configs.refactorex = {
			default_config = {
				cmd = M.config.cmd,
				filetypes = M.config.filetypes,
				root_dir = M.config.root_dir,
				settings = M.config.settings,
				capabilities = {
					textDocumentSync = {
						openClose = true,
						change = 1, -- Full sync
						save = { includeText = true },
					},
					codeActionProvider = {
						resolveProvider = true,
					},
					renameProvider = {
						prepareProvider = true,
					},
				},
			},
			docs = {
				description = [[
					RefactorEx Language Server for Elixir
					https://github.com/synic/refactorex
				]],
			},
		}
	end

	-- Setup LSP client
	if lspconfig.refactorex and lspconfig.refactorex.setup then
		lspconfig.refactorex.setup(opts)
	else
		vim.notify("Failed to initialize refactorex LSP", vim.log.levels.ERROR)
	end
end

return M
