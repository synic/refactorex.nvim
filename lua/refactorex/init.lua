-- LSP client configuration
local lspconfig = require("lspconfig")
local configs = require("lspconfig.configs")
local Job = require("plenary.job")
local Path = require("plenary.path")

local refactorex_version =
	vim.fn.readfile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h") .. "/.version.txt")[1]
local default_port = 6890
local server_start_timeout = 2500
local github_url = "https://github.com/gp-pereira/refactorex"

local M = {
	config = {
		filetypes = { "elixir" },
		cmd = { "nc", "127.0.0.1", tostring(default_port) },
		root_dir = function(fname)
			return require("lspconfig").util.root_pattern("mix.exs")(fname)
		end,
		settings = {},
		server_start_timeout = server_start_timeout,
		github_url = github_url,
	},
	installing = false,
	install_complete = false,
	pending_server_starts = {},
}

local function get_install_dir()
	return Path:new(vim.fn.stdpath("data")):joinpath("refactorex")
end

local function is_port_available(port)
	---@diagnostic disable-next-line: missing-fields
	local result = Job:new({
		command = "lsof",
		args = { "-i", ":" .. tostring(port) },
	}):sync()

	return #result == 0
end

local function find_available_port()
	if is_port_available(default_port) then
		return default_port
	end

	for port = default_port + 1, default_port + 100 do
		if is_port_available(port) then
			return port
		end
	end

	error("No available ports found in range " .. default_port .. "-" .. (default_port + 100))
end

local function check_dependencies()
	local required_commands = { "nc", "curl", "tar", "mix" }
	for _, cmd in ipairs(required_commands) do
		if vim.fn.executable(cmd) ~= 1 then
			error(string.format("Required command '%s' not found in PATH", cmd))
		end
	end
end

local function setup_server_config(opts)
	if not configs.refactorex then
		configs.refactorex = {
			default_config = {
				cmd = opts.cmd,
				filetypes = opts.filetypes,
				root_dir = opts.root_dir,
				settings = opts.settings,
				capabilities = {
					textDocumentSync = {
						openClose = true,
						change = 1,
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
				description = string.format(
					[[
	                RefactorEx Language Server for Elixir
	                %s
	            ]],
					M.config.github_url
				),
			},
		}
	end
end

function M.ensure_refactorex(callback, force_reinstall)
	local install_dir = get_install_dir()
	local tar_file = install_dir:joinpath(string.format("refactorex-%s.tar.gz", refactorex_version))
	local refactorex_path = install_dir:joinpath(string.format("refactorex-%s", refactorex_version))

	if not install_dir:exists() then
		install_dir:mkdir({ parents = true })
	end

	if force_reinstall and refactorex_path:exists() then
		vim.notify("Removing existing RefactorEx installation...", vim.log.levels.INFO)
		refactorex_path:rm({ recursive = true })
	elseif refactorex_path:exists() and not force_reinstall then
		vim.notify("RefactorEx is already installed", vim.log.levels.INFO)
		M.install_complete = true
		if callback then
			callback()
		end
		return
	end

	if M.installing then
		if callback then
			table.insert(M.pending_server_starts, callback)
		end
		return
	end

	M.installing = true

	vim.notify("Downloading RefactorEx...", vim.log.levels.INFO)
	---@diagnostic disable-next-line: missing-fields
	local download_job = Job:new({
		command = "curl",
		args = {
			"--fail",
			"-L",
			"--create-dirs",
			"-o",
			tar_file:absolute(),
			string.format("%s/archive/refs/tags/%s.tar.gz", M.config.github_url, refactorex_version),
		},
		on_exit = function(_, retval)
			if retval ~= 0 then
				vim.notify("Failed to download RefactorEx", vim.log.levels.ERROR)
				return
			end

			vim.notify("Download complete. Extracting...", vim.log.levels.INFO)
			---@diagnostic disable-next-line: missing-fields
			Job:new({
				command = "tar",
				args = { "xzf", tar_file:absolute(), "-C", install_dir:absolute() },
				on_exit = function(_, retval2)
					if retval2 ~= 0 then
						vim.notify("Failed to extract RefactorEx", vim.log.levels.ERROR)
						return
					end
					tar_file:rm()

					vim.notify("Extraction complete. Installing mix dependencies...", vim.log.levels.INFO)

					---@diagnostic disable-next-line: missing-fields
					Job:new({
						command = "mix",
						args = { "deps.get" },
						cwd = install_dir:joinpath(string.format("refactorex-%s", refactorex_version)):absolute(),
						on_exit = function(_, retval3)
							if retval3 ~= 0 then
								vim.notify("Failed to run mix deps.get", vim.log.levels.ERROR)
								M.installing = false
								return
							end

							vim.notify("Dependencies installed. Compiling...", vim.log.levels.INFO)

							---@diagnostic disable-next-line: missing-fields
							Job:new({
								command = "mix",
								args = { "compile" },
								cwd = install_dir
									:joinpath(string.format("refactorex-%s", refactorex_version))
									:absolute(),
								on_exit = function(_, retval4)
									if retval4 ~= 0 then
										vim.notify("Failed to compile RefactorEx", vim.log.levels.ERROR)
										M.installing = false
										return
									end

									vim.notify("RefactorEx installation complete!", vim.log.levels.INFO)
									M.installing = false
									M.install_complete = true

									if callback then
										callback()
									end

									for _, pending_callback in ipairs(M.pending_server_starts) do
										pending_callback()
									end
									M.pending_server_starts = {}
								end,
							}):start()
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
		M.ensure_refactorex(nil, true)
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
		on_exit = function(stuff, return_val)
			print(vim.inspect(stuff))
			if return_val ~= 0 then
				vim.notify(string.format("Failed to start RefactorEx server on port %d", port), vim.log.levels.ERROR)
				return
			end
		end,
	}):start()
end

function M.setup(opts)
	opts = vim.tbl_deep_extend("force", M.config, opts or {})

	local ok, err = pcall(check_dependencies)
	if not ok then
		vim.notify(tostring(err), vim.log.levels.ERROR)
		return
	end

	create_commands()
	setup_server_config(opts)

	local server_started = false
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "elixir",
		callback = function()
			if not server_started then
				local port = find_available_port()
				M.config.cmd = { "nc", "127.0.0.1", tostring(port) }
				opts = vim.tbl_deep_extend("force", M.config, opts or {})

				local function initialize_server()
					start_server(port)
					server_started = true

					vim.defer_fn(function()
						if lspconfig.refactorex and lspconfig.refactorex.setup then
							lspconfig.refactorex.setup(opts)
							vim.cmd("LspStart refactorex")
						else
							vim.notify("Failed to initialize refactorex LSP", vim.log.levels.ERROR)
						end
					end, opts.server_start_timeout)
				end

				local start_script = Path:new(get_install_dir())
					:joinpath("refactorex-" .. refactorex_version .. "/bin/start")
				if not start_script:exists() then
					vim.notify("RefactorEx not found. Starting automatic download...", vim.log.levels.INFO)
					M.ensure_refactorex(initialize_server)
				else
					initialize_server()
				end
			end
		end,
		once = true,
	})
end

return M
