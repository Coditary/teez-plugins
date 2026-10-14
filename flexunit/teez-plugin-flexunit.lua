-- FlexUnit runner for legacy Adobe ActionScript / Flex projects.
-- Supports Ant (build.xml), Maven (pom.xml), and configurable mxmlc + player runs.

local DEFAULT_INCLUDE = { "**/*Test.as", "**/tests/**" }

local function on_path(cmd)
  local result = sys.run("sh", { "-c", "command -v " .. cmd .. " >/dev/null 2>&1" })
  return result.exit_code == 0
end

local function first_on_path(candidates)
  for _, cmd in ipairs(candidates) do
    if on_path(cmd) then
      return cmd
    end
  end
  return nil
end

local function ensure_tool(mode, runner)
  if mode == "ant" then
    if not on_path("ant") then
      error("flexunit: 'ant' not found on PATH (mode=ant)")
    end
    return "ant"
  end

  if mode == "maven" then
    local mvn = first_on_path({ "mvn", "mvnw" })
    if not mvn then
      error("flexunit: 'mvn' or 'mvnw' not found on PATH (mode=maven)")
    end
    return mvn
  end

  if mode == "mxmlc" then
    local compiler = runner.compiler or first_on_path({ "mxmlc", "compc" })
    if not compiler then
      error("flexunit: mxmlc/compc not found on PATH (mode=mxmlc)")
    end
    local player = runner.player or first_on_path({ "adl", "flashplayerdebugger", "flashplayer" })
    if not player and not runner.player_command then
      error("flexunit: no SWF player found (set runners.flexunit.player or player_command)")
    end
    return compiler
  end

  error("flexunit: unknown mode '" .. tostring(mode) .. "' (expected ant, maven, or mxmlc)")
end

local function include_patterns(context)
  local runner = context.runner or {}
  if runner.include then
    return runner.include
  end
  return DEFAULT_INCLUDE
end

local function exclude_patterns(context)
  local runner = context.runner or {}
  return runner.exclude or {}
end

local function is_excluded(path, excludes)
  for _, pattern in ipairs(excludes) do
    if filter.glob_match(path, pattern) then
      return true
    end
  end
  return false
end

local function relative_path(root, path)
  if path:sub(1, #root + 1) == root .. "/" then
    return path:sub(#root + 2)
  end
  if path:sub(1, #root) == root then
    return path:sub(#root + 2)
  end
  return path
end

local function read_package_name(file_path)
  if not fs.read then
    return nil
  end
  local content = fs.read(file_path)
  if not content then
    return nil
  end
  return content:match("package%s+([%w%.]+)")
end

local function path_to_test_id(target_path, file_path)
  local rel = relative_path(target_path, file_path):gsub("%.as$", "")
  local class_name = rel:match("([^/]+)$") or rel
  local package_name = read_package_name(file_path)
  if package_name then
    return package_name .. "." .. class_name
  end
  return rel:gsub("/", ".")
end

local function is_test_file(path)
  if path:match("Test%.as$") then
    return true
  end
  if path:find("/tests/") or path:find("\\tests\\") then
    return path:match("%.as$") ~= nil
  end
  return false
end

local function discover_test_files(context)
  local tests = {}
  local seen = {}
  local includes = include_patterns(context)
  local excludes = exclude_patterns(context)

  for _, pattern in ipairs(includes) do
    for _, path in ipairs(fs.glob(context.target_path, pattern)) do
      if is_test_file(path) and not is_excluded(path, excludes) then
        local id = path_to_test_id(context.target_path, path)
        if not seen[id] then
          seen[id] = true
          table.insert(tests, id)
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

local function resolve_mode(context)
  local runner = context.runner or {}
  if runner.mode then
    return runner.mode
  end
  if fs.exists("pom.xml") and not fs.exists("build.xml") then
    return "maven"
  end
  if runner.compiler or runner.player or runner.runner_mxml or runner.main_class then
    return "mxmlc"
  end
  return "ant"
end

local function append_args(args, extra)
  if not extra then
    return
  end
  for _, value in ipairs(extra) do
    table.insert(args, value)
  end
end

local function build_ant_command(context, target)
  local runner = context.runner or {}
  ensure_tool("ant", runner)

  local args = { "-f", runner.build_file or "build.xml" }
  append_args(args, runner.args)
  table.insert(args, target)

  local spec = {
    command = "ant",
    args = args,
    cwd = context.target_path,
  }

  if runner.env then
    spec.env = runner.env
  end

  return spec
end

local function build_maven_command(context)
  local runner = context.runner or {}
  local mvn = ensure_tool("maven", runner)

  local args = { "test" }
  append_args(args, runner.args)

  local spec = {
    command = mvn,
    args = args,
    cwd = context.target_path,
  }

  if runner.env then
    spec.env = runner.env
  end

  return spec
end

local function build_mxmlc_command(context)
  local runner = context.runner or {}
  ensure_tool("mxmlc", runner)

  local compiler = runner.compiler or first_on_path({ "mxmlc", "compc" })
  local output = runner.output or "bin/FlexUnitTests.swf"
  local entry = runner.runner_mxml or runner.main_class

  if not entry then
    error("flexunit: mxmlc mode requires runners.flexunit.runner_mxml or main_class")
  end

  local args = {}
  append_args(args, runner.compiler_args)

  if runner.coverage then
    table.insert(args, "-coverage")
    if runner.coverage_config then
      table.insert(args, "-coverage-config=" .. runner.coverage_config)
    end
  end

  local source_paths = runner.source_path or { "src", "test" }
  for _, dir in ipairs(source_paths) do
    table.insert(args, "-source-path+=" .. dir)
  end

  local library_paths = runner.library_path or { "libs" }
  for _, dir in ipairs(library_paths) do
    table.insert(args, "-library-path+=" .. dir)
  end

  append_args(args, runner.include_libraries)

  table.insert(args, "-output=" .. output)

  if entry:match("%.mxml$") or entry:match("%.as$") then
    table.insert(args, entry)
  else
    table.insert(args, entry .. ".as")
  end

  local spec = {
    command = compiler,
    args = args,
    cwd = context.target_path,
  }

  local player = runner.player or first_on_path({ "adl", "flashplayerdebugger", "flashplayer" })

  if runner.player_command then
    spec.env = spec.env or {}
    spec.env.TEEZ_FLEXUNIT_PLAYER = runner.player_command
    spec.env.TEEZ_FLEXUNIT_SWF = output
  elseif player == "adl" then
    spec.env = spec.env or {}
    local descriptor = runner.app_descriptor or "src/application.xml"
    spec.env.TEEZ_FLEXUNIT_PLAYER = table.concat({ player, "-nodebug", descriptor, "--", output }, " ")
  elseif player then
    spec.env = spec.env or {}
    local player_cmd = player .. " " .. output
    if runner.player_args and #runner.player_args > 0 then
      player_cmd = player_cmd .. " " .. table.concat(runner.player_args, " ")
    end
    spec.env.TEEZ_FLEXUNIT_PLAYER = player_cmd
  end

  if runner.env then
    spec.env = spec.env or {}
    for key, value in pairs(runner.env) do
      spec.env[key] = value
    end
  end

  return spec
end

function list(context)
  return apply_filters(discover_test_files(context), context)
end

function build_command(context)
  local runner = context.runner or {}
  local mode = resolve_mode(context)

  if mode == "maven" then
    return build_maven_command(context)
  end

  if mode == "mxmlc" then
    return build_mxmlc_command(context)
  end

  return build_ant_command(context, runner.target or "test")
end

function build_coverage_run(context)
  local runner = context.runner or {}

  if not runner.coverage then
    return nil
  end

  local mode = resolve_mode(context)

  if mode == "maven" then
    local mvn = ensure_tool("maven", runner)
    local args = { "test", "jacoco:report" }
    append_args(args, runner.coverage_args or runner.args)

    return {
      command = mvn,
      args = args,
      cwd = context.target_path,
      collect = runner.coverage_collect,
      report = runner.coverage_report or "target/site/jacoco/jacoco.xml",
      reporter = runner.coverage_reporter or "cobertura",
      output = runner.coverage_output or "coverage/teez.msgpack",
      min_line_rate = runner.min_line_rate,
    }
  end

  if mode == "mxmlc" then
    local spec = build_mxmlc_command(context)
    return {
      command = spec.command,
      args = spec.args,
      cwd = spec.cwd,
      env = spec.env,
      collect = runner.coverage_collect or {
        command = runner.coverage_collector or "java",
        args = runner.coverage_collector_args or { "-jar", "flexcover-reporter.jar" },
      },
      report = runner.coverage_report or "coverage/flexcover.xml",
      reporter = runner.coverage_reporter or "cobertura",
      output = runner.coverage_output or "coverage/teez.msgpack",
      min_line_rate = runner.min_line_rate,
    }
  end

  local target = runner.coverage_target or "coverage"
  local spec = build_ant_command(context, target)

  return {
    command = spec.command,
    args = spec.args,
    cwd = spec.cwd,
    env = spec.env,
    collect = runner.coverage_collect,
    report = runner.coverage_report or "coverage/cobertura.xml",
    reporter = runner.coverage_reporter or "cobertura",
    output = runner.coverage_output or "coverage/teez.msgpack",
    min_line_rate = runner.min_line_rate,
  }
end

local function parse_duration_ms(text)
  if not text then
    return nil
  end
  local seconds = tonumber(text)
  if seconds then
    return math.floor(seconds * 1000)
  end
  return nil
end

local function strip_runner_prefix(line)
  local stripped = line:match("^%[junit%]%s*(.+)$")
  if stripped then
    return stripped
  end
  stripped = line:match("^%[flexunit%]%s*(.+)$")
  if stripped then
    return stripped
  end
  return line
end

function parse_line(line)
  if not line or line == "" then
    return nil
  end

  line = strip_runner_prefix(line)

  if line:match("^OK %(%d+ tests?%)$") then
    return { event = "output", text = line }
  end

  if line:match("^Tests run: %d+, Failures: %d+, Errors: %d+") then
    return { event = "output", text = line }
  end

  local running = line:match("^Running%s+(.+)$")
  if running then
    return { event = "start", id = running }
  end

  local test_failed = line:match("^TEST%s+(%S+)%s+FAILED")
  if test_failed then
    return { event = "fail", id = test_failed, msg = line }
  end

  local test_ok = line:match("^TEST%s+(%S+)%s+OK")
  if test_ok then
    return { event = "pass", id = test_ok }
  end

  local fqcn, method, result, duration = line:match("^%s*(%S+)%.(%S+)%s+(PASSED|FAILED|ERROR)%s*%(([%d%.]+)%s*s%)")
  if not fqcn then
    fqcn, method, result = line:match("^%s*(%S+)%.(%S+)%s+(PASSED|FAILED|ERROR)")
  end
  if fqcn and method and result then
    local event = "pass"
    local msg = nil
    if result == "FAILED" or result == "ERROR" then
      event = "fail"
      msg = line
    end
    return {
      event = event,
      id = fqcn .. "." .. method,
      msg = msg,
      duration_ms = parse_duration_ms(duration),
    }
  end

  local plus_method = line:match("^%+%s+(%S+)")
  if plus_method then
    return { event = "pass", id = plus_method }
  end

  local minus_method = line:match("^%-%s+(%S+)")
  if minus_method then
    return { event = "fail", id = minus_method, msg = line }
  end

  local failure_title = line:match("^FAILURE!?%s*:?%s*(.+)$")
  if failure_title then
    return { event = "fail", id = failure_title, msg = line }
  end

  local flexunit_pass = line:match("^Test%s+fixture%s+(.+)%s+passed%.?$")
  if flexunit_pass then
    return { event = "pass", id = flexunit_pass }
  end

  local flexunit_fail = line:match("^Failure:?%s+(.+)$")
  if flexunit_fail then
    return { event = "fail", id = flexunit_fail, msg = line }
  end

  local dot_kind, dot_id = line:match("^%s*([FE])%s+(.+)$")
  if dot_kind and dot_id then
    return { event = "fail", id = dot_id, msg = line }
  end

  if line:match("^%s*%.%s*$") then
    return nil
  end

  if line:match("^Time:")
      or line:match("^There were")
      or line:match("^Expected:")
      or line:match("^Actual:")
      or line:match("^%s*at%s+") then
    return { event = "output", text = line }
  end

  return { event = "output", text = line }
end
