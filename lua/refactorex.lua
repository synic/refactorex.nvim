-- LSP client configuration
local lspconfig = require("lspconfig")
local configs = require("lspconfig.configs")

local refactorex_version =
	vim.fn.readfile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/refactorex-version.txt")[1]
local github_url = "https://github.com/gp-pereira/refactorex"

local function path_join(...)
	local parts = { ... }
	return table.concat(parts, "/"):gsub("//+", "/")
end

local function file_exists(path)
	local stat = vim.loop.fs_stat(path)
	return stat and stat.type == "file"
end

local function dir_exists(path)
	local stat = vim.loop.fs_stat(path)
	return stat and stat.type == "directory"
end

local function mkdir_p(path)
	return vim.fn.mkdir(path, "p")
end

local function rmdir_rf(path)
	if vim.fn.has("win32") == 1 then
		vim.fn.system(string.format('rd /s /q "%s"', path))
	else
		vim.fn.system(string.format('rm -rf "%s"', path))
	end
end

local install_dir = path_join(vim.fn.stdpath("data"), "refactorex")
local install_path = path_join(install_dir, "refactorex-" .. refactorex_version)
local start_script = path_join(install_path, "bin/start")

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

local function async_spawn(cmd, args, cwd, on_exit)
	local stdout, stderr = {}, {}

	local stdout_pipe = vim.loop.new_pipe(false)
	local stderr_pipe = vim.loop.new_pipe(false)

	local handle
	handle = vim.loop.spawn(cmd, {
		args = args,
		cwd = cwd,
		stdio = { nil, stdout_pipe, stderr_pipe },
	}, function(code, _)
		if handle then
			handle:close()
		end
		if on_exit then
			vim.schedule(function()
				on_exit(code == 0, stdout, stderr)
			end)
		end
	end)

	if handle then
		vim.loop.read_start(stdout_pipe, function(_, data)
			if data then
				table.insert(stdout, data)
			end
		end)

		vim.loop.read_start(stderr_pipe, function(_, data)
			if data then
				table.insert(stderr, data)
			end
		end)
	else
		if on_exit then
			vim.schedule(function()
				on_exit(false, stdout, stderr)
			end)
		end
	end
end

local function download_refactorex(tar_file, callback)
	vim.notify("RefactorEx: downloading and installing updated release source...", vim.log.levels.INFO)

	async_spawn(
		"curl",
		{
			"--fail",
			"-L",
			"--create-dirs",
			"-o",
			tar_file,
			string.format("%s/archive/refs/tags/%s.tar.gz", M.config.github_url, refactorex_version),
		},
		nil,
		function(success, _)
			if not success then
				vim.notify("RefactorEx: failed to download release source", vim.log.levels.ERROR)
				M.installing = false
				return
			end
			callback()
		end
	)
end

local function extract_tarball(tar_file, callback)
	async_spawn(
		"tar",
		{
			"xzf",
			tar_file,
			"-C",
			install_dir,
		},
		nil,
		function(success)
			if not success then
				vim.notify("RefactorEx: failed to extract source tarball", vim.log.levels.ERROR)
				M.installing = false
				return
			end
			vim.fn.delete(tar_file)
			callback()
		end
	)
end

local function install_mix_dependencies(callback)
	async_spawn(
		"mix",
		{
			"deps.get",
		},
		install_path,
		function(success)
			if not success then
				vim.notify("RefactorEx: failed to run mix deps.get", vim.log.levels.ERROR)
				M.installing = false
				return
			end
			callback()
		end
	)
end

local function compile_refactorex(callback)
	async_spawn(
		"mix",
		{
			"compile",
		},
		install_path,
		function(success)
			if not success then
				vim.notify("RefactorEx: failed to compile", vim.log.levels.ERROR)
				M.installing = false
				return
			end
			M.installing = false
			M.install_complete = true
			callback()
		end
	)
end

function M.ensure_refactorex(callback, force_reinstall)
	local tar_file = path_join(install_dir, string.format("refactorex-%s.tar.gz", refactorex_version))
	local refactorex_path = path_join(install_dir, string.format("refactorex-%s", refactorex_version))

	if not dir_exists(install_dir) then
		mkdir_p(install_dir)
	end

	if force_reinstall and dir_exists(refactorex_path) then
		vim.notify("RefactorEx: removing existing RefactorEx installation...", vim.log.levels.INFO)
		rmdir_rf(refactorex_path)
	elseif dir_exists(refactorex_path) and not force_reinstall then
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
		extract_tarball(tar_file, function()
			install_mix_dependencies(function()
				compile_refactorex(function()
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
end

local function create_commands()
	vim.api.nvim_create_user_command("RefactorExDownload", function()
		M.ensure_refactorex(nil, true)
	end, {
		desc = "Download or update the RefactorEx binary",
	})
end

local function start_lsp_server(opts)
	opts.cmd = { start_script, "--stdio" }
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
				if file_exists(start_script) then
					start_lsp_server(opts)
				else
					M.ensure_refactorex(function()
						vim.notify("RefactorEx: installed successfully, starting server...", vim.log.levels.INFO)
						start_lsp_server(opts)
					end)
				end

				server_started = true
			end
		end,
		once = true,
	})
end

return M
