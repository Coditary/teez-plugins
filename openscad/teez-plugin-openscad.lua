local DEFAULT_INCLUDE = { "**/tests/**", "**/*_test.scad" }

local function runner_config(context)
  return context.runner or {}
end

local function include_patterns(context)
  local runner = runner_config(context)
  if runner.include then
    return runner.include
  end
  return DEFAULT_INCLUDE
end

local function exclude_patterns(context)
  local runner = runner_config(context)
  return runner.exclude or {}
end

local function path_matches_any(path, patterns)
  for _, pattern in ipairs(patterns) do
    if filter.glob_match(path, pattern) then
      return true
    end
  end
  return false
end

local function is_scad_test(path, context)
  if not path:match("%.scad$") then
    return false
  end
  if not path_matches_any(path, include_patterns(context)) then
    return false
  end
  if path_matches_any(path, exclude_patterns(context)) then
    return false
  end
  return true
end

local function collect_tests(context)
  local tests = {}
  local seen = {}

  for _, path in ipairs(fs.glob(context.target_path, "**/*.scad")) do
    if is_scad_test(path, context) and not seen[path] then
      seen[path] = true
      table.insert(tests, path)
    end
  end

  table.sort(tests)
  return tests
end

local function apply_filters(tests, filters)
  if not filters then
    return tests
  end

  local filtered = {}
  for _, id in ipairs(tests) do
    if filter.matches({ id = id }, filters) then
      table.insert(filtered, id)
    end
  end
  return filtered
end

local function resolve_tests(context)
  if context.target_path:match("%.scad$") and is_scad_test(context.target_path, context) then
    return { context.target_path }
  end

  return apply_filters(collect_tests(context), context.filters)
end

local function append_runner_args(args, runner)
  if runner.args then
    for _, arg in ipairs(runner.args) do
      table.insert(args, arg)
    end
  end
  return args
end

function list(context)
  return resolve_tests(context)
end

function build_command(context)
  local runner = runner_config(context)
  local tests = resolve_tests(context)

  if runner.command then
    local args = append_runner_args({}, runner)
    if runner.append_target ~= false then
      table.insert(args, context.target_path)
    end

    return {
      command = runner.command,
      args = args,
      cwd = runner.cwd or context.target_path,
      env = runner.env,
    }
  end

  if #tests == 0 then
    error("no OpenSCAD test files found")
  end

  if #tests == 1 then
    return {
      command = "openscad",
      args = { "-o", "/dev/null", tests[1] },
      cwd = runner.cwd or context.target_path,
      env = runner.env,
    }
  end

  local parts = {}
  for _, test_file in ipairs(tests) do
    table.insert(
      parts,
      string.format(
        'openscad -o /dev/null %q && echo "PASS %s" || echo "FAIL %s"',
        test_file,
        test_file,
        test_file
      )
    )
  end

  return {
    command = "bash",
    args = { "-c", table.concat(parts, "; ") },
    cwd = runner.cwd or context.target_path,
    env = runner.env,
  }
end

function parse_line(line)
  local pass_id = line:match("^PASS:?%s+(.+)$")
  if pass_id then
    return { event = "pass", id = pass_id }
  end

  local fail_id, msg = line:match("^FAIL:?%s+([^%-]+)%-%s*(.+)$")
  if fail_id then
    return { event = "fail", id = fail_id:match("^%s*(.-)%s*$"), msg = msg }
  end

  fail_id = line:match("^FAIL:?%s+(.+)$")
  if fail_id then
    return { event = "fail", id = fail_id, msg = line }
  end

  if line:match("[Ee]rror") or line:match("Parser error") then
    return { event = "fail", id = "openscad", msg = line }
  end

  return { event = "output", text = line }
end
