" DBGp client: a remote debugger interface to the DBGp protocol
"
" Script Info and Documentation  {{{
"=============================================================================
"    Copyright: Copyright (C) 2007 Sam Ghods
"      License: The MIT License
"
"               Permission is hereby granted, free of charge, to any person obtaining
"               a copy of this software and associated documentation files
"               (the "Software"), to deal in the Software without restriction,
"               including without limitation the rights to use, copy, modify,
"               merge, publish, distribute, sublicense, and/or sell copies of the
"               Software, and to permit persons to whom the Software is furnished
"               to do so, subject to the following conditions:
"
"               The above copyright notice and this permission notice shall be included
"               in all copies or substantial portions of the Software.
"
"               THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
"               OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
"               MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
"               IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
"               CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
"               TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
"               SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
" Name Of File: debugger.vim, debugger.py
"  Description: remote debugger interface to DBGp protocol
"   Maintainer: Sam Ghods <sam <at> box.net>
"  Last Change: 06 Mar 2013
"          URL: http://www.vim.org/scripts/script.php?script_id=1929
"      Version: 1.1.1
"               Originally written by Seung Woo Shin <segv <at> sayclub.com>
"               The original script is located at:
"               http://www.vim.org/scripts/script.php?script_id=1152
"        Usage: N.B.: For a complete tutorial on how to setup this script,
"               please visit:
"               http://tech.blog.box.net/2007/06/20/how-to-debug-php-with-vim-and-xdebug-on-linux/
"               -----
"
"               This file should reside in the plugins directory along
"               with debugger.py and be automatically sourced.
"
"               By default, the script expects the debugging engine to connect
"               on port 9000. You can change this with the g:debuggerPort
"               variable by putting the following line your vimrc:
"
"                 let g:debuggerPort = 10001
"
"               where 10001 is the new port number you want the server to
"               connect to.
"
"               There are three maximum limits you can set referring to the
"               properties (variables) returned by the debugging engine.
"
"               g:debuggerMaxChildren (default 32): The max number of array or
"               object children to initially retrieve per variable.
"               For example:
"
"                 let g:debuggerMaxChildren = 64
"
"               g:debuggerMaxData (default 1024 bytes): The max amount of
"               variable data to retrieve.
"               For example:
"
"                 let g:debuggerMaxData = 2048
"
"               g:debuggerMaxDepth (default 1): The maximum depth that the
"               debugger engine may return when sending arrays, hashs or
"               object structures to the IDE.
"               For example:
"
"                 let g:debuggerMaxDepth = 10
"
"               Finally, if you use the Mini Buffer Explorer vim plugin,
"               minibufexpl.vim, running the debugger may mess up your window
"               setup. As a result the script has support to close and open
"               the explorer when you enter and quit debugging sessions. To
"               enable this support, add the following line to your vimrc:
"
"                 let g:debuggerMiniBufExpl = 1
"
"      History: 1.1.1 o Added a check so the script doesn't load if python is
"                     not compiled in. (Contributed by Lars Becker.)
"               1.1   o Added vim variable to change port.
"                     o You can now put debugger.py in either runtime directory
"                     or the home directory.
"                     o Added to ability to change max children, data and depth
"                     settings.
"                     o Made it so stack_get wouldn't be called if the debugger
"                     has already stopped.
"                     o Added support for minibufexpl.vim.
"                     o License added.
"               1.0   o Initial release on December 7, 2004
"
" Known Issues: The code is designed for the DBGp protocol, but it has only been
"               tested with XDebug 2.0RC4. If anyone would like to contribute patches
"               to get it working with other DBGp software, I would be happy
"               to implement them.
"
"               Sometimes things go a little crazy... breakpoints don't show
"               up, too many windows are created / not enough are closed, and
"               so on... if you can actually find a set of solidly
"               reproducible steps that lead to a bug, please do e-mail <sam
"               <at> box.net> and I will take a look.
"
"         Todo: Compatibility for other DBGp engines.
"
"               Add a status line/window which constantly shows what the current
"               status of the debugger is. (starting, break, stopped, etc.)
"
"=============================================================================
" }}}


"=============================================================================
" check that everything is OK
"=============================================================================
if !has("python")
  finish
endif

" Load debugger.py either from the runtime directory (usually
" /usr/local/share/vim/vim71/plugin/ if you're running Vim 7.1) or from the
" home vim directory (usually ~/.vim/plugin/).
let s:debugger_py = expand('<sfile>:p:h') . '/debugger.py'
if filereadable(s:debugger_py)
  execute 'pyfile ' . s:debugger_py
else
  call confirm('debugger.vim: Unable to find debugger.py. Place it in either your home vim directory or in the Vim runtime directory.', 'OK')
endif


"=============================================================================
" map debugging function keys
"=============================================================================
map <silent> <Plug>(debugger_resize)       :<C-U>python debugger_resize()<CR>
map <silent> <Plug>(debugger_step_into)    :<C-U>python debugger_command('step_into')<CR>
map <silent> <Plug>(debugger_step_over)    :<C-U>python debugger_command('step_over')<CR>
map <silent> <Plug>(debugger_step_out)     :<C-U>python debugger_command('step_out')<CR>
map <silent> <Plug>(debugger_run)          :<C-U>call <SID>startDebugging()<CR>
map <silent> <Plug>(debugger_quit)         :<C-U>call <SID>stopDebugging()<CR>
map <silent> <Plug>(debugger_run_to)       :<C-U>python debugger_run_to()<CR>
map <silent> <Plug>(debugger_toggle_mark)  :<C-U>python debugger_mark()<CR>
map <silent> <Plug>(debugger_stack_up)     :<C-U>python debugger_up()<CR>
map <silent> <Plug>(debugger_stack_down)   :<C-U>python debugger_down()<CR>
map <silent> <Plug>(debugger_context_get)  :<C-U>python debugger_watch_input("context_get")<CR>A<CR>
map <silent> <Plug>(debugger_property_get) :<C-U>python debugger_watch_input("property_get", '<cword>')<CR>A<CR>
map <silent> <Plug>(debugger_eval)         :<C-U>python debugger_watch_input("eval")<CR>A

" default key mappings
let s:default_key_mappings = [
      \ ['<F1>',      '<Plug>(debugger_resize)'],
      \ ['<F2>',      '<Plug>(debugger_step_into)'],
      \ ['<F3>',      '<Plug>(debugger_step_over)'],
      \ ['<F4>',      '<Plug>(debugger_step_out)'],
      \ ['<F5>',      '<Plug>(debugger_run)'],
      \ ['<F6>',      '<Plug>(debugger_quit)'],
      \ ['<F7>',      '<Plug>(debugger_run_to)'],
      \ ['<F8>',      '<Plug>(debugger_toggle_mark)'],
      \ ['<F9>',      '<Plug>(debugger_stack_up)'],
      \ ['<F10>',     '<Plug>(debugger_stack_down)'],
      \ ['<F11>',     '<Plug>(debugger_context_get)'],
      \ ['<F12>',     '<Plug>(debugger_property_get)'],
      \ ['<Leader>e', '<Plug>(debugger_eval)'],
      \ ]

if !exists('g:debugger_no_default_key_mappings') || !g:debugger_no_default_key_mappings
  for [s:key, s:cmd] in s:default_key_mappings
    execute 'map' s:key s:cmd
  endfor
  unlet s:key s:cmd
endif


"=============================================================================
" Initialization
"=============================================================================
hi DbgCurrent term=reverse ctermfg=White ctermbg=Red gui=reverse
hi DbgBreakPt term=reverse ctermfg=White ctermbg=Green gui=reverse

command! -nargs=0 DebuggerRun  call <SID>startDebugging()
command! -nargs=0 DebuggerQuit call <SID>stopDebugging()
command! -nargs=? Bp python debugger_mark('<args>')
command! -nargs=0 Up python debugger_up()
command! -nargs=0 Dn python debugger_down()

sign define current text=->  texthl=DbgCurrent linehl=DbgCurrent
sign define breakpt text=B>  texthl=DbgBreakPt linehl=DbgBreakPt

if !exists('g:debuggerPort')
  let g:debuggerPort = 9000
endif
if !exists('g:debuggerProxyHost')
  let g:debuggerProxyHost = 'localhost'
endif
if !exists('g:debuggerProxyPort')
  let g:debuggerProxyPort = 0
endif
if !exists('g:debuggerProxyKey')
  let g:debuggerProxyKey = ''
endif
if !exists('g:debuggerMaxChildren')
  let g:debuggerMaxChildren = 32
endif
if !exists('g:debuggerMaxData')
  let g:debuggerMaxData = 1024
endif
if !exists('g:debuggerMaxDepth')
  let g:debuggerMaxDepth = 1
endif
if !exists('g:debuggerMiniBufExpl')
  let g:debuggerMiniBufExpl = 0
endif
if !exists('g:debuggerFileMapping')
  let g:debuggerFileMapping = []
endif
if !exists('g:debuggerTimeout')
  let g:debuggerTimeout = 10
endif
if !exists('g:debuggerDedicatedTab')
  let g:debuggerDedicatedTab = 1
endif
if !exists('g:debuggerDebugMode')
  let g:debuggerDebugMode = 0
endif



"=============================================================================
" Debugging functions
"=============================================================================

function! s:startDebugging()
  python debugger_run()
endfunction

function! s:stopDebugging()
  python debugger_quit()
  " if your code goes weird re-source your syntax file, or any other
  " cleanups here
  "source ~/.vim/plugin/torte.vim
endfunction

"=============================================================================
" Help functions
"=============================================================================

function! s:getDebuggerKeyMappings()
  redir => list | execute 'silent! map' | redir END
  let maps = map( split(list, '\n'),
        \ 'matchlist(v:val,''^.\s\+\(\S\+\)\s\+\%(\*\s\+\)\?\(\S\+\)'')[1:2]')
  let ret = {}
  for [key, cmd] in maps
    let ret[cmd] = key
  endfor
  return ret
endfunction

function! s:makeHelp()
  let file = get(split(globpath(&rtp, 'doc/dbgp_cheat.txt'), '\n'), 0, '')
  if !filereadable(file) | return [] | endif
  let text = join(readfile(file), "\n")
  let maps = s:getDebuggerKeyMappings()
  for [key, cmd] in s:default_key_mappings
    let pat = '\s\zs' . escape(key, '[].\') . '\s\+'
    let sub = has_key(maps, cmd) ? escape(maps[cmd], '&') : ''
    let text = substitute(text, pat, '\=printf("%-".len(submatch(0))."s",sub)', '')
  endfor
  return split(text, "\n")
endfunction

"=============================================================================
" Init Debugger python script
"=============================================================================

let s:SID = maparg('<Plug>(debugger_run)', '', 0, 1)['sid']
execute 'python debugger_init(' s:SID ')'
