local DEFAULT_INCLUDE = {
  "**/spec/**/*_spec.cr",
  "**/spec/**",
}

local function runner_opts(context)
  return context.runner or {}
end

local function include_patterns(context)
  local runner = runner_opts(context)
  if runner.include then
    return runner.include
  end
  return DEFAULT_INCLUDE
end

local function excluded(context, path)
  local runner = runner_opts(context)
  if not runner.exclude then
    return false
  end
  for _, pattern in ipairs(runner.exclude) do
    if filter.glob_match(path, pattern) then
      return true
    end
  end
  return false
end

local function append_runner_args(args, context)
  local runner = runner_opts(context)
  if runner.args then
    for _, arg in ipairs(runner.args) do
      table.insert(args, arg)
    end
  end
  if runner.pattern and runner.pattern ~= "" then
    table.insert(args, "-e")
    table.insert(args, runner.pattern)
  end
end

local function spec_targets(context)
  local targets = {}
  local seen = {}
  local root = context.target_path

  for _, pattern in ipairs(include_patterns(context)) do
    for _, path in ipairs(fs.glob(root, pattern)) do
      if not excluded(context, path) and not seen[path] then
        seen[path] = true
        table.insert(targets, path)
      end
    end
  end

  table.sort(targets)
  return targets
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

local function parse_dry_run_output(output)
  local tests = {}
  local seen = {}

  for line in output:gmatch("[^\r\n]+") do
    local desc = line:match("^%s+(.+)$")
    if desc and desc ~= "" and not desc:match("^%d+%)") then
      if not seen[desc] then
        seen[desc] = true
        table.insert(tests, desc)
      end
    end
  end

  return tests
end

local function list_from_discovery(context)
  return apply_filters(spec_targets(context), context)
end

function list(context)
  local args = { "spec", "--dry-run" }
  append_runner_args(args, context)

  local targets = spec_targets(context)
  if #targets > 0 then
    for _, target in ipairs(targets) do
      table.insert(args, target)
    end
  else
    table.insert(args, ".")
  end

  local result = sys.run("crystal", args, { cwd = context.target_path })
  if result.exit_code == 0 and result.stdout ~= "" then
    local tests = parse_dry_run_output(result.stdout)
    if #tests > 0 then
      return apply_filters(tests, context)
    end
  end

  return list_from_discovery(context)
end

local function build_spec_args(context, extra)
  local runner = runner_opts(context)
  local args = { "spec" }

  local format = runner.format
  if format and format ~= "" then
    table.insert(args, "--format")
    table.insert(args, format)
  end

  if runner.verbose ~= false then
    table.insert(args, "--verbose")
  end

  if extra then
    for _, arg in ipairs(extra) do
      table.insert(args, arg)
    end
  end

  append_runner_args(args, context)

  local targets = spec_targets(context)
  if #targets > 0 then
    for _, target in ipairs(targets) do
      table.insert(args, target)
    end
  else
    table.insert(args, ".")
  end

  return args
end

function build_command(context)
  return {
    command = "crystal",
    args = build_spec_args(context),
    cwd = context.target_path,
  }
end

function build_coverage_run(context)
  local runner = runner_opts(context)
  local coverage = runner.coverage
  local extra = {}

  if coverage == false then
    -- no gcov flag
  elseif type(coverage) == "table" and coverage.gcov == false then
    -- explicit opt-out
  else
    table.insert(extra, "--gcov")
  end

  if type(coverage) == "table" and coverage.args then
    for _, arg in ipairs(coverage.args) do
      table.insert(extra, arg)
    end
  end

  local spec = {
    command = "crystal",
    args = build_spec_args(context, extra),
    cwd = context.target_path,
  }

  if type(coverage) == "table" then
    if coverage.report then
      spec.report = coverage.report
    end
    if coverage.output then
      spec.output = coverage.output
    end
    if coverage.reporter then
      spec.reporter = coverage.reporter
    end
    if coverage.min_line_rate then
      spec.min_line_rate = coverage.min_line_rate
    end
    if coverage.collect then
      spec.collect = coverage.collect
    end
  end

  return spec
end

local failure_context = {
  active = false,
  id = nil,
}

local function reset_failure_context()
  failure_context.active = false
  failure_context.id = nil
end

function parse_line(line)
  if line == "" then
    return nil
  end

  -- TAP format (optional via runners.crystal.format = "tap")
  local tap_pass, _, tap_id = line:match("^ok%s+(%d+)%s+%-%s+(.+)$")
  if tap_pass then
    reset_failure_context()
    return { event = "pass", id = tap_id }
  end

  local tap_fail, _, tap_fail_id = line:match("^not ok%s+(%d+)%s+%-%s+(.+)$")
  if tap_fail then
    reset_failure_context()
    failure_context.active = true
    failure_context.id = tap_fail_id
    return { event = "fail", id = tap_fail_id, msg = tap_fail_id }
  end

  if line:match("^#") then
    if failure_context.active and failure_context.id then
      return { event = "output", text = line }
    end
    return nil
  end

  -- Failure summary: "  1) Group example name"
  local full_desc = line:match("^%s*%d+%)%s+(.+)$")
  if full_desc then
    failure_context.active = true
    failure_context.id = full_desc
    return { event = "fail", id = full_desc, msg = full_desc }
  end

  if failure_context.active and line:match("^%s+") then
    return { event = "output", text = line }
  end
  reset_failure_context()

  -- Pending examples
  if line:match("^%s*%*%s+") or line:match("^%s*PENDING:?") then
    local pending = line:match("^%s*%*%s+(.+)$") or line:match("^%s*PENDING:?%s*(.+)$")
    if pending and pending ~= "" then
      return { event = "skip", id = pending }
    end
  end

  -- Documentation-format example lines (indented descriptions).
  local indent, desc = line:match("^(%s+)([^%s].*)$")
  if indent and desc and #indent >= 4 then
    return { event = "pass", id = desc }
  end

  -- Progress format without ids.
  if line == "." then
    return nil
  end
  if line == "F" or line == "E" then
    return { event = "fail", id = "crystal spec", msg = "example failed" }
  end
  if line == "*" then
    return { event = "skip", id = "crystal spec" }
  end

  if line:match("^%d+ examples,") or line:match("^Finished in ") then
    return nil
  end

  return { event = "output", text = line }
end
