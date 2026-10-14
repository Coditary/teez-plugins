local function runner_config(context)
  return (context and context.runner) or {}
end

local function append_args(args, extra)
  if not extra then
    return
  end
  if type(extra) == "string" then
    table.insert(args, extra)
    return
  end
  for _, value in ipairs(extra) do
    table.insert(args, value)
  end
end

local function resolve_target(context)
  local runner = runner_config(context)
  if runner.project then
    return runner.project
  end
  if runner.solution then
    return runner.solution
  end

  local root = context.target_path
  local solutions = fs.glob(root, "*.sln")
  if #solutions == 1 then
    return solutions[1]
  end
  if #solutions > 1 then
    table.sort(solutions)
    return solutions[1]
  end

  local projects = fs.glob(root, "*.csproj")
  if #projects == 1 then
    return projects[1]
  end
  if #projects > 1 then
    local test_projects = {}
    for _, project in ipairs(projects) do
      if project:match("[Tt]ests%.csproj$") or project:match("%.Tests%.csproj$") then
        table.insert(test_projects, project)
      end
    end
    if #test_projects == 1 then
      return test_projects[1]
    end
    if #test_projects > 1 then
      table.sort(test_projects)
      return test_projects[1]
    end
    table.sort(projects)
    return projects[1]
  end

  return "."
end

local function include_patterns(context)
  local runner = runner_config(context)
  if runner.include then
    return runner.include
  end
  return { "**/*Tests.cs", "**/*.Tests/**" }
end

local function exclude_patterns(context)
  local runner = runner_config(context)
  if runner.exclude then
    return runner.exclude
  end
  return {}
end

local function matches_any_pattern(value, patterns)
  for _, pattern in ipairs(patterns) do
    if filter.glob_match(value, pattern) or filter.glob_match(value:gsub("%.", "/"), pattern) then
      return true
    end
  end
  return false
end

local function test_id_allowed(id, context)
  local includes = include_patterns(context)
  local excludes = exclude_patterns(context)

  if #excludes > 0 and matches_any_pattern(id, excludes) then
    return false
  end
  if #includes == 0 then
    return true
  end
  return matches_any_pattern(id, includes)
end

local function build_filter_expression(context)
  local runner = runner_config(context)
  if runner.filter and runner.filter ~= "" then
    return runner.filter
  end

  if not context.filters then
    return nil
  end

  local parts = {}
  if context.filters.names then
    for _, name in ipairs(context.filters.names) do
      table.insert(parts, "FullyQualifiedName~" .. name)
    end
  end
  if context.filters.pattern then
    table.insert(parts, "FullyQualifiedName~" .. context.filters.pattern)
  end
  if context.filters.id then
    table.insert(parts, "FullyQualifiedName=" .. context.filters.id)
  end

  if #parts == 0 then
    return nil
  end
  if #parts == 1 then
    return parts[1]
  end
  return table.concat(parts, "|")
end

local function base_args(context, target)
  local args = { "test", target, "--nologo" }
  local runner = runner_config(context)

  if runner.configuration then
    table.insert(args, "--configuration")
    table.insert(args, runner.configuration)
  end
  if runner.framework then
    table.insert(args, "--framework")
    table.insert(args, runner.framework)
  end
  if runner.no_build then
    table.insert(args, "--no-build")
  end

  local filter_expr = build_filter_expression(context)
  if filter_expr then
    table.insert(args, "--filter")
    table.insert(args, filter_expr)
  end

  append_args(args, runner.args)
  return args
end

local function parse_list_output(output, context)
  local tests = {}
  local seen = {}

  for line in output:gmatch("[^\r\n]+") do
    local id = line:match("^%s+(%S.+)$")
    if id and not id:match("^The following") and id ~= "No test is available" then
      if test_id_allowed(id, context) then
        if context.filters then
          if filter.matches({ id = id }, context.filters) then
            if not seen[id] then
              seen[id] = true
              table.insert(tests, id)
            end
          end
        elseif not seen[id] then
          seen[id] = true
          table.insert(tests, id)
        end
      end
    end
  end

  return tests
end

function list(context)
  local target = resolve_target(context)
  local args = base_args(context, target)
  table.insert(args, "--list-tests")

  local output = sys.exec("dotnet", args, { cwd = context.target_path })
  return parse_list_output(output, context)
end

function build_command(context)
  local target = resolve_target(context)
  local args = base_args(context, target)
  table.insert(args, "--logger")
  table.insert(args, "console;verbosity=detailed")

  return {
    command = "dotnet",
    args = args,
    cwd = context.target_path,
  }
end

function build_coverage_run(context)
  local target = resolve_target(context)
  local args = base_args(context, target)
  table.insert(args, '--collect:"XPlat Code Coverage"')
  table.insert(args, "--results-directory")
  table.insert(args, runner_config(context).results_directory or "TestResults")

  return {
    command = "dotnet",
    args = args,
    cwd = context.target_path,
    report = "TestResults/**/coverage.cobertura.xml",
    reporter = "cobertura",
    output = "coverage/coverage.cobertura.xml",
  }
end

local function map_status(status)
  if status == "Passed" then
    return "pass"
  end
  if status == "Failed" then
    return "fail"
  end
  if status == "Skipped" then
    return "skip"
  end
  return nil
end

local ignored_line_patterns = {
  "^Test run for ",
  "^Total tests:",
  "^Passed:%s",
  "^Failed:%s",
  "^Skipped:%s",
  "^Starting test execution",
  "^A total of ",
  "^Microsoft %(R%)",
  "^Build started",
  "^Build succeeded%.?",
  "^Build FAILED%.?",
  "^Determining projects to restore",
  "^All projects are up%-to%-date",
  "^VSTest version ",
  "^Results File:",
  "^Attachments:",
  "^  %d+ Warning",
  "^  %d+ Error",
  "^Time Elapsed ",
}

local function is_ignored_line(line)
  for _, pattern in ipairs(ignored_line_patterns) do
    if line:match(pattern) then
      return true
    end
  end
  return false
end

function parse_line(line)
  local status, name, duration = line:match("^%s*(Passed|Failed|Skipped)%s+(.-)%s+%[(%d+) ms%]%s*$")
  if status and name then
    local event = map_status(status)
    if event then
      local result = { event = event, id = name, duration_ms = tonumber(duration) }
      if event == "fail" then
        result.msg = "Failed " .. name
      end
      return result
    end
  end

  status, name = line:match("^%s*(Passed|Failed|Skipped)%s+(.-)%s*$")
  if status and name and not name:match("^%[") then
    local event = map_status(status)
    if event then
      local result = { event = event, id = name }
      if event == "fail" then
        result.msg = "Failed " .. name
      end
      return result
    end
  end

  if is_ignored_line(line) or not line:match("%S") then
    return nil
  end

  if line:match("^%s*Error Message:%s*$")
      or line:match("^%s*Stack Trace:%s*$")
      or line:match("^%s*Assert%.")
      or line:match("^%s*at %S")
      or line:match("^%s*Expected:")
      or line:match("^%s*But was:")
      or line:match("^%s*Standard Output Messages:")
  then
    return { event = "output", text = line }
  end

  return nil
end
