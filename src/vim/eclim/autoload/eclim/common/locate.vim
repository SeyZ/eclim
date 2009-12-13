" Author:  Eric Van Dewoestine
"
" Description: {{{
"   Implements the :LocateFile functionality.
"
" License:
"
" Copyright (C) 2005 - 2009  Eric Van Dewoestine
"
" This program is free software: you can redistribute it and/or modify
" it under the terms of the GNU General Public License as published by
" the Free Software Foundation, either version 3 of the License, or
" (at your option) any later version.
"
" This program is distributed in the hope that it will be useful,
" but WITHOUT ANY WARRANTY; without even the implied warranty of
" MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
" GNU General Public License for more details.
"
" You should have received a copy of the GNU General Public License
" along with this program.  If not, see <http://www.gnu.org/licenses/>.
"
" }}}

" Global Variables {{{
if !exists('g:EclimLocateFileDefaultAction')
  let g:EclimLocateFileDefaultAction = g:EclimDefaultFileOpenAction
endif

if !exists('g:EclimLocateFileScope')
  let g:EclimLocateFileScope = 'project'
endif

if !exists('g:EclimLocateFileFuzzy')
  let g:EclimLocateFileFuzzy = 1
endif
" }}}

" Script Variables {{{
let s:command_locate = '-command locate_file -s "<scope>"'
let s:scopes = [
    \ 'project',
    \ 'workspace',
  \ ]
let s:help = [
    \ '<esc> - close the locate prompt + results',
    \ '<tab>, <down> - select the next file',
    \ '<s-tab>, <up> - select the previous file',
    \ '<cr> - open selected file w/ default action',
    \ '<c-e> - open with :edit',
    \ '<c-s> - open in a split window',
    \ '<c-t> - open in a new tab',
    \ '<c-l> - choose search scope',
    \ '<c-h> - toggle help buffer',
  \ ]
" }}}

" LocateFile(action, file) {{{
" Locates a file using the specified action for opening the file when found.
"   action - '' (use user default), 'split', 'edit', etc.
"   file - 'somefile.txt',
"          '', (kick off completion mode),
"          '<cursor>' (locate the file under the cursor)
function eclim#common#locate#LocateFile(action, file)
  let project = eclim#project#util#GetCurrentProjectName()
  let scope = (g:EclimLocateFileScope == 'workspace' ? 'workspace' : 'project')
  if scope == 'project' && project == ''
    let scope = 'workspace'
  endif

  let workspace = eclim#eclipse#ChooseWorkspace()
  if workspace == '0'
    return
  endif

  if !eclim#PingEclim(0, workspace)
    call eclim#util#EchoError('Unable to connect to eclimd.')
    return
  endif

  let results = []
  let action = a:action
  if action == ''
    let action = g:EclimLocateFileDefaultAction
  endif

  let file = a:file
  if file == ''
    call s:LocateFileCompletionInit(action, scope, project, workspace)
    return
  elseif file == '<cursor>'
    let file = eclim#util#GrabUri()

    " if grabbing a relative url, remove any anchor info or query parameters
    let file = substitute(file, '[#?].*', '', '')
  endif

  let name = fnamemodify(file, ':t')
  if name == ''
    call eclim#util#Echo('Please supply more than just a directory name.')
    return
  endif

  let pattern = file
  let pattern = s:LocateFileConvertPattern(pattern)
  let command = s:command_locate
  let command = substitute(command, '<scope>', scope, '')
  let command .= ' -p "' . pattern . '"'
  if scope == 'project'
    let command .= ' -n "' . project . '"'
  endif

  let port = eclim#client#nailgun#GetNgPort(workspace)
  let results = split(eclim#ExecuteEclim(command, port), '\n')
  if len(results) == 1 && results[0] == '0'
    return
  endif

  call map(results, "split(v:val, '|')[2]")

  let result = ''
  " One result.
  if len(results) == 1
    let result = results[0]

  " More than one result.
  elseif len(results) > 1
    let message = "Multiple results, choose the file to open"
    let response = eclim#util#PromptList(message, results, g:EclimInfoHighlight)
    if response == -1
      return
    endif

    let result = results[response]

  " No results
  else
    call eclim#util#Echo('Unable to locate file named "' . file . '".')
    return
  endif

  call eclim#util#GoToBufferWindowOrOpen(
    \ escape(eclim#util#Simplify(result), ' '), action)
  call eclim#util#Echo(' ')
endfunction " }}}

" LocateFileCompletion() {{{
function eclim#common#locate#LocateFileCompletion()
  let completions = []
  let display = []
  let name = substitute(getline('.'), '^>\s*', '', '')
  if name !~ '^\s*$'
    let pattern = name
    if g:EclimLocateFileFuzzy
      let pattern = '.*' . substitute(pattern, '\(.\)', '\1.*?', 'g')
      let pattern = substitute(pattern, '\.\([^*]\)', '\\.\1', 'g')
    else
      let pattern = s:LocateFileConvertPattern(pattern)
    endif

    let command = s:command_locate
    let command = substitute(command, '<scope>', b:scope, '')
    let command .= ' -p "' . pattern . '"'
    if b:project != ''
      let command .= ' -n "' . b:project . '"'
    endif

    let port = eclim#client#nailgun#GetNgPort(b:workspace)
    let results = split(eclim#ExecuteEclim(command, port), '\n')
    if len(results) == 1 && results[0] == '0'
      let winnr = winnr()
      exec bufwinnr(b:results_bufnum) . 'winc w'
      1,$delete _
      exec winnr . 'winc w'
      return
    endif
    if !empty(results)
      for result in results
        let parts = split(result, '|')
        let dict = {'word': parts[0], 'menu': parts[1], 'info': parts[2]}
        call add(completions, dict)
        call add(display, parts[0] . '  ' . parts[1])
      endfor
    endif
  endif
  let b:completions = completions
  let winnr = winnr()
  exec bufwinnr(b:results_bufnum) . 'winc w'
  1,$delete _
  call append(1, display)
  1,1delete _
  exec winnr . 'winc w'

  " part of bad hack for gvim on windows
  let b:start_selection = 1

  call s:LocateFileSelection(1)
endfunction " }}}

" s:LocateFileCompletionInit(action, scope, project, workspace) {{{
function s:LocateFileCompletionInit(action, scope, project, workspace)
  let file = expand('%')
  let bufnum = bufnr('%')
  let winrestcmd = winrestcmd()

  topleft 10split \[Locate\ Results\]
  set filetype=locate_results
  setlocal nonumber nowrap
  setlocal noswapfile nobuflisted
  setlocal buftype=nofile bufhidden=delete

  let results_bufnum = bufnr('%')

  let locate_in = (a:scope == 'project' ? a:project : 'workspace')
  exec 'topleft 1split ' . escape('[Locate in ' . locate_in . ']', ' []')
  call setline(1, '> ')
  call cursor(1, col('$'))
  set filetype=locate_prompt
  syntax match Keyword /^>/
  set winfixheight
  setlocal nonumber
  setlocal nolist
  setlocal noswapfile nobuflisted
  setlocal buftype=nofile bufhidden=delete

  let b:bufnum = bufnum
  let b:project = a:project
  let b:workspace = a:workspace
  let b:scope = a:scope
  let b:results_bufnum = results_bufnum
  let b:help_bufnum = 0
  let b:selection = 1
  let b:updatetime = &updatetime

  set updatetime=300

  augroup locate_file_init
    autocmd!
    exec 'autocmd InsertLeave <buffer> let &updatetime = ' . b:updatetime . ' | ' .
      \ 'doautocmd BufWinLeave | bd | ' .
      \ 'doautocmd BufWinLeave | bd ' . b:results_bufnum . ' | ' .
      \ 'call eclim#util#GoToBufferWindow(' .  b:bufnum . ') | ' .
      \ 'doautocmd BufEnter | ' .
      \ 'doautocmd WinEnter | ' .
      \ winrestcmd
  augroup END

  " enable completion after user starts typing
  call s:LocateFileCompletionAutocmdDeferred()

  imap <buffer> <silent> <tab> <c-r>=<SID>LocateFileSelection("n")<cr>
  imap <buffer> <silent> <down> <c-r>=<SID>LocateFileSelection("n")<cr>
  imap <buffer> <silent> <s-tab> <c-r>=<SID>LocateFileSelection("p")<cr>
  imap <buffer> <silent> <up> <c-r>=<SID>LocateFileSelection("p")<cr>
  exec 'imap <buffer> <silent> <cr> ' .
    \ '<c-r>=<SID>LocateFileSelect("' . a:action . '")<cr>'
  imap <buffer> <silent> <c-e> <c-r>=<SID>LocateFileSelect('edit')<cr>
  imap <buffer> <silent> <c-s> <c-r>=<SID>LocateFileSelect('split')<cr>
  imap <buffer> <silent> <c-t> <c-r>=<SID>LocateFileSelect("tablast \| tabnew")<cr>
  imap <buffer> <silent> <c-l> <c-r>=<SID>LocateFileChangeScope()<cr>
  imap <buffer> <silent> <c-h> <c-r>=<SID>LocateFileHelp()<cr>

  startinsert!
endfunction " }}}

" s:LocateFileCompletionAutocmd() {{{
function s:LocateFileCompletionAutocmd()
  augroup locate_file
    autocmd!
    autocmd CursorHoldI <buffer> call eclim#common#locate#LocateFileCompletion()
  augroup END
endfunction " }}}

" s:LocateFileCompletionAutocmdDeferred() {{{
function s:LocateFileCompletionAutocmdDeferred()
  augroup locate_file
    autocmd!
    autocmd CursorMovedI <buffer> call <SID>LocateFileCompletionAutocmd()
  augroup END
endfunction " }}}

" s:LocateFileSelection(sel) {{{
function s:LocateFileSelection(sel)
  " pause completion while tabbing though results
  augroup locate_file
    autocmd!
  augroup END

  let sel = a:sel
  let prev_sel = b:selection

  " bad hack for gvim on windows
  let start_sel = b:start_selection
  let double_defer = 0
  if sel =~ '^[np]$' && (has('win32') || has('win64'))
    let double_defer = b:start_selection == 1
    let b:start_selection = 0
  endif

  let winnr = winnr()
  exec bufwinnr(b:results_bufnum) . 'winc w'

  if sel == 'n'
    let sel = prev_sel < line('$') ? prev_sel + 1 : 1
  elseif sel == 'p'
    let sel = prev_sel > 1 ? prev_sel - 1 : line('$')
  endif

  syntax clear
  exec 'syntax match PmenuSel /\%' . sel . 'l.*/'
  exec 'call cursor(' . sel . ', 1)'
  normal! zt

  exec winnr . 'winc w'

  exec 'let b:selection = ' . sel

  if double_defer
    augroup locate_file
      autocmd!
      autocmd CursorMovedI <buffer> call <SID>LocateFileCompletionAutocmdDeferred()
    augroup END
  else
    call s:LocateFileCompletionAutocmdDeferred()
  endif

  return ''
endfunction " }}}

" s:LocateFileSelect(action) {{{
function s:LocateFileSelect(action)
  if exists('b:completions') && !empty(b:completions)
    let winnr = winnr()
    let file = eclim#util#Simplify(b:completions[b:selection - 1].info)
    let bufnum = bufnr('%')
    let results_bufnum = b:results_bufnum
    let updatetime = b:updatetime
    call eclim#util#GoToBufferWindow(b:bufnum)
    call eclim#util#GoToBufferWindowOrOpen(escape(file, '\'), a:action)
    call feedkeys(
      \ "\<esc>:let &updatetime = " . updatetime . " | " .
      \ ":bd " . bufnum . " | " .
      \ "bd " . results_bufnum . " | " .
      \ "doautocmd WinEnter\<cr>", 'n')
  endif
  return ''
endfunction " }}}

" s:LocateFileChangeScope() {{{
function s:LocateFileChangeScope()
  if b:help_bufnum && bufexists(b:help_bufnum)
    exec 'bdelete ' . b:help_bufnum
  endif

  let winnr = winnr()
  exec bufwinnr(b:results_bufnum) . 'winc w'
  silent! noautocmd exec '50vnew \[Locate\ Scope\]'
  let b:locate_winnr = winnr
  stopinsert
  set modifiable
  call append(1, s:scopes)
  1,1delete _
  call append(line('$'),
    \ ['', '" <cr> - select a scope', '" <c-c>, <c-l>, or q - cancel'])
  syntax match Comment /^".*/
  set nomodifiable
  set winfixheight
  setlocal nonumber
  setlocal nolist
  setlocal noswapfile nobuflisted
  setlocal buftype=nofile bufhidden=delete

  nmap <buffer> <silent> <cr> :call <SID>ChooseScope()<cr>
  nmap <buffer> <silent> q :call <SID>CloseScopeChooser()<cr>
  nmap <buffer> <silent> <c-c> :call <SID>CloseScopeChooser()<cr>
  nmap <buffer> <silent> <c-l> :call <SID>CloseScopeChooser()<cr>

  return ''
endfunction " }}}

" s:ChooseScope() {{{
function s:ChooseScope()
  let scope = getline('.')
  if scope =~ '^"\|^\s*$'
    return
  endif

  if scope == 'project'
    let project = ''
    let names = eclim#project#util#GetProjectNames()
    let prompt = 'Choose a project (ctrl-c to cancel): '
    while project == ''
      let project = input(
        \ prompt, '', 'customlist,eclim#project#util#CommandCompleteProject')
      if project == ''
        echo ''
        return
      endif

      if !eclim#util#ListContains(names, project)
        let prompt = "Project '" . project . "' not found (ctrl-c to cancel): "
        let project = ''
      endif
    endwhile
    let workspace = eclim#project#util#GetProjectWorkspace(project)

  elseif scope == 'workspace'
    let project = ''
    let workspace = eclim#eclipse#ChooseWorkspace()
  endif

  call s:CloseScopeChooser()

  let b:scope = scope
  let b:project = project
  let b:workspace = workspace

  let locate_in = (b:scope == 'project' ? b:project : 'workspace')
  exec 'file ' . escape('[Locate in ' . locate_in . ']', ' []')

  call eclim#common#locate#LocateFileCompletion()
endfunction " }}}

" s:CloseScopeChooser() {{{
function s:CloseScopeChooser()
  let winnum = b:locate_winnr
  bdelete
  exec winnum . 'winc w'
  startinsert!
endfunction " }}}

" s:LocateFileHelp() {{{
function s:LocateFileHelp()
  let winnr = winnr()
  exec bufwinnr(b:results_bufnum) . 'winc w'
  let help_bufnum = eclim#help#BufferHelp(s:help, 'vertical', 50)
  exec winnr . 'winc w'
  let b:help_bufnum = help_bufnum

  return ''
endfunction " }}}

" s:LocateFileConvertPattern(pattern) {{{
function s:LocateFileConvertPattern(pattern)
  let pattern = a:pattern

  " if the user supplied a path, prepend a '.*/' to it so that they don't need
  " to type full paths to match.
  if pattern =~ '.\+/'
    let pattern = '.*/' . pattern
  endif
  let pattern = substitute(pattern, '\*\*', '.*', 'g')
  let pattern = substitute(pattern, '\(^\|\([^.]\)\)\*', '\1[^/]*?', 'g')
  let pattern = substitute(pattern, '\.\([^*]\)', '\\.\1', 'g')
  "let pattern = substitute(pattern, '\([^*]\)?', '\1.', 'g')
  let pattern .= '.*'
  return pattern
endfunction " }}}

" vim:ft=vim:fdm=marker
