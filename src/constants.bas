'##################################################################################################################################
' facts, in "ZX Next" speak:
'   a 16KB block is known as a "bank", but we won't be using banks as this is more of ZX Spectrum 128K interpreter
'   a  8KB block is known as a "page", for use via MMU, and we will be using 8KB pages in this worked example of a poor man's virtual memory system to swap pages in and out
'##################################################################################################################################
' N.B: in this demo I use the term "module" to refer to individual files of "*.bas" source code.
'   Boriel has since released v2 of his amazing and wonderful compiler which now includes the construct of true "Modules"
'   ...but I / we / you don't use those is this demo / worked example, so...
'   ...here, a "module" to me is simply a discreet file of source code with at least one majot routine inside it.
'##################################################################################################################################
' the Z80's 64KB is accessible as eight 8KB MMU slots, all eight can be paged, but is this demo, we will only be paging four of them
' and so the other four can be considered as "core" which simply mean always mapped in, and paged means swapped as needed:
'   MMU 0   $0000   paged data   data_m, and data_z which takes turns with it in this slot  } these three are lent back to the system
'   MMU 1   $2000   paged data   data_i, the second                                        } for the length of any file call, as ROM,
'   MMU 2   $4000   paged data   data_c, the third                                         } ROM, and the system variables page (10)
'   MMU 3   $6000   paged code   the stages
'   MMU 4   $8000   core  code   main loop, core subs and functions, the API jump table
'   MMU 5   $A000   core  code   second page, with the interrupt handler and its table at the very top
'   MMU 6   $C000   core  data   fixed variables growing up from $C000, the heap in the last 1024 bytes
'   MMU 7   $E000   core  screen 80 x 32 x word = 5120 bytes of tile map ($E000-$F3FF), then 3070 bytes of Z80 stack ($F400-$FFFD, grows downwards)
' why this order: everything that must never disappear (core code, core data, stack, screen) is above $8000...
' ...so the bottom of memory can be handed to NextZXOS whenever it is needed, e.g. a file handler call needs the ROM at $0000-$3FFF...
' ...and nothing of ours has to live at $0000, which is why interrupts use mode 2 (see A_IM2_TABLE below) and not mode 1
' N.B: MMU 0, 1 and 2 start out exactly as the system left them (ROM, ROM, and page 10), the first call to
' s_core_swap_paged_data() for a slot is what puts one of our own pages there, stage-init.bas does this as a test...
' ...once our data is in MMU 0 there is nothing sensible at $0066, where a non maskable interrupt jumps to,
' so the loader switches off the two buttons that can cause one (see nextreg $06 in load.bas)
'##################################################################################################################################
' what of Boriel BASIC this demo does not use, and why...
' N.B: none of what follows is a fault in Boriel BASIC, the compiler and its library is doing exactly what it was designed to do... it was
' written for a ZX Spectrum (or a Next) that keeps its ROM at the bottom of memory and its system variables at $5C00, as
' every ordinary program does, and so some of its routines call into that ROM, or keep a working value in one of those
' system variables, which is the right and sensible thing to do on such a machine...
' ...this demo is not such a machine: its own architecture takes all eight MMU slots, all 64KB, for its own code and
' data, see the table above, the ROM's slots ($0000-$3FFF, MMU 0 and 1) and the system variables' slot ($4000-$5FFF,
' MMU 2) are its three paged data slots, the system's pages are only there until s_core_swap_paged_data() first puts one
' of ours in their place... from then on a call into the ROM would run our data as if it were code, and a system
' variable is two bytes in the middle of our data, which a write to it would change
' ...so it is this demo's choice of memory layout that rules these out, they all work as documented in an ordinary
' program, but a program laid out like this demo has to leave them alone or bring its own:
'   CHR, CHR$       keeps a value at $5C4D (DEST) while it builds the string, use fs_core_char() instead
'   STR$            uses the ROM's floating point calculator (rst $28), use fs_core_number() instead
'   VAL             the ROM calculator, and the system variables CH_ADD, STKBOT and ERR_SP, work the digits out yourself
'   Float           variables of that type, and any sum done in them: + - * / ^, comparisons, and SIN COS TAN ASN ACS
'                   ATN LN EXP SQR whatever they are given, all of these use the ROM calculator
'   Mod on Fixed    uses MEMBOT ($5C92), the rest of Fixed (+ - * / and comparisons) is the compiler's own and is fine
'   RND, RANDOMIZE  the seed is kept in system variables ($5C76), and RANDOMIZE reads FRAMES ($5C78)
'   arrays          Dim a( 10 ) and the like, indexing uses MEMBOT ($5C92), and an array also puts data in front of the
'                   code, which the core and the stages must not have, as they are entered at their first byte (build.ps1
'                   checks that)
'   PRINT, CLS, INK, PAPER, BRIGHT, FLASH, OVER, INVERSE, AT, TAB, PLOT, DRAW, CIRCLE, ATTR, SCREEN$, POINT
'                   all of them draw on the ULA screen at $4000 through system variables, this demo draws on the tilemap
'                   instead, use s_core_print_char_at(), s_core_print_string_at() and s_core_clear_screen()
'   INKEY$          calls the ROM's keyboard routines, use fub_core_scan_key() or s_core_get_key()
'   PAUSE, BEEP     call into the ROM, wait with s_core_wait_for_vblank() in the core, or s_core_countdown()
'   LOAD, SAVE      call into the ROM's tape routines, use fub_core_file_save_page() and fub_core_file_load_page()
' what is fine: whole number types (Byte, UByte, Integer, UInteger, Long, ULong) and all the sums on them, including whole
' number "/" and Mod, strings (they live in the shared heap) with +, Len, Code and slicing, Peek, Poke, Out, In, and Asm
' N.B: one system variable is still written: when the heap has no room for a new string, the library puts an error code
' in ERR_NR ($5C3A), as it should, so here a full heap also changes two bytes of the page in MMU 2, keep an eye on the
' heap in the monitor
' N.B: build.ps1 looks through the compiled code of every module and stops the build if any of these has been used
' Put simply as, if you want to take complete control and maximize memory usage and still use the boriel compiler then you are
' are going to have to forgoe some built in functions like Chr() and Val() and Str$() etc.
'##################################################################################################################################
' how Boriel BASIC divides whole numbers, which is not the same as C or C++...
' N.B: this is not a fault either: BASICs have never agreed on the signs of a division's answer and remainder, Sinclair
' BASIC has no MOD at all, and Boriel BASIC defines its own, it matters only when bringing code across from C or C++,
' where the same sum written the same way can quietly give a different answer
' measured on 15 October 2026 with Boriel ZX BASIC 1.19.0, by running each sum in ZEsarUX and reading the answers back,
' * marks where the answer is not the one C and C++ give:
'
'   sum           C / C++     Byte        Integer, Long
'   ---           -------     ----        -------------
'    7 /  2         3           3           3
'   -7 /  2        -3           3 *        -3
'    7 / -2        -3          -3          -3
'   -7 / -2         3          -3 *         3
'   -7 Mod  2      -1           1 *         1 *
'   -7 Mod -2      -1           1 *         1 *
'
'   "/" on Byte     the answer takes the sign of the divisor, so to divide a negative Byte the C way, put it in an
'                   Integer first
'   "/" otherwise   Integer and Long cut the answer towards 0, as C and C++ do
'   Mod             the answer is never negative: it is the remainder of the two numbers without their signs, for
'                   every size, C and C++ give the remainder the sign of the dividend
'   unsigned        UByte, UInteger and ULong have no signs, "/" and Mod give the same answers as C and C++
'
'   constants       a sum made only of constants is worked out by the compiler, and its "/" keeps the fraction,
'                   as BASIC's "/" always has:
'                     22 / 4                          is 5.5, C and C++ give 5
'                     Dim x As Integer = -7 / 2       is -4, the -3.5 is rounded down, C and C++ cut it to -3
'                     v - 22 / 4, with v = 10         is 4, C and C++ give 5: the 5.5 has the compiler do the whole sum
'                                                     in Fixed (with fractions), 10 - 5.5 = 4.5, cut to 4 when stored
'                   so where a C-style whole answer is wanted, shift instead (22 >> 2 is 5), or put the constant in a
'                   whole number variable first, or write the answer (5) in, with a comment saying where it came from
' N.B: none of these can be caught by the build, they compile and run, and give the answer Boriel BASIC defines
'##################################################################################################################################
' notes re screen components:
'   component	size    where it lives          paged or core?
'   ---------   ----    --------------          --------------
'   font        2048    physical RAM page 10	never mapped by us, the display hardware reads it directly, it sits in the old Spectrum display file area, below the system variables
'   tile map    5120	physical RAM page 11	core, at the start of the page that is permanently mapped to MMU7 ($E000), the Next can only display tiles from pages 10, 11 or 14
'   palette      512    internal FPGA RAM	    neither, instead we populate the palette using NextReg $44 (data port)
'##################################################################################################################################
' --- DATA TYPES ---
' N.B: from this point onwards all defines and constants use this naming convention...
'   prefix      meaning             intent                                      typical Z80 target
'   ------      -------             ------                                      ------------------
'   MMU_        special use         for page swapping                           (well, it's used by ZX Next extensions really)
'   T_          custom structures   structured data layout                      (used in Boriel basic to reference data in pages in slots)
'   UB_         unsigned byte       counters, indices, small values (0-255)     A, B, C, L
'   UW_         unsigned word       large counts, 16-bit math values            BC, DE, HL
'   UL_         unsigned long       very large counts, 32-bit integers          (used for Boriel basic variables only)
'   UC_         unsigned byte       but naming is used to denote an ASCII code  typically A, but could be used in any half of a register pair
'   SB_ SW_     signed byte/word	offsets, relative movements (-128 to 127)   A or IX+d
'   MB_ MW_     masked byte/word    flags for bit masks                         AND, OR, BIT
'   A_          address             fixed & derived memory locations            HL, DE, BC, IX, IY
'##################################################################################################################################
' file: constants.bas
'   N.B: only the NEXTREG and MMU constants can start with NEXTREG_ and MMU_
'   ...all other defines and constants are to follow the naming convention...

Const   true    As UByte = 1
Const   false   As UByte = 0

' --- ZX NEXT HARDWARE ---
' some addresses are an IO address, other addresses are a RAM address
#define A_NEXTREG_SELECT    $243B
#define A_NEXTREG_DATA      $253B
#define A_Z80_CPU_STACK     $FFFE   ' i.e. one byte before last byte to cater for 16-bit width of 'SP' (the Stack Pointer)

' nextreg register indices
Const   UB_NEXTREG_MACHINE_ID       As UByte    = $00
Const   UB_NEXTREG_VERSION          As UByte    = $01
Const   UB_NEXTREG_RESET_CONFIG     As UByte    = $02
Const   UB_NEXTREG_CPU_SPEED        As UByte    = $07
Const   UB_NEXTREG_PERIPHERAL_1     As UByte    = $08
Const   UB_NEXTREG_PALETTE_INDEX    As UByte    = $40
Const   UB_NEXTREG_PALETTE_CONTROL  As UByte    = $43
Const   UB_NEXTREG_TILEMAP_CTRL     As UByte    = $6B

' machine control
Const   UB_NEXTREG_MACHINE_RESET    As UByte    = %00000001

' machine speed
Const   UB_CPU_SPEED_3MHZ           As UByte    = 0          ' 00 =  3.5 MHz (original Z80 speed)
Const   UB_CPU_SPEED_7MHZ           As UByte    = 1          ' 01 =  7 MHz mode
Const   UB_CPU_SPEED_14MHZ          As UByte    = 2          ' 10 = 14 MHz mode
Const   UB_CPU_SPEED_28MHZ          As UByte    = 3          ' 11 = 28 MHz mode

' screen config
Const   UB_TILE_ENABLE              As UByte    = %10000000  ' bit 7: tilemap enable (0=off, 1=on)
Const   UB_TILE_RES6                As UByte    = %01000000  ' bit 6: reserved (always 0)
Const   UB_TILE_4BIT_MODE           As UByte    = %00100000  ' bit 5: tile definitions (0=8-bit, 1=4-bit)
Const   UB_TILE_ATTR_ENABLE         As UByte    = %00010000  ' bit 4: tile attributes/2-byte mode (0=off, 1=on)
Const   UB_TILE_80COL               As UByte    = %00001000  ' bit 3: palette/columns (1=80 col / 256-color)
Const   UB_TILE_TEXT_MODE           As UByte    = %00000100  ' bit 2: text mode (0=off, 1=on)
Const   UB_TILE_OVER_SPRITES        As UByte    = %00000010  ' bit 1: tilemap over sprites (1=tilemap on top)
Const   UB_TILE_512_ENABLE          As UByte    = %00000001  ' bit 0: enable 512 tile mode

' periperal control
Const   UB_PERIP_1_JOY_MASK         As UByte    = %11000000  ' bits 6-7: joystick configuration
Const   UB_PERIP_1_TURBO_SOUND      As UByte    = %00100000  ' bit 5: turbo sound enable (set to 0 for off)
Const   UB_PERIP_1_60HZ             As UByte    = %00000100  ' bit 2: 50hz/60hz select (0=50hz, 1=60hz)
Const   UB_PERIP_1_MIC_EN           As UByte    = %00000010  ' bit 1: enable ear/mic port
Const   UB_PERIP_1_PAGING_EN        As UByte    = %00000001  ' bit 0: enable rom/ram paging


' N.B: some constants were removed from here because the registers are not what they claimed to be...
' ...nextreg $05 is Peripheral 1 (joysticks, 50/60Hz, scandoubler), nextreg $11 is the video timing mode, and nextreg $02 is reset control...
' ...there is no real time clock register, and no Ctrl or Alt keys, the Next's extra keys can be read from nextreg $B0 and $B1 if ever needed...
' ...the keyboard itself is read in fub_core_scan_key() in core.bas, which explains the ports, so the constants below are no longer used

' keyboard port and row selection masks
Const   UW_PORT_ULA                 As UInteger = $FFFE
Const   UB_KEY_ROW_CAPS_SHIFT       As UByte    = %11111110
Const   UB_KEY_ROW_SYMBOL_SHIFT     As UByte    = %01111111

' bit masks for specific keys in the ula response
Const   UB_ULA_BIT_CAPS_SHIFT       As UByte    = %00001
Const   UB_ULA_BIT_SYMBOL_SHIFT     As UByte    = %00010

' mask for the 5-bit matrix data (bits 0-4)
Const   UB_ULA_MATRIX_MASK          As UByte    = %00011111
' value when no keys are pressed in a row
Const   UB_ULA_MATRIX_IDLE          As UByte    = %00011111

' --- ZX NEXT / Z80 MMU SLOTS ---
' the slot numbers
Const   MMU_SLOT_0                  As UByte = $50
Const   MMU_SLOT_1                  As UByte = $51
Const   MMU_SLOT_2                  As UByte = $52
Const   MMU_SLOT_3                  As UByte = $53
Const   MMU_SLOT_4                  As UByte = $54
Const   MMU_SLOT_5                  As UByte = $55
Const   MMU_SLOT_6                  As UByte = $56
Const   MMU_SLOT_7                  As UByte = $57

' slot principal usage
Const   MMU_SLOT_CORE_CODE          As UByte = MMU_SLOT_4  ' and also slot 5...
Const   MMU_SLOT_CORE_DATA          As UByte = MMU_SLOT_6
Const   MMU_SLOT_PAGED_CODE         As UByte = MMU_SLOT_3
Const   MMU_SLOT_CORE_SCREEN        As UByte = MMU_SLOT_7
Const   MMU_SLOT_PAGED_DATA_M       As UByte = MMU_SLOT_0  ' the three paged data slots, known by four names...
Const   MMU_SLOT_PAGED_DATA_Z       As UByte = MMU_SLOT_0  ' ...data_z shares MMU 0 with data_m, only one of the two can be in view at a time
Const   MMU_SLOT_PAGED_DATA_I       As UByte = MMU_SLOT_1
Const   MMU_SLOT_PAGED_DATA_C       As UByte = MMU_SLOT_2

' slot addresses
#define A_MMU_SLOT_0    $0000   ' to $1FFF
#define A_MMU_SLOT_1    $2000   ' to $3FFF
#define A_MMU_SLOT_2    $4000   ' to $5FFF
#define A_MMU_SLOT_3    $6000   ' to $7FFF
#define A_MMU_SLOT_4    $8000   ' to $9FFF
#define A_MMU_SLOT_5    $A000   ' to $BFFF
#define A_MMU_SLOT_6    $C000   ' to $DFFF, size 8192
#define A_MMU_SLOT_7    $E000   ' to $FFFF

' slot principal usage
#define A_MMU_SLOT_PAGED_DATA_M     A_MMU_SLOT_0    ' the three paged data slots, known by four names...
#define A_MMU_SLOT_PAGED_DATA_Z     A_MMU_SLOT_0    ' ...data_z shares MMU 0 with data_m, only one of the two can be in view at a time
#define A_MMU_SLOT_PAGED_DATA_I     A_MMU_SLOT_1
#define A_MMU_SLOT_PAGED_DATA_C     A_MMU_SLOT_2
#define A_MMU_SLOT_PAGED_CODE       A_MMU_SLOT_3
#define A_MMU_SLOT_CORE_CODE        A_MMU_SLOT_4    ' and also slot 5...
#define A_MMU_SLOT_CORE_DATA        A_MMU_SLOT_6    ' size 8192
#define A_MMU_SLOT_CORE_SCREEN      A_MMU_SLOT_7

'#################################################################################################################################
' for a ZX Next with 2MB RAM, then the initial proposed 8KB page layout, from 224 (0 to 223) pages, is:
'   0-17        reserved by NextZXOS for itself (its API document says so), of which we use only these two:
'   10          font, in its first 2KB only             never mapped by us (the rest of the page holds the system variables)
'   11          core  screen cells, Z80 stack           MMU 7
'   50,51       core  code                              MMU 4,5
'   52          core  data, heap                        MMU 6
'   53-55       reserved
'   60-89       paged application code                  MMU 3
'   224-255     must not use beyond 1.75 MB, as these pages are too slow on older ZX Next models
'##################################################################################################################################

' --- ZX NEXT 8KB PAGE NUMBERS WITHIN THE 2MB RAM ---
Const   UB_PAGE_CORE_CODE           As UByte    = 50   '  2 pages, 16KB
Const   UB_PAGE_CORE_DATA           As UByte    = 52
Const   UB_PAGE_FONT                As UByte    = 10   ' never mapped by us, the display hardware reads it directly
Const   UB_PAGE_CORE_SCREEN         As UByte    = 11   ' the screen cells, and above them the core's stack

' pages used by the paged data test in stage-init.bas, two per data slot (DATA_M_1 and DATA_M_2 are the two pages for slot data_m, and so on)
Const   UB_PAGE_TEST_DATA_M_1       As UByte    = 90
Const   UB_PAGE_TEST_DATA_M_2       As UByte    = 91
Const   UB_PAGE_TEST_DATA_I_1       As UByte    = 93
Const   UB_PAGE_TEST_DATA_I_2       As UByte    = 94
Const   UB_PAGE_TEST_DATA_C_1       As UByte    = 100
Const   UB_PAGE_TEST_DATA_C_2       As UByte    = 101
' the page used by the file test in stage-init.bas, it is saved to the SD card, wiped, and loaded back
Const   UB_PAGE_TEST_FILE           As UByte    = 102

' the example data, see stage-data-include.bas: the core data page above (52, always in MMU 6, never paged out), and
' three pages of paged data, one for each of the left, centre and right stages, which all take their turn in the same
' paged data slot, MMU 0 (data_m), so the monitor's hits and swaps for MMU 0 show the page cache at work...
Const   UB_PAGE_DATA_LEFT           As UByte    = 96
Const   UB_PAGE_DATA_CENTRE         As UByte    = 97
Const   UB_PAGE_DATA_RIGHT          As UByte    = 98
Const   UB_SLOT_DATA                As UByte    = 0    ' the slot they take turns in, as s_core_swap_paged_data() numbers them
' ...and four spare pages, which a load from the SD card goes into first, so that nothing is changed unless all four
' files load, see fub_core_load_all() in core.bas
Const   UB_PAGE_SPARE_CORE          As UByte    = 103
Const   UB_PAGE_SPARE_LEFT          As UByte    = 104
Const   UB_PAGE_SPARE_CENTRE        As UByte    = 105
Const   UB_PAGE_SPARE_RIGHT         As UByte    = 106

Const   UB_PAGED_CODE_STAGE_INIT    As UByte    = 60
Const   UB_PAGED_CODE_STAGE_LEFT    As UByte    = 68
Const   UB_PAGED_CODE_STAGE_RIGHT   As UByte    = 69
Const   UB_PAGED_CODE_STAGE_CENTRE  As UByte    = 70
' ...and a library page: code that any stage may call, see s_core_call_library() in core.bas and stage-lib-demo.bas
Const   UB_PAGED_CODE_LIB_DEMO      As UByte    = 71

' --- LIBRARIES ---
' a library is a page of code like a stage, at $6000 in MMU 3, but called by a stage (or by another library) for one routine,
' and then put away again: the page that called it is put back before the call returns, see s_core_call_library()...
' ...its own working storage is the top 512 bytes of its own page, $7E00 to $7FFF while it is running: it belongs to that
' library alone, it is in view exactly when the library is, it costs no page swap, and, the page being RAM, what the
' library leaves there is still there the next time it is called, build.ps1 checks that a library's code stops short of it
' N.B: it goes out of view when the library returns, so anything handed back to the caller must go in the core data
#define A_LIB_PRIVATE               A_MMU_SLOT_PAGED_CODE + 7680
#define UW_LIB_CODE_LIMIT           7680
' the routines in the demo library, see stage-lib-demo.bas
Const   UB_LIB_DEMO_COUNT           As UByte    = 1
Const   UB_LIB_DEMO_SHOW            As UByte    = 2

' --- MAIN STAGES OF PROCESSING ---
Const   UB_STAGE_INIT               As UByte    = 0
Const   UB_STAGE_LEFT               As UByte    = 8
Const   UB_STAGE_RIGHT              As UByte    = 9
Const   UB_STAGE_CENTRE             As UByte    = 10

' --- THE EXAMPLE DATA ---
' what each of the three data pages holds, at the start of the page, seen through MMU 0 at $0000:
Const   UB_DATA_COUNTER             As UByte    = 0    ' a ULong, how many times the page's stage has paged it in
Const   UB_DATA_LETTER              As UByte    = 4    ' the stage's letter, L, C or R, so the screen can show which page is in
' the file that S saves to and O loads from, and the number that says how its pages are laid out, a load refuses a
' file with any other number, so change it whenever what is saved changes shape
#define S_SAVE_FILE                 "zxpaging.sav"
Const   UB_SAVE_VERSION             As UByte    = 1
' the two keys that save and load, as upper case character codes, as fub_core_countdown() compares them
Const   UC_KEY_SAVE                 As UByte    = 83   ' "S"
Const   UC_KEY_LOAD                 As UByte    = 79   ' "O", for "old", as L is taken by the left stage
Const   UC_KEY_MONITOR              As UByte    = 77   ' "M", the core's own key, the memory monitor on or off, in every stage
' the three stages' own keys: in any of the three, each one goes to its stage, see s_data_run() in stage-data-include.bas
Const   UC_KEY_LEFT                 As UByte    = 76   ' "L"
Const   UC_KEY_CENTRE               As UByte    = 67   ' "C"
Const   UC_KEY_RIGHT                As UByte    = 82   ' "R"

' --- SOME KEYBOARD CONSTANTS ---
' ...for the extended keys (above 127 to avoid standard ASCII)
Const   UW_KEY_UP           As UInteger = 130
Const   UW_KEY_DOWN         As UInteger = 131
Const   UW_KEY_LEFT         As UInteger = 132
Const   UW_KEY_RIGHT        As UInteger = 133
Const   UW_KEY_INSERT       As UInteger = 134
Const   UW_KEY_DELETE       As UInteger = 135
Const   UW_KEY_HOME         As UInteger = 136
Const   UW_KEY_END          As UInteger = 137
Const   UW_KEY_PGUP         As UInteger = 138
Const   UW_KEY_PGDN         As UInteger = 139
' ...and the Spectrum's own special keys, a real Next has a dedicated key for each, a classic keyboard uses caps shift + a digit
Const   UW_KEY_EDIT         As UInteger = 140   ' caps shift + 1
Const   UW_KEY_CAPS_LOCK    As UInteger = 141   ' caps shift + 2
Const   UW_KEY_TRUE_VIDEO   As UInteger = 142   ' caps shift + 3
Const   UW_KEY_INV_VIDEO    As UInteger = 143   ' caps shift + 4
Const   UW_KEY_GRAPH        As UInteger = 144   ' caps shift + 9
' N.B: there is no key code for extend (caps shift + symbol shift), it is our Ctrl key, see MB_KEY_CTRL and fub_core_scan_key() in core.bas

' the two registers that hold the Next keyboard's extra keys, in both a bit is 1 while its key is down
Const   UB_NEXTREG_EXT_KEYS_0       As UByte    = $B0   ' bit 7 ;   6 "   5 ,   4 .   3 up   2 down   1 left   0 right
Const   UB_NEXTREG_EXT_KEYS_1       As UByte    = $B1   ' bit 7 delete   6 edit   5 break   4 inv video   3 true video   2 graph   1 caps lock   0 extend

Const   MB_KEY_CTRL         As UByte    = %00000001     ' extend held, i.e. caps shift + symbol shift, or the Next's EXTEND key
Const   MB_KEY_SHIFT        As UByte    = %00000010
Const   MB_KEY_SYMBOL       As UByte    = %00001000

' --- SCREEN GEOMETRY ---
Const   UB_SCREEN_ROWS          As UByte    = 32
Const   UB_SCREEN_COLS          As UByte    = 80

' --- SCREEN ADDRESSING ---
#define A_SCREEN_BASE           $E000   ' the screen cells start at the very beginning of MMU 7 (page 14)

' --- PROGRAM CRASH AND ERROR CONSTANTS ---
Const   UB_CRASH_BAD_CORE_STAGE             As UByte = 1
Const   UB_CRASH_BAD_DATA_STRUCTURE_SIZE    As UByte = 2
Const   UB_CRASH_RAMCOPY_OVERLAP            As UByte = 3

' --- PALETTE COLOURS ---
' color attribute constants for 80x32 text mode
Const UB_BLACK          As UByte = 0                ' pair 0: black ink
Const UB_BLUE           As UByte = 2                ' pair 1: blue ink
Const UB_RED            As UByte = 4                ' pair 2: red ink
Const UB_MAGENTA        As UByte = 6                ' pair 3: magenta ink
Const UB_GREEN          As UByte = 8                ' pair 4: green ink
Const UB_CYAN           As UByte = 10               ' pair 5: cyan ink
Const UB_YELLOW         As UByte = 12               ' pair 6: yellow ink
Const UB_WHITE          As UByte = 14               ' pair 7: white ink
Const UB_DARK_GREY      As UByte = 16               ' pair 8: dark grey ink
Const UB_BRIGHT_BLUE    As UByte = 18               ' pair 9: bright blue
Const UB_BRIGHT_RED     As UByte = 20               ' pair 10: bright red
Const UB_BRIGHT_MAGENTA As UByte = 22               ' pair 11: bright magenta
Const UB_BRIGHT_GREEN   As UByte = 24               ' pair 12: bright green
Const UB_BRIGHT_CYAN    As UByte = 26               ' pair 13: bright cyan
Const UB_BRIGHT_YELLOW  As UByte = 28               ' pair 14: bright yellow
Const UB_BRIGHT_WHITE   As UByte = 30               ' pair 15: bright white

' the 9-bit RGB values (%RRRGGGBBB)
' ...spaced-out 9-bit RGB constants (%RRR, %GGG, %BBB)
' ...each component is %000 to %111 (0-7)
Const   UW_BLACK_RGB          As UInteger = ( %000 Shl 6 ) Or ( %000 Shl 3 ) Or %000
Const   UW_BLUE_RGB           As UInteger = ( %000 Shl 6 ) Or ( %000 Shl 3 ) Or %101
Const   UW_RED_RGB            As UInteger = ( %101 Shl 6 ) Or ( %000 Shl 3 ) Or %000
Const   UW_MAGENTA_RGB        As UInteger = ( %101 Shl 6 ) Or ( %000 Shl 3 ) Or %101
Const   UW_GREEN_RGB          As UInteger = ( %000 Shl 6 ) Or ( %101 Shl 3 ) Or %000
Const   UW_CYAN_RGB           As UInteger = ( %000 Shl 6 ) Or ( %101 Shl 3 ) Or %101
Const   UW_YELLOW_RGB         As UInteger = ( %101 Shl 6 ) Or ( %101 Shl 3 ) Or %000
Const   UW_WHITE_RGB          As UInteger = ( %101 Shl 6 ) Or ( %101 Shl 3 ) Or %101
Const   UW_DARK_GREY_RGB      As UInteger = ( %010 Shl 6 ) Or ( %010 Shl 3 ) Or %010
Const   UW_BRIGHT_BLUE_RGB    As UInteger = ( %000 Shl 6 ) Or ( %000 Shl 3 ) Or %111
Const   UW_BRIGHT_RED_RGB     As UInteger = ( %111 Shl 6 ) Or ( %000 Shl 3 ) Or %000
Const   UW_BRIGHT_MAGENTA_RGB As UInteger = ( %111 Shl 6 ) Or ( %000 Shl 3 ) Or %111
Const   UW_BRIGHT_GREEN_RGB   As UInteger = ( %000 Shl 6 ) Or ( %111 Shl 3 ) Or %000
Const   UW_BRIGHT_CYAN_RGB    As UInteger = ( %000 Shl 6 ) Or ( %111 Shl 3 ) Or %111
Const   UW_BRIGHT_YELLOW_RGB  As UInteger = ( %111 Shl 6 ) Or ( %111 Shl 3 ) Or %000
Const   UW_BRIGHT_WHITE_RGB   As UInteger = ( %111 Shl 6 ) Or ( %111 Shl 3 ) Or %111

'##################################################################################################################################
' --- CORE API JUMP TABLE ---
' core.bas places one "jp <routine>" every three bytes starting at $8010, in exactly this order...
' ...the paged stages reach the core routines through these fixed addresses (see stage-include.bas)...
' ...so the core can be recompiled, and its routines can move around, without recompiling the stages...
#define A_JUMP_NEXT_REG            $8010
#define A_JUMP_CRASH               $8013
#define A_JUMP_RAM_COPY            $8016
#define A_JUMP_CLEAR_SCREEN        $8019
#define A_JUMP_PRINT_CHAR_AT       $801C
#define A_JUMP_PRINT_STRING_AT     $801F
#define A_JUMP_GET_KEY             $8022
#define A_JUMP_COUNTDOWN           $8025
#define A_JUMP_NUMBER              $8028
#define A_JUMP_SCAN_KEY            $802B
#define A_JUMP_KEY_NAME            $802E
#define A_JUMP_SWAP_PAGED_DATA      $8031
#define A_JUMP_FILE_SAVE_PAGE       $8034
#define A_JUMP_FILE_LOAD_PAGE       $8037
#define A_JUMP_CHAR                 $803A
#define A_JUMP_RAM_FILL             $803D
#define A_JUMP_SAVE_ALL             $8040
#define A_JUMP_LOAD_ALL             $8043
#define A_JUMP_CLEAR_ROW            $8046
#define A_JUMP_CALL_LIBRARY         $8049

' --- INTERRUPTS ---
' we use interrupt mode 2, so that the handler can live in the core and nothing of ours is needed at $0038...
' ...in mode 2 the Z80 jumps to the address it reads from a table, at ( I register * 256 ) + whatever byte is on the data bus...
' ...that byte is not predictable on a Spectrum, so the table is 257 copies of one value, and the handler sits at the address
' made of that value twice, then it does not matter which entry gets read...
' ...both live at the top of the second core code page, the loader builds them (see s_load_set_interrupts() in load.bas),
' and build.ps1 checks that the core's own code stops short of them
#define A_IM2_HANDLER           $BDBD   ' the handler itself, a single "reti"
#define A_IM2_TABLE             $BE00   ' 257 bytes, $BE00 to $BF00, every one of them $BD

' --- THE STACK ---
#define A_STACK_BOTTOM          $F400   ' the lowest address the stack may reach, directly above the 5120 bytes of screen cells
#define UB_STACK_FILL           $A5     ' the core fills the stack area with this at start up, so the memory monitor can see how deep it has ever been
#define UB_HEAP_FILL            $5A     ' ...and the heap with this, for the same reason

' --- THE HEAP ---
' there is one heap (for strings), shared by the core and all of the stages, the core prepares it once at start up...
' ...so a stage can build a string and hand it to a core routine, e.g. s_core_print_string_at( 2 , 38 , "INIT" , UB_BRIGHT_WHITE )...
' ...it lives in the last 1024 bytes of the core data page ($DC00 to $DFFF), as set by --heap-address and --heap-size for core.bas and the stages in build.ps1...
' ...so the fixed variables below (which grow upwards from $C000) must stay under $DC00

' --- CORE DATA and WORKING STORAGE ---
#define A_API           A_MMU_SLOT_CORE_DATA            'size 100, allow for the address of up to 50 different subs and functions
#define A_CORE          A_MMU_SLOT_CORE_DATA +  232     'size 168, up to A_KEY
#define A_KEY           A_MMU_SLOT_CORE_DATA +  400     'size  50
' the program's own part of the core data page, everything from here to the heap, $C200 to $DBFF, 6656 bytes...
' ...this is what a save keeps and a load brings back, the 512 bytes below it are the core's own workings, and the heap
' above it holds the strings of the program that is running now, a load must not change either of them
#define A_DEMO          A_MMU_SLOT_CORE_DATA +  512     'size 6656
#define UW_DEMO_SIZE    6656

'##################################################################################################################################
