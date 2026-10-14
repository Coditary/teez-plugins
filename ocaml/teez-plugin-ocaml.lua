-- teez OCaml / Alcotest adapter (dune runtest)

local DEFAULT_INCLUDE = {
  "**/*_test.ml",
  "**/*_test.mli",
  "**/test/**",
}

local function trim(value)
  return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function strip_ansi(line)
  return (line:gsub("%[[%d;]*m", ""))
end

local function target_path(context)
  return context.target_path or "."
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
    instrument = "bisect_ppx",
    report = "coverage/cobertura.xml",
    output = "coverage/teez.msgpack",
    reporter = "cobertura",
    collect_command = "bisect-ppx-report",
    collect_args = { "cobertura", "coverage/cobertura.xml" },
    clean_profile = true,
  }
end

local function effective_coverage_cfg(context)
  return shallow_merge(default_coverage_cfg(), coverage_cfg(context))
end

local function resolve_glob_hit(root, file)
  if file:sub(1, 1) == "/" then
    return file
  end
  return root .. "/" .. file
end

local function path_excluded(target, pattern)
  return filter.glob_match(target, pattern)
end

local function include_patterns(context)
  local cfg = runner_cfg(context)
  if cfg.include then
    return cfg.include
  end
  return DEFAULT_INCLUDE
end

local function runner_targets(context)
  local target = target_path(context)
  local patterns = include_patterns(context)
  local paths = {}
  local seen = {}

  for _, pattern in ipairs(patterns) do
    for _, file in ipairs(fs.glob(target, pattern)) do
      local resolved = resolve_glob_hit(target, file)
      local excluded = false
      if context.runner and context.runner.exclude then
        for _, exclude_pattern in ipairs(context.runner.exclude) do
          if path_excluded(resolved, exclude_pattern) then
            excluded = true
            break
          end
        end
      end
      if not excluded and not seen[resolved] then
        seen[resolved] = true
        table.insert(paths, resolved)
      end
    end
  end

  if #paths == 0 then
    return { target }
  end
  return paths
end

local function dune_command(context)
  local cfg = runner_cfg(context)
  if cfg.command then
    return cfg.command
  end
  return "dune"
end

local function dune_subcommand(context)
  local cfg = runner_cfg(context)
  if cfg.subcommand then
    return cfg.subcommand
  end
  return "test"
end

local function append_runner_args(args, context)
  local cfg = runner_cfg(context)
  if not cfg then
    return
  end

  if cfg.force then
    table.insert(args, "--force")
  end

  if cfg.args then
    for _, arg in ipairs(cfg.args) do
      table.insert(args, arg)
    end
  end
end

local function insert_unique(tests, seen, id)
  if id == nil or id == "" or seen[id] then
    return
  end
  seen[id] = true
  table.insert(tests, id)
end

local function file_test_id(path)
  local id = path:gsub("%.mli$", ""):gsub("%.ml$", "")
  return id
end

local function collect_from_files(context)
  local tests = {}
  local seen = {}
  for _, path in ipairs(runner_targets(context)) do
    if path:match("%.mli?$") or path:match("/test/") then
      insert_unique(tests, seen, file_test_id(path))
    end
  end
  return tests
end

local function parse_describe_line(tests, seen, plain)
  if plain == "" then
    return
  end

  local runtest_name = plain:match("^@runtest%-(.+)$")
  if runtest_name then
    insert_unique(tests, seen, "runtest/" .. runtest_name)
    return
  end

  local alias = plain:match("alias%s+(%S+)")
  if alias and alias:match("^runtest") then
    insert_unique(tests, seen, alias)
    return
  end

  local exe = plain:match("(%S+_test%.exe)$")
  if exe then
    insert_unique(tests, seen, exe:gsub("%.exe$", ""))
    return
  end

  if plain:match("_test%.mli?$") or plain:match("/test/") then
    insert_unique(tests, seen, file_test_id(plain))
  end
end

local function parse_describe_targets(output)
  local tests = {}
  local seen = {}

  for line in output:gmatch("[^\r\n]+") do
    parse_describe_line(tests, seen, strip_ansi(trim(line)))
  end

  return tests
end

local function collect_from_describe(context)
  local target = target_path(context)
  local command = dune_command(context)
  local tests = {}
  local seen = {}

  local attempts = {
    { "describe", "targets", target },
    { "describe", "workspace", target },
  }

  for _, args in ipairs(attempts) do
    local result = sys.run(command, args)
    if result.exit_code == 0 and result.stdout and result.stdout ~= "" then
      for _, id in ipairs(parse_describe_targets(result.stdout)) do
        insert_unique(tests, seen, id)
      end
    end
  end

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

local function collect_tests(context)
  local tests = {}
  local seen = {}

  for _, id in ipairs(collect_from_describe(context)) do
    insert_unique(tests, seen, id)
  end

  for _, id in ipairs(collect_from_files(context)) do
    insert_unique(tests, seen, id)
  end

  return apply_filters(tests, context)
end

local function alcotest_id(suite, index, name)
  local case = trim(name):gsub("%.+$", "")
  return suite .. "::" .. index .. "::" .. case
end

function list(context)
  return collect_tests(context)
end

function build_command(context)
  local args = { dune_subcommand(context) }
  append_runner_args(args, context)

  for _, target in ipairs(runner_targets(context)) do
    table.insert(args, target)
  end

  return {
    command = dune_command(context),
    args = args,
  }
end

function build_list_command(context)
  local target = target_path(context)
  return {
    command = dune_command(context),
    args = { "describe", "targets", target },
  }
end

function build_coverage_run(context)
  local cfg = effective_coverage_cfg(context)
  local target = target_path(context)
  local args = {
    dune_subcommand(context),
    "--instrument-with",
    cfg.instrument or "bisect_ppx",
    "--force",
  }

  append_runner_args(args, context)
  for _, path in ipairs(runner_targets(context)) do
    table.insert(args, path)
  end

  local report = cfg.report or "coverage/cobertura.xml"
  local collect_command = cfg.collect_command or "bisect-ppx-report"
  local collect_args = {}
  local source_args = cfg.collect_args or { "cobertura", report }
  for _, arg in ipairs(source_args) do
    table.insert(collect_args, arg)
  end

  if cfg.coverage_path then
    table.insert(collect_args, "--coverage-path")
    table.insert(collect_args, cfg.coverage_path)
  end

  return {
    command = dune_command(context),
    args = args,
    cwd = target,
    collect = {
      command = collect_command,
      args = collect_args,
    },
    report = report,
    reporter = cfg.reporter or "cobertura",
    output = cfg.output or "coverage/teez.msgpack",
    min_line_rate = cfg.min_line_rate,
    clean_profile = cfg.clean_profile,
  }
end

function parse_line(line)
  local plain = strip_ansi(line)

  local suite = plain:match("^Testing [`'](.+)[`']%.?$")
  if suite then
    return { event = "start", id = suite }
  end

  local status, alc_suite, index, name = plain:match("^%s*%[(OK|FAIL|SKIP|ERROR)%]%s+(%S+)%s+(%d+)%s+(.+)$")
  if status and alc_suite and index and name then
    local id = alcotest_id(alc_suite, index, name)
    if status == "OK" then
      return { event = "pass", id = id }
    end
    if status == "SKIP" then
      return { event = "skip", id = id }
    end
    return { event = "fail", id = id, msg = status }
  end

  if plain:match("^Test Successful") then
    return { event = "output", text = plain }
  end

  if plain:match("^Test Failed") or plain:match("%[failure%]") then
    return { event = "output", text = plain }
  end

  local failed_case = plain:match("^%-%- .-%[(.-)%] Failed %-%-$")
  if failed_case then
    return { event = "fail", id = trim(failed_case), msg = plain }
  end

  local alias, exit_code = plain:match("(%S+)%s+alias%s+runtest%s+%(exit%s+(%d+)%)$")
  if alias and exit_code then
    if exit_code == "0" then
      return { event = "pass", id = alias }
    end
    return { event = "fail", id = alias, msg = "exit " .. exit_code }
  end

  if plain:match("^Error:") or plain:match("^File \"[^\"]+\", line %d+") then
    return { event = "output", text = plain }
  end

  return nil
end
