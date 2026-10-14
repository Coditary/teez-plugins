local function runner_opts(context)
  return context.runner or {}
end

local function path_join(base, child)
  if base:sub(-1) == "/" then
    return base .. child
  end
  return base .. "/" .. child
end

local function resolve_gradle(context)
  local target = context.target_path
  local wrapper = path_join(target, "gradlew")
  if fs.exists(wrapper) then
    return wrapper
  end

  local probe = sys.run("sh", { "-c", "command -v gradle" })
  if probe.exit_code == 0 and probe.stdout:match("%S") then
    return "gradle"
  end

  error("kotlin runner: neither ./gradlew nor gradle on PATH is available")
end

local function append_runner_args(args, context)
  local opts = runner_opts(context)
  if opts.args then
    for _, arg in ipairs(opts.args) do
      table.insert(args, arg)
    end
  end
end

local function test_task_for_project(project)
  if not project or project == "" then
    return "test"
  end
  project = project:gsub("^:", "")
  return ":" .. project .. ":test"
end

local function collect_test_patterns(context)
  local patterns = {}
  local opts = runner_opts(context)

  if opts.tests then
    if type(opts.tests) == "string" then
      table.insert(patterns, opts.tests)
    else
      for _, pattern in ipairs(opts.tests) do
        table.insert(patterns, pattern)
      end
    end
  end

  if context.filters then
    if context.filters.names then
      for _, name in ipairs(context.filters.names) do
        table.insert(patterns, "*" .. name .. "*")
      end
    end
    if context.filters.pattern then
      table.insert(patterns, context.filters.pattern)
    end
  end

  return patterns
end

local function apply_test_patterns(args, patterns)
  for _, pattern in ipairs(patterns) do
    table.insert(args, "--tests")
    table.insert(args, pattern)
  end
end

local function parse_dry_run_task(line)
  local trimmed = line:match("^%s*(.-)%s*$")
  if not trimmed or trimmed == "" then
    return nil
  end

  local task = trimmed:match("^(:[%w%-%.]+:test)%s+SKIPPED%s*$")
  if task then
    return task
  end

  task = trimmed:match("^(:test)%s+SKIPPED%s*$")
  if task then
    return task
  end

  return nil
end

local function parse_testcase_xml(path)
  local file = io.open(path, "r")
  if not file then
    return {}
  end

  local content = file:read("*a")
  file:close()
  if not content then
    return {}
  end

  local tests = {}
  local seen = {}

  for testcase in content:gmatch("<testcase%s+[^>]+/>") do
    local name = testcase:match('name="([^"]*)"')
    local classname = testcase:match('classname="([^"]*)"')
    if name and classname then
      local id = classname .. " > " .. name
      if not seen[id] then
        seen[id] = true
        table.insert(tests, id)
      end
    end
  end

  for testcase in content:gmatch("<testcase%s+[^>]+>.-</testcase>") do
    local name = testcase:match('name="([^"]*)"')
    local classname = testcase:match('classname="([^"]*)"')
    if name and classname then
      local id = classname .. " > " .. name
      if not seen[id] then
        seen[id] = true
        table.insert(tests, id)
      end
    end
  end

  return tests
end

local function absolute_path(context, path)
  if path:sub(1, 1) == "/" then
    return path
  end
  return path_join(context.target_path, path)
end

local function discover_tests_from_reports(context)
  local patterns = {
    "**/build/test-results/**/TEST-*.xml",
    "**/build/test-results/test/TEST-*.xml",
  }

  local seen_paths = {}
  local tests = {}
  local seen_ids = {}

  for _, pattern in ipairs(patterns) do
    local matches = fs.glob(context.target_path, pattern) or {}
    for _, path in ipairs(matches) do
      local abs = absolute_path(context, path)
      if not seen_paths[abs] then
        seen_paths[abs] = true
        for _, id in ipairs(parse_testcase_xml(abs)) do
          if not seen_ids[id] then
            seen_ids[id] = true
            table.insert(tests, id)
          end
        end
      end
    end
  end

  return tests
end

local function filter_test_ids(tests, context)
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

function list(context)
  local gradle = resolve_gradle(context)
  local opts = runner_opts(context)
  local args = { test_task_for_project(opts.project), "--dry-run", "--console=plain" }
  append_runner_args(args, context)

  local output = sys.exec(gradle, args, { cwd = context.target_path })
  local tests = {}
  local seen = {}

  for line in output:gmatch("[^\r\n]+") do
    local task = parse_dry_run_task(line)
    if task and not seen[task] then
      seen[task] = true
      table.insert(tests, task)
    end
  end

  if opts.discover_tests or #tests == 0 then
    for _, id in ipairs(discover_tests_from_reports(context)) do
      if not seen[id] then
        seen[id] = true
        table.insert(tests, id)
      end
    end
  end

  return filter_test_ids(tests, context)
end

function build_command(context)
  local gradle = resolve_gradle(context)
  local opts = runner_opts(context)
  local args = { test_task_for_project(opts.project), "--console=plain" }

  apply_test_patterns(args, collect_test_patterns(context))
  append_runner_args(args, context)

  local spec = {
    command = gradle,
    args = args,
    cwd = context.target_path,
  }

  if opts.jvm_args then
    local jvm_args = opts.jvm_args
    if type(jvm_args) == "table" then
      jvm_args = table.concat(jvm_args, " ")
    end
    spec.env = {
      GRADLE_OPTS = jvm_args,
    }
  end

  return spec
end

local function parse_test_result_line(line)
  local class_name, test_name, status = line:match("^%s*([%w%.$]+) > (.+) (PASSED|FAILED|SKIPPED)%s*$")
  if class_name then
    return class_name, test_name, status
  end

  class_name, status = line:match("^%s*Test ([%w%.$%(%)]+) (PASSED|FAILED|SKIPPED)%s*$")
  if class_name then
    local method = class_name:match("%.([^%.]+)$") or class_name
    return class_name, method, status
  end

  return nil
end

function parse_line(line)
  if not line or line == "" then
    return nil
  end

  local class_name, test_name, status = parse_test_result_line(line)
  if class_name and test_name and status then
    local id = class_name .. " > " .. test_name
    if status == "PASSED" then
      return { event = "pass", id = id }
    end
    if status == "FAILED" then
      return { event = "fail", id = id, msg = line }
    end
    if status == "SKIPPED" then
      return { event = "skip", id = id }
    end
  end

  if line:match("BUILD SUCCESSFUL") or line:match("BUILD FAILED") then
    return { event = "output", text = line }
  end

  if line:match("^> Task ") then
    return { event = "output", text = line }
  end

  return { event = "output", text = line }
end

local function default_coverage_report(context, coverage)
  local opts = runner_opts(context)
  if opts.coverage_report then
    return opts.coverage_report
  end

  local project = opts.project
  if project and project ~= "" then
    project = project:gsub("^:", "")
    if coverage == "kover" then
      return project .. "/build/reports/kover/report.xml"
    end
    return project .. "/build/reports/jacoco/test/jacocoTestReport.xml"
  end

  if coverage == "kover" then
    return "build/reports/kover/report.xml"
  end
  return "build/reports/jacoco/test/jacocoTestReport.xml"
end

function build_coverage_run(context)
  local gradle = resolve_gradle(context)
  local opts = runner_opts(context)
  local coverage = (opts.coverage or "jacoco"):lower()
  local args = { test_task_for_project(opts.project), "--console=plain" }

  apply_test_patterns(args, collect_test_patterns(context))

  if coverage == "kover" then
    table.insert(args, "koverXmlReport")
  else
    table.insert(args, "jacocoTestReport")
  end

  append_runner_args(args, context)

  local spec = {
    command = gradle,
    args = args,
    cwd = context.target_path,
    report = default_coverage_report(context, coverage),
    reporter = "cobertura",
    output = opts.coverage_output or "coverage/kotlin.xml",
  }

  if opts.min_line_rate then
    spec.min_line_rate = opts.min_line_rate
  end

  return spec
end
