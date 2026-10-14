-- teez runner for Wolfram Language UnitTesting (`UnitTesting` package)

local DEFAULT_INCLUDE = {
  "**/Tests/**",
  "**/*Test*.wl",
}

local DEFAULT_EXCLUDE = {
  "**/*.teez.lua",
}

local TEST_GLOBS = {
  "**/Test*.wl",
  "**/Tests/**/*.wl",
}

local WOLFRAM_COMMANDS = { "wolframscript", "math", "wolfram" }

local PROJECT_RUNNERS = {
  "run-tests.wl",
  "scripts/run-tests.wl",
  "Tests/run-tests.wl",
}

local function normalize_path(path)
  return path:gsub("\\", "/")
end

local function merge_patterns(context)
  local include = {}
  local exclude = {}

  for _, pattern in ipairs(DEFAULT_INCLUDE) do
    table.insert(include, pattern)
  end
  if context.runner and context.runner.include then
    for _, pattern in ipairs(context.runner.include) do
      table.insert(include, pattern)
    end
  end

  for _, pattern in ipairs(DEFAULT_EXCLUDE) do
    table.insert(exclude, pattern)
  end
  if context.runner and context.runner.exclude then
    for _, pattern in ipairs(context.runner.exclude) do
      table.insert(exclude, pattern)
    end
  end

  return include, exclude
end

local function is_excluded(path, exclude_patterns)
  for _, pattern in ipairs(exclude_patterns) do
    if filter.glob_match(path, pattern) then
      return true
    end
  end
  return false
end

local function is_included(path, include_patterns)
  for _, pattern in ipairs(include_patterns) do
    if filter.glob_match(path, pattern) then
      return true
    end
  end
  return false
end

local function resolve_wolfram_command()
  for _, name in ipairs(WOLFRAM_COMMANDS) do
    local result = sys.run("which", { name })
    if result.exit_code == 0 and result.stdout and result.stdout:match("%S") then
      return name
    end
  end
  error("wolfram runner requires wolframscript or math on PATH")
end

local function discover_test_files(context)
  local include_patterns, exclude_patterns = merge_patterns(context)
  local tests = {}
  local seen = {}
  local globs = TEST_GLOBS

  if context.runner and context.runner.test_glob then
    globs = { context.runner.test_glob }
  end

  for _, pattern in ipairs(globs) do
    local files = fs.glob(context.target_path, pattern)
    for _, file in ipairs(files) do
      local rel = normalize_path(file)
      if not is_excluded(rel, exclude_patterns) and is_included(rel, include_patterns) then
        if not seen[rel] then
          seen[rel] = true
          table.insert(tests, rel)
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

function list(context)
  return apply_filters(discover_test_files(context), context)
end

local function escape_wl_string(value)
  return value:gsub("\\", "\\\\"):gsub("\"", "\\\"")
end

local function write_temp_script(content)
  local tmp = os.getenv("TMPDIR") or os.getenv("TEMP") or "/tmp"
  local path = tmp .. "/teez-wolfram-" .. tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999)) .. ".wl"
  local handle = io.open(path, "w")
  if not handle then
    error("failed to create temporary wolfram runner script")
  end
  handle:write(content)
  handle:close()
  return path
end

local function tests_dir(context)
  if context.runner and context.runner.tests_dir then
    return context.runner.tests_dir
  end
  return "Tests"
end

local function build_test_target_expression(context, test_targets)
  if #test_targets == 0 then
    return "\"" .. escape_wl_string(tests_dir(context)) .. "\""
  end
  if #test_targets == 1 then
    return "\"" .. escape_wl_string(test_targets[1]) .. "\""
  end

  local parts = {}
  for _, target in ipairs(test_targets) do
    table.insert(parts, "\"" .. escape_wl_string(target) .. "\"")
  end
  return "{" .. table.concat(parts, ", ") .. "}"
end

local function build_runner_script(context, test_targets, with_coverage)
  local target = escape_wl_string(context.target_path)
  local test_target = build_test_target_expression(context, test_targets)
  local lines = {
    "(* teez wolfram runner - generated *)",
    "SetDirectory[\"" .. target .. "\"];",
    "Needs[\"UnitTesting`\"];",
  }

  if with_coverage then
    table.insert(lines, "coverageFile = FileNameJoin[{\"" .. target .. "\", \"coverage\", \"wolfram-coverage.json\"}];")
    table.insert(lines, "CreateDirectory[DirectoryName[coverageFile]];")
    table.insert(lines, "coverageEnabled = True;")
    table.insert(lines, "If[!MemberQ[$Packages, \"CodeCoverageTools`\"],")
    table.insert(lines, "  Quiet[Needs[\"CodeCoverageTools`\"]];")
    table.insert(lines, "  If[!MemberQ[$Packages, \"CodeCoverageTools`\"], coverageEnabled = False];")
    table.insert(lines, "];")
    table.insert(lines, "If[coverageEnabled,")
    table.insert(lines, "  coverage = BeginCodeCoverage[];")
    table.insert(lines, "  summary = TestRun[" .. test_target .. ", Verbose -> False];")
    table.insert(lines, "  coverageData = EndCodeCoverage[coverage];")
    table.insert(lines, "  Export[coverageFile, coverageData, \"JSON\"];")
    table.insert(lines, ",")
    table.insert(lines, "  summary = TestRun[" .. test_target .. ", Verbose -> False];")
    table.insert(lines, "];")
  else
    table.insert(lines, "summary = TestRun[" .. test_target .. ", Verbose -> False];")
  end

  table.insert(lines, "If[!MatchQ[summary, _TestSummaryObject],")
  table.insert(lines, "  Print[\"TEEZ_ERROR: TestRun did not return TestSummaryObject\"];")
  table.insert(lines, "  Quit[1];")
  table.insert(lines, "];")
  table.insert(lines, "Print[\"Test Summary\"];")
  table.insert(lines, "Print[\"Tests run: \", summary[\"TestsRunCount\"]];")
  table.insert(lines, "Print[\"Tests succeeded: \", summary[\"TestsSucceededCount\"]];")
  table.insert(lines, "Print[\"Tests failed: \", summary[\"TestsFailedCount\"]];")
  table.insert(lines, "Print[\"Tests with errors: \", summary[\"TestsWithErrorsCount\"]];")
  table.insert(lines, "results = If[KeyExistsQ[summary, \"Tests\"], summary[\"Tests\"],")
  table.insert(lines, "  If[KeyExistsQ[summary, \"Results\"], summary[\"Results\"], {}]];")
  table.insert(lines, "Do[")
  table.insert(lines, "  Which[")
  table.insert(lines, "    MatchQ[result, _SuccessTestResult], Print[\"Success   \", result[\"TestID\"]],")
  table.insert(lines, "    MatchQ[result, _FailureTestResult],")
  table.insert(lines, "      Print[\"Failure   \", result[\"TestID\"], \"   \", ToString[result[\"FailureMessage\"], InputForm]],")
  table.insert(lines, "    MatchQ[result, _ErrorTestResult],")
  table.insert(lines, "      Print[\"Error     \", result[\"TestID\"], \"   \", ToString[result[\"Messages\"], InputForm]],")
  table.insert(lines, "    MatchQ[result, _SkipTestResult], Print[\"Skipped   \", result[\"TestID\"]],")
  table.insert(lines, "    True, Nothing")
  table.insert(lines, "  ],")
  table.insert(lines, "  {result, results}")
  table.insert(lines, "];")
  table.insert(lines, "If[summary[\"TestsFailedCount\"] > 0 || summary[\"TestsWithErrorsCount\"] > 0, Quit[1], Quit[0]];")

  return table.concat(lines, "\n")
end

local function find_project_runner(target_path)
  for _, rel in ipairs(PROJECT_RUNNERS) do
    local path = target_path .. "/" .. rel
    if fs.exists(path) then
      return rel
    end
  end
  return nil
end

local function coverage_enabled(context)
  return context.runner and context.runner.coverage
end

local function build_wolfram_command(context, with_coverage)
  local wolfram = resolve_wolfram_command()
  local args = {}

  if not with_coverage then
    local project_runner = find_project_runner(context.target_path)
    if project_runner then
      args = { "-file", project_runner }
      if context.runner and context.runner.args then
        for _, arg in ipairs(context.runner.args) do
          table.insert(args, arg)
        end
      end
      return {
        command = wolfram,
        args = args,
        cwd = context.target_path,
      }
    end
  end

  local tests = apply_filters(discover_test_files(context), context)
  local script_path = write_temp_script(build_runner_script(context, tests, with_coverage))
  args = { "-file", script_path }

  if context.runner and context.runner.args then
    for _, arg in ipairs(context.runner.args) do
      table.insert(args, arg)
    end
  end

  return {
    command = wolfram,
    args = args,
    cwd = context.target_path,
  }
end

function build_command(context)
  return build_wolfram_command(context, coverage_enabled(context))
end

function build_coverage_run(context)
  if not coverage_enabled(context) then
    return nil
  end

  local spec = build_wolfram_command(context, true)
  local min_line_rate = nil
  if context.runner then
    min_line_rate = context.runner.min_line_rate or context.runner.coverage_min_line_rate
  end

  return {
    command = spec.command,
    args = spec.args,
    cwd = spec.cwd,
    env = spec.env,
    report = "coverage/wolfram-coverage.json",
    reporter = "json",
    output = "coverage/teez.msgpack",
    min_line_rate = min_line_rate,
  }
end

function parse_line(line)
  if line == "" then
    return nil
  end

  local id, msg

  id, msg = line:match("^%s*|?%s*Success%s+(.+)%s*$")
  if id then
    return { event = "pass", id = id }
  end

  id, msg = line:match("^%s*|?%s*Failure%s+(.+)%s+(.+)%s*$")
  if id then
    return { event = "fail", id = id, msg = msg }
  end

  id = line:match("^%s*|?%s*Failure%s+(.+)%s*$")
  if id then
    return { event = "fail", id = id, msg = line }
  end

  id, msg = line:match("^%s*|?%s*Error%s+(.+)%s+(.+)%s*$")
  if id then
    return { event = "fail", id = id, msg = msg }
  end

  id = line:match("^%s*|?%s*Skipped%s+(.+)%s*$")
  if id then
    return { event = "skip", id = id }
  end

  if line:match("^Test Summary")
      or line:match("^Tests run:")
      or line:match("^Tests succeeded:")
      or line:match("^Tests failed:")
      or line:match("^Tests with errors:")
      or line:match("^TEEZ_ERROR:")
  then
    return { event = "output", text = line }
  end

  return { event = "output", text = line }
end
