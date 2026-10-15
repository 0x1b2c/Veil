-- Tests for Veil/Resources/veil-wezterm.lua, run outside wezterm by
-- `nvim --clean -l Tests/wezterm/veil-wezterm-test.lua` (part of `just test`).
-- The script reaches wezterm only through `require('wezterm')`, so each test
-- loads it against a fake that records what the script asks wezterm to do.

local repo_root = vim.fn.fnamemodify(arg[0], ':p:h:h:h')
local script_path = repo_root .. '/Veil/Resources/veil-wezterm.lua'

local system_veil = '/Applications/Veil.app/Contents/bin/veil'
local home_dir = '/Users/someone'
local user_veil = home_dir .. '/Applications/Veil.app/Contents/bin/veil'

local function fake_wezterm()
  local fake = { home_dir = home_dir, handlers = {}, spawned = {}, errors = {} }
  function fake.on(event, handler)
    table.insert(fake.handlers, { event = event, handler = handler })
  end
  function fake.log_error(message)
    table.insert(fake.errors, message)
  end
  function fake.json_parse(text)
    return vim.json.decode(text)
  end
  function fake.background_child_process(argv)
    table.insert(fake.spawned, argv)
  end
  return fake
end

-- Loads the script the way `dofile` in wezterm.lua does, with `wezterm`
-- resolving to `fake`. Only the paths in `installed` exist.
local function load_script(fake, installed)
  package.loaded.wezterm = fake
  local module = dofile(script_path)
  package.loaded.wezterm = nil
  module.file_exists = function(path)
    return vim.tbl_contains(installed, path)
  end
  return module
end

local focused_window = {
  is_focused = function()
    return true
  end,
}

local function broadcast(fake, window, name, value)
  for _, registration in ipairs(fake.handlers) do
    if registration.event == 'user-var-changed' then
      registration.handler(window, {}, name, value)
    end
  end
end

local function payload(fields)
  return vim.json.encode(vim.tbl_extend('force', {
    host = '2b.example.ts.net',
    port = 7001,
    workspace = 'proj',
  }, fields or {}))
end

local passed, failed = 0, 0

local function test(name, body)
  local ok, err = pcall(body)
  if ok then
    passed = passed + 1
  else
    failed = failed + 1
    io.stderr:write(('FAIL %s: %s\n'):format(name, err))
  end
end

local function expect_equal(actual, expected)
  if not vim.deep_equal(actual, expected) then
    error(('expected %s, got %s'):format(vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

test('@ws-007 one dofile line connects this machine to the broadcast workspace', function()
  local fake = fake_wezterm()
  load_script(fake, { system_veil })
  expect_equal(#fake.handlers, 1)
  expect_equal(fake.handlers[1].event, 'user-var-changed')

  broadcast(fake, focused_window, 'veil-edit', payload())

  expect_equal(fake.spawned, {
    { system_veil, '--veil-connect', '2b.example.ts.net:7001', '--veil-workspace', 'proj' },
  })
  expect_equal(fake.errors, {})
end)

test('other user vars are left alone', function()
  local fake = fake_wezterm()
  load_script(fake, { system_veil })
  broadcast(fake, focused_window, 'something-else', payload())
  expect_equal(fake.spawned, {})
  expect_equal(fake.errors, {})
end)

test('an unfocused window ignores the broadcast', function()
  local fake = fake_wezterm()
  load_script(fake, { system_veil })
  local unfocused_window = {
    is_focused = function()
      return false
    end,
  }
  broadcast(fake, unfocused_window, 'veil-edit', payload())
  expect_equal(fake.spawned, {})
end)

test('veil is found in ~/Applications when /Applications has none', function()
  local fake = fake_wezterm()
  load_script(fake, { user_veil })
  broadcast(fake, focused_window, 'veil-edit', payload())
  expect_equal(#fake.spawned, 1)
  expect_equal(fake.spawned[1][1], user_veil)
end)

test('/Applications wins when both have Veil', function()
  local fake = fake_wezterm()
  load_script(fake, { user_veil, system_veil })
  broadcast(fake, focused_window, 'veil-edit', payload())
  expect_equal(fake.spawned[1][1], system_veil)
end)

test('a missing Veil is logged instead of spawned', function()
  local fake = fake_wezterm()
  load_script(fake, {})
  broadcast(fake, focused_window, 'veil-edit', payload())
  expect_equal(fake.spawned, {})
  expect_equal(#fake.errors, 1)
  assert(fake.errors[1]:find(system_veil, 1, true), fake.errors[1])
  assert(fake.errors[1]:find(user_veil, 1, true), fake.errors[1])
end)

test('a malformed payload is logged instead of spawned', function()
  for _, value in ipairs({
    'not json',
    '[]',
    payload({ host = 7 }),
    payload({ port = '7001' }),
    payload({ workspace = vim.NIL }),
  }) do
    local fake = fake_wezterm()
    load_script(fake, { system_veil })
    broadcast(fake, focused_window, 'veil-edit', value)
    expect_equal(fake.spawned, {})
    expect_equal(#fake.errors, 1)
  end
end)

io.stdout:write(('Lua: %d passed, %d failed\n'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
