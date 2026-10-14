-- teez clojure.test adapter

local parse_context = {
    namespace = nil,
}

local LIST_EVAL = table.concat({
    "(require '[clojure.java.classpath :as cp]",
    "'[clojure.test :as t]",
    "'[clojure.string :as str])",
    "(doseq [path (cp/classpath-directories)]",
    "  (doseq [^java.io.File f (file-seq (clojure.java.io/file path))",
    "          :when (and (.isFile f)",
    "                    (re-find #\"_test\\.clj[c]?$\" (.getName f)))]",
    "    (try (load-file (.getPath f)) (catch Throwable _))))",
    "(doseq [ns-sym (sort (map ns-name (filter #(str/ends-with? (name (ns-name %)) \"-test\") (all-ns))))",
    "  :when-let [ns-obj (find-ns ns-sym)]",
    "  (doseq [v (t/test-ns-vars ns-obj)]",
    "    (println (str ns-sym \"/\" (str (:name (meta v)))))))",
}, " ")

local function trim(value)
    return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function target_path(context)
    return context.target_path or "."
end

local function runner_cfg(context)
    if type(context.runner) == "table" then
        return context.runner
    end
    return {}
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

local function default_include_patterns()
    return {
        "**/test/**",
        "**/*_test.clj",
        "**/*_test.cljc",
    }
end

local function include_patterns(context)
    local cfg = runner_cfg(context)
    if cfg.include then
        return cfg.include
    end
    return default_include_patterns()
end

local function exclude_patterns(context)
    local cfg = runner_cfg(context)
    return cfg.exclude
end

local function runner_targets(context)
    local target = target_path(context)
    local paths = {}
    local seen = {}

    for _, pattern in ipairs(include_patterns(context)) do
        for _, file in ipairs(fs.glob(target, pattern)) do
            local resolved = resolve_glob_hit(target, file)
            local excluded = false
            local excludes = exclude_patterns(context)
            if excludes then
                for _, exclude_pattern in ipairs(excludes) do
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
    return normalized_path:match("([^/]+%.clj[c]?)$") or normalized_path
end

local function clojure_command(context)
    local cfg = runner_cfg(context)
    if cfg.command then
        return cfg.command
    end
    return "clojure"
end

local function test_alias(context)
    local cfg = runner_cfg(context)
    return cfg.alias or "test"
end

local function test_mode(context)
    local cfg = runner_cfg(context)
    local mode = cfg.mode or "M"
    if mode == "X" or mode == "x" then
        return "X"
    end
    return "M"
end

local function uses_kaocha(context)
    local cfg = runner_cfg(context)
    return cfg.tool == "kaocha"
end

local function kaocha_command(context)
    local cfg = runner_cfg(context)
    return cfg.kaocha_command or "kaocha"
end

local function append_kaocha_runner_args(args, context)
    local cfg = runner_cfg(context)
    if cfg.pattern then
        table.insert(args, "--focus")
        table.insert(args, cfg.pattern)
    end

    if cfg.args then
        for _, arg in ipairs(cfg.args) do
            table.insert(args, arg)
        end
    end
end

local function append_runner_args(args, context)
    if uses_kaocha(context) then
        return
    end

    local cfg = runner_cfg(context)
    if cfg.args then
        for _, arg in ipairs(cfg.args) do
            table.insert(args, arg)
        end
    end
end

local function append_alias_prefix(args, context)
    local alias = test_alias(context)
    local mode = test_mode(context)
    table.insert(args, "-" .. mode .. ":" .. alias)
end

local function build_clojure_args(context, extra)
    local args = {}
    append_alias_prefix(args, context)
    if extra then
        for _, token in ipairs(extra) do
            table.insert(args, token)
        end
    end
    append_runner_args(args, context)
    return args
end

local function append_kaocha_separator(args, context)
    if uses_kaocha(context) and #args > 0 then
        table.insert(args, "--")
    end
end

local function build_kaocha_args(context, extra)
    local args = {}
    if extra then
        for _, token in ipairs(extra) do
            table.insert(args, token)
        end
    end
    append_kaocha_runner_args(args, context)
    return args
end

local function join_titles(parts)
    return table.concat(parts, " > ")
end

local function make_namespace_test_id(namespace, var_name)
    return namespace .. "/" .. var_name
end

local function collect_tests_from_output(output)
    local tests = {}
    local seen = {}

    for line in output:gmatch("[^\r\n]+") do
        line = trim(line)
        if line ~= "" and not line:match("^WARNING:") and not line:match("^Options:") then
            local ns, var = line:match("^(%S+)%s+(%S+)$")
            if ns and var and not line:match("/") then
                line = ns .. "/" .. var
            end

            if line:match("/") or line:match("_test%.clj[c]?$") or line:match("%.clj[c]?$") then
                if not seen[line] then
                    seen[line] = true
                    table.insert(tests, line)
                end
            end
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

local function collect_tests_with_kaocha(context)
    local args = build_clojure_args(context, nil)
    append_kaocha_separator(args, context)
    table.insert(args, "--list")

    local output = sys.exec(clojure_command(context), args, { cwd = target_path(context) })
    local tests = collect_tests_from_output(output)
    if #tests > 0 then
        return tests
    end

    args = build_kaocha_args(context, { "--list" })
    output = sys.exec(kaocha_command(context), args, { cwd = target_path(context) })
    return collect_tests_from_output(output)
end

local function collect_tests_with_eval(context)
    local args = build_clojure_args(context, { "-e", LIST_EVAL })
    local output = sys.exec(clojure_command(context), args, { cwd = target_path(context) })
    return collect_tests_from_output(output)
end

local function collect_tests_from_files(context)
    local tests = {}
    local root = target_path(context)
    for _, target in ipairs(runner_targets(context)) do
        table.insert(tests, relative_test_path(root, target))
    end
    table.sort(tests)
    return tests
end

local function collect_tests(context)
    local tests = {}

    if uses_kaocha(context) then
        tests = collect_tests_with_kaocha(context)
    else
        tests = collect_tests_with_eval(context)
    end

    if #tests == 0 then
        tests = collect_tests_from_files(context)
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

local function coverage_cfg(context)
    local cfg = runner_cfg(context)
    local from_runner = type(cfg.coverage) == "table" and cfg.coverage or {}
    local from_global = type(config) == "table" and type(config.coverage) == "table" and config.coverage
        or {}
    return shallow_merge(from_global, from_runner)
end

local function default_coverage_cfg(_context)
    return {
        alias = "coverage",
        reports_directory = "target/coverage",
        report = "target/coverage/lcov.info",
        output = "coverage/teez.msgpack",
        reporter = "msgpack",
    }
end

local function effective_coverage_cfg(context)
    return shallow_merge(default_coverage_cfg(context), coverage_cfg(context))
end

local function looks_like_test_id(id)
    if id:match("/") then
        return true
    end
    return id:match("_test%.clj[c]?$") ~= nil or id:match("%.clj[c]?$") ~= nil
end

local function with_duration(event, duration_ms)
    if duration_ms ~= nil then
        event.duration_ms = duration_ms
    end
    return event
end

local function build_test_id(namespace, var_name, file_hint)
    if namespace and var_name then
        return make_namespace_test_id(namespace, var_name)
    end
    if parse_context.namespace and var_name then
        return make_namespace_test_id(parse_context.namespace, var_name)
    end
    if file_hint and var_name then
        return join_titles({ file_hint, var_name })
    end
    return var_name
end

local function should_ignore_line(line)
    if line:match("^Ran %d+ tests") then
        return true
    end
    if line:match("^%d+ tests?, %d+ assertions?") then
        return true
    end
    if line:match("^%d+ failures?, %d+ errors?") then
        return true
    end
    if line:match("^%s*expected:") or line:match("^%s*actual:") then
        return true
    end
    if line:match("^%s*at ") or line:match("^%s*Caused by:") then
        return true
    end
    if line:match("^%[%s*[%P%.F]+") then
        return true
    end
    if line:match("^Loading ") or line:match("^SLF4J:") then
        return true
    end
    return false
end

local function parse_testing_header(line)
    return line:match("^Testing%s+(%S+)$")
end

local function parse_result_in_line(line)
    local event, var_name, file_hint = line:match("^(FAIL|ERROR|PASS) in %(([^)]+)%) %(([^)]+):%d+%)$")
    if event and var_name then
        return event, var_name, file_hint
    end

    event, var_name = line:match("^(FAIL|ERROR|PASS) in %(([^)]+)%)$")
    if event and var_name then
        return event, var_name, nil
    end

    return nil, nil, nil
end

local function parse_kaocha_result_line(line)
    local ns, var, status = line:match("^(%S+)%s+(%S+)%s+(PASS|FAIL|ERROR|SKIP)$")
    if ns and var and status then
        return status, var, ns
    end

    local var_name, status = line:match("^%s+(%S+)%s+(PASS|FAIL|ERROR|SKIP)$")
    if var_name and status and parse_context.namespace then
        return status, var_name, parse_context.namespace
    end

    return nil, nil, nil
end

local function parse_namespace_var_line(line)
    return line:match("^(%S+/%S+)$")
end

function prefetch_starts()
    return false
end

function list(context)
    return collect_tests(context)
end

function build_command(context)
    parse_context.namespace = nil

    if uses_kaocha(context) then
        local cfg = runner_cfg(context)
        if cfg.kaocha_direct then
            return {
                command = kaocha_command(context),
                args = build_kaocha_args(context, nil),
                cwd = target_path(context),
            }
        end
    end

    local args = build_clojure_args(context, nil)
    if uses_kaocha(context) then
        append_kaocha_separator(args, context)
        append_kaocha_runner_args(args, context)
    end

    return {
        command = clojure_command(context),
        args = args,
        cwd = target_path(context),
    }
end

function build_list_command(context)
    if uses_kaocha(context) then
        local args = build_clojure_args(context, nil)
        append_kaocha_separator(args, context)
        table.insert(args, "--list")
        return {
            command = clojure_command(context),
            args = args,
            cwd = target_path(context),
        }
    end

    return {
        command = clojure_command(context),
        args = build_clojure_args(context, { "-e", LIST_EVAL }),
        cwd = target_path(context),
    }
end

function build_coverage_run(context)
    local cov = effective_coverage_cfg(context)
    if cov.tool ~= "cloverage" then
        return nil
    end

    parse_context.namespace = nil

    local target = target_path(context)
    local alias = cov.alias or "coverage"
    local reports_directory = cov.reports_directory or "target/coverage"
    local report = cov.report or fs.join(reports_directory, "lcov.info")
    local args = {
        "-M:" .. alias,
        "--lcov",
        "--output",
        reports_directory,
    }

    if cov.args then
        for _, arg in ipairs(cov.args) do
            table.insert(args, arg)
        end
    end

    return {
        command = clojure_command(context),
        args = args,
        cwd = target,
        report = report,
        reporter = cov.reporter or "msgpack",
        output = cov.output or "coverage/teez.msgpack",
        min_line_rate = cov.min_line_rate,
    }
end

function parse_line(line)
    line = trim(line:gsub("%c%[[%d;]*m", ""))
    if line == "" or should_ignore_line(line) then
        return nil
    end

    local testing_ns = parse_testing_header(line)
    if testing_ns then
        parse_context.namespace = testing_ns
        return { event = "start", id = testing_ns }
    end

    local event, var_name, file_hint = parse_result_in_line(line)
    if event and var_name then
        local id = build_test_id(parse_context.namespace, var_name, file_hint)
        if not looks_like_test_id(id) then
            return nil
        end
        if event == "PASS" then
            return { event = "pass", id = id }
        end
        return { event = "fail", id = id, msg = event .. " in (" .. var_name .. ")" }
    end

    event, var_name, file_hint = parse_kaocha_result_line(line)
    if event and var_name then
        if file_hint then
            parse_context.namespace = file_hint
        end
        local id = build_test_id(parse_context.namespace, var_name, file_hint)
        if not looks_like_test_id(id) then
            return nil
        end
        if event == "PASS" then
            return { event = "pass", id = id }
        end
        if event == "SKIP" then
            return { event = "skip", id = id }
        end
        return { event = "fail", id = id, msg = event }
    end

    local ns_var = parse_namespace_var_line(line)
    if ns_var then
        return { event = "start", id = ns_var }
    end

    return { event = "output", text = line }
end
