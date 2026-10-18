#PRAGMA push(case_insensitive)
#PRAGMA case_insensitive = True
#define STANDALONE  ' remove ROM initialization and SysVars...

' the loader starts here, at $C000 (the --org given to the compiler in build.ps1, and the start address in sjasmplus.cfg)...
' ...the stack is already set up for us: the nex file header carries a stack address of $DFFE, near the top of MMU 6,
' which comes from the SAVENEX OPEN line in sjasmplus.cfg, and whatever loads the nex file sets the stack pointer from it
Asm
    di                  ; interrupts off straight away, and they stay off until s_load_set_interrupts() has put our own handler in place
End Asm

    ' N.B: these two must come first, and in this order, every delay in the loader is timed by the frame interrupt...
    ' ...the interrupt handler and its table live at the top of the second core code page, so that page must be mapped in
    ' before they can be built, and they must be built before anything waits for an interrupt
    s_load_map_pages()
    s_load_set_interrupts()
    s_load_set_hardware()
    s_load_set_palette()
    s_load_clear_screen()
    s_load_colour_test()

    ' hold the test pattern and the colour patch on screen for three seconds, the core clears the screen as soon as it starts
    s_load_hold_screen()

Asm
    jp $8000            ; jump to core.bas, its first act is to map its own data page into MMU 6, which is where we are running now
End Asm


Sub s_load_set_hardware()

    s_load_sleep()
    ' set the tilemap clip window to the whole screen, the same values that the hardware has after a reset...
    ' ...register $1B takes four writes in turn: x1, x2, y1, y2, and writing bit 3 of $1C first makes sure we start at x1...
    ' ...the x values are doubled by the hardware, so 159 means pixel 319, the right hand edge, in both 40 and 80 column modes
    Asm
        nextreg $1C, %00001000                          ; Clip Window Control Register, restart the tilemap clip writes at x1
        nextreg $1B, 0                                  ; x1 = 0
        nextreg $1B, 159                                ; x2 = 159
        nextreg $1B, 0                                  ; y1 = 0
        nextreg $1B, 255                                ; y2 = 255
    End Asm

    s_load_sleep()
    Asm
        nextreg $68, %10100000                          ; ULA Control Register
    End Asm
    ' bit 7     = Disable ULA output (0 on reset)
    ' bit 6-5   = Color blending control for layering modes 6 & 7 (3.01.01)
    '   00      = ULA as blend colour
    '   01      = No blending
    '   10      = ULA/Tilemap mix result as blend colour
    '   11      = Tilemap as blend colour
    ' bit 4     = Cancel entries in 8x5 matrix for extended keys (3.01.04)
    ' bit 3     = Enable ULAplus (0 on reset)
    ' bit 2     = Enable ULA half pixel scroll (0 on reset) may change
    ' bit 1     = reserved (must be 0)
    ' bit 0     = Enable stencil mode (0 on reset)
    '   When ULA and Layer 3 are enabled, if either are transparent, the result
    '   is transparent, otherwise the result is the logical AND of both colours.

    s_load_sleep()
    ' N.B: bit 5 must be 0 here, core.bas writes two bytes per cell (character, then colour attribute)
    Asm
        nextreg $6B, %11001001                          ; Layer 3 Tilemap Control Register
    End Asm
    ' bit 7     = 1 to enable the tilemap
    ' bit 6     = 0 for 40x32, 1 for 80x32
    ' bit 5     = 1 to eliminate the attribute entry in the tilemap
    ' bit 4     = layer 3 palette select
    ' bit 3     = text mode
    ' bit 2     = reserved, set to 0
    ' bit 1     = 1 to activate 512 tile mode
    ' bit 0     = 1 to force tilemap on top of ULA

    s_load_sleep()
    ' N.B: this register is only used when bit 5 of $6B is 1, it has no effect while every cell carries its own attribute byte
    Asm
        nextreg $6C, %01000000                          ; Default Tilemap Attribute Register
    End Asm
    ' bits 7-4  = Palette Offset
    ' bit 3     = X mirror
    ' bit 2     = Y mirror
    ' bit 1     = Rotate
    ' bit 0     = ULA over tilemap (or bit 8 of the tile number if 512 tile mode is enabled)

    s_load_sleep()
    ' N.B: these two registers are documented in 16KB bank terms, in our 8KB page terms: bank 5 = pages 10 and 11, bank 7 = page 14...
    ' ...(only the first half of bank 7 can hold tiles, so page 15 is not available for this)
    ' ...the display hardware reads these pages directly, they do not have to be mapped into an MMU slot to be shown...
    ' ...so the font sits in the first 2KB of page 10, which we never map in, and page 11 holds the screen cells and the stack...
    ' ...page 14 is not used at all, it belongs to NextZXOS
    ' N.B: in Boriel "Or" is the logical (true/false) operator, to combine bits it has to be "bOr"
    ' page 11 is the second half of bank 5, so it starts 8KB into the bank, i.e. at offset $2000, and the register holds the high byte, $20
    Asm
        nextreg $6E, %00100000                          ; Tilemap Base Address Register = page 11 (bank 5 + 8KB), i.e. the screen cells
    End Asm
    ' bit 7     = 1 to select bank 7, 0 to select bank 5
    ' bit 6     = reserved, must be 0
    ' bits 5-0  = MSB of address of the tilemap in bank

    s_load_sleep()
    ' page 10 is the first half of bank 5, and the font is at its very start, so the offset is 0
    Asm
        nextreg $6F, %00000000                          ; Tile Definitions Base Address Register = page 10 (bank 5), at offset 0, i.e. the font
    End Asm
    ' bit 7     = 1 to select bank 7, 0 to select bank 5
    ' bit 6     = reserved, must be 0
    ' bits 5-0  = MSB of address of the tile definitions in bank

    s_load_sleep()
    ' N.B: bits 4-2 were %111 (the U+L-5 blend mode), we want the plain S L U ordering
    Asm
        nextreg $15, %00000000                          ; Sprite and Layers System Register
    End Asm
    ' bit 7     = LoRes mode (0 on reset)
    ' bit 6     = Sprite priority (0 on reset)
    '   0       = sprite 127 on top
    '   1       = sprite 0 on top
    ' bit 5     = Enable sprite clipping in over border mode (0 on reset)
    ' bits 4-2  = set layers priorities (000 on reset)
    '   000 - S L U
    '   001 - L S U
    '   010 - S U L
    '   011 - L U S
    '   100 - U S L
    '   101 - U L S
    '   110 - S (U+L) ULA and Layer 2 combined, colours clamped to 7
    '   111 - S (U+L-5) ULA and Layer 2 combined, colours clamped to [0,7]
    ' bit 1     = Enable Sprites Over border (0 on reset)
    ' bit 0     = Enable Sprites (0 on reset)

    s_load_sleep()
    Out $E3,   $00                                  ' divMMC control port, clear the two manual mapping bits so divMMC memory is paged out
    ' N.B: this does not switch off divMMC automapping, that is a separate mechanism which this port does not control

    s_load_sleep()
    Asm
        nextreg $62, $00                                ; Copper Control Register, stop the copper (and zero the top bits of its address)
    End Asm

    s_load_sleep()
    Asm
        nextreg $0B, $00                                ; Joystick I/O Mode Register, switch joystick i/o mode off (N.B: nothing to do with the DMA)
    End Asm

    s_load_sleep()
    ' Peripheral 1 Settings Register
    ' bits 7-6  = joystick 1 mode (MSB)
    ' bits 5-4  = joystick 2 mode (MSB)
    ' bit 3     = joystick 1 mode (LSB)
    ' bit 2     = 50/60 Hz mode (0 = 50Hz, 1 = 60Hz)
    ' bit 1     = joystick 2 mode (LSB)
    ' bit 0     = enable scandoubler (0 = disabled for CRT, 1 = enabled for VGA)
    ' the three joystick mode bits are spread out, for joystick 1 they are bits 7, 6 and 3, and for joystick 2 bits 5, 4 and 1...
    '   000 = Sinclair 2 (keys 6 7 8 9 0)    001 = Kempston 2    010 = Kempston 1    011 = Megadrive 1
    '   100 = Cursor (keys 5 6 7 8 0)        101 = Megadrive 2   110 = Sinclair 1 (keys 1 2 3 4 5)
    ' we set joystick 1 to Cursor, i.e. bit 7 on, so that it arrives as the cursor keys, which fub_core_scan_key() in core.bas understands...
    ' ...N.B: this is also what makes the PC's arrow keys work in ZEsarUX, it treats them as joystick 1 and obeys this mode,
    ' with any of the other modes the arrow keys go somewhere that our keyboard routine does not look...
    ' ...(on a real Next the arrow keys do not depend on this, they are read from nextreg $B0)
    ' joystick 2 is left as mode 000, and 50Hz is selected, the countdown in core.bas counts 50 frames to the second...
    ' ...but bit 0 is kept exactly as we found it, switching the scandoubler off can lose the picture on a real Next using VGA
    Asm
        ld bc, $243B                                    ; nextreg can only write, so the register is read through the ports
        ld a, $05
        out (c), a
        inc b                                           ; $253B
        in a, (c)
        and %00000001                                   ; bit 0, the scandoubler, kept as we found it...
        or %10000000                                    ; ...and joystick 1 to Cursor
        nextreg $05, a                                  ; Peripheral 1 Settings Register
    End Asm

    s_load_sleep()
    ' Peripheral 2 Settings Register
    ' bit 7     = enable F8 cpu speed hotkey
    ' bit 6     = divert BEEP only to internal speaker
    ' bit 5     = enable F3 50/60 Hz hotkey
    ' bit 4     = enable divMMC NMI by the DRIVE button
    ' bit 3     = enable multiface NMI by the M1 button
    ' bit 2     = PS/2 mode (config mode only)
    ' bits 1-0  = audio chip mode
    ' we clear bits 7, 4 and 3 and leave the rest as we found them...
    ' ...bits 4 and 3: those two buttons cause a non maskable interrupt, which makes the Z80 jump to $0066 whatever it
    ' is doing, and in our memory map $0066 is inside the first paged data slot, so it would be running data as code
    ' ...bit 7: the F8 key would change the CPU speed, and this program runs at 28MHz at all times, see the end of this
    ' routine (it also takes F5 and F6, the expansion bus keys, with it)
    Asm
        ld bc, $243B                                    ; nextreg can only write, so the register is read through the ports
        ld a, $06
        out (c), a
        inc b                                           ; $253B
        in a, (c)
        and %01100111
        nextreg $06, a                                  ; Peripheral 2 Settings Register
    End Asm

    s_load_sleep()
    ' Video Timing Register ($11), left alone...
    ' ...it selects the display timing (VGA settings 0 to 6, or HDMI) and can only be written in config mode...
    ' ...it has nothing to do with the CPU or ULA clock speed, the CPU speed is nextreg $07 (see the end of this routine)...
    ' ...writing it here crashed the speccy inside zesarux, so it stays commented out
    'nextreg $11, %00000010

    s_load_sleep()
    ' Peripheral 3 Settings Register (N.B: nothing to do with interrupts)
    ' bit 7     = 128K banking unlock
    ' bit 6     = disable RAM and port contention
    ' bit 5     = PSG stereo mode (0 = ABC, 1 = ACB)
    ' bit 4     = enable internal speaker
    ' bit 3     = enable DACs
    ' bit 2     = enable read of port $FF (Timex)
    ' bit 1     = enable multiple PSGs (turbosound)
    ' bit 0     = enable issue 2 keyboard
    ' writing 0 switches all of these off, so the internal speaker is silent and contention is on
    Asm
        nextreg $08, 0
    End Asm

    s_load_sleep()
    Asm
        nextreg $22, 0                                  ; Line Interrupt Control Register, disable line interrupts...
    End Asm
    ' ...N.B: bit 2 is also 0, which leaves the normal 50Hz frame interrupt enabled, the countdown in core.bas relies on it

    's_load_sleep()
    'nextreg $8F, 0                                  ' unlock and map ram

    's_load_sleep()
    'nextreg $8E, 3                                  ' allow writing to ram in slots 0 and 1

    's_load_sleep()
    'nextreg $12, 0                                  ' N.B: $12 chooses which RAM Layer 2 uses, it does not disable it, to disable Layer 2 clear bit 7 of $69

    s_load_sleep()
    ' reset the tilemap scroll, both ways (N.B: the y scroll is $31, not $6D which is not a documented register)
    Asm
        nextreg $2F, 0                                  ; Tilemap Horizontal Scroll MSB
        nextreg $30, 0                                  ; Tilemap Horizontal Scroll LSB
        nextreg $31, 0                                  ; Tilemap Vertical Scroll
    End Asm

    's_load_sleep()
    'nextreg $4B, 1                                  ' N.B: $4B is the sprite transparency index, the background (fallback) colour is $4A

    s_load_sleep()
    ' CPU Speed Register: 28 MHz, eight times the speed of an original Spectrum, and it stays so: the F8 key that
    ' would change it is switched off above, and the memory monitor shows the speed the CPU is really running at...
    ' ...N.B: nothing of ours is timed by counting instructions, every wait counts 50Hz frame interrupts, which arrive
    ' at the same rate whatever the CPU speed, so nothing runs short at 28MHz
    ' ...N.B: a real Next runs at 3.5MHz while the expansion bus is switched on, which this program never does, and
    ' pages 224 to 255 (above 1.75MB) are too slow for it on the older boards, so they are not used, see constants.bas
    Asm
        nextreg $07, %00000011                          ; 11 = 28MHz
    End Asm

    s_load_sleep()
End Sub


Sub s_load_set_palette()
    ' select tilemap palette 0 and start at index 0
    Asm
        nextreg $43, %00110000                          ; Palette Control Register (it covers all the layers, not just the ULA)
    End Asm
    ' bit 7: '1' to disable palette write auto-increment.
    ' bits 6-4: Select palette for reading or writing:
    '    000 = ULA first palette
    '    100 = ULA second palette
    '    001 = Layer 2 first palette
    '    101 = Layer 2 second palette
    '    010 = Sprites first palette 
    '    110 = Sprites second palette
    '    011 = Tilemap first palette
    '    111 = Tilemap second palette
    ' bit 3: Select Sprites palette (0 = first palette, 1 = second palette)
    ' bit 2: Select Layer 2 palette (0 = first palette, 1 = second palette)
    ' bit 1: Select ULA palette (0 = first palette, 1 = second palette)
    ' bit 0: Enable Enhanced ULA mode if 1 (0 after a reset)

    Asm
        nextreg $40, 0                                  ; Palette Index Select, start writing at index 0
    End Asm

    ' 8-bit Palette Data ($41) takes ONE write per entry (RRRGGGBB) and then auto-increments the index,
    ' so each entry is one nextreg $41...
    ' (it is the 9-bit register $44 that needs two writes per entry)

    ' how the colours work in text mode:
    '   each screen cell has an attribute byte, its top 7 bits choose a PAIR of palette entries...
    '   ...pair N is palette entries 2N (the paper, used for the 0 pixels) and 2N + 1 (the ink, used for the 1 pixels)...
    '   ...so the attribute byte to put in a cell is 2 * N, e.g. pair 7 (white) is attribute 14, see the UB_ colours in constants.bas
    ' every colour value is in RRRGGGBB format, and every paper here is black
    ' the first eight pairs are the normal colours at about 70% intensity (%101), the second eight are the bright ones at 100% (%111)

    Asm
        ; pair 0: black ink on black paper (attribute byte 0)
        nextreg $41, $00 ; index 0 (paper)
        nextreg $41, $00 ; index 1 (ink)

        ; pair 1: blue ink on black paper (attribute byte 2)
        nextreg $41, $00 ; index 2 (paper)
        nextreg $41, $02 ; index 3 (ink)   %000 000 10

        ; pair 2: red ink on black paper (attribute byte 4)
        nextreg $41, $00 ; index 4 (paper)
        nextreg $41, $A0 ; index 5 (ink)   %101 000 00

        ; pair 3: magenta ink on black paper (attribute byte 6)
        nextreg $41, $00 ; index 6 (paper)
        nextreg $41, $A2 ; index 7 (ink)   %101 000 10

        ; pair 4: green ink on black paper (attribute byte 8)
        nextreg $41, $00 ; index 8 (paper)
        nextreg $41, $14 ; index 9 (ink)   %000 101 00

        ; pair 5: cyan ink on black paper (attribute byte 10)
        nextreg $41, $00 ; index 10 (paper)
        nextreg $41, $16 ; index 11 (ink)   %000 101 10

        ; pair 6: yellow ink on black paper (attribute byte 12)
        nextreg $41, $00 ; index 12 (paper)
        nextreg $41, $B4 ; index 13 (ink)   %101 101 00

        ; pair 7: white ink on black paper (attribute byte 14)
        nextreg $41, $00 ; index 14 (paper)
        nextreg $41, $B6 ; index 15 (ink)   %101 101 10

        ; pair 8: dark grey ink on black paper (attribute byte 16)
        nextreg $41, $00 ; index 16 (paper)
        nextreg $41, $49 ; index 17 (ink)   %010 010 01

        ; pair 9: bright blue ink on black paper (attribute byte 18)
        nextreg $41, $00 ; index 18 (paper)
        nextreg $41, $03 ; index 19 (ink)   %000 000 11

        ; pair 10: bright red ink on black paper (attribute byte 20)
        nextreg $41, $00 ; index 20 (paper)
        nextreg $41, $E0 ; index 21 (ink)   %111 000 00

        ; pair 11: bright magenta ink on black paper (attribute byte 22)
        nextreg $41, $00 ; index 22 (paper)
        nextreg $41, $E3 ; index 23 (ink)   %111 000 11

        ; pair 12: bright green ink on black paper (attribute byte 24)
        nextreg $41, $00 ; index 24 (paper)
        nextreg $41, $1C ; index 25 (ink)   %000 111 00

        ; pair 13: bright cyan ink on black paper (attribute byte 26)
        nextreg $41, $00 ; index 26 (paper)
        nextreg $41, $1F ; index 27 (ink)   %000 111 11

        ; pair 14: bright yellow ink on black paper (attribute byte 28)
        nextreg $41, $00 ; index 28 (paper)
        nextreg $41, $FC ; index 29 (ink)   %111 111 00

        ; pair 15: bright white ink on black paper (attribute byte 30)
        nextreg $41, $00 ; index 30 (paper)
        nextreg $41, $FF ; index 31 (ink)   %111 111 11
    End Asm

    ' Global Transparency Colour Register...
    ' ...in text mode any pixel whose final colour equals this value is treated as transparent, and it is $E3 after a reset...
    ' ...$E3 is exactly our bright magenta, so we move the transparent colour to a value that the palette above does not use
    Asm
        nextreg $14, $E7
    End Asm
End Sub


Sub s_load_map_pages()
    ' N.B: there must be no s_load_sleep() in here, nothing may wait for an interrupt until s_load_set_interrupts() has run
    ' the slots that are not mentioned are deliberately left alone...
    ' ...MMU 0, 1 and 2 are the paged data slots, the demo does not use them, so they keep whatever the system put there
    ' ...MMU 3 is the paged code slot, the core maps each stage into it as needed
    ' ...MMU 6 is where this loader is running, so the core maps its own data page (52) there as its very first act
    Asm
        nextreg $54, 50                                 ; MMU 4 = first page of core.bin
        nextreg $55, 51                                 ; MMU 5 = second page of core.bin, the interrupt handler will go at the top of this
        nextreg $57, 11                                 ; MMU 7 = page 11, the screen cells (from $E000) and above them the core's stack
    End Asm
End Sub


Sub s_load_set_interrupts()
    ' switches the Z80 to interrupt mode 2, with our own handler at the top of the second core code page...
    ' ...in mode 2 the Z80 jumps to the address it reads from a table at ( I register * 256 ) + the byte on the data bus...
    ' ...that byte is not predictable on a Spectrum, so the table is 257 copies of $BD, and the handler sits at $BDBD,
    ' then whichever entry gets read the answer is the same
    ' N.B: these addresses are A_IM2_TABLE and A_IM2_HANDLER in constants.bas, and build.ps1 checks that the core's code stops short of them
    ' N.B: the handler is a single "reti", it does not switch interrupts back on, every wait does its own ei / halt / di
    Asm
        ld hl, $BE00        ; the table, $BE00 to $BF00...
        ld de, $BE01
        ld bc, 256
        ld (hl), $BD
        ldir                ; ...257 bytes in all, every one of them $BD

        ld hl, $BDBD        ; the handler...
        ld (hl), $ED
        inc hl
        ld (hl), $4D        ; ...$ED $4D is "reti"

        ld a, $BE           ; the I register is the high byte of the table's address
        ld i, a
        im 2
    End Asm
End Sub


Sub s_load_clear_screen()
    Asm
        ; fill all 80 x 32 cells with a two byte pair, an ASCII code and an attribute
        ld hl, $E000
        ld (hl), 65     ; ASCII A
        inc hl
        ld (hl), 14     ; attribute white ink on black paper
        ld hl, $E000
        ld de, $E002
        ld bc, 5118
        ldir
    End Asm
    Out $FE, 0          ' border, black
End Sub


Sub s_load_colour_test()
    ' draws a colour test patch in the middle of the screen, on top of the test pattern, one patch for each of the 16 colour pairs...
    '   rows 13 and 14 = pairs 0 to 7,  the normal colours: black blue red magenta green cyan yellow white
    '   rows 16 and 17 = pairs 8 to 15, dark grey and then the bright colours in the same order
    ' each patch is 4 cells wide and 2 cells tall...
    ' ...its top row is four solid blocks (character 127), which shows the ink colour on its own...
    ' ...its bottom row is the pair number as a hex digit, 0 to F, four times, which shows how text looks in that colour
    ' N.B: all of the variables are declared in here on purpose, so that they live on the stack and not in front of the code
    Dim lub_pair , lub_x , lub_digit , lub_attribute    As UByte
    Dim luw_row , luw_column , luw_address              As UInteger

    For lub_pair = 0 To 15
        If lub_pair < 8 Then
            luw_row    = 13
            luw_column = 24 + 4 * lub_pair
        Else
            luw_row    = 16
            luw_column = 24 + 4 * ( lub_pair - 8 )
        End If

        If lub_pair < 10 Then
            lub_digit = 48 + lub_pair               ' 48 = "0"
        Else
            lub_digit = 55 + lub_pair               ' 65 = "A", so pair 10 gives "A"
        End If

        lub_attribute = lub_pair * 2                ' the attribute byte for a pair is twice the pair number

        ' each cell is two bytes (character, then attribute), and each row of 80 cells is 160 bytes
        luw_address = $E000 + 160 * luw_row + 2 * luw_column
        For lub_x = 0 To 3
            Poke luw_address       , 127
            Poke luw_address + 1   , lub_attribute
            Poke luw_address + 160 , lub_digit
            Poke luw_address + 161 , lub_attribute
            luw_address = luw_address + 2
        Next
    Next
End Sub


Sub s_load_hold_screen()
    ' N.B: the loop counter is declared in here on purpose, a variable inside a Sub lives on the stack...
    ' ...a variable declared outside of any Sub is placed in front of the code, at $C000, where the Z80 starts running
    '
    ' holds for exactly three seconds, timed by the frame interrupt, which arrives 50 times a second whatever the CPU speed...
    ' ...each pass of the loop waits for one interrupt, so 150 passes = 3 seconds, change the 150 to change the hold time (255 at most)...
    Dim i As UByte
    For i = 1 To 150
        s_load_wait_frame()
    Next
End Sub


Sub s_load_wait_frame()
    ' waits for the next frame interrupt, which arrives 50 times a second whatever speed the CPU is set to
    ' N.B: this must only be used after s_load_set_interrupts() has run, before then an interrupt would go to whatever the system left in place
    Asm
        ei          ; allow the next frame interrupt
        halt        ; wait for it
        di          ; and keep interrupts off again, as the rest of the loader expects
    End Asm
End Sub


Sub s_load_sleep()
    ' a very short delay, in two halves, with the border red for the first half and magenta for the second...
    ' ...the flashing shows that this routine is being called, and nothing has to be remembered between calls...
    ' ...(the border colour cannot be read back from the hardware, port $FE is write only for the border)
    ' each half waits for 1 frame interrupt, so the whole delay is 2 frames = 0.04 seconds at any CPU speed...
    ' ...to make every delay in the loader shorter or longer just change the two loop limits below (they cannot go lower than 1)
    Dim i As UByte

    Out $FE, 2          ' border, red
    For i = 1 To 1
        s_load_wait_frame()
    Next

    Out $FE, 3          ' border, magenta
    For i = 1 To 1
        s_load_wait_frame()
    Next
End Sub
