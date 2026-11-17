// Stand-ins for the few Windows Forms input types upstream's non-UI code mentions.
// Values are identical to the real ones (Keys == Win32 virtual-key codes), so conversions keep working.
using System;

namespace System.Windows.Forms
{
    [Flags]
    public enum Keys
    {
        None = 0,
        LButton = 1,
        RButton = 2,
        Cancel = 3,
        MButton = 4,
        XButton1 = 5,
        XButton2 = 6,
        Back = 8,
        Tab = 9,
        LineFeed = 10,
        Clear = 12,
        Return = 13,
        Enter = 13,
        ShiftKey = 16,
        ControlKey = 17,
        Menu = 18,
        Pause = 19,
        Capital = 20,
        CapsLock = 20,
        Escape = 27,
        Space = 32,
        Prior = 33,
        PageUp = 33,
        Next = 34,
        PageDown = 34,
        End = 35,
        Home = 36,
        Left = 37,
        Up = 38,
        Right = 39,
        Down = 40,
        Select = 41,
        Print = 42,
        Execute = 43,
        Snapshot = 44,
        PrintScreen = 44,
        Insert = 45,
        Delete = 46,
        Help = 47,
        LWin = 91,
        RWin = 92,
        Apps = 93,
        Sleep = 95,
        Multiply = 106,
        Add = 107,
        Separator = 108,
        Subtract = 109,
        Decimal = 110,
        Divide = 111,
        NumLock = 144,
        Scroll = 145,
        LShiftKey = 160,
        RShiftKey = 161,
        LControlKey = 162,
        RControlKey = 163,
        LMenu = 164,
        RMenu = 165,
        OemSemicolon = 186,
        Oem1 = 186,
        Oemplus = 187,
        Oemcomma = 188,
        OemMinus = 189,
        OemPeriod = 190,
        OemQuestion = 191,
        Oem2 = 191,
        Oemtilde = 192,
        Oem3 = 192,
        OemOpenBrackets = 219,
        Oem4 = 219,
        OemPipe = 220,
        Oem5 = 220,
        OemCloseBrackets = 221,
        Oem6 = 221,
        OemQuotes = 222,
        Oem7 = 222,
        Oem8 = 223,
        OemBackslash = 226,
        Oem102 = 226,
        KeyCode = 65535,
        Shift = 65536,
        Control = 131072,
        Alt = 262144,
        Modifiers = -65536,
        D0 = 48,
        NumPad0 = 96,
        D1 = 49,
        NumPad1 = 97,
        D2 = 50,
        NumPad2 = 98,
        D3 = 51,
        NumPad3 = 99,
        D4 = 52,
        NumPad4 = 100,
        D5 = 53,
        NumPad5 = 101,
        D6 = 54,
        NumPad6 = 102,
        D7 = 55,
        NumPad7 = 103,
        D8 = 56,
        NumPad8 = 104,
        D9 = 57,
        NumPad9 = 105,
        A = 65,
        B = 66,
        C = 67,
        D = 68,
        E = 69,
        F = 70,
        G = 71,
        H = 72,
        I = 73,
        J = 74,
        K = 75,
        L = 76,
        M = 77,
        N = 78,
        O = 79,
        P = 80,
        Q = 81,
        R = 82,
        S = 83,
        T = 84,
        U = 85,
        V = 86,
        W = 87,
        X = 88,
        Y = 89,
        Z = 90,
        F1 = 112,
        F2 = 113,
        F3 = 114,
        F4 = 115,
        F5 = 116,
        F6 = 117,
        F7 = 118,
        F8 = 119,
        F9 = 120,
        F10 = 121,
        F11 = 122,
        F12 = 123,
        F13 = 124,
        F14 = 125,
        F15 = 126,
        F16 = 127,
        F17 = 128,
        F18 = 129,
        F19 = 130,
        F20 = 131,
        F21 = 132,
        F22 = 133,
        F23 = 134,
        F24 = 135
    }

    [Flags]
    public enum MouseButtons
    {
        None = 0,
        Left = 0x100000,
        Right = 0x200000,
        Middle = 0x400000,
        XButton1 = 0x800000,
        XButton2 = 0x1000000,
    }

    public class KeyEventArgs(Keys keyData) : EventArgs
    {
        public Keys KeyData { get; } = keyData;
        public Keys KeyCode => KeyData & Keys.KeyCode;
        public Keys Modifiers => KeyData & Keys.Modifiers;
        public int KeyValue => (int)(KeyData & Keys.KeyCode);
        public bool Alt => (KeyData & Keys.Alt) != 0;
        public bool Control => (KeyData & Keys.Control) != 0;
        public bool Shift => (KeyData & Keys.Shift) != 0;
        public bool Handled { get; set; }
        public bool SuppressKeyPress { get; set; }
    }

    public delegate void KeyEventHandler(object? sender, KeyEventArgs e);

    public class MouseEventArgs(MouseButtons button, int clicks, int x, int y, int delta) : EventArgs
    {
        public MouseButtons Button { get; } = button;
        public int Clicks { get; } = clicks;
        public int X { get; } = x;
        public int Y { get; } = y;
        public int Delta { get; } = delta;
        public System.Drawing.Point Location => new(X, Y);
    }

    public enum MessageBoxIcon
    {
        None = 0,
        Error = 16,
        Question = 32,
        Warning = 48,
        Information = 64,
    }
}
