#PRAGMA push(case_insensitive)
#PRAGMA case_insensitive = True
#define STANDALONE  ' remove ROM initialization and SysVars...

' N.B: this must be the very first code in the file, the core calls address $6000 to run this stage...
' ...the build script checks that the compiled code really does start at $6000
s_stage_right()
' and so we finally need this in order to return to the core which called us...
Asm
    ret
End Asm


#include "constants.bas"
#include "globals.bas"
#include "stage-include.bas"
#include "stage-data-include.bas"


Sub s_stage_right()
    ' this stage's name in its colour, at the head of its column of the stage table and at the right of the title
    s_data_stage_names( 82 )

    ' count this stage in the core data, page its own data in, and wait for a key or the countdown...
    ' ...the R key (82) pages the data in again and counts again, the L key (76) moves on to the left straight away
    s_data_run( UB_PAGE_DATA_RIGHT , 82 , 60 , 76 )
End Sub
