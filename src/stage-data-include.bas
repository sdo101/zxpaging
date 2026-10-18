' the example of data, both kinds, shared by the left, centre and right stages, each has its own copy of these routines...
'
'   core data   page 52, always in MMU 6 at $C000, never paged out: the core and every stage simply use its variables,
'               gul_demo_stages_run and gub_demo_last_stage (see globals.bas), with no paging at all
'   paged data  pages 96, 97 and 98, one for each stage, which all take their turn in the same paged data slot, MMU 0
'               at $0000: a stage asks the core for its own page with s_core_swap_paged_data(), and the core changes
'               the slot only if some other page is in it (a swap), if its page is there already nothing is changed
'               (a hit), the memory monitor shows the hits and swaps for each slot as they happen
'
' so pressing a stage's own key again and again is all hits: the page is in already, and the counter inside it goes up
' by one each time, while moving to the next stage is a swap: its page takes the slot, and its own counter goes up
' S saves the core data page and the three data pages to the SD card, all four in the one file, O loads them back


Sub s_data_message( ps_text As String , pub_colour As UByte )
    ' the line under the monitor, for what saving or loading did
    s_core_clear_row( 29 , 2 , UB_BLACK )
    s_core_print_string_at( 29 , 2 , ps_text , pub_colour )
End Sub


Sub s_data_stage_name( pub_column As UByte , ps_name As String , pub_letter As UByte , pub_running As UByte , pub_colour As UByte )
    ' one stage's name at the head of its column of the stage table, in its colour if it is the one running
    If pub_letter = pub_running Then
        s_core_print_string_at( 14 , pub_column , ps_name , pub_colour )
    Else
        s_core_print_string_at( 14 , pub_column , ps_name , UB_DARK_GREY )
    End If
End Sub


Sub s_data_stage_names( pub_running As UByte )
    ' the stage table's three names, the running stage's in its colour, and its name at the right of the title, the
    ' stage's letter in pub_running, 0 for the start up stage, which writes its own name
    s_data_stage_name( 20 , "LEFT" , 76 , pub_running , UB_BRIGHT_YELLOW )      ' 76 = "L"
    s_data_stage_name( 40 , "CENTRE" , 67 , pub_running , UB_BRIGHT_GREEN )    ' 67 = "C"
    s_data_stage_name( 60 , "RIGHT" , 82 , pub_running , UB_BRIGHT_RED )       ' 82 = "R"
    If pub_running = 76 Then s_core_print_string_at( 0 , 66 , "stage  LEFT  " , UB_BRIGHT_YELLOW )
    If pub_running = 67 Then s_core_print_string_at( 0 , 66 , "stage  CENTRE" , UB_BRIGHT_GREEN )
    If pub_running = 82 Then s_core_print_string_at( 0 , 66 , "stage  RIGHT " , UB_BRIGHT_RED )
End Sub


Sub s_data_show_page( pub_column As UByte )
    ' shows what is in the data page that is in MMU 0 now, in the stage's column of the stage table: the page's number,
    ' the letter kept in the page itself, which shows that the right page really is in the slot, and the page's counter
    Dim lub_letter As UByte
    lub_letter = Peek( A_MMU_SLOT_PAGED_DATA_M + UB_DATA_LETTER )
    If lub_letter = 0 Then lub_letter = 63              ' 63 = "?", the page has never been given its letter
    s_core_print_string_at( 16 , pub_column , "                  " , UB_BLACK )                   ' 18 cells
    s_core_print_string_at( 16 , pub_column , fs_core_number( gub_core_MMU0_page_number ) + " (" + fs_core_char( lub_letter ) + "), count " + fs_core_number( Peek( ULong , A_MMU_SLOT_PAGED_DATA_M + UB_DATA_COUNTER ) ) , UB_BRIGHT_CYAN )
End Sub


Sub s_data_page_in( pub_page As UByte , pub_column As UByte )
    ' pages the stage's own data page into MMU 0, a hit if it is there already, a swap if not, and adds one to its counter
    s_core_swap_paged_data( UB_SLOT_DATA , pub_page )
    Poke ULong A_MMU_SLOT_PAGED_DATA_M + UB_DATA_COUNTER , Peek( ULong , A_MMU_SLOT_PAGED_DATA_M + UB_DATA_COUNTER ) + 1
    s_data_show_page( pub_column )
End Sub


Sub s_data_show_core()
    ' shows the core data, read straight from page 52 in MMU 6, no paging needed, beside the labels stage-init.bas drew
    s_core_print_string_at( 21 , 56 , fs_core_number( gul_demo_stages_run ) , UB_BRIGHT_CYAN )
    s_core_print_string_at( 22 , 56 , fs_core_char( gub_demo_last_stage ) , UB_BRIGHT_CYAN )
End Sub


Sub s_data_save()
    Dim lub_failed As UByte
    lub_failed = fub_core_save_all()
    If lub_failed = 0 Then
        s_data_message( "saved: the core data, 3 data pages" , UB_BRIGHT_GREEN )
    Else
        s_data_message( "save failed: file " + fs_core_number( lub_failed ) + ", error " + fs_core_number( gub_core_file_error ) , UB_BRIGHT_RED )
    End If
End Sub


Sub s_data_load( pub_page As UByte )
    ' loads all four pages back, and then shows each data page's counter again under its stage's letter, which means
    ' paging each of them into MMU 0 in turn, the monitor counts those swaps too, and last of all the stage's own page
    Dim lub_failed As UByte
    lub_failed = fub_core_load_all()
    If lub_failed = 0 Then
        s_data_message( "loaded: the core data, 3 data pages" , UB_BRIGHT_GREEN )
        s_core_swap_paged_data( UB_SLOT_DATA , UB_PAGE_DATA_LEFT )
        s_data_show_page( 20 )
        s_core_swap_paged_data( UB_SLOT_DATA , UB_PAGE_DATA_CENTRE )
        s_data_show_page( 40 )
        s_core_swap_paged_data( UB_SLOT_DATA , UB_PAGE_DATA_RIGHT )
        s_data_show_page( 60 )
        s_core_swap_paged_data( UB_SLOT_DATA , pub_page )
    ElseIf lub_failed = 5 Then
        s_data_message( "that file is not one of ours" , UB_BRIGHT_RED )
    ElseIf gub_core_file_error = 5 Then
        s_data_message( "nothing to load, press S to save" , UB_BRIGHT_RED )         ' 5 = no such file
    Else
        s_data_message( "load failed: file " + fs_core_number( lub_failed ) + ", error " + fs_core_number( gub_core_file_error ) , UB_BRIGHT_RED )
    End If
End Sub


Sub s_data_run( pub_page As UByte , pub_letter As UByte , pub_column As UByte , pub_flip_key As UByte )
    ' what each of the three stages does once its marker is up: counts itself in the core data, pages its own data in,
    ' then waits with a countdown, and acts on the keys...
    '   its own letter      page its data in again (a hit, as it is still there) and count once more, wait again
    '   S or O              save or load, wait again
    '   another's letter    return to the core, asking it to run that stage next (L, C or R, from any of the three)
    '   the countdown running out: return to the core, which runs the next stage in the round
    Dim lub_key As UByte

    gul_demo_stages_run = gul_demo_stages_run + 1
    gub_demo_last_stage = pub_letter
    ' the library counts this stage's coming in, in its own private storage, and shows its counts, see stage-lib-demo.bas
    gub_lib_param_1 = pub_letter
    s_core_call_library( UB_PAGED_CODE_LIB_DEMO , UB_LIB_DEMO_COUNT )
    s_core_call_library( UB_PAGED_CODE_LIB_DEMO , UB_LIB_DEMO_SHOW )
    lub_key = pub_letter                ' coming in counts as a press of the stage's own key
    Do
        If lub_key = pub_letter  Then s_data_page_in( pub_page , pub_column )
        If lub_key = UC_KEY_SAVE Then s_data_save()
        If lub_key = UC_KEY_LOAD Then s_data_load( pub_page )
        s_data_show_core()
        lub_key = fub_core_countdown( 17 , pub_column , pub_letter , pub_flip_key )
    Loop While lub_key = pub_letter Or lub_key = UC_KEY_SAVE Or lub_key = UC_KEY_LOAD
    If lub_key = UC_KEY_LEFT   Then gub_core_next_stage = UB_STAGE_LEFT
    If lub_key = UC_KEY_CENTRE Then gub_core_next_stage = UB_STAGE_CENTRE
    If lub_key = UC_KEY_RIGHT  Then gub_core_next_stage = UB_STAGE_RIGHT
End Sub
