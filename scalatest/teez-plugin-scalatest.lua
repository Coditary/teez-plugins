-- teez ScalaTest adapter (sbt)

local parse_state = {
  suite = nil,
}

local function trim(value)
  return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function runner_cfg(context)
  if type(context.runner) == "table" then
    return context.runner
  end
  return {}
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

local function target_path(context)
  return context.target_path or "."
end

local function path_join(base, child)
  if base:sub(-1) == "/" then
    return base .. child
  end
  return base .. "/" .. child
end

local function append_runner_args(args, context)
  local cfg = runner_cfg(context)
  if not cfg.args then
    return
  end
  for _, arg in ipairs(cfg.args) do
    table.insert(args, arg)
  end
end

local function base_sbt_args()
  return { "-batch", "-Dsbt.supershell=false", "-Dsbt.log.noformat=true" }
end

local function test_task_for_project(project)
  if not project or project == "" then
    return "test"
  end
  project = project:gsub("^/", "")
  return project .. "/test"
end

local function runner_pattern(context)
  local cfg = runner_cfg(context)
  if cfg.pattern and cfg.pattern ~= "" then
    return cfg.pattern
  end
  return nil
end

local function filters_pattern(context)
  if type(context.filters) ~= "table" then
    return nil
  end

  if type(context.filters.name) == "string" and context.filters.name ~= "" then
    return context.filters.name
  end

  if type(context.filters.pattern) == "string" and context.filters.pattern ~= "" then
    return context.filters.pattern
  end

  return nil
end

local function effective_name_pattern(context)
  return runner_pattern(context) or filters_pattern(context)
end

local function collect_suite_targets(context)
  local targets = {}
  local cfg = runner_cfg(context)

  if cfg.suites then
    if type(cfg.suites) == "string" then
      table.insert(targets, cfg.suites)
    else
      for _, suite in ipairs(cfg.suites) do
        table.insert(targets, suite)
      end
    end
  end

  if cfg.tests then
    if type(cfg.tests) == "string" then
      table.insert(targets, cfg.tests)
    else
      for _, suite in ipairs(cfg.tests) do
        table.insert(targets, suite)
      end
    end
  end

  if context.filters and context.filters.names then
    for _, name in ipairs(context.filters.names) do
      table.insert(targets, name)
    end
  end

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

local function normalize_test_id(suite, test_name)
  suite = trim(suite)
  test_name = trim(test_name or "")

  if suite == "" then
    return nil
  end

  if test_name ~= "" then
    return suite .. "::" .. test_name
  end

  return suite
end

local function insert_unique(tests, seen, id)
  id = trim(id)
  if id == "" or seen[id] then
    return
  end
  seen[id] = true
  table.insert(tests, id)
end

local function is_test_source(path)
  local normalized = path:gsub("\\", "/")
  if not normalized:match("/src/test/") then
    return false
  end
  if not normalized:match("%.scala$") then
    return false
  end

  local basename = normalized:match("([^/]+)$") or ""
  return basename:match("Spec%.scala$")
    or basename:match("Test%.scala$")
    or basename:match("Tests%.scala$")
    or basename:match("Suite%.scala$")
end

local function path_to_suite_id(path)
  local normalized = path:gsub("\\", "/")
  local relative = normalized:match("src/test/scala/(.+)%.scala$")
    or normalized:match("src/test/(.+)%.scala$")
  if not relative then
    return nil
  end
  return relative:gsub("/", ".")
end

local function include_patterns(context)
  local cfg = runner_cfg(context)
  if type(cfg.include) == "table" and #cfg.include > 0 then
    return cfg.include
  end
  return { "**/src/test/**/*.scala" }
end

local function excluded_by_runner(path, context)
  local cfg = runner_cfg(context)
  if type(cfg.exclude) ~= "table" then
    return false
  end

  for _, pattern in ipairs(cfg.exclude) do
    if filter.glob_match(path, pattern) then
      return true
    end
  end

  return false
end

local function discover_tests_from_sources(context)
  local tests = {}
  local seen = {}
  local root = target_path(context)

  for _, pattern in ipairs(include_patterns(context)) do
    local matches = fs.glob(root, pattern) or {}
    for _, path in ipairs(matches) do
      if not excluded_by_runner(path, context) and is_test_source(path) then
        insert_unique(tests, seen, path_to_suite_id(path))
      end
    end
  end

  return tests
end

local function parse_defined_test_names_output(output)
  local tests = {}
  local seen = {}

  for line in output:gmatch("[^\r\n]+") do
    local list_body = line:match("%[info%]%s+List%((.+)%)")
      or line:match("%[info%]%s+%[(.+)%]")
      or line:match("^%s*List%((.+)%)")

    if list_body then
      for entry in list_body:gmatch("[^,]+") do
        entry = trim(entry)
        entry = entry:gsub('^"', ""):gsub('"$', "")
        insert_unique(tests, seen, entry)
      end
    end

    local suite = line:match("^%s*([%w%.]+)%s*$")
    if suite and suite:match("%.") and not suite:match("^%[") then
      insert_unique(tests, seen, suite)
    end
  end

  return tests
end

local function collect_tests_from_sbt(context)
  local cfg = runner_cfg(context)
  local key = cfg.defined_test_names_key or "definedTestNames"
  local project = cfg.project
  local show_target = key
  if project and project ~= "" then
    show_target = project:gsub("^/", "") .. "/" .. key
  end

  local args = base_sbt_args()
  table.insert(args, "show")
  table.insert(args, show_target)
  append_runner_args(args, context)

  local result = sys.run("sbt", args, { cwd = target_path(context) })
  if result.exit_code ~= 0 then
    return nil, trim(result.stderr) or trim(result.stdout)
  end

  local tests = parse_defined_test_names_output(result.stdout .. "\n" .. result.stderr)
  if #tests == 0 then
    return nil, "definedTestNames returned no suites"
  end

  return tests
end

local function discover_tests_from_reports(context)
  local patterns = {
    "**/target/test-reports/TEST-*.xml",
    "**/target/test-reports/*.xml",
    "**/target/scala-*/test-reports/TEST-*.xml",
  }

  local tests = {}
  local seen_ids = {}
  local seen_paths = {}
  local root = target_path(context)

  for _, pattern in ipairs(patterns) do
    local matches = fs.glob(root, pattern) or {}
    for _, path in ipairs(matches) do
      local abs = path
      if path:sub(1, 1) ~= "/" then
        abs = path_join(root, path)
      end
      if not seen_paths[abs] then
        seen_paths[abs] = true
        local file = io.open(abs, "r")
        if file then
          local content = file:read("*a")
          file:close()
          if content then
            for testcase in content:gmatch("<testcase%s+[^>]+/>") do
              local name = testcase:match('name="([^"]*)"')
              local classname = testcase:match('classname="([^"]*)"')
              if name and classname then
                insert_unique(tests, seen_ids, normalize_test_id(classname, name))
              end
            end
            for testcase in content:gmatch("<testcase%s+[^>]+>.-</testcase>") do
              local name = testcase:match('name="([^"]*)"')
              local classname = testcase:match('classname="([^"]*)"')
              if name and classname then
                insert_unique(tests, seen_ids, normalize_test_id(classname, name))
              end
            end
          end
        end
      end
    end
  end

  return tests
end

function list(context)
  local cfg = runner_cfg(context)
  local tests = {}
  local seen = {}

  local from_sbt, sbt_error = collect_tests_from_sbt(context)
  if from_sbt then
    for _, id in ipairs(from_sbt) do
      insert_unique(tests, seen, id)
    end
  end

  if cfg.discover_tests or #tests == 0 then
    for _, id in ipairs(discover_tests_from_sources(context)) do
      insert_unique(tests, seen, id)
    end
  end

  if cfg.discover_tests or #tests == 0 then
    for _, id in ipairs(discover_tests_from_reports(context)) do
      insert_unique(tests, seen, id)
    end
  end

  if #tests == 0 and sbt_error then
    error("scalatest discovery failed: " .. sbt_error)
  end

  return apply_filters(tests, context)
end

local function test_only_command(context)
  local cfg = runner_cfg(context)
  local project = cfg.project
  if project and project ~= "" then
    return project:gsub("^/", "") .. "/testOnly"
  end
  return "testOnly"
end

local function append_test_selection(args, context)
  local cfg = runner_cfg(context)
  local suites = collect_suite_targets(context)
  local name_pattern = effective_name_pattern(context)

  if #suites > 0 or name_pattern then
    table.insert(args, test_only_command(context))
    for _, suite in ipairs(suites) do
      table.insert(args, suite)
    end
    if name_pattern then
      table.insert(args, "--")
      table.insert(args, "-z")
      table.insert(args, name_pattern)
    end
    return
  end

  table.insert(args, test_task_for_project(cfg.project))
end

local function build_sbt_spec(context, args)
  local cfg = runner_cfg(context)
  append_runner_args(args, context)

  local spec = {
    command = cfg.command or "sbt",
    args = args,
    cwd = target_path(context),
  }

  if cfg.sbt_opts then
    local sbt_opts = cfg.sbt_opts
    if type(sbt_opts) == "table" then
      sbt_opts = table.concat(sbt_opts, " ")
    end
    spec.env = { SBT_OPTS = sbt_opts }
  elseif cfg.jvm_opts then
    local jvm_opts = cfg.jvm_opts
    if type(jvm_opts) == "table" then
      jvm_opts = table.concat(jvm_opts, " ")
    end
    spec.env = { SBT_OPTS = jvm_opts }
  end

  return spec
end

function build_command(context)
  local args = base_sbt_args()
  append_test_selection(args, context)
  return build_sbt_spec(context, args)
end

local function coverage_cfg(context)
  local cfg = runner_cfg(context)
  local from_runner = type(cfg.coverage) == "table" and cfg.coverage or {}
  local from_global = type(config) == "table" and type(config.coverage) == "table" and config.coverage
    or {}
  return shallow_merge(from_global, from_runner)
end

local function default_coverage_cfg(context)
  local cfg = runner_cfg(context)
  local report = cfg.coverage_report
  if not report then
    report = "target/scala-2.13/scoverage-report/cobertura.xml"
  end

  return {
    goals = { "clean", "coverage", "test", "coverageReport" },
    report = report,
    output = "coverage/scalatest.msgpack",
    reporter = "cobertura",
  }
end

local function effective_coverage_cfg(context)
  return shallow_merge(default_coverage_cfg(context), coverage_cfg(context))
end

function build_coverage_run(context)
  local coverage = effective_coverage_cfg(context)
  local goals = type(coverage.goals) == "table" and coverage.goals
    or { "clean", "coverage", "test", "coverageReport" }
  local args = base_sbt_args()
  local inserted_test_selection = false

  for _, goal in ipairs(goals) do
    if goal == "test" and not inserted_test_selection then
      append_test_selection(args, context)
      inserted_test_selection = true
    else
      table.insert(args, goal)
    end
  end

  if not inserted_test_selection then
    append_test_selection(args, context)
  end

  local spec = build_sbt_spec(context, args)
  spec.report = coverage.report
  spec.reporter = coverage.reporter or "cobertura"
  spec.output = coverage.output or "coverage/scalatest.msgpack"

  if coverage.min_line_rate then
    spec.min_line_rate = coverage.min_line_rate
  end

  if coverage.min_branch_rate then
    spec.min_branch_rate = coverage.min_branch_rate
  end

  return spec
end

local function parse_suite_header(line)
  local suite = line:match("^%[info%]%s+([%w%.]+):%s*$")
  if suite then
    parse_state.suite = suite
    return { event = "start", id = suite }
  end

  suite = line:match("^%[info%]%s+[%w%s]+%s+([%w%.]+):%s*$")
  if suite then
    parse_state.suite = suite
    return { event = "start", id = suite }
  end

  return nil
end

local function parse_scalatest_test_line(line)
  local suite = parse_state.suite

  local test_name = line:match("^%[info%]%s+%+%s+(.+)$")
  if test_name then
    return { event = "pass", id = normalize_test_id(suite, test_name) }
  end

  test_name = line:match("^%[info%]%s+x%s+(.+)$")
  if test_name then
    return { event = "fail", id = normalize_test_id(suite, test_name), msg = line }
  end

  test_name = line:match("^%[info%]%s+o%s+(.+)$")
  if test_name then
    return { event = "skip", id = normalize_test_id(suite, test_name) }
  end

  test_name = line:match("^%[info%]%s+%-%s+(.+)%s+%*%*%* FAILED %*%*%*%s*$")
  if test_name then
    return { event = "fail", id = normalize_test_id(suite, test_name), msg = line }
  end

  test_name = line:match("^%[info%]%s+%-%s+(.+)%s+!!! IGNORED !!!%s*$")
  if test_name then
    return { event = "skip", id = normalize_test_id(suite, test_name) }
  end

  test_name = line:match("^%[info%]%s+%-%s+(.+)%s+%(pending%)$")
  if test_name then
    return { event = "skip", id = normalize_test_id(suite, test_name) }
  end

  test_name = line:match("^%[info%]%s+%-%s+(.+)$")
  if test_name and not test_name:match("^%s*$") then
    return { event = "pass", id = normalize_test_id(suite, test_name) }
  end

  return nil
end

function parse_line(line)
  line = trim(line)
  if line == "" then
    return nil
  end

  local suite_event = parse_suite_header(line)
  if suite_event then
    return suite_event
  end

  local test_event = parse_scalatest_test_line(line)
  if test_event then
    return test_event
  end

  if line:match("%*%*%* %d+ TEST FAILED %*%*%*") or line:match("%*%*%* %d+ TESTS? FAILED %*%*%*") then
    return { event = "output", text = line }
  end

  if line:match("^%[success%]") or line:match("^%[error%]") then
    return { event = "output", text = line }
  end

  return { event = "output", text = line }
end
