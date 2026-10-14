local DEFAULT_INCLUDE = { "**/*Test.m", "**/tests/**/*.m" }
local DEFAULT_EXCLUDE = { "**/*.teez.lua" }

local function runner_opts(context)
  return context.runner or {}
end

local function include_patterns(context)
  local opts = runner_opts(context)
  return opts.include or DEFAULT_INCLUDE
end

local function exclude_patterns(context)
  local opts = runner_opts(context)
  local exclude = {}
  for _, pattern in ipairs(DEFAULT_EXCLUDE) do
    table.insert(exclude, pattern)
  end
  if opts.exclude then
    for _, pattern in ipairs(opts.exclude) do
      table.insert(exclude, pattern)
    end
  end
  return exclude
end

local function is_excluded(path, patterns)
  for _, pattern in ipairs(patterns) do
    if filter.glob_match(path, pattern) then
      return true
    end
  end
  return false
end

local function rel_path(root, path)
  if path:sub(1, #root + 1) == root .. "/" then
    return path:sub(#root + 2)
  end
  if path:sub(1, #root + 1) == root .. "\\" then
    return path:sub(#root + 2):gsub("\\", "/")
  end
  return path
end

local function escape_matlab_string(value)
  return value:gsub("'", "''")
end

local function tests_folder(context)
  local opts = runner_opts(context)
  if opts.tests_folder then
    return opts.tests_folder
  end
  local root = context.target_path
  if fs.exists(root .. "/tests") then
    return "tests"
  end
  if fs.exists(root .. "/+tests") then
    return "+tests"
  end
  return "tests"
end

local function collect_tests(context)
  local include = include_patterns(context)
  local exclude = exclude_patterns(context)
  local seen = {}
  local tests = {}

  for _, pattern in ipairs(include) do
    for _, path in ipairs(fs.glob(context.target_path, pattern)) do
      if not seen[path] and not is_excluded(path, exclude) then
        seen[path] = true
        table.insert(tests, rel_path(context.target_path, path))
      end
    end
  end

  table.sort(tests)
  return tests
end

local function filter_tests(tests, filters)
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

local function runtests_script(context)
  local tests = filter_tests(collect_tests(context), context.filters)

  if #tests == 1 then
    local test_path = escape_matlab_string(tests[1])
    return "runtests(which('" .. test_path .. "'))"
  end

  if #tests > 1 then
    local entries = {}
    for _, test_path in ipairs(tests) do
      table.insert(entries, "which('" .. escape_matlab_string(test_path) .. "')")
    end
    return "runtests([" .. table.concat(entries, ", ") .. "])"
  end

  local folder = escape_matlab_string(tests_folder(context))
  return "runtests('" .. folder .. "')"
end

local function matlab_batch(script)
  return {
    command = "matlab",
    args = { "-batch", script },
  }
end

function list(context)
  return filter_tests(collect_tests(context), context.filters)
end

function build_command(context)
  local opts = runner_opts(context)
  local script = runtests_script(context)

  if opts.matlab_script then
    script = opts.matlab_script
  elseif opts.prelude then
    script = opts.prelude .. "; " .. script
  end

  local spec = matlab_batch(script)

  if opts.args then
    for _, arg in ipairs(opts.args) do
      table.insert(spec.args, arg)
    end
  end

  if opts.env then
    spec.env = opts.env
  end

  if opts.cwd then
    spec.cwd = opts.cwd
  end

  return spec
end

function parse_line(line)
  if line == nil or line == "" then
    return nil
  end

  local trimmed = line:match("^%s*(.-)%s*$")

  local passed = trimmed:match("^Passed%s+(%S+/%S+)")
  if passed then
    return { event = "pass", id = passed }
  end

  local failed = trimmed:match("^Failed%s+(%S+/%S+)")
    or trimmed:match("^Failed:%s*(%S+/%S+)")
  if failed then
    return { event = "fail", id = failed, msg = trimmed }
  end

  local failure_in = trimmed:match("^Failure in%s+(%S+/%S+)")
  if failure_in then
    return { event = "fail", id = failure_in, msg = trimmed }
  end

  local error_in = trimmed:match("^Error occurred in%s+(%S+)")
  if error_in then
    return { event = "fail", id = error_in, msg = trimmed }
  end

  local running_test = trimmed:match("^Running%s+(%S+/%S+)")
  if running_test then
    return { event = "start", id = running_test }
  end

  local running_class = trimmed:match("^Running%s+(%S+)$")
  if running_class then
    return { event = "start", id = running_class }
  end

  local done_class = trimmed:match("^Done%s+(%S+)")
  if done_class then
    return { event = "pass", id = done_class }
  end

  local summary_passed, summary_total = trimmed:match("^(%d+)%s+Passed,%s+(%d+)%s+Total")
  if summary_passed and summary_total then
    return { event = "output", text = trimmed }
  end

  return { event = "output", text = trimmed }
end

function build_coverage_run(context)
  local opts = runner_opts(context)
  if not opts.coverage then
    return nil
  end

  local folder = escape_matlab_string(tests_folder(context))
  local report = type(opts.coverage) == "string" and opts.coverage or "coverage/matlab.cov"
  local source = escape_matlab_string(opts.coverage_source or ".")
  local script = table.concat({
    "import matlab.unittest.plugins.CodeCoveragePlugin;",
    "import matlab.unittest.plugins.codecoverage.CoberturaFormat;",
    "reportFile = '" .. escape_matlab_string(report) .. "';",
    "sourceFolder = '" .. source .. "';",
    "suite = testsuite('" .. folder .. "');",
    "runner = testrunner;",
    "runner.addPlugin(CodeCoveragePlugin.forFolder(sourceFolder, 'IncludingSubfolders', true, 'Producing', CoberturaFormat(reportFile)));",
    "results = runner.run(suite);",
    "assertSuccess(results);",
  }, " ")

  local spec = matlab_batch(script)
  spec.report = report
  spec.reporter = "cobertura"
  spec.output = opts.coverage_output or "coverage/teez.msgpack"

  if opts.coverage_min_line_rate then
    spec.min_line_rate = opts.coverage_min_line_rate
  end

  if opts.cwd then
    spec.cwd = opts.cwd
  end

  return spec
end
