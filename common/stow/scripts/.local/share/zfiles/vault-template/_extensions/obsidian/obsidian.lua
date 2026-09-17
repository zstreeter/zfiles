obsidian.lua — teach Quarto to read Obsidian Flavored Markdown.

(Long-bracket comment: the text below contains `]]`, which would close an
ordinary --[[ block early.)

Paired with, and useless without, this in _quarto.yml:

    from: markdown+wikilinks_title_after_pipe+mark
    filters:
      - at: pre-ast
        path: _extensions/obsidian/obsidian.lua

WHY A FILTER AND NOT A PREPROCESSOR

The obvious way to bridge Obsidian and Pandoc is to rewrite the text before
Pandoc sees it. That approach is wrong, and the reason is worth keeping: every
rule you would write is a regex over prose, and LaTeX is built from exactly the
characters those regexes hunt for. `^` is a block-id marker and a superscript.
`==` is an Obsidian highlight and a comparison in an aligned equation. `[[ ]]`
is a wikilink and a bracket matrix. A text-level pass cannot tell them apart,
so it silently corrupts formulas, and the damage surfaces as a LaTeX error far
from its cause.

A filter runs after parsing, on the syntax tree. By then math is a Math node
and code is a Code node -- opaque, and unreachable by any rule here. The bug
class is designed out rather than defended against.

Pandoc 3.x already does most of the work, which is why this file is small:

    [[Note]] / [[Note|alias]]   Link, tagged with a "wikilink" class
    ![[figure.png]]             Figure > Image, same class
    ==highlight==               Span .mark          (needs +mark)
    $$ ... $$                   Math DisplayMath    (untouched, always)

So what is left is the four things Pandoc has no concept of:

    [[@citekey]]        a CITATION, not a link -- see below
    ![[Note#Section]]   transclusion; Pandoc has no such notion
    > [!warning]        a callout, not a blockquote
    %%comment%%         a comment, not text

The citation case is the one that costs real work if you skip it. This repo's
vaults file literature notes as @<citekey>.md and link them [[@citekey]] (see
the vault AGENTS.md), so a wikilink beginning with @ is a bibliography entry. It
does not announce itself when it goes wrong: the link renders as plain text, the
reference never reaches the bibliography, and the paper's reference list is
quietly short.
]==]

local stringify = pandoc.utils.stringify

local MAX_EMBED_DEPTH = 3

local IMAGE_EXT = {
  png = true, jpg = true, jpeg = true, gif = true,
  svg = true, webp = true, pdf = true, bmp = true, tif = true, tiff = true,
}

local CALLOUTS = {
  note = 'note', info = 'note', abstract = 'note', summary = 'note',
  tldr = 'note', example = 'note', quote = 'note', cite = 'note',
  todo = 'note', question = 'note', help = 'note', faq = 'note',
  tip = 'tip', hint = 'tip', success = 'tip', check = 'tip', done = 'tip',
  important = 'important',
  warning = 'warning', attention = 'warning',
  caution = 'caution', danger = 'caution', error = 'caution',
  failure = 'caution', fail = 'caution', missing = 'caution', bug = 'caution',
}


local function is_dir(path)
  return (pcall(pandoc.system.list_directory, path))
end

local function read_file(path)
  local fh = io.open(path, 'r')
  if not fh then return nil end
  local text = fh:read('a')
  fh:close()
  return text
end

local function find_vault(start)
  local dir = start
  for _ = 1, 40 do
    if dir == nil or dir == '' then return nil end
    if is_dir(pandoc.path.join{ dir, '.obsidian' }) then return dir end
    local parent = pandoc.path.directory(dir)
    if parent == dir then return nil end
    dir = parent
  end
  return nil
end

local notes, assets = {}, {}

local function index_vault(root)
  local function walk(dir, depth)
    if depth > 12 then return end
    local ok, entries = pcall(pandoc.system.list_directory, dir)
    if not ok then return end
    for _, name in ipairs(entries) do
      if name:sub(1, 1) ~= '.' then
        local full = pandoc.path.join{ dir, name }
        if is_dir(full) then
          walk(full, depth + 1)
        else
          local stem, ext = name:match('^(.*)%.([^.]+)$')
          if ext then
            ext = ext:lower()
            if ext == 'md' then
              notes[stem] = notes[stem] or full
              notes[name] = notes[name] or full
            elseif IMAGE_EXT[ext] then
              assets[name] = assets[name] or full
              assets[stem] = assets[stem] or full
            end
          end
        end
      end
    end
  end
  walk(root, 0)
end

local function resolve_document()
  local candidates = {}
  local function add(d)
    if d and d ~= '' and not d:match('quarto%-session') then
      candidates[#candidates + 1] = d
    end
  end

  add(os.getenv('QUARTO_DOCUMENT_PATH'))       -- Quarto: the real source dir
  local input = (PANDOC_STATE.input_files or {})[1]
  add(input and pandoc.path.directory(input))  -- plain pandoc
  local ok, cwd = pcall(pandoc.system.get_working_directory)
  add(ok and cwd or nil)                       -- Quarto chdirs here too
  add(os.getenv('QUARTO_PROJECT_DIR'))         -- last resort: project root

  for _, dir in ipairs(candidates) do
    local found = find_vault(dir)
    if found then return dir, found end
  end
  return candidates[1] or '.', nil
end

local input_dir, vault = resolve_document()
if vault then index_vault(vault) end

local function relative_to_input(path)
  local ok, rel = pcall(pandoc.path.make_relative, path, input_dir)
  if ok and rel and rel ~= '' then return rel end
  return path
end

local function warn(msg)
  io.stderr:write('obsidian.lua: ' .. msg .. '\n')
end


local function extract_section(blocks, heading)
  local want = heading:lower():gsub('^%s+', ''):gsub('%s+$', '')
  local out, level = {}, nil
  for _, b in ipairs(blocks) do
    if b.t == 'Header' then
      if level then
        if b.level <= level then break end
      elseif stringify(b.content):lower() == want then
        level = b.level
        goto continue
      end
    end
    if level then out[#out + 1] = b end
    ::continue::
  end
  return out
end

local function embed_target(block)
  local inner
  if block.t == 'Figure' then
    local first = block.content[1]
    if first and (first.t == 'Plain' or first.t == 'Para') then inner = first.content end
  elseif block.t == 'Para' or block.t == 'Plain' then
    inner = block.content
  end
  if not inner or #inner ~= 1 then return nil end

  local img = inner[1]
  if img.t ~= 'Image' or not img.classes:includes('wikilink') then return nil end

  local target = img.src
  local ext = target:match('%.([^.]+)$')
  if ext and IMAGE_EXT[ext:lower()] then return nil end
  return target
end

local function missing(what, target)
  return pandoc.Strong{ pandoc.Str('[missing ' .. what .. ': ' .. target .. ']') }
end

local function transclude(blocks, depth)
  local out = {}
  for _, b in ipairs(blocks) do
    local target = embed_target(b)
    if not target then
      out[#out + 1] = b
    elseif depth >= MAX_EMBED_DEPTH then
      warn('embed depth limit reached at [[' .. target .. ']] -- not inlined')
      out[#out + 1] = pandoc.Para{ missing('embed, depth limit', target) }
    else
      local name, section = target:match('^([^#]*)#?(.*)$')
      name = name:gsub('%s+$', '')
      local path = notes[name] or notes[name .. '.md']
      local text = path and read_file(path)
      if not text then
        warn('embedded note not found: ' .. target)
        out[#out + 1] = pandoc.Para{ missing('embed', target) }
      else
        local doc = pandoc.read(text, 'markdown+wikilinks_title_after_pipe+mark')
        local sub = doc.blocks
        if section ~= '' then sub = extract_section(sub, section) end
        for _, x in ipairs(transclude(sub, depth + 1)) do
          out[#out + 1] = x
        end
      end
    end
  end
  return out
end


local function strip_inline_comments(inlines)
  local out, skipping, changed = {}, false, false
  for _, el in ipairs(inlines) do
    local is_marker = el.t == 'Str' and el.text == '%%'
    -- The single-token form, %%like this%%, arrives as one Str.
    local whole = el.t == 'Str' and el.text:match('^%%%%.*%%%%$')
    if whole then
      changed = true
    elseif is_marker then
      skipping, changed = not skipping, true
    elseif not skipping then
      out[#out + 1] = el
    else
      changed = true
    end
  end
  if not changed then return nil end
  while out[1] and (out[1].t == 'Space' or out[1].t == 'SoftBreak') do
    table.remove(out, 1)
  end
  while out[#out] and (out[#out].t == 'Space' or out[#out].t == 'SoftBreak') do
    table.remove(out)
  end
  return out
end

local function strip_comment_blocks(blocks)
  local out, skipping = {}, false
  for _, b in ipairs(blocks) do
    local textish = b.t == 'Para' or b.t == 'Plain'
    local lone = textish and #b.content == 1 and b.content[1].t == 'Str'
      and b.content[1].text == '%%'
    if lone then
      skipping = not skipping
    elseif textish and #b.content == 0 then
    elseif not skipping then
      out[#out + 1] = b
    end
  end
  return out
end


local function callout(bq)
  local first = bq.content[1]
  if not first or (first.t ~= 'Para' and first.t ~= 'Plain') then return nil end

  local head = first.content[1]
  if not head or head.t ~= 'Str' then return nil end

  local kind, fold = head.text:match('^%[!([%w%-]+)%]([%+%-]?)$')
  if not kind then return nil end
  kind = kind:lower()

  local title, body_head, seen_break = {}, {}, false
  for i = 2, #first.content do
    local el = first.content[i]
    if not seen_break and (el.t == 'SoftBreak' or el.t == 'LineBreak') then
      seen_break = true
    elseif seen_break then
      body_head[#body_head + 1] = el
    elseif not (#title == 0 and el.t == 'Space') then
      title[#title + 1] = el
    end
  end

  local body = {}
  if #body_head > 0 then body[1] = pandoc.Para(body_head) end
  for i = 2, #bq.content do body[#body + 1] = bq.content[i] end

  local quarto = CALLOUTS[kind]
  if not quarto then
    warn('unmapped callout type [!' .. kind .. '] -- kept as a blockquote')
    if #title > 0 then
      table.insert(body, 1, pandoc.Para{ pandoc.Strong(title) })
    end
    return pandoc.BlockQuote(body)
  end

  local attr = {}
  if #title > 0 then attr.title = stringify(pandoc.Para(title)) end
  if fold == '-' then attr.collapse = 'true'
  elseif fold == '+' then attr.collapse = 'false' end

  return pandoc.Div(body, pandoc.Attr('', { 'callout-' .. quarto }, attr))
end


local function wikilink(el)
  if not el.classes:includes('wikilink') then return nil end

  local target = el.target
  if target:sub(1, 1) == '@' then
    local id = target:sub(2):gsub('#.*$', '')
    return pandoc.Cite(
      { pandoc.Str('@' .. id) },
      { pandoc.Citation(id, 'NormalCitation') })
  end

  return el.content
end

local function wikiimage(el)
  if not el.classes:includes('wikilink') then return nil end

  local target = el.src
  local ext = target:match('%.([^.]+)$')
  if not (ext and IMAGE_EXT[ext:lower()]) then return nil end

  local path = assets[target] or assets[target:gsub('%.[^.]+$', '')]
  if not path then
    local fh = io.open(pandoc.path.join{ input_dir, target })
    if fh then fh:close(); return nil end
    warn('asset not found in vault: ' .. target)
    return missing('image', target)
  end

  el.src = relative_to_input(path)
  local caption = stringify(el.caption)
  local width = caption:match('^(%d+)$')
  if width then
    el.attributes.width = width .. 'px'
    el.caption = {}
  end
  return el
end

local function wikifigure(fig)
  local first = fig.content[1]
  if not first or not first.content or #first.content ~= 1 then return nil end
  local img = first.content[1]
  if img.t ~= 'Image' or not img.classes:includes('wikilink') then return nil end
  fig.caption = pandoc.Caption({})
  return fig
end

local function strip_block_id(el)
  if el.text:match('^%^[%w%-]+$') then return {} end
  return nil
end

local function mark(el)
  if not el.classes:includes('mark') or not FORMAT:match('typst') then return nil end
  local out = { pandoc.RawInline('typst', '#highlight[') }
  for _, x in ipairs(el.content) do out[#out + 1] = x end
  out[#out + 1] = pandoc.RawInline('typst', ']')
  return out
end

return {
  { Pandoc = function(doc)
      if not vault then
        warn('not inside an Obsidian vault -- [[links]] and ![[embeds]] '
          .. 'cannot be resolved')
      end
      doc.blocks = transclude(doc.blocks, 0)
      return doc
    end },
  { Blocks = strip_comment_blocks, Inlines = strip_inline_comments },
  { BlockQuote = callout, Link = wikilink, Image = wikiimage,
    Figure = wikifigure, Span = mark, Str = strip_block_id },
}
