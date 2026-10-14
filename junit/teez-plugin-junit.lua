-- teez JUnit adapter (Maven Surefire / Gradle test)

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

local function path_exists(path)
  return fs.exists(path)
end

local function has_gradle_project(target)
  return path_exists(target .. "/build.gradle")
    or path_exists(target .. "/build.gradle.kts")
    or path_exists(target .. "/gradlew")
end

local function has_maven_project(target)
  return path_exists(target .. "/pom.xml")
end

local function command_available(command)
  local result = sys.run(command, { "--version" })
  return result.exit_code == 0
end

local function resolve_tool(context)
  local cfg = runner_cfg(context)
  local target = target_path(context)
  local configured = cfg.tool

  if configured == "maven" or configured == "gradle" then
    return configured
  end

  if path_exists(target .. "/gradlew") or (has_gradle_project(target) and not has_maven_project(target)) then
    return "gradle"
  end

  if has_maven_project(target) then
    return "maven"
  end

  if has_gradle_project(target) then
    return "gradle"
  end

  return "maven"
end

local function ensure_tool_available(context, tool)
  local target = target_path(context)

  if tool == "gradle" then
    if path_exists(target .. "/gradlew") then
      return
    end
    if command_available("gradle") then
      return
    end
    error("junit runner: no gradlew wrapper and gradle not found on PATH")
  end

  if command_available("mvn") then
    return
  end
  error("junit runner: mvn not found on PATH")
end

local function resolve_command(context, tool)
  local target = target_path(context)
  local cfg = runner_cfg(context)

  if cfg.command then
    return cfg.command
  end

  if tool == "gradle" then
    if path_exists(target .. "/gradlew") then
      return target .. "/gradlew"
    end
    return "gradle"
  end

  return "mvn"
end

local function prepend_project_args(args, context, tool)
  local target = target_path(context)
  if target == "." then
    return
  end

  if tool == "maven" and path_exists(target .. "/pom.xml") then
    table.insert(args, 1, target .. "/pom.xml")
    table.insert(args, 1, "-f")
    return
  end

  if tool == "gradle" and not path_exists(target .. "/gradlew") then
    table.insert(args, 1, target)
    table.insert(args, 1, "-p")
  end
end

local function run_tool(context, tool, args)
  prepend_project_args(args, context, tool)
  local command = resolve_command(context, tool)
  return sys.run(command, args, { cwd = target_path(context) })
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

local function effective_test_pattern(context)
  return runner_pattern(context) or filters_pattern(context)
end

local function maven_test_pattern(context)
  local pattern = effective_test_pattern(context)
  if not pattern then
    return nil
  end

  -- Maven Surefire accepts Class, Class#method, Class*, pkg.* patterns.
  return pattern:gsub("%.%*$", "*"):gsub("%*%*$", "*")
end

local function gradle_test_pattern(context)
  local pattern = effective_test_pattern(context)
  if not pattern then
    return nil
  end

  -- Gradle --tests prefers FQCN or FQCN.method; keep glob-like segments.
  return pattern:gsub("#", ".")
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

local function normalize_test_id(class_name, method_name)
  class_name = trim(class_name)
  method_name = trim(method_name or "")

  if class_name == "" then
    return nil
  end

  method_name = method_name:gsub("%(%)$", "")

  if method_name ~= "" then
    return class_name .. "#" .. method_name
  end

  return class_name
end

local function insert_unique(tests, seen, id)
  id = trim(id)
  if id == "" or seen[id] then
    return
  end
  seen[id] = true
  table.insert(tests, id)
end

local function parse_maven_dry_run_line(line, tests, seen)
  local class_name, method_name = line:match("^%[INFO%] Running%s+([%w%.]+)#?(%w*)")
  if class_name then
    insert_unique(tests, seen, normalize_test_id(class_name, method_name))
    return
  end

  class_name, method_name = line:match("^%[INFO%] Would run:%s+([%w%.]+)#?(%w*)")
  if class_name then
    insert_unique(tests, seen, normalize_test_id(class_name, method_name))
    return
  end

  class_name, method_name = line:match("([%w%.]+)#([%w%(%)]+)")
  if class_name and method_name then
    insert_unique(tests, seen, normalize_test_id(class_name, method_name))
  end
end

local function parse_gradle_dry_run_line(line, tests, seen)
  local class_name, method_name = line:match("^[%w%.]+ > ([%w%.]+) > ([%w%(%)]+)%s+SKIPPED")
  if class_name and method_name then
    insert_unique(tests, seen, normalize_test_id(class_name, method_name))
    return
  end

  class_name, method_name = line:match("([%w%.]+) > ([%w%(%)%.]+)%s*$")
  if class_name and method_name and not line:match("^> Task") then
    insert_unique(tests, seen, normalize_test_id(class_name, method_name))
  end
end

local function collect_maven_tests(context)
  ensure_tool_available(context, "maven")

  local args = { "-q", "test", "-DdryRun=true", "-DfailIfNoTests=false" }
  local pattern = maven_test_pattern(context)
  if pattern then
    table.insert(args, "-Dtest=" .. pattern)
  end
  append_runner_args(args, context)

  local result = run_tool(context, "maven", args)
  if result.exit_code ~= 0 and trim(result.stderr) ~= "" and trim(result.stdout) == "" then
    error("maven test discovery failed: " .. trim(result.stderr))
  end

  local tests = {}
  local seen = {}
  local output = result.stdout .. "\n" .. result.stderr
  for line in output:gmatch("[^\r\n]+") do
    parse_maven_dry_run_line(line, tests, seen)
  end

  return apply_filters(tests, context)
end

local function collect_gradle_tests(context)
  ensure_tool_available(context, "gradle")

  local args = { "test", "--console=plain", "--dry-run" }
  local pattern = gradle_test_pattern(context)
  if pattern then
    table.insert(args, "--tests")
    table.insert(args, pattern)
  end
  append_runner_args(args, context)

  local result = run_tool(context, "gradle", args)
  if result.exit_code ~= 0 then
    local message = trim(result.stderr)
    if message == "" then
      message = trim(result.stdout)
    end
    error("gradle test discovery failed: " .. message)
  end

  local tests = {}
  local seen = {}
  local output = result.stdout .. "\n" .. result.stderr
  for line in output:gmatch("[^\r\n]+") do
    parse_gradle_dry_run_line(line, tests, seen)
  end

  if #tests == 0 then
    insert_unique(tests, seen, "test")
  end

  return apply_filters(tests, context)
end

function list(context)
  local tool = resolve_tool(context)
  if tool == "gradle" then
    return collect_gradle_tests(context)
  end
  return collect_maven_tests(context)
end

function build_command(context)
  local tool = resolve_tool(context)
  ensure_tool_available(context, tool)

  local command = resolve_command(context, tool)
  local args = {}

  if tool == "gradle" then
    table.insert(args, "test")
    local pattern = gradle_test_pattern(context)
    if pattern then
      table.insert(args, "--tests")
      table.insert(args, pattern)
    end
  else
    table.insert(args, "test")
    local pattern = maven_test_pattern(context)
    if pattern then
      table.insert(args, "-Dtest=" .. pattern)
    end
    table.insert(args, "-DfailIfNoTests=false")
  end

  append_runner_args(args, context)

  return {
    command = command,
    args = args,
    cwd = target_path(context),
  }
end

function build_list_command(context)
  local tool = resolve_tool(context)
  ensure_tool_available(context, tool)

  local command = resolve_command(context, tool)
  local args = {}

  if tool == "gradle" then
    table.insert(args, "test")
    table.insert(args, "--console=plain")
    table.insert(args, "--dry-run")
    local pattern = gradle_test_pattern(context)
    if pattern then
      table.insert(args, "--tests")
      table.insert(args, pattern)
    end
  else
    table.insert(args, "-q")
    table.insert(args, "test")
    table.insert(args, "-DdryRun=true")
    table.insert(args, "-DfailIfNoTests=false")
    local pattern = maven_test_pattern(context)
    if pattern then
      table.insert(args, "-Dtest=" .. pattern)
    end
  end

  append_runner_args(args, context)

  return {
    command = command,
    args = args,
    cwd = target_path(context),
  }
end

local function coverage_cfg(context)
  local cfg = runner_cfg(context)
  local from_runner = type(cfg.coverage) == "table" and cfg.coverage or {}
  local from_global = type(config) == "table" and type(config.coverage) == "table" and config.coverage
    or {}
  return shallow_merge(from_global, from_runner)
end

local function default_coverage_cfg(context, tool)
  if tool == "gradle" then
    return {
      goals = { "test", "jacocoTestReport" },
      report = "build/reports/jacoco/test/jacocoTestReport.xml",
      output = "coverage/teez.msgpack",
      reporter = "cobertura",
    }
  end

  return {
    goals = { "test", "jacoco:report" },
    report = "target/site/jacoco/jacoco.xml",
    output = "coverage/teez.msgpack",
    reporter = "cobertura",
  }
end

local function effective_coverage_cfg(context, tool)
  return shallow_merge(default_coverage_cfg(context, tool), coverage_cfg(context))
end

function build_coverage_run(context)
  local tool = resolve_tool(context)
  ensure_tool_available(context, tool)

  local command = resolve_command(context, tool)
  local coverage = effective_coverage_cfg(context, tool)
  local args = {}
  local goals = type(coverage.goals) == "table" and coverage.goals or nil

  if tool == "gradle" then
    table.insert(args, "test")
    local pattern = gradle_test_pattern(context)
    if pattern then
      table.insert(args, "--tests")
      table.insert(args, pattern)
    end
    if goals then
      for _, goal in ipairs(goals) do
        if goal ~= "test" then
          table.insert(args, goal)
        end
      end
    else
      table.insert(args, "jacocoTestReport")
    end
  else
    local pattern = maven_test_pattern(context)
    if pattern then
      table.insert(args, "-Dtest=" .. pattern)
    end
    table.insert(args, "-DfailIfNoTests=false")
    if goals then
      for _, goal in ipairs(goals) do
        table.insert(args, goal)
      end
    else
      table.insert(args, "test")
      table.insert(args, "jacoco:report")
    end
  end

  prepend_project_args(args, context, tool)
  append_runner_args(args, context)

  local spec = {
    command = command,
    args = args,
    cwd = target_path(context),
    report = coverage.report,
    reporter = coverage.reporter,
    output = coverage.output,
  }

  if coverage.min_line_rate then
    spec.min_line_rate = coverage.min_line_rate
  end

  if coverage.min_branch_rate then
    spec.min_branch_rate = coverage.min_branch_rate
  end

  return spec
end

local function parse_duration_ms(text)
  if not text then
    return nil
  end

  local seconds = text:match("Time elapsed:%s+([%d%.]+)%s*s")
  if seconds then
    return math.floor(tonumber(seconds) * 1000 + 0.5)
  end

  return nil
end

function parse_line(line)
  line = trim(line)
  if line == "" then
    return nil
  end

  -- Gradle: Class > method() PASSED|FAILED|SKIPPED
  local class_name, method_name, status = line:match("^([%w%.]+) > ([%w%(%)%.]+)%s+(PASSED|FAILED|SKIPPED)$")
  if class_name and method_name and status then
    local id = normalize_test_id(class_name, method_name)
    if status == "PASSED" then
      return { event = "pass", id = id }
    end
    if status == "SKIPPED" then
      return { event = "skip", id = id }
    end
    return { event = "fail", id = id, msg = status }
  end

  -- Maven Surefire failure/skip lines with timing
  local test_id, marker, duration_text = line:match("^%[ERROR%]%s+([%w%.#%(%)]+)%s+Time elapsed:%s+[%d%.]+%s*s%s+<<<%s+(FAILURE!|ERROR!|SKIPPED!)")
  if test_id and marker then
    local duration_ms = parse_duration_ms(duration_text or line)
    if marker == "SKIPPED!" then
      return { event = "skip", id = test_id:gsub("%(%)$", ""), duration_ms = duration_ms }
    end
    return { event = "fail", id = test_id:gsub("%(%)$", ""), msg = marker, duration_ms = duration_ms }
  end

  -- Maven/JUnit pass line
  test_id, marker = line:match("^%[INFO%]%s+([%w%.#%(%)]+)%s+Time elapsed:%s+[%d%.]+%s*s%s+-")
  if test_id then
    return { event = "pass", id = test_id:gsub("%(%)$", ""), duration_ms = parse_duration_ms(line) }
  end

  -- Surefire running banner
  class_name = line:match("^%[INFO%] Running%s+([%w%.]+)")
  if class_name then
    return { event = "start", id = class_name }
  end

  class_name = line:match("^Running%s+([%w%.]+)")
  if class_name then
    return { event = "start", id = class_name }
  end

  -- Generic JUnit Platform style: class.method() STATUS
  test_id, status = line:match("^([%w%.#%(%)]+)%s+(PASSED|FAILED|SKIPPED)$")
  if test_id and status then
    if status == "PASSED" then
      return { event = "pass", id = test_id:gsub("%(%)$", "") }
    end
    if status == "SKIPPED" then
      return { event = "skip", id = test_id:gsub("%(%)$", "") }
    end
    return { event = "fail", id = test_id:gsub("%(%)$", ""), msg = status }
  end

  return { event = "output", text = line }
end
