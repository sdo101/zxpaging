#PRAGMA push(case_insensitive)
#PRAGMA case_insensitive = True
#define STANDALONE  ' remove ROM initialization and SysVars...

' N.B: this must be the very first code in the file, the core calls address $6000 to run this stage...
' ...the build script checks that the compiled code really does start at $6000
s_stage_centre()
' and so we finally need this in order to return to the core which called us...
Asm
    ret
End Asm


#include "constants.bas"
#include "globals.bas"
#include "stage-include.bas"
#include "stage-data-include.bas"


Sub s_stage_centre()
    ' this stage's name in its colour, at the head of its column of the stage table and at the right of the title
    s_data_stage_names( 67 )

    ' count this stage in the core data, page its own data in, and wait for a key or the countdown...
    ' ...the C key (67) pages the data in again and counts again, the R key (82) moves on to the right straight away
    s_data_run( UB_PAGE_DATA_CENTRE , 67 , 40 , 82 )
End Sub
