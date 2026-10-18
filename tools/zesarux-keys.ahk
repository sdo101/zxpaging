; makes a PC keyboard type what the program expects while the ZEsarUX emulator's window has the keyboard, and does
; nothing anywhere else. AutoHotkey version 2, started by build.ps1 with the emulator, or by double clicking this file.
; It sits in the notification area as a green H, right click it there to stop it.
;
; why it is needed: ZEsarUX turns the PC's keys into the Spectrum's forty, and some are lost or changed on the way...
;   the number pad          does not arrive at all
;   Ctrl with a letter      arrives as symbol shift and the letter, a symbol, and not as our Ctrl
;   shift with punctuation  arrives as caps shift, symbol shift and a key, which is our Ctrl with a letter
; ...what the emulator does do: Shift is caps shift, Ctrl and Alt are both symbol shift, and Tab is both shifts
; together, which is the program's Ctrl (the Next's EXTEND key), see fub_core_scan_key() in core.bas
;
; what this does about it:
;   the number pad          its digits are the top row's digits, with Num Lock on or off, and . + - * / are themselves
;   Ctrl with a letter      is sent as Tab and the letter, so Ctrl-G is the program's Ctrl-G
;   punctuation             every punctuation key, with shift and without, is sent as symbol shift and the Spectrum
;                           key that has that symbol, from key_table_symbol in core.bas
; N.B: the punctuation is by where the keys are on a UK keyboard, another layout wants the tables below changed

#Requires AutoHotkey v2.0
#SingleInstance Force
SendMode "Event"
; a key sent is held for 60 thousandths of a second, three of the program's looks at the keyboard (one a frame), and 20
; pass between keys
SetKeyDelay 20, 60

failures := ""
count := 0
HotIfWinActive "ahk_exe zesarux.exe ahk_class SDL_app"

; the number pad: a digit is held for as long as the pad's key is, so that a key held down is still held in the program
pad := Map( "Numpad0", "0", "Numpad1", "1", "Numpad2", "2", "Numpad3", "3", "Numpad4", "4"
          , "Numpad5", "5", "Numpad6", "6", "Numpad7", "7", "Numpad8", "8", "Numpad9", "9"
          , "NumpadIns", "0", "NumpadEnd", "1", "NumpadDown", "2", "NumpadPgDn", "3", "NumpadLeft", "4"
          , "NumpadClear", "5", "NumpadRight", "6", "NumpadHome", "7", "NumpadUp", "8", "NumpadPgUp", "9" )
for name, digit in pad {
    Define( "*" name, HoldDown.Bind( digit ) )
    Define( "*" name " up", HoldUp.Bind( digit ) )
}
Define( "NumpadEnter", ( * ) => SendEvent( "{Enter}" ) )
Define( "NumpadDot", Symbol.Bind( "m" ) )
Define( "NumpadAdd", Symbol.Bind( "k" ) )
Define( "NumpadSub", Symbol.Bind( "j" ) )
Define( "NumpadMult", Symbol.Bind( "b" ) )
Define( "NumpadDiv", Symbol.Bind( "v" ) )

; Ctrl with a letter
for letter in StrSplit( "abcdefghijklmnopqrstuvwxyz" )
    Define( "^" letter, Control.Bind( letter ) )

; punctuation without shift, by the key's scan code on a UK keyboard, and the Spectrum key that has the symbol
;        -          =          [          ]          ;          '          #          \          ,          .          /          `
plain := Map( "SC00C", "j", "SC00D", "l", "SC01A", "y", "SC01B", "u", "SC027", "o", "SC028", "7", "SC02B", "3"
            , "SC056", "d", "SC033", "n", "SC034", "m", "SC035", "v", "SC029", "e" )
for code, key in plain
    Define( code, Symbol.Bind( key ) )

; punctuation with shift, the same way, N.B: the pound sign is not here, the program has no use for one
;        !          "          $          %          ^          &          *          (          )          _          +
;        {          }          :          @          ~          |          <          >          ?
shifted := Map( "SC002", "1", "SC003", "p", "SC005", "4", "SC006", "5", "SC007", "h", "SC008", "6", "SC009", "b"
              , "SC00A", "8", "SC00B", "9", "SC00C", "0", "SC00D", "k", "SC01A", "f", "SC01B", "g", "SC027", "z"
              , "SC028", "2", "SC02B", "a", "SC056", "s", "SC033", "q", "SC034", "w", "SC035", "c" )
for code, key in shifted
    Define( "+" code, Symbol.Bind( key ) )

HotIfWinActive

; what was set up, and anything that could not be, is written where build.ps1 and a curious person can read it
FileOpen( A_Temp "\zesarux-keys.log", "w" ).Write( count " keys set up" ( failures = "" ? "" : ", these could not be:" failures ) "`n" )
if failures != ""
    MsgBox "zesarux-keys.ahk could not set up these keys:" failures

Define( name, action ) {
    global failures, count
    try {
        Hotkey name, action
        count += 1
    } catch as problem {
        failures .= "`n  " name ": " problem.Message
    }
}

; the top row digit goes down, and stays down, {Blind} leaves Shift and the rest as they are being held
HoldDown( digit, * ) {
    SendEvent "{Blind}{" digit " down}"
}

HoldUp( digit, * ) {
    SendEvent "{Blind}{" digit " up}"
}

; symbol shift, which the emulator takes Ctrl for, and the Spectrum key that has the symbol on it...
; ...N.B: a Shift being held is let go while this is sent, AutoHotkey sees to that, or the program would read Ctrl
Symbol( key, * ) {
    SendEvent "{LCtrl down}" key "{LCtrl up}"
}

; both shifts, which the emulator takes Tab for, and the letter: the program's Ctrl and that letter
Control( letter, * ) {
    SendEvent "{Tab down}" letter "{Tab up}"
}
