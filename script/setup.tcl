set search_path [list ./ ./script /fetools/work_area/frontend/SAED32_EDK/lib/stdcell_lvt/db_nldm]
 
set target_library [list saed32lvt_ss0p75v25c.db]
 
set link_library "* $target_library"
 
set designer "name"
 
#define aliases

alias h history

alias rc "report_constraint -all_violators"
 
#set symbol_library

#set synthetic_library
 
