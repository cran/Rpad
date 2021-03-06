# minihttpd.tcl
# This is based on a modified scwsd (Static Content Web Daemon) from 
# http://www.smith-house.org:8000/open.html
# Copyright � 2002 by Larry Smith
# Licensed under the GNU General Public License (http://www.gnu.org/copyleft/gpl.html)
# 
# Changes by Tom Short, copyright 2005, EPRI Solutions, Inc., also licensed under the GNU GPL V2 or later
# 

# The readme for the file is here:

# scwsd is a bare-bones Static Content Web Server Daemon.
# It has no extra features, but serves as a minimal
# implementation from which to build other web applications.
# It is written in Tcl, requires only the vanilla tclsh
# interpreter to run, and is less than 200 lines.  It is
# derived from Steve Uhlers minihttpd.tcl, somewhat
# streamlined and updated, with identifiers changed to
# be more readable.
# 
# To operate it, you use:
# 
# scwsd <root directory> <port> <default file> > log-file
# 
# for example:
# 
# scwsd ~/public_html 8080 index.html > web.log
# 
# scwsd will serve any file in the heirarchy at or under
# root.  It ignores "../" in files and so refuses to serve
# files outside that hierarchy unless they are pointed to
# by links within the hierarchy.


#!/usr/bin/tclsh
# Static Content Web Server Daemon
# config is a global array containing the global server state
#  root:  the root of the document directory
#  port:  The port this server is serving
#  listen:  the main listening socket id
#  accepts:  a count of accepted connections so far

array set config {
  bufsize  32768
  sockblock  0
}

# HTTP/1.0 error codes (the ones we use)
array set errors {
  204 {No Content}
  400 {Bad Request}
  404 {Not Found}
  503 {Service Unavailable}
  504 {Service Temporarily Unavailable}
}

# Start the server by listening for connections on the desired port.
proc server {root { port 0 } { default "" } } {
  global config

  if { $port == 0 } { set port 8079 }
  if { "$default" == "" } { set default index.html }
#  puts "Starting webserver, root at $root, port $port, default page $default"
  array set config [list root $root default $default]
  if {![info exists config(port)]} {
    set config(port) $port
    set config(listen) [socket -server accept_connect $port]
    set config(accepts) 0
  }
  return $config(port)
}

# Accept a new connection from the server and set up a handler
# to read the request from the client.

proc accept_connect {newsock ipaddr port} {
  global config
  upvar #0 config$newsock data

  incr config(accepts)
  fconfigure $newsock -blocking $config(sockblock) \
    -buffersize $config(bufsize) \
    -translation {auto crlf}
# Only local clients allowed!
  if {$ipaddr != "127.0.0.1"} {
       close $newsock
       return
   }

#  putlog $newsock Connect $ipaddr $port
  set data(ipaddr) $ipaddr
  fileevent $newsock readable [list pull $newsock]
}

# read data from a client request
proc pull { sock } {
  upvar #0 config$sock data

    if {[info exists data(state)] && $data(state) == "query" && $data(proto) == "POST"} {
      set line [read $sock]
      set readCount [string length $line]
    } else {
      set readCount [gets $sock line]
    }
  if {![info exists data(state)]} {
    if [regexp {(POST|GET) ([^?]+)\??([^ ]*) HTTP/1.[01]} $line x data(proto) data(url) data(query)] {
      set data(state) mime
    } else {
      push-error $sock 400 "bad first line: $line"
    }
    return
  }
  
  set state [string compare $readCount 0],$data(state),$data(proto)
  switch -- $state {
    0,mime,GET  -
    0,query,POST  { push $sock }
    0,mime,POST   { 
      set data(state) query 
    }
    1,mime,POST  { regexp {^Content-Length: (.*)} $line x data(length) }
    1,mime,GET    {
      if [regexp {([^:]+):[   ]*(.*)}  $line dummy key value] {
        set data(mime,[string tolower $key]) $value
      }
    }
    1,query,POST  {
        append data(query) $line
        if {[string length $data(query)] >= $data(length)} {
            push $sock
        }
    }
	-1,query,POST	{
	  push $sock
	}
    default {
      if [eof $sock] {
#        putlog $sock Error "unexpected eof on <$data(url)> request"
      } else {
#        putlog $sock Error "unhandled state <$state> fetching <$data(url)>"
      }
      push-error $sock 404 ""
    }
  }
}

# Close a socket.
proc disconnect { sock } {
  upvar #0 config$sock data
  unset data
  flush $sock
  close $sock
}

proc finish { mypath in out bytes { error {} } } {
  close $in
  disconnect $out
#  putlog $out Done "$mypath"
}


##########
# Snippets/Sidebar in a Can/The Magic Notebook is (c) 2001-3 by Jonathan
# Hayward, released under the Artistic License, and comes with no warranty.
# Please visit my homepage at http://JonathansCorner.com to see what else I've
# created--not just software.#Cosmetically adapted from Brent B. Welch, _Practical Programming in Tcl and
#Tk_
proc URLDecode {url} {
	regsub -all {%C2%A0} $url { } url
	regsub -all {\+} $url { } url
	regsub -all {%([[:xdigit:]]{2})} $url \
		{[format %c 0x\1]} url
	return [subst $url]
}
########## end Snippets/Sidebar

proc push { sock } {
  global config
  global user
  upvar #0 config$sock data
  set dontcache true 
# Use R's current directory as a first try at retrieving requests 
# The regex strips off the leading slash
   	regsub {(^/)} $data(url) {} mypath 

# If we can't find it in R's current directory, use the root directory
    if {![file exists $mypath]} {
      set mypath [ URLtoString "$config(root)$data(url)"]
      regsub -all "\\.UP\\./" $mypath "../" mypath
      set dontcache false
    }

#  regsub -all "\\.\\./" $mypath "" mypath
  if {[file isdirectory $mypath]} { append mypath $config(default) }


  if {[string length $mypath] == 0} {
    push-error $sock 400 "$data(url) invalid path"
    return
  }

    if {[regexp .*Rpad_process.pl $data(url)]} {
        foreach {name value} [split $data(query) &=] {
            set user([URLDecode $name]) [URLDecode $value]
        } 
        if {$user(command) == "savefile"} {
            if {![catch {open $user(filename) w} savedfile]} {
                puts $savedfile $user(content)
                close $savedfile
            }
# do we need to send something back?
            puts $sock "HTTP/1.0 200 Data follows"
            puts $sock "Date: [fmtdate [clock clicks]]"
            puts $sock "Last-Modified: [fmtdate [clock clicks]]"
#            puts $sock "Connection: Keep-Alive"
            puts $sock "Content-Type: text/plain"
            puts $sock ""
            puts $sock testtesttest
            puts $sock ""
            disconnect $sock
            return
        }
        if {$user(command) == "savehtml"} {
            if {![catch {open $user(filename) w} savedfile]} {
                puts $savedfile {<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0//EN"><html><head><meta http-equiv="Content-Type" content="text/html; charset=utf-8" /><script type="text/javascript" src="editor/Rpad_loader.js"></script></head><body>}
                puts $savedfile $user(content)
                puts $savedfile {</body></html>}
                close $savedfile
            }
# do we need to send something back?
            disconnect $sock
            return
        }
# default is to log in (needed because Mozilla doesn't send a LF after the POST,
# so the [read $sock] doesn't pick up the command=login
#        if {$user(command) == "login"} {
            puts $sock "HTTP/1.0 200 Data follows"
            puts $sock "Content-Type: text/plain"
            puts $sock "Content-Length: 12"
            puts $sock ""
            puts -nonewline $sock "testtesttest"
            disconnect $sock
            return
#        }
        disconnect $sock
        return
    }
    if {[regexp .*R_process.pl $data(url)]} {
        foreach {name value} [split $data(query) &=] {
            set user([URLDecode $name]) [URLDecode $value]
        } 
# run the commands in R
        if {$user(command) == "R_commands"} {
            R_eval "processRpadCommands()"
            puts $sock "HTTP/1.0 200 Data follows"
            puts $sock "Content-Type: text/plain"
            puts $sock ""
#            fconfigure $sock -translation binary -blocking $config(sockblock)
            puts $sock $RpadTclResults
            disconnect $sock
            return
       }
# default to returning something - otherwise IE hangs up sometimes
       puts $sock "HTTP/1.0 200 Data follows"
       puts $sock "Content-Type: text/plain"
#       puts $sock "Content-Length: 12"
       puts $sock ""
       puts $sock testtesttest
       puts $sock ""
       disconnect $sock
       return
    }
    if {[regexp .*shell_process.pl $data(url)]} {
            puts $sock "HTTP/1.0 200 Data follows"
            puts $sock "Content-Type: text/plain"
            puts $sock ""
            puts $sock {Not implemented}
            puts $sock ""
            disconnect $sock
        return
    }


  if {![catch {open $mypath} in]} {
    puts $sock "HTTP/1.x 200 Data follows"
    puts $sock "Date: [fmtdate [file mtime $mypath]]"
    if {$dontcache} {
      puts $sock "Pragma: no-cache"
      puts $sock "Cache-Control: no-cache"
      puts $sock "Expires: [fmtdate [file mtime $mypath]]"
    }      
    puts $sock "Last-Modified: [fmtdate [file mtime $mypath]]"
    puts $sock "Content-Type: [mime-type $mypath]"
    puts $sock "Content-Length: [file size $mypath]"
    puts $sock ""
    fconfigure $sock -translation binary -blocking $config(sockblock)
    fconfigure $in -translation binary -blocking 1
    fcopy $in $sock -command [list finish $mypath $in $sock]
  } else {
    push-error $sock 404 "$data(url) $in"
  }
#  disconnect $sock
}

# convert the file suffix into a mime type
array set mimetypes {
  {}    text/plain
  .txt  text/plain
  .htm  text/html
  .html text/html
  .gif  image/gif
  .jpg  image/jpeg
  .xbm  image/x-xbitmap
    .png	image/png
    .css	text/css
    .js	    application/x-javascript
    .htc	text/x-component
    .xml	text/xml
    .pdf    application/pdf                
    .eps    application/postscript
    .ps     application/postscript                
    .Rpad   text/html
}

proc mime-type {path} {
  global mimetypes

  set type text/plain
  catch {set type $mimetypes([file extension $path])}
  return $type
}

proc push-error {sock code errmsg } {
  upvar #0 config$sock data
  global errors

  append data(url) ""
  set message "<title>Error: $code</title>Error <b>$data(url): $errors($code)</b>."
  puts $sock "HTTP/1.0 $code $errors($code)"
  puts $sock "Date: [fmtdate [clock clicks]]"
  puts $sock "Content-Length: [string length $message]"
  puts $sock ""
  puts $sock $message
  flush $sock
#  putlog $sock Error $message
  disconnect $sock
}

# Generate a date string in HTTP format.
proc fmtdate {clicks} {
  return [clock format $clicks -format {%a, %d %b %Y %T %Z}]
}

# Decode url-encoded strings.
proc URLtoString {data} {
  regsub -all {([][$\\])} $data {\\\1}
  regsub -all {%([0-9a-fA-F][0-9a-fA-F])} $data  {[format %c 0x\1]} data
  return [subst $data]
}

proc bgerror {msg} {
    global errorInfo
#    puts stderr "bgerror: $msg\n$errorInfo"
}

# Here's how to start the Tcl server:
#   server e:/misc/www/Rpad 8080 index.html
