using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;

namespace BetterGI.Mac.Ui;

/// <summary>
/// Upstream's own doc comments for config and task-parameter properties (Assets/config-docs.json,
/// generated from upstream's source by scripts/extract-upstream-members.py).
/// </summary>
public static class ConfigDocs
{
    private static readonly Lazy<Dictionary<string, Dictionary<string, string>>> Docs = new(Load);

    /// <summary>Description of a property, looked up on the type and then its base types; null when none.</summary>
    public static string? Get(Type type, string property)
    {
        for (var current = type; current != null && current != typeof(object); current = current.BaseType)
        {
            if (Docs.Value.TryGetValue(current.Name, out var members) && members.TryGetValue(property, out var text)
                                                                      && !string.IsNullOrWhiteSpace(text))
            {
                return text;
            }
        }

        return null;
    }

    private static Dictionary<string, Dictionary<string, string>> Load()
    {
        try
        {
            var path = Path.Combine(AppContext.BaseDirectory, "Assets", "config-docs.json");
            return JsonSerializer.Deserialize<Dictionary<string, Dictionary<string, string>>>(File.ReadAllText(path)) ?? [];
        }
        catch
        {
            return []; // descriptions are optional: property names are shown instead
        }
    }
}
