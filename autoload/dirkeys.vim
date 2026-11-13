" ============================================================================
" File:        autoload/dirkeys.vim
" Description: 项目本地快捷键加载与冲突检测核心
" ============================================================================

let s:save_cpo = &cpo
set cpo&vim

let s:loaded_files = []
let s:loaded_dir   = ''

" ---------- 基础工具 ----------

function! s:err(msg) abort
  echohl ErrorMsg
  echomsg '[dirkeys] ' . a:msg
  echohl None
endfunction

function! s:warn(msg) abort
  echohl WarningMsg
  echomsg '[dirkeys] ' . a:msg
  echohl None
endfunction

function! s:debug(msg) abort
  if get(g:, 'dirkeys_verbose', 0)
    echomsg '[dirkeys] ' . a:msg
  endif
endfunction

function! s:short(path) abort
  return fnamemodify(a:path, ':~:.')
endfunction

function! s:mode_str(mode) abort
  if empty(a:mode) || a:mode ==# ' '
    return 'nvo'
  endif
  return a:mode
endfunction

" ---------- 目录发现 ----------

function! dirkeys#find_dir(...) abort
  let l:base = a:0 ? a:1 : getcwd()
  let l:name = get(g:, 'dirkeys_dirname', '.dirkeys')

  let l:candidate = simplify(l:base . '/' . l:name)
  if isdirectory(l:candidate)
    return l:candidate
  endif

  if get(g:, 'dirkeys_search_upward', 0)
    let l:parent = fnamemodify(l:base, ':h')
    while l:parent !=# l:base && l:parent !=# '' && l:parent !=# '/'
      let l:candidate = simplify(l:parent . '/' . l:name)
      if isdirectory(l:candidate)
        return l:candidate
      endif
      let l:base   = l:parent
      let l:parent = fnamemodify(l:base, ':h')
    endwhile
  endif
  return ''
endfunction

" ---------- 文件扫描 ----------

function! dirkeys#scan(dir) abort
  if empty(a:dir) || !isdirectory(a:dir)
    return []
  endif
  let l:pattern = get(g:, 'dirkeys_recursive', 1) ? '**/*.vim' : '*.vim'
  let l:files   = globpath(a:dir, l:pattern, 1, 1)
  call filter(l:files, 'filereadable(v:val)')
  if get(g:, 'dirkeys_exclude_hidden', 1)
    call filter(l:files, "fnamemodify(v:val, ':t') !~# '^\\.'")
  endif
  call sort(l:files)   " 保证加载顺序稳定
  return l:files
endfunction

" ---------- 映射快照 ----------

function! s:snapshot() abort
  if exists('*maplist')
    return s:snapshot_maplist()
  endif
  return s:snapshot_legacy()
endfunction

function! s:snapshot_maplist() abort
  let l:res = {}
  for l:m in maplist()
    let l:mode = s:mode_str(l:m.mode)
    let l:key  = l:mode . '|' . l:m.lhs
    let l:res[l:key] = {
          \ 'mode':    l:mode,
          \ 'lhs':     l:m.lhs,
          \ 'rhs':     l:m.rhs,
          \ 'noremap': get(l:m, 'noremap', 0),
          \ 'buffer':  get(l:m, 'buffer',  0),
          \ }
  endfor
  return l:res
endfunction

function! s:snapshot_legacy() abort
  let l:res = {}
  for l:mode in ['n', 'v', 'x', 's', 'o', 'i', 'l', 'c', 't']
    let l:out = ''
    redir => l:out
    silent! execute l:mode . 'map'
    redir END

    for l:line in split(l:out, "\n")
      let l:m = matchlist(l:line, '^\(\S*\)\s\+\(\S\+\)\s\+\(.*\)$')
      if len(l:m) < 4
        continue
      endif
      let l:mkey = s:mode_str(l:m[1])
      let l:key  = l:mkey . '|' . l:m[2]
      let l:res[l:key] = {
            \ 'mode':    l:mkey,
            \ 'lhs':     l:m[2],
            \ 'rhs':     l:m[3],
            \ 'noremap': 0,
            \ 'buffer':  0,
            \ }
    endfor
  endfor
  return l:res
endfunction

" ---------- 单个文件冲突检查 ----------

function! s:check_file(file, pre, post, baseline, local_defs) abort
  let l:warns = []
  let l:fname = s:short(a:file)

  for [l:key, l:val] in items(a:post)
    let l:prev = get(a:pre, l:key, {})
    if !empty(l:prev)
          \ && l:prev.rhs ==# l:val.rhs
          \ && l:prev.noremap ==# l:val.noremap
      continue
    endif

    " 1) 与全局基线冲突
    if has_key(a:baseline, l:key)
      let l:b = a:baseline[l:key]
      if l:b.rhs !=# l:val.rhs || l:b.noremap !=# l:val.noremap
        call add(l:warns, {
              \ 'level': 'global',
              \ 'file':  l:fname,
              \ 'lhs':   l:val.lhs,
              \ 'mode':  l:val.mode,
              \ 'old':   l:b.rhs,
              \ 'new':   l:val.rhs,
              \ })
      endif
    endif

    " 2) 与先前加载的本地文件冲突
    if has_key(a:local_defs, l:key)
      let l:p = a:local_defs[l:key]
      if l:p.val.rhs !=# l:val.rhs || l:p.val.noremap !=# l:val.noremap
        call add(l:warns, {
              \ 'level':     'cross',
              \ 'file':      l:fname,
              \ 'prev_file': l:p.file,
              \ 'lhs':       l:val.lhs,
              \ 'mode':      l:val.mode,
              \ 'old':       l:p.val.rhs,
              \ 'new':       l:val.rhs,
              \ })
      endif
    endif

    let a:local_defs[l:key] = {'file': l:fname, 'val': l:val}
  endfor

  return l:warns
endfunction

function! s:print_warnings(warnings) abort
  echohl WarningMsg
  echomsg '[dirkeys] 检测到 ' . len(a:warnings) . ' 处快捷键冲突:'
  for l:w in a:warnings
    if l:w.level ==# 'global'
      echomsg printf('  [覆盖全局] %s (%s) 由 %s 定义: %s -> %s',
            \ l:w.lhs, l:w.mode, l:w.file, l:w.old, l:w.new)
    else
      echomsg printf('  [文件冲突] %s (%s) 由 %s 覆盖 %s: %s -> %s',
            \ l:w.lhs, l:w.mode, l:w.file, l:w.prev_file, l:w.old, l:w.new)
    endif
  endfor
  echohl None
endfunction

" ---------- 加载 ----------

function! dirkeys#load() abort
  if !get(g:, 'dirkeys_enable', 1)
    call s:debug('插件已禁用')
    return
  endif

  let l:dir = dirkeys#find_dir()
  if empty(l:dir)
    call s:debug('未找到配置目录: ' . get(g:, 'dirkeys_dirname', '.vim'))
    return
  endif

  let l:files = dirkeys#scan(l:dir)
  if empty(l:files)
    call s:debug('配置目录中无 .vim 文件: ' . l:dir)
    return
  endif

  call s:debug('从 ' . l:dir . ' 加载 ' . len(l:files) . ' 个文件')

  let l:baseline   = s:snapshot()
  let l:local_defs = {}
  let l:warnings   = []
  let l:loaded     = []
  let l:level      = get(g:, 'dirkeys_conflict_level', 'warn')

  for l:file in l:files
    let l:pre = s:snapshot()
    try
      execute 'source ' . fnameescape(l:file)
    catch /^dirkeys: /
      break
    catch
      call s:err('加载失败 ' . s:short(l:file) . ': ' . v:exception)
      continue
    endtry
    let l:post = s:snapshot()

    let l:file_warns = s:check_file(l:file, l:pre, l:post, l:baseline, l:local_defs)
    call extend(l:warnings, l:file_warns)
    call add(l:loaded, l:file)

    if !empty(l:file_warns) && l:level ==# 'error'
      let s:loaded_files = l:loaded
      let s:loaded_dir   = l:dir
      throw 'dirkeys: 检测到快捷键冲突，中止加载'
    endif
  endfor

  let s:loaded_files = l:loaded
  let s:loaded_dir   = l:dir

  if !empty(l:warnings)
    if l:level !=# 'silent'
      call s:print_warnings(l:warnings)
    endif
  else
    call s:debug('加载完成，未检测到冲突')
  endif
endfunction

function! dirkeys#reload() abort
  if !get(g:, 'dirkeys_enable', 1)
    return
  endif
  call s:debug('重新加载本地快捷键配置')
  call dirkeys#load()
endfunction

" ---------- 状态 ----------

function! dirkeys#status() abort
  echohl Title
  echomsg '===== dirkeys 状态 ====='
  echohl None
  echomsg '插件启用:     ' . (get(g:, 'dirkeys_enable', 1) ? 'yes' : 'no')
  echomsg '配置目录名:   ' . get(g:, 'dirkeys_dirname', '.dirkeys')
  echomsg '已加载目录:   ' . (empty(s:loaded_dir) ? '(无)' : s:loaded_dir)
  echomsg '已加载文件数: ' . len(s:loaded_files)
  for l:f in s:loaded_files
    echomsg '  - ' . s:short(l:f)
  endfor
  echomsg '冲突级别:     ' . get(g:, 'dirkeys_conflict_level', 'warn')
endfunction

" ---------- 编辑 / 预检 ----------

function! dirkeys#edit() abort
  let l:dir = dirkeys#find_dir()
  if empty(l:dir)
    call s:err('未找到配置目录: ' . get(g:, 'dirkeys_dirname', '.vim'))
    return
  endif
  let l:files = dirkeys#scan(l:dir)
  if !empty(l:files)
    execute 'edit ' . fnameescape(l:files[0])
  else
    execute 'edit ' . fnameescape(l:dir)
  endif
endfunction

function! s:cmd_mode(cmd) abort
  if a:cmd ==# 'map' || a:cmd ==# 'noremap'
    return 'nvo'
  endif
  return a:cmd[0]
endfunction

function! dirkeys#check() abort
  let l:dir = dirkeys#find_dir()
  if empty(l:dir)
    call s:warn('未找到配置目录')
    return
  endif
  let l:files = dirkeys#scan(l:dir)
  if empty(l:files)
    call s:warn('目录中没有 .vim 文件')
    return
  endif

  let l:baseline = s:snapshot()
  let l:defined  = {}
  let l:warns    = []

  for l:file in l:files
    let l:fname  = s:short(l:file)
    let l:lineno = 0
    for l:line in readfile(l:file)
      let l:lineno += 1
      let l:m = matchlist(l:line,
            \ '^\s*\(noremap\|nnoremap\|vnoremap\|xnoremap\|snoremap\|onoremap\|inoremap\|lnoremap\|cnoremap\|tnoremap\|map\|nmap\|vmap\|xmap\|smap\|omap\|imap\|lmap\|cmap\|tmap\)\s\+\(\S\+\)')
      if len(l:m) < 3
        continue
      endif
      let l:cmd  = l:m[1]
      let l:lhs  = l:m[2]
      let l:mode = s:cmd_mode(l:cmd)
      let l:key  = l:mode . '|' . l:lhs

      " 兼容 maplist 拆分为单模式的情况
      let l:probe = (l:mode ==# 'nvo')
            \ ? ['nvo', 'n', 'v', 'o'] : [l:mode]
      for lm in l:probe
        if has_key(l:baseline, lm . '|' . l:lhs)
          call add(l:warns, printf('[全局冲突] %s:%d  %s (%s) 覆盖已有全局映射',
                \ l:fname, l:lineno, l:lhs, l:mode))
          break
        endif
      endfor

      if has_key(l:defined, l:key)
        call add(l:warns, printf('[本地冲突] %s:%d  %s (%s) 与 %s 重复',
              \ l:fname, l:lineno, l:lhs, l:mode, l:defined[l:key]))
      endif
      let l:defined[l:key] = l:fname . ':' . l:lineno
    endfor
  endfor

  if empty(l:warns)
    echomsg '[dirkeys] 静态检查通过，未发现冲突'
  else
    echohl WarningMsg
    echomsg '[dirkeys] 静态检查发现 ' . len(l:warns) . ' 处潜在冲突:'
    for l:w in l:warns
      echomsg '  ' . l:w
    endfor
    echohl None
  endif
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo
