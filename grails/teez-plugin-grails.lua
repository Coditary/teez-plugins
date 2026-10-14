-- teez Grails adapter (Gradle + Spock)

local DEFAULT_INCLUDE = {
  "**/src/test/groovy/**",
  "**/src/integration-test/groovy/**",
  "**/*Spec.groovy",
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

local function absolute_path(base, path)
  if path:sub(1, 1) == "/" then
    return path
  end
  return path_join(base, path)
end

local function find_gradle_root(start_path)
  local path = start_path
  while path and path ~= "" do
    if fs.exists(path .. "/gradlew")
      or fs.exists(path .. "/build.gradle")
      or fs.exists(path .. "/build.gradle.kts")
      or fs.exists(path .. "/settings.gradle")
      or fs.exists(path .. "/settings.gradle.kts") then
      return path
    end
    local parent = path:match("^(.*)/[^/]+$")
    if not parent or parent == path then
      break
    end
    path = parent
  end
  return start_path
end

local function resolve_gradle(context)
  local root = find_gradle_root(target_path(context))
  local wrapper = path_join(root, "gradlew")
  if fs.exists(wrapper) then
    return wrapper, root
  end

  local probe = sys.run("sh", { "-c", "command -v gradle" })
  if probe.exit_code == 0 and trim(probe.stdout) ~= "" then
    return "gradle", root
  end

  error("grails runner: neither ./gradlew nor gradle on PATH is available")
end

local function prepend_project_args(args, gradle_root, target)
  if target ~= gradle_root and not fs.exists(target .. "/gradlew") then
    table.insert(args, 1, target)
    table.insert(args, 1, "-p")
  end
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

local function include_patterns(context)
  local cfg = runner_cfg(context)
  if cfg.include then
    return cfg.include
  end
  return DEFAULT_INCLUDE
end

local function path_excluded(path, exclude_patterns)
  for _, pattern in ipairs(exclude_patterns) do
    if filter.glob_match(path, pattern) then
      return true
    end
  end
  return false
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

local function gradle_test_pattern(context)
  local pattern = effective_test_pattern(context)
  if not pattern then
    return nil
  end
  return pattern:gsub("#", ".")
end

local function test_task_for_project(project)
  if not project or project == "" then
    return "test"
  end
  project = project:gsub("^:", "")
  return ":" .. project .. ":test"
end

local function test_id(class_name, feature)
  class_name = trim(class_name)
  feature = trim(feature or "")
  if class_name == "" then
    return nil
  end
  feature = feature:gsub("%(%)$", "")
  if feature ~= "" then
    return class_name .. " > " .. feature
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

local function class_name_from_spec_path(spec_path)
  local normalized = spec_path:gsub("\\", "/")
  local rel = normalized:match("src/test/groovy/(.+)%.groovy$")
    or normalized:match("src/integration%-test/groovy/(.+)%.groovy$")
  if rel then
    return rel:gsub("/", ".")
  end

  local base = normalized:match("([^/]+)Spec%.groovy$")
  if base then
    return base .. "Spec"
  end

  return nil
end

local function parse_spec_features(spec_path)
  local file = io.open(spec_path, "r")
  if not file then
    return {}
  end

  local content = file:read("*a")
  file:close()
  if not content then
    return {}
  end

  local features = {}
  local seen = {}
  for feature in content:gmatch('def%s+"([^"]+)"') do
    if not seen[feature] then
      seen[feature] = true
      table.insert(features, feature)
    end
  end
  for feature in content:gmatch('void%s+"([^"]+)"') do
    if not seen[feature] then
      seen[feature] = true
      table.insert(features, feature)
    end
  end

  return features
end

local function discover_specs_from_glob(context)
  local target = target_path(context)
  local cfg = runner_cfg(context)
  local exclude = cfg.exclude or {}
  local tests = {}
  local seen = {}

  for _, pattern in ipairs(include_patterns(context)) do
    local matches = fs.glob(target, pattern) or {}
    for _, path in ipairs(matches) do
      if path:match("%.groovy$") then
        local resolved = absolute_path(target, path)
        if not path_excluded(resolved, exclude) then
          local class_name = class_name_from_spec_path(resolved)
          if class_name then
            local features = parse_spec_features(resolved)
            if #features == 0 then
              insert_unique(tests, seen, class_name)
            else
              for _, feature in ipairs(features) do
                insert_unique(tests, seen, test_id(class_name, feature))
              end
            end
          end
        end
      end
    end
  end

  return tests
end

local function parse_gradle_dry_run_line(line, tests, seen)
  local class_name, feature = line:match("^[%w%.]+ > ([%w%.]+) > (.+)%s+SKIPPED%s*$")
  if class_name and feature then
    insert_unique(tests, seen, test_id(class_name, feature))
    return
  end

  class_name, feature = line:match("^([%w%.]+) > (.+)%s+SKIPPED%s*$")
  if class_name and feature and not line:match("^> Task") then
    insert_unique(tests, seen, test_id(class_name, feature))
  end
end

local function collect_gradle_dry_run_tests(context)
  local gradle, gradle_root = resolve_gradle(context)
  local cfg = runner_cfg(context)
  local args = { test_task_for_project(cfg.project), "--console=plain", "--dry-run" }
  local pattern = gradle_test_pattern(context)
  if pattern then
    table.insert(args, "--tests")
    table.insert(args, pattern)
  end
  append_runner_args(args, context)
  prepend_project_args(args, gradle_root, target_path(context))

  local result = sys.run(gradle, args, { cwd = gradle_root })
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

  return tests
end

function list(context)
  local cfg = runner_cfg(context)
  local tests = {}
  local seen = {}

  for _, id in ipairs(collect_gradle_dry_run_tests(context)) do
    insert_unique(tests, seen, id)
  end

  if cfg.discover_specs or #tests == 0 then
    for _, id in ipairs(discover_specs_from_glob(context)) do
      insert_unique(tests, seen, id)
    end
  end

  return apply_filters(tests, context)
end

local function build_test_args(context)
  local cfg = runner_cfg(context)
  local args = { test_task_for_project(cfg.project), "--console=plain" }
  local pattern = gradle_test_pattern(context)
  if pattern then
    table.insert(args, "--tests")
    table.insert(args, pattern)
  end
  append_runner_args(args, context)
  return args
end

function build_command(context)
  local gradle, gradle_root = resolve_gradle(context)
  local args = build_test_args(context)
  prepend_project_args(args, gradle_root, target_path(context))

  return {
    command = gradle,
    args = args,
    cwd = gradle_root,
  }
end

function build_list_command(context)
  local gradle, gradle_root = resolve_gradle(context)
  local args = build_test_args(context)
  table.insert(args, 2, "--dry-run")
  prepend_project_args(args, gradle_root, target_path(context))

  return {
    command = gradle,
    args = args,
    cwd = gradle_root,
  }
end

local function coverage_cfg(context)
  local cfg = runner_cfg(context)
  local from_runner = type(cfg.coverage) == "table" and cfg.coverage or {}
  local from_global = type(config) == "table" and type(config.coverage) == "table" and config.coverage
    or {}
  return shallow_merge(from_global, from_runner)
end

local function default_coverage_cfg()
  return {
    goals = { "test", "jacocoTestReport" },
    report = "build/reports/jacoco/test/jacocoTestReport.xml",
    output = "coverage/teez.msgpack",
    reporter = "cobertura",
  }
end

function build_coverage_run(context)
  local gradle, gradle_root = resolve_gradle(context)
  local coverage = shallow_merge(default_coverage_cfg(), coverage_cfg(context))
  local args = build_test_args(context)
  local goals = type(coverage.goals) == "table" and coverage.goals or nil
  local test_task = test_task_for_project(runner_cfg(context).project)

  if goals then
    for _, goal in ipairs(goals) do
      if goal ~= "test" and goal ~= test_task then
        table.insert(args, goal)
      end
    end
  else
    table.insert(args, "jacocoTestReport")
  end

  prepend_project_args(args, gradle_root, target_path(context))

  local spec = {
    command = gradle,
    args = args,
    cwd = gradle_root,
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

local function parse_test_result_line(line)
  local class_name, feature, status = line:match("^%s*([%w%.$]+) > (.+) (PASSED|FAILED|SKIPPED)%s*$")
  if class_name and feature and status then
    return class_name, feature, status
  end

  class_name, status = line:match("^%s*Test ([%w%.$%(%)]+) (PASSED|FAILED|SKIPPED)%s*$")
  if class_name and status then
    local method = class_name:match("%.([^%.]+)$") or class_name
    return class_name, method, status
  end

  return nil
end

function parse_line(line)
  line = trim(line)
  if line == "" then
    return nil
  end

  local class_name, feature, status = parse_test_result_line(line)
  if class_name and feature and status then
    local id = test_id(class_name, feature)
    if status == "PASSED" then
      return { event = "pass", id = id }
    end
    if status == "SKIPPED" then
      return { event = "skip", id = id }
    end
    return { event = "fail", id = id, msg = line }
  end

  local test_name, marker, duration_text = line:match(
    "^%[ERROR%]%s+([%w%.#%(%)%s]+)%s+Time elapsed:%s+[%d%.]+%s*s%s+<<<%s+(FAILURE!|ERROR!|SKIPPED!)"
  )
  if test_name and marker then
    local duration_ms = parse_duration_ms(duration_text or line)
    local id = test_name:gsub("#", " > "):gsub("%(%)$", "")
    if marker == "SKIPPED!" then
      return { event = "skip", id = id, duration_ms = duration_ms }
    end
    return { event = "fail", id = id, msg = marker, duration_ms = duration_ms }
  end

  test_name = line:match("^%[INFO%]%s+([%w%.#%(%)%s]+)%s+Time elapsed:%s+[%d%.]+%s*s%s+-")
  if test_name then
    local id = test_name:gsub("#", " > "):gsub("%(%)$", "")
    return { event = "pass", id = id, duration_ms = parse_duration_ms(line) }
  end

  class_name = line:match("^%[INFO%] Running%s+([%w%.]+)")
  if class_name then
    return { event = "start", id = class_name }
  end

  class_name = line:match("^Running%s+([%w%.]+)")
  if class_name then
    return { event = "start", id = class_name }
  end

  return { event = "output", text = line }
end
