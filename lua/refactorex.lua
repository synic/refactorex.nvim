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

local M = {
	config = {
		filetypes = { "elixir" },
		cmd = {},
		root_dir = function(fname)
			local current = vim.fn.expand(fname)
			while current ~= "/" do
				if vim.fn.filereadable(current .. "/mix.exs") == 1 then
					return current
				end
				current = vim.fn.fnamemodify(current, ":h")
			end
			return vim.fn.getcwd()
		end,
		settings = {},
		github_url = github_url,
		auto_update = true,
		pin_version = nil,
	},
	installing = false,
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

local function get_client_config(opts)
	return {
		name = "refactorex",
		cmd = opts.cmd,
		filetypes = opts.filetypes,
		root_dir = opts.root_dir(vim.fn.expand("%:p")),
		settings = opts.settings,
		capabilities = vim.tbl_deep_extend("force", vim.lsp.protocol.make_client_capabilities(), {
			textDocumentSync = {
				openClose = true,
				change = 1,
				save = { includeText = true },
			},
			codeActionProvider = {
				resolveProvider = true,
			},
			renameProvider = true,
		}),
	}
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

local function download_refactorex(tar_file, version, callback)
	async_spawn(
		"curl",
		{
			"--fail",
			"-L",
			"--create-dirs",
			"-o",
			tar_file,
			string.format("%s/archive/refs/tags/%s.tar.gz", M.config.github_url, version),
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
				vim.fn.delete(tar_file)
				return
			end
			vim.fn.delete(tar_file)
			callback()
		end
	)
end

local function handle_install_error(msg, install_path)
	vim.notify("RefactorEx: " .. msg, vim.log.levels.ERROR)
	M.installing = false
	if install_path then
		rmdir_rf(install_path)
	end
end

local function install_mix_dependencies(install_path, callback)
	async_spawn("mix", { "deps.get" }, install_path, function(success)
		if not success then
			handle_install_error("failed to run mix deps.get", install_path)
			return
		end
		callback()
	end)
end

local function compile_refactorex(install_path, callback)
	async_spawn("mix", { "compile" }, install_path, function(success)
		if not success then
			handle_install_error("failed to compile", install_path)
			return
		end
		M.installing = false
		callback()
	end)
end

local function get_installed_versions()
	local versions = {}
	local handle = vim.loop.fs_scandir(install_dir)
	if handle then
		while true do
			local name = vim.loop.fs_scandir_next(handle)
			if not name then
				break
			end
			if name:match("^refactorex%-") and dir_exists(path_join(install_dir, name)) then
				local version = name:match("^refactorex%-(.+)$")
				if version then
					table.insert(versions, version)
				end
			end
		end
	end
	return versions
end

local function get_latest_version(callback)
	async_spawn(
		"curl",
		{
			"-s",
			"https://api.github.com/repos/gp-pereira/refactorex/releases/latest",
		},
		nil,
		function(success, stdout, _)
			if not success then
				vim.notify("RefactorEx: Failed to check latest version", vim.log.levels.ERROR)
				callback(nil)
				return
			end

			local response = table.concat(stdout)
			local version = response:match('"name":%s*"([^"]+)"')
			if version then
				version = version:match("^%s*(.-)%s*$")
				callback(version)
			else
				vim.notify("RefactorEx: Failed to parse version from response", vim.log.levels.ERROR)
				callback(nil)
			end
		end
	)
end

local function start_lsp_server(opts, install_path, callback)
	local start_script = path_join(install_path, "bin/start")
	opts.cmd = { start_script, "--stdio" }

	local function start_server()
		local client_config = get_client_config(opts)
		local client = vim.lsp.get_clients({ name = "refactorex" })[1]

		if client then
			client.stop()
		end

		vim.defer_fn(function()
			vim.lsp.start(client_config)
			if callback then
				callback()
			end
		end, client and 100 or 0)
	end

	vim.schedule(start_server)
end

function M.ensure_refactorex(callback, opts)
	local function install_version(version)
		local install_path = path_join(install_dir, "refactorex-" .. version)
		local tar_file = path_join(install_dir, string.format("refactorex-%s.tar.gz", version))

		if not dir_exists(install_dir) then
			mkdir_p(install_dir)
		end

		local installed_versions = get_installed_versions()
		local current_version = installed_versions[#installed_versions]

		if dir_exists(install_path) then
			rmdir_rf(install_path)
		end

		if M.installing then
			if callback then
				table.insert(M.pending_server_starts, callback)
			end
			return
		end

		M.installing = true

		if current_version then
			if current_version == version then
				vim.notify(string.format("RefactorEx: reinstalling v%s", version), vim.log.levels.INFO)
			else
				local action = "upgrading"
				if current_version > version then
					action = "downgrading"
				end
				vim.notify(
					string.format("RefactorEx: %s from v%s to v%s", action, current_version, version),
					vim.log.levels.INFO
				)
			end
		else
			vim.notify(string.format("RefactorEx: installing v%s", version), vim.log.levels.INFO)
		end

		download_refactorex(tar_file, version, function()
			extract_tarball(tar_file, function()
				vim.notify("RefactorEx: compiling...", vim.log.levels.INFO)
				install_mix_dependencies(install_path, function()
					compile_refactorex(install_path, function()
						M.installing = false
						if opts then
							vim.notify(
								string.format("RefactorEx: starting server with v%s", version),
								vim.log.levels.INFO
							)
							start_lsp_server(opts, install_path, function()
								if callback then
									callback(install_path)
								end
							end)
						else
							if callback then
								callback(install_path)
							end
						end
						for _, pending_callback in ipairs(M.pending_server_starts) do
							pending_callback(install_path)
						end
						M.pending_server_starts = {}
					end)
				end)
			end)
		end)
	end

	if opts and opts.pin_version then
		install_version(opts.pin_version)
	else
		get_latest_version(function(version)
			if not version then
				if callback then
					callback(nil)
				end
				return
			end
			install_version(version)
		end)
	end
end

function M.setup(opts)
	opts = vim.tbl_deep_extend("force", M.config, opts or {})

	local ok, err = pcall(check_dependencies)
	if not ok then
		vim.notify(tostring(err), vim.log.levels.ERROR)
		return
	end

	local function create_commands()
		vim.api.nvim_create_user_command("RefactorExDownload", function()
			M.ensure_refactorex(function(install_path)
				if install_path then
					start_lsp_server(opts, install_path)
				end
			end, opts)
		end, {
			desc = "Download and install RefactorEx (respects pinned version if set)",
		})
	end

	create_commands()

	local installed_versions = get_installed_versions()
	local server_started = false

	local function start_server(install_path)
		if not server_started and install_path then
			local start_script = path_join(install_path, "bin/start")
			if file_exists(start_script) then
				start_lsp_server(opts, install_path, function()
					server_started = true
				end)
			end
		end
	end

	local function setup_server(install_path)
		vim.api.nvim_create_autocmd("FileType", {
			pattern = "elixir",
			callback = function()
				start_server(install_path)
			end,
			once = true,
		})

		if vim.bo.filetype == "elixir" then
			start_server(install_path)
		end
	end

	if opts.pin_version then
		local pinned_path = path_join(install_dir, "refactorex-" .. opts.pin_version)
		if not dir_exists(pinned_path) then
			M.ensure_refactorex(function(install_path)
				if install_path then
					setup_server(install_path)
				end
			end, opts)
		else
			setup_server(pinned_path)
		end
	elseif #installed_versions == 0 then
		M.ensure_refactorex(function(install_path)
			if install_path then
				setup_server(install_path)
			end
		end, opts)
	elseif opts.auto_update then
		get_latest_version(function(latest_version)
			local current = installed_versions[#installed_versions]
			if latest_version and latest_version ~= current then
				M.ensure_refactorex(function(install_path)
					if install_path then
						setup_server(install_path)
					end
				end, opts)
			else
				setup_server(path_join(install_dir, "refactorex-" .. current))
			end
		end)
	else
		setup_server(path_join(install_dir, "refactorex-" .. installed_versions[#installed_versions]))
	end
end

return M
