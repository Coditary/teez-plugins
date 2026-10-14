local DEFAULT_INCLUDE = { "**/tests/**", "**/*_test.stan" }

local function runner_cfg(context)
    return context.runner or {}
end

local function include_patterns(context)
    local cfg = runner_cfg(context)
    if cfg.include then
        return cfg.include
    end
    return DEFAULT_INCLUDE
end

local function exclude_patterns(context)
    local cfg = runner_cfg(context)
    return cfg.exclude or {}
end

local function is_excluded(path, excludes)
    for _, pattern in ipairs(excludes) do
        if filter.glob_match(path, pattern) then
            return true
        end
    end
    return false
end

local function collect_tests(context)
    local root = context.target_path
    local includes = include_patterns(context)
    local excludes = exclude_patterns(context)
    local seen = {}
    local tests = {}

    for _, pattern in ipairs(includes) do
        local matches = fs.glob(root, pattern)
        for _, path in ipairs(matches) do
            if path:match("%.stan$") and not seen[path] and not is_excluded(path, excludes) then
                seen[path] = true
                table.insert(tests, path)
            end
        end
    end

    table.sort(tests)
    return tests
end

local function filter_tests(context, tests)
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

local function resolve_stanc(context)
    local cfg = runner_cfg(context)
    if cfg.stanc then
        return cfg.stanc
    end
    if cfg.cmdstan_path then
        return cfg.cmdstan_path .. "/bin/stanc"
    end
    return "stanc"
end

local function resolve_python(context)
    return runner_cfg(context).python or "python3"
end

local function resolve_test_script(context)
    local cfg = runner_cfg(context)
    if cfg.test_script then
        return cfg.test_script
    end
    if fs.exists("python/run_tests.py") then
        return "python/run_tests.py"
    end
    if fs.exists("run_tests.py") then
        return "run_tests.py"
    end
    return "python/run_tests.py"
end

local function build_env(context)
    local cfg = runner_cfg(context)
    local env = {}

    if cfg.env and type(cfg.env) == "table" then
        for key, value in pairs(cfg.env) do
            env[key] = value
        end
    end

    if cfg.cmdstan_path then
        env.CMDSTAN = cfg.cmdstan_path
        env.PATH = cfg.cmdstan_path .. "/bin:" .. (os.getenv("PATH") or "")
    end

    if next(env) == nil then
        return nil
    end
    return env
end

local function append_args(args, extra)
    if not extra then
        return
    end
    for _, value in ipairs(extra) do
        table.insert(args, value)
    end
end

local function shell_quote(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function build_python_harness(context, tests)
    local cfg = runner_cfg(context)
    local args = { resolve_test_script(context) }
    append_args(args, cfg.args)
    for _, test in ipairs(tests) do
        table.insert(args, test)
    end

    return {
        command = resolve_python(context),
        args = args,
        env = build_env(context),
    }
end

local function build_cmdstan_harness(context, tests)
    local cfg = runner_cfg(context)
    local stanc = resolve_stanc(context)
    local stanc_args = cfg.stanc_args or { "--warn=error" }
    local stanc_arg_text = table.concat(stanc_args, " ")

    local body = {}
    table.insert(body, "set -e")
    for _, test in ipairs(tests) do
        table.insert(
            body,
            string.format(
                'echo "START %s"; if %s %s %s -o=/tmp/teez_stan_%s 2>&1; then echo "PASS %s"; else echo "FAIL %s: stanc compilation failed"; exit 1; fi',
                test,
                stanc,
                stanc_arg_text,
                shell_quote(test),
                test:gsub("[^%w]", "_"),
                test,
                test
            )
        )
    end

    return {
        command = "sh",
        args = { "-c", table.concat(body, "; ") },
        env = build_env(context),
    }
end

function list(context)
    return filter_tests(context, collect_tests(context))
end

function build_command(context)
    local cfg = runner_cfg(context)
    local harness = cfg.harness or "python"
    local tests = filter_tests(context, collect_tests(context))

    if #tests == 0 then
        error("no Stan test models found (include: tests/**, *_test.stan)")
    end

    if harness == "cmdstan" then
        return build_cmdstan_harness(context, tests)
    end
    return build_python_harness(context, tests)
end

function parse_line(line)
    local pass_id = line:match("^PASS%s+(.+)$")
    if pass_id then
        return { event = "pass", id = pass_id }
    end

    local fail_id, msg = line:match("^FAIL%s+([^:]+):%s*(.+)$")
    if fail_id then
        return { event = "fail", id = fail_id, msg = msg }
    end

    fail_id = line:match("^FAIL%s+(.+)$")
    if fail_id then
        return { event = "fail", id = fail_id, msg = line }
    end

    local start_id = line:match("^START%s+(.+)$")
    if start_id then
        return { event = "start", id = start_id }
    end

    local skip_id = line:match("^SKIP%s+(.+)$")
    if skip_id then
        return { event = "skip", id = skip_id }
    end

    local pytest_pass = line:match("(%S+%.stan)%s+PASSED")
    if pytest_pass then
        return { event = "pass", id = pytest_pass }
    end

    local pytest_fail = line:match("(%S+%.stan)%s+FAILED")
    if pytest_fail then
        return { event = "fail", id = pytest_fail, msg = line }
    end

    local ok_id = line:match("^OK%s+(.+)$")
    if ok_id then
        return { event = "pass", id = ok_id }
    end

    return { event = "output", text = line }
end
