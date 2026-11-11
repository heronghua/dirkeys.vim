" ============================================================================
" File:        plugin/dirkeys.vim
" Description: 自动加载项目本地 .vim 目录中的快捷键配置，并检测冲突
" Author:      dirkeys.vim
" License:     MIT
" ============================================================================

if exists('g:loaded_dirkeys')
  finish
endif
let g:loaded_dirkeys = 1

let s:save_cpo = &cpo
set cpo&vim

" ---------- 默认配置 ----------
function! s:init_default(name, value) abort
  if !exists('g:' . a:name)
    let g:{a:name} = a:value
  endif
endfunction

call s:init_default('dirkeys_enable',               1)
call s:init_default('dirkeys_auto_load',            1)
call s:init_default('dirkeys_dirname',              '.vim')
call s:init_default('dirkeys_recursive',            1)
call s:init_default('dirkeys_search_upward',        0)
call s:init_default('dirkeys_conflict_level',       'warn')  " warn | error | silent
call s:init_default('dirkeys_reload_on_dirchange',  0)
call s:init_default('dirkeys_verbose',              0)

" ---------- 用户命令 ----------
command! -nargs=0 DirkeysLoad    call dirkeys#load()
command! -nargs=0 DirkeysReload  call dirkeys#reload()
command! -nargs=0 DirkeysStatus  call dirkeys#status()
command! -nargs=0 DirkeysCheck   call dirkeys#check()
command! -nargs=0 DirkeysEdit    call dirkeys#edit()

" ---------- 自动加载 ----------
if g:dirkeys_enable && g:dirkeys_auto_load
  augroup dirkeys_auto
    autocmd!
    autocmd VimEnter * ++nested call dirkeys#load()
    if get(g:, 'dirkeys_reload_on_dirchange', 0) && exists('##DirChanged')
      autocmd DirChanged * ++nested call dirkeys#reload()
    endif
  augroup END
endif

let &cpo = s:save_cpo
unlet s:save_cpo