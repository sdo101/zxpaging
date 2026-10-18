#PRAGMA push(case_insensitive)
#PRAGMA case_insensitive = True
#define STANDALONE  ' remove ROM initialization and SysVars...

' N.B: this must be the very first code in the file, the core calls address $6000 to run this stage...
' ...the build script checks that the compiled code really does start at $6000
s_stage_init()
Asm
    ret
End Asm


#include "constants.bas"
#include "globals.bas"
#include "stage-include.bas"
#include "stage-data-include.bas"


Function fub_init_test_data_slot( pub_slot As UByte , puw_address As UInteger , pub_page_1 As UByte , pub_page_2 As UByte ) As UByte
    ' a test of one paged data slot, returns true if it passed...
    ' ...puw_address is where the slot appears in memory, $0000 for slot 0, $2000 for slot 1, $4000 for slot 2
    ' the test: put the first page in the slot and write to its first and last bytes, do the same with the second page using different values,
    ' then go back to each page in turn and check that what we wrote is still there, i.e. that these really are two
    ' separate pages, and that each one keeps its contents while it is paged out
    Dim lub_first_1 , lub_last_1 , lub_first_2 , lub_last_2 As UByte

    ' four values that are different from each other, and different for every slot
    lub_first_1 = $A0 + pub_slot
    lub_last_1  = $A8 + pub_slot
    lub_first_2 = $B0 + pub_slot
    lub_last_2  = $B8 + pub_slot

    s_core_swap_paged_data( pub_slot , pub_page_1 )
    Poke puw_address        , lub_first_1
    Poke puw_address + 8191 , lub_last_1        ' 8191 = the last byte of an 8KB page

    s_core_swap_paged_data( pub_slot , pub_page_2 )
    Poke puw_address        , lub_first_2
    Poke puw_address + 8191 , lub_last_2

    s_core_swap_paged_data( pub_slot , pub_page_1 )
    If Peek( puw_address )        <> lub_first_1 Then Return false
    If Peek( puw_address + 8191 ) <> lub_last_1  Then Return false

    s_core_swap_paged_data( pub_slot , pub_page_2 )
    If Peek( puw_address )        <> lub_first_2 Then Return false
    If Peek( puw_address + 8191 ) <> lub_last_2  Then Return false

    ' asking for the page that is already there must change nothing, the core counts this as a "hit"
    s_core_swap_paged_data( pub_slot , pub_page_2 )
    If Peek( puw_address ) <> lub_first_2 Then Return false

    Return true
End Function


Sub s_init_show_result( pub_row As UByte , ps_what As String , pub_passed As UByte )
    ' one test, at the top left, and how it went, the results in a column of their own
    s_core_print_string_at( pub_row , 2 , ps_what , UB_WHITE )
    If pub_passed Then
        s_core_print_string_at( pub_row , 37 , "OK" , UB_BRIGHT_GREEN )
    Else
        s_core_print_string_at( pub_row , 37 , "FAILED" , UB_BRIGHT_RED )
    End If
End Sub


Sub s_init_test_paged_data()
    ' a test of the three paged data slots, MMU 0, 1 and 2, known as data_m, data_i and data_c
    ' N.B: this is the first thing to put our own pages into those slots, until now they held what the system left there
    Dim lub_passed As UByte

    s_core_print_string_at( 3 , 2 , "start up tests" , UB_BRIGHT_WHITE )

    ' each slot on its own, two pages apiece...
    lub_passed = fub_init_test_data_slot( 0 , A_MMU_SLOT_PAGED_DATA_M , UB_PAGE_TEST_DATA_M_1 , UB_PAGE_TEST_DATA_M_2 )
    s_init_show_result( 4 , "MMU 0 at $0000, pages 90 and 91" , lub_passed )

    lub_passed = fub_init_test_data_slot( 1 , A_MMU_SLOT_PAGED_DATA_I , UB_PAGE_TEST_DATA_I_1 , UB_PAGE_TEST_DATA_I_2 )
    s_init_show_result( 5 , "MMU 1 at $2000, pages 93 and 94" , lub_passed )

    lub_passed = fub_init_test_data_slot( 2 , A_MMU_SLOT_PAGED_DATA_C , UB_PAGE_TEST_DATA_C_1 , UB_PAGE_TEST_DATA_C_2 )
    s_init_show_result( 6 , "MMU 2 at $4000, pages 100 and 101" , lub_passed )

    ' ...then all three at the same time, each showing its own first page, which is how a program will normally run:
    ' three different kinds of data all in view together
    s_core_swap_paged_data( 0 , UB_PAGE_TEST_DATA_M_1 )
    s_core_swap_paged_data( 1 , UB_PAGE_TEST_DATA_I_1 )
    s_core_swap_paged_data( 2 , UB_PAGE_TEST_DATA_C_1 )
    lub_passed = true
    If Peek( A_MMU_SLOT_PAGED_DATA_M ) <> $A0 Then lub_passed = false
    If Peek( A_MMU_SLOT_PAGED_DATA_I )    <> $A1 Then lub_passed = false
    If Peek( A_MMU_SLOT_PAGED_DATA_C )  <> $A2 Then lub_passed = false
    s_init_show_result( 7 , "all three slots at the same time" , lub_passed )

    ' the core's own count of what it did, for each slot it should be 5 swaps (first, second, first, second, and back to first) and 1 hit...
    ' ...all on one row, under the tests
    s_core_print_string_at( 8 , 2 , "swaps/hits  MMU0 " + fs_core_number( gul_core_MMU0_page_swaps ) + "/" + fs_core_number( gul_core_MMU0_cache_hits ) + "  MMU1 " + fs_core_number( gul_core_MMU1_page_swaps ) + "/" + fs_core_number( gul_core_MMU1_cache_hits ) + "  MMU2 " + fs_core_number( gul_core_MMU2_page_swaps ) + "/" + fs_core_number( gul_core_MMU2_cache_hits ) , UB_DARK_GREY )
End Sub

Sub s_init_test_file()
    ' a test of saving and loading through the SD card: fill a page with a pattern, save it to a file, wipe the page,
    ' load the file back, and check that every one of the 8192 bytes is what it was
    ' the page is looked at through the third paged data slot, MMU 2 at $4000
    Dim luw_i                           As UInteger
    Dim lub_save , lub_load , lub_same  As UByte

    ' the pattern: each byte is the low half of its own position, flipped about a bit so that it is not simply 0, 1, 2, 3...
    s_core_swap_paged_data( 2 , UB_PAGE_TEST_FILE )
    For luw_i = 0 To 8191
        Poke A_MMU_SLOT_PAGED_DATA_C + luw_i , Cast( UByte , luw_i ) bXor $5A
    Next

    lub_save = fub_core_file_save_page( "zxpagingtest.bin" , UB_PAGE_TEST_FILE )

    ' wipe the page, so that what we find afterwards can only have come from the file
    For luw_i = 0 To 8191
        Poke A_MMU_SLOT_PAGED_DATA_C + luw_i , 0
    Next

    lub_load = fub_core_file_load_page( "zxpagingtest.bin" , UB_PAGE_TEST_FILE )

    lub_same = true
    For luw_i = 0 To 8191
        If Peek( A_MMU_SLOT_PAGED_DATA_C + luw_i ) <> ( Cast( UByte , luw_i ) bXor $5A ) Then
            lub_same = false
            Exit For
        End If
    Next

    If lub_save = 0 And lub_load = 0 And lub_same Then
        s_init_show_result( 9 , "a page saved to SD, loaded back" , true )
    Else
        s_init_show_result( 9 , "a page saved to SD, loaded back" , false )
        ' say which part failed: the error numbers from the save and from the load (0 = it worked), and whether the bytes matched
        s_core_print_string_at( 10 , 4 , "save error " + fs_core_number( lub_save ) + ", load error " + fs_core_number( lub_load ) + ", the same " + fs_core_number( lub_same ) , UB_BRIGHT_RED )
    End If
End Sub

Sub s_init_new_data_page( pub_page As UByte , pub_letter As UByte )
    ' one of the three pages of paged data, cleared, with its counter at 0, and its stage's letter kept in it
    s_core_swap_paged_data( UB_SLOT_DATA , pub_page )
    s_core_ram_fill( A_MMU_SLOT_PAGED_DATA_M , 8192 , 0 )
    Poke A_MMU_SLOT_PAGED_DATA_M + UB_DATA_LETTER , pub_letter
End Sub


Sub s_init_new_data()
    ' the example's data starts afresh: the program's own part of the core data page, which is always in MMU 6, and
    ' the three pages of paged data, which take turns in MMU 0, see stage-data-include.bas
    s_core_ram_fill( A_DEMO , UW_DEMO_SIZE , 0 )
    gub_demo_last_stage = 45                    ' 45 = "-", no stage has run yet
    s_init_new_data_page( UB_PAGE_DATA_LEFT , 76 )          ' "L"
    s_init_new_data_page( UB_PAGE_DATA_CENTRE , 67 )        ' "C"
    s_init_new_data_page( UB_PAGE_DATA_RIGHT , 82 )         ' "R"
End Sub


Sub s_init_title_screen()
    Dim lub_key As UByte        ' N.B: declared inside the Sub, so it lives on the stack and not in front of the code

    ' footer prompt (N.B: on row 30, the memory monitor that s_core_get_key() draws uses rows 19 to 28)
    s_core_print_string_at( 30 , 27 , "Press any key to begin..." , UB_BRIGHT_YELLOW )

    ' wait for user input
    s_core_get_key()
    ' check if the one-hour timeout occurred
    If guw_key_code = 0 Then gub_core_end = true

    ' rub out the prompt, and show which key it was as a test of the keyboard routine, at the top right: a label, and
    ' its value in a column of its own, as every panel on this screen has them
    s_core_print_string_at( 30 , 27 , "                         " , UB_BLACK )
    s_core_print_string_at( 3 , 44 , "keyboard" , UB_BRIGHT_WHITE )
    s_core_print_string_at( 4 , 44 , "started by" , UB_DARK_GREY )
    s_core_print_string_at( 4 , 56 , gs_key_astext , UB_BRIGHT_CYAN )
    ' ...and its key code, which also shows a stage calling the core's fs_core_number()
    s_core_print_string_at( 5 , 44 , "key code" , UB_DARK_GREY )
    s_core_print_string_at( 5 , 56 , fs_core_number( guw_key_code ) , UB_BRIGHT_CYAN )
    ' ...and its name again, this time worked out by the stage itself calling the core's fs_core_key_name()
    s_core_print_string_at( 6 , 44 , "key name" , UB_DARK_GREY )
    s_core_print_string_at( 6 , 56 , fs_core_key_name( gub_key_char , gub_key_modifiers ) , UB_BRIGHT_CYAN )
    ' ...then wait here until the key has been let go, which shows a stage calling the core's fub_core_scan_key()
    Do
        lub_key = fub_core_scan_key()
    Loop Until lub_key = 0
    s_core_print_string_at( 7 , 44 , "key" , UB_DARK_GREY )
    s_core_print_string_at( 7 , 56 , "released" , UB_BRIGHT_CYAN )

    ' the labels for the example's data, drawn once here, the stages and the library fill in the numbers, see
    ' stage-data-include.bas and stage-lib-demo.bas
    s_core_print_string_at( 9 , 44 , "library" , UB_BRIGHT_WHITE )
    s_core_print_string_at( 10 , 44 , "page" , UB_DARK_GREY )
    s_core_print_string_at( 10 , 56 , "71, in MMU 3 when called" , UB_WHITE )
    s_core_print_string_at( 11 , 44 , "its storage" , UB_DARK_GREY )
    s_core_print_string_at( 11 , 56 , "512 bytes at $7E00" , UB_WHITE )
    s_core_print_string_at( 12 , 44 , "calls" , UB_DARK_GREY )

    ' the stage table: a column each for the three stages, under their names, which each stage colours as it runs
    s_core_print_string_at( 14 , 2 , "stage" , UB_BRIGHT_WHITE )
    s_core_print_string_at( 15 , 2 , "code page" , UB_DARK_GREY )
    s_core_print_string_at( 15 , 20 , fs_core_number( UB_PAGED_CODE_STAGE_LEFT ) , UB_WHITE )
    s_core_print_string_at( 15 , 40 , fs_core_number( UB_PAGED_CODE_STAGE_CENTRE ) , UB_WHITE )
    s_core_print_string_at( 15 , 60 , fs_core_number( UB_PAGED_CODE_STAGE_RIGHT ) , UB_WHITE )
    s_core_print_string_at( 16 , 2 , "data page" , UB_DARK_GREY )
    s_core_print_string_at( 17 , 2 , "next stage in" , UB_DARK_GREY )
    s_data_stage_names( 0 )

    ' beside the monitor: the core data and the paged data
    s_core_print_string_at( 19 , 44 , "core data" , UB_BRIGHT_WHITE )
    s_core_print_string_at( 20 , 44 , "page" , UB_DARK_GREY )
    s_core_print_string_at( 20 , 56 , "52, in MMU 6, never out" , UB_WHITE )
    s_core_print_string_at( 21 , 44 , "stages run" , UB_DARK_GREY )
    s_core_print_string_at( 22 , 44 , "last stage" , UB_DARK_GREY )
    s_core_print_string_at( 24 , 44 , "paged data" , UB_BRIGHT_WHITE )
    s_core_print_string_at( 25 , 44 , "pages" , UB_DARK_GREY )
    s_core_print_string_at( 25 , 56 , "96 97 98, one a stage" , UB_WHITE )
    s_core_print_string_at( 26 , 44 , "slot" , UB_DARK_GREY )
    s_core_print_string_at( 26 , 56 , "MMU 0, each in turn" , UB_WHITE )

    ' what the keys do from now on, in the left, centre and right stages
    s_core_print_string_at( 30 , 2 , "L C R: that stage's data again, or on to it   S: save   O: load   M: monitor" , UB_BRIGHT_YELLOW )
End Sub


Sub s_stage_init()
    s_core_clear_screen()
    ' the title, and which stage is running at its right, see s_data_stage_names()
    s_core_print_string_at( 0 , 2 , "zxpaging  all eight MMU slots, paged code, paged data" , UB_BRIGHT_WHITE )
    s_core_print_string_at( 0 , 66 , "stage  INIT" , UB_BRIGHT_WHITE )
    s_core_print_string_at( 1 , 2 , "----------------------------------------------------------------------------" , UB_DARK_GREY )
    s_init_test_paged_data()
    s_init_test_file()
    s_init_new_data()
    s_init_title_screen()
End Sub
