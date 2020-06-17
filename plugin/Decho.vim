"" Decho.vim:   Debugging support for VimL
" Date:        Nov 29, 2019
" Version:     24
" Maintainer:  Charles E. Campbell <NcampObell@SdrPchip.AorgM-NOSPAM>
"
" Usage: {{{1
"   Decho "a string"
"   call Decho("another string")
"   let g:decho_bufname = "ANewDBGBufName"
"   let g:decho_bufenter= 1    " tells Decho to ignore BufEnter, WinEnter,
"                              " WinLeave events while Decho is working
"   call Decho("one","thing","after","another")
"   DechoOn     : removes any first-column '"' from lines containing Decho
"   DechoOff    : inserts a '"' into the first-column in lines containing Decho
"   DechoMsgOn  : use echomsg instead of DBG buffer
"   DechoMsgOff : turn debugging off
"   DechoRemOn  : turn remote Decho messaging on
"   DechoRemOff : turn remote Decho messaging off
"   DechoVarOn [varname] : use variable to write debugging messages to
"   DechoVarOff : turn debugging off
"   DechoTabOn  : turn debugging on (uses a separate tab)
"   DechoTabOff : turn debugging off
"
"   :DechoSep [msg] : include a separator, count, and optional message
"
" GetLatestVimScripts: 120 1 :AutoInstall: Decho.vim
" GetLatestVimScripts: 1066 1 :AutoInstall: cecutil.vim
" redraw!|call inputsave()|call input("Press <cr> to continue")|call inputrestore()

" ---------------------------------------------------------------------
" Load Once: {{{1
if exists("g:loaded_Decho") || &cp
 finish
endif
let g:loaded_Decho = "v24"
let s:keepcpo      = &cpo
let s:decho_enabled= 1
set cpo&vim

" ---------------------------------------------------------------------
"  Default Values For Variables: {{{1
if !exists("g:decho_bufname")
 let g:decho_bufname= "DBG"
endif
if !exists("s:decho_depth")
 let s:decho_depth  = 0
endif
if !exists("g:decho_winheight")
 let g:decho_winheight= 5
endif
if !exists("g:decho_bufenter")
 let g:decho_bufenter= 0
endif
if !exists("g:dechomode") || !exists("s:DECHOWIN")
 let s:DECHOWIN = 1
 let s:DECHOMSG = 2
 let s:DECHOVAR = 3
 let s:DECHOREM = 4
 let s:DECHOTAB = 5
 let g:dechomode= s:DECHOWIN
endif
if !exists("g:dechovarname")
 let g:dechovarname = "g:dechovar"
endif
if !exists("g:dechofuncname")
 let g:dechofuncname= 0
endif
if !exists("g:decholinenum")
 let g:decholinenum= 0
endif

" ---------------------------------------------------------------------
"  User Interface: {{{1
if g:decholinenum
 com! -nargs=+ -complete=expression		Decho			call Decho(<args>,'~'.expand("<slnum>"))
else
 com! -nargs=+ -complete=expression		Decho			call Decho(<args>)
endif
com! -nargs=+ -complete=expression		Dredir			call Dredir(<args>)
com! -nargs=0							Dhide    		call s:Dhide(1)
com! -nargs=0							Dshow    		call s:Dhide(0)
com! -nargs=0							DechoToggle		call s:DechoToggle()
com! -nargs=?							DechoSep		call DechoSep(<q-args>)
com! -nargs=?							Dsep			call DechoSep(<q-args>)
com! -nargs=0							DechoMsgOn		call s:DechoCtrlInit(s:DECHOMSG,expand("<sfile>"))
com! -nargs=0							DechoMsgOff		call s:DechoMsg(0)
com! -nargs=0 -range=%					DechoOn			call DechoOn(<line1>,<line2>)
com! -nargs=0 -range=%					DechoOff		call DechoOff(<line1>,<line2>)
if has("clientserver") && executable("gvim")
 com! -nargs=0							DechoRemOn		call s:DechoCtrlInit(s:DECHOREM,expand("<sfile>"))
 com! -nargs=0							DechoRemOff		call s:DechoRemote(0)
else
 com! -nargs=?							DechoRemOn		call s:DechoCtrlInit(s:DECHOTAB,expand("<sfile>"))
 com! -nargs=?							DechoRemOff		set lz|	call s:DechoTab(0)|set nolz
endif
com! -nargs=?							DechoVarOn		call s:DechoCtrlInit(s:DECHOVAR,expand("<sfile>"),<args>)
com! -nargs=0							DechoVarOff		call s:DechoVarOff()
com! -nargs=?							DechoTabOn		call s:DechoCtrlInit(s:DECHOTAB,expand("<sfile>"))
com! -nargs=?							DechoTabOff		set lz|	call s:DechoTab(0)|set nolz
com! -nargs=0							DechoPause		call s:DechoPause()
com! -nargs=?							DechoFuncName	call s:DechoFuncName(<args>)
au Filetype Decho nmap <silent> <buffer> <F1>	:setlocal noro ma<cr>

" =====================================================================
" Functions: {{{1

" ---------------------------------------------------------------------
" Decho: the primary debugging function: splits the screen as necessary and {{{2
"        writes messages to a small window (g:decho_winheight lines)
"        on the bottom of the screen
fun! Decho(...)
  let eikeep= &ei
  set ei=all
"  call Rfunc("Decho(a:1=".((a:0 > 0)? a:1 : 'n/a').") a:0=".a:0)

  " if not enabled, leave immediately
  if !s:decho_enabled
"   call Rret("Decho : not enabled, leave immediately")
   let &ei= eikeep
   return
  endif

  " set up ctrl mode as user specified earlier
  call s:DechoCtrl()

  " open DBG window (if dechomode is dechowin)
  if g:dechomode == s:DECHOWIN
   let swp   = winsaveview()
   let curbuf= bufnr("%")
   if g:decho_bufenter
    let eikeep= &ei
	let eakeep= &ea
	set ei=BufEnter,WinEnter,WinLeave,ShellCmdPost,FocusGained noea
   endif

   " As needed, create/switch-to the DBG buffer
   if !bufexists(g:decho_bufname) && bufnr("*/".g:decho_bufname."$") == -1
    " if requested DBG-buffer doesn't exist, create a new one
    " at the bottom of the screen.
	exe "keepj sil! bot ".g:decho_winheight."new ".fnameescape(g:decho_bufname)
    setlocal noswf
	keepj sil! %d _

   elseif bufwinnr(g:decho_bufname) > 0
    " if requested DBG-buffer exists in a window,
    " go to that window (by window number)
    exe "keepj ".bufwinnr(g:decho_bufname)."wincmd W"
    exe "res ".g:decho_winheight

   else
    " user must have closed the DBG-buffer window.
    " create a new one at the bottom of the screen.
    exe "keepj sil bot ".g:decho_winheight."new"
    setlocal noswf
    exe "keepj b ".bufnr(g:decho_bufname)
   endif

   set ft=Decho
   setlocal noswapfile noro nobl fo=n2croql

   "  make sure DBG window is on the bottom
   wincmd J
  endif

  " Build Message
  let i  = 1
  " append (function-name) to message
  if g:dechofuncname && exists("s:Dfunclist_".s:decho_depth)
   let msg= "(".s:Dfunclist_{s:decho_depth}.") "
  else
   let msg= ""
  endif
  while i <= a:0
   try
	if type(a:{i}) == 1
	 " append string
	 let msg= msg.a:{i}
	else
	 " append a stringified version
	 let msg= msg.string(a:{i})
	endif
   catch /^Vim\%((\a\+)\)\=:E730/
    " looks like a:i is a list
	let msg= msg.string(a:{i})
   endtry
   if i < a:0
    let msg=msg." "
   endif
   let i=i+1
  endwhile

  " Initialize message with leading idepth-|s 
  let smsg   = ""
  let idepth = 0
  while idepth < s:decho_depth
   let smsg   = "|".smsg
   let idepth = idepth + 1
  endwhile

  " Handle special characters (\t \r \n)
  " and append msg to smsg  (strtrans use suggested by Andy Wokula)
  let smsg= smsg.strtrans(msg)

   " append optional line number information: ~###
"   if g:decholinenum
"    let smsg= smsg." ~".line(".")
"   endif

"  echomsg "g:dechomode=".g:dechomode
  if g:dechomode == s:DECHOMSG
   " display message with echomsg
   exe "unsilent echomsg '".substitute(smsg,"'","'.\"'\".'","ge")."'"

  elseif g:dechomode == s:DECHOVAR
   " "display" message by appending to variable named by g:dechovarname
   let smsg= substitute(smsg,"'","''","ge")
   if exists(g:dechovarname)
    exe "let ".g:dechovarname."= ".g:dechovarname.".'\n".smsg."'"
   else
    exe "let ".g:dechovarname."= '".smsg."'"
   endif

  elseif g:dechomode == s:DECHOREM
   " display message by appending it to remote DECHOREMOTE vim server
   let smsg= substitute(smsg,"\<esc>","\<c-v>\<esc>","ge")
   try
	if smsg =~ '<\w\{2,4}>'
	 let smsg= substitute(smsg,"'","''","g")
	 call remote_send("DECHOREMOTE",":call setline(line('$')+1,'".smsg."')\<cr>".':set nomod ma'."\<cr>")
	else
     call remote_send("DECHOREMOTE",'Go'.smsg."\<esc>".':set nomod ma'."\<cr>")
	endif
   catch /^Vim\%((\a\+)\)\=:E241/
    let g:dechomode= s:DECHOWIN
   endtry

  elseif g:dechomode == s:DECHOTAB
   " display message by appending it to the debugging tab window
   let lzkeep= &lz
   set ei=all lz
   let g:dechotabcur = tabpagenr()
   exe "sil! tabn ".g:dechotabnr
   if !exists("t:dechotabpage")
	" looks like a new tab has been inserted -- look for a tab having t:dechotabpage
	let g:dechotabnr= 1
	silent! tabn 1
	while !exists("t:dechotabpage")
	 let g:dechotabnr= g:dechotabnr + 1
	 if g:dechotabnr > tabpagenr("$")
	  " re-generate the "Decho Tab" tab -- looks like it was closed!
	  call s:DechoTab(1)
      exe "tabn ".g:dechotabnr
	  break
	 endif
     exe "tabn ".g:dechotabnr
    endwhile
   endif

   " check that the debugging tab still has a debugging window left in it; use it
   " if present
   let dbgwin= bufwinnr(bufname("Decho Tab"))
   if dbgwin == -1
	" looks like only non-debugging windows are left in what had been the debugging tab.
	" Regenerate it.
	if exists("t:dechotabpage")
	 unlet t:dechotabpage
	endif
	call s:DechoTab(1)
    exe "tabn ".g:dechotabnr
   else
	exe dbgwin."wincmd w"
   endif

   " append message to "Decho Tab" window in the debugging tab
   " echomsg "appending message to tab#".tabpagenr()
   setlocal ma noro
   call setline(line("$")+1,smsg)
   setlocal noma nomod
   " restore tab# to original user tab
   exe "tabn ".g:dechotabcur
   " echomsg "returning to tab#".tabpagenr()
   let &ei= eikeep
   let &lz= lzkeep

  else
   " Write Message to DBG buffer
   setlocal ma
   keepjumps $
   keepjumps let res= append("$",smsg)
   setlocal nomod

   " Put cursor at bottom of DBG window, then return to original window
   exe "res ".g:decho_winheight
   keepjumps norm! G
   if exists("g:decho_hide") && g:decho_hide > 0
    setlocal hidden
    q
   endif
   keepjumps wincmd p
   if exists("swp")
	call winrestview(swp)
   endif

   if g:decho_bufenter
    let &ei= eikeep
	let &ea= eakeep
   endif
  endif
"  call Rret("Decho")
  let &ei= eikeep
  if !exists("g:did_drchip_decho_syntax")
   syn on
  endif
endfun

" ---------------------------------------------------------------------
"  Dfunc: just like Decho, except that it also bumps up the depth {{{2
"         It also appends a "{" to facilitate use of %
"         Usage:  call _Dfunc("functionname([opt arglist])")
fun! Dfunc(...)
"  call Rfunc("Dfunc(...) a:0=".a:0)

  " if not enabled, leave immediately
  if !s:decho_enabled
"   call Rret("Dfunc(...) disabled")
   return
  endif
  let keep_dechofuncname = g:dechofuncname
  let g:dechofuncname    = 0

  " Build Message
  let i  = 1
  let msg= ""
  while i <= a:0
   exe "let msg=msg.a:".i
   if i < a:0
    let msg=msg." "
   endif
   let i=i+1
  endwhile
  let msg= msg." {"
  call Decho(msg)
  let s:decho_depth               = s:decho_depth + 1
  let s:Dfunclist_{s:decho_depth} = substitute(msg,'[( \t].*$','','')
  let g:dechofuncname             = keep_dechofuncname

"  call Rret("Dfunc")
endfun

" ---------------------------------------------------------------------
"  Dret: just like Decho, except that it also bumps down the depth {{{2
"        It also appends a "}" to facilitate use of %
"         Usage:  call _Dret("functionname [optional return] [: optional extra info]")
fun! Dret(...)
"  call Rfunc("Dret(...) a:0=".a:0)

  " if not enabled, leave immediately
  if !s:decho_enabled
"   call Rret("Dret : disabled")
   return
  endif
  let keep_dechofuncname = g:dechofuncname
  let g:dechofuncname    = 0

  " Build Message
  let i  = 1
  let msg= ""
  while i <= a:0
   exe "let msg=msg.a:".i
   if i < a:0
    let msg=msg." "
   endif
   let i=i+1
  endwhile
  let msg= msg." }"
  call Decho("return ".msg)
  if s:decho_depth > 0
   let retfunc= substitute(msg,'\s.*$','','e')
   if  retfunc != s:Dfunclist_{s:decho_depth}
   	echoerr "Dret: appears to be called by<".s:Dfunclist_{s:decho_depth}."> but returning from<".retfunc.">"
   endif
   unlet s:Dfunclist_{s:decho_depth}
   let s:decho_depth= s:decho_depth - 1
  endif
  let g:dechofuncname= keep_dechofuncname

"  call Rret("Dret")
endfun

" ---------------------------------------------------------------------
" DechoOn: de-comments Dfunc/Dret/Decho statements in the plugin being debugged {{{2
fun! DechoOn(line1,line2)
"  call Rfunc("DechoOn(line1=".a:line1.",line2=".a:line2.")")
  let ickeep = &ic
  set noic
  let swp    = winsaveview()
  let dbgpat = '\<D\%(echo\|echoWF\|echoBuf\|func\|echoFuncName\|redir\|ret\|echo\%(Msg\|Rem\|Tab\|Var\)O\%(n\|ff\)\|echoToggle\)\>\|\<g:dechofuncname\>'
  if search(dbgpat,'cnw') == 0
   echoerr "this file<".expand("%")."> does not contain any Decho/Dfunc/Dret commands or function calls!"
  else
   exe "sil! keepj ".a:line1.",".a:line2.'g/'.dbgpat.'/s/^"\([^"]\)/\1/e'
  endif
  call winrestview(swp)
  let &ic= ickeep
"  call Rret("DechoOn")
endfun

" ---------------------------------------------------------------------
" DechoOff: comments Dfunc/Dret/Decho statements in the plugin being debugged {{{2
fun! DechoOff(line1,line2)
  let ickeep= &ic
  set noic
  let swp= winsaveview()
  exe "sil! keepj ".a:line1.",".a:line2.'g/\<D\%(echo\|echoWF\|echoBuf\|func\|echoFuncName\|redir\|ret\|echo\%(Msg\|Rem\|Tab\|Var\)O\%(n\|ff\)\|echoToggle\)\>\|\<g:dechofuncname\>/s/^[^"]/"&/'
  call winrestview(swp)
  let &ic= ickeep
endfun

" ---------------------------------------------------------------------
" DechoDepth: allow user to force depth value {{{2
fun! DechoDepth(depth)
"  call Rfunc("DechoDepth(depth=".a:depth.")")
  let s:decho_depth= a:depth
"  call Rret("DechoDepth")
endfun

" ---------------------------------------------------------------------
" DechoCtrl: sets up the deferred CMD's mode {{{2
"            Also see DechoCtrlInit()
fun! s:DechoCtrl()
"  call Rfunc("s:DechoCtrl() mode<".(exists("s:DechoCtrlmode")? s:DechoCtrlmode : 'n/a')."> fname<".(exists("s:DechoCtrlfname")? s:DechoCtrlfname : 'n/a')."> args<".(exists("s:DechoCtrlargs")? s:DechoCtrlargs : 'n/a'))

  if !exists("s:DechoCtrlmode")
"   call Rret("s:DechoCtrl")
   return

  elseif s:DechoCtrlmode == s:DECHOWIN
"   call Recho("g:dechomode= s:DECHOWIN")
   let g:dechomode= s:DECHOWIN

  elseif s:DechoCtrlmode == s:DECHOMSG
"   call Recho("g:dechomode= s:DECHOMSG")
   call s:DechoMsg(1,s:DechoCtrlfname)

  elseif s:DechoCtrlmode == s:DECHOVAR
"   call Recho("g:dechomode= s:DECHOVAR")
   if exists("s:DechoCtrlargs")
	call s:DechoVarOn(s:DechoCtrlfname,s:DechoCtrlargs)
   else
	call s:DechoVarOn(s:DechoCtrlfname)
   endif

  elseif s:DechoCtrlmode == s:DECHOREM
"   call Recho("g:dechomode= s:DECHOREM")
   call s:DechoRemote(1,s:DechoCtrlfname)

  elseif s:DechoCtrlmode == s:DECHOTAB
"   call Recho("g:dechomode= s:DECHOTAB")
   set lz
   call s:DechoTab(1,s:DechoCtrlfname)
   set nolz

  else
   echoerr "(s:DechoCtrl) bad mode#".s:DechoCtrlmode
  endif

  if exists("s:DechoCtrlmode") |unlet s:DechoCtrlmode |endif
  if exists("s:DechoCtrlfname")|unlet s:DechoCtrlfname|endif
  if exists("s:DechoCtrlargs") |unlet s:DechoCtrlargs |endif

"  call Rret("s:DechoCtrl")
endfun

" ---------------------------------------------------------------------
" s:DechoCtrlInit: initializes DechoCtrl variables {{{2
"    One of the DechoCMDOn commands calls this function with the associated CMD's mode
"    Instead of being immediate, the command's effect is deferred until the first Decho call.
"   _Decho() calls DechoCtrl(), which in turn sets up the CMD's mode.
fun! s:DechoCtrlInit(mode,...)
"  call Rfunc("DechoCtrlInit(mode=".a:mode.") a:0=".a:0)
  let s:DechoCtrlmode = a:mode
  if a:0 > 0
   let s:DechoCtrlfname= a:1
  endif
  if a:0 > 1
   let s:DechoCtrlargs = a:2
  elseif exists("s:DechoCtrlargs")
   unlet s:DechoCtrlargs
  endif
"  call Rret("DechoCtrlInit : s:DechoCtrlargs=".(exists("s:DechoCtrlargs")? s:DechoCtrlargs : 'n/a'))
endfun

" ---------------------------------------------------------------------
" s:DechoFuncName: toggles/sets inclusion of funcname in each debugging line {{{2
fun! s:DechoFuncName(...)
"  call Dfunc("s:DechoFuncName() a:0=".a:0)
  if a:0 > 0
   let g:dechofuncname= a:1
  else
   let g:dechofuncname= !g:dechofuncname
  endif
"  call Dret("s:DechoFuncName : g:dechofuncname=".g:dechofuncname)
endfun

" ---------------------------------------------------------------------
" s:DechoMsg: supports sending Dfunc/Dret/Decho statements out via echomsg {{{2
fun! s:DechoMsg(onoff,...)
"  call Rfunc("s:DechoMsg(onoff=".a:onoff.") a:0=".a:0)
  if a:onoff
   let g:dechomode = s:DECHOMSG
   let g:dechofile = (a:0 > 0)? a:1 : ""
  else
   let g:dechomode= s:DECHOWIN
  endif
"  call Rret("s:DechoMsg")
endfun

" ---------------------------------------------------------------------
" s:DechoPause: puts a pause-until-<cr> into operation; will place a {{{2
"             separator into the debug output for reporting
fun! s:DechoPause()
"  call Rfunc("s:DechoPause()")
  redraw!
  call DechoSep("(pause)")
  call inputsave()
  call input("Press <cr> to continue")
  call inputrestore()
"  call Rret("s:DechoPause")
endfun

 " ---------------------------------------------------------------------
" s:Dhide: (un)hide DBG buffer {{{2
fun! s:Dhide(hide)
"  call Rfunc("Dhide(hide=".a:hide.")")

  if !bufexists(g:decho_bufname) && bufnr("*/".g:decho_bufname."$") == -1
   " DBG-buffer doesn't exist, simply set g:decho_hide
   let g:decho_hide= a:hide

  elseif bufwinnr(g:decho_bufname) > 0
   " DBG-buffer exists in a window, so its not currently hidden
   if a:hide == 0
   	" already visible!
    let g:decho_hide= a:hide
   else
   	" need to hide window.  Goto window and make hidden
	let curwin = winnr()
	let dbgwin = bufwinnr(g:decho_bufname)
    exe bufwinnr(g:decho_bufname)."wincmd W"
	setlocal hidden
	q
	if dbgwin != curwin
	 " return to previous window
     exe curwin."wincmd W"
	endif
   endif

  else
   " The DBG-buffer window is currently hidden.
   if a:hide == 0
	let curwin= winnr()
    exe "sil bot ".g:decho_winheight."new"
    setlocal bh=wipe
    exe "b ".bufnr(g:decho_bufname)
    exe curwin."wincmd W"
   else
   	let g:decho_hide= a:hide
   endif
  endif
  let g:decho_hide= a:hide
"  call Rret("Dhide")
endfun

" ---------------------------------------------------------------------
" Dredir: this function performs a debugging redir by temporarily using {{{2
"         register a in a redir @a of the given command.  Register a's
"         original contents are restored.
"         Usage: call D-redir([comment,comment,...,] command)
"   Usage:  _Dredir(["string","string",...,]"cmd")  (ignore the leading _)
fun! Dredir(...)
"  call Rfunc("Dredir(...) a:0=".a:0)
  if a:0 <= 0
"   call Rret("Dredir")
   return
  endif
  let cmd  = a:{1}
  let icmd = 2
  while icmd <= a:0
   call Decho(a:{icmd})
   let icmd= icmd + 1
  endwhile

  " save register a, initialize
  let keep_rega = @a
  let v:errmsg  = ''

  " do the redir of the command to the register a
  try
   redir @a
    exe "keepj sil ".cmd
  catch /.*/
   let v:errmsg= substitute(v:exception,'^[^:]\+:','','e')
  finally
   redir END
   if v:errmsg == ''
   	let output= @a
   else
   	let output= v:errmsg
   endif
   let @a= keep_rega
  endtry

  " process output via Decho()
  while output != ""
   if output =~ "\n"
   	let redirline = substitute(output,'\n.*$','','e')
   	let output    = substitute(output,'^.\{-}\n\(.*$\)$','\1','e')
   else
   	let redirline = output
   	let output    = ""
   endif
   call Decho("redir<".cmd.">: ".redirline)
  endwhile
"  call Rret("Dredir")
endfun

" ---------------------------------------------------------------------
" DechoSep: puts a separator with counter into debugging output {{{2
"           usage: :DechoSep     -- puts a count and separator line in
"                  :DechoSep msg -- like :DechoSep but also includes a message string
fun! DechoSep(...)
"  call Rfunc("DechoSep() a:0=".a:0)
  if !exists("s:dechosepcnt")
   let s:dechosepcnt= 1
  else
   let s:dechosepcnt= s:dechosepcnt + 1
  endif
  let eikeep= &ei
  set ei=all
  call Decho("--sep".s:dechosepcnt."--".((a:0 > 0)? " ".a:1 : ""))
  if a:1 =~ "^:"
   exe a:1
  elseif a:1 != ""
   exe "norm ".a:1
  endif
  let &ei= eikeep
"  call Rret("DechoSep")
endfun

" ---------------------------------------------------------------------
 " DechoRemote: supports sending debugging to a remote vim {{{2
if has("clientserver") && executable("gvim")
 fun! s:DechoRemote(mode,...)
"   call Rfunc("s:DechoRemote(mode=".a:mode.",".((a:0 > 0)? a:1 : '...')." a:0=".a:0)
   if a:mode == 0
    " turn remote debugging off
"	call Recho("turn remote debugging off")
    if g:dechomode == s:DECHOREM
     let g:dechomode= s:DECHOWIN
    endif

   elseif a:mode == 1
    " turn remote debugging on
"	call Recho("turn remote debugging on")
    if g:dechomode != s:DECHOREM
 	 let g:dechomode= s:DECHOREM
    endif
	let g:dechofile= (a:0 > 0)? a:1 : ""
    if serverlist() !~ '\<DECHOREMOTE\>'
     " start up remote Decho server
     echomsg "DEBUG: start up DECHOREMOTE server"
"	 call Recho("DEBUG: start up DECHOREMOTE server")
     if has("win32") && executable("start")
      call system("start gvim --servername DECHOREMOTE")
	 else
      call system("gvim --servername DECHOREMOTE")
	 endif
     while 1
      try
 	   call remote_send("DECHOREMOTE",':set ft=Decho fo-=at'."\<cr>")
	   call remote_send("DECHOREMOTE",':file [Decho\ Remote\ Server]'."\<cr>")
 	   call remote_send("DECHOREMOTE",":put ='-----------------------------'\<cr>")
 	   call remote_send("DECHOREMOTE",":put ='Remote Decho Debugging Window'\<cr>")
 	   call remote_send("DECHOREMOTE",":put ='-----------------------------'\<cr>")
	   call remote_send("DECHOREMOTE","1GddG")
	   call remote_send("DECHOREMOTE",':set noswf nomod nobl nonu ch=1 fo=n2croql nosi noai'."\<cr>")
 	   call remote_send("DECHOREMOTE",':set ft=Decho'."\<cr>")
	   call remote_send("DECHOREMOTE",':syn on'."\<cr>")
 	   break
      catch /^Vim\%((\a\+)\)\=:E241/
 	   sleep 200m
      endtry
     endwhile
     if serverlist() !~ '\<DECHOREMOTE\>'
      echo "***warning*** remote server started but unable to use it"
"      call Rret("s:DechoRemote : DECHOREMOTE not on serverlist()!")
      return
     endif
    endif

   else
    echohl Warning | echomsg "DechoRemote(".a:mode.") not supported" | echohl None
   endif

"   call Rret("s:DechoRemote")
 endfun
endif

" ---------------------------------------------------------------------
"  DechoVarOn: turn debugging-to-a-variable on.  The variable is given {{{2
"              when used:   DechoVarOn [varname]
fun! s:DechoVarOn(...)
"  call Rfunc("s:DechoVarOn(...) a:0=".a:0)
  let g:dechomode= s:DECHOVAR

  if a:0 > 0
   let g:dechofile= a:1
   if a:2 =~# '^g:'
    exe "let ".a:2.'= ""'
   else
    exe "let g:".a:2.'= ""'
   endif
  else
   let g:dechovarname= "g:dechovar"
  endif
"  call Rret("s:DechoVarOn")
endfun

" ---------------------------------------------------------------------
" DechoVarOff: returns to normal Dfunc/Dret/Decho handling {{{2
fun! s:DechoVarOff()
"  call Rfunc("s:DechoVarOff()")
  if exists("g:dechovarname")
   if exists(g:dechovarname)
    exe "unlet ".g:dechovarname
   endif
  endif
  let g:dechomode= s:DECHOWIN
"  call Rfunc("s:DechoVarOn")
endfun

 " --------------------------------------------------------------------
 " DechoTab: {{{2
if v:version >= 700
 fun! s:DechoTab(mode,...)
"   call Rfunc("DechoTab(mode=".a:mode.") a:0=".a:0)
   "echomsg "DechoTab(mode=".a:mode.") a:0=".a:0

   if a:mode
    let g:dechomode = s:DECHOTAB
	let g:dechofile = (a:0 > 0)? a:1 : ""
    let dechotabcur = tabpagenr()
" 	call Recho("dechotabcur#".dechotabcur." g:dechotabnr".(exists("g:dechotabnr")? "#".g:dechotabnr : "-doesn't exist"))
    if !exists("g:dechotabnr")
	 let eikeep= &ei
	 set ei=all
	 tabnew
	 sil! file Decho\ Tab
	 let t:dechotabpage= 1
	 let g:dechotabnr  = tabpagenr()
" 	 call Recho("setting g:dechotabnr#".g:dechotabnr." dechofile<".g:dechofile.">")
	 setlocal ma
	 put ='---------'
	 put ='Decho Tab '.g:dechofile
	 put ='---------'
	 norm! 1GddG
	 let &ei          = ""
	 set ft=Decho
	 set ei=all
	 setlocal noma nomod nobl noswf ch=1 fo=n2croql
	 exe "tabn ".dechotabcur
	 let &ei= eikeep
" 	 call Recho("return to tab#".dechotabcur.": file<".expand("%").">")
	endif
   else
    let g:dechomode= s:DECHOWIN
   endif

" call Rret("DechoTab")
 endfun
endif

" ---------------------------------------------------------------------
" DechoBuf: Apply Decho to all lines in the specified buffer {{{2
"   Usage:  D-echoBuf(bufnumber[,desc])                     -- list all lines in specified buffer
"           D-echoBuf(bufnumber,firstline[,desc])           -- list lines from firstline to end of specified buffer
"           D-echoBuf(bufnumber,firstline,lastline[,desc])  -- list lines from firstline to lastline of specified buffer
"           desc: The desc(ription) must be a string.
fun! DechoBuf(bufexpr,...)
  let bevalkeep = &beval
  let eikeep    = &ei
  let lnum      = 1
  let bufend    = "$"
  let desc      = ""
  set nobeval ei=all
  if a:0 >= 1
   if type(a:1) == v:t_number
    let lnum= a:1
   else
	let desc= '  <'.a:1.'>'
   endif
  endif
  if a:0 >= 2
   if type(a:2) == v:t_number
    let bufend= a:2
   else
	let desc= '  <'.a:2.'>'
   endif
  endif
  if a:0 >= 3
   let desc= '  <'.a:3.'>'
  endif
  let buflines= getbufline(a:bufexpr,lnum,bufend)
  call Decho("--- --- Buffer Snapshot #".a:bufexpr." --- --- {".desc)
  for curline in buflines
   call Decho(":",curline)
  endfor
  let &beval= bevalkeep
  let &ei   = eikeep
  call Decho("--- --- Buffer Snapshot #".a:bufexpr." --- --- }".desc)
endfun

" ---------------------------------------------------------------------
" s:DechoToggle: toggles debugging output between enabled and disabled {{{2
fun! s:DechoToggle()
"  call Rfunc("s:DechoToggle()")
  let s:decho_enabled= !s:decho_enabled
  echo (s:decho_enabled)? "Decho enabled" : "Decho disabled"
"  call Rret("s:DechoToggle : Decho ".((s:decho_enabled)? "enabled" : "disabled"))
endfun

" ---------------------------------------------------------------------
"  End Plugin: {{{1
let &cpo= s:keepcpo
unlet s:keepcpo

" ---------------------------------------------------------------------
"  vim: ts=4 fdm=marker ft=vim
