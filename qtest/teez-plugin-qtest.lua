local function runner_opts(context)
    return context.runner or {}
end

local function join_path(a, b)
    if a:sub(-1) == "/" then
        return a .. b
    end
    return a .. "/" .. b
end

local function resolve_build_dir(target_path, opts)
    local candidates = {}

    if opts.build_dir then
        local dir = opts.build_dir
        if not dir:match("^/") then
            dir = join_path(target_path, dir)
        end
        table.insert(candidates, dir)
    end

    for _, name in ipairs({ "build", "cmake-build-debug", "cmake-build-release", "out/build" }) do
        table.insert(candidates, join_path(target_path, name))
    end
    table.insert(candidates, target_path)

    for _, dir in ipairs(candidates) do
        if fs.exists(join_path(dir, "CTestTestfile.cmake"))
            or fs.exists(join_path(dir, "CMakeCache.txt"))
            or fs.exists(join_path(dir, "Makefile"))
        then
            return dir
        end
    end

    return opts.build_dir and join_path(target_path, opts.build_dir) or join_path(target_path, "build")
end

local function detect_backend(target_path, opts)
    local build_dir = resolve_build_dir(target_path, opts)
    if fs.exists(join_path(build_dir, "CTestTestfile.cmake")) then
        return "cmake", build_dir
    end
    if fs.exists(join_path(build_dir, "CMakeCache.txt")) then
        return "cmake", build_dir
    end
    local pros = fs.glob(target_path, "*.pro")
    if pros and #pros > 0 then
        return "qmake", build_dir
    end
    if fs.exists(join_path(target_path, "CMakeLists.txt")) then
        return "cmake", build_dir
    end
    return "cmake", build_dir
end

local function include_patterns(opts)
    local patterns = opts.include
    if not patterns or #patterns == 0 then
        patterns = { "**/tests/**", "**/*_test.cpp", "**/*Test.qml" }
    end
    return patterns
end

local function exclude_patterns(opts)
    local patterns = opts.exclude or {}
    local merged = {}
    for _, pattern in ipairs(patterns) do
        table.insert(merged, pattern)
    end
    table.insert(merged, "**/*.teez.lua")
    return merged
end

local function path_matches_globs(path, includes, excludes)
    for _, pattern in ipairs(excludes) do
        if filter.glob_match(path, pattern) then
            return false
        end
    end
    for _, pattern in ipairs(includes) do
        if filter.glob_match(path, pattern) then
            return true
        end
    end
    return false
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

local function ctest_args(opts, extra)
    local args = { "-N" }
    if opts.config then
        table.insert(args, "-C")
        table.insert(args, opts.config)
    end
    if opts.regex then
        table.insert(args, "-R")
        table.insert(args, opts.regex)
    end
    if opts.exclude_regex then
        table.insert(args, "-E")
        table.insert(args, opts.exclude_regex)
    end
    if extra then
        for _, arg in ipairs(extra) do
            table.insert(args, arg)
        end
    end
    if opts.args then
        for _, arg in ipairs(opts.args) do
            table.insert(args, arg)
        end
    end
    return args
end

local function parse_ctest_list(output)
    local tests = {}
    local seen = {}
    for line in output:gmatch("[^\r\n]+") do
        local name = line:match("^%s*Test #%d+:%s+(.+)$")
        if name and not seen[name] then
            seen[name] = true
            table.insert(tests, name)
        end
    end
    return tests
end

local function list_qmake_tests(target_path, build_dir, opts)
    local tests = {}
    local seen = {}

    local pros = fs.glob(target_path, "*.pro")
    for _, pro in ipairs(pros or {}) do
        local content = nil
        local result = sys.run("cat", { pro })
        if result.exit_code == 0 then
            content = result.stdout
        end
        if content then
            for test_name in content:gmatch("TESTS%s*%+=%s*([%w_%-%.]+)") do
                if not seen[test_name] then
                    seen[test_name] = true
                    table.insert(tests, test_name)
                end
            end
        end
    end

    local makefile = join_path(build_dir, "Makefile")
    if fs.exists(makefile) then
        local result = sys.run("cat", { makefile })
        if result.exit_code == 0 then
            local content = result.stdout
            for target in content:gmatch("\n([%w_%-%.]+_test):") do
                if not seen[target] then
                    seen[target] = true
                    table.insert(tests, target)
                end
            end
        end
    end

    local includes = include_patterns(opts)
    local excludes = exclude_patterns(opts)
    for _, pattern in ipairs({ "**/*_test", "**/tests/**" }) do
        for _, path in ipairs(fs.glob(target_path, pattern) or {}) do
            local base = path:match("([^/]+)$") or path
            if path_matches_globs(path, includes, excludes) and not seen[base] then
                seen[base] = true
                table.insert(tests, base)
            end
        end
    end

    return tests
end

local function uses_ninja(build_dir)
    if not fs.exists(join_path(build_dir, "build.ninja")) then
        return false
    end
    return true
end

local function coverage_tool(opts)
    local coverage = opts.coverage or {}
    local tool = coverage.tool or coverage.collector or "gcovr"
    if tool == "llvm-cov" or tool == "llvm_cov" then
        return "llvm-cov"
    end
    return "gcovr"
end

local function coverage_collect_spec(target_path, build_dir, opts)
    local coverage = opts.coverage or {}
    local tool = coverage_tool(opts)
    local report = coverage.report or "coverage/lcov.info"
    local output = coverage.output or "coverage/teez.msgpack"
    local reporter = coverage.reporter or "msgpack"

    if tool == "llvm-cov" then
        local profile = coverage.profile or join_path(build_dir, "default.profdata")
        local objects = coverage.objects or { join_path(build_dir, "**") }
        local args = { "export", profile }
        for _, object in ipairs(objects) do
            table.insert(args, object)
        end
        if coverage.llvm_cov_args then
            for _, arg in ipairs(coverage.llvm_cov_args) do
                table.insert(args, arg)
            end
        end
        table.insert(args, "--format=lcov")
        table.insert(args, "-o")
        table.insert(args, report)
        return {
            command = "llvm-cov",
            args = args,
        }
    end

    local gcovr_args = {
        "--root",
        target_path,
        "--build-root",
        build_dir,
        "--lcov",
        "--output",
        report,
    }
    if coverage.filters then
        for _, pattern in ipairs(coverage.filters) do
            table.insert(gcovr_args, "--filter")
            table.insert(gcovr_args, pattern)
        end
    end
    if coverage.gcovr_args then
        for _, arg in ipairs(coverage.gcovr_args) do
            table.insert(gcovr_args, arg)
        end
    end

    return {
        command = "gcovr",
        args = gcovr_args,
    }
end

function list(context)
    local opts = runner_opts(context)
    local backend, build_dir = detect_backend(context.target_path, opts)

    local tests = {}
    if backend == "cmake" then
        local args = ctest_args(opts)
        local output = sys.exec("ctest", args, { cwd = build_dir })
        tests = parse_ctest_list(output)
    else
        tests = list_qmake_tests(context.target_path, build_dir, opts)
    end

    return apply_filters(tests, context)
end

function build_command(context)
    local opts = runner_opts(context)
    local backend, build_dir = detect_backend(context.target_path, opts)

    if backend == "qmake" then
        local args = { "check" }
        if opts.verbose or opts.qtest_verbose then
            table.insert(args, "TESTARGS=-v")
        end
        if opts.args then
            for _, arg in ipairs(opts.args) do
                table.insert(args, arg)
            end
        end
        return {
            command = "make",
            args = args,
            cwd = build_dir,
        }
    end

    if opts.use_ninja or (opts.generator == "ninja" and uses_ninja(build_dir)) then
        local args = { "test" }
        if opts.verbose or opts.qtest_verbose then
            table.insert(args, "-v")
        end
        if opts.args then
            for _, arg in ipairs(opts.args) do
                table.insert(args, arg)
            end
        end
        return {
            command = "ninja",
            args = args,
            cwd = build_dir,
            env = opts.env,
        }
    end

    local args = { "--output-on-failure" }
    if opts.verbose or opts.qtest_verbose then
        table.insert(args, "-V")
    end
    if opts.config then
        table.insert(args, "-C")
        table.insert(args, opts.config)
    end
    if opts.regex then
        table.insert(args, "-R")
        table.insert(args, opts.regex)
    end
    if opts.exclude_regex then
        table.insert(args, "-E")
        table.insert(args, opts.exclude_regex)
    end
    if context.filters and context.filters.name then
        table.insert(args, "-R")
        table.insert(args, context.filters.name)
    end
    if opts.parallel then
        table.insert(args, "-j")
        table.insert(args, tostring(opts.parallel))
    end
    if opts.args then
        for _, arg in ipairs(opts.args) do
            table.insert(args, arg)
        end
    end

    local env = opts.env
    if opts.qtest_verbose and not env then
        env = { QT_LOGGING_RULES = "qt.qpa.*=false" }
    end

    return {
        command = "ctest",
        args = args,
        cwd = build_dir,
        env = env,
    }
end

function parse_line(line)
    if line == "" then
        return nil
    end

    local qtest_pass = line:match("^%s*PASS%s*:%s*(.+)$")
    if qtest_pass then
        return { event = "pass", id = qtest_pass }
    end

    local qtest_fail = line:match("^%s*FAIL!%s*:%s*(.+)$")
    if qtest_fail then
        local id = qtest_fail:match("^([^%(]+)") or qtest_fail
        id = id:gsub("%s+$", "")
        return { event = "fail", id = id, msg = qtest_fail }
    end

    local qtest_skip = line:match("^%s*SKIP%s*:%s*(.+)$")
    if qtest_skip then
        return { event = "skip", id = qtest_skip }
    end

    local qtest_xfail = line:match("^%s*XFAIL%s*:%s*(.+)$")
    if qtest_xfail then
        return { event = "pass", id = qtest_xfail }
    end

    local ctest_pass = line:match("^%s*%d+/%d+%s+Test #%d+:%s+([^%.]+).*Passed")
    if ctest_pass then
        ctest_pass = ctest_pass:gsub("%s+$", "")
        return { event = "pass", id = ctest_pass }
    end

    local ctest_fail = line:match("^%s*%d+/%d+%s+Test #%d+:%s+([^%.]+).*Failed")
    if ctest_fail then
        ctest_fail = ctest_fail:gsub("%s+$", "")
        return { event = "fail", id = ctest_fail, msg = line }
    end

    local ctest_start = line:match("^%s*Start%s+%d+:%s+(.+)$")
    if ctest_start then
        return { event = "start", id = ctest_start }
    end

    if line:match("^%s*Test project ") or line:match("^%s*Label Time Summary:") then
        return nil
    end

    return { event = "output", text = line }
end

function build_coverage_run(context)
    local opts = runner_opts(context)
    local _, build_dir = detect_backend(context.target_path, opts)
    local coverage = opts.coverage or {}
    local collect = coverage_collect_spec(context.target_path, build_dir, opts)

    local run_args = { "--output-on-failure", "-V" }
    if opts.config then
        table.insert(run_args, "-C")
        table.insert(run_args, opts.config)
    end
    if opts.regex then
        table.insert(run_args, "-R")
        table.insert(run_args, opts.regex)
    end
    if opts.args then
        for _, arg in ipairs(opts.args) do
            table.insert(run_args, arg)
        end
    end

    local env = opts.env or {}
    if coverage_tool(opts) == "gcovr" then
        env.CXXFLAGS = (env.CXXFLAGS or os.getenv("CXXFLAGS") or "") .. " -fprofile-arcs -ftest-coverage"
        env.CFLAGS = (env.CFLAGS or os.getenv("CFLAGS") or "") .. " -fprofile-arcs -ftest-coverage"
        env.LDFLAGS = (env.LDFLAGS or os.getenv("LDFLAGS") or "") .. " -fprofile-arcs -ftest-coverage"
    end

    return {
        command = "ctest",
        args = run_args,
        cwd = build_dir,
        env = env,
        collect = collect,
        report = coverage.report or "coverage/lcov.info",
        reporter = coverage.reporter or "msgpack",
        output = coverage.output or "coverage/teez.msgpack",
        min_line_rate = coverage.min_line_rate,
    }
end
