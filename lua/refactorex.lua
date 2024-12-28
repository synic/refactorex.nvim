-- LSP client configuration
local lspconfig = require("lspconfig")
local configs = require("lspconfig.configs")
local Job = require("plenary.job")
local Path = require("plenary.path")

local refactorex_version =
	vim.fn.readfile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/refactorex-version.txt")[1]
local github_url = "https://github.com/gp-pereira/refactorex"

local M = {
	config = {
		filetypes = { "elixir" },
		cmd = {},
		root_dir = function(fname)
			return require("lspconfig").util.root_pattern("mix.exs")(fname)
		end,
		settings = {},
		github_url = github_url,
	},
	installing = false,
	install_complete = false,
	pending_server_starts = {},
}

local function get_install_dir()
	return Path:new(vim.fn.stdpath("data")):joinpath("refactorex")
end

local function apply_stdio_patch(install_path, callback)
	local patch_source = Path:new(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h"))
		:joinpath("../patches/stdio-0.1.28.patch")

	if not patch_source:exists() then
		if callback then
			callback(false)
		end
		return
	end

	---@diagnostic disable-next-line: missing-fields
	Job:new({
		command = "patch",
		args = { "-p1", "-d", install_path:absolute() },
		writer = patch_source:read(),
		on_exit = function(j, return_val)
			if return_val == 0 and j:result()[1]:match("patching file") then
				local start_stdio_script = install_path:joinpath("bin/start-stdio")
				if start_stdio_script:exists() then
					---@diagnostic disable-next-line: missing-fields
					Job:new({
						command = "chmod",
						args = { "+x", start_stdio_script:absolute() },
						on_exit = function(_, retval)
							if retval ~= 0 then
								vim.notify(
									"RefactorEx: Failed to make start-stdio script executable",
									vim.log.levels.ERROR
								)
							end
							if callback then
								callback(retval == 0)
							end
						end,
					}):start()
				else
					vim.notify("RefactorEx: start-stdio script not found", vim.log.levels.ERROR)
					if callback then
						callback(false)
					end
				end
			else
				vim.notify("RefactorEx: Failed to apply stdio patch", vim.log.levels.ERROR)
				if callback then
					callback(false)
				end
			end
		end,
	}):start()
end

local function check_dependencies()
	local required_commands = { "nc", "curl", "tar", "mix", "patch", "chmod" }
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

local function download_refactorex(tar_file, callback)
	vim.notify("RefactorEx: downloading and installing release source...", vim.log.levels.INFO)

	---@diagnostic disable-next-line: missing-fields
	Job:new({
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
				vim.notify("RefactorEx: failed to download release source", vim.log.levels.ERROR)
				M.installing = false
				return
			end
			callback()
		end,
	}):start()
end

local function extract_tarball(tar_file, install_dir, callback)
	---@diagnostic disable-next-line: missing-fields
	Job:new({
		command = "tar",
		args = { "xzf", tar_file:absolute(), "-C", install_dir:absolute() },
		on_exit = function(_, retval)
			if retval ~= 0 then
				vim.notify("RefactorEx: failed to extract source tarball", vim.log.levels.ERROR)
				M.installing = false
				return
			end
			tar_file:rm()
			callback()
		end,
	}):start()
end

local function install_mix_dependencies(install_path, callback)
	---@diagnostic disable-next-line: missing-fields
	Job:new({
		command = "mix",
		args = { "deps.get" },
		cwd = install_path:absolute(),
		on_exit = function(_, retval)
			if retval ~= 0 then
				vim.notify("RefactorEx: failed to run mix deps.get", vim.log.levels.ERROR)
				M.installing = false
				return
			end
			callback()
		end,
	}):start()
end

local function compile_refactorex(install_path, callback)
	---@diagnostic disable-next-line: missing-fields
	Job:new({
		command = "mix",
		args = { "compile" },
		cwd = install_path:absolute(),
		on_exit = function(_, retval)
			if retval ~= 0 then
				vim.notify("RefactorEx: failed to compile", vim.log.levels.ERROR)
				M.installing = false
				return
			end
			M.installing = false
			M.install_complete = true
			callback()
		end,
	}):start()
end

function M.ensure_refactorex(callback, force_reinstall)
	local install_dir = get_install_dir()
	local tar_file = install_dir:joinpath(string.format("refactorex-%s.tar.gz", refactorex_version))
	local refactorex_path = install_dir:joinpath(string.format("refactorex-%s", refactorex_version))

	if not install_dir:exists() then
		install_dir:mkdir({ parents = true })
	end

	if force_reinstall and refactorex_path:exists() then
		vim.notify("RefactorEx: removing existing RefactorEx installation...", vim.log.levels.INFO)
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

	download_refactorex(tar_file, function()
		extract_tarball(tar_file, install_dir, function()
			local install_path = install_dir:joinpath(string.format("refactorex-%s", refactorex_version))
			install_mix_dependencies(install_path, function()
				apply_stdio_patch(install_path, function(success)
					if not success then
						M.installing = false
						return
					end
					compile_refactorex(install_path, function()
						if callback then
							callback()
						end
						for _, pending_callback in ipairs(M.pending_server_starts) do
							pending_callback()
						end
						M.pending_server_starts = {}
					end)
				end)
			end)
		end)
	end)
end

local function create_commands()
	vim.api.nvim_create_user_command("RefactorExDownload", function()
		M.ensure_refactorex(nil, true)
	end, {
		desc = "Download or update the RefactorEx binary",
	})

	vim.api.nvim_create_user_command("RefactorExPatch", function()
		local install_dir = get_install_dir()
		local install_path = install_dir:joinpath(string.format("refactorex-%s", refactorex_version))

		if not install_path:exists() then
			vim.notify("RefactorEx installation not found", vim.log.levels.ERROR)
			return
		end

		apply_stdio_patch(install_path)
	end, {
		desc = "Apply stdio patch to existing RefactorEx installation",
	})
end

local function start_lsp_server(opts, start_stdio_script)
	opts.cmd = { start_stdio_script:absolute() }
	setup_server_config(opts)

	vim.schedule(function()
		lspconfig.refactorex.setup(opts)
		vim.cmd("LspStart refactorex")
	end)
end

function M.setup(opts)
	opts = vim.tbl_deep_extend("force", M.config, opts or {})

	local ok, err = pcall(check_dependencies)
	if not ok then
		vim.notify(tostring(err), vim.log.levels.ERROR)
		return
	end

	create_commands()

	local server_started = false
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "elixir",
		callback = function()
			if not server_started then
				local install_path = Path:new(get_install_dir()):joinpath("refactorex-" .. refactorex_version)
				local start_stdio_script = install_path:joinpath("bin/start-stdio")
				local start_script = install_path:joinpath("bin/start")

				if start_stdio_script:exists() then
					start_lsp_server(opts, start_stdio_script)
				elseif start_script:exists() then
					-- this is only required for the 0.1.28 version that may have already been installed for some neovim users -
					-- I switched from tcp transport to patching refactorex to use the stdio transport, however, some people may
					-- already have 0.1.28 downloaded and installed. If `bin/start-stdio` doesn't exist, then it means that the
					-- source hasn't been patched and it needs to be done.
					--
					-- When there's a new version of refactorex, this can be removed, because patching will be done as a part of
					-- the new version installation process (or, possibly might not be needed at all, see:
					-- https://github.com/gp-pereira/refactorex/pull/19)
					apply_stdio_patch(install_path, function(success)
						if success then
							start_lsp_server(opts, start_stdio_script)
						else
							vim.notify("RefactorEx: Failed to apply stdio patch", vim.log.levels.ERROR)
						end
					end)
				else
					M.ensure_refactorex(function()
						vim.notify("RefactorEx: installed successfully, starting server...", vim.log.levels.INFO)
						start_lsp_server(opts, start_stdio_script)
					end)
				end

				server_started = true
			end
		end,
		once = true,
	})
end

return M
