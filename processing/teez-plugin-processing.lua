local DEFAULT_INCLUDE = { "**/test/**", "**/*Test*.pde" }

local function runner_options(context)
  return context.runner or {}
end

local function merged_include(context)
  local runner = runner_options(context)
  if runner.include and #runner.include > 0 then
    return runner.include
  end
  return DEFAULT_INCLUDE
end

local function merged_exclude(context)
  local runner = runner_options(context)
  return runner.exclude or {}
end

local function path_is_excluded(path, excludes)
  for _, pattern in ipairs(excludes) do
    if filter.glob_match(path, pattern) then
      return true
    end
  end
  return false
end

local function sketch_name_from_pde(pde_path)
  local filename = pde_path:match("([^/]+)$")
  if not filename then
    return nil
  end
  return filename:match("^(.+)%.pde$")
end

local function is_main_sketch_pde(pde_path)
  local sketch_name = sketch_name_from_pde(pde_path)
  if not sketch_name then
    return false
  end
  local parent = pde_path:match("^(.+)/[^/]+$")
  if not parent then
    return false
  end
  local parent_name = parent:match("([^/]+)$")
  return sketch_name == parent_name
end

local function relative_to(root, abs_path)
  if abs_path:sub(1, #root) == root then
    local rel = abs_path:sub(#root + 1)
    return rel:gsub("^/", "")
  end
  return abs_path
end

local function sketch_dir_from_pde(root, pde_path)
  local parent = pde_path:match("^(.+)/[^/]+$")
  if not parent then
    return nil
  end
  return relative_to(root, parent)
end

local function discover_test_sketches(context)
  local root = context.target_path
  local includes = merged_include(context)
  local excludes = merged_exclude(context)
  local seen = {}
  local tests = {}

  for _, pattern in ipairs(includes) do
    local glob_pattern = pattern
    if not glob_pattern:match("%.pde$") then
      glob_pattern = pattern:gsub("/?$", "") .. "/**/*.pde"
    end

    for _, pde_path in ipairs(fs.glob(root, glob_pattern)) do
      if is_main_sketch_pde(pde_path) then
        local sketch_dir = sketch_dir_from_pde(root, pde_path)
        if sketch_dir and sketch_dir ~= "" and not seen[sketch_dir] then
          if not path_is_excluded(sketch_dir, excludes) and not path_is_excluded(pde_path, excludes) then
            seen[sketch_dir] = true
            table.insert(tests, sketch_dir)
          end
        end
      end
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

local function join_path(base, path)
  if path:sub(1, 1) == "/" then
    return path
  end
  return base:gsub("/$", "") .. "/" .. path
end

local function resolve_run_target(context, tests)
  local root = context.target_path
  local runner = runner_options(context)

  if runner.sketch then
    return join_path(root, runner.sketch)
  end

  if #tests == 1 then
    return join_path(root, tests[1])
  end

  return root
end

local function append_runner_args(args, runner)
  if runner.args then
    for _, arg in ipairs(runner.args) do
      table.insert(args, arg)
    end
  end
end

function list(context)
  local tests = discover_test_sketches(context)
  return apply_filters(tests, context.filters)
end

function build_command(context)
  local root = context.target_path
  local runner = runner_options(context)
  local mode = runner.mode or "processing-java"
  local tests = apply_filters(discover_test_sketches(context), context.filters)

  if mode == "ant" then
    local args = { "junit" }
    append_runner_args(args, runner)
    return {
      command = "ant",
      args = args,
      cwd = runner.cwd or root,
    }
  end

  local args = { "--run-tests" }
  append_runner_args(args, runner)
  table.insert(args, resolve_run_target(context, tests))

  return {
    command = "processing-java",
    args = args,
    cwd = runner.cwd or root,
  }
end

function build_coverage_run(context)
  local runner = runner_options(context)
  if not runner.coverage then
    return nil
  end

  local root = context.target_path
  local mode = runner.mode or "processing-java"
  local cov = runner.coverage
  local tests = apply_filters(discover_test_sketches(context), context.filters)

  if mode == "ant" then
    local target = cov.ant_target or "coverage"
    local args = { target }
    if cov.args then
      for _, arg in ipairs(cov.args) do
        table.insert(args, arg)
      end
    end
    append_runner_args(args, runner)

    return {
      command = "ant",
      args = args,
      cwd = cov.cwd or runner.cwd or root,
      collect = cov.collect,
      report = cov.report or "coverage/report.xml",
      reporter = cov.reporter or "cobertura",
      output = cov.output or "coverage/teez.msgpack",
      min_line_rate = cov.min_line_rate,
    }
  end

  local args = { "--run-tests" }
  if cov.args then
    for _, arg in ipairs(cov.args) do
      table.insert(args, arg)
    end
  end
  append_runner_args(args, runner)
  table.insert(args, resolve_run_target(context, tests))

  return {
    command = "processing-java",
    args = args,
    cwd = cov.cwd or runner.cwd or root,
    collect = cov.collect,
    report = cov.report,
    reporter = cov.reporter or "cobertura",
    output = cov.output or "coverage/teez.msgpack",
    min_line_rate = cov.min_line_rate,
  }
end

function parse_line(line)
  if line == "" then
    return nil
  end

  local junit_running = line:match("%[junit%] Running%s+(.+)")
  if junit_running then
    return { event = "start", id = junit_running }
  end

  local junit_failed = line:match("%[junit%] TEST%s+(.-)%s+FAILED")
  if junit_failed then
    return { event = "fail", id = junit_failed, msg = line }
  end

  local class, name = line:match("^%s*(%S+)%s+>%s+(%S+)%s+PASSED")
  if class and name then
    return { event = "pass", id = class .. "." .. name }
  end

  class, name = line:match("^%s*(%S+)%s+>%s+(%S+)%s+FAILED")
  if class and name then
    return { event = "fail", id = class .. "." .. name, msg = line }
  end

  local pass_id, duration_ms = line:match("^PASS%s+(%S+)%s*%((%d+)ms%)")
  if pass_id then
    return { event = "pass", id = pass_id, duration_ms = tonumber(duration_ms) }
  end

  pass_id = line:match("^PASS%s+(%S+)")
  if pass_id then
    return { event = "pass", id = pass_id }
  end

  local fail_id, fail_msg = line:match("^FAIL%s+(%S+)%s*(.*)$")
  if fail_id then
    return {
      event = "fail",
      id = fail_id,
      msg = fail_msg ~= "" and fail_msg or line,
    }
  end

  if line:match("Tests run:%s+%d+") then
    return { event = "output", text = line }
  end

  if line:match("OK %(%d+ tests%)") or line:match("FAILURES!!!") then
    return { event = "output", text = line }
  end

  return { event = "output", text = line }
end
