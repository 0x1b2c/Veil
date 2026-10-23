-- Veil's wezterm handler for display forwarding.
--
-- On a machine running Veil, add one line to wezterm.lua:
--
--   dofile('/Applications/Veil.app/Contents/Resources/veil-wezterm.lua')
--
-- When `veil` runs in a wezterm mux pane on behalf of a keyboard on another
-- machine, it prepares a headless nvim for the project and emits the
-- `veil-edit` user var. The mux broadcasts it to every attached GUI; on the
-- machine named by the payload's `viewer`, this handler opens a Veil window
-- connected to that nvim, and on every other machine it does nothing. A
-- request raised in one of the GUI's own local panes is ignored, and so is a
-- port that is not a TCP port.
--
-- The payload is JSON, as encoded by `WorkspaceUserVar.Payload` in VeilCore:
--
--   { "host": "100.101.102.103", "port": 7001, "viewer": "a2",
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
  if request.port ~= math.floor(request.port) or request.port < 1 or request.port > 65535 then
    return nil, 'payload port is not a TCP port: ' .. tostring(value)
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

-- The domain wezterm names "local" holds the panes this GUI runs itself,
-- including plain `ssh` sessions started in them. A mux's panes reach this
-- GUI through a client domain named after its `unix_domains`, `ssh_domains`
-- or `tls_clients` entry.
M.local_domain = 'local'

-- Whether a request raised in `pane` may open a window. `veil` raises it
-- in a pane of the mux it runs under, so only those are trusted: text
-- printed in a local pane, such as a file shown with `cat` or the output of
-- an SSH session to another host, must not choose the address Veil
-- connects to.
function M.is_from_mux_pane(pane)
  return pane:get_domain_name() ~= M.local_domain
end

function M.on_user_var_changed(_, pane, name, value)
  if name ~= M.user_var then
    return
  end
  if not M.is_from_mux_pane(pane) then
    wezterm.log_error(
      'veil-edit: ignored a request raised in a pane of the local domain; '
        .. 'only panes of an attached mux may open workspaces'
    )
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
