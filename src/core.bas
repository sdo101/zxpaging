#PRAGMA push(case_insensitive)
#PRAGMA case_insensitive = True
#define STANDALONE  ' remove ROM initialization and SysVars...

' N.B: these two includes only declare constants and fixed address variables, they produce no code or data...
' ...they are up here so that the start up code below can use the constants
#include "constants.bas"
#include "globals.bas"

' N.B: this must be the very first code in the file, it is what sits at address $8000, where the loader jumps to...
' ...the build script checks that nothing has been placed in front of it, so the core must not use arrays or ordinary
' variables outside of a Sub or Function, only variables declared with "At <address>" (strings are fine, they live in the heap)
' N.B: the core lives in MMU 4 and 5, not at the bottom of memory, see the notes at the top of constants.bas for why...
' ...so there are no interrupt or restart vectors in here, interrupts use mode 2 and the loader has already set that up
Asm
    jp core_start   ; address $8000: the loader jumps here

    org $8010       ; the API jump table, three bytes per entry, the order must match the A_JUMP_ list in constants.bas...
                    ; ...only ever add new entries at the end, the stages have the addresses of the existing ones compiled in...
                    ; ...(the table can now grow as long as it likes, the start up code simply follows it)
    jp _s_core_next_reg
    jp _s_core_crash
    jp _s_core_ram_copy
    jp _s_core_clear_screen
    jp _s_core_print_char_at
    jp _s_core_print_string_at
    jp _s_core_get_key
    jp _fub_core_countdown
    jp _fs_core_number
    jp _fub_core_scan_key
    jp _fs_core_key_name
    jp _s_core_swap_paged_data
    jp _fub_core_file_save_page
    jp _fub_core_file_load_page
    jp _fs_core_char
    jp _s_core_ram_fill
    jp _fub_core_save_all
    jp _fub_core_load_all
    jp _s_core_clear_row
    jp _s_core_call_library

core_start:
    di                          ; interrupts off, they stay off except while we are deliberately waiting for one
    ld sp, A_Z80_CPU_STACK      ; move the stack to the top of page 11, which the loader mapped into MMU 7

    ; map the core data page (52) into MMU 6, nextreg $56...
    ; ...the loader could not do this for us, because the loader itself was running in MMU 6, this is what discards it
    ld bc, A_NEXTREG_SELECT
    ld a, $56
    out (c), a
    ld bc, A_NEXTREG_DATA
    ld a, 52
    out (c), a

    ; fill the whole stack area with a known byte, the stack is empty at this moment so nothing is lost...
    ; ...the memory monitor later counts how many of these bytes are still untouched, to show how deep the stack has ever been
    ld hl, A_STACK_BOTTOM
    ld de, A_STACK_BOTTOM + 1
    ld bc, A_Z80_CPU_STACK - A_STACK_BOTTOM - 1
    ld (hl), UB_STACK_FILL
    ldir

    ; fill the heap with a known byte too, before it is prepared, so the memory monitor can show how much of it has ever been used...
    ; ...the compiler knows where the heap is and how big, from the --heap-address and --heap-size options in build.ps1
    ld hl, .core.ZXBASIC_MEM_HEAP
    ld de, .core.ZXBASIC_MEM_HEAP + 1
    ld bc, .core.ZXBASIC_HEAP_SIZE - 1
    ld (hl), UB_HEAP_FILL
    ldir

    ; headerless mode leaves out the compilers own start up code, which is what normally prepares the heap...
    ; ...so we prepare it here ourselves, before any string is used...
    ; ...it takes the heap address and size from the --heap-address and --heap-size options in build.ps1
    call .core.__MEM_INIT
End Asm

s_core_main()


'##################################################################################################################################
' --- BORIEL LANGUAGE TIPS ---
' 1) about FastCall
'   - can be used with Function and/or Sub
'   - a FastCall routine can only ever accept no parameters at all, or only one parameter
'     i.e. am FastCall routine can never accept more than one parameter
'   - if the parameter is a byte it is available upon entry in the A register
'   - if the parameter is a word it is available upon entry in the HL register pair
'   - if the parameter is a long it is available upon entry in the DEHL registers
' 2) @ can be used to acquire address (pointer) and * can be used to dereference the pointer/address
'##################################################################################################################################


'##################################################################################################################################
' --- CORE ROUTINES ---

Sub s_core_next_reg( pub_reg As UByte , pub_value As UByte )
    gub_shared_1 = pub_reg
    gub_shared_2 = pub_value
    Asm
        ld a, (_gub_shared_1)   ; load register number
        ld bc, A_NEXTREG_SELECT ; use your constant $243B
        out (c), a              ; select register

        ld a, (_gub_shared_2)   ; load value
        ld bc, A_NEXTREG_DATA   ; use your constant $253B
        out (c), a              ; write value
    End Asm
End Sub


Sub s_core_return_to_zxos()
    ' perform hardware soft reset...
    ' N.B: the soft reset bit lives in nextreg $02, not in nextreg $00 (which is the read only machine id)
    s_core_next_reg( UB_NEXTREG_RESET_CONFIG , UB_NEXTREG_MACHINE_RESET )
End Sub


Sub s_core_print_char_at( pub_x As UByte , pub_y As UByte , pub_char As UByte , pub_colour As UByte )
    ' puts one character, in one colour, into one cell of the screen
    ' N.B: every caller passes ( row , column ), so pub_x is the row (0 to 31) and pub_y is the column (0 to 79)
    ' N.B: all in Z80, this is the most called routine there is: the compiler has already put the address of the
    ' parameters into IX, and a UByte parameter is the high byte of the pair it was pushed as, which is why the
    ' offsets are the odd numbers: row ix+5, column ix+7, character ix+9, colour ix+11
    Asm
        ; guard: quietly ignore anything off screen, a bad position would otherwise be written over the stack,
        ; which sits just above the screen cells
        ld a, (ix+5)                    ; the row
        cp 32                           ; UB_SCREEN_ROWS
        jr nc, s_core_print_char_at_end
        ld d, a
        ld a, (ix+7)                    ; the column
        cp 80                           ; UB_SCREEN_COLS
        jr nc, s_core_print_char_at_end

        ; the cell is at screen base + row * 160 + column * 2: two bytes a cell, eighty cells a row
        ld e, 160
        mul d, e                        ; DE = row * 160, a Next instruction
        ld hl, A_SCREEN_BASE
        add hl, de
        add a, a                        ; column * 2, 158 at most
        add hl, a                       ; a Next instruction

        ld a, (ix+9)
        ld (hl), a                      ; the character
        inc hl
        ld a, (ix+11)
        ld (hl), a                      ; its colour
    s_core_print_char_at_end:
    End Asm
End Sub


Sub s_core_clear_row( pub_row As UByte , pub_from As UByte , pub_colour As UByte )
    ' fills one row of the screen with spaces of one colour, from the column pub_from to the end of the row (0 for
    ' the whole row): the first cell is written, and LDIR copies it along the others
    ' N.B: one call instead of up to eighty to s_core_print_char_at(), the core and, through the jump table, the
    ' stages use it
    Asm
        ; guard: quietly ignore anything off screen, as s_core_print_char_at() does
        ld a, (ix+5)                    ; the row
        cp 32                           ; UB_SCREEN_ROWS
        jr nc, s_core_clear_row_end
        ld d, a
        ld a, (ix+7)                    ; the column to start from
        cp 80                           ; UB_SCREEN_COLS
        jr nc, s_core_clear_row_end
        ld c, a

        ld e, 160
        mul d, e                        ; DE = row * 160, a Next instruction
        ld hl, A_SCREEN_BASE
        add hl, de
        add a, a                        ; column * 2
        add hl, a                       ; a Next instruction, HL = the first cell to clear

        ld (hl), 32
        inc hl
        ld a, (ix+9)
        ld (hl), a                      ; the colour
        dec hl

        ; the cells after it, ( 79 - column ) of them, two bytes each
        ld a, 79
        sub c
        jr z, s_core_clear_row_end      ; N.B: none, the last column: LDIR with a count of 0 would copy 65536 bytes
        add a, a
        ld c, a
        ld b, 0
        ld d, h
        ld e, l
        inc de
        inc de                          ; DE = the cell after the first
        ldir
    s_core_clear_row_end:
    End Asm
End Sub


Sub s_core_clear_screen()
    ' fill all 80 x 32 cells with a two byte pair: a space, and attribute 0 (black ink on black paper)
    Asm
        ld hl, A_SCREEN_BASE
        ld (hl), 32
        inc hl
        ld (hl), 0
        ld hl, A_SCREEN_BASE
        ld de, A_SCREEN_BASE + 2
        ld bc, 5118
        ldir
    End Asm
End Sub


Sub s_core_pause()
    ' a delay of one second, so that the eye can follow the stages taking turns...
    ' ...timed by 50 frame interrupts, and not by counting round an empty loop, which would run eight times faster
    ' at 28MHz than at 3.5MHz
    Asm
        ld b, 50
    core_pause_frame:
        ei                  ; let the next frame interrupt in, and wait for it
        halt
        di                  ; interrupts stay off the rest of the time
        djnz core_pause_frame
    End Asm
End Sub


Sub s_core_print_string_at( pub_x As UByte , pub_y As UByte , ps_text As String , pub_colour As UByte )
    ' puts a string, in one colour, on the screen from ( row , column ) onwards, stopping at the end of the row
    ' N.B: every caller passes ( row , column ), so pub_x is the row (0 to 31) and pub_y is the column (0 to 79)
    ' N.B: all in Z80, the characters are read straight out of the string: in BASIC each one was taken with
    ' ps_text( i ), which builds a new string of one character in the heap and frees it again, for every character,
    ' and that made drawing the memory monitor take long enough to miss key presses, even at 28MHz
    ' N.B: a string parameter is the address of the string in the heap, at ix+8 and ix+9, and a string there is its
    ' length, two bytes, then its characters... the compiler's own code at the end of this routine frees it, as before
    ' the other parameters, as in s_core_print_char_at(): row ix+5, column ix+7, colour ix+11
    Asm
        ; guard: quietly ignore a position that is off screen
        ld a, (ix+5)                    ; the row
        cp 32                           ; UB_SCREEN_ROWS
        jr nc, s_core_print_string_at_end
        ld d, a
        ld e, 160
        mul d, e                        ; DE = row * 160, a Next instruction
        ld hl, A_SCREEN_BASE
        add hl, de                      ; HL = the start of the row
        ld a, (ix+7)                    ; the column
        cp 80                           ; UB_SCREEN_COLS
        jr nc, s_core_print_string_at_end
        ld c, a

        ; the string: no string at all, or an empty one, is nothing to do
        ld e, (ix+8)
        ld d, (ix+9)
        ld a, d
        or e
        jr z, s_core_print_string_at_end
        ld a, (de)                      ; its length, low byte...
        ld b, a
        inc de
        ld a, (de)                      ; ...and high byte, anything over 255 is more than a row holds anyway
        inc de                          ; DE = the first character
        or a
        jr z, s_core_print_string_at_short
        ld b, 80
    s_core_print_string_at_short:
        ld a, b
        or a
        jr z, s_core_print_string_at_end

        ; no further than the end of the row: at most ( 80 - column ) characters
        ld a, 80
        sub c
        cp b
        jr nc, s_core_print_string_at_fits
        ld b, a
    s_core_print_string_at_fits:
        ld a, c
        add a, a                        ; column * 2
        add hl, a                       ; a Next instruction, HL = the first cell
        ld c, (ix+11)                   ; the colour

    s_core_print_string_at_next:
        ld a, (de)
        or a                            ; a 0 in the string ends it, as it always has
        jr z, s_core_print_string_at_end
        ld (hl), a                      ; the character
        inc hl
        ld (hl), c                      ; its colour
        inc hl
        inc de
        djnz s_core_print_string_at_next
    s_core_print_string_at_end:
    End Asm
End Sub


Function fs_core_char( pub_code As UByte ) As String
    ' a string of one character, given its code, it is our own replacement for Chr$...
    ' N.B: Chr$ is not used anywhere in this demo: the compiler's own routine for it keeps a value, while it works, in the
    ' system variable DEST at $5C4D, as is right on an ordinary Spectrum, but in this demo's memory layout that address is
    ' in whatever page is in MMU 2 at the time, see the notes in constants.bas
    ' N.B: a string is its length, 2 bytes, and then its characters, so a string of one space is made, and the space is changed
    Dim ls_one As String

    ls_one = " "
    Poke Peek( UInteger , @ls_one ) + 2 , pub_code
    Return ls_one
End Function


Function fs_core_number( pul_value As ULong ) As String
    ' turns a whole number into text, e.g. 1234 into "1234", it is our own replacement for Str$...
    ' N.B: Str$ is not used anywhere in this demo: the compiler implements it by calling the floating point calculator
    ' inside the Spectrum ROM (rst $28), as is right on an ordinary Spectrum, but in this demo's memory layout the ROM is
    ' not there once our own data is in MMU 0 and 1...
    ' ...the same goes for anything else that needs floating point, see the notes in constants.bas for the whole list
    Dim ls_text     As String
    Dim lul_value   As ULong = pul_value
    ls_text = ""
    Do
        ' peel off the last digit, and put it on the front of the text
        ls_text   = fs_core_char( 48 + Cast( UByte , lul_value Mod 10 ) ) + ls_text       ' 48 = "0"
        lul_value = lul_value / 10
    Loop Until lul_value = 0
    Return ls_text
End Function


Function fs_core_padded( ps_text As String , pub_width As UByte ) As String
    ' the text with spaces added on the end to make it pub_width long, for lining things up in columns
    Dim ls_text As String
    ls_text = ps_text
    While Len( ls_text ) < pub_width
        ls_text = ls_text + " "
    End While
    Return ls_text
End Function


Function fs_core_monitor_slot( pub_page As UByte , pul_hits As ULong , pul_swaps As ULong ) As String
    ' one slot's line in the memory monitor: its page, its hits and its swaps, in columns
    Dim ls_page As String
    If pub_page = 255 Then
        ls_page = "sys"
    Else
        ls_page = fs_core_number( pub_page )
    End If
    Return fs_core_padded( ls_page , 6 ) + fs_core_padded( fs_core_number( pul_hits ) , 10 ) + fs_core_number( pul_swaps )
End Function


Function fuw_core_first_changed( puw_from As UInteger , puw_count As UInteger , pub_fill As UByte ) As UInteger
    ' the address of the first byte from puw_from onwards that is no longer pub_fill, looking at puw_count bytes at
    ' most, or puw_from + puw_count if every one of them still is... the memory monitor uses it to find how much of
    ' the heap and the stack has ever been used, as the core filled both with a known byte at start up
    ' N.B: in Z80, the stack is 3070 bytes, too many to look at one at a time in BASIC every time the monitor is drawn
    ' the parameters: puw_from ix+4 and ix+5, puw_count ix+6 and ix+7, pub_fill ix+9
    Asm
        ld l, (ix+4)
        ld h, (ix+5)
        ld c, (ix+6)
        ld b, (ix+7)
        ld e, (ix+9)                    ; the fill byte
        ld a, b
        or c
        jr z, core_first_changed_done
    core_first_changed_next:
        ld a, (hl)
        cp e
        jr nz, core_first_changed_done
        inc hl
        dec bc
        ld a, b
        or c
        jr nz, core_first_changed_next
    core_first_changed_done:
        ld (_guw_shared_4), hl
    End Asm
    Return guw_shared_4
End Function


Sub s_core_display_monitor()
    ' draws a box showing how the four paged slots, the heap and the stack are being used
    ' N.B: everything is measured before this routine builds any strings of its own, so that what it reports is everybody
    ' else's use
    Dim i                           As Ubyte
    Dim lub_collision               As UByte
    Dim lub_blocks                  As UByte
    Dim luw_screen_top              As UInteger
    Dim luw_stack_pos               As UInteger
    Dim luw_scan                    As UInteger
    Dim luw_heap_start              As UInteger
    Dim luw_heap_size               As UInteger
    Dim luw_heap_free               As UInteger
    Dim luw_heap_biggest            As UInteger
    Dim luw_block , luw_size        As UInteger
    Dim ls_top_line , ls_box_line   As String
    Dim luw_heap_most               As UInteger
    Dim lub_speed                   As UByte
    Dim luw_stack_most              As UInteger

    luw_screen_top = A_STACK_BOTTOM         ' i.e. directly above the 5120 bytes of screen cells

    Asm
        ld hl, 0
        add hl, sp
        ld (_guw_shared_1), hl
        ld hl, .core.ZXBASIC_MEM_HEAP       ; where the heap is, and how big, as the compiler was told in build.ps1
        ld (_guw_shared_2), hl
        ld hl, .core.ZXBASIC_HEAP_SIZE
        ld (_guw_shared_3), hl
    End Asm
    luw_stack_pos  = guw_shared_1
    luw_heap_start = guw_shared_2
    luw_heap_size  = guw_shared_3

    ' measure the heap FIRST, before this routine builds any strings of its own, so that what it reports is everybody else's use...
    ' ...the heap begins with a 4 byte header, and after that it is a chain of free blocks, each one starts with two words:
    ' its own size in bytes, and the address of the next free block, or 0 if it is the last one...
    ' ...the header has the same shape, with a size of 0, so the address of the first free block is in its second word
    luw_heap_free    = 0
    luw_heap_biggest = 0
    lub_blocks       = 0
    luw_block        = Peek( UInteger , luw_heap_start + 2 )
    While luw_block <> 0 And lub_blocks < 64        ' the 64 is only a safety limit, in case the chain has been damaged
        luw_size = Peek( UInteger , luw_block )
        luw_heap_free = luw_heap_free + luw_size
        If luw_size > luw_heap_biggest Then luw_heap_biggest = luw_size
        luw_block  = Peek( UInteger , luw_block + 2 )
        lub_blocks = lub_blocks + 1
    End While

    ' the most the heap has ever used...
    ' ...the core filled the heap with UB_HEAP_FILL at start up, and the heap hands out memory from its top end downwards,
    ' so we walk up from just above the header and its first free block until we meet the first byte that has been overwritten
    luw_scan = fuw_core_first_changed( luw_heap_start + 8 , luw_heap_size - 8 , UB_HEAP_FILL )
    luw_heap_most = luw_heap_start + luw_heap_size - luw_scan

    ' the most the stack has ever used...
    ' ...the core filled the whole stack area with UB_STACK_FILL at start up, and the stack grows downwards from the top,
    ' so we walk up from the bottom until we meet the first byte that has been overwritten
    luw_scan = fuw_core_first_changed( A_STACK_BOTTOM , A_Z80_CPU_STACK - A_STACK_BOTTOM , UB_STACK_FILL )
    luw_stack_most = A_Z80_CPU_STACK - luw_scan

    ' the box, rows 19 to 28, columns 2 to 41, and in it...
    ls_top_line = "+--------------------------------------+"
    ls_box_line = "|                                      |"
    s_core_print_string_at( 19 , 2 , ls_top_line , UB_DARK_GREY )
    For i = 20 To 27
        s_core_print_string_at( i , 2 , ls_box_line , UB_DARK_GREY )
    Next
    s_core_print_string_at( 28 , 2 , ls_top_line , UB_DARK_GREY )

    ' ...the four paged slots: which page each holds now, and how often asking for a page found it already there (a hit)
    ' or had to change it (a swap), "sys" means the system's own page is still there, none of ours has been put in yet
    s_core_print_string_at( 20 , 3 , "slot   page  hits      swaps" , UB_WHITE )
    s_core_print_string_at( 21 , 3 , "MMU 0  " + fs_core_monitor_slot( gub_core_MMU0_page_number , gul_core_MMU0_cache_hits , gul_core_MMU0_page_swaps ) , UB_DARK_GREY )
    s_core_print_string_at( 22 , 3 , "MMU 1  " + fs_core_monitor_slot( gub_core_MMU1_page_number , gul_core_MMU1_cache_hits , gul_core_MMU1_page_swaps ) , UB_DARK_GREY )
    s_core_print_string_at( 23 , 3 , "MMU 2  " + fs_core_monitor_slot( gub_core_MMU2_page_number , gul_core_MMU2_cache_hits , gul_core_MMU2_page_swaps ) , UB_DARK_GREY )
    s_core_print_string_at( 24 , 3 , "MMU 3  " + fs_core_monitor_slot( gub_core_MMU3_page_number , gul_core_MMU3_cache_hits , gul_core_MMU3_page_swaps ) , UB_DARK_GREY )

    ' ...the heap: b = the biggest single free block, a string longer than this cannot be built even if the total free
    ' is more, s = bytes in use now (the 4 is the heap's own header, which is never available), f = free now, m = the most
    ' ever in use... and the stack: p = where the stack pointer is, s = bytes in use now, f = free now, m = the most ever
    s_core_print_string_at( 25 , 3 , "heap   b:" + fs_core_padded( fs_core_number( luw_heap_biggest ) , 6 ) + "s:" + fs_core_padded( fs_core_number( luw_heap_size - 4 - luw_heap_free ) , 6 ) + "f:" + fs_core_padded( fs_core_number( luw_heap_free ) , 6 ) + "m:" + fs_core_number( luw_heap_most ) , UB_DARK_GREY )
    s_core_print_string_at( 26 , 3 , "stack  p:" + fs_core_padded( fs_core_number( luw_stack_pos ) , 6 ) + "s:" + fs_core_padded( fs_core_number( A_Z80_CPU_STACK - luw_stack_pos ) , 6 ) + "f:" + fs_core_padded( fs_core_number( luw_stack_pos - luw_screen_top ) , 6 ) + "m:" + fs_core_number( luw_stack_most ) , UB_DARK_GREY )

    ' ...and the speed the CPU is really running at, read from the CPU Speed Register, bits 5 and 4, see load.bas
    Out $243B , $07
    lub_speed = ( In( $253B ) >> 4 ) bAnd 3
    If lub_speed = UB_CPU_SPEED_3MHZ  Then s_core_print_string_at( 27 , 3 , "cpu    3.5MHz" , UB_BRIGHT_RED )
    If lub_speed = UB_CPU_SPEED_7MHZ  Then s_core_print_string_at( 27 , 3 , "cpu    7MHz" , UB_BRIGHT_RED )
    If lub_speed = UB_CPU_SPEED_14MHZ Then s_core_print_string_at( 27 , 3 , "cpu    14MHz" , UB_BRIGHT_RED )
    If lub_speed = UB_CPU_SPEED_28MHZ Then s_core_print_string_at( 27 , 3 , "cpu    28MHz" , UB_DARK_GREY )

    lub_collision = false
    If luw_stack_pos <= luw_screen_top Then
        s_core_print_string_at( 27 , 25 , "COLLISION" , UB_BRIGHT_RED )
        lub_collision = true
    End If
    If lub_collision Then
        Asm
            di
            halt
        End Asm
    End If
End Sub


Sub s_core_wait_for_vblank()
    ' pause the CPU to save power until the next 20ms tick...
    Asm
        ei          ; enable interrupts to allow wake-up
        halt        ; wait for the jump to $0038
        di          ; disable interrupts again for total control
    End Asm
End Sub


Function fub_core_scan_key() As UByte
    ' looks at the keyboard once, right now, and returns the code of the key that is down, or 0 if there is none...
    ' ...it does not wait, s_core_get_key() is the routine that waits for a key
    ' it also sets gub_key_modifiers, to say whether caps shift and/or symbol shift are being held
    '
    ' how the keyboard is read:
    '   the 40 keys are wired as 8 rows of 5, and a row is chosen by which bit of the HIGH byte of the port address is 0...
    '   ...the low byte of the port address is always $FE, and nothing needs to be written to the port first...
    '   ...in the byte that comes back bits 0 to 4 are the five keys of that row, and a bit is 0 while its key is down.
    '       row 0   port $FEFE   caps shift, Z, X, C, V
    '       row 1   port $FDFE   A, S, D, F, G
    '       row 2   port $FBFE   Q, W, E, R, T
    '       row 3   port $F7FE   1, 2, 3, 4, 5
    '       row 4   port $EFFE   0, 9, 8, 7, 6
    '       row 5   port $DFFE   P, O, I, U, Y
    '       row 6   port $BFFE   enter, L, K, J, H
    '       row 7   port $7FFE   space, symbol shift, M, N, B
    '   every key therefore has an index of ( row * 5 ) + bit, from 0 to 39, e.g. caps shift is 0 and symbol shift is 36
    ' N.B: bAnd and bOr are the bitwise operators, a plain And or Or would only give true or false
    '
    ' what comes back:
    '   on its own a key gives the code in key_table_normal, i.e. lower case letters, digits, 13 for enter, 32 for space
    '   with symbol shift it gives the code in key_table_symbol, where that is not 0
    '   with caps shift a letter comes back in upper case, and these combinations give the traditional Spectrum editing keys...
    '       caps shift + 5, 6, 7, 8  =  left, down, up, right  (UW_KEY_LEFT etc.)
    '       caps shift + 0           =  8  (delete / backspace)
    '       caps shift + space       =  27 (break, which we treat as escape)
    '       caps shift + 1, 2, 3, 4  =  edit, caps lock, true video, inv video  (UW_KEY_EDIT etc.)
    '       caps shift + 9           =  graph
    '
    ' Ctrl:
    '   a Spectrum has no Ctrl key, so we use "extend" as our Ctrl, i.e. caps shift and symbol shift held together...
    '   ...while it is held a letter comes back as the classic control code, Ctrl-A = 1, Ctrl-B = 2 ... Ctrl-Z = 26,
    '   and gub_key_modifiers is set to MB_KEY_CTRL (and to nothing else), any other key comes back as its normal code...
    '   ...on its own it is just a modifier, like the shift keys, and gives 0
    '   how the user types Ctrl-A on each keyboard:
    '       a real Next keyboard     = hold EXTEND, press A
    '       a classic keyboard       = hold caps shift and symbol shift, press A
    '       a PS/2 keyboard          = hold the two keys that the Next treats as caps shift and symbol shift, press A...
    '                                  ...(one PS/2 key cannot be extend, the Next's key table allows a key one shift, not both)
    '       ZEsarUX                  = hold Tab, press A, or hold Shift and Ctrl together, press A...
    '                                  ...(ZEsarUX makes Tab extend, Shift caps shift, and both Ctrl and Alt symbol shift)
    '   N.B: several control codes are the same number as another key, e.g. Ctrl-H = 8 = delete, Ctrl-M = 13 = enter...
    '   ...so always look at MB_KEY_CTRL in gub_key_modifiers to tell them apart
    '
    ' which keyboards this works with:
    '   a classic 40 key Spectrum keyboard        = everything above, the special keys are typed as the combinations
    '   a real Next keyboard                      = the same, plus it has a dedicated key for each special key, and for ; " , .
    '   a PS/2 keyboard plugged into a Next       = the Next turns each of its keys into one of the above before we ever see it
    ' the Next's dedicated keys are read first, from nextreg $B0 and $B1, so they are recognised for what they are...
    ' ...(the Next also presses the matching combination in the 8 x 5 matrix for us, which is why the modifiers are
    ' reported as 0 for these keys, we cannot tell a real caps shift from the one the Next added)
    Dim lub_row , lub_bit , lub_mask , lub_bits     As UByte
    Dim lub_index , lub_found , lub_code            As UByte
    Dim lub_caps , lub_sym , lub_ctrl               As UByte
    Dim luw_row_bit , luw_port                      As UInteger

    ' first the Next keyboard's dedicated keys, in both registers a bit is 1 while its key is down...
    ' ...on anything that does not have these registers they read as 0, so this part simply finds nothing...
    ' ...(a reading of 255 would mean all eight keys at once, so that is treated as "not there" as well)
    Out A_NEXTREG_SELECT , UB_NEXTREG_EXT_KEYS_0
    lub_bits = In( A_NEXTREG_DATA )
    If lub_bits <> 0 And lub_bits <> 255 Then
        gub_key_modifiers = 0
        If ( lub_bits bAnd %00001000 ) <> 0 Then Return Cast( UByte , UW_KEY_UP )
        If ( lub_bits bAnd %00000100 ) <> 0 Then Return Cast( UByte , UW_KEY_DOWN )
        If ( lub_bits bAnd %00000010 ) <> 0 Then Return Cast( UByte , UW_KEY_LEFT )
        If ( lub_bits bAnd %00000001 ) <> 0 Then Return Cast( UByte , UW_KEY_RIGHT )
        If ( lub_bits bAnd %10000000 ) <> 0 Then Return 59      ' ;
        If ( lub_bits bAnd %01000000 ) <> 0 Then Return 34      ' "
        If ( lub_bits bAnd %00100000 ) <> 0 Then Return 44      ' ,
        If ( lub_bits bAnd %00010000 ) <> 0 Then Return 46      ' .
    End If
    lub_ctrl = false
    Out A_NEXTREG_SELECT , UB_NEXTREG_EXT_KEYS_1
    lub_bits = In( A_NEXTREG_DATA )
    If lub_bits = 255 Then lub_bits = 0
    ' the EXTEND key is our Ctrl, so it is noted as a modifier and is not a key in its own right...
    If ( lub_bits bAnd %00000001 ) <> 0 Then lub_ctrl = true
    lub_bits = lub_bits bAnd %11111110
    If lub_bits <> 0 Then
        gub_key_modifiers = 0
        If ( lub_bits bAnd %10000000 ) <> 0 Then Return 8       ' delete, the same code as caps shift + 0
        If ( lub_bits bAnd %00100000 ) <> 0 Then Return 27      ' break, the same code as caps shift + space
        If ( lub_bits bAnd %01000000 ) <> 0 Then Return Cast( UByte , UW_KEY_EDIT )
        If ( lub_bits bAnd %00000010 ) <> 0 Then Return Cast( UByte , UW_KEY_CAPS_LOCK )
        If ( lub_bits bAnd %00001000 ) <> 0 Then Return Cast( UByte , UW_KEY_TRUE_VIDEO )
        If ( lub_bits bAnd %00010000 ) <> 0 Then Return Cast( UByte , UW_KEY_INV_VIDEO )
        If ( lub_bits bAnd %00000100 ) <> 0 Then Return Cast( UByte , UW_KEY_GRAPH )
    End If

    ' now the 8 x 5 matrix that every keyboard has...
    lub_found   = 255       ' 255 = no key found yet
    lub_caps    = false
    lub_sym     = false
    luw_row_bit = 1
    For lub_row = 0 To 7
        ' build the port address for this row: the high byte is all 1s except for this row's bit, the low byte is $FE
        luw_port = ( ( 255 - luw_row_bit ) << 8 ) bOr $FE
        lub_bits = In( luw_port ) bAnd %00011111
        If lub_bits <> %00011111 Then
            lub_mask = 1
            For lub_bit = 0 To 4
                If ( lub_bits bAnd lub_mask ) = 0 Then
                    lub_index = ( lub_row * 5 ) + lub_bit
                    If lub_index = 0 Then
                        lub_caps = true
                    ElseIf lub_index = 36 Then
                        lub_sym = true
                    ElseIf lub_found = 255 Then
                        lub_found = lub_index       ' if several keys are down, the first one found wins
                    End If
                End If
                lub_mask = lub_mask << 1
            Next
        End If
        luw_row_bit = luw_row_bit << 1
    Next

    ' both shift keys together is extend, which is our Ctrl (the Next's EXTEND key presses both of them for us)...
    If lub_caps And lub_sym Then lub_ctrl = true

    gub_key_modifiers = 0
    If lub_ctrl Then
        gub_key_modifiers = MB_KEY_CTRL
    Else
        If lub_caps Then gub_key_modifiers = gub_key_modifiers bOr MB_KEY_SHIFT
        If lub_sym  Then gub_key_modifiers = gub_key_modifiers bOr MB_KEY_SYMBOL
    End If

    ' no ordinary key is down, only modifiers at most...
    If lub_found = 255 Then Return 0

    lub_code = Peek( @key_table_normal + lub_found )
    If lub_ctrl Then
        ' Ctrl + a letter gives the classic control code, Ctrl-A = 1 ... Ctrl-Z = 26, anything else keeps its normal code
        If lub_code >= 97 And lub_code <= 122 Then lub_code = lub_code - 96
        Return lub_code
    End If
    If lub_sym Then
        lub_index = Peek( @key_table_symbol + lub_found )
        If lub_index <> 0 Then lub_code = lub_index
    ElseIf lub_caps Then
        If lub_found = 19 Then                              ' caps shift + 5
            lub_code = Cast( UByte , UW_KEY_LEFT )
        ElseIf lub_found = 24 Then                          ' caps shift + 6
            lub_code = Cast( UByte , UW_KEY_DOWN )
        ElseIf lub_found = 23 Then                          ' caps shift + 7
            lub_code = Cast( UByte , UW_KEY_UP )
        ElseIf lub_found = 22 Then                          ' caps shift + 8
            lub_code = Cast( UByte , UW_KEY_RIGHT )
        ElseIf lub_found = 20 Then                          ' caps shift + 0
            lub_code = 8
        ElseIf lub_found = 35 Then                          ' caps shift + space
            lub_code = 27
        ElseIf lub_found = 15 Then                          ' caps shift + 1
            lub_code = Cast( UByte , UW_KEY_EDIT )
        ElseIf lub_found = 16 Then                          ' caps shift + 2
            lub_code = Cast( UByte , UW_KEY_CAPS_LOCK )
        ElseIf lub_found = 17 Then                          ' caps shift + 3
            lub_code = Cast( UByte , UW_KEY_TRUE_VIDEO )
        ElseIf lub_found = 18 Then                          ' caps shift + 4
            lub_code = Cast( UByte , UW_KEY_INV_VIDEO )
        ElseIf lub_found = 21 Then                          ' caps shift + 9
            lub_code = Cast( UByte , UW_KEY_GRAPH )
        ElseIf lub_code >= 97 And lub_code <= 122 Then      ' a letter, make it upper case
            lub_code = lub_code - 32
        End If
    End If
    ' for the special keys the caps shift was part of typing the key, not a modifier, so do not report it...
    ' ...this also makes a combination typed on a classic keyboard look exactly the same as the Next's dedicated key
    If lub_code = 8 Or lub_code = 27 Or lub_code >= 130 Then gub_key_modifiers = 0
    Return lub_code

    ' the two lookup tables, one byte per key, in key index order, i.e. five keys per row...
    ' ...they sit here, after the Return, so that they are part of the code and never run as instructions...
    ' ...(a Dim'd array would make the compiler put data in front of the code, which the core must not have)
key_table_normal:
    Asm
        defb   0, 122, 120,  99, 118    ; row 0: caps shift, z, x, c, v
        defb  97, 115, 100, 102, 103    ; row 1: a, s, d, f, g
        defb 113, 119, 101, 114, 116    ; row 2: q, w, e, r, t
        defb  49,  50,  51,  52,  53    ; row 3: 1, 2, 3, 4, 5
        defb  48,  57,  56,  55,  54    ; row 4: 0, 9, 8, 7, 6
        defb 112, 111, 105, 117, 121    ; row 5: p, o, i, u, y
        defb  13, 108, 107, 106, 104    ; row 6: enter, l, k, j, h
        defb  32,   0, 109, 110,  98    ; row 7: space, symbol shift, m, n, b
    End Asm
key_table_symbol:
    Asm
        defb   0,  58,  35,  63,  47    ; row 0: (caps shift), z = :   x = #   c = ?   v = /
        defb 126, 124,  92, 123, 125    ; row 1: a = ~   s = |   d = \   f = {   g = }
        defb  60,  62,  96,  60,  62    ; row 2: q = <   w = >   e = `   r = <   t = >
        defb  33,  64,  35,  36,  37    ; row 3: 1 = !   2 = @   3 = #   4 = $   5 = %
        defb  95,  41,  40,  39,  38    ; row 4: 0 = _   9 = )   8 = (   7 = '   6 = &
        defb  34,  59,   0,  93,  91    ; row 5: p = "   o = ;   i = none   u = ]   y = [
        defb   0,  61,  43,  45,  94    ; row 6: enter = none   l = =   k = +   j = -   h = ^
        defb   0,   0,  46,  44,  42    ; row 7: space = none   (symbol shift)   m = .   n = ,   b = *
    End Asm
    Return 0        ' never reached, it is only here because the compiler expects a Function to end with a Return
End Function


Function fs_core_key_name( pub_code As UByte , pub_modifiers As UByte ) As String
    ' turns a key code from fub_core_scan_key(), and the modifiers that came with it, into text for showing to the user...
    ' ...e.g. "a", "Shift-A", "Ctrl-A", "Enter", "Left", "#"
    Dim msg , add       As String

    msg = ""
    If ( pub_modifiers bAnd MB_KEY_CTRL )  <> 0 Then msg = msg + "Ctrl-"
    If ( pub_modifiers bAnd MB_KEY_SHIFT ) <> 0 Then msg = msg + "Shift-"
    If ( pub_modifiers bAnd MB_KEY_CTRL ) <> 0 And pub_code >= 1 And pub_code <= 26 Then
        msg = msg + fs_core_char( pub_code + 64 )       ' a control code, show it as its letter, 1 = "A"
    ElseIf pub_code >= 33 And pub_code <= 126 Then
        msg = msg + fs_core_char( pub_code )
    Else
        add = ""
        If pub_code = 27                                Then add = "ESC"
        If pub_code = 32                                Then add = "Space"
        If pub_code = 13                                Then add = "Enter"
        If pub_code = 8                                 Then add = "Backspace"
        If pub_code = Cast( UByte , UW_KEY_UP )         Then add = "Up"
        If pub_code = Cast( UByte , UW_KEY_DOWN )       Then add = "Down"
        If pub_code = Cast( UByte , UW_KEY_LEFT )       Then add = "Left"
        If pub_code = Cast( UByte , UW_KEY_RIGHT )      Then add = "Right"
        If pub_code = Cast( UByte , UW_KEY_EDIT )       Then add = "Edit"
        If pub_code = Cast( UByte , UW_KEY_CAPS_LOCK )  Then add = "Caps Lock"
        If pub_code = Cast( UByte , UW_KEY_TRUE_VIDEO ) Then add = "True Video"
        If pub_code = Cast( UByte , UW_KEY_INV_VIDEO )  Then add = "Inv Video"
        If pub_code = Cast( UByte , UW_KEY_GRAPH )      Then add = "Graph"
        If add = ""                                     Then add = "c" + fs_core_number( pub_code )
        msg = msg + add
    End If
    Return msg
End Function


Sub s_core_toggle_monitor()
    ' the M key is the core's own: it turns the memory monitor on and off, whatever stage is running, and is never
    ' handed on to the stage (it was the GRAPH key, caps shift and 9, until 16 October 2026)
    Dim i As UByte
    gub_core_monitor = Not gub_core_monitor
    If gub_core_monitor Then
        s_core_display_monitor()
    Else
        For i = 19 To 28
            s_core_print_string_at( i , 2 , "                                        " , UB_BLACK )     ' 40 cells
        Next
    End If
    ' wait for the key to be let go, or it would be taken again straight away
    Do
        s_core_wait_for_vblank()
    Loop Until fub_core_scan_key() = 0
End Sub


Function fub_core_countdown( pub_x As UByte , pub_y As UByte , pub_stay_key As UByte , pub_flip_key As UByte ) As UByte
    ' shows a countdown  5 4 3 2 1  at ( row , column ), one second per digit, and returns when it runs out...
    ' ...while it runs it watches the keyboard, the two keys are given as upper case character codes, e.g. 76 for "L",
    ' and any of these four ends it straight away, so that the stage can act on it:
    '   pub_stay_key                  =  the stage's own key, the stage stays, and starts another countdown
    '   pub_flip_key                  =  the next stage's key, the stage gives up waiting and returns to the core
    '   UC_KEY_LEFT, CENTRE or RIGHT  =  any stage's key, so that from any stage the user can go to any other
    '   UC_KEY_SAVE or UC_KEY_LOAD    =  the stage saves or loads, and starts another countdown
    ' returns the key that ended it, or 0 if it ran out... a key is only returned once it has been let go again, so that
    ' the next countdown does not find it still held down and take it for a second press
    ' N.B: the memory monitor is not drawn here, the core's main loop brings it up to date when the stage hands back
    ' the name of the last key pressed, e.g. "Ctrl-A", is shown two cells to the right of the digit, and stays there
    ' until another key is pressed or the countdown ends, as a running test of the keyboard routine
    ' the timing comes from the frame interrupt, which arrives 50 times a second whatever speed the CPU is set to
    Dim lub_seconds         As UByte = 5
    Dim lub_ticks           As UByte = 0
    Dim lub_key             As UByte
    Dim lub_shown_key       As UByte = 0        ' the key, and its modifiers, whose name is on screen at the moment
    Dim lub_shown_modifiers As UByte = 0
    Dim lub_result          As UByte = 0
    Do
        s_core_print_char_at( pub_x , pub_y , 48 + lub_seconds , UB_BRIGHT_WHITE )      ' 48 = "0"
        s_core_wait_for_vblank()

        lub_key = fub_core_scan_key()
        ' show the name of the key, but only when it changes, building the text 50 times a second would be wasteful
        If lub_key <> 0 Then
            If lub_key <> lub_shown_key Or gub_key_modifiers <> lub_shown_modifiers Then
                lub_shown_key       = lub_key
                lub_shown_modifiers = gub_key_modifiers
                s_core_print_string_at( pub_x , pub_y + 2 , "                " , UB_BLACK )       ' rub out the old name, 16 cells
                s_core_print_string_at( pub_x , pub_y + 2 , fs_core_key_name( lub_key , gub_key_modifiers ) , UB_BRIGHT_CYAN )
            End If
        End If

        ' the stay and flip keys are plain letters, a letter arrives in lower case unless caps shift is held,
        ' so make it upper case for the comparisons below (a Ctrl-letter is a control code, so it never matches)
        If lub_key >= 97 And lub_key <= 122 Then lub_key = lub_key - 32

        If lub_key = UC_KEY_MONITOR Then
            s_core_toggle_monitor()
            lub_key = 0
        End If

        If lub_key <> 0 And ( lub_key = pub_stay_key Or lub_key = pub_flip_key Or lub_key = UC_KEY_SAVE Or lub_key = UC_KEY_LOAD Or lub_key = UC_KEY_LEFT Or lub_key = UC_KEY_CENTRE Or lub_key = UC_KEY_RIGHT ) Then
            lub_result = lub_key
            Exit Do
        End If
        lub_ticks = lub_ticks + 1
        If lub_ticks = 50 Then
            lub_ticks   = 0
            lub_seconds = lub_seconds - 1
        End If
    Loop Until lub_seconds = 0
    s_core_print_char_at( pub_x , pub_y , 32 , UB_BLACK )                                        ' rub out the digit
    s_core_print_string_at( pub_x , pub_y + 2 , "                " , UB_BLACK )                   ' and the key name
    If lub_result <> 0 Then
        Do
            s_core_wait_for_vblank()
        Loop Until fub_core_scan_key() = 0
    End If
    Return lub_result
End Function


Sub s_core_get_key()
    ' waits for a key to be pressed, and then fills in...
    '   guw_key_code        the code of the key, see fub_core_scan_key() for what the codes are, or 0 if nobody pressed anything for an hour
    '   gub_key_char        the same code as a byte
    '   gub_key_modifiers   MB_KEY_CTRL, MB_KEY_SHIFT and/or MB_KEY_SYMBOL if those were being held
    '   gs_key_astext       the key as text for showing to the user, e.g. "a", "Shift-A", "Ctrl-A", "Enter", "Left"
    Dim lub_code        As UByte
    Dim lul_frames      As ULong

    If gub_core_monitor Then s_core_display_monitor()

    ' wait for every key to be let go, so that a key still held from before is not taken as a new press...
    Do
        s_core_wait_for_vblank()
    Loop Until fub_core_scan_key() = 0

    ' now wait for a new press, looking once per frame, i.e. 50 times a second...
    ' ...and give up after one hour: 60 minutes * 60 seconds * 50 frames = 180000 frames
    lul_frames = 0
    Do
        s_core_wait_for_vblank()
        lub_code   = fub_core_scan_key()
        lul_frames = lul_frames + 1
        If lul_frames >= 180000 Then
            guw_key_code = 0        ' signal the timeout
            gub_key_char = 0
            Return
        End If
        ' M is the core's own, see s_core_toggle_monitor(), the wait carries on for the key the caller wanted, N.B: M or
        ' m, with or without caps shift
        If lub_code = UC_KEY_MONITOR Or lub_code = UC_KEY_MONITOR + 32 Then
            s_core_toggle_monitor()
            lub_code = 0
        End If
    Loop Until lub_code <> 0

    ' populate the shared structure (fub_core_scan_key() has already set gub_key_modifiers)
    guw_key_code  = lub_code
    gub_key_char  = lub_code
    gs_key_astext = fs_core_key_name( lub_code , gub_key_modifiers )
End Sub


Sub s_core_crash( pub_error_code As UByte , ps_error_text As String )
    Dim x , y               As UByte
    Dim lub_error_row       As UByte
    Dim lub_error_col       As UByte
    Dim ls_error_message    As String
    Dim lub_max_length      As UByte = 78

    ' clear the last three lines...
    For x = 29 To 31
        For y = 0 to 79
            s_core_print_char_at( x , y , 32 , UB_BLACK )
        Next y
    Next x

    ' construct the error message...
    ls_error_message = "error " + fs_core_number( pub_error_code ) + " : " + ps_error_text

    ' truncate if the message is too wide for the screen...
    If Len( ls_error_message ) > lub_max_length Then 
        ls_error_message = ls_error_message( To ( lub_max_length - 1 ) )
    End If

    ' calculate positions based on the final message length...
    lub_error_row = 30
    lub_error_col = ( 80 - Len( ls_error_message ) ) / 2

    ' display centered error message
    s_core_print_string_at( lub_error_row , lub_error_col , ls_error_message , UB_BRIGHT_RED )

    ' wait for key press...
    s_core_get_key()
    s_core_return_to_zxos()
End Sub


Sub s_core_swap_paged_data( pub_slot As UByte , pub_page_number As UByte )
    ' puts a page into one of the three paged data slots, pub_slot is 0, 1 or 2...
    '   slot 0 = MMU 0 = $0000 to $1FFF     data_m
    '   slot 1 = MMU 1 = $2000 to $3FFF     data_i
    '   slot 2 = MMU 2 = $4000 to $5FFF     data_c
    ' ...and keeps count, exactly as s_core_swap_paged_code() does for the code slot, if the page is already there nothing is changed
    ' N.B: a slot's three tracking variables are found from its number, see the note beside them in globals.bas
    Dim luw_tracker As UInteger

    ' guard: there are only three data slots, anything else would remap the code, the data or the screen from under us
    If pub_slot > 2 Then Return

    luw_tracker = A_CORE + 9 + 9 * Cast( UInteger , pub_slot )
    If Peek( luw_tracker ) = pub_page_number Then
        Poke ULong luw_tracker + 1 , Peek( ULong , luw_tracker + 1 ) + 1       ' a hit
    Else
        s_core_next_reg( MMU_SLOT_0 + pub_slot , pub_page_number )              ' the MMU registers are $50 to $57, in slot order
        Poke luw_tracker , pub_page_number
        Poke ULong luw_tracker + 5 , Peek( ULong , luw_tracker + 5 ) + 1       ' a swap
    End If
End Sub


Sub s_core_swap_paged_code( pub_page_number As UByte )
    If gub_core_MMU3_page_number = pub_page_number Then
        gul_core_MMU3_cache_hits = gul_core_MMU3_cache_hits + 1
    Else
        s_core_next_reg( MMU_SLOT_PAGED_CODE , pub_page_number )
        gub_core_MMU3_page_number = pub_page_number
        gul_core_MMU3_page_swaps  = gul_core_MMU3_page_swaps + 1
    End If
End Sub


Sub s_core_call_library( pub_page As UByte , pub_function As UByte )
    ' runs one routine of a library page, a page of code that any stage may use, as one stage cannot use another...
    ' ...the stage that called is in the code slot, MMU 3, so the library takes its place for the length of the call: the
    ' library's page goes into the slot, it is called at $6000 with the routine wanted in gub_lib_function, and the page that
    ' was there is put back before we return, so the stage carries on as if nothing had happened
    ' N.B: this runs in the core, MMU 4 and 5, which is why it may swap the code slot out from under the stage that called it
    ' N.B: the page to go back to is kept on the stack, in lub_caller, not in a fixed place, so a library may itself call a library
    Dim lub_caller As UByte

    lub_caller       = gub_core_MMU3_page_number
    gub_lib_function = pub_function
    s_core_swap_paged_code( pub_page )
    Asm
        call A_MMU_SLOT_PAGED_CODE
    End Asm
    s_core_swap_paged_code( lub_caller )
End Sub


Sub s_core_ram_copy( puw_src_address As UInteger, puw_dst_address As UInteger, puw_byte_count As UInteger )
    If puw_byte_count = 0 Then 
        Return 
    End If
    If puw_src_address < puw_dst_address Then
        If ( puw_src_address + puw_byte_count ) >= puw_dst_address Then
            s_core_crash( UB_CRASH_RAMCOPY_OVERLAP , "ramcopy buffer overlap: " + fs_core_number( puw_dst_address ) )
        End If
    End If
    guw_shared_1 = puw_src_address
    guw_shared_2 = puw_dst_address
    guw_shared_3 = puw_byte_count
    Asm
        ld hl, (_guw_shared_1)
        ld de, (_guw_shared_2)
        ld bc, (_guw_shared_3)
        ldir
    End Asm
End Sub


Function fub_core_file_transfer( ps_name As String , pub_page As UByte , pub_write As UByte ) As UByte
    ' saves one 8KB page to a file on the SD card, or loads one 8KB page from a file, this is the routine behind
    ' fub_core_file_save_page() and fub_core_file_load_page(), which are the two that other code should call
    ' returns 0 if it worked, otherwise an error number:
    '   1 to 250 = the error number that the system gave us, e.g. 5 means "no such file"
    '   254      = the file name was empty, or longer than 63 characters
    '   255      = the system reported no error, but fewer than 8192 bytes were read or written
    ' a file may hold many pages, one after another: gub_core_file_slot says which of them this call is for, the first
    ' is 0, and such a file is never emptied, a page is written over the one that was there, 255, as it usually is,
    ' means the file is one page and no more, and writing it replaces the whole file
    ' N.B: a file of many pages is WRITTEN from its first page to its last, in order, in one go: page 0 makes the file
    ' afresh, deleting any there was, and it is then kept open while the others follow, each going where the last
    ' ended, until a call with gub_core_file_slot = 254 closes it, which the caller must make, even after a failure...
    ' ...why not open and close it for every page, "open it, or make it if it is not there"? NextZXOS would do that
    ' happily, but the ZEsarUX emulator, when it answers the file calls itself, empties a file every time it is opened
    ' for writing, however that is asked for, so a file written that way came out all noughts but for its last page...
    ' ...reading is simpler: any page of the file, opened, found (F_SEEK) and closed in the one call
    '
    ' how file access works on the Next:
    '   a file call is "rst $08" followed by one byte that says which call it is, with the details in registers...
    '   ...and NextZXOS will only answer it if its ROM is at the bottom of memory, where our three paged data slots are...
    '   ...so for the length of the call we lend those three slots back to the system, and then put our own pages back:
    '       MMU 0 and MMU 1 = the ROM
    '       MMU 2           = page 10, which holds the system's own variables
    '   everything of ours that has to survive is above that: this code (MMU 4 and 5), the core data (MMU 6), the stack (MMU 7)
    '   the page being saved or loaded is brought into MMU 3 at $6000 for the call, and the stage that was there is put back after
    '   the file name is copied into a small buffer inside this routine, i.e. in MMU 4 or 5, with a 0 on the end as the system expects
    ' N.B: because MMU 0, 1 and 2 are lent out, nothing in the paged data slots can be reached during the call,
    ' that is why this works in whole pages, the caller says which page and we fetch it ourselves
    Dim i , lub_length , lub_result As UByte

    If Len( ps_name ) = 0 Or Len( ps_name ) > 63 Then Return 254
    lub_length = Len( ps_name )
    For i = 0 To lub_length - 1
        Poke @core_file_name + i , Code( ps_name( i ) )
    Next
    Poke @core_file_name + lub_length , 0

    ' bring the page in question into MMU 3, and lend the bottom of memory to the system...
    ' N.B: file calls need the 48K BASIC ROM in particular, which is the ROM that is selected when a nex file is started,
    ' so we rely on that and do not select it ourselves... nextreg $8E can select it, but writing to $8E also puts
    ' the system's own pages back into MMU 6 and 7, i.e. it swaps our core data and our stack out from under us
    s_core_next_reg( MMU_SLOT_PAGED_CODE , pub_page )
    s_core_next_reg( MMU_SLOT_0 , 255 )         ' 255 = the ROM
    s_core_next_reg( MMU_SLOT_1 , 255 )
    s_core_next_reg( MMU_SLOT_2 , 10 )          ' page 10 = the system variables

    ' N.B: these are set here, and not earlier, because s_core_next_reg() uses the same shared scratch variables
    ' gub_core_file_plan says which of the steps below this call takes: 1 open the file, 2 seek, 4 close it afterwards,
    ' 8 no reading or writing at all
    If pub_write Then
        gub_shared_1 = $0E                      ' open for writing ($02), creating the file and deleting any existing one ($0C)
        If gub_core_file_slot = 255 Then
            gub_core_file_plan = 1 + 4          ' a file of one page: opened, written and closed
        ElseIf gub_core_file_slot = 254 Then
            gub_core_file_plan = 4 + 8          ' the file of many pages is finished with: closed, and nothing else
        ElseIf gub_core_file_slot = 0 Then
            gub_core_file_plan = 1              ' the first page of many: opened, written, and left open for the rest
        Else
            gub_core_file_plan = 0              ' a later page: written where the last one ended
        End If
    Else
        gub_shared_1 = $01                      ' open for reading ($01), the file must exist ($00)
        gub_core_file_plan = 1 + 4
        If gub_core_file_slot <> 255 Then gub_core_file_plan = 1 + 2 + 4
    End If
    gub_shared_4 = pub_write
    guw_shared_1 = A_MMU_SLOT_PAGED_CODE        ' where the page is, $6000
    guw_shared_2 = 8192                         ' how many bytes
    guw_shared_3 = 8192                         ' how many were read or written, set here for the call that only closes

    Asm
        push ix                     ; the compiler uses IX for this routine's own variables, and the calls want it for an address
        push iy
        ld iy, $5C3A                ; some system routines expect IY to point at the system variable ERR_NR

        ; F_OPEN: A = drive ("*" means the default drive), IX = the file name, B = how to open it
        ld a, (_gub_core_file_plan)
        and 1
        jr z, core_file_is_open
        ld a, (_gub_shared_1)
        ld b, a
        ld ix, core_file_name_asm
        ld a, 42                    ; "*"
        rst $08
        defb $9A
        jr c, core_file_failed      ; carry set = failed, with the error number in A
        ld (_gub_core_file_handle), a   ; otherwise A is the file handle, keep it
core_file_is_open:

        ; F_SEEK, to read one page of a file of many: A = the handle, BCDE = how far in, IXL = 0 for "from the start"
        ; the page wanted is gub_core_file_slot, 8192 bytes each, so BCDE = slot * $2000: D = the low 3 bits of the
        ; slot moved up 5, E = 0, C = the slot's other bits, B = 0
        ld a, (_gub_core_file_plan)
        and 2
        jr z, core_file_no_seek
        ld a, (_gub_core_file_slot)
        ld c, a
        and 7
        rrca
        rrca
        rrca
        ld d, a
        ld e, 0
        ld a, c
        srl a
        srl a
        srl a
        ld c, a
        ld b, 0
        ld ix, 0
        ld a, (_gub_core_file_handle)
        rst $08
        defb $9F
        jr c, core_file_close_failed
core_file_no_seek:
        ; F_READ or F_WRITE: A = the handle, IX = the address, BC = the number of bytes
        ld a, (_gub_core_file_plan)
        and 8
        jr nz, core_file_close_only
        ld ix, (_guw_shared_1)
        ld bc, (_guw_shared_2)
        ld a, (_gub_shared_4)
        or a
        ld a, (_gub_core_file_handle)
        jr nz, core_file_write
        rst $08
        defb $9D                    ; F_READ
        jr core_file_transferred
core_file_write:
        rst $08
        defb $9E                    ; F_WRITE
core_file_transferred:
        ld (_guw_shared_3), bc      ; BC = how many bytes were actually read or written
        jr c, core_file_close_failed    ; it failed: the file is closed whatever the plan was, and the failure reported
        ld a, (_gub_core_file_plan)
        and 4
        jr z, core_file_worked      ; a file of many pages is left open for its next page
core_file_close_only:
        ; F_CLOSE: A = the handle
        ld a, (_gub_core_file_handle)
        rst $08
        defb $9B
        jr c, core_file_failed
core_file_worked:
        xor a                       ; it all worked, 0 = no error
        jr core_file_finished
core_file_close_failed:
        push af                     ; the seek or the transfer failed: the file is closed, and that failure is what is reported
        ld a, (_gub_core_file_handle)
        rst $08
        defb $9B
        pop af
core_file_failed:
        or a                        ; make sure that a failure is never reported as 0
        jr nz, core_file_finished
        ld a, 255
core_file_finished:
        ld (_gub_shared_2), a
        di                          ; the system may have switched interrupts on, we keep them off
        pop iy
        pop ix
    End Asm
    lub_result = gub_shared_2

    ' take the bottom of memory back, each slot gets the page that s_core_swap_paged_data() last put there...
    ' ...255 means we never put one of our pages there, which for MMU 0 and 1 is the ROM, and for MMU 2 is page 10, as they already are
    s_core_next_reg( MMU_SLOT_0 , gub_core_MMU0_page_number )
    s_core_next_reg( MMU_SLOT_1 , gub_core_MMU1_page_number )
    If gub_core_MMU2_page_number <> 255 Then s_core_next_reg( MMU_SLOT_2 , gub_core_MMU2_page_number )
    ' ...and put back whichever stage was in MMU 3, it may well be the one that called us
    s_core_next_reg( MMU_SLOT_PAGED_CODE , gub_core_MMU3_page_number )

    If lub_result = 0 And guw_shared_3 <> 8192 Then lub_result = 255
    Return lub_result

    ' the file name, as the system wants it: the characters followed by a 0, this is 64 bytes set aside inside the code...
    ' ...it has to be somewhere that is still mapped in during the call, and that is not in the top two slots
core_file_name:
    Asm
core_file_name_asm:
        defs 64, 0
    End Asm
    Return 0        ' never reached, it is only here because the compiler expects a Function to end with a Return
End Function


Function fub_core_file_save_page( ps_name As String , pub_page As UByte ) As UByte
    ' saves the 8KB page pub_page to the file ps_name on the SD card, replacing any file of that name
    ' returns 0 if it worked, otherwise an error number, see fub_core_file_transfer()
    Return fub_core_file_transfer( ps_name , pub_page , true )
End Function


Function fub_core_file_load_page( ps_name As String , pub_page As UByte ) As UByte
    ' loads the file ps_name from the SD card into the 8KB page pub_page
    ' returns 0 if it worked, otherwise an error number, see fub_core_file_transfer()
    Return fub_core_file_transfer( ps_name , pub_page , false )
End Function


Sub s_core_ram_fill( puw_address As UInteger , puw_byte_count As UInteger , pub_value As UByte )
    ' sets puw_byte_count bytes from puw_address onwards to pub_value, e.g. to clear a page that is in one of the slots
    ' N.B: the first byte is set, then LDIR copies each byte onto the next, which carries the value along
    If puw_byte_count = 0 Then Return
    Poke puw_address , pub_value
    If puw_byte_count = 1 Then Return
    guw_shared_1 = puw_address
    guw_shared_2 = puw_byte_count - 1
    Asm
        ld hl, (_guw_shared_1)
        ld d, h
        ld e, l
        inc de
        ld bc, (_guw_shared_2)
        ldir
    End Asm
End Sub


Sub s_core_copy_page( pub_from_page As UByte , pub_to_page As UByte )
    ' copies one whole 8KB page onto another, the first is brought into MMU 3 and the second into MMU 2 for the copy,
    ' and both slots are given back what they held, as s_core_swap_paged_code() and s_core_swap_paged_data() last left
    ' them... N.B: so it may be called from a stage, which is in MMU 3, as long as it is the core that does the copying
    s_core_next_reg( MMU_SLOT_PAGED_CODE , pub_from_page )
    s_core_next_reg( MMU_SLOT_2 , pub_to_page )
    guw_shared_1 = 8192
    Asm
        ld hl, A_MMU_SLOT_PAGED_CODE
        ld de, A_MMU_SLOT_PAGED_DATA_C
        ld bc, (_guw_shared_1)
        ldir
    End Asm
    If gub_core_MMU2_page_number = 255 Then
        s_core_next_reg( MMU_SLOT_2 , 10 )      ' 255 = none of ours was ever put there, so it is the system's page 10
    Else
        s_core_next_reg( MMU_SLOT_2 , gub_core_MMU2_page_number )
    End If
    s_core_next_reg( MMU_SLOT_PAGED_CODE , gub_core_MMU3_page_number )
End Sub


Function fub_core_save_transfer( pub_slot As UByte , pub_page As UByte , pub_write As UByte ) As UByte
    ' one page of the save file, to it or from it, pub_slot is which of the file's pages it is, 0 if it worked
    Dim lub_result As UByte
    gub_core_file_slot = pub_slot
    If pub_write Then
        lub_result = fub_core_file_save_page( S_SAVE_FILE , pub_page )
    Else
        lub_result = fub_core_file_load_page( S_SAVE_FILE , pub_page )
    End If
    gub_core_file_slot = 255
    Return lub_result
End Function


Function fub_core_save_all() As UByte
    ' saves the example's data to the SD card, four pages in the one file, S_SAVE_FILE, in this order:
    '   0   the core data page, 52, the one that is always in MMU 6 and never paged out
    '   1   the left stage's page of paged data, 96
    '   2   the centre stage's, 97
    '   3   the right stage's, 98
    ' the core data page is saved whole, the core's own workings and the heap with it, as a page is the unit the file
    ' routines work in... a load only brings back the program's own part of it, see fub_core_load_all()
    ' N.B: a page is saved from wherever it is, it need not be in a slot, the file routine brings it into MMU 3 itself
    ' N.B: the file is written from its first page to its last in one go, and then closed, see fub_core_file_transfer()
    ' returns 0 if all four were saved, otherwise which page of the file failed, 1 to 4, with the system's error number
    ' in gub_core_file_error, see fub_core_file_transfer() for what the numbers mean
    Dim lub_failed As UByte = 0

    ' the marks that tell a load this file is one of ours, and laid out as this version lays it out
    gub_demo_mark_1  = 80                   ' "P"
    gub_demo_mark_2  = 68                   ' "D"
    gub_demo_version = UB_SAVE_VERSION

    gub_core_file_error = fub_core_save_transfer( 0 , UB_PAGE_CORE_DATA , true )
    If gub_core_file_error <> 0 Then lub_failed = 1
    If lub_failed = 0 Then
        gub_core_file_error = fub_core_save_transfer( 1 , UB_PAGE_DATA_LEFT , true )
        If gub_core_file_error <> 0 Then lub_failed = 2
    End If
    If lub_failed = 0 Then
        gub_core_file_error = fub_core_save_transfer( 2 , UB_PAGE_DATA_CENTRE , true )
        If gub_core_file_error <> 0 Then lub_failed = 3
    End If
    If lub_failed = 0 Then
        gub_core_file_error = fub_core_save_transfer( 3 , UB_PAGE_DATA_RIGHT , true )
        If gub_core_file_error <> 0 Then lub_failed = 4
    End If
    ' the file is finished with, and is closed whether all went well or not (the page given is not used)
    gub_shared_1 = fub_core_save_transfer( 254 , UB_PAGE_SPARE_CORE , true )
    Return lub_failed
End Function


Function fub_core_load_all() As UByte
    ' brings back what fub_core_save_all() saved, all or nothing: the file's four pages are first loaded into four
    ' spare pages, the marks at the start of its core data are looked at, and only if all four loaded and the marks
    ' are ours is anything changed...
    '   the core data page: only the program's own part of it, A_DEMO onwards, is copied from its spare page, the 512
    '                       bytes below that are the core's own workings, which page is in each slot and so on, and
    '                       the heap above it holds the strings of what is running now, both belong to now, not then
    '   the three pages of paged data: copied whole from their spare pages
    ' returns 0 if it worked, otherwise:
    '   1 to 4  that page of the file could not be loaded, with the system's error number in gub_core_file_error,
    '           5 means there is no such file, i.e. nothing has been saved yet
    '   5       the file loaded, but it is not one of ours, or not of this version
    gub_core_file_error = fub_core_save_transfer( 0 , UB_PAGE_SPARE_CORE , false )
    If gub_core_file_error <> 0 Then Return 1
    gub_core_file_error = fub_core_save_transfer( 1 , UB_PAGE_SPARE_LEFT , false )
    If gub_core_file_error <> 0 Then Return 2
    gub_core_file_error = fub_core_save_transfer( 2 , UB_PAGE_SPARE_CENTRE , false )
    If gub_core_file_error <> 0 Then Return 3
    gub_core_file_error = fub_core_save_transfer( 3 , UB_PAGE_SPARE_RIGHT , false )
    If gub_core_file_error <> 0 Then Return 4

    ' the spare core data page is brought into MMU 3, where the stage is, for the rest of this, and the stage put back
    ' at the end, N.B: so nothing here may return to the stage until it has been
    s_core_next_reg( MMU_SLOT_PAGED_CODE , UB_PAGE_SPARE_CORE )
    gub_shared_1 = 0
    If Peek( A_MMU_SLOT_PAGED_CODE + ( A_DEMO - A_MMU_SLOT_CORE_DATA ) ) = 80 Then
        If Peek( A_MMU_SLOT_PAGED_CODE + ( A_DEMO - A_MMU_SLOT_CORE_DATA ) + 1 ) = 68 Then
            If Peek( A_MMU_SLOT_PAGED_CODE + ( A_DEMO - A_MMU_SLOT_CORE_DATA ) + 2 ) = UB_SAVE_VERSION Then gub_shared_1 = 1
        End If
    End If
    If gub_shared_1 Then
        ' the program's part of the core data page
        Asm
            ld hl, A_MMU_SLOT_PAGED_CODE + ( A_DEMO - A_MMU_SLOT_CORE_DATA )
            ld de, A_DEMO
            ld bc, UW_DEMO_SIZE
            ldir
        End Asm
    End If
    s_core_next_reg( MMU_SLOT_PAGED_CODE , gub_core_MMU3_page_number )
    If gub_shared_1 = 0 Then Return 5

    s_core_copy_page( UB_PAGE_SPARE_LEFT , UB_PAGE_DATA_LEFT )
    s_core_copy_page( UB_PAGE_SPARE_CENTRE , UB_PAGE_DATA_CENTRE )
    s_core_copy_page( UB_PAGE_SPARE_RIGHT , UB_PAGE_DATA_RIGHT )
    Return 0
End Function


'##################################################################################################################################
' ---MAIN PROGRAM ---

Sub s_core_main_vars()
    gub_core_end              = false     ' the core data page is not cleared for us, so set this explicitly
    guw_key_code              = 0
    gub_key_char              = 0
    gub_key_modifiers         = 0
    ' N.B: a String variable is really a two byte pointer into the heap, and assigning to it frees whatever it pointed at before...
    ' ...so the pointer must start out as 0 (meaning "no string yet"), otherwise the first assignment would free a random address
    Poke UInteger A_KEY + 4 , 0             ' gs_key_astext
    gub_core_MMU3_page_number = 0
    gul_core_MMU3_cache_hits  = 0
    gul_core_MMU3_page_swaps  = 0
    ' the three paged data slots, 255 is the number the Next uses for "the ROM", and it is not one of our pages...
    ' ...so it stands for "nothing of ours is in this slot yet", the slots still hold whatever the system left there
    gub_core_MMU0_page_number = 255
    gul_core_MMU0_cache_hits  = 0
    gul_core_MMU0_page_swaps  = 0
    gub_core_MMU1_page_number = 255
    gul_core_MMU1_cache_hits  = 0
    gul_core_MMU1_page_swaps  = 0
    gub_core_MMU2_page_number = 255
    gul_core_MMU2_cache_hits  = 0
    gul_core_MMU2_page_swaps  = 0
    gub_core_file_error       = 0
    gub_core_file_slot        = 255         ' a file is one page and no more unless a caller says otherwise

    s_core_ram_copy( 0, 0, 0 )           ' to stop the compiler optimizer from dropping this routine...
    s_core_clear_screen()                ' start with a blank screen, and this call also stops the optimizer from dropping the routine...
    If gub_core_end Then gub_shared_1 = fub_core_countdown( 0 , 0 , 0 , 0 )     ' never actually runs, it is only here to stop the optimizer from dropping the routine...
    If gub_core_end Then s_core_ram_fill( 0 , 0 , 0 )                           ' ditto
    If gub_core_end Then gub_shared_1 = fub_core_save_all()                     ' ditto
    If gub_core_end Then gub_shared_1 = fub_core_load_all()                     ' ditto
    If gub_core_end Then s_core_clear_row( 0 , 0 , 0 )                          ' ditto
    If gub_core_end Then s_core_swap_paged_data( 255 , 0 )     ' ditto
    If gub_core_end Then gub_shared_1 = fub_core_file_save_page( "" , 0 )      ' ditto
    If gub_core_end Then gub_shared_1 = fub_core_file_load_page( "" , 0 )      ' ditto
    If gub_core_end Then s_core_call_library( 0 , 0 )                       ' ditto
End Sub


Sub s_core_main()
    ' the core's main loop: it picks the next stage, pages its code into MMU 3, and calls it at $6000, and when the
    ' stage has finished it returns here, and the core picks the one after... a stage never calls another stage
    Dim lub_page    As UByte        ' the page of code the stage is in
    Dim lub_next    As UByte        ' the stage to run after it

    s_core_main_vars()
    gub_core_stage      = UB_STAGE_INIT
    gub_core_next_stage = UB_STAGE_INIT
    gub_core_monitor    = true
    Do
        ' N.B: gub_core_stage holds a UB_STAGE_ number, which is not the same thing as a UB_PAGED_CODE_ page number
        If gub_core_stage = UB_STAGE_INIT Then
            lub_page = UB_PAGED_CODE_STAGE_INIT
            lub_next = UB_STAGE_LEFT
        ElseIf gub_core_stage = UB_STAGE_LEFT Then
            lub_page = UB_PAGED_CODE_STAGE_LEFT
            lub_next = UB_STAGE_CENTRE
        ElseIf gub_core_stage = UB_STAGE_CENTRE Then
            lub_page = UB_PAGED_CODE_STAGE_CENTRE
            lub_next = UB_STAGE_RIGHT
        ElseIf gub_core_stage = UB_STAGE_RIGHT Then
            lub_page = UB_PAGED_CODE_STAGE_RIGHT
            lub_next = UB_STAGE_LEFT
        Else
            s_core_crash( UB_CRASH_BAD_CORE_STAGE , "no such stage: " + fs_core_number( gub_core_stage ) )
        End If

        s_core_swap_paged_code( lub_page )
        ' the memory monitor is brought up to date here, each time a stage has handed back to the core, and not while
        ' a stage is running, it shows how things stand as the next stage starts, with its page now in MMU 3
        If gub_core_monitor Then s_core_display_monitor()
        Asm
            call A_MMU_SLOT_PAGED_CODE
        End Asm
        ' the start up stage is followed by a second's pause, so the eye can see its results before the next begins,
        ' the other stages wait by calling back into the core's fub_core_countdown()
        If gub_core_stage = UB_STAGE_INIT Then s_core_pause()
        ' a stage may ask for a stage other than the next in the round, by pressing its letter, see s_data_run()
        If gub_core_next_stage <> UB_STAGE_INIT Then lub_next = gub_core_next_stage
        gub_core_next_stage = UB_STAGE_INIT
        gub_core_stage = lub_next
    Loop Until gub_core_end
    s_core_return_to_zxos()
End Sub
