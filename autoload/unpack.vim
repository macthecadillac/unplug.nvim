" FIXME: check every dictionary indexing and insert error handler for the
" configuration processing step since users might put in undefined keys
if exists('g:unpacked')
  finish
endif

let g:unpack#packpath = unpack#platform#config_path()
let g:unpacked = v:false
let s:default_loader_path = unpack#platform#join(unpack#platform#config_path(), 'unpack')
let g:unpack#loader_path = get(g:, 'unpack#loader_path', s:default_loader_path)

let s:error = ''
let s:configuration = {}
let s:configuration.packages = {}
let g:unpack#packpath_modified = v:false

let s:default_package_options = {
      \   'opt': v:false,
      \   'ft': [],
      \   'cmd': [],
      \   'event': [],
      \   'branch': '',
      \   'commit': '',
      \   'post-install': '',
      \   'local': v:false,
      \   'pre': '',
      \   'post': '',
      \   'requires': [],
      \ }

" initialize the plugin
function! unpack#begin(...)
  if a:0 >= 1
    let g:unpack#packpath = a:1
    let g:unpack#packpath_modified = v:true
  endif
endfunction

function! unpack#end()
  let g:unpacked = v:true
endfunction

function! unpack#load(path, ...)
  if !exists('g:unpacked')
    echohl ErrorMsg
    echom 'Plug-in not initialized. Check your configuration. (Hint: did you call unpack#end?)'
    echohl None
    finish
  endif

  if a:0
    let l:opts = a:1
  else
    let l:opts = s:default_package_options
  endif
  let g:unpacked = v:true
  let l:name = s:extract_name(trim(a:path))
  let l:full_path = s:get_full_path(a:path)
  if l:name.ok && l:full_path.ok
    let l:spec = extend(deepcopy(s:default_package_options), l:opts)
    let l:spec.local = l:full_path.local
    let l:spec.path = l:full_path.path
    let s:configuration.packages[l:name.name] = l:spec
  else
    echohl ErrorMsg
    if !l:name.ok
      echom l:name.msg
    else
      echom l:full_path.msg
    endif
    echohl NONE
  endif
endfunction

function! s:dependency_graphs()
  if !exists('s:package_dependency_graphs')
    let s:package_dependency_graphs = unpack#solv#nodes(s:configuration)
  endif
  return s:package_dependency_graphs
endfunction

function! unpack#compile()
  let l:output = unpack#code#gen(s:configuration)
  let l:config_path = unpack#platform#config_path()
  if isdirectory(g:unpack#loader_path)  " remove previously generated loaders
    call delete(g:unpack#loader_path, 'rf')
  endif
  call mkdir(g:unpack#loader_path, 'p')

  if !empty(l:output.ftplugin)
    let l:ftplugin = unpack#platform#join(g:unpack#loader_path, 'ftplugin')
    call mkdir(l:ftplugin)
    for [l:ft, l:ft_loader] in items(l:output.ftplugin)
      call writefile(l:ft_loader, unpack#platform#join(l:ftplugin, l:ft . '.vim'))
    endfor
  endif

  if !empty(l:output.plugin.unpack)
    let l:plugin = unpack#platform#join(g:unpack#loader_path, 'plugin')
    call mkdir(l:plugin)
    call writefile(l:output.plugin.unpack, unpack#platform#join(l:plugin, 'unpack.vim'))
  endif

  if !empty(l:output.autoload.unpack.loader)
    let l:autoload = unpack#platform#join(g:unpack#loader_path, 'autoload', 'unpack')
    call mkdir(l:autoload, 'p')
    call writefile(l:output.autoload.unpack.loader, unpack#platform#join(l:autoload, 'loader.vim'))
  endif
endfunction

function! unpack#write()
  let l:opt_packages = unpack#platform#ls(unpack#platform#opt_path())
  let l:start_packages = unpack#platform#ls(unpack#platform#start_path())
  for [l:package, l:spec] in items(s:configuration.packages)
    if s:is_member(l:package, l:opt_packages) && unpack#solv#is_optional(l:package, s:configuration)
      call s:make_mandatory(l:package)
    elseif s:is_member(l:package, l:start_packages) && unpack#solv#is_optional(l:package, s:configuration)
      call s:make_optional(l:package)
    endif
  endfor
  call unpack#compile()
endfunction

function! s:is_member(item, list)
  for l:item in a:list
    if l:item ==# a:item
      return v:true
    endif
  endfor
  return v:false
endfunction

function! s:make_optional(name)
  let l:opt_dir = unpack#platform#join(unpack#platform#opt_path(), a:name)
  let l:start_dir = unpack#platform#join(unpack#platform#start_path(), a:name)
  call unpack#platform#move(l:start_dir, l:opt_dir)
endfunction

function! s:make_mandatory(name)
  let l:opt_dir = unpack#platform#join(unpack#platform#opt_path(), a:name)
  let l:start_dir = unpack#platform#join(unpack#platform#start_path(), a:name)
  call unpack#platform#move(l:opt_dir, l:start_dir)
endfunction

" TODO: add timeout
function! s:clone(name)
  let l:spec = s:configuration.packages[a:name]
  let l:opt_dir = unpack#platform#join(unpack#platform#opt_path(), a:name) 
  let l:start_dir = unpack#platform#join(unpack#platform#start_path(), a:name) 
  if !(isdirectory(l:opt_dir) || isdirectory(l:start_dir))
    let l:dir = unpack#solv#is_optional(a:name, s:configuration) ? unpack#platform#opt_path() : unpack#platform#start_path()
    if !(isdirectory(l:dir))
      call mkdir(l:dir, 'p')
    endif
    let l:Update = function('unpack#ui#update')
    if empty(l:spec.branch) && empty(l:spec.commit)
      let l:cmd = ['git', '-C', l:dir, 'clone', l:spec.path]
      call unpack#job#start(a:name, l:cmd, {->0}, l:Update, l:spec['post-install'])
    elseif !empty(l:spec.commit) && !empty(l:spec.branch)
      let l:cmd1 = ['git', '-C', l:dir, 'clone', '-b', l:spec.branch, l:spec.path]
      let l:cmd2 = ['git', '-C', unpack#platform#join(l:dir, a:name), 'checkout', l:spec.commit]
      call unpack#job#start(a:name, l:cmd1, {->0}, l:Update, {->
         \ unpack#job#start(a:name, l:cmd2, {->0}, l:Update, l:spec['post-install'])})
    elseif !empty(l:spec.commit)
      let l:cmd1 = ['git', '-C', l:dir, 'clone', l:spec.path]
      let l:cmd2 = ['git', '-C', unpack#platform#join(l:dir, a:name), 'checkout', l:spec.commit]
      call unpack#job#start(a:name, l:cmd1, {->0}, l:Update, {->
         \ unpack#job#start(a:name, l:cmd2, {->0}, l:Update, l:spec['post-install'])})
    else
      let l:cmd = ['git', '-C', l:dir, 'clone', '-b', l:spec.branch, l:spec.path]
      call unpack#job#start(a:name, l:cmd, {->0}, l:Update, l:spec['post-install'])
    endif
  endif
endfunction

" TODO: add timeout
function! s:fetch(name)
  let l:spec = s:configuration.packages[a:name]
  let l:dir = unpack#solv#is_optional(a:name, s:configuration) ?
        \ unpack#platform#opt_path() : unpack#platform#start_path()
  let l:Update = function('unpack#ui#update')
  let l:cmd = ['git', '-C', unpack#platform#join(l:dir, a:name), 'fetch']
  " TODO: only run post-install if something changed
  call unpack#job#start(a:name, l:cmd, {->0}, l:Update, l:spec['post-install'])
endfunction

function! unpack#list(text, ...)
  return filter(sort(keys(s:configuration.packages)), {_, s -> stridx(s, a:text) ==# 0})
endfunction

function! s:for_each_package_do(f, names)
  if len(a:names) >= 1  " user specified packages to perform action
    let l:error = 0
    for l:name in a:names
      if !has_key(s:configuration.packages, l:name)
        echohl ErrorMsg
        echom l:name . ' is not a known package.'
        echohl NONE
        let l:error = 1
        break
      endif
    endfor

    if !l:error
      for l:name in a:names
        call a:f(l:name)
      endfor
    endif
  else
    for l:name in keys(s:configuration.packages)
      call a:f(l:name)
    endfor
  endif
endfunction

function! s:install(name)
  let l:spec = s:configuration.packages[a:name]
  if l:spec.local
    if unpack#solv#is_optional(a:name, s:configuration)
      let l:install_path = unpack#platform#opt_path()
    else
      let l:install_path = unpack#platform#start_path()
    endif
    call unpack#platform#ln(l:spec.path, unpack#platform#join(l:install_path, a:name))
  else
    call s:clone(a:name)
  endif
endfunction

function! unpack#install(...)
  call unpack#ui#new_window()
  call s:for_each_package_do(function('s:install'), a:000)
endfunction

function! unpack#clean()
  let l:opt_dir = unpack#platform#opt_path()
  let l:start_dir = unpack#platform#start_path()
  call s:remove_package_if_not_in_list(l:opt_dir)
  call s:remove_package_if_not_in_list(l:start_dir)
endfunction

function! s:remove_package_if_not_in_list(base_path)
  for l:package in unpack#platform#ls(a:base_path)
    let l:name = unpack#platform#split(l:package)[-1]
    if !s:is_member(l:name, keys(s:configuration.packages))
      let l:path = unpack#platform#join(a:base_path, l:package)
      call delete(l:path, 'rf')
    endif
  endfor
endfunction

function! unpack#update(...)
  call unpack#ui#new_window()
  call s:for_each_package_do(function('s:fetch'), a:000)
endfunction

function! s:extract_name(path)
  if stridx(a:path, '/') > 0
    if stridx(a:path, 'http:') ==# 0 || stridx(a:path, 'https:') ==# 0 || stridx(a:path, 'git@') ==# 0
      let repo = split(a:path, '/')[-1]
      if repo[-4:] ==# '.git'
        return {'ok': 1, 'name': repo[:-4]}
      else
        return {'ok': 0, 'path': a:path, 'msg': 'not a valid git repo'}
      endif
    else  " not a url
      return {'ok': 1, 'name': split(a:path, '/')[-1]}
    endif
  else
    return {'ok': 0, 'path': a:path, 'msg': 'not a valid entry'}
  endif
endfunction

function! s:get_full_path(path)
  if count(a:path, '/') ==# 1  " path for Github
    return {'ok': 1, 'local': 0, 'path': 'https://github.com/' . a:path . '.git'}
  elseif count(a:path, '/') > 1
    if stridx(a:path, 'http:') ==# 1 || stridx(a:path, 'https:') ==# 1
      if a:path[-4] ==# '.git'
        return {'ok': 1, 'local': 0, 'path': a:path}
      else
        return {'ok': 0, 'path': a:path, 'msg': 'not a valid git repo'}
      endif
    else
      return {'ok': 1, 'local': 1, 'path': a:path}
    endif
  else
    return {'ok': 0, 'path': a:path, 'msg': 'not a valid entry'}
  endif
endfunction
