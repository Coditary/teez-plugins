local DEFAULT_INCLUDE = {
    "**/tests/**",
    "**/*_test.tcl",
    "**/all.tcl",
}

local DEFAULT_EXCLUDE = {
    "**/pkgIndex.tcl",
}

local function runner_opts(context)
    return context.runner or {}
end

local function shell_command(context)
    local runner = runner_opts(context)
    if runner.shell then
        return runner.shell
    end
    if runner.use_wish then
        return "wish"
    end
    return "tclsh"
end

local function include_patterns(context)
    local runner = runner_opts(context)
    if runner.include then
        return runner.include
    end
    return DEFAULT_INCLUDE
end

local function exclude_patterns(context)
    local runner = runner_opts(context)
    if runner.exclude then
        return runner.exclude
    end
    return DEFAULT_EXCLUDE
end

local function is_excluded(path, patterns)
    for _, pattern in ipairs(patterns) do
        if filter.glob_match(path, pattern) then
            return true
        end
    end
    return false
end

local function rel_path(target_path, abs_path)
    local prefix = target_path:gsub("/+$", "") .. "/"
    if abs_path:sub(1, #prefix) == prefix then
        return abs_path:sub(#prefix + 1)
    end
    return abs_path
end

local function collect_candidates(context)
    local target_path = context.target_path
    local include = include_patterns(context)
    local exclude = exclude_patterns(context)
    local seen = {}
    local candidates = {}

    local function add(path)
        if seen[path] or is_excluded(path, exclude) then
            return
        end
        if not path:match("%.tcl$") then
            return
        end
        seen[path] = true
        table.insert(candidates, path)
    end

    for _, pattern in ipairs(include) do
        if pattern:match("%.tcl$") then
            for _, path in ipairs(fs.glob(target_path, pattern)) do
                add(path)
            end
        else
            for _, path in ipairs(fs.glob(target_path, pattern .. "/**/*.tcl")) do
                add(path)
            end
            for _, path in ipairs(fs.glob(target_path, pattern .. "/*.tcl")) do
                add(path)
            end
        end
    end

    table.sort(candidates)
    return candidates
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

local function find_all_tcl(candidates, target_path)
    local all_entries = {}
    for _, path in ipairs(candidates) do
        local rel = rel_path(target_path, path)
        if rel == "all.tcl" or rel:match("/all%.tcl$") then
            table.insert(all_entries, path)
        end
    end
    return all_entries
end

local function list_test_files(context)
    local candidates = collect_candidates(context)
    local target_path = context.target_path
    local all_tcl = find_all_tcl(candidates, target_path)

    local ids = {}
    if #all_tcl > 0 then
        for _, path in ipairs(all_tcl) do
            table.insert(ids, rel_path(target_path, path))
        end
    else
        for _, path in ipairs(candidates) do
            local rel = rel_path(target_path, path)
            if not rel:match("/all%.tcl$") and rel ~= "all.tcl" then
                table.insert(ids, rel)
            end
        end
    end

    return filter_ids(ids, context)
end

local function shell_quote(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function build_inline_script(files)
    local lines = {
        "package require tcltest",
        "namespace import -force ::tcltest::*",
        "configure -verbose {body error}",
    }

    for _, file in ipairs(files) do
        table.insert(lines, "source " .. shell_quote(file))
    end

    return table.concat(lines, "; ")
end

local function rels_to_abs(target_path, rels)
    local abs = {}
    for _, rel in ipairs(rels) do
        table.insert(abs, target_path .. "/" .. rel)
    end
    return abs
end

local function resolve_run_targets(context)
    local target_path = context.target_path
    local candidates = collect_candidates(context)
    local all_tcl = find_all_tcl(candidates, target_path)

    if #all_tcl > 0 then
        local rels = {}
        for _, path in ipairs(all_tcl) do
            table.insert(rels, rel_path(target_path, path))
        end
        rels = filter_ids(rels, context)
        if #rels == 1 then
            return { mode = "file", path = target_path .. "/" .. rels[1] }
        end
        if #rels > 1 then
            return { mode = "inline", files = rels_to_abs(target_path, rels) }
        end
    end

    local rels = {}
    for _, path in ipairs(candidates) do
        local rel = rel_path(target_path, path)
        if rel ~= "all.tcl" and not rel:match("/all%.tcl$") then
            table.insert(rels, rel)
        end
    end
    rels = filter_ids(rels, context)

    if #rels == 1 then
        return { mode = "file", path = target_path .. "/" .. rels[1] }
    end
    if #rels > 1 then
        return { mode = "inline", files = rels_to_abs(target_path, rels) }
    end

    error("no Tcl test files found under " .. target_path)
end

function list(context)
    return list_test_files(context)
end

function build_command(context)
    local runner = runner_opts(context)
    local shell = shell_command(context)
    local target = resolve_run_targets(context)
    local args = {}
    if runner.args then
        for _, arg in ipairs(runner.args) do
            table.insert(args, arg)
        end
    end

    if target.mode == "file" then
        table.insert(args, target.path)
    else
        table.insert(args, "-c")
        table.insert(args, build_inline_script(target.files))
    end

    local spec = {
        command = shell,
        args = args,
        cwd = runner.cwd or context.target_path,
    }

    if context.filters then
        spec.env = {
            TEEZ_FILTERS = json.encode(context.filters),
        }
    end

    return spec
end

function parse_line(line)
    local name, status = line:match("^====%s+(%S+)%s+.*(PASSED|FAILED|SKIPPED)%s*$")
    if name and status == "PASSED" then
        return { event = "pass", id = name }
    end
    if name and status == "FAILED" then
        return { event = "fail", id = name, msg = line }
    end
    if name and status == "SKIPPED" then
        return { event = "skip", id = name }
    end

    if line:match("^----%s+") then
        return { event = "output", text = line }
    end

    return nil
end

function build_coverage_run(context)
    local runner = runner_opts(context)
    local coverage = runner.coverage
    if not coverage then
        return nil
    end

    local run = build_command(context)
    local tool = coverage.tool or "ncover"
    local output = coverage.output or "coverage/ncover.dat"
    local report = coverage.report or "coverage/lcov.info"
    local reporter = coverage.reporter or "lcov"
    local min_line_rate = coverage.min_line_rate

    local args = { "run", "--output", output }
    if coverage.args then
        for _, arg in ipairs(coverage.args) do
            table.insert(args, arg)
        end
    end
    table.insert(args, run.command)
    for _, arg in ipairs(run.args) do
        table.insert(args, arg)
    end

    local spec = {
        command = tool,
        args = args,
        cwd = run.cwd,
        env = run.env,
        collect = {
            command = tool,
            args = { "report", "--input", output, "--format", "lcov", "--output", report },
        },
        report = report,
        reporter = reporter,
        output = coverage.teez_output or "coverage/teez.msgpack",
    }

    if min_line_rate then
        spec.min_line_rate = min_line_rate
    end

    return spec
end
