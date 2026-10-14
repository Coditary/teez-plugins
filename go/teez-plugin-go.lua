-- teez go test adapter

local DEFAULT_INCLUDE = { "**/*_test.go" }

local parse_state = {
  packages = {},
  pkg_index = 1,
  current = ".",
}

local function target_path(context)
  return context.target_path or "."
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

local function find_module_root(start_path)
  local path = start_path
  while path and path ~= "" do
    if fs.exists(path .. "/go.mod") then
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

local function relative_to(base, path)
  if path:sub(1, #base) == base then
    local rel = path:sub(#base + 1)
    if rel:sub(1, 1) == "/" then
      rel = rel:sub(2)
    end
    if rel == "" then
      return "."
    end
    return rel
  end
  return path
end

local function package_path(module_root, dir_path)
  local rel = relative_to(module_root, dir_path)
  if rel == "." then
    return "."
  end
  return "./" .. rel
end

local function directory_of(file)
  return file:match("^(.*)/[^/]+$") or "."
end

local function default_packages(context)
  local target = target_path(context)
  local module_root = find_module_root(target)
  local rel = relative_to(module_root, target)
  if rel == "." then
    return { "./..." }
  end
  return { "./" .. rel .. "/..." }
end

local function runner_targets(context)
  local target = target_path(context)
  local module_root = find_module_root(target)
  local include = (context.runner and context.runner.include) or DEFAULT_INCLUDE

  if not context.runner or not context.runner.include then
    return default_packages(context)
  end

  local packages = {}
  local seen = {}
  for _, pattern in ipairs(include) do
    for _, file in ipairs(fs.glob(target, pattern)) do
      local resolved = resolve_glob_hit(target, file)
      local excluded = false
      if context.runner.exclude then
        for _, exclude_pattern in ipairs(context.runner.exclude) do
          if path_excluded(resolved, exclude_pattern) then
            excluded = true
            break
          end
        end
      end
      if not excluded then
        local pkg = package_path(module_root, directory_of(resolved))
        if not seen[pkg] then
          seen[pkg] = true
          table.insert(packages, pkg)
        end
      end
    end
  end

  if #packages == 0 then
    return default_packages(context)
  end
  return packages
end

local function append_runner_args(args, context)
  if not context.runner then
    return
  end

  if context.runner.pattern then
    table.insert(args, "-run")
    table.insert(args, context.runner.pattern)
  end

  if context.runner.args then
    for _, arg in ipairs(context.runner.args) do
      table.insert(args, arg)
    end
  end
end

local function is_listed_test(name)
  if name == "TestMain" then
    return false
  end
  return name:match("^Test") or name:match("^Example")
end

local function test_id(pkg, name)
  return pkg .. "::" .. name
end

local function reset_parse_state(packages)
  parse_state.packages = packages
  parse_state.pkg_index = 1
  parse_state.current = packages[1] or "."
end

local function advance_package()
  parse_state.pkg_index = parse_state.pkg_index + 1
  parse_state.current = parse_state.packages[parse_state.pkg_index] or parse_state.current
end

local function collect_tests(context)
  local module_root = find_module_root(target_path(context))
  local tests = {}
  for _, pkg in ipairs(runner_targets(context)) do
    local args = { "test", "-list", pkg }
    append_runner_args(args, context)
    local output = sys.exec("go", args, { cwd = module_root })
    for line in output:gmatch("[^\r\n]+") do
      local name = line:match("^(%S+)")
      if name and is_listed_test(name) then
        table.insert(tests, test_id(pkg, name))
      end
    end
  end

  if context.filters then
    local filtered = {}
    for _, id in ipairs(tests) do
      if filter.matches({ id = id }, context.filters) then
        table.insert(filtered, id)
      end
    end
    return filtered
  end

  return tests
end

function list(context)
  return collect_tests(context)
end

function build_command(context)
  local module_root = find_module_root(target_path(context))
  local packages = runner_targets(context)
  reset_parse_state(packages)

  local args = { "test", "-v" }
  append_runner_args(args, context)
  for _, pkg in ipairs(packages) do
    table.insert(args, pkg)
  end

  return {
    command = "go",
    args = args,
    cwd = module_root,
  }
end

function build_coverage_run(context)
  local module_root = find_module_root(target_path(context))
  local packages = runner_targets(context)
  reset_parse_state(packages)

  local profile = "coverage.out"
  local args = {
    "test",
    "-coverprofile=" .. profile,
    "-covermode=atomic",
  }
  append_runner_args(args, context)
  for _, pkg in ipairs(packages) do
    table.insert(args, pkg)
  end

  return {
    command = "go",
    args = args,
    cwd = module_root,
    report = profile,
  }
end

function parse_line(line)
  if line:match("^ok%s+") or line:match("^FAIL%s+%S") then
    advance_package()
    return nil
  end

  local pass = line:match("^--- PASS:%s+(%S+)")
  if pass then
    return { event = "pass", id = test_id(parse_state.current, pass) }
  end

  local fail = line:match("^--- FAIL:%s+(%S+)")
  if fail then
    return { event = "fail", id = test_id(parse_state.current, fail), msg = "FAILED" }
  end

  local skip = line:match("^--- SKIP:%s+(%S+)")
  if skip then
    return { event = "skip", id = test_id(parse_state.current, skip) }
  end

  return nil
end
