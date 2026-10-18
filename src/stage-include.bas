' shims for core API routines...
'
' how these work:
'   a stage calls one of these exactly as if it were the real routine, so the parameters and the return address are on the stack...
'   ...the shim then jumps (not calls) to the routine's fixed entry in the core jump table (see constants.bas)...
'   ...the real core routine therefore sees the stack exactly as if the stage had called it directly...
'   ...and when it finishes it removes the parameters and returns straight back to the stage.
'
' N.B: for any Sub that takes parameters the compiler starts it with "push ix : ld ix, 0 : add ix, sp"...
' ...so those shims must "pop ix" first to undo that, the shims with no parameters have nothing to undo.
' N.B: the shims that take a String work because the stages share the core's heap (see the heap notes in build.ps1)...
' ...the stage builds the string in the heap, and the core routine frees it from the same heap when it has finished with it.

Sub s_core_next_reg( pub_reg As UByte , pub_value As UByte )
    Asm
        pop ix
        jp A_JUMP_NEXT_REG
    End Asm
End Sub


Sub s_core_crash( pub_error_code As UByte , ps_error_text As String )
    Asm
        pop ix
        jp A_JUMP_CRASH
    End Asm
End Sub


Sub s_core_ram_copy( puw_src_address As UInteger , puw_dst_address As UInteger , puw_byte_count As UInteger )
    Asm
        pop ix
        jp A_JUMP_RAM_COPY
    End Asm
End Sub


Sub s_core_call_library( pub_page As UByte , pub_function As UByte )
    Asm
        pop ix
        jp A_JUMP_CALL_LIBRARY
    End Asm
End Sub


Sub s_core_clear_screen()
    Asm
        jp A_JUMP_CLEAR_SCREEN
    End Asm
End Sub


Sub s_core_print_char_at( pub_x As UByte , pub_y As UByte , pub_char As UByte , pub_colour As UByte )
    Asm
        pop ix
        jp A_JUMP_PRINT_CHAR_AT
    End Asm
End Sub


Sub s_core_print_string_at( pub_x As UByte , pub_y As UByte , ps_text As String , pub_colour As UByte )
    Asm
        pop ix
        jp A_JUMP_PRINT_STRING_AT
    End Asm
End Sub


Sub s_core_get_key()
    Asm
        jp A_JUMP_GET_KEY
    End Asm
End Sub


Function fub_core_countdown( pub_x As UByte , pub_y As UByte , pub_stay_key As UByte , pub_flip_key As UByte ) As UByte
    Asm
        pop ix
        jp A_JUMP_COUNTDOWN
    End Asm
    Return 0        ' never reached, it is only here because the compiler expects a Function to end with a Return
End Function


' N.B: a Function works through a shim in just the same way as a Sub, the core routine hands its result straight back to the stage...
' ...here the result is a string, which the core builds in the shared heap, and the stage frees once it has used it
Function fs_core_number( pul_value As ULong ) As String
    Asm
        pop ix
        jp A_JUMP_NUMBER
    End Asm
    Return ""       ' never reached, it is only here because the compiler expects a Function to end with a Return
End Function


Function fub_core_scan_key() As UByte
    Asm
        jp A_JUMP_SCAN_KEY
    End Asm
    Return 0        ' never reached, it is only here because the compiler expects a Function to end with a Return
End Function


Function fs_core_key_name( pub_code As UByte , pub_modifiers As UByte ) As String
    Asm
        pop ix
        jp A_JUMP_KEY_NAME
    End Asm
    Return ""       ' never reached, it is only here because the compiler expects a Function to end with a Return
End Function


Sub s_core_swap_paged_data( pub_slot As UByte , pub_page_number As UByte )
    Asm
        pop ix
        jp A_JUMP_SWAP_PAGED_DATA
    End Asm
End Sub


Function fub_core_file_save_page( ps_name As String , pub_page As UByte ) As UByte
    Asm
        pop ix
        jp A_JUMP_FILE_SAVE_PAGE
    End Asm
    Return 0        ' never reached, it is only here because the compiler expects a Function to end with a Return
End Function


Function fub_core_file_load_page( ps_name As String , pub_page As UByte ) As UByte
    Asm
        pop ix
        jp A_JUMP_FILE_LOAD_PAGE
    End Asm
    Return 0        ' never reached, it is only here because the compiler expects a Function to end with a Return
End Function


' N.B: a stage must use this in place of Chr$, see the notes in constants.bas for what else a stage cannot use
Function fs_core_char( pub_code As UByte ) As String
    Asm
        pop ix
        jp A_JUMP_CHAR
    End Asm
    Return ""       ' never reached, it is only here because the compiler expects a Function to end with a Return
End Function


Sub s_core_ram_fill( puw_address As UInteger , puw_byte_count As UInteger , pub_value As UByte )
    Asm
        pop ix
        jp A_JUMP_RAM_FILL
    End Asm
End Sub


Function fub_core_save_all() As UByte
    Asm
        jp A_JUMP_SAVE_ALL
    End Asm
    Return 0        ' never reached, it is only here because the compiler expects a Function to end with a Return
End Function


Function fub_core_load_all() As UByte
    Asm
        jp A_JUMP_LOAD_ALL
    End Asm
    Return 0        ' never reached, it is only here because the compiler expects a Function to end with a Return
End Function


Sub s_core_clear_row( pub_row As UByte , pub_from As UByte , pub_colour As UByte )
    Asm
        pop ix
        jp A_JUMP_CLEAR_ROW
    End Asm
End Sub
