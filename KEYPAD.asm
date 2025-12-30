;====================================================================
; PROJECT: 4x4 Keypad Driver with 2-Digit Number Entry
; CONTROLLER: PIC16F877A
;
; DESCRIPTION:
; This program reads input from a 4x4 Matrix Keypad.
; It implements a simple state machine to accept 2-digit numbers.
;
; CONTROLS:
; - Key 'A' (0x0A): UNLOCK / ENABLE INPUT
; - Key '#' (0x0F): LOCK / RESET
; - Keys 0-9      : Data Entry
;
; LOGIC:
; 1. System waits for 'A' to enable input.
; 2. User enters 1st Digit -> Value is stored.
; 3. User enters 2nd Digit -> Formula: (1st Digit * 10) + 2nd Digit.
; 4. Result is displayed on PORTD.

;====================================================================

LIST    P=16F877A
        INCLUDE "p16f877a.inc"
        __CONFIG h'3F31'

;================ VARIABLES =================
        CBLOCK  0x20
            row_idx       ; Current row being scanned (0-3)
            col_idx       ; Current column detected (0-3)
            key_idx       ; The decoded key value (0-15 or 0xFF)
            last_key      ; Stores the final calculated value
            prev_key      ; Stores previous key for debouncing/holding
            delay         ; General delay counter
            digit_state   ; State: 0=Waiting 1st digit, 1=Waiting 2nd digit
            input_enable  ; Flag: 0=Locked, 1=Unlocked (Set by 'A')
        ENDC

;================ RESET VECTOR ==============
        ORG     0x0000
        GOTO    INIT

;================ INIT ======================
INIT:
        BANKSEL input_enable
        CLRF    input_enable    ; Disable input initially (Wait for 'A')

        BANKSEL digit_state
        CLRF    digit_state     ; Reset state machine

        ; -------- PORTD (OUTPUT) --------
        BANKSEL TRISD
        CLRF    TRISD           ; Set PORTD as Output
        BANKSEL PORTD
        MOVLW   0xFF
        MOVWF   PORTD           ; Initialize PORTD High (Active Low LEDs off?)

        ; -------- PORTB (ROWS & COLS) --------
        ; RB2-RB5 = ROW (Outputs)
        ; RB6-RB7 = COL (Inputs)
        BANKSEL TRISB
        MOVLW   b'11000011'     ; 1=Input, 0=Output
        MOVWF   TRISB

        BANKSEL PORTB
        BSF     PORTB,2         ; Set Rows HIGH initially
        BSF     PORTB,3
        BSF     PORTB,4
        BSF     PORTB,5

        ; -------- PORTC (COLS) --------
        ; RC4-RC5 = COL (Inputs)
        BANKSEL TRISC
        BSF     TRISC,4         ; Set RC4 as Input
        BSF     TRISC,5         ; Set RC5 as Input

        BANKSEL last_key
        CLRF    last_key        ; Clear result
        BANKSEL prev_key
        MOVLW   0xFF            ; Init prev_key to "No Key"
        MOVWF   prev_key

;================ MAIN LOOP =================
MAIN:
        CALL    KEYPAD_GET      ; Scan Keypad. W = Key Value or 0xFF

        BANKSEL key_idx
        MOVWF   key_idx         ; Store current key

        ; ---- Check: Is a key pressed? ----
        MOVF    key_idx,W
        XORLW   0xFF            ; 0xFF means no key
        BTFSC   STATUS,Z
        GOTO    SHOW_LAST       ; No key -> Keep displaying last value

        ; ---- Check: Is it the SAME key held down? ----
        BANKSEL prev_key
        MOVF    prev_key,W
        SUBWF   key_idx,W
        BTFSC   STATUS,Z
        GOTO    SHOW_LAST       ; Same key -> Ignore (debounce/repeat block)

        ; ---- NEW VALID KEY PRESSED ----

        ; === CHECK FOR 'A' (ENABLE) ===
        BANKSEL key_idx
        MOVF    key_idx,W
        XORLW   0x0A            ; Is it 'A'?
        BTFSS   STATUS,Z
        GOTO    CHECK_ENABLE    ; No -> Check if enabled

        ; 'A' Pressed -> Unlock System
        BANKSEL input_enable
        MOVLW   1
        MOVWF   input_enable

        ; Reset Logic
        BANKSEL digit_state
        CLRF    digit_state     ; Ready for 1st digit

        BANKSEL last_key
        CLRF    last_key        ; Clear previous value (optional)

        GOTO    SAVE_PREV       ; Update history and loop

CHECK_ENABLE:
        ; If input_enable is 0, ignore all other keys
        BANKSEL input_enable
        MOVF    input_enable,W
        BTFSC   STATUS,Z
        GOTO    SAVE_PREV       ; System locked -> Ignore key

        ; === CHECK FOR '#' (RESET/LOCK) ===
        BANKSEL key_idx
        MOVF    key_idx,W
        XORLW   0x0F            ; Is it '#'?
        BTFSS   STATUS,Z
        GOTO    DIGIT_CHECK     ; No -> Process as Number

        ; '#' Pressed -> Lock System
        BANKSEL input_enable
        CLRF    input_enable    ; Lock

        BANKSEL digit_state
        CLRF    digit_state     ; Reset state

        GOTO    SAVE_PREV

DIGIT_CHECK:
        ; State Machine: 0 = First Digit, 1 = Second Digit
        BANKSEL digit_state
        MOVF    digit_state,W
        BTFSS   STATUS,Z
        GOTO    SECOND_DIGIT    ; If State=1, go to Second Digit logic

        ; Verify State is indeed 0 (Redundant check but safe)
        BANKSEL digit_state
        MOVF    digit_state,W
        BTFSS   STATUS,Z
        GOTO    DIGIT_CHECK     ; Should not happen based on logic above

        ; ===== FIRST DIGIT LOGIC =====
        BANKSEL key_idx
        MOVF    key_idx,W

        ; Goal: last_key = key * 10
        ; Implementation: (key * 2) + (key * 8) = key * 10
        
        BANKSEL last_key
        MOVWF   last_key
        BCF     STATUS,C
        RLF     last_key,F      ; last_key = key * 2

        BANKSEL delay           ; Use 'delay' var as temp storage
        MOVWF   delay
        BCF     STATUS,C
        RLF     delay,F         ; temp * 2
        BCF     STATUS,C
        RLF     delay,F         ; temp * 4
        BCF     STATUS,C
        RLF     delay,F         ; temp * 8

        MOVF    delay,W
        BANKSEL last_key
        ADDWF   last_key,F      ; last_key = (key*2) + (key*8) = key*10

        ; Update State -> Expect 2nd digit next
        BANKSEL digit_state
        MOVLW   1
        MOVWF   digit_state
        GOTO    SAVE_PREV

        ; ===== SECOND DIGIT LOGIC =====
SECOND_DIGIT:
        BANKSEL key_idx
        MOVF    key_idx,W
        BANKSEL last_key
        ADDWF   last_key,F      ; last_key = (First*10) + Second

        ; Operation Complete. Reset state.
        BANKSEL digit_state
        CLRF    digit_state
        
        BANKSEL input_enable
        CLRF    input_enable    ; Lock system (require 'A' again)

SAVE_PREV:
        ; Update previous key to prevent repeated triggering
        BANKSEL prev_key
        MOVF    key_idx,W
        MOVWF   prev_key

SHOW_LAST:
        ; Output result to PORTD
        BANKSEL last_key
        MOVF    last_key,W
        
        BANKSEL PORTD
        MOVWF   PORTD
        GOTO    MAIN

;================ SUBROUTINE: KEYPAD GET ====
; Scans 4x4 Matrix.
; Returns: W = Key Value (0x00..0x0F) or 0xFF if None
;============================================================
KEYPAD_GET:
        BANKSEL key_idx
        MOVLW   0xFF
        MOVWF   key_idx         ; Default: No Key

        BANKSEL row_idx
        CLRF    row_idx         ; Start from Row 0

SCAN_ROW:
        ; Step 1: Set ALL Rows HIGH
        BANKSEL PORTB
        BSF     PORTB,2
        BSF     PORTB,3
        BSF     PORTB,4
        BSF     PORTB,5

        ; Step 2: Drive CURRENT Row LOW
        BANKSEL row_idx
        MOVF    row_idx,W
        CALL    DRIVE_ROW_LOW
        CALL    SMALL_DELAY     ; Wait for signal to settle

        ; Step 3: Check Columns
        CALL    READ_COL
        BTFSS   STATUS,Z        ; If Z=0, a key was found
        GOTO    FOUND_KEY

        ; Step 4: Next Row
        BANKSEL row_idx
        INCF    row_idx,F
        MOVLW   d'4'
        SUBWF   row_idx,W
        BTFSS   STATUS,Z        ; Done all 4 rows?
        GOTO    SCAN_ROW        ; No -> Continue

        MOVLW   0xFF            ; No key detected in any row
        RETURN

FOUND_KEY:
        ; Calculate Key Index: (Row * 4) + Col
        BANKSEL row_idx
        MOVF    row_idx,W
        MOVWF   key_idx
        RLF     key_idx,F       ; Row * 2
        RLF     key_idx,F       ; Row * 4

        BANKSEL col_idx
        MOVF    col_idx,W
        ADDWF   key_idx,F       ; + Col

        ; Convert Index to Actual Key Value via Lookup Table
        MOVF    key_idx,W
        CALL    KEY_TABLE
        RETURN

;================ HELPER: DRIVE ROW LOW =====
; Sets the specific row pin to 0 (Active Low Scan)
;============================================================
DRIVE_ROW_LOW:
        ADDWF   PCL,F
        GOTO    ROW0
        GOTO    ROW1
        GOTO    ROW2
        GOTO    ROW3

ROW0:   BCF     PORTB,2
        RETURN
ROW1:   BCF     PORTB,3
        RETURN
ROW2:   BCF     PORTB,4
        RETURN
ROW3:   BCF     PORTB,5
        RETURN

;================ HELPER: READ COLUMNS ======
; Checks input pins. Returns Col Index in 'col_idx'.
; Z Flag = 0 if key found, 1 if no key.
;============================================================
READ_COL:
        BANKSEL PORTB
        BTFSS   PORTB,6         ; Check RB6
        GOTO    C0
        BTFSS   PORTB,7         ; Check RB7
        GOTO    C1

        BANKSEL PORTC
        BTFSS   PORTC,4         ; Check RC4
        GOTO    C2
        BTFSS   PORTC,5         ; Check RC5
        GOTO    C3

        BSF     STATUS,Z        ; No column is Low -> No press
        RETURN

C0:     MOVLW   0
        BANKSEL col_idx
        MOVWF   col_idx
        BCF     STATUS,Z        ; Key Found flag
        RETURN
C1:     MOVLW   1
        BANKSEL col_idx
        MOVWF   col_idx
        BCF     STATUS,Z
        RETURN
C2:     MOVLW   2
        BANKSEL col_idx
        MOVWF   col_idx
        BCF     STATUS,Z
        RETURN
C3:     MOVLW   3
        BANKSEL col_idx
        MOVWF   col_idx
        BCF     STATUS,Z
        RETURN

;================ LOOKUP TABLE ==============
; Maps Matrix Index (0-15) to Key Value
;============================================================
KEY_TABLE:
        ADDWF   PCL,F
        RETLW   0x01    ; Key 1
        RETLW   0x02    ; Key 2
        RETLW   0x03    ; Key 3
        RETLW   0x0A    ; Key A
        RETLW   0x04    ; Key 4
        RETLW   0x05    ; Key 5
        RETLW   0x06    ; Key 6
        RETLW   0x0B    ; Key B
        RETLW   0x07    ; Key 7
        RETLW   0x08    ; Key 8
        RETLW   0x09    ; Key 9
        RETLW   0x0C    ; Key C
        RETLW   0x0E    ; Key * (Mapped to 0x0E)
        RETLW   0x00    ; Key 0
        RETLW   0x0F    ; Key # (Mapped to 0x0F)
        RETLW   0x0D    ; Key D

;================ SMALL DELAY ===============
SMALL_DELAY:
        BANKSEL delay
        MOVLW   d'60'
        MOVWF   delay
SD_LOOP:
        DECFSZ  delay,F
        GOTO    SD_LOOP
        RETURN

        END


