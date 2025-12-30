; PIC16F877A - 4MHz

    LIST    P=16F877A
    INCLUDE "P16F877A.INC"

    __CONFIG _FOSC_HS & _WDTE_OFF & _PWRTE_ON & _BOREN_OFF & _LVP_OFF & _CP_OFF

; Degiskenler
CBLOCK 0x20
    pot_son
    fark
    ldr_veri        ; LDR'den okunan deger
    yuzde           ; Hesaplanan yuzde
    sonuc_ldr       ; Isik sonucu
    sonuc_pot       ; Pot sonucu
    hedef_konum     ; Gitmek istedigimiz yer
    
    matematik_1     ; Carpma bolme icin
    matematik_2
    sayac
    
    sicaklik_tam    ; Sicaklik (tam kisim)
    sicaklik_onda   ; Sicaklik (ondalik)
    
    gelen_veri      ; UART'tan gelen
    gecici          ; Temp register
    
    adim_simdiki_L  ; Motorun su anki yeri
    adim_simdiki_H
    adim_hedef_L    ; Gidecegi yer
    adim_hedef_H
    
    motor_fazi      ; Step motor sirasi
    
    lcd_temp        ; LCD islemleri icin
    basamak_bir
    basamak_on
    basamak_yuz
    
    bekleme1        ; Gecikme donguleri icin
    bekleme2
    
    bmp_yuksek      ; Sensor verileri
    bmp_dusuk
    basinc_tam
    basinc_dusuk
    
    pc_modu         ; 1 ise PC kontrol ediyor
    lcd_sayaci      ; Ekrani cok hizli yenilememek icin
    
    i2c_veri
    ham_isi_H
    ham_isi_L
ENDC

; Program Baslangici
ORG 0x000
    GOTO AYARLAR

; ------------------------------------
; AYARLAR VE PORTLAR
; ------------------------------------
AYARLAR
    BSF STATUS, RP0     ; Bank 1'e gec
    
    MOVLW 0xFF          ; PortA hepsi giris (Sensorler burada)
    MOVWF TRISA
    
    CLRF TRISB          ; PortB hepsi cikis (LCD)
    CLRF TRISD          ; PortD hepsi cikis (Motor)
    
    ; I2C pinleri
    BSF TRISC, 3        ; SCL
    BSF TRISC, 4        ; SDA
    
    ; Seri haberlesme pinleri
    BSF TRISC, 7        ; RX (Giris)
    BCF TRISC, 6        ; TX (Cikis)

    ; Analog ayarlari
    MOVLW b'00000100'   ; AN0 ve AN1 analog olsun
    MOVWF ADCON1
    
    ; UART ayarlari (9600 baud rate)
    MOVLW d'25'
    MOVWF SPBRG
    MOVLW b'00100100'   ; Iletimi ac
    MOVWF TXSTA
    
    BCF STATUS, RP0     ; Bank 0'a don

    MOVLW b'10010000'   ; Alimi ac
    MOVWF RCSTA
    MOVLW b'10000001'   ; ADC'yi ac
    MOVWF ADCON0

    CLRF PORTB
    CLRF PORTD
    CLRF motor_fazi
    CLRF adim_simdiki_L
    CLRF adim_simdiki_H
    CLRF pc_modu   
    
    MOVLW d'255'
    MOVWF lcd_sayaci

    CALL Gecikme_Uzun
    CALL LCD_Hazirla
    CALL LCD_Temizle
    CALL I2C_Kurulum    ; Sensoru hazirla
    CALL Gecikme_Kisa

; ------------------------------------
; ANA DONGU BURADA DONER
; ------------------------------------
BASLA
    ; --- LDR OKUMA (Buras? ayn? kal?yor) ---
    MOVLW 0                 ; Kanal 0 sec (LDR)
    CALL ADC_Oku
    MOVWF ldr_veri
    CALL Yuzde_Hesapla
    MOVF yuzde,W
    MOVWF sonuc_ldr

    ; --- OTOMATIK KAPATMA (GECE MODU) ---
    MOVLW d'50'
    SUBWF sonuc_ldr,W
    BTFSS STATUS,C
    GOTO GECE_MODU

    ; ==========================================================
    ; YENI EKLENEN KISIM: POTANSIYOMETRE HAREKET KONTROLU
    ; ==========================================================
    
    ; 1. Potansiyometreyi her zaman oku (PC modunda olsak bile)
    MOVLW 1                 ; Kanal 1 sec (POT)
    CALL ADC_Oku
    MOVWF ldr_veri          ; Hesaplama fonksiyonu ldr_veri kullaniyor
    CALL Yuzde_Hesapla      ; Sonuc 'yuzde' degiskeninde
    
    ; Yonu ters cevirme islemi (Senin orijinal kodun)
    MOVF yuzde,W
    SUBLW d'100'
    MOVWF sonuc_pot         ; Su anki pot degeri sonuc_pot icinde
    
    ; 2. Eski de?er ile farka bak (Hareket var mi?)
    MOVF sonuc_pot, W
    SUBWF pot_son, W        ; W = pot_son - sonuc_pot
    MOVWF fark              ; Fark? sakla
    
    ; Fark negatif mi pozitif mi? Mutlak degerini alalim (ABS)
    BTFSS fark, 7           ; 7. bit 1 ise sayi negatiftir
    GOTO Fark_Pozitif
    
    ; Sayi negatifse tersini al (Two's complement)
    COMF fark, F
    INCF fark, F
    
Fark_Pozitif
    ; 3. Fark toleransin (örne?in 3 birim) üzerinde mi?
    MOVLW d'3'              ; Tolerans degeri (Titremeyi onlemek icin)
    SUBWF fark, W           ; W = fark - 3
    BTFSS STATUS, C         ; Eger Fark < 3 ise C=0 olur
    GOTO Pot_Hareket_Yok    ; Hareket yok, cik
    
    ; --- HAREKET VAR! ---
    ; Kullanici dugmeyi cevirdi, PC modunu iptal et!
    BCF pc_modu, 0          ; Kilidi kir
    
    ; Yeni degeri hafizaya al ki surekli fark algilamasin
    MOVF sonuc_pot, W
    MOVWF pot_son
    
Pot_Hareket_Yok
    ; ==========================================================
    
    ; Simdi PC kontrolunde miyiz diye bakabiliriz
    BTFSC pc_modu, 0
    GOTO SENSOR_ISLEMLERI   ; PC modundaysak motoru guncelleme

    ; PC modunda degilsek hedefi potansiyometre yap
    MOVF sonuc_pot, W
    MOVWF hedef_konum
    
    GOTO SENSOR_ISLEMLERI
GECE_MODU
    MOVLW d'100'        ; Perdeyi tam kapat
    MOVWF hedef_konum
    
SENSOR_ISLEMLERI
    ; Sensor ve haberlesme islemleri
    CALL Sensor_Oku
    CALL Seri_Haberlesme_Bak
    CALL Adim_Hesapla
    CALL Motoru_Hareket_Ettir

    ; LCD'yi her turda yazmiyoruz yavaslamasin diye
    DECFSZ lcd_sayaci, F
    GOTO BASLA
    
    CALL Ekrana_Yaz
    MOVLW d'50'         ; Sayaci sifirla
    MOVWF lcd_sayaci

    GOTO BASLA

; ------------------------------------
; MOTOR ISLEMLERI
; ------------------------------------
Adim_Hesapla
    ; Yuzdeyi 10 ile carpip adim sayisi yapiyoruz
    CLRF adim_hedef_H
    CLRF adim_hedef_L
    MOVF hedef_konum,W
    MOVWF sayac
    MOVF sayac,F
    BTFSC STATUS,Z
    RETURN
Carpma_Dongusu
    MOVLW d'10'
    ADDWF adim_hedef_L,F
    BTFSC STATUS,C
    INCF adim_hedef_H,F
    DECFSZ sayac,F
    GOTO Carpma_Dongusu
    RETURN

Motoru_Hareket_Ettir
    ; Hedefe geldik mi
    MOVF adim_hedef_H,W
    SUBWF adim_simdiki_H,W
    BTFSS STATUS,Z
    GOTO Farkli_Byte
    MOVF adim_hedef_L,W
    SUBWF adim_simdiki_L,W
    BTFSC STATUS,Z
    RETURN ; Esitse cik

    BTFSC STATUS,C
    GOTO Geri_Git
    GOTO Ileri_Git

Farkli_Byte
    BTFSC STATUS,C
    GOTO Geri_Git
    GOTO Ileri_Git

Ileri_Git
    INCF adim_simdiki_L,F
    BTFSC STATUS,Z
    INCF adim_simdiki_H,F
    INCF motor_fazi,F
    MOVLW d'4'
    SUBWF motor_fazi,W
    BTFSC STATUS,Z
    CLRF motor_fazi
    CALL Fazi_Uygula
    RETURN

Geri_Git
    MOVLW 1
    SUBWF adim_simdiki_L,F
    BTFSS STATUS,C
    DECF adim_simdiki_H,F
    DECF motor_fazi,F
    MOVLW 0xFF
    SUBWF motor_fazi,W
    BTFSC STATUS,Z
    GOTO Faz_3_Yap
    GOTO Fazi_Uygula
Faz_3_Yap
    MOVLW d'3'
    MOVWF motor_fazi
    CALL Fazi_Uygula
    RETURN

Fazi_Uygula
    MOVF motor_fazi,W
    CALL Faz_Tablosu
    MOVWF PORTD
    CALL Gecikme_Motor
    RETURN

Faz_Tablosu
    ADDWF PCL,F
    RETLW b'00000001'
    RETLW b'00000010'
    RETLW b'00000100'
    RETLW b'00001000'

Gecikme_Motor
    MOVLW d'10'
    MOVWF bekleme2
Dly_Loop
    MOVLW d'100'
    MOVWF bekleme1
Ic_Loop
    NOP
    DECFSZ bekleme1,F
    GOTO Ic_Loop
    DECFSZ bekleme2,F
    GOTO Dly_Loop
    RETURN

; ------------------------------------
; ADC ISLEMLERI
; ------------------------------------
Yuzde_Hesapla
    ; ADC degerini yuzdeye cevirir
    MOVF ldr_veri,W
    MOVWF sayac
    CLRF matematik_1
    CLRF matematik_2
    MOVF sayac,F
    BTFSC STATUS,Z
    GOTO Yuzde_100_Yap
Hesap_Don
    MOVLW d'101'
    ADDWF matematik_1,F
    BTFSC STATUS,C
    INCF matematik_2,F
    DECFSZ sayac,F
    GOTO Hesap_Don
    MOVF matematik_2,W
    SUBLW d'100'
    MOVWF yuzde
    RETURN
Yuzde_100_Yap
    MOVLW d'100'
    MOVWF yuzde
    RETURN

ADC_Oku
    ; Kanali secip okuma yapiyoruz
    ANDLW 0x07
    MOVWF lcd_temp
    BCF ADCON0,3
    BCF ADCON0,4
    BCF ADCON0,5
    BTFSC lcd_temp,0
    BSF ADCON0,3
    BTFSC lcd_temp,1
    BSF ADCON0,4
    BTFSC lcd_temp,2
    BSF ADCON0,5
    BSF ADCON0,ADON
    CALL Gecikme_Kisa
    BSF ADCON0,GO
Wait_ADC
    BTFSC ADCON0,GO
    GOTO Wait_ADC
    MOVF ADRESH,W
    RETURN

; ------------------------------------
; SERI HABERLESME (UART)
; ------------------------------------
Seri_Haberlesme_Bak
    BTFSC RCSTA,OERR        ; Hata var mi?
    CALL Seri_Reset
    
    BTFSS PIR1,RCIF         ; Veri geldi mi?
    RETURN
    
    MOVF RCREG,W            ; Veriyi al
    MOVWF gelen_veri
    
    ; PC'den gelen komutlari kontrol et
    MOVF gelen_veri, W
    ANDLW b'11000000'
    SUBLW b'11000000'
    BTFSC STATUS, Z
    GOTO Perde_Ayarla_PC
    
    MOVF gelen_veri, W
    ANDLW b'11000000'
    SUBLW b'10000000'
    BTFSC STATUS, Z
    GOTO Perde_Ayarla_Low

    ; Bilgi isteme komutlari
    MOVLW 0x01
    SUBWF gelen_veri, W
    BTFSC STATUS, Z
    GOTO Gonder_Perde_L
    
    MOVLW 0x02
    SUBWF gelen_veri, W
    BTFSC STATUS, Z
    GOTO Gonder_Perde_H
    
    MOVLW 0x03
    SUBWF gelen_veri, W
    BTFSC STATUS, Z
    GOTO Gonder_Temp_L
    
    MOVLW 0x04
    SUBWF gelen_veri, W
    BTFSC STATUS, Z
    GOTO Gonder_Temp_H
    
    MOVLW 0x05
    SUBWF gelen_veri, W
    BTFSC STATUS, Z
    GOTO Gonder_Basinc_L
    
    MOVLW 0x06
    SUBWF gelen_veri, W
    BTFSC STATUS, Z
    GOTO Gonder_Basinc_H
    
    MOVLW 0x08
    SUBWF gelen_veri, W
    BTFSC STATUS, Z
    GOTO Gonder_Isik
    RETURN

Perde_Ayarla_PC
    MOVF gelen_veri, W
    ANDLW b'00111111'
    IORWF hedef_konum, F ; Onceden gelen 64'luk degerle OR'la (Birle?tir)
    BSF pc_modu, 0
    RETURN

Perde_Ayarla_Low
    MOVF gelen_veri, W
    ANDLW b'00111111'
    MOVWF gecici        ; Gelen yüksek bitleri (64, 128 vb) geciciye al
    BCF STATUS, C
    RLF gecici, F       ; Sola kaydirarak 64 ile carpmis gibi olalim
    RLF gecici, F
    RLF gecici, F
    RLF gecici, F
    RLF gecici, F
    RLF gecici, F
    MOVF gecici, W
    MOVWF hedef_konum   ; hedef_konum artik 64 veya 0 oldu
    RETURN

Gonder_Perde_L
    MOVLW d'0'
    CALL Veri_Gonder
    RETURN
Gonder_Perde_H
    MOVF hedef_konum, W
    CALL Veri_Gonder
    RETURN
Gonder_Temp_L
    MOVF sicaklik_onda, W
    CALL Veri_Gonder
    RETURN
Gonder_Temp_H
    MOVF sicaklik_tam, W
    CALL Veri_Gonder
    RETURN
Gonder_Basinc_L
    MOVF basinc_dusuk, W
    CALL Veri_Gonder
    RETURN
Gonder_Basinc_H
    MOVF basinc_tam, W
    CALL Veri_Gonder
    RETURN
Gonder_Isik
    MOVF sonuc_ldr, W
    CALL Veri_Gonder
    RETURN

Veri_Gonder
    MOVWF gecici
    BSF STATUS, RP0
Bekle_TX
    BTFSS TXSTA, TRMT
    GOTO Bekle_TX
    BCF STATUS, RP0
    MOVF gecici, W
    MOVWF TXREG
    RETURN

Seri_Reset
    BCF RCSTA,CREN
    BSF RCSTA,CREN
    RETURN

; ------------------------------------
; I2C ISLEMLERI (Sensor icin)
; ------------------------------------
I2C_Kurulum
    BSF STATUS, RP0
    BSF TRISC, 3
    BSF TRISC, 4
    MOVLW d'9'
    MOVWF SSPADD
    BCF STATUS, RP0
    MOVLW b'00101000'
    MOVWF SSPCON
    RETURN

I2C_Basla
    BSF STATUS, RP0
    BSF SSPCON2, SEN
    BCF STATUS, RP0
I2C_Basla_Bekle
    BSF STATUS, RP0
    BTFSC SSPCON2, SEN
    GOTO I2C_Basla_Bekle
    BCF STATUS, RP0
    RETURN

I2C_Dur
    BSF STATUS, RP0
    BSF SSPCON2, PEN
    BCF STATUS, RP0
I2C_Dur_Bekle
    BSF STATUS, RP0
    BTFSC SSPCON2, PEN
    GOTO I2C_Dur_Bekle
    BCF STATUS, RP0
    RETURN

I2C_Yeniden_Basla
    BSF STATUS, RP0
    BSF SSPCON2, RSEN
    BCF STATUS, RP0
I2C_Yeniden_Bekle
    BSF STATUS, RP0
    BTFSC SSPCON2, RSEN
    GOTO I2C_Yeniden_Bekle
    BCF STATUS, RP0
    RETURN

I2C_Yaz
    MOVWF SSPBUF
I2C_Yaz_Bekle
    BTFSS PIR1, SSPIF
    GOTO I2C_Yaz_Bekle
    BCF PIR1, SSPIF
    BSF STATUS, RP0
    BTFSC SSPCON2, ACKSTAT
    BCF STATUS, Z
    BTFSS SSPCON2, ACKSTAT
    BSF STATUS, Z
    BCF STATUS, RP0
    RETURN

I2C_Oku
    BSF STATUS, RP0
    BSF SSPCON2, RCEN
    BCF STATUS, RP0
I2C_Oku_Bekle
    BSF STATUS, RP0
    BTFSC SSPCON2, RCEN
    GOTO I2C_Oku_Bekle
    BCF STATUS, RP0
    BTFSS PIR1, SSPIF
    GOTO I2C_Oku_Bekle
    BCF PIR1, SSPIF
    MOVF SSPBUF, W
    MOVWF i2c_veri
    RETURN

I2C_Onay_Ver
    BSF STATUS, RP0
    BCF SSPCON2, ACKDT
    BSF SSPCON2, ACKEN
    BCF STATUS, RP0
I2C_Onay_Bekle
    BSF STATUS, RP0
    BTFSC SSPCON2, ACKEN
    GOTO I2C_Onay_Bekle
    BCF STATUS, RP0
    RETURN

I2C_Onay_Verme
    BSF STATUS, RP0
    BSF SSPCON2, ACKDT
    BSF SSPCON2, ACKEN
    BCF STATUS, RP0
I2C_Onay_Verme_Bekle
    BSF STATUS, RP0
    BTFSC SSPCON2, ACKEN
    GOTO I2C_Onay_Verme_Bekle
    BCF STATUS, RP0
    RETURN

; ------------------------------------
; SENSOR OKUMA (BMP180)
; ------------------------------------
Sensor_Oku
    CALL Sicaklik_Oku
    CALL Gecikme_Kisa
    CALL Basinc_Oku
    RETURN

Sicaklik_Oku
    CALL I2C_Basla
    MOVLW 0xEE
    CALL I2C_Yaz
    MOVLW 0xF4
    CALL I2C_Yaz
    MOVLW 0x2E
    CALL I2C_Yaz
    CALL I2C_Dur
    
    CALL Gecikme_Kisa
    
    CALL I2C_Basla
    MOVLW 0xEE
    CALL I2C_Yaz
    MOVLW 0xF6
    CALL I2C_Yaz
    CALL I2C_Yeniden_Basla
    MOVLW 0xEF
    CALL I2C_Yaz
    
    CALL I2C_Oku
    MOVF i2c_veri, W
    MOVWF bmp_yuksek
    CALL I2C_Onay_Ver
    
    CALL I2C_Oku
    MOVF i2c_veri, W
    MOVWF bmp_dusuk
    CALL I2C_Onay_Verme
    CALL I2C_Dur
    
    ; Hesaplamalar (Basitlestirilmis)
    MOVF bmp_yuksek, W
    MOVWF ham_isi_H
    MOVF bmp_dusuk, W
    MOVWF ham_isi_L
    
    MOVF bmp_yuksek, W
    MOVWF sicaklik_tam
    RRF sicaklik_tam, F
    RRF sicaklik_tam, F
    RRF sicaklik_tam, F
    BCF sicaklik_tam, 7
    BCF sicaklik_tam, 6
    BCF sicaklik_tam, 5
    
    MOVF bmp_dusuk, W
    ANDLW 0x0F
    MOVWF sicaklik_onda
    
    ; Sayi duzenleme
    MOVLW d'10'
    SUBWF sicaklik_onda, W
    BTFSC STATUS, C
    MOVLW d'9'
    BTFSC STATUS, C
    MOVWF sicaklik_onda
    RETURN

Basinc_Oku
    CALL I2C_Basla
    MOVLW 0xEE
    CALL I2C_Yaz
    MOVLW 0xF4
    CALL I2C_Yaz
    MOVLW 0x34
    CALL I2C_Yaz
    CALL I2C_Dur
    
    CALL Gecikme_Kisa
    CALL Gecikme_Kisa
    
    CALL I2C_Basla
    MOVLW 0xEE
    CALL I2C_Yaz
    MOVLW 0xF6
    CALL I2C_Yaz
    CALL I2C_Yeniden_Basla
    MOVLW 0xEF
    CALL I2C_Yaz
    
    CALL I2C_Oku
    MOVF i2c_veri, W
    MOVWF bmp_yuksek
    CALL I2C_Onay_Ver
    
    CALL I2C_Oku
    MOVF i2c_veri, W
    MOVWF bmp_dusuk
    CALL I2C_Onay_Verme
    CALL I2C_Dur
    
    MOVF bmp_yuksek, W
    MOVWF basinc_tam
    
    BCF STATUS, C
    RLF basinc_tam, F
    RLF basinc_tam, F
    
    MOVLW d'225'
    ADDWF basinc_tam, F
    MOVLW d'0'
    MOVWF basinc_dusuk
    RETURN

; ------------------------------------
; LCD ISLEMLERI
; ------------------------------------
Ekrana_Yaz
    MOVLW 0x80
    CALL LCD_Komut
    
    ; Satir 1
    
    MOVF sicaklik_tam,W
    MOVWF yuzde
    CALL Sayi_Yaz
    MOVLW '.'
    CALL LCD_Veri
    MOVF sicaklik_onda,W
    ADDLW '0'
    CALL LCD_Veri
    MOVLW 0XDF
    CALL LCD_Veri
    MOVLW 'C'
    CALL LCD_Veri
    
    MOVLW ' '
    CALL LCD_Veri
    MOVLW ' '
    CALL LCD_Veri
    
    
    MOVF basinc_tam,W
    MOVWF yuzde
    CALL Sayi_Yaz
    MOVLW 'h'
    CALL LCD_Veri
    MOVLW 'P'
    CALL LCD_Veri
    MOVLW 'a'
    CALL LCD_Veri

    MOVLW 0xC0
    CALL LCD_Komut
    
    ; Satir 2
    MOVF sonuc_ldr,W
    MOVWF yuzde
    CALL Sayi_Yaz
    MOVLW 'L'
    CALL LCD_Veri
    MOVLW 'u'
    CALL LCD_Veri
    MOVLW 'x'
    CALL LCD_Veri
    
    MOVLW ' '
    CALL LCD_Veri
    
    MOVF hedef_konum,W
    MOVWF yuzde
    CALL Sayi_Yaz
    
    MOVLW '.'
    CALL LCD_Veri
    MOVLW '0'
    CALL LCD_Veri
    MOVLW '%'
    CALL LCD_Veri
    RETURN

Sayi_Yaz
    ; 3 basamakli sayiyi ekrana yazar
    MOVLW d'100'
    SUBWF yuzde,W
    BTFSC STATUS,C
    GOTO Yuz_Var
    CLRF basamak_on
    MOVF yuzde,W
    MOVWF basamak_bir
    MOVLW '0'
    CALL LCD_Veri
Bolme_Islemi
    MOVLW d'10'
    SUBWF basamak_bir,W
    BTFSS STATUS,C
    GOTO Rakamlari_Yaz
    MOVWF basamak_bir
    INCF basamak_on,F
    GOTO Bolme_Islemi
Rakamlari_Yaz
    MOVF basamak_on,W
    ADDLW '0'
    CALL LCD_Veri
    MOVF basamak_bir,W
    ADDLW '0'
    CALL LCD_Veri
    RETURN
Yuz_Var
    MOVLW '1'
    CALL LCD_Veri
    MOVLW '0'
    CALL LCD_Veri
    MOVLW '0'
    CALL LCD_Veri
    RETURN

LCD_Komut
    MOVWF lcd_temp
    ANDLW 0xF0
    MOVWF PORTB
    BCF PORTB,1
    NOP
    BSF PORTB,2
    CALL Gecikme_Kisa
    BCF PORTB,2
    SWAPF lcd_temp,W
    ANDLW 0xF0
    MOVWF PORTB
    BCF PORTB,1
    NOP
    BSF PORTB,2
    CALL Gecikme_Kisa
    BCF PORTB,2
    RETURN

LCD_Veri
    MOVWF lcd_temp
    ANDLW 0xF0
    MOVWF PORTB
    BSF PORTB,1
    NOP
    BSF PORTB,2
    CALL Gecikme_Kisa
    BCF PORTB,2
    SWAPF lcd_temp,W
    ANDLW 0xF0
    MOVWF PORTB
    BSF PORTB,1
    NOP
    BSF PORTB,2
    CALL Gecikme_Kisa
    BCF PORTB,2
    RETURN

LCD_Hazirla
    MOVLW 0x30
    CALL LCD_Nibble
    CALL Gecikme_Kisa
    MOVLW 0x30
    CALL LCD_Nibble
    CALL Gecikme_Kisa
    MOVLW 0x20
    CALL LCD_Nibble
    CALL Gecikme_Kisa
    MOVLW 0x28
    CALL LCD_Komut
    MOVLW 0x0C
    CALL LCD_Komut
    MOVLW 0x06
    CALL LCD_Komut
    RETURN

LCD_Nibble
    MOVWF PORTB
    BSF PORTB,2
    NOP
    BCF PORTB,2
    RETURN

LCD_Temizle
    MOVLW 0x01
    CALL LCD_Komut
    CALL Gecikme_Uzun
    RETURN

; ------------------------------------
; BEKLEME FONKSIYONLARI
; ------------------------------------
Gecikme_Kisa
    MOVLW d'50'
    MOVWF bekleme1
D1  
    DECFSZ bekleme1,F
    GOTO D1
    RETURN

Gecikme_Uzun
    MOVLW d'100'
    MOVWF bekleme2
L1  
    MOVLW d'255'
    MOVWF bekleme1
L2  
    DECFSZ bekleme1,F
    GOTO L2
    DECFSZ bekleme2,F
    GOTO L1
    RETURN

    END