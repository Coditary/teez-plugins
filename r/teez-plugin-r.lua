-- teez R / testthat adapter

local DEFAULT_TEST_DIR = "tests/testthat"
local TEST_FILE_PATTERNS = { "test-*.R", "test_*.R", "test*.R" }

local function target_path(context)
  return context.target_path or "."
end

local function runner_cfg(context)
  if type(context.runner) == "table" then
    return context.runner
  end
  return {}
end

local function join_path(root, child)
  if child:sub(1, 1) == "/" then
    return child
  end
  return root .. "/" .. child
end

local function resolve_test_dir(context)
  local target = target_path(context)
  local cfg = runner_cfg(context)

  if type(cfg.test_dir) == "string" and cfg.test_dir ~= "" then
    if cfg.test_dir:sub(1, 1) == "/" then
      return cfg.test_dir
    end
    return join_path(target, cfg.test_dir)
  end

  if fs.exists(join_path(target, "tests/testthat")) then
    return join_path(target, "tests/testthat")
  end

  if fs.exists(join_path(target, "testthat")) then
    return join_path(target, "testthat")
  end

  return join_path(target, DEFAULT_TEST_DIR)
end

local function relative_test_dir(context)
  local target = target_path(context)
  local test_dir = resolve_test_dir(context)
  local prefix = target .. "/"
  if test_dir:sub(1, #prefix) == prefix then
    return test_dir:sub(#prefix + 1)
  end
  return test_dir
end

local function path_excluded(path, pattern)
  return filter.glob_match(path, pattern)
end

local function should_include_test(path, context)
  local cfg = runner_cfg(context)

  if cfg.include then
    local matched = false
    for _, pattern in ipairs(cfg.include) do
      if filter.glob_match(path, pattern) then
        matched = true
        break
      end
    end
    if not matched then
      return false
    end
  end

  if cfg.exclude then
    for _, pattern in ipairs(cfg.exclude) do
      if path_excluded(path, pattern) then
        return false
      end
    end
  end

  return true
end

local function test_id_for_file(context, test_dir, file)
  local target = target_path(context)
  local absolute = join_path(test_dir, file)
  local prefix = target .. "/"
  if absolute:sub(1, #prefix) == prefix then
    return absolute:sub(#prefix + 1)
  end
  return absolute
end

local function collect_test_files(context)
  local test_dir = resolve_test_dir(context)
  if not fs.exists(test_dir) then
    return {}
  end

  local tests = {}
  local seen = {}
  for _, pattern in ipairs(TEST_FILE_PATTERNS) do
    for _, file in ipairs(fs.glob(test_dir, pattern)) do
      local id = test_id_for_file(context, test_dir, file)
      if should_include_test(id, context) and not seen[id] then
        seen[id] = true
        table.insert(tests, id)
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

local function r_quote(value)
  return string.format("%q", value)
end

local function append_runner_filter(r_code, context)
  local cfg = runner_cfg(context)
  if type(cfg.filter) == "string" and cfg.filter ~= "" then
    return r_code .. ", filter = " .. r_quote(cfg.filter)
  end
  if type(cfg.pattern) == "string" and cfg.pattern ~= "" then
    return r_code .. ", filter = " .. r_quote(cfg.pattern)
  end
  return r_code
end

local function build_testthat_code(context)
  local rel_dir = relative_test_dir(context)
  local code = "testthat::test_dir("
    .. r_quote(rel_dir)
    .. ', reporter = "Tap", stop_on_failure = FALSE'
  code = append_runner_filter(code, context)
  return code .. ")"
end

local function build_devtools_code(context)
  local code = 'devtools::test(reporter = "Tap", stop_on_failure = FALSE'
  code = append_runner_filter(code, context)
  return code .. ")"
end

local function build_run_expression(context)
  local cfg = runner_cfg(context)
  local body

  if cfg.use_devtools then
    body = table.concat({
      'if (!requireNamespace("devtools", quietly = TRUE)) stop("devtools not installed")',
      build_devtools_code(context),
    }, "\n")
  else
    body = table.concat({
      'if (!requireNamespace("testthat", quietly = TRUE)) stop("testthat not installed")',
      build_testthat_code(context),
    }, "\n")
  end

  return body
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

local function coverage_cfg(context)
  local cfg = runner_cfg(context)
  local from_runner = type(cfg.coverage) == "table" and cfg.coverage or {}
  local from_global = type(config) == "table" and type(config.coverage) == "table" and config.coverage
    or {}
  return shallow_merge(from_global, from_runner)
end

function list(context)
  return apply_filters(collect_test_files(context), context)
end

function build_command(context)
  local spec = {
    command = "Rscript",
    args = { "-e", build_run_expression(context) },
    cwd = target_path(context),
  }

  local cfg = runner_cfg(context)
  if cfg.env then
    spec.env = cfg.env
  end

  return spec
end

function parse_line(line)
  if line:match("^%d+%.%.%d+$") then
    return nil
  end

  if line:match("^# Context ") then
    return nil
  end

  local skip_reason = line:match("^ok %d+ #%s*SKIP%s+(.*)$")
  if skip_reason then
    return { event = "skip", id = skip_reason }
  end

  if line:match("^ok %d+ #%s*WARNING") then
    local detail = line:match("^ok %d+ #%s*WARNING%s+(.*)$") or "warning"
    return { event = "pass", id = detail }
  end

  local pass_id = line:match("^ok %d+ (.+)$")
  if pass_id and not line:match("^ok %d+ #") then
    return { event = "pass", id = pass_id }
  end

  local fail_id = line:match("^not ok %d+ (.+)$")
  if fail_id then
    return { event = "fail", id = fail_id, msg = fail_id }
  end

  if line:match("^[#%s]") then
    return { event = "output", text = line }
  end

  return nil
end

function build_coverage_run(context)
  local cfg = runner_cfg(context)
  if cfg.coverage == false then
    return nil
  end

  local cov = coverage_cfg(context)
  local report = cov.report or "coverage/cobertura.xml"
  local output = cov.output or "coverage/teez.msgpack"
  local reporter = cov.reporter or "cobertura"
  local coverage_type = cov.type or "tests"

  local expression = table.concat({
    'if (!requireNamespace("covr", quietly = TRUE)) stop("covr not installed")',
    'if (!requireNamespace("xml2", quietly = TRUE)) stop("xml2 not installed (required by covr::to_cobertura)")',
    'dir.create("coverage", recursive = TRUE, showWarnings = FALSE)',
    "cov <- covr::package_coverage(path = ., type = " .. r_quote(coverage_type) .. ", quiet = TRUE)",
    "covr::to_cobertura(cov, filename = " .. r_quote(report) .. ")",
  }, "\n")

  local spec = {
    command = "Rscript",
    args = { "-e", expression },
    cwd = target_path(context),
    report = report,
    reporter = reporter,
    output = output,
  }

  if cov.min_line_rate then
    spec.min_line_rate = cov.min_line_rate
  end

  return spec
end
