-- teez Ada AUnit runner — gprbuild/alr + optional gnatcov coverage

local function runner_opts(context)
    return context.runner or {}
end

local function tool_on_path(name)
    local result = sys.run("sh", { "-c", "command -v " .. name .. " >/dev/null 2>&1" })
    return result.exit_code == 0
end

local function uses_alr(context)
    local opts = runner_opts(context)
    if opts.use_alr ~= nil then
        return opts.use_alr
    end
    if opts.use_gprbuild then
        return false
    end
    return fs.exists("alr.toml") and tool_on_path("alr")
end

local function uses_gprbuild(context)
    if uses_alr(context) then
        return false
    end
    return tool_on_path("gprbuild")
end

local function join_path(dir, name)
    if dir == "" or dir == "." then
        return name
    end
    if dir:sub(-1) == "/" then
        return dir .. name
    end
    return dir .. "/" .. name
end

local DEFAULT_INCLUDE = {
    "**/*-tests.adb",
    "**/tests/**",
}

local function merge_patterns(runner)
    local patterns = {}
    local seen = {}

    local function add(pattern)
        if pattern and pattern ~= "" and not seen[pattern] then
            seen[pattern] = true
            table.insert(patterns, pattern)
        end
    end

    for _, pattern in ipairs(DEFAULT_INCLUDE) do
        add(pattern)
    end
    if runner.include then
        for _, pattern in ipairs(runner.include) do
            add(pattern)
        end
    end

    return patterns
end

local function should_exclude(path, runner)
    local excludes = runner.exclude or {
        "**/*.teez.lua",
    }
    for _, pattern in ipairs(excludes) do
        if filter.glob_match(path, pattern) then
            return true
        end
    end
    return false
end

local function collect_test_files(context)
    local opts = runner_opts(context)
    local patterns = merge_patterns(opts)
    local files = {}
    local seen = {}

    for _, pattern in ipairs(patterns) do
        for _, path in ipairs(fs.glob(context.target_path, pattern)) do
            if not should_exclude(path, opts) and not seen[path] then
                seen[path] = true
                table.insert(files, path)
            end
        end
    end

    table.sort(files)
    return files
end

local function basename(path)
    return path:match("([^/]+)$") or path
end

local function stem(path)
    local name = basename(path)
    return name:gsub("%.[^%.]+$", "")
end

local function package_name_from_file(path)
    local file_stem = stem(path)
    if file_stem:match("%-tests$") then
        local prefix = file_stem:sub(1, -7)
        if prefix ~= "" then
            return prefix:gsub("(%a)([%w_]*)", function(first, rest)
                return first:upper() .. rest
            end) .. "_Tests"
        end
    end
    return file_stem:gsub("(%a)([%w_]*)", function(first, rest)
        return first:upper() .. rest
    end)
end

local function read_file(path)
    local result = sys.run("cat", { path })
    if result.exit_code ~= 0 then
        return nil
    end
    return result.stdout
end

local function ids_from_test_sources(context)
    local ids = {}
    local seen = {}

    for _, path in ipairs(collect_test_files(context)) do
        if path:match("%.adb$") then
            local content = read_file(path)
            local package_name = package_name_from_file(path)

            if content then
                local pkg = content:match("package%s+([%w_%.]+)")
                if pkg then
                    package_name = pkg
                end

                for proc in content:gmatch("procedure%s+([%w_%.]+)%s*;") do
                    local id = package_name .. "." .. proc
                    if not seen[id] then
                        seen[id] = true
                        table.insert(ids, id)
                    end
                end
            end

            local fallback = package_name .. "." .. stem(path)
            if not seen[fallback] then
                seen[fallback] = true
                table.insert(ids, fallback)
            end
        elseif not path:match("%.") then
            local id = path:gsub("/", ".")
            if not seen[id] then
                seen[id] = true
                table.insert(ids, id)
            end
        end
    end

    table.sort(ids)
    return ids
end

local function find_project_file(context)
    local opts = runner_opts(context)
    if opts.project then
        return opts.project
    end

    local gpr_files = fs.glob(context.target_path, "*.gpr")
    table.sort(gpr_files)
    for _, path in ipairs(gpr_files) do
        local name = basename(path)
        if name:match("test") or name:match("tests") then
            return path
        end
    end
    if gpr_files[1] then
        return gpr_files[1]
    end
    return nil
end

local function executables_from_gpr(project_path)
    local content = read_file(project_path)
    if not content then
        return {}
    end

    local executables = {}
    local seen = {}

    local function add(name)
        if name and name ~= "" and not seen[name] then
            seen[name] = true
            table.insert(executables, name)
        end
    end

    for name in content:gmatch('Executable%s*%(%s*"([^"]+)"') do
        add(name)
    end
    for name in content:gmatch('for%s+Exec_Name%s+use%s*%(%s*"([^"]+)"') do
        add(name)
    end
    for name in content:gmatch('for%s+Main%s+use%s*%(%s*"([^"]+)"') do
        add(name)
    end

    return executables
end

local function discover_test_executables(context)
    local opts = runner_opts(context)
    if opts.test_executable then
        return { opts.test_executable }
    end

    local executables = {}
    local seen = {}

    local function add(path)
        if path and path ~= "" and not seen[path] then
            seen[path] = true
            table.insert(executables, path)
        end
    end

    local project = find_project_file(context)
    if project then
        for _, name in ipairs(executables_from_gpr(project)) do
            if name:match("test") then
                add(name)
            end
        end
        for _, name in ipairs(executables_from_gpr(project)) do
            add(name)
        end
    end

    for _, pattern in ipairs({
        "bin/*test*",
        "bin/*_tests",
        "obj/*/*test*",
        "**/*_test_runner",
        "**/*-tests",
    }) do
        for _, path in ipairs(fs.glob(context.target_path, pattern)) do
            if not path:match("%.") or path:match("%.exe$") then
                add(path)
            end
        end
    end

    return executables
end

local function filter_ids(ids, context)
    if not context.filters then
        return ids
    end

    local filtered = {}
    for _, id in ipairs(ids) do
        if filter.matches({ id = id }, context.filters) then
            table.insert(filtered, id)
        end
    end
    return filtered
end

local function unique_append(dest, src)
    local seen = {}
    for _, value in ipairs(dest) do
        seen[value] = true
    end
    for _, value in ipairs(src) do
        if not seen[value] then
            seen[value] = true
            table.insert(dest, value)
        end
    end
    return dest
end

local function list_from_alr(context)
    if not tool_on_path("alr") or not fs.exists("alr.toml") then
        return nil
    end

    local result = sys.run("alr", { "test", "--list" }, { cwd = context.target_path })
    if result.exit_code ~= 0 or result.stdout == "" then
        return nil
    end

    local ids = {}
    for line in result.stdout:gmatch("[^\r\n]+") do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed ~= "" and not trimmed:match("^#") and not trimmed:match("^%-%-") then
            table.insert(ids, trimmed)
        end
    end

    if #ids == 0 then
        return nil
    end
    return ids
end

function list(context)
    local ids = {}

    local alr_ids = list_from_alr(context)
    if alr_ids then
        ids = unique_append(ids, alr_ids)
    end

    ids = unique_append(ids, discover_test_executables(context))
    ids = unique_append(ids, ids_from_test_sources(context))

    return filter_ids(ids, context)
end

local function append_args(args, extra)
    if not extra then
        return
    end
    for _, value in ipairs(extra) do
        table.insert(args, value)
    end
end

local function append_filter_args(args, context)
    local opts = runner_opts(context)
    if opts.args then
        append_args(args, opts.args)
    end

    if not context.filters then
        return
    end

    if context.filters.name then
        for _, pattern in ipairs(context.filters.name) do
            table.insert(args, "--filter")
            table.insert(args, pattern)
        end
    end
end

local function build_alr_command(context)
    local args = { "test", "-q" }
    append_filter_args(args, context)
    return {
        command = "alr",
        args = args,
        cwd = context.target_path,
    }
end

local function shell_quote(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function build_gprbuild_run_command(context)
    local opts = runner_opts(context)
    local project = find_project_file(context)
    if not project then
        error("ada runner: no .gpr project file found")
    end

    local executables = discover_test_executables(context)
    local test_exe = opts.test_executable or executables[1]
    if not test_exe then
        error("ada runner: no test executable found; set runners.ada.test_executable")
    end

    local gprbuild_cmd = "gprbuild -P " .. shell_quote(project)
    if opts.gprbuild_args then
        for _, arg in ipairs(opts.gprbuild_args) do
            gprbuild_cmd = gprbuild_cmd .. " " .. shell_quote(arg)
        end
    end
    gprbuild_cmd = gprbuild_cmd .. " " .. shell_quote(test_exe)

    local run_args = {}
    append_filter_args(run_args, context)
    if opts.run_args then
        append_args(run_args, opts.run_args)
    end

    local run_cmd = shell_quote(test_exe)
    for _, arg in ipairs(run_args) do
        run_cmd = run_cmd .. " " .. shell_quote(arg)
    end

    local spec = {
        command = "sh",
        args = { "-c", gprbuild_cmd .. " && " .. run_cmd },
        cwd = opts.run_dir or context.target_path,
    }

    if opts.gpr_project_path then
        spec.env = { GPR_PROJECT_PATH = opts.gpr_project_path }
    end

    return spec
end

function build_command(context)
    if uses_alr(context) then
        if not tool_on_path("alr") then
            error("ada runner: alr not found on PATH")
        end
        return build_alr_command(context)
    end

    if not uses_gprbuild(context) then
        error("ada runner: neither alr nor gprbuild found on PATH")
    end

    return build_gprbuild_run_command(context)
end

local function trim(line)
    return (line:match("^%s*(.-)%s*$") or line)
end

local current_test_id = nil
local last_failed_id = nil

function parse_line(line)
    if line == "" then
        return nil
    end

    local text = trim(line)

    local test_case = text:match("^Test Case:%s+(.+)$")
    if test_case then
        current_test_id = test_case
        last_failed_id = nil
        return { event = "start", id = test_case }
    end

    if text:match("^Status:%s+PASSED%s*$") and current_test_id then
        local id = current_test_id
        current_test_id = nil
        last_failed_id = nil
        return { event = "pass", id = id }
    end

    if text:match("^Status:%s+FAILED%s*$") and current_test_id then
        last_failed_id = current_test_id
        current_test_id = nil
        return { event = "fail", id = last_failed_id, msg = "AUnit test failed" }
    end

    local error_msg = text:match("^Error:%s+(.+)$")
    if error_msg and last_failed_id then
        return { event = "output", text = text }
    end

    local passed = text:match("^PASSED:%s+(.+)$")
        or text:match("^%s*%[%s*PASSED%s*%]%s+(.+)$")
        or text:match("^%s*%[%s*OK%s*%]%s+(.+)$")
        or text:match("^ok%s+%d+%s+%-%s+(.+)$")
        or text:match("^Running Test%s+(.+)%s+%.%.%.%s+PASSED%s*$")
    if passed then
        return { event = "pass", id = passed }
    end

    local failed = text:match("^FAILED:%s+(.+)$")
        or text:match("^%s*%[%s*FAILED%s*%]%s+(.+)$")
        or text:match("^not ok%s+%d+%s+%-%s+(.+)$")
        or text:match("^Running Test%s+(.+)%s+%.%.%.%s+FAILED%s*$")
    if failed then
        return { event = "fail", id = failed, msg = text }
    end

    if text:match("^%s*=+%s*$") or text:match("^Running%s+tests") or text:match("^Running%s+%d+%s+tests") then
        return { event = "output", text = text }
    end

    return { event = "output", text = text }
end

local function coverage_enabled(context)
    local opts = runner_opts(context)
    return opts.coverage == true or opts.coverage == "gnatcov"
end

function build_coverage_run(context)
    if not coverage_enabled(context) then
        return nil
    end

    if not tool_on_path("gnatcov") then
        error("ada runner: gnatcov not found on PATH (set runners.ada.coverage = true)")
    end

    local opts = runner_opts(context)
    local project = find_project_file(context)
    if not project then
        error("ada runner: no .gpr project file found for coverage")
    end

    local output_dir = opts.coverage_dir or "coverage"
    local trace_file = join_path(output_dir, "gnatcov.trace")
    local lcov_file = join_path(output_dir, "lcov.info")

    local instrument_args = { "instrument", project }
    append_args(instrument_args, opts.gnatcov_instrument_args)

    local export_args = {
        "export",
        "--format=lcov",
        trace_file,
        "--output", lcov_file,
    }
    append_args(export_args, opts.gnatcov_export_args)

    local run_spec = build_command(context)
    run_spec.env = run_spec.env or {}
    run_spec.env.GNATCOV_TRACE_FILE = trace_file

    local instrument_cmd = "gnatcov instrument " .. shell_quote(project)
    if opts.gnatcov_instrument_args then
        for _, arg in ipairs(opts.gnatcov_instrument_args) do
            instrument_cmd = instrument_cmd .. " " .. shell_quote(arg)
        end
    end

    local run_shell = run_spec.command
    if run_spec.args and #run_spec.args > 0 then
        if run_spec.command == "sh" then
            run_shell = run_spec.args[2]
        else
            run_shell = run_spec.command
            for _, arg in ipairs(run_spec.args) do
                run_shell = run_shell .. " " .. shell_quote(arg)
            end
        end
    end

    return {
        command = "sh",
        args = { "-c", instrument_cmd .. " && " .. run_shell },
        cwd = context.target_path,
        env = run_spec.env,
        collect = {
            command = "gnatcov",
            args = export_args,
            cwd = context.target_path,
        },
        report = lcov_file,
        output = join_path(output_dir, "teez.msgpack"),
        reporter = opts.coverage_reporter or "lcov",
        min_line_rate = opts.min_line_rate,
    }
end
