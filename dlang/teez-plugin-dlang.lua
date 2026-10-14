-- teez D adapter (dub test / dmd -unittest)

local DEFAULT_INCLUDE = { "**/*.d" }
local DEFAULT_EXCLUDE = { "**/*.teez.lua" }

local last_failed_id = nil

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

local function coverage_cfg(context)
  local cfg = runner_cfg(context)
  local from_runner = type(cfg.coverage) == "table" and cfg.coverage or {}
  local from_global = type(config) == "table" and type(config.coverage) == "table" and config.coverage
    or {}
  return shallow_merge(from_global, from_runner)
end

local function default_coverage_cfg()
  return {
    tool = "gcovr",
    build_type = "unittest-coverage",
    report = "coverage/lcov.info",
    output = "coverage/teez.msgpack",
    reporter = "msgpack",
  }
end

local function effective_coverage_cfg(context)
  return shallow_merge(default_coverage_cfg(), coverage_cfg(context))
end

local function target_path(context)
  return context.target_path or "."
end

local function resolve_glob_hit(root, file)
  if file:sub(1, 1) == "/" then
    return file
  end
  if root == "." or root == "" then
    return file
  end
  return root .. "/" .. file
end

local function include_patterns(context)
  local cfg = runner_cfg(context)
  if cfg.include then
    return cfg.include
  end
  return DEFAULT_INCLUDE
end

local function exclude_patterns(context)
  local cfg = runner_cfg(context)
  local exclude = {}
  for _, pattern in ipairs(DEFAULT_EXCLUDE) do
    table.insert(exclude, pattern)
  end
  if cfg.exclude then
    for _, pattern in ipairs(cfg.exclude) do
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

local function find_dub_root(start_path)
  local path = start_path or "."
  if path == "" then
    path = "."
  end

  local current = path
  for _ = 1, 32 do
    if fs.exists(current .. "/dub.json") or fs.exists(current .. "/dub.sdl") then
      return current
    end

    if current == "." or current == "/" then
      break
    end

    local parent = current:match("^(.*)/[^/]+$")
    if not parent or parent == current then
      parent = "."
    end
    current = parent
  end

  return start_path or "."
end

local function has_dub_project(target)
  return fs.exists(target .. "/dub.json") or fs.exists(target .. "/dub.sdl")
end

local function run_mode(context)
  local cfg = runner_cfg(context)
  if cfg.run_mode then
    return cfg.run_mode
  end
  return "auto"
end

local function should_use_dub(context)
  local mode = run_mode(context)
  if mode == "dmd" then
    return false
  end
  if mode == "dub" then
    return true
  end
  return has_dub_project(find_dub_root(target_path(context)))
end

local function append_args(args, extra)
  if not extra then
    return
  end
  for _, value in ipairs(extra) do
    table.insert(args, value)
  end
end

local function append_runner_args(args, context)
  local cfg = runner_cfg(context)
  append_args(args, cfg.args)
end

local function test_id(file, line_no, name)
  if name and name ~= "" then
    return file .. ":" .. line_no .. "::" .. name
  end
  return file .. ":" .. line_no
end

local function apply_filters(ids, filters)
  if not filters then
    return ids
  end

  local filtered = {}
  for _, id in ipairs(ids) do
    if filter.matches({ id = id }, filters) then
      table.insert(filtered, id)
    end
  end
  return filtered
end

local function collect_source_files(context)
  local target = target_path(context)
  local includes = include_patterns(context)
  local excludes = exclude_patterns(context)
  local files = {}
  local seen = {}

  for _, pattern in ipairs(includes) do
    for _, file in ipairs(fs.glob(target, pattern)) do
      local resolved = resolve_glob_hit(target, file)
      if not is_excluded(resolved, excludes) and not seen[resolved] then
        seen[resolved] = true
        table.insert(files, resolved)
      end
    end
  end

  table.sort(files)
  return files
end

local function parse_grep_unittest_line(line, root)
  local path, line_no = line:match("^([^:]+):(%d+):")
  if not path or not line_no then
    return nil
  end

  if not path:match("%.d$") then
    return nil
  end

  local relative = path
  if root and root ~= "." and path:sub(1, #root + 1) == root .. "/" then
    relative = path:sub(#root + 2)
  end

  return test_id(relative, line_no)
end

local function discover_unittests_from_sources(context)
  local root = find_dub_root(target_path(context))
  local result = sys.run("grep", {
    "-R",
    "-n",
    "-E",
    "unittest\\s*(\\{|\\b)",
    "--include=*.d",
    ".",
  }, { cwd = root })

  local tests = {}
  local seen = {}

  if result.exit_code == 0 or result.exit_code == 1 then
    for line in result.stdout:gmatch("[^\r\n]+") do
      local id = parse_grep_unittest_line(line, root)
      if id and not seen[id] then
        seen[id] = true
        table.insert(tests, id)
      end
    end
  end

  table.sort(tests)
  return tests
end

local function parse_dub_verbose_listing(output)
  local tests = {}
  local seen = {}

  for line in output:gmatch("[^\r\n]+") do
    local file, line_no, name = line:match("^%s*(%S+%.d):(%d+):.*unittest%s+(%S+)")
    if file and line_no and name and name ~= "FAILED" and name ~= "PASS" then
      local id = test_id(file, line_no, name)
      if not seen[id] then
        seen[id] = true
        table.insert(tests, id)
      end
    end

    local pass_file, pass_line = line:match("^%s*(%S+%.d):(%d+):.*unittest%s+PASS")
    if pass_file and pass_line then
      local id = test_id(pass_file, pass_line)
      if not seen[id] then
        seen[id] = true
        table.insert(tests, id)
      end
    end
  end

  table.sort(tests)
  return tests
end

local function list_from_dub_verbose(context)
  local root = find_dub_root(target_path(context))
  local args = { "test", "--verbose", "--", "-v" }
  append_runner_args(args, context)

  local result = sys.run("dub", args, { cwd = root })
  if result.exit_code ~= 0 and trim(result.stdout) == "" then
    return {}
  end

  return parse_dub_verbose_listing(result.stdout)
end

local function collect_tests(context)
  local cfg = runner_cfg(context)
  local list_mode = cfg.list_mode or "discovery"

  if list_mode == "dub" and should_use_dub(context) then
    local from_dub = list_from_dub_verbose(context)
    if #from_dub > 0 then
      return from_dub
    end
  end

  local from_sources = discover_unittests_from_sources(context)
  if #from_sources > 0 then
    return from_sources
  end

  return collect_source_files(context)
end

local function build_dub_test_args(context, coverage)
  local args = { "test" }
  local cfg = runner_cfg(context)

  if cfg.verbose ~= false then
    table.insert(args, "--verbose")
  end

  if coverage then
    local cov = effective_coverage_cfg(context)
    local build_type = cov.build_type
    if build_type and build_type ~= "" then
      table.insert(args, "--build=" .. build_type)
    end
    append_args(args, cov.dub_args)
  end

  append_runner_args(args, context)

  if cfg.unittest_args then
    table.insert(args, "--")
    append_args(args, cfg.unittest_args)
  elseif cfg.verbose ~= false then
    table.insert(args, "--")
    table.insert(args, "-v")
  end

  return args
end

local function build_dmd_args(context, coverage)
  local cfg = runner_cfg(context)
  local compiler = cfg.compiler or "dmd"
  local args = { "-unittest" }

  if coverage then
    local cov = effective_coverage_cfg(context)
    if cov.dflags then
      append_args(args, cov.dflags)
    else
      table.insert(args, "-cov")
    end
  end

  append_args(args, cfg.dflags)
  append_args(args, cfg.dmd_args)

  if cfg.sources then
    append_args(args, cfg.sources)
  else
    for _, file in ipairs(collect_source_files(context)) do
      table.insert(args, file)
    end
  end

  if #args == (coverage and 2 or 1) then
    table.insert(args, ".")
  end

  return args, compiler
end

local function build_coverage_collect(context, cov)
  if type(cov.collect) == "table" and cov.collect.command then
    return cov.collect
  end

  local tool = cov.tool or "gcovr"
  local root = find_dub_root(target_path(context))
  local report = cov.report or "coverage/lcov.info"

  if tool == "lst" then
    return {
      command = "sh",
      args = {
        "-c",
        "mkdir -p coverage && find . -name '*.lst' -type f | sort | xargs -r cat > "
          .. report,
      },
    }
  end

  if tool == "llvm-cov" then
    return {
      command = "sh",
      args = {
        "-c",
        "llvm-profdata merge -sparse default.profraw -o default.profdata && "
          .. "llvm-cov export -instr-profile=default.profdata "
          .. (cov.binary or "app") .. " -format=lcov > " .. report,
      },
    }
  end

  local gcovr_args = cov.collect_args or {
    "--root",
    root,
    "--exclude-unreachable-branches",
    "--exclude-throw-branches",
    "--print-summary",
    "-o",
    report,
  }

  return {
    command = "gcovr",
    args = gcovr_args,
  }
end

function list(context)
  return apply_filters(collect_tests(context), context.filters)
end

function build_command(context)
  last_failed_id = nil

  if should_use_dub(context) then
    return {
      command = "dub",
      args = build_dub_test_args(context, false),
      cwd = find_dub_root(target_path(context)),
    }
  end

  local args, compiler = build_dmd_args(context, false)
  return {
    command = compiler,
    args = args,
    cwd = find_dub_root(target_path(context)),
  }
end

function build_coverage_run(context)
  last_failed_id = nil
  local cov = effective_coverage_cfg(context)
  local root = find_dub_root(target_path(context))
  local report = cov.report or "coverage/lcov.info"
  local output = cov.output or "coverage/teez.msgpack"
  local reporter = cov.reporter or "msgpack"

  if should_use_dub(context) then
    return {
      command = "dub",
      args = build_dub_test_args(context, true),
      cwd = root,
      collect = build_coverage_collect(context, cov),
      report = report,
      reporter = reporter,
      output = output,
      min_line_rate = cov.min_line_rate,
    }
  end

  local args, compiler = build_dmd_args(context, true)
  return {
    command = compiler,
    args = args,
    cwd = root,
    collect = build_coverage_collect(context, cov),
    report = report,
    reporter = reporter,
    output = output,
    min_line_rate = cov.min_line_rate,
  }
end

function parse_line(line)
  line = trim(line)
  if line == "" then
    return nil
  end

  local pass_file, pass_line, pass_name = line:match("^(%S+%.d):(%d+):.*unittest%s+(%S+)")
  if pass_file and pass_line and pass_name then
    if pass_name == "PASS" then
      last_failed_id = nil
      return { event = "pass", id = test_id(pass_file, pass_line) }
    end
    if pass_name ~= "FAILED" then
      last_failed_id = nil
      return { event = "pass", id = test_id(pass_file, pass_line, pass_name) }
    end
  end

  local fail_file, fail_line = line:match("^(%S+%.d):(%d+).*unittest%s+FAILED")
  if fail_file and fail_line then
    local id = test_id(fail_file, fail_line)
    last_failed_id = id
    return { event = "fail", id = id, msg = "unittest FAILED" }
  end

  local exc, exc_file, exc_line, exc_msg = line:match("^core%.exception%.(%S+)@(%S+)%((%d+)%),?%s*(.*)$")
  if exc and exc_file and exc_line then
    local id = test_id(exc_file, exc_line)
    last_failed_id = id
    return { event = "fail", id = id, msg = exc .. ": " .. trim(exc_msg) }
  end

  if line:match("modules passed unittests") or line:match("All tests successful") then
    last_failed_id = nil
    return { event = "output", text = line }
  end

  if line:match("modules FAILED unittests") or line:match("tests FAILED") then
    return { event = "output", text = line }
  end

  local summary_passed, summary_total = line:match("(%d+)/(%d+)%s+tests%s+PASSED")
  if summary_passed and summary_total then
    return { event = "output", text = line }
  end

  if last_failed_id and (line:match("^%s+assert") or line:match("^%s+expected") or line:match("^%s+actual")) then
    return { event = "output", text = line }
  end

  if line:match("^%s+Building") or line:match("^%s+Running") or line:match("^%s+Compiling") then
    return nil
  end

  return nil
end
