import serial
import time
import tkinter as tk
from tkinter import messagebox, ttk

# --- RENK PALETİ VE STİL ---
COLORS = {
    "bg_main": "#1e1e1e",      # Koyu Arka Plan
    "bg_card": "#2d2d2d",      # Kart Arka Planı
    "accent_blue": "#0078d4",  # Windows Mavisi
    "accent_green": "#28a745", # Perde Yeşili
    "text_main": "#ffffff",    # Ana Beyaz Metin
    "text_dim": "#aaaaaa",     # Soluk Gri Metin
    "btn_hover": "#3a3a3a",    # Buton Üzerine Gelince
    "error": "#d13438"         # Hata Kırmızı
}

# --- API KATMANI ---

class HomeAutomationSystemConnection:
    """Temel seri port bağlantı sınıfı"""
    def __init__(self, port, baud=9600):
        self.comPort = port
        self.baudRate = baud
        self.ser = None

    def open(self):
        """Bağlantıyı açar"""
        if self.ser and self.ser.is_open:
            return True
        try:
            self.ser = serial.Serial(self.comPort, self.baudRate, timeout=0.5)
            return True
        except Exception as e:
            print(f"Baglanti Hatasi: {e}")
            return False

    def close(self):
        """Bağlantıyı kapatır"""
        if self.ser and self.ser.is_open:
            self.ser.close()

class AirConditionerSystemConnection(HomeAutomationSystemConnection):
    """Board 1 (Klima/Isı Sistemi) için API sınıfı"""
    def __init__(self, port="COM11"):
        super().__init__(port)
        self.ambientTemperature = 0.0
        self.desiredTemperatureFromPic = 0.0
        self.fanSpeed = 0

    def update(self):
        """PIC'den güncel verileri sorgular"""
        if not self.ser or not self.ser.is_open: return
        try:
            # 1. Gerçek Sıcaklığı Oku (PIC'den 0x04 ve 0x03 iste)
            self.ser.write(b'\x04')
            h = int.from_bytes(self.ser.read(1), "big")
            self.ser.write(b'\x03')
            l = int.from_bytes(self.ser.read(1), "big")
            self.ambientTemperature = h + (l / 10.0)

            # 2. Hedef Sıcaklığı Oku (PIC'den 0x06 iste)
            self.ser.write(b'\x06')
            self.desiredTemperatureFromPic = int.from_bytes(self.ser.read(1), "big")

            # 3. Fan Hızını Oku (PIC'den 0x05 iste)
            self.ser.write(b'\x05')
            self.fanSpeed = int.from_bytes(self.ser.read(1), "big")
        except: pass

    def setDesiredTemp(self, temp: float):
        """PIC'e yeni hedef sıcaklık gönderir"""
        if not (10.0 <= temp <= 50.0): return False
        integral = int(temp)
        # Komut protokolü: 11xxxxxx (ilk iki bit 1, kalan 6 bit değer)
        cmd = 0b11000000 | (integral & 0x3F)
        if self.ser and self.ser.is_open:
            self.ser.write(bytes([cmd]))
            return True
        return False

class CurtainControlSystemConnection(HomeAutomationSystemConnection):
    """Board 2 (Perde/Sensör Sistemi) için API sınıfı"""
    def __init__(self, port="COM9"):
        super().__init__(port)
        self.curtainStatus = 0.0
        self.outdoorTemp = 0.0
        self.outdoorPress = 0.0
        self.lightIntensity = 0.0

    def update(self):
        """Perde sistemi sensör verilerini günceller"""
        if not self.ser or not self.ser.is_open: return
        try:
            self.ser.write(b'\x02')
            self.curtainStatus = float(int.from_bytes(self.ser.read(1), "big"))
            self.ser.write(b'\x04')
            self.outdoorTemp = float(int.from_bytes(self.ser.read(1), "big"))
            self.ser.write(b'\x06')
            self.outdoorPress = float(int.from_bytes(self.ser.read(1), "big"))
            self.ser.write(b'\x08')
            self.lightIntensity = float(int.from_bytes(self.ser.read(1), "big"))
        except: pass

    def setCurtainStatus(self, status: float):
        """Perde açıklık oranını ayarlar"""
        if not (0.0 <= status <= 100.0): return False
        val = int(status)
        low_part = val & 0x3F
        high_part = (val >> 6) & 0x3F
        cmd_low = 0b11000000 | low_part
        cmd_high = 0b10000000 | high_part
        if self.ser and self.ser.is_open:
            self.ser.write(bytes([cmd_high]))
            time.sleep(0.05)
            self.ser.write(bytes([cmd_low]))
            return True
        return False

# --- GUI KATMANI ---

class AppGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("ESOGU HomeSense v2.0")
        self.root.geometry("500x700")
        self.root.configure(bg=COLORS["bg_main"])
        
        self.ac_api = AirConditionerSystemConnection()
        self.curtain_api = CurtainControlSystemConnection()
        
        self.active_api = None
        self.timer_id = None
        
        self.main_menu()

    def main_menu(self):
        self.ac_api.close()
        self.curtain_api.close()
        self.active_api = None
        self.clear_frame()
        
        header = tk.Label(self.root, text="🏠 HOME AUTOMATION", font=("Segoe UI Bold", 18), bg=COLORS["bg_main"], fg=COLORS["text_main"])
        header.pack(pady=(50, 10))
        
        sub_header = tk.Label(self.root, text="Yönetmek istediğiniz sistemi seçin", font=("Segoe UI", 10), bg=COLORS["bg_main"], fg=COLORS["text_dim"])
        sub_header.pack(pady=(0, 40))
        
        self.create_modern_button(self.root, "🌬️  AIR CONDITIONER SYSTEM", self.ac_screen).pack(pady=10, fill="x", padx=60)
        self.create_modern_button(self.root, "🪟  CURTAIN CONTROL SYSTEM", self.curtain_screen, COLORS["accent_green"]).pack(pady=10, fill="x", padx=60)
        
        exit_btn = tk.Button(self.root, text="✕  EXIT", command=self.root.quit, bg=COLORS["bg_main"], fg=COLORS["error"], relief="flat", font=("Segoe UI Semibold", 10), cursor="hand2")
        exit_btn.pack(side="bottom", pady=40)

    def ac_screen(self):
        self.clear_frame()
        if self.ac_api.open():
            self.active_api = self.ac_api
            tk.Label(self.root, text="AIR CONDITIONER CONTROL", font=("Segoe UI Bold", 14), bg=COLORS["bg_main"], fg=COLORS["text_main"]).pack(pady=30)
            
            # Veri Kartı
            card = tk.Frame(self.root, bg=COLORS["bg_card"], padx=20, pady=20)
            card.pack(fill="x", padx=40)
            
            # Ambient Temp
            tk.Label(card, text="Ambient Temp", bg=COLORS["bg_card"], fg=COLORS["text_dim"], font=("Segoe UI", 10)).grid(row=0, column=0, sticky="w")
            self.lbl_ac_temp = tk.Label(card, text="--°C", bg=COLORS["bg_card"], fg=COLORS["accent_blue"], font=("Segoe UI Bold", 24))
            self.lbl_ac_temp.grid(row=1, column=0, sticky="w", pady=(0, 10))
            
            # Desired Temp (PIC'den gelen)
            tk.Label(card, text="Target (PIC)", bg=COLORS["bg_card"], fg=COLORS["text_dim"], font=("Segoe UI", 10)).grid(row=0, column=1, sticky="w", padx=(30, 0))
            self.lbl_ac_desired = tk.Label(card, text="--°C", bg=COLORS["bg_card"], fg=COLORS["accent_green"], font=("Segoe UI Bold", 24))
            self.lbl_ac_desired.grid(row=1, column=1, sticky="w", padx=(30, 0), pady=(0, 10))

            # Fan Speed
            tk.Label(card, text="Fan Speed", bg=COLORS["bg_card"], fg=COLORS["text_dim"], font=("Segoe UI", 10)).grid(row=2, column=0, sticky="w")
            self.lbl_ac_fan = tk.Label(card, text="-- rps", bg=COLORS["bg_card"], fg=COLORS["text_main"], font=("Segoe UI Bold", 20))
            self.lbl_ac_fan.grid(row=3, column=0, sticky="w")

            tk.Label(self.root, text="Set Desired Temp (10.0 - 50.0)", bg=COLORS["bg_main"], fg=COLORS["text_dim"], font=("Segoe UI", 10)).pack(pady=(30, 5))
            self.entry = tk.Entry(self.root, font=("Segoe UI", 14), bg=COLORS["bg_card"], fg="white", insertbackground="white", relief="flat", justify="center")
            self.entry.pack(pady=5, padx=100, fill="x")
            
            self.create_modern_button(self.root, "UPDATE TEMPERATURE", self.send_ac).pack(pady=20, padx=100, fill="x")
            self.create_modern_button(self.root, "← RETURN TO MENU", self.main_menu, COLORS["bg_card"]).pack(pady=10)
            
            self.start_timer()
        else:
            messagebox.showerror("Error", "Could not connect to Board 1 (COM11)")
            self.main_menu()

    def curtain_screen(self):
        self.clear_frame()
        if self.curtain_api.open():
            self.active_api = self.curtain_api
            tk.Label(self.root, text="CURTAIN & SENSOR MONITOR", font=("Segoe UI Bold", 14), bg=COLORS["bg_main"], fg=COLORS["text_main"]).pack(pady=30)
            
            grid_frame = tk.Frame(self.root, bg=COLORS["bg_main"])
            grid_frame.pack(pady=10)
            
            self.lbl_out_temp = self.create_sensor_label(grid_frame, "Outdoor Temp", 0, 0)
            self.lbl_press = self.create_sensor_label(grid_frame, "Air Pressure", 0, 1)
            self.lbl_light = self.create_sensor_label(grid_frame, "Light Level", 1, 0)
            self.lbl_curt_stat = self.create_sensor_label(grid_frame, "Curtain Stat", 1, 1)

            tk.Label(self.root, text="Set Curtain Openness (0 - 100%)", bg=COLORS["bg_main"], fg=COLORS["text_dim"], font=("Segoe UI", 10)).pack(pady=(30, 5))
            self.entry = tk.Entry(self.root, font=("Segoe UI", 14), bg=COLORS["bg_card"], fg="white", insertbackground="white", relief="flat", justify="center")
            self.entry.pack(pady=5, padx=100, fill="x")
            
            self.create_modern_button(self.root, "APPLY STATUS", self.send_curtain, COLORS["accent_green"]).pack(pady=20, padx=100, fill="x")
            self.create_modern_button(self.root, "← RETURN TO MENU", self.main_menu, COLORS["bg_card"]).pack(pady=10)
            
            self.start_timer()
        else:
            messagebox.showerror("Error", "Could not connect to Board 2 (COM9)")
            self.main_menu()

    # --- YARDIMCI METODLAR ---
    def start_timer(self):
        if self.active_api:
            self.active_api.update()
            self.refresh_labels()
            self.timer_id = self.root.after(1000, self.start_timer)

    def refresh_labels(self):
        try:
            if self.active_api == self.ac_api:
                self.lbl_ac_temp.config(text=f"{self.ac_api.ambientTemperature:.1f}°C")
                self.lbl_ac_desired.config(text=f"{self.ac_api.desiredTemperatureFromPic}°C")
                self.lbl_ac_fan.config(text=f"{self.ac_api.fanSpeed} rps")
            elif self.active_api == self.curtain_api:
                self.lbl_out_temp.config(text=f"🌡️ {self.curtain_api.outdoorTemp:.1f} °C")
                self.lbl_press.config(text=f"📉 {self.curtain_api.outdoorPress:.0f} hPa")
                self.lbl_light.config(text=f"☀️ {self.curtain_api.lightIntensity:.0f} Lux")
                self.lbl_curt_stat.config(text=f"🪟 {self.curtain_api.curtainStatus:.1f}% ")
        except: pass

    def send_ac(self):
        try:
            val = float(self.entry.get())
            if self.ac_api.setDesiredTemp(val):
                messagebox.showinfo("Success", f"Target set to {val}°C")
            else:
                messagebox.showwarning("Range Error", "Please enter 10.0 to 50.0")
        except: messagebox.showerror("Input Error", "Invalid format")

    def send_curtain(self):
        try:
            val = float(self.entry.get())
            if self.curtain_api.setCurtainStatus(val):
                messagebox.showinfo("Success", f"Curtain set to {val}%")
            else: messagebox.showwarning("Range Error", "0 to 100 required")
        except: messagebox.showerror("Input Error", "Invalid format")

    def create_modern_button(self, parent, text, command, color=COLORS["accent_blue"]):
        btn = tk.Button(parent, text=text, command=command, bg=color, fg=COLORS["text_main"], relief="flat", font=("Segoe UI Semibold", 10), padx=20, pady=10, cursor="hand2")
        return btn

    def create_sensor_label(self, parent, title, r, c):
        f = tk.Frame(parent, bg=COLORS["bg_card"], padx=15, pady=15, width=180, height=80)
        f.grid(row=r, column=c, padx=10, pady=10)
        f.pack_propagate(False)
        tk.Label(f, text=title, bg=COLORS["bg_card"], fg=COLORS["text_dim"], font=("Segoe UI", 8)).pack(anchor="w")
        lbl = tk.Label(f, text="--", bg=COLORS["bg_card"], fg="white", font=("Segoe UI Bold", 11))
        lbl.pack(anchor="w")
        return lbl

    def clear_frame(self):
        if self.timer_id: self.root.after_cancel(self.timer_id)
        for w in self.root.winfo_children(): w.destroy()

if __name__ == "__main__":
    root = tk.Tk()
    # DPI Awareness (Daha net fontlar için)
    try:
        from ctypes import windll
        windll.shcore.SetProcessDpiAwareness(1)
    except: pass
    AppGUI(root)
    root.mainloop()