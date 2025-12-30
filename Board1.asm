;*******************************************************************************
; PROJE: AKILLI PERDE S?STEM? - BOARD 1 (FAN HIZI DÜZELT?LD?)
; PINOUT: RD0-RD7(Seg), RC0-RC3(Dig), RC4(Heater), RC5(Cooler), RA4(Fan Tach)
;*******************************************************************************
    LIST    P=16F877A
    INCLUDE "p16f877a.inc"
    __CONFIG h'3F31'

;================ DE???KENLER =================
    CBLOCK 0x20
        temp_actual, temp_target, temp_frac
        TENS, ONES, DLY, cntA, cntB
        display_mode, fan_int, GELEN_VERI, DISPLAY_VAL
        MODE_TIMER, KEY_DELAY
    ENDC

    ORG     0x0000
    GOTO    INIT

;================ BA?LANGIÇ AYARLARI =================
INIT:
    MOVLW   d'35'
    MOVWF   temp_target
    CLRF    display_mode
    CLRF    MODE_TIMER
    CLRF    KEY_DELAY

    BANKSEL TRISD
    CLRF    TRISD           ; RD0-RD7: Segmentler
    BANKSEL TRISC
    MOVLW   b'10000000'     ; RC7: RX In, Di?erleri Out
    MOVWF   TRISC
    BANKSEL TRISB
    MOVLW   b'11110000'     ; Keypad
    MOVWF   TRISB
    BANKSEL TRISA
    MOVLW   b'00010001'     ; RA0: Temp, RA4: Fan Tach giri?i
    MOVWF   TRISA

    ; -------- ANALOG & TIMER0 AYARLARI --------
    BANKSEL ADCON1
    MOVLW   b'00001110'     ; RA0 Analog
    MOVWF   ADCON1
    
    ; Timer0: RA4 pinindeki yükselen kenarlar? say (T0CS=1, T0SE=0)
    ; Prescaler'? WDT'ye ata (PSA=1), böylece her darbe direkt say?l?r
    BANKSEL OPTION_REG
    MOVLW   b'10101111'     ; T0CS=1, T0SE=0, PSA=1, PORTB Pull-up On
    MOVWF   OPTION_REG

    BANKSEL ADCON0
    MOVLW   b'01000001'     ; ADC On
    MOVWF   ADCON0

    BANKSEL SPBRG
    MOVLW   d'25'           ; 9600 Baud
    MOVWF   SPBRG
    MOVLW   b'00100100'
    MOVWF   TXSTA
    BANKSEL RCSTA
    MOVLW   b'10010000'
    MOVWF   RCSTA

    BANKSEL PORTA
    CLRF    PORTC
    CLRF    PORTD
    CLRF    TMR0
    GOTO    MAIN_LOOP

;================ ANA DÖNGÜ =================
MAIN_LOOP:
    CALL    READ_TEMP       ; Is? oku
    CALL    HVAC_CONTROL    ; Kontrol et
    CALL    PYTHON_DINLE    ; API'yi dinle
    CALL    SCAN_KEYPAD     ; Tu? tak?m?n? tara
    
    ; Display Modu Zamanlay?c?s?
    INCF    MODE_TIMER, F
    MOVLW   d'180'
    SUBWF   MODE_TIMER, W
    BTFSS   STATUS, C
    GOTO    DISPLAY_CONT
    
    CLRF    MODE_TIMER
    CALL    READ_FAN        ; Sadece mod de?i?irken fan? güncelle (Performans için)
    INCF    display_mode, F
    MOVLW   d'3'
    SUBWF   display_mode, W
    BTFSC   STATUS, C
    CLRF    display_mode

DISPLAY_CONT:
    CALL    PREPARE_VAL
    CALL    SPLIT_VAL
    CALL    MUX_REFRESH
    GOTO    MAIN_LOOP

;================ FAN OKUMA (TMR0 Üzerinden) =================
READ_FAN:
    BANKSEL TMR0
    MOVF    TMR0, W         ; Timer0 de?erini oku (RA4'ten gelen sinyal say?s?)
    MOVWF   fan_int         ; fan_int içine kaydet
    CLRF    TMR0            ; Bir sonraki say?m için s?f?rla
    BANKSEL PORTA
    RETURN

;================ KEYPAD TARAMA =================
SCAN_KEYPAD:
    DECFSZ  KEY_DELAY, F
    RETURN
    MOVLW   d'25'
    MOVWF   KEY_DELAY
    MOVLW   b'11111110'
    MOVWF   PORTB
    BTFSS   PORTB, 7
    GOTO    UP_T
    MOVLW   b'11111101'
    MOVWF   PORTB
    BTFSS   PORTB, 7
    GOTO    DOWN_T
    RETURN

UP_T:
    MOVLW d'50'
    SUBWF temp_target, W
    BTFSC STATUS, C
    RETURN
    INCF temp_target, F
    MOVLW 1
    MOVWF display_mode
    RETURN

DOWN_T:
    MOVF temp_target, W
    SUBLW d'10'
    BTFSC STATUS, C
    RETURN
    DECF temp_target, F
    MOVLW 1
    MOVWF display_mode
    RETURN

;================ API DINLEME =================
PYTHON_DINLE:
    BANKSEL PIR1
    BTFSS   PIR1, RCIF
    GOTO    FINISH_RX
    BANKSEL RCREG
    MOVF    RCREG, W
    MOVWF   GELEN_VERI
    MOVF    GELEN_VERI, W
    XORLW   0x04
    BTFSC   STATUS, Z
    GOTO    SEND_A
    MOVF    GELEN_VERI, W
    XORLW   0x06
    BTFSC   STATUS, Z
    GOTO    SEND_D
    MOVF    GELEN_VERI, W
    XORLW   0x05
    BTFSC   STATUS, Z
    GOTO    SEND_F
    MOVF    GELEN_VERI, W
    ANDLW   0xC0
    XORLW   0xC0
    BTFSC   STATUS, Z
    GOTO    SET_A_API
FINISH_RX:
    BANKSEL PORTA
    RETURN

SEND_A: MOVF temp_actual, W
    CALL UART_WRITE
    GOTO FINISH_RX
SEND_D: MOVF temp_target, W
    CALL UART_WRITE
    GOTO FINISH_RX
SEND_F: MOVF fan_int, W
    CALL UART_WRITE
    GOTO FINISH_RX
SET_A_API: MOVF GELEN_VERI, W
    ANDLW 0x3F
    MOVWF temp_target
    GOTO FINISH_RX

UART_WRITE:
    BANKSEL TXREG
    MOVWF   TXREG
TX_WAIT:
    BANKSEL TXSTA
    BTFSS   TXSTA, TRMT
    GOTO    TX_WAIT
    BANKSEL PORTA
    RETURN

;================ HVAC & MUX =================
HVAC_CONTROL:
    BANKSEL PORTA
    BCF     PORTC, 4
    BCF     PORTC, 5
    MOVF    temp_actual, W
    SUBWF   temp_target, W
    BTFSS   STATUS, C
    GOTO    H_COOL
    BTFSC   STATUS, Z
    RETURN
    BSF     PORTC, 4
    RETURN
H_COOL: BSF PORTC, 5
    RETURN

MUX_REFRESH:
    MOVF display_mode, W
    CALL M_TAB
    MOVWF PORTD
    BSF PORTC, 0
    CALL S_DLY
    BCF PORTC, 0
    MOVF TENS, W
    CALL H_TAB
    MOVWF PORTD
    BSF PORTC, 1
    CALL S_DLY
    BCF PORTC, 1
    MOVF ONES, W
    CALL H_TAB
    IORLW b'10000000'
    MOVWF PORTD
    BSF PORTC, 2
    CALL S_DLY
    BCF PORTC, 2
    MOVF temp_frac, W
    CALL H_TAB
    MOVWF PORTD
    BSF PORTC, 3
    CALL S_DLY
    BCF PORTC, 3
    RETURN

PREPARE_VAL:
    MOVF display_mode, W
    XORLW 0
    BTFSC STATUS, Z
    GOTO P_AMB
    MOVF display_mode, W
    XORLW 1
    BTFSC STATUS, Z
    GOTO P_TRG
    MOVF fan_int, W
    MOVWF DISPLAY_VAL
    RETURN
P_AMB: MOVF temp_actual, W
    MOVWF DISPLAY_VAL
    RETURN
P_TRG: MOVF temp_target, W
    MOVWF DISPLAY_VAL
    RETURN

READ_TEMP:
    BSF     ADCON0, GO
W_ADC: BTFSC ADCON0, GO
    GOTO W_ADC
    MOVF ADRESH, W
    MOVWF temp_actual
    BCF STATUS, C
    RLF temp_actual, F
    CLRF temp_frac
    RETURN

SPLIT_VAL:
    MOVF DISPLAY_VAL, W
    MOVWF ONES
    CLRF TENS
D_L: MOVLW d'10'
    SUBWF ONES, F
    BTFSS STATUS, C
    GOTO D_E
    INCF TENS, F
    GOTO D_L
D_E: MOVLW d'10'
    ADDWF ONES, F
    RETURN

S_DLY: MOVLW d'110'
    MOVWF DLY
DS: DECFSZ DLY, F
    GOTO DS
    RETURN

M_TAB: ADDWF PCL, F
    RETLW b'01110111' ; A
    RETLW b'01011110' ; D
    RETLW b'01110001' ; F

H_TAB: ADDWF PCL, F
    RETLW b'00111111' ;0
    RETLW b'00000110' ;1
    RETLW b'01011011' ;2
    RETLW b'01001111' ;3
    RETLW b'01100110' ;4
    RETLW b'01101101' ;5
    RETLW b'01111101' ;6
    RETLW b'00000111' ;7
    RETLW b'01111111' ;8
    RETLW b'01101111' ;9
    END
