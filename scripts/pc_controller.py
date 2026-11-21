"""
Optional PC Keyboard Controller for GALAGOOSE (Nexys A7 USB-UART Bridge).
Sends 1-byte packets {0x80 | mask} at 115200 8N1 over COMx:
  bit 0: UP    (W / Up Arrow)
  bit 1: DOWN  (S / Down Arrow)
  bit 2: LEFT  (A / Left Arrow)
  bit 3: RIGHT (D / Right Arrow)
  bit 4: FIRE/START (Space / Z / Enter)
Press ESC to quit.

Usage:
  python scripts/pc_controller.py COM5
"""
import sys
import time
import ctypes
from ctypes import wintypes

if len(sys.argv) < 2:
    print("Usage: python scripts/pc_controller.py <COM_PORT>  (e.g. COM5)")
    sys.exit(1)

port_name = sys.argv[1]

try:
    import serial
    ser = serial.Serial(port_name, 115200, timeout=0)
    def send_byte(b):
        ser.write(bytes([b]))
    def close_port():
        ser.close()
except ImportError:
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    GENERIC_WRITE = 0x40000000
    OPEN_EXISTING = 3
    INVALID_HANDLE_VALUE = ctypes.c_void_p(-1).value

    class DCB(ctypes.Structure):
        _fields_ = [
            ("DCBlength", wintypes.DWORD),
            ("BaudRate", wintypes.DWORD),
            ("fBinary", wintypes.DWORD, 1),
            ("fParity", wintypes.DWORD, 1),
            ("fOutxCtsFlow", wintypes.DWORD, 1),
            ("fOutxDsrFlow", wintypes.DWORD, 1),
            ("fDtrControl", wintypes.DWORD, 2),
            ("fDsrSensitivity", wintypes.DWORD, 1),
            ("fTXContinueOnXoff", wintypes.DWORD, 1),
            ("fOutX", wintypes.DWORD, 1),
            ("fInX", wintypes.DWORD, 1),
            ("fErrorChar", wintypes.DWORD, 1),
            ("fNull", wintypes.DWORD, 1),
            ("fRtsControl", wintypes.DWORD, 2),
            ("fAbortOnError", wintypes.DWORD, 1),
            ("fDummy2", wintypes.DWORD, 17),
            ("wReserved", wintypes.WORD),
            ("XonLim", wintypes.WORD),
            ("XoffLim", wintypes.WORD),
            ("ByteSize", ctypes.c_ubyte),
            ("Parity", ctypes.c_ubyte),
            ("StopBits", ctypes.c_ubyte),
            ("XonChar", ctypes.c_char),
            ("XoffChar", ctypes.c_char),
            ("ErrorChar", ctypes.c_char),
            ("EofChar", ctypes.c_char),
            ("EvtChar", ctypes.c_char),
            ("wReserved1", wintypes.WORD),
        ]

    handle = kernel32.CreateFileW(f"\\\\.\\{port_name}", GENERIC_WRITE, 0, None, OPEN_EXISTING, 0, None)
    if handle == INVALID_HANDLE_VALUE:
        raise OSError(f"Cannot open {port_name} (WinError {ctypes.get_last_error()})")

    dcb = DCB()
    dcb.DCBlength = ctypes.sizeof(DCB)
    kernel32.GetCommState(handle, ctypes.byref(dcb))
    dcb.BaudRate = 115200
    dcb.ByteSize = 8
    dcb.Parity = 0
    dcb.StopBits = 0
    kernel32.SetCommState(handle, ctypes.byref(dcb))

    def send_byte(b):
        buf = (ctypes.c_ubyte * 1)(b)
        written = wintypes.DWORD(0)
        kernel32.WriteFile(handle, buf, 1, ctypes.byref(written), None)

    def close_port():
        kernel32.CloseHandle(handle)

user32 = ctypes.WinDLL("user32")
VK_UP, VK_DOWN, VK_LEFT, VK_RIGHT = 0x26, 0x28, 0x25, 0x27
VK_W, VK_S, VK_A, VK_D = ord("W"), ord("S"), ord("A"), ord("D")
VK_SPACE, VK_Z, VK_RETURN, VK_ESCAPE = 0x20, ord("Z"), 0x0D, 0x1B

def pressed(vk):
    return (user32.GetAsyncKeyState(vk) & 0x8000) != 0

print(f"GALAGOOSE PC Controller connected on {port_name} @ 115200 8N1")
print("Controls: WASD or Arrow Keys = Move | Space / Z / Enter = Fire/Start | ESC = Exit")

try:
    while True:
        if pressed(VK_ESCAPE):
            send_byte(0x80)
            break
        mask = 0
        if pressed(VK_UP) or pressed(VK_W):
            mask |= 0x01
        if pressed(VK_DOWN) or pressed(VK_S):
            mask |= 0x02
        if pressed(VK_LEFT) or pressed(VK_A):
            mask |= 0x04
        if pressed(VK_RIGHT) or pressed(VK_D):
            mask |= 0x08
        if pressed(VK_SPACE) or pressed(VK_Z) or pressed(VK_RETURN):
            mask |= 0x10
        send_byte(0x80 | mask)
        time.sleep(0.015)
finally:
    close_port()
    print("Disconnected.")
