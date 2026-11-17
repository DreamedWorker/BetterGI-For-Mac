using System;
using System.Globalization;
using System.Linq;
using System.Reflection;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;

namespace BetterGI.Mac.Ui;

/// <summary>
/// Builds an editor for any settings object by reflection: one row per public read/write property of a
/// simple type (bool, number, string, enum). Upstream has several hundred options spread over dozens of
/// config and parameter classes; this shows all of them without a hand-written page for each.
/// </summary>
public static class PropertyGrid
{
    /// <param name="target">Object to edit; its properties are written directly.</param>
    /// <param name="changed">Called after a property was changed (save the config here).</param>
    public static Control Build(object target, Action? changed = null)
    {
        var panel = new StackPanel { Spacing = 2 };
        var type = target.GetType();
        var skipped = 0;
        foreach (var property in type.GetProperties(BindingFlags.Public | BindingFlags.Instance).OrderBy(p => p.MetadataToken))
        {
            if (!property.CanRead || property.GetIndexParameters().Length > 0)
            {
                continue;
            }

            var setter = property.GetSetMethod();
            var editor = setter is null ? null : CreateEditor(target, property, changed);
            if (editor is null)
            {
                if (setter != null)
                {
                    skipped++;
                }

                continue;
            }

            panel.Children.Add(Row(type, property, editor));
        }

        if (panel.Children.Count == 0)
        {
            panel.Children.Add(Hint("No simple options here."));
        }

        if (skipped > 0)
        {
            panel.Children.Add(Hint($"{skipped} more option(s) are lists or nested objects; they are kept as they are and can be edited in User/config.json."));
        }

        return panel;
    }

    private static Control Row(Type owner, PropertyInfo property, Control editor)
    {
        var description = ConfigDocs.Get(owner, property.Name);
        var texts = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 12, 0) };
        texts.Children.Add(new TextBlock { Text = description ?? property.Name, TextWrapping = TextWrapping.Wrap });
        if (description != null)
        {
            texts.Children.Add(Hint(property.Name));
        }

        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,230"), Margin = new Thickness(0, 5) };
        grid.Children.Add(texts);
        Grid.SetColumn(editor, 1);
        editor.VerticalAlignment = VerticalAlignment.Center;
        grid.Children.Add(editor);
        return grid;
    }

    private static TextBlock Hint(string text) =>
        new() { Text = text, Opacity = 0.6, FontSize = 11.5, TextWrapping = TextWrapping.Wrap };

    private static Control? CreateEditor(object target, PropertyInfo property, Action? changed)
    {
        var type = Nullable.GetUnderlyingType(property.PropertyType) ?? property.PropertyType;
        object? current;
        try
        {
            current = property.GetValue(target);
        }
        catch
        {
            return null; // a getter that needs services which are not available here
        }

        void Set(object? value)
        {
            try
            {
                property.SetValue(target, value);
                changed?.Invoke();
            }
            catch (Exception e)
            {
                AppLog.Warn($"{property.Name}: {e.GetBaseException().Message}");
            }
        }

        if (type == typeof(bool))
        {
            var toggle = new ToggleSwitch { IsChecked = current as bool? ?? false, OnContent = "", OffContent = "", HorizontalAlignment = HorizontalAlignment.Right };
            toggle.IsCheckedChanged += (_, _) => Set(toggle.IsChecked == true);
            return toggle;
        }

        if (type.IsEnum)
        {
            var combo = new ComboBox { ItemsSource = Enum.GetValues(type), SelectedItem = current, HorizontalAlignment = HorizontalAlignment.Stretch };
            combo.SelectionChanged += (_, _) =>
            {
                if (combo.SelectedItem != null)
                {
                    Set(combo.SelectedItem);
                }
            };
            return combo;
        }

        if (type == typeof(string))
        {
            var box = new TextBox { Text = current as string ?? "" };
            box.LostFocus += (_, _) =>
            {
                if (!Equals(box.Text ?? "", property.GetValue(target) as string ?? ""))
                {
                    Set(box.Text ?? "");
                }
            };
            return box;
        }

        if (type.IsPrimitive || type == typeof(decimal))
        {
            var box = new TextBox { Text = Convert.ToString(current, CultureInfo.InvariantCulture) ?? "" };
            box.LostFocus += (_, _) =>
            {
                var before = Convert.ToString(property.GetValue(target), CultureInfo.InvariantCulture) ?? "";
                if (box.Text == before)
                {
                    return;
                }

                try
                {
                    Set(Convert.ChangeType(box.Text, type, CultureInfo.InvariantCulture));
                }
                catch
                {
                    box.Text = before; // not a valid number: restore
                }
            };
            return box;
        }

        return null;
    }
}
