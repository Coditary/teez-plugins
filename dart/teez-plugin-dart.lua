local prev_passed = 0
local prev_skipped = 0
local prev_failed = 0
local last_fail_id = nil

local DEFAULT_INCLUDE = { "**/test/**/*_test.dart", "**/test/**/*.dart" }

local function runner_opts(context)
    return context.runner or {}
end

local function include_patterns(context)
    local patterns = runner_opts(context).include
    if patterns and #patterns > 0 then
        return patterns
    end
    return DEFAULT_INCLUDE
end

local function exclude_patterns(context)
    return runner_opts(context).exclude or {}
end

local function matches_any(path, patterns)
    for _, pattern in ipairs(patterns) do
        if filter.glob_match(path, pattern) then
            return true
        end
    end
    return false
end

local function collect_test_paths(context)
    local root = context.target_path
    local include = include_patterns(context)
    local exclude = exclude_patterns(context)
    local seen = {}
    local paths = {}

    for _, pattern in ipairs(include) do
        for _, path in ipairs(fs.glob(root, pattern)) do
            if not seen[path] and not matches_any(path, exclude) then
                seen[path] = true
                table.insert(paths, path)
            end
        end
    end

    table.sort(paths)
    return paths
end

local function append_runner_args(args, context)
    local extra = runner_opts(context).args
    if extra then
        for _, arg in ipairs(extra) do
            table.insert(args, arg)
        end
    end

    local concurrency = runner_opts(context).concurrency
    if concurrency then
        table.insert(args, "--concurrency=" .. tostring(concurrency))
    end
end

local function append_filters(args, context)
    local filters = context.filters
    if not filters then
        return
    end

    if filters.names then
        for _, name in ipairs(filters.names) do
            table.insert(args, "--name")
            table.insert(args, name)
        end
    end

    if filters.plain_names then
        for _, name in ipairs(filters.plain_names) do
            table.insert(args, "--plain-name")
            table.insert(args, name)
        end
    end

    if filters.tags then
        for _, tag in ipairs(filters.tags) do
            table.insert(args, "--tags")
            table.insert(args, tag)
        end
    end

    if filters.exclude_tags then
        for _, tag in ipairs(filters.exclude_tags) do
            table.insert(args, "--exclude-tags")
            table.insert(args, tag)
        end
    end
end

local function append_targets(args, context)
    local paths = collect_test_paths(context)
    if #paths > 0 then
        for _, path in ipairs(paths) do
            table.insert(args, path)
        end
        return
    end

    table.insert(args, context.target_path)
end

local function build_test_args(context, reporter)
    local args = { "test" }

    if reporter then
        table.insert(args, "--reporter")
        table.insert(args, reporter)
    end

    append_runner_args(args, context)
    append_filters(args, context)
    append_targets(args, context)

    return args
end

local function parse_counters(counter_str)
    local passed = 0
    local skipped = 0
    local failed = 0

    for token in counter_str:gmatch("[%+%-~]%d+") do
        local sign, num = token:match("([%+~%-])(%d+)")
        num = tonumber(num) or 0
        if sign == "+" then
            passed = num
        elseif sign == "~" then
            skipped = num
        elseif sign == "-" then
            failed = num
        end
    end

    return passed, skipped, failed
end

local function full_test_name(test_id, tests_by_id)
    local parts = {}
    local current = tests_by_id[test_id]
    while current do
        table.insert(parts, 1, current.name)
        current = current.parentID and tests_by_id[current.parentID] or nil
    end
    return table.concat(parts, " ")
end

local function is_leaf_test(test_id, tests_by_id)
    for _, test in pairs(tests_by_id) do
        if test.parentID == test_id then
            return false
        end
    end
    return tests_by_id[test_id] ~= nil
end

local function serialize_test_id(suite_path, test_id, tests_by_id)
    local name = full_test_name(test_id, tests_by_id)
    if suite_path == "" or name == "" then
        return nil
    end
    return suite_path .. ": " .. name
end

local function filter_test_ids(ids, context)
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

local function add_test_id(ids, seen, suite_paths, test_id, tests_by_id)
    if not is_leaf_test(test_id, tests_by_id) then
        return
    end

    local test = tests_by_id[test_id]
    local suite_path = test and suite_paths[test.suiteID] or ""
    local id = serialize_test_id(suite_path, test_id, tests_by_id)
    if id and not seen[id] then
        seen[id] = true
        table.insert(ids, id)
    end
end

local function parse_json_test_ids(output)
    local suite_paths = {}
    local tests_by_id = {}
    local completed = {}
    local ids = {}
    local seen = {}
    local saw_test_done = false

    for line in output:gmatch("[^\r\n]+") do
        if line ~= "" then
            local ok, evt = pcall(json.decode, line)
            if ok and type(evt) == "table" and evt.type then
                if evt.type == "suite" and evt.suite then
                    suite_paths[evt.suite.id] = evt.suite.path or ""
                elseif evt.type == "testStart" and evt.test then
                    local test = evt.test
                    tests_by_id[test.id] = {
                        name = test.name or "",
                        parentID = test.parentID,
                        suiteID = test.suiteID,
                    }
                elseif evt.type == "testDone" and evt.testID then
                    saw_test_done = true
                    if not evt.hidden then
                        completed[evt.testID] = true
                    end
                end
            end
        end
    end

    if saw_test_done then
        for test_id in pairs(completed) do
            add_test_id(ids, seen, suite_paths, test_id, tests_by_id)
        end
    else
        for test_id in pairs(tests_by_id) do
            add_test_id(ids, seen, suite_paths, test_id, tests_by_id)
        end
    end

    return ids
end

function list(context)
    local output

    local list_args = { "test", "--list", "--reporter", "json" }
    append_runner_args(list_args, context)
    append_filters(list_args, context)
    append_targets(list_args, context)

    local probe = sys.run("dart", list_args, { cwd = context.target_path })
    if probe.exit_code == 0 then
        output = probe.stdout
    else
        local result = sys.run("dart", build_test_args(context, "json"), {
            cwd = context.target_path,
        })
        if result.exit_code ~= 0 then
            error("dart test list failed: " .. (result.stderr or result.stdout or "unknown error"))
        end
        output = result.stdout
    end

    return filter_test_ids(parse_json_test_ids(output), context)
end

function build_command(context)
    return {
        command = "dart",
        args = build_test_args(context, "expanded"),
        cwd = context.target_path,
    }
end

function build_coverage_run(context)
    local coverage_dir = runner_opts(context).coverage_dir or "coverage"
    local args = build_test_args(context, "expanded")
    table.insert(args, "--coverage=" .. coverage_dir)

    return {
        command = "dart",
        args = args,
        cwd = context.target_path,
        collect = {
            command = "dart",
            args = {
                "run",
                "coverage:format_coverage",
                "--lcov",
                "-i",
                coverage_dir,
                "-o",
                "coverage/lcov.info",
                "--report-on",
                coverage_dir,
            },
            cwd = context.target_path,
        },
        report = "coverage/lcov.info",
        reporter = "lcov",
    }
end

function parse_line(line)
    if line == "" then
        return nil
    end

    if last_fail_id and not line:match("^%d+:%d+") then
        return { event = "output", text = line }
    end

    local _, counters, rest = line:match("^(%d+:%d+)\s+([+%d%s~-]+):\s+(.+)$")
    if not counters then
        return nil
    end

    if rest:match("^loading ") or rest:match("^All tests passed!?$") or rest:match("^Some tests failed%.?$") then
        last_fail_id = nil
        return nil
    end

    local passed, skipped, failed = parse_counters(counters)
    local id = rest:gsub("%s%[E%]$", "")

    if failed > prev_failed then
        prev_passed = passed
        prev_skipped = skipped
        prev_failed = failed
        last_fail_id = id
        return { event = "fail", id = id, msg = rest }
    end

    if skipped > prev_skipped then
        prev_passed = passed
        prev_skipped = skipped
        prev_failed = failed
        last_fail_id = nil
        return { event = "skip", id = id }
    end

    if passed > prev_passed then
        prev_passed = passed
        prev_skipped = skipped
        prev_failed = failed
        last_fail_id = nil
        return { event = "pass", id = id }
    end

    last_fail_id = nil
    return { event = "start", id = id }
end
