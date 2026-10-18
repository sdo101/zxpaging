'##################################################################################################################################
' --- STRUCTURED DATA TYPES ---

' shared scratch variables...
' (A_API + 0 to A_API + 13 used to hold the addresses of the core routines, the jump table at $0040 replaces them)
Dim gub_shared_1                            As UByte    At A_API + 14
Dim gub_shared_2                            As UByte    At A_API + 15
Dim gub_shared_3                            As UByte    At A_API + 16
Dim gub_shared_4                            As UByte    At A_API + 17
Dim guw_shared_1                            As UInteger At A_API + 18
Dim guw_shared_2                            As UInteger At A_API + 20
Dim guw_shared_3                            As UInteger At A_API + 22
Dim guw_shared_4                            As UInteger At A_API + 24

' core data...
' which page is in each paged slot at the moment, and how often asking for a page found it already there (a hit) or had to change it (a swap)...
' ...MMU 3 is the paged code slot, MMU 0, 1 and 2 are the three paged data slots...
' N.B: each group is 9 bytes (1 + 4 + 4), and the three data slot groups must stay in this order, 9 bytes apart, starting at A_CORE + 9,
' because s_core_swap_paged_data() in core.bas works out where a slot's group is from its slot number
Dim gub_core_MMU3_page_number    As UByte    At A_CORE
Dim gul_core_MMU3_cache_hits     As ULong    At A_CORE + 1
Dim gul_core_MMU3_page_swaps     As ULong    At A_CORE + 5

Dim gub_core_MMU0_page_number    As UByte    At A_CORE + 9
Dim gul_core_MMU0_cache_hits     As ULong    At A_CORE + 10
Dim gul_core_MMU0_page_swaps     As ULong    At A_CORE + 14

Dim gub_core_MMU1_page_number    As UByte    At A_CORE + 18
Dim gul_core_MMU1_cache_hits     As ULong    At A_CORE + 19
Dim gul_core_MMU1_page_swaps     As ULong    At A_CORE + 23

Dim gub_core_MMU2_page_number    As UByte    At A_CORE + 27
Dim gul_core_MMU2_cache_hits     As ULong    At A_CORE + 28
Dim gul_core_MMU2_page_swaps     As ULong    At A_CORE + 32

' N.B: this used to be at A_CORE + 34, which is inside the four bytes of the swap counter just above it (A_CORE + 32 to 35)
Dim gub_core_stage               As UByte    At A_CORE + 36
' a library call: which of the library's routines is wanted, what is handed to it, and what it hands back, see
' s_core_call_library() in core.bas, N.B: in the core data, which every page can see, a library's own storage cannot be seen
' by its caller
Dim gub_lib_function             As UByte    At A_CORE + 37
Dim gub_lib_param_1              As UByte    At A_CORE + 38
Dim guw_lib_result               As UInteger At A_CORE + 39
Dim gub_core_end                 As UByte    At A_CORE + 43  ' flag for end
Dim gub_core_monitor             As UByte    At A_CORE + 44  ' enable the inflight memory monitor
Dim guw_core_stack_pos           As UInteger At A_CORE + 45  ' last known stack position
Dim guw_core_heap_top            As UInteger At A_CORE + 47  ' last known top of heap
Dim gub_core_file_error          As UByte    At A_CORE + 49  ' the system's error number from the last save or load that failed
Dim gub_core_file_slot           As UByte    At A_CORE + 50  ' which 8KB of a file the next page saved or loaded is, 255 for a file that is one page and no more, see fub_core_file_transfer()
Dim gub_core_file_handle         As UByte    At A_CORE + 51  ' the file that fub_core_file_transfer() has open, N.B: between calls too, while a file of many pages is being written
Dim gub_core_file_plan           As UByte    At A_CORE + 52  ' which steps the call under way takes, see fub_core_file_transfer()
Dim gub_core_next_stage          As UByte    At A_CORE + 53  ' the stage a stage asks to be run after it, by its UB_STAGE_ number, or UB_STAGE_INIT for the next in the round

' the example's core data, in the core data page, which is always in MMU 6, so the core and every stage can use these
' at any time, with no paging at all... a save keeps them, and a load brings them back, see A_DEMO in constants.bas
Dim gub_demo_mark_1              As UByte    At A_DEMO       ' "P" and "D", put there by a save, so a load can tell that a file
Dim gub_demo_mark_2              As UByte    At A_DEMO + 1   ' is one of ours, see fub_core_load_all()
Dim gub_demo_version             As UByte    At A_DEMO + 2   ' UB_SAVE_VERSION, also put there by a save
Dim gub_demo_last_stage          As UByte    At A_DEMO + 3   ' the letter of the last stage to run, L, C or R
Dim gul_demo_stages_run          As ULong    At A_DEMO + 4   ' how many times a stage has been run, of the three

' keyboard...
Dim gub_key_char            As UByte    At A_KEY        ' a, A
Dim guw_key_code            As UInteger At A_KEY + 1    ' ASCII code or special numbers
Dim gub_key_modifiers       As UByte    At A_KEY + 3    ' a bitmask of MB_KEY_CTRL, MB_KEY_SHIFT (caps shift) and MB_KEY_SYMBOL (symbol shift)
Dim gs_key_astext           As String   At A_KEY + 4    ' the key as text, e.g. a, Shift-A, Ctrl-A, #, Enter, Left, Backspace

'##################################################################################################################################