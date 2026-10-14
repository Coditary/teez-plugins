-- teez zig adapter (std.testing via zig build test / zig test)

local parse_context = {
    file = nil,
}

local help_cache = nil

local function trim(value)
    return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function target_path(context)
    return context.target_path or "."
end

local function resolve_glob_hit(root, file)
    if file:sub(1, 1) == "/" then
        return file
    end
    return root .. "/" .. file
end

local function path_excluded(target, pattern)
    return filter.glob_match(target, pattern)
end

local function runner_targets(context)
    local target = target_path(context)
    if not context.runner or not context.runner.include then
        return { target }
    end

    local paths = {}
    local seen = {}
    for _, pattern in ipairs(context.runner.include) do
        for _, file in ipairs(fs.glob(target, pattern)) do
            local resolved = resolve_glob_hit(target, file)
            local excluded = false
            if context.runner.exclude then
                for _, exclude_pattern in ipairs(context.runner.exclude) do
                    if path_excluded(resolved, exclude_pattern) then
                        excluded = true
                        break
                    end
                end
            end
            if not excluded and not seen[resolved] then
                seen[resolved] = true
                table.insert(paths, resolved)
            end
        end
    end

    if #paths == 0 then
        return { target }
    end
    return paths
end

local function zig_command(context)
    if context.runner and context.runner.command then
        return context.runner.command
    end
    return "zig"
end

local function normalize_path(value)
    return value:gsub("\\", "/")
end

local function relative_test_path(root, absolute_path)
    local normalized_root = normalize_path(root):gsub("/+$", "")
    local normalized_path = normalize_path(absolute_path)
    local prefix = normalized_root .. "/"
    if normalized_path:sub(1, #prefix) == prefix then
        return normalized_path:sub(#prefix + 1)
    end
    return normalized_path:match("([^/]+%.zig)$") or normalized_path
end

local function join_titles(parts)
    return table.concat(parts, " > ")
end

local function make_test_id(rel_file, name)
    if rel_file and rel_file ~= "" then
        return join_titles({ rel_file, name })
    end
    return name
end

local function has_build_zig(context)
    local target = target_path(context)
    return fs.exists(target .. "/build.zig") or fs.exists(fs.join(target, "build.zig"))
end

local function use_build_system(context)
    local runner = context.runner or {}
    if runner.use_build == false then
        return false
    end
    if runner.use_build == true then
        return true
    end
    return has_build_zig(context)
end

local function zig_test_help(context)
    if help_cache then
        return help_cache
    end
    local result = sys.run(zig_command(context or {}), { "test", "--help" })
    help_cache = result.stdout or ""
    return help_cache
end

local function flag_supported(context, flag_pattern)
    return zig_test_help(context):match(flag_pattern) ~= nil
end

local function list_tests_supported(context)
    return flag_supported(context, "%-%-list%-tests")
end

local function coverage_supported(context)
    return flag_supported(context, "%-%-coverage") or flag_supported(context, "%-fcoverage")
end

local function test_filter_pattern(context)
    if context.runner and context.runner.pattern then
        return context.runner.pattern
    end
    if context.filters and type(context.filters.name) == "string" and context.filters.name ~= "" then
        return context.filters.name
    end
    return nil
end

local function append_runner_args(args, context)
    if not context.runner then
        return
    end

    if context.runner.args then
        for _, arg in ipairs(context.runner.args) do
            table.insert(args, arg)
        end
    end
end

local function append_test_filter(args, context, needs_separator)
    local pattern = test_filter_pattern(context)
    if not pattern then
        return
    end

    if needs_separator then
        table.insert(args, "--")
    end
    table.insert(args, "--test-filter")
    table.insert(args, pattern)
end

local function zig_source_targets(context)
    local root = target_path(context)
    local targets = {}
    local seen = {}

    for _, target in ipairs(runner_targets(context)) do
        if target:match("%.zig$") then
            local rel = relative_test_path(root, target)
            if not seen[rel] then
                seen[rel] = true
                table.insert(targets, rel)
            end
        end
    end

    if #targets > 0 then
        return targets
    end

    for _, file in ipairs(fs.glob(root, "**/*.zig")) do
        local rel = relative_test_path(root, resolve_glob_hit(root, file))
        if not seen[rel] then
            seen[rel] = true
            table.insert(targets, rel)
        end
    end

    table.sort(targets)
    return targets
end

local function append_zig_test_targets(args, context)
    local root = target_path(context)
    for _, rel in ipairs(zig_source_targets(context)) do
        table.insert(args, rel)
    end
end

local function collect_tests_from_list_output(context, rel_file, output)
    local tests = {}
    for line in output:gmatch("[^\r\n]+") do
        line = trim(line)
        if line ~= "" and not line:match("^error:") then
            table.insert(tests, make_test_id(rel_file, line))
        end
    end
    return tests
end

local function collect_tests_for_file(context, rel_file)
    local root = target_path(context)
    local args = { "test", "--list-tests", rel_file }
    append_runner_args(args, context)
    append_test_filter(args, context, false)

    local result = sys.run(zig_command(context), args, { cwd = root })
    if result.exit_code ~= 0 or not result.stdout or result.stdout == "" then
        return {}
    end

    return collect_tests_from_list_output(context, rel_file, result.stdout)
end

local function collect_tests_from_file_scan(context)
    local tests = {}
    for _, rel_file in ipairs(zig_source_targets(context)) do
        for _, test_id in ipairs(collect_tests_for_file(context, rel_file)) do
            table.insert(tests, test_id)
        end
    end
    table.sort(tests)
    return tests
end

local function apply_filters(tests, context)
    if not context.filters then
        return tests
    end

    local filtered = {}
    for _, id in ipairs(tests) do
        if filter.matches({ id = id }, context.filters) then
            table.insert(filtered, id)
        end
    end
    return filtered
end

local function collect_tests(context)
    local tests = {}

    if list_tests_supported(context) then
        tests = collect_tests_from_file_scan(context)
    end

    if #tests == 0 then
        local root = target_path(context)
        for _, rel_file in ipairs(zig_source_targets(context)) do
            table.insert(tests, rel_file)
        end
        table.sort(tests)
    end

    return apply_filters(tests, context)
end

local function shallow_merge(base, overrides)
    local merged = {}
    for key, value in pairs(base) do
        merged[key] = value
    end
    if type(overrides) == "table" then
        for key, value in pairs(overrides) do
            merged[key] = value
        end
    end
    return merged
end

local function runner_cfg(context)
    if type(context.runner) == "table" then
        return context.runner
    end
    return {}
end

local function coverage_cfg(context)
    local cfg = runner_cfg(context)
    local from_runner = type(cfg.coverage) == "table" and cfg.coverage or {}
    local from_global = type(config) == "table" and type(config.coverage) == "table" and config.coverage
        or {}
    return shallow_merge(from_global, from_runner)
end

local function default_coverage_cfg(_context)
    return {
        reports_directory = "zig-out/coverage",
        report = "zig-out/coverage/lcov.info",
        output = "coverage/teez.msgpack",
        reporter = "msgpack",
    }
end

local function effective_coverage_cfg(context)
    return shallow_merge(default_coverage_cfg(context), coverage_cfg(context))
end

local function looks_like_test_id(id)
    if id:match("%.zig%s*>") then
        return true
    end
    return id:match("^[%w%.]+$") ~= nil
end

local function with_duration(event, duration_ms)
    if duration_ms ~= nil then
        event.duration_ms = duration_ms
    end
    return event
end

local function parse_duration(value)
    if not value then
        return nil
    end

    local amount, unit = trim(value):match("^([%d%.]+)%s*(ns|us|µs|ms|s)$")
    if not amount then
        return nil
    end

    amount = tonumber(amount)
    if not amount then
        return nil
    end

    if unit == "ns" then
        return amount / 1000000
    end
    if unit == "us" or unit == "µs" then
        return amount / 1000
    end
    if unit == "ms" then
        return amount
    end
    if unit == "s" then
        return amount * 1000
    end

    return nil
end

local function strip_ansi(line)
    return line:gsub("%c%[[%d;]*m", "")
end

local function should_ignore_line(line)
    if line:match("^All %d+ tests passed%.?$") then
        return true
    end
    if line:match("^%d+ tests? failed") then
        return true
    end
    if line:match("^Build Summary") or line:match("^%s*%- ") then
        return true
    end
    if line:match("^error:") or line:match("^warning:") then
        return true
    end
    if line:match("^Compile ") or line:match("^Link ") then
        return true
    end
    return false
end

local function match_test_result(line)
    local file, name, status, duration = line:match("^(.+%.zig):(.+)%.%.%. (OK|FAILED|SKIP)(?: %((.+)%))?$")
    if file and name then
        return file, trim(name), status, duration
    end

    local _, _, test_name, status2, duration2 = line:match("^Test %[(%d+)/(%d+)%] (.+)%.%.%. (OK|FAILED|SKIP)(?: %((.+)%))?$")
    if test_name then
        return parse_context.file, trim(test_name), status2, duration2
    end

    local _, _, test_name3, status3, duration3 = line:match("^%[(%d+)/(%d+)%] (.+)%.%.%. (OK|FAILED|SKIP)(?: %((.+)%))?$")
    if test_name3 then
        return parse_context.file, trim(test_name3), status3, duration3
    end

    return nil, nil, nil, nil
end

local function normalize_file_ref(file)
    if not file then
        return nil
    end
    file = normalize_path(file)
    if file:sub(1, 2) == "./" then
        file = file:sub(3)
    end
    return file
end

function prefetch_starts()
    return false
end

function list(context)
    return collect_tests(context)
end

function build_command(context)
    parse_context.file = nil

    local root = target_path(context)
    local sources = zig_source_targets(context)
    if #sources == 1 then
        parse_context.file = sources[1]
    end

    if use_build_system(context) then
        local args = { "build", "test" }
        if flag_supported(context, "%-%-summary") then
            table.insert(args, "--summary")
            table.insert(args, "all")
        end
        append_runner_args(args, context)
        append_test_filter(args, context, true)

        return {
            command = zig_command(context),
            args = args,
            cwd = root,
        }
    end

    local args = { "test" }
    append_test_filter(args, context, false)
    append_runner_args(args, context)
    append_zig_test_targets(args, context)

    return {
        command = zig_command(context),
        args = args,
        cwd = root,
    }
end

function build_list_command(context)
    local root = target_path(context)
    local args = { "test", "--list-tests" }
    append_runner_args(args, context)
    append_test_filter(args, context, false)
    append_zig_test_targets(args, context)

    return {
        command = zig_command(context),
        args = args,
        cwd = root,
    }
end

function build_coverage_run(context)
    if not coverage_supported(context) then
        return nil
    end

    parse_context.file = nil

    local root = target_path(context)
    local cov = effective_coverage_cfg(context)
    local reports_directory = cov.reports_directory or "zig-out/coverage"
    local report = cov.report or fs.join(reports_directory, "lcov.info")

    if use_build_system(context) then
        local args = { "build", "test" }
        if cov.build_arg then
            table.insert(args, cov.build_arg)
        else
            table.insert(args, "-Dcoverage=true")
        end
        append_runner_args(args, context)
        append_test_filter(args, context, true)

        return {
            command = zig_command(context),
            args = args,
            cwd = root,
            report = report,
            reporter = cov.reporter or "msgpack",
            output = cov.output or "coverage/teez.msgpack",
            min_line_rate = cov.min_line_rate,
        }
    end

    local args = { "test", "--coverage" }
    if cov.args then
        for _, arg in ipairs(cov.args) do
            table.insert(args, arg)
        end
    end
    append_test_filter(args, context, false)
    append_runner_args(args, context)
    append_zig_test_targets(args, context)

    return {
        command = zig_command(context),
        args = args,
        cwd = root,
        report = report,
        reporter = cov.reporter or "msgpack",
        output = cov.output or "coverage/teez.msgpack",
        min_line_rate = cov.min_line_rate,
    }
end

function parse_line(line)
    line = trim(strip_ansi(line))
    if line == "" or should_ignore_line(line) then
        return nil
    end

    local running_file = line:match("^running %d+ tests? from %./(.+)$")
        or line:match("^running %d+ tests? from (.+)$")
    if running_file then
        parse_context.file = normalize_file_ref(running_file)
        return nil
    end

    local file, name, status, duration_raw = match_test_result(line)
    if not name or not status then
        return nil
    end

    file = normalize_file_ref(file)
    local id = make_test_id(file, name)
    if not looks_like_test_id(id) then
        return nil
    end

    local duration_ms = parse_duration(duration_raw)

    if status == "OK" then
        return with_duration({ event = "pass", id = id }, duration_ms)
    end

    if status == "FAILED" then
        return with_duration({ event = "fail", id = id, msg = "FAILED" }, duration_ms)
    end

    if status == "SKIP" then
        return with_duration({ event = "skip", id = id }, duration_ms)
    end

    return nil
end
