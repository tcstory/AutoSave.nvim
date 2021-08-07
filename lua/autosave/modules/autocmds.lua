local api = vim.api
local fn = vim.fn
local cmd = vim.cmd

local opts = require("autosave.config").options
local autosave = require("autosave")
local default_events = {"InsertLeave", "TextChanged"}

local modified

local M = {}

local function table_has_value(tbl, value)
  for key, _ in pairs(tbl) do
    if (tbl[key] == value) then
      return true
    end
  end

  return false
end

local function table_is_empty(tbl) 
  return next(tbl) == nil
end

local function set_modified(value)
  modified = value
end

local function get_modified()
  return modified
end

local function actual_save()
  -- might use  update, but in that case it can't be checked if a file was modified and so it will always
  -- print opts["execution_message"]
  if (api.nvim_eval([[&modified]]) == 1) then
    local first_char_pos = fn.getpos("'[")
    local last_char_pos = fn.getpos("']")

    cmd("silent! write")

    fn.setpos("'[", first_char_pos)
    fn.setpos("']", last_char_pos)

    if (get_modified() == nil or get_modified() == false) then
      set_modified(true)
    end

    M.message_and_interval()
  end
end

local function assert_user_conditions()
  local sc_exists, sc_filetype, sc_modifiable = true, true, true
  local conditions_tbl = opts["conditions"]
  local filetype_is_tbl = conditions_tbl["filetype_is"]
  local filetype_is_not_tbl = conditions_tbl["filetype_is_not"]
  
  if (conditions_tbl["exists"] == true) then
    if (fn.filereadable(fn.expand("%:p")) == 0) then
      sc_exists = false
    end
  end

  if (conditions_tbl["modifiable"] == true) then
    if (api.nvim_eval([[&modifiable]]) == 0) then
      sc_modifiable = false
    end
  end

  if (table_is_empty(filetype_is_tbl) == false) then
    if (table_has_value(filetype_is_tbl, api.nvim_eval("&filetype")) == false) then
      sc_filetype = false
    end
  elseif (table_is_empty(filetype_is_not_tbl) == false) then
    if (table_has_value(filetype_is_not_tbl, api.nvim_eval([[&filetype]])) == true) then
      sc_filetype = false
    end
  else 
    -- nothing to do
  end

  return {sc_exists, sc_filetype, sc_modifiable}
end

local function assert_return(values, expected)
  for key, value in pairs(values) do
    if (value ~= expected) then
      return false
    end
  end

  return true
end

function M.message_and_interval()
  if (get_modified() == true) then
    set_modified(false)
    if (opts["execution_message"] ~= "") then
      print(opts["execution_message"])
    end

    if (opts["clean_command_line_interval"] > 0) then
      cmd(
      [[call timer_start(]] ..
      opts["clean_command_line_interval"] .. [[, funcref('g:AutoSaveClearCommandLine'))]]
      )
    end
  end
end

local function debounce(lfn, duration)
  local queued = false

  local function inner_debounce()
    if not queued then
      vim.defer_fn(
      function()
        queued = false
        lfn()
      end,
      duration
      )
      queued = true
    end
  end

  return inner_debounce
end

function M.do_save()
  if (assert_return(assert_user_conditions(), true)) then
    M.debounced_save()
  end
end

function M.save()
  if (autosave.hook_before_saving ~= nil) then
    autosave.hook_before_saving()
  end

  M.do_save()

  if (autosave.hook_after_saving ~= nil) then
    autosave.hook_after_saving()
  end
end

local function events()
  if (next(opts["events"]) == nil or opts["events"] == nil) then
    return default_events
  else
    return opts["events"]
  end
end

local function parse_events()
  return table.concat(events(), ",")
end

function M.load_autocommands()
  if opts["debounce_delay"] == 0 then
    M.debounced_save = actual_save
  else
    M.debounced_save = debounce(actual_save, opts["debounce_delay"])
  end

  if (opts["write_all_buffers"] == false) then
    api.nvim_exec(
    [[
    aug autosave_save
    au!
    au ]] ..
    parse_events() ..
    [[ * execute "lua require'autosave.modules.autocmds'.save()"
    aug END
    ]],
    false
    )
  else
    local event_1 = events()[1]
    api.nvim_exec(
    [[
    aug autosave_save
    au!
    au ]] ..
    parse_events() ..
    [[ * if !exists("g:autosave_changed") | let g:autosave_changed="t" | doautoall autosave_save ]] ..
    event_1 ..
    [[ | unlet g:autosave_changed | else | execute "lua require'autosave.modules.autocmds'.save()" | endif
    aug END
    ]],
    false
    )
  end
end

function M.unload_autocommands()
  api.nvim_exec([[
  aug autosave_save
  au!
  aug END
  ]], false)
end

return M
