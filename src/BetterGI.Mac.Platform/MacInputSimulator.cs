using BetterGI.Mac.Platform;
using Vanara.PInvoke;

// Same namespace and class name as upstream's Fischless.WindowsInput.InputSimulator, so upstream code that
// does `new InputSimulator()` (Core/Simulator/Simulation.cs) gets the CGEvent implementation unchanged.
namespace Fischless.WindowsInput;

/// <summary>
/// macOS implementation of upstream's raw input layer (the SendInput wrapper on Windows).
/// </summary>
public sealed class InputSimulator : IInputSimulator, IKeyboardSimulator, IMouseSimulator, IInputDeviceStateAdaptor
{
    private readonly MacInput _input = new();

    public IKeyboardSimulator Keyboard => this;

    public IMouseSimulator Mouse => this;

    public IInputDeviceStateAdaptor InputDeviceState => this;

    #region keyboard

    public IKeyboardSimulator KeyDown(User32.VK keyCode)
    {
        _input.KeyDown(keyCode);
        return this;
    }

    public IKeyboardSimulator KeyDown(bool? isExtendedKey, User32.VK keyCode) => KeyDown(keyCode);

    public IKeyboardSimulator KeyUp(User32.VK keyCode)
    {
        _input.KeyUp(keyCode);
        return this;
    }

    public IKeyboardSimulator KeyUp(bool? isExtendedKey, User32.VK keyCode) => KeyUp(keyCode);

    public IKeyboardSimulator KeyPress(User32.VK keyCode)
    {
        // Down and up are posted back to back like SendInput; callers add their own delays.
        _input.KeyDown(keyCode);
        _input.KeyUp(keyCode);
        return this;
    }

    public IKeyboardSimulator KeyPress(bool? isExtendedKey, User32.VK keyCode) => KeyPress(keyCode);

    public IKeyboardSimulator KeyPress(params User32.VK[] keyCodes)
    {
        foreach (var key in keyCodes)
        {
            KeyPress(key);
        }

        return this;
    }

    public IKeyboardSimulator KeyPress(bool? isExtendedKey, params User32.VK[] keyCodes) => KeyPress(keyCodes);

    public IKeyboardSimulator ModifiedKeyStroke(IEnumerable<User32.VK> modifierKeyCodes, IEnumerable<User32.VK> keyCodes)
    {
        var modifiers = modifierKeyCodes.ToArray();
        foreach (var modifier in modifiers)
        {
            KeyDown(modifier);
        }

        foreach (var key in keyCodes)
        {
            KeyPress(key);
        }

        foreach (var modifier in modifiers.Reverse())
        {
            KeyUp(modifier);
        }

        return this;
    }

    public IKeyboardSimulator ModifiedKeyStroke(IEnumerable<User32.VK> modifierKeyCodes, User32.VK keyCode) =>
        ModifiedKeyStroke(modifierKeyCodes, [keyCode]);

    public IKeyboardSimulator ModifiedKeyStroke(User32.VK modifierKey, IEnumerable<User32.VK> keyCodes) =>
        ModifiedKeyStroke([modifierKey], keyCodes);

    public IKeyboardSimulator ModifiedKeyStroke(User32.VK modifierKeyCode, User32.VK keyCode) =>
        ModifiedKeyStroke([modifierKeyCode], [keyCode]);

    public IKeyboardSimulator TextEntry(string text)
    {
        if (!string.IsNullOrEmpty(text))
        {
            MacNative.bgi_type_text(text, text.Length);
        }

        return this;
    }

    public IKeyboardSimulator TextEntry(char character) => TextEntry(character.ToString());

    IKeyboardSimulator IKeyboardSimulator.Sleep(int millsecondsTimeout)
    {
        Thread.Sleep(millsecondsTimeout);
        return this;
    }

    IKeyboardSimulator IKeyboardSimulator.Sleep(TimeSpan timeout)
    {
        Thread.Sleep(timeout);
        return this;
    }

    #endregion

    #region mouse

    public IMouseSimulator MoveMouseBy(int pixelDeltaX, int pixelDeltaY)
    {
        _input.MoveMouseBy(pixelDeltaX, pixelDeltaY);
        return this;
    }

    /// <summary>Windows semantics: 0..65535 across the primary display.</summary>
    public IMouseSimulator MoveMouseTo(double absoluteX, double absoluteY)
    {
        MacNative.bgi_main_display_size(out var width, out var height);
        _input.MoveMouseToPoints(absoluteX / 65535d * width, absoluteY / 65535d * height);
        return this;
    }

    /// <summary>Windows semantics: 0..65535 across the bounding box of all displays.</summary>
    public IMouseSimulator MoveMouseToPositionOnVirtualDesktop(double absoluteX, double absoluteY)
    {
        MacNative.bgi_virtual_desktop_bounds(out var x, out var y, out var width, out var height);
        _input.MoveMouseToPoints(x + absoluteX / 65535d * width, y + absoluteY / 65535d * height);
        return this;
    }

    private IMouseSimulator Button(int button, bool down)
    {
        _input.MouseButton(button, down);
        return this;
    }

    private IMouseSimulator Click(int button, int times = 1)
    {
        for (var i = 0; i < times; i++)
        {
            _input.MouseButton(button, true);
            _input.MouseButton(button, false);
        }

        return this;
    }

    public IMouseSimulator LeftButtonDown() => Button(0, true);
    public IMouseSimulator LeftButtonUp() => Button(0, false);
    public IMouseSimulator LeftButtonClick() => Click(0);
    public IMouseSimulator LeftButtonDoubleClick() => Click(0, 2);
    public IMouseSimulator MiddleButtonDown() => Button(2, true);
    public IMouseSimulator MiddleButtonUp() => Button(2, false);
    public IMouseSimulator MiddleButtonClick() => Click(2);
    public IMouseSimulator MiddleButtonDoubleClick() => Click(2, 2);
    public IMouseSimulator RightButtonDown() => Button(1, true);
    public IMouseSimulator RightButtonUp() => Button(1, false);
    public IMouseSimulator RightButtonClick() => Click(1);
    public IMouseSimulator RightButtonDoubleClick() => Click(1, 2);
    public IMouseSimulator XButtonDown(int buttonId) => Button(2 + buttonId, true);
    public IMouseSimulator XButtonUp(int buttonId) => Button(2 + buttonId, false);
    public IMouseSimulator XButtonClick(int buttonId) => Click(2 + buttonId);
    public IMouseSimulator XButtonDoubleClick(int buttonId) => Click(2 + buttonId, 2);

    public IMouseSimulator VerticalScroll(int scrollAmountInClicks)
    {
        _input.VerticalScroll(scrollAmountInClicks);
        return this;
    }

    /// <summary>Not used by the game; kept for interface completeness.</summary>
    public IMouseSimulator HorizontalScroll(int scrollAmountInClicks) => this;

    IMouseSimulator IMouseSimulator.Sleep(int millsecondsTimeout)
    {
        Thread.Sleep(millsecondsTimeout);
        return this;
    }

    IMouseSimulator IMouseSimulator.Sleep(TimeSpan timeout)
    {
        Thread.Sleep(timeout);
        return this;
    }

    #endregion

    #region state

    public bool IsKeyDown(User32.VK keyCode) => MacInput.IsKeyDown(keyCode);

    public bool IsKeyUp(User32.VK keyCode) => !MacInput.IsKeyDown(keyCode);

    public bool IsHardwareKeyDown(User32.VK keyCode) => MacInput.IsKeyDown(keyCode);

    public bool IsHardwareKeyUp(User32.VK keyCode) => !MacInput.IsKeyDown(keyCode);

    /// <summary>Toggle state (Caps Lock etc.) is not queried on macOS.</summary>
    public bool IsTogglingKeyInEffect(User32.VK keyCode) => false;

    #endregion
}

/// <summary>Same values as upstream's VK2 (Fischless.WindowsInput/InputBuilder.cs).</summary>
public enum VK2
{
    VK_ENTER = User32.VK.VK_RETURN,

    /// <summary>The numeric-keypad ENTER key (extended-key flag on Windows).</summary>
    VK_NUMPAD_ENTER = 0x0E,
}
