if exists('g:unpacked')
  finish
endif

let s:error = ''

" TODO: any non-default option here (maybe except 'config') warrants manual
" loading (must be installed to opt)
let s:default_package_options = {
      \   'ft': [],
      \   'cmd': [],
      \   'event': [],
      \   'post-install': '',
      \   'setup': '',
      \   'config': '',
      \ }

" initialize the plugin
function! unpack#begin(...)
  let g:unpacked = v:false
  let s:configuration = {}
  if a:0 >= 1
    let s:configuration.packpath = a:1
  else
    let s:configuration.packpath = stdpath('config')
  endif
  let s:configuration.packages = {}
endfunction

function! unpack#end()
  let g:unpacked = v:true
endfunction

function! unpack#load(path, opts)
  if !exists('g:unpacked')
    echohl ErrorMsg
    echom 'Plug-in not initialized. Check your configuration. (Hint: did you call unpack#begin?)'
    echohl None
    finish
  endif

  let g:unpacked = v:true
  let l:name = s:extract_name(a:path)
  let l:full_path = s:get_full_path(a:path)
  if l:name[0] ==# 'ok' && l:full_path[0] ==# 'ok'
    let s:configuration.packages[l:name[1]] = extend(deepcopy(s:default_package_options), a:opts)
    let s:configuration.packages[l:name[1]].location = l:full_path[1][0]
    let s:configuration.packages[l:name[1]].path = l:full_path[1][1]
    return ['ok']
  else
    return l:name
  endif
endfunction

" TODO: split filetype autocmds into ftplugins within the loader plugin. That
" way lazyload on filetype will have literally zero overhead
function! unpack#compile()
  let l:state = {}
  let l:state.packages = []
  let l:state.ft = {}
  let l:state.cmd = {}
  let l:state.event = {}
  let l:state['post-install'] = {}
  let l:state.setup = {}
  let l:state.config = {}
  let l:state.location = {}
  let l:state.path = {}
  for [l:name, l:opts] in items(s:configuration.packages)
    let l:state = s:compile_item(name, opts, l:state)
  endfor
  let l:output = s:codegen(l:state)
  let l:dir = stdpath('config') . '/plugin/unpack'
  let l:loader = '/loader.vim'
  if !isdirectory(l:dir)
    call mkdir(l:dir, 'p')
  endif
  call writefile(l:output, l:dir . l:loader)
endfunction

function! s:compile_item(name, opts, state)
  for [l:key, l:val] in items(a:opts)
    let a:state[l:key][a:name] = l:val
  endfor
  return a:state
endfunction

function! s:augroup_gen(name, defs)
  let l:output = ['augroup ' . a:name]
  for [l:type, l:filters, l:cmd] in a:defs
    for l:filter in l:filters
      call add(l:output, '  autocmd ' . l:type . ' ' . l:filter . ' ' . l:cmd)
    endfor
  endfor
  return add(l:output, 'augroup END')
endfunction

function! s:pre_post_gen(exe)
  if a:exe ==# ''
    return []
  elseif type(a:exe) ==# 1  " string
    return ['    execute "' . a:exe . '"']
  elseif type(a:exe) ==# 2  " lambda
    return ['    call ' . a:exe . '()']
  else
    let error = '"setup" must be either a lambda or a string'
    return []
  endif
endfunction

function! s:loader_gen(name, state)
  let l:output = []
  let l:name = substitute(tolower(a:name), '\.', '_', 'g')
  let l:flag = 'g:unpack_loader_' . l:name . '_init_status'
  call add(l:output, 'let ' . l:flag . ' = 0')
  call add(l:output, 'function! unpack#loader#' . l:name . '()')
  call add(l:output, '  if !' . l:flag)
  call add(l:output, '    let ' . l:flag . ' = 1')

  call extend(l:output, s:pre_post_gen(get(a:state.setup, a:name, '')))
  call add(l:output, '    execute "packadd ' . a:name . '"')
  call extend(l:output, s:pre_post_gen(get(a:state.config, a:name, '')))

  call add(l:output, '  endif')
  call add(l:output, 'endfunction')
  return l:output
endfunction

function! s:item_gen(name, state)
  let l:output = []
  let l:defs = []
  let l:name = substitute(tolower(a:name), '\.', '_', 'g')
  let l:cmd = 'call unpack#loader#' . l:name . '()'

  for [l:type, l:key] in [['FileType', 'ft'], ['CmdUndefined', 'cmd']]
    if has_key(a:state[l:key], a:name)
      call add(l:defs, [l:type, a:state[l:key][a:name], l:cmd])
    endif
  endfor

  if has_key(a:state.event, a:name)
    for l:event in a:state.event[a:name]
      call add(l:defs, [l:event, ['*'], l:cmd])
    endfor
  endif

  return extend(s:loader_gen(a:name, a:state), s:augroup_gen(toupper(l:name), l:defs))
endfunction

function! s:codegen(state)
  let l:output = []
  call add(l:output, '" autogenerated by unpack#compile()')
  call add(l:output, 'set packpath+=' . s:configuration.packpath)
  for l:name in keys(s:configuration.packages)
    call extend(l:output, s:item_gen(l:name, a:state))
  endfor
  return l:output
endfunction

function! s:check_git_version()
endfunction

function! s:checkout(spec)
  " 'git '.credential_helper.'fetch --depth 999999 && git checkout '.plug#shellescape(sha).' --', a:spec.dir
endfunction

function! s:clone(spec)
endfunction

function! s:pull(spec)
endfunction

function! unpack#install()
endfunction

function! unpack#clean()
endfunction

function! unpack#update()
endfunction

function! s:extract_name(path)
  if stridx(a:path, '/') > 0
    " TODO: add in git addresses as well
    if stridx(a:path, 'http:') ==# 1 || stridx(a:path, 'https:') ==# 1
      let repo = split(a:path, '/')[-1]
      if repo[-4:] ==# '.git'
        return ['ok', repo[:-4]]
      else
        return ['error', [a:path, 'not a valid git repo']]
      endif
    else  " not a url
      return ['ok', split(a:path, '/')[-1]]
    endif
  else
    return ['error', [a:path, 'not a valid entry']]
  endif
endfunction

function! s:get_full_path(path)
  if count(a:path, '/') ==# 1  " path for Github
    return ['ok', ['remote', 'https://github.com/' . a:path . '.git']]
  elseif count(a:path, '/') > 1
    if stridx(a:path, 'http:') ==# 1 || stridx(a:path, 'https:') ==# 1
      if a:path[-4] ==# '.git'
        return ['ok', ['remote', a:path]]
      else
        return ['error', [a:path, 'not a valid git repo']]
      endif
    else
      return ['ok', ['local', a:path]]
    endif
  else
    return ['error', [a:path, 'not a valid entry']]
  endif
endfunction
