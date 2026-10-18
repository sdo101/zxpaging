#PRAGMA push(case_insensitive)
#PRAGMA case_insensitive = True
#define STANDALONE  ' remove ROM initialization and SysVars...

' N.B: this must be the very first code in the file, the core calls address $6000 to run this page...
' ...the build script checks that the compiled code really does start at $6000
s_lib_demo()
' and so we finally need this in order to return to the core which called us...
Asm
    ret
End Asm


#include "constants.bas"
#include "globals.bas"
#include "stage-include.bas"

' this page is a LIBRARY, not a stage: the core does not run it in turn, a stage calls one of its routines when it wants it,
' s_core_call_library( UB_PAGED_CODE_LIB_DEMO , <which routine> ), and carries on afterwards just where it was...
' ...for the length of the call this page is in MMU 3 in place of the stage, and the stage's page is put back after it,
' see s_core_call_library() in core.bas
'
' why a program on the Next wants libraries: a stage is one page of code, 8KB, and everything it does must fit in it...
' ...code that more than one stage needs cannot live in any one of them, a stage cannot call into another stage, both
' would have to be at $6000 at once, and the core's own two pages fill up soon enough...
' ...a library is the way out: as many pages of code as are needed, each one called for one routine at a time, by any
' stage, or by another library
'
' its routines, the one wanted is in gub_lib_function, what is handed over is in gub_lib_param_1:
'   UB_LIB_DEMO_COUNT   counts a call from the stage whose letter is in gub_lib_param_1, L, C or R, in this library's own
'                       storage, and hands back the total of all calls so far in guw_lib_result
'   UB_LIB_DEMO_SHOW    shows the counts, under the labels stage-init.bas drew
'
' its own storage: the top 512 bytes of this page, A_LIB_PRIVATE, $7E00 to $7FFF while it runs...
' ...no other page can see them, and no stage needs to give up any of its core data for them...
' ...and they keep what was left in them from one call to the next, this page being RAM like any other: the counts below
' go up and up, whichever stage calls, although nothing outside this page holds them
' N.B: build.ps1 checks that this page's code stops short of A_LIB_PRIVATE, at UW_LIB_CODE_LIMIT, 7680 bytes
' N.B: they start out as noughts, the rest of the page in the nex file, and they are not in a save, which keeps the core
' data and the data pages only: a library that must keep something across a save puts it in the core data

' --- working storage, private to this page ---
#define A_DEMO_ALL          A_LIB_PRIVATE           ' 4 bytes, every call counted
#define A_DEMO_LEFT         A_LIB_PRIVATE + 4       ' 2 bytes, calls from the left stage
#define A_DEMO_CENTRE       A_LIB_PRIVATE + 6       ' 2 bytes, from the centre stage
#define A_DEMO_RIGHT        A_LIB_PRIVATE + 8       ' 2 bytes, from the right stage


Sub s_demo_count( pub_letter As UByte )
    ' counts one call from the stage with that letter
    Poke ULong A_DEMO_ALL , Peek( ULong , A_DEMO_ALL ) + 1
    If pub_letter = 76 Then Poke UInteger A_DEMO_LEFT , Peek( UInteger , A_DEMO_LEFT ) + 1         ' 76 = "L"
    If pub_letter = 67 Then Poke UInteger A_DEMO_CENTRE , Peek( UInteger , A_DEMO_CENTRE ) + 1     ' 67 = "C"
    If pub_letter = 82 Then Poke UInteger A_DEMO_RIGHT , Peek( UInteger , A_DEMO_RIGHT ) + 1       ' 82 = "R"
    ' what is handed back goes in the core data, the caller cannot see this page once the call is over
    guw_lib_result = Peek( UInteger , A_DEMO_ALL )
End Sub


Sub s_demo_show()
    ' the counts, read from this page's own storage, beside the labels stage-init.bas drew
    s_core_print_string_at( 12 , 56 , "L " + fs_core_number( Peek( UInteger , A_DEMO_LEFT ) ) + "  C " + fs_core_number( Peek( UInteger , A_DEMO_CENTRE ) ) + "  R " + fs_core_number( Peek( UInteger , A_DEMO_RIGHT ) ) + "  all " + fs_core_number( Peek( ULong , A_DEMO_ALL ) ) + "  " , UB_BRIGHT_CYAN )
End Sub


Sub s_lib_demo()
    If gub_lib_function = UB_LIB_DEMO_COUNT Then
        s_demo_count( gub_lib_param_1 )
    ElseIf gub_lib_function = UB_LIB_DEMO_SHOW Then
        s_demo_show()
    End If
End Sub
