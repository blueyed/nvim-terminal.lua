--- Highlights terminal CSI ANSI color codes.
-- @module terminal
local nvim = require 'nvim'

local function rgb_to_hex(r,g,b)
	return ("#%02X%02X%02X"):format(r,g,b)
end

local cterm_colors = {
	[0] =
	"#000000", "#AA0000", "#00AA00", "#AA5500", "#0000AA", "#AA00AA", "#00AAAA", "#AAAAAA",
	"#555555", "#FF5555", "#55FF55", "#FFFF55", "#5555FF", "#FF55FF", "#55FFFF", "#FFFFFF"
}
local function cube6(v)
	return v == 0 and v or (v*40 + 55)
end
-- https://en.wikipedia.org/wiki/ANSI_escape_code#8-bit
for b = 0, 5 do
	for g = 0, 5 do
		for r = 0, 5 do
			local i = 16 + 36*r + 6*g + b
			-- Some terminals implement this differently
			-- cterm_colors[i] = rgb_to_hex(51*r,51*g,51*b)
			cterm_colors[i] = rgb_to_hex(cube6(r),cube6(g),cube6(b))
		end
	end
end
for i = 0, 23 do
	local v = 8 + (i * 10)
	cterm_colors[232+i] = rgb_to_hex(v,v,v)
end

--- Return a lookup table from [0,255] to an RGB color.
-- Respects g:terminal_color_n
-- @treturn {[number]=string} number to hex string
local function initialize_terminal_colors()
	local result = {}
	for i = 0, 255 do
		result[i] = cterm_colors[i]
	end
	-- g:terminal_color_n overrides
	if nvim.o.termguicolors then
		-- TODO only do 16 colors?
		for i = 0, 255 do
			local status, value = pcall(vim.api.nvim_get_var, 'terminal_color_'..i)
			if status then
				result[i] = value
			else
				-- TODO assume contiguous and break early?
				break
			end
		end
	end
	return result
end

--- Parses a list of codes into an object of cterm/gui attributes
-- @tparam {[number]=string} rgb_color_table cterm color RGB lookup table
-- @tparam {string|int,...} attrs the list of codes numbers like 0 from ^[[0m
-- @tparam[opt={}] {[string]=string} attributes mutable table to output results into
-- @treturn {[string]=string} a table of cterm*/gui* attributes
local function resolve_attributes(rgb_color_table, attrs, attributes)
	attributes = attributes or {}
	for _, v in ipairs(attrs) do
		v = tonumber(v)
		-- @todo The color codes implemented is not complete
		-- @todo cterm and gui can have multiple values for italics/things other than bold.
		if not v then
			-- TODO print warning here? It might be spammy.
			-- nvim.err_writeln("Invalid mode encountered")
		elseif v >= 30 and v <= 37 then
			-- Foreground color
			local ctermfg = v-30
			attributes.ctermfg = ctermfg
			attributes.guifg = rgb_color_table[ctermfg]
		elseif v >= 40 and v <= 47 then
			-- Background color
			local ctermbg = v-40
			attributes.ctermbg = ctermbg
			attributes.guibg = rgb_color_table[ctermbg]
		elseif v >= 90 and v <= 97 then
			-- Bright colors. Foreground
			local ctermfg = v-90+8
			attributes.ctermfg = ctermfg
			attributes.guifg = rgb_color_table[ctermfg]
		elseif v >= 100 and v <= 107 then
			-- Bright colors. Background
			local ctermbg = v-100+8
			attributes.ctermbg = ctermbg
			attributes.guibg = rgb_color_table[ctermbg]
		elseif v == 22 then
			attributes.cterm = 'NONE'
			attributes.gui = 'NONE'
		elseif v == 39 then
			-- Reset to normal color for foreground
			attributes.ctermfg = 'fg'
			attributes.guifg = 'fg'
		elseif v == 49 then
			-- Reset to normal color for background
			attributes.ctermbg = 'bg'
			attributes.guibg = 'bg'
		elseif v == 1 then
			attributes.cterm = 'bold'
			attributes.gui = 'bold'
		elseif v == 0 then
			-- RESET
			attributes = {}
		end
	end
	return attributes
end

local function format_attributes(attributes)
	local result = {}
	for k, v in pairs(attributes) do
		table.insert(result, k.."="..v)
	end
	return result
end

local HIGHLIGHT_NAME_PREFIX = "termcolorcode"

--- Make a deterministic name for a highlight given these attributes
local function make_highlight_name(attributes)
	local result = {HIGHLIGHT_NAME_PREFIX}
	if attributes.cterm then
		table.insert(result, "c")
		table.insert(result, attributes.cterm)
	end
	if attributes.ctermfg then
		table.insert(result, "cfg")
		table.insert(result, attributes.ctermfg)
	end
	if attributes.ctermbg then
		table.insert(result, "cbg")
		table.insert(result, attributes.ctermbg)
	end
	if attributes.gui then
		table.insert(result, "g")
		table.insert(result, attributes.gui)
	end
	if attributes.guifg then
		table.insert(result, "gfg")
		table.insert(result, (attributes.guifg:gsub("^#", "")))
	end
	if attributes.guibg then
		table.insert(result, "gbg")
		table.insert(result, (attributes.guibg:gsub("^#", "")))
	end
	return table.concat(result, "_")
end

local highlight_cache = {}

-- Ref: https://stackoverflow.com/questions/1252539/most-efficient-way-to-determine-if-a-lua-table-is-empty-contains-no-entries
local function table_is_empty(t)
	return next(t) == nil
end

local function create_highlight(attributes)
	if table_is_empty(attributes) then
		return "Normal"
	end
	local highlight_name = make_highlight_name(attributes)
	-- Look up in our cache.
	if not highlight_cache[highlight_name] then
	-- if nvim.fn.hlID(highlight_name) == 0 then
		-- Create the highlight
		nvim.ex.highlight(highlight_name, unpack(format_attributes(attributes)))
		highlight_cache[highlight_name] = true
	end
	return highlight_name
end

--- Highlight a region in a buffer from the attributes specified
local function highlight_from_attributes(buf, ns, current_attributes,
		 region_line_start, region_byte_start,
		 region_line_end, region_byte_end)
	-- TODO should I bother with highlighting normal regions?
	local highlight_name = create_highlight(current_attributes)
	if region_line_start == region_line_end then
		nvim.buf_add_highlight(buf, ns, highlight_name, region_line_start, region_byte_start, region_byte_end)
	else
		nvim.buf_add_highlight(buf, ns, highlight_name, region_line_start, region_byte_start, -1)
		for linenum = region_line_start + 1, region_line_end - 1 do
			nvim.buf_add_highlight(buf, ns, highlight_name, linenum, 0, -1)
		end
		nvim.buf_add_highlight(buf, ns, highlight_name, region_line_end, 0, region_byte_end)
	end
end

--- Parse a color code inner
-- Either an RGB code or an incremental list of other CSI codes.
local function parse_color_code(rgb_color_table, code, current_attributes)
	if code:match("^[34]8[:;]5[:;]") then
		local kind, sep1, sep2, n = code:match("^([34])8([:;])5([:;])(%d+)$")
		-- TODO do this better
		assert(sep1 == sep2)
		local ctermnr = tonumber(n)
		current_attributes[kind == "3" and "ctermfg" or "ctermbg"] = ctermnr
		current_attributes[kind == "3" and "guifg" or "guibg"] = rgb_color_table[ctermnr]
	elseif code:match("^[34]8[:;]2[:;]") then
		local kind, sep1, sep2, r, sep3, g, sep4, b = code:match("^([34])8([:;])2([:;])(%d+)([:;])(%d+)([:;])(%d+)$")
		-- TODO do this better
		assert(sep1 == sep2 and sep1 == sep3 and sep1 == sep4)
		-- TODO confirm that r,g,b are in the correct format.
		current_attributes[kind == "3" and "guifg" or "guibg"] = "#"..r..g..b
	else
		local parts = vim.split(code, ";", true)
		current_attributes = resolve_attributes(rgb_color_table, parts, current_attributes)
	end
	return current_attributes
end

--- Default namespace used in `highlight_buffer` and `attach_to_buffer`.
-- The name is "terminal_highlight"
-- @see highlight_buffer
-- @see attach_to_buffer
local DEFAULT_NAMESPACE = nvim.create_namespace 'terminal_highlight'

--[[-- Highlight the buffer region.
Highlight starting from `line_start` (0-indexed) for each line described by `lines` in the
buffer `buf` and attach it to the namespace `ns`.

@usage
-- Re-highlights the current buffer
local terminal = require 'terminal'
-- Clear existing highlight
vim.api.nvim_buf_clear_namespace(buf, terminal.DEFAULT_NAMESPACE, 0, -1)
local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
terminal.highlight_buffer(0, nil, lines, 0)

@usage
local function rehighlight_region(buf, line_start, line_end)
  local ns = terminal.DEFAULT_NAMESPACE
  vim.api.nvim_buf_clear_namespace(buf, ns, line_start, line_end)
  local lines = vim.api.nvim_buf_get_lines(0, line_start, line_end, false)
  terminal.highlight_buffer(0, nil, lines, line_start)
end

@tparam integer buf buffer id.
@tparam[opt=DEFAULT_NAMESPACE] integer ns the namespace id. Create it with `vim.api.create_namespace`
@tparam {string,...} lines the lines to highlight from the buffer.
@tparam integer line_start should be 0-indexed
@tparam[opt=initialize_terminal_colors()] {[number]=string} rgb_color_table cterm color RGB lookup table
]]
local function highlight_buffer(buf, ns, lines, line_start, rgb_color_table)
	rgb_color_table = rgb_color_table or initialize_terminal_colors()
	ns = ns or DEFAULT_NAMESPACE
	--[[
	Algorithm overview:
	Maintain an attributes object which contains the currently applicable
	style to apply based on the incremental definitions from CSI codes.

	1. Start with a bare attributes object which represents a Normal style.
	2. Scan for the next CSI color code.
	3. Apply a highlight on the region between the last CSI code and this new
	one. based on the current attributes.
	4. Update the current attributes with those defined by the new CSI code.
	5. Repeat from 2
	]]
	local current_region_start, current_attributes = nil, {}
	for current_linenum, line in ipairs(lines) do
		-- @todo it's possible to skip processing the new code if the attributes hasn't changed.
		current_linenum = current_linenum - 1 + line_start
		-- Scan for potential color codes.
		for match_start, code, _ in line:gmatch("()%[([%d;:]+)m()") do
			-- Highlight any current region.
			if current_region_start then
				highlight_from_attributes(buf, ns, current_attributes,
						current_region_start[1], current_region_start[2],
						current_linenum, match_start)
			end
			current_region_start = {current_linenum, match_start}
			-- Update attributes from the new escape code.
			current_attributes = parse_color_code(rgb_color_table, code, current_attributes)
		end
	end
	if current_region_start then
		highlight_from_attributes(buf, ns, current_attributes,
				current_region_start[1], current_region_start[2],
				line_start + #lines, -1)
	end
end

--- Attach to a buffer and continuously highlight changes.
-- @tparam integer buf A value of 0 implies the current buffer.
-- @tparam[opt=initialize_terminal_colors()] {[number]=string} rgb_color_table cterm color RGB lookup table
-- @see highlight_buffer
local function attach_to_buffer(buf)
	local ns = DEFAULT_NAMESPACE
--	local ns = nvim.create_namespace 'terminal_highlight'
	do
		nvim.buf_clear_namespace(buf, ns, 0, -1)
		local lines = nvim.buf_get_lines(buf, 0, -1, true)
		highlight_buffer(buf, ns, lines, 0)
	end
	-- send_buffer: true doesn't actually do anything in Lua (yet)
	nvim.buf_attach(buf, false, {
		on_lines = function(_event_type, buf_, _changed_tick, _firstline, _lastline, _new_lastline)
			-- TODO I don't think there's a way around this. Codes are affected by
			-- everything before and affect things after. You could do more
			-- intelligence analysis by only parsing up until the last affected
			-- values, but that's complicated.
			local firstline = 0
			local new_lastline = -1
			nvim.buf_clear_namespace(buf_, ns, firstline, new_lastline)
			local lines = nvim.buf_get_lines(buf_, firstline, new_lastline, true)
			highlight_buffer(buf_, ns, lines, firstline)
		end;
	})
end

--- Easy to use function if you want the full setup without fine grained control.
-- Establishes an autocmd for `FileType terminal`
-- @tparam[opt=initialize_terminal_colors()] {[number]=string} rgb_color_table cterm color RGB lookup table
-- @usage require'terminal'.setup()
local function setup(rgb_color_table)
	rgb_color_table = rgb_color_table or initialize_terminal_colors()
	function TERMINAL_SETUP_HOOK()
		nvim.win_set_option(0, 'concealcursor', 'nc')
		nvim.win_set_option(0, 'wrap', false)
		attach_to_buffer(nvim.get_current_buf(), rgb_color_table)
	end
	nvim.ex.augroup("TerminalSetup")
	nvim.ex.autocmd_()
	nvim.ex.autocmd("FileType terminal lua TERMINAL_SETUP_HOOK()")
	nvim.ex.augroup("END")
end

--- @export
return {
	DEFAULT_NAMESPACE = DEFAULT_NAMESPACE;
	setup = setup;
	attach_to_buffer = attach_to_buffer;
	highlight_buffer = highlight_buffer;
	initialize_terminal_colors = initialize_terminal_colors;
}

--[=[ Example:
```lua
local buf = 1
local ns = nvim.create_namespace("terminal_highlight")
nvim.buf_clear_namespace(buf, ns, 0, -1)
local lines = nvim.buf_get_lines(buf, 1, -1, false)
require'terminal'.highlight_buffer(buf, ns, lines, 0)
```
]=]
