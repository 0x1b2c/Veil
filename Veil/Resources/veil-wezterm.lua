-- Veil's handler for remote workspace launch in wezterm.
--
-- On a machine running Veil, add one line to wezterm.lua:
--
--   dofile('/Applications/Veil.app/Contents/Resources/veil-wezterm.lua')
--
-- When `veil` runs in a wezterm mux pane on behalf of a keyboard on another
-- machine, it prepares a headless nvim for the project and emits the
-- `veil-edit` user var. The mux broadcasts it to every attached GUI; on the
-- machine named by the payload's `viewer`, this handler opens a Veil window
-- connected to that nvim, and on every other machine it does nothing.
--
-- The payload is JSON, as encoded by `WorkspaceUserVar.Payload` in VeilCore:
--
--   { "host": "2b.example.ts.net", "port": 7001, "viewer": "a2",
--     "workspace": "proj" }
--
-- and the handler runs `veil --veil-connect <host>:<port>
-- --veil-workspace <workspace>`.
--
-- wezterm evaluates its configuration in a fresh Lua state on every load
-- and reload, so registering the handler here never stacks up copies.

local wezterm = require('wezterm')

local M = {}

M.user_var = 'veil-edit'

-- The comparable core of a hostname, the same rule as
-- `WorkspaceViewer.normalize` in VeilCore: wezterm reports one machine as
-- "A2", "A2.local", "a2.tail1234.ts.net", or "A2.local (via proxy pid
-- 13754)" depending on the API, so keep what precedes the first space, "(",
-- or ".", trim spaces and tabs, and lowercase. Tests/wezterm holds the case
-- table both implementations are tested against.
function M.normalize_hostname(hostname)
  local core = hostname:match('^[^ (.]*')
  core = core:gsub('^[ \t]+', ''):gsub('[ \t]+$', '')
  return core:lower()
end

-- Whether a broadcast naming `viewer` is meant for the machine `hostname`.
function M.is_for_this_machine(viewer, hostname)
  return M.normalize_hostname(viewer) == M.normalize_hostname(hostname)
end

-- wezterm's Lua has no `debug` library, so this script cannot locate the
-- bundle it was loaded from. The GUI's PATH may lack `veil` too, so look
-- in the two places a Veil.app is installed, in this order.
function M.veil_candidates(home_dir)
  local relative = '/Applications/Veil.app/Contents/bin/veil'
  return { relative, home_dir .. relative }
end

function M.file_exists(path)
  local file = io.open(path, 'r')
  if file == nil then
    return false
  end
  file:close()
  return true
end

-- The first of `candidates` that exists, or nil.
function M.find_veil(candidates)
  for _, path in ipairs(candidates) do
    if M.file_exists(path) then
      return path
    end
  end
  return nil
end

-- The decoded payload, or nil and the reason it is unusable.
function M.parse_request(json_parse, value)
  local ok, request = pcall(json_parse, value)
  if not ok or type(request) ~= 'table' then
    return nil, 'payload is not a JSON object: ' .. tostring(value)
  end
  if type(request.host) ~= 'string' or type(request.port) ~= 'number' then
    return nil, 'payload lacks a host and port: ' .. tostring(value)
  end
  if type(request.workspace) ~= 'string' then
    return nil, 'payload lacks a workspace name: ' .. tostring(value)
  end
  if type(request.viewer) ~= 'string' then
    return nil, 'payload lacks a viewer: ' .. tostring(value)
  end
  return request
end

function M.connect_argv(veil, request)
  return {
    veil,
    '--veil-connect',
    string.format('%s:%d', request.host, request.port),
    '--veil-workspace',
    request.workspace,
  }
end

function M.on_user_var_changed(_, _, name, value)
  if name ~= M.user_var then
    return
  end
  local request, problem = M.parse_request(wezterm.json_parse, value)
  if request == nil then
    wezterm.log_error('veil-edit: ' .. problem)
    return
  end
  -- The broadcast reaches every attached GUI; only the viewer's reacts.
  if not M.is_for_this_machine(request.viewer, wezterm.hostname()) then
    return
  end
  local candidates = M.veil_candidates(wezterm.home_dir)
  local veil = M.find_veil(candidates)
  if veil == nil then
    wezterm.log_error(
      'veil-edit: Veil.app not found; looked for ' .. table.concat(candidates, ' and ')
    )
    return
  end
  wezterm.background_child_process(M.connect_argv(veil, request))
end

wezterm.on('user-var-changed', M.on_user_var_changed)

return M
