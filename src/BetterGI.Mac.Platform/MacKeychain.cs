using System.Text.Json;

namespace BetterGI.Mac.Platform;

/// <summary>
/// Generic passwords in the user's login keychain (the macOS counterpart of Windows Credential Manager).
/// </summary>
public static class MacKeychain
{
    public static bool Set(string service, string account, string secret) =>
        MacNative.bgi_keychain_set(service, account, secret) != 0;

    public static (string Account, string Secret)? Get(string service)
    {
        var json = MacNative.TakeString(MacNative.bgi_keychain_get(service));
        if (string.IsNullOrEmpty(json))
        {
            return null;
        }

        using var document = JsonDocument.Parse(json);
        return (document.RootElement.GetProperty("account").GetString() ?? "",
            document.RootElement.GetProperty("secret").GetString() ?? "");
    }

    public static bool Delete(string service) => MacNative.bgi_keychain_delete(service) != 0;
}
