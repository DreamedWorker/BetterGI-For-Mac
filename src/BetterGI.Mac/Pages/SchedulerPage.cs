using System;
using System.Collections.Generic;
using System.Dynamic;
using System.IO;
using System.Linq;
using System.Text.Json;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Script.Group;
using BetterGenshinImpact.Core.Script.Project;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.Model;
using BetterGenshinImpact.Service.Interface;
using BetterGenshinImpact.ViewModel.Pages;
using BetterGI.Mac.Ui;
using Microsoft.Extensions.DependencyInjection;

namespace BetterGI.Mac.Pages;

/// <summary>
/// Scheduler (调度器): upstream's script groups. A group is an ordered list of JS scripts, pathing routes,
/// key-mouse macros and shell commands, stored as User/ScriptGroup/&lt;name&gt;.json in upstream's format and
/// run by upstream's ScriptService, so groups are interchangeable with the Windows version.
/// </summary>
public static class SchedulerPage
{
    private static string GroupFolder => Global.Absolute(@"User\ScriptGroup");

    public static Control Build(CoreSession core)
    {
        var scriptService = core.Services.GetRequiredService<IScriptService>();
        var groups = new List<ScriptGroup>();
        ScriptGroup? current = null;

        var groupList = new ListBox();
        var projectList = new ListBox { Height = 250 };
        var projectDetails = new ContentControl();
        var groupTitle = new TextBlock { FontSize = 15, FontWeight = FontWeight.SemiBold };
        var newName = new TextBox { Watermark = "New group name", Width = 170 };
        var addKind = new ComboBox { ItemsSource = new[] { "JS 脚本", "地图追踪 (folder)", "键鼠脚本", "Shell" }, SelectedIndex = 0, Width = 150 };
        var addChoice = new ComboBox { Width = 300 };
        var addText = new TextBox { Watermark = "shell command", Width = 300, IsVisible = false };

        void Save(ScriptGroup group)
        {
            Directory.CreateDirectory(GroupFolder);
            ScriptGroup.ResetGroupInfo(group);
            group.WriteToFileAtomically(Path.Combine(GroupFolder, group.Name + ".json"));
        }

        void ShowProjects()
        {
            groupTitle.Text = current is null ? "Select or create a group" : current.Name;
            projectDetails.Content = null;
            if (current is null)
            {
                projectList.ItemsSource = null;
                return;
            }

            var index = 0;
            projectList.ItemsSource = current.Projects.Select(p => PageUi.TwoLine(
                $"{++index}. {p.Name}",
                $"{Describe(ScriptGroupProjectExtensions.TypeDescriptions, p.Type)} · {Describe(ScriptGroupProjectExtensions.StatusDescriptions, p.Status)} · {p.ScheduleDesc} · ×{p.RunNum}"
                + (string.IsNullOrEmpty(p.FolderName) || p.Type == "Javascript" ? "" : " · " + p.FolderName))).ToList();
        }

        void LoadGroups(string? select = null)
        {
            groups.Clear();
            Directory.CreateDirectory(GroupFolder);
            foreach (var file in Directory.GetFiles(GroupFolder, "*.json").OrderBy(f => f))
            {
                try
                {
                    var group = ScriptGroup.FromJson(File.ReadAllText(file));
                    ScriptGroup.ResetGroupInfo(group);
                    groups.Add(group);
                }
                catch (Exception e)
                {
                    AppLog.Warn($"配置组 {Path.GetFileName(file)} 读取失败：{e.GetBaseException().Message}");
                }
            }

            groups.Sort((a, b) => a.Index.CompareTo(b.Index));
            groupList.ItemsSource = groups.Select(g => PageUi.TwoLine(g.Name, $"{g.Projects.Count} item(s)")).ToList();
            current = groups.FirstOrDefault(g => g.Name == select) ?? groups.FirstOrDefault();
            groupList.SelectedIndex = current is null ? -1 : groups.IndexOf(current);
            ShowProjects();
        }

        void RefreshChoices()
        {
            addText.IsVisible = addKind.SelectedIndex == 3;
            addChoice.IsVisible = !addText.IsVisible;
            IEnumerable<string> choices = addKind.SelectedIndex switch
            {
                0 => SafeDirectories(Global.ScriptPath()).Select(d => d.Name),
                1 => PathingFolders(),
                2 => SafeFiles(Global.Absolute(@"User\KeyMouseScript"), "*.json").Select(f => f.Name),
                _ => [],
            };
            addChoice.ItemsSource = choices.ToList();
            addChoice.SelectedIndex = addChoice.ItemCount > 0 ? 0 : -1;
        }

        void AddProject()
        {
            if (current is null)
            {
                AppLog.Warn("Create or select a group first.");
                return;
            }

            var choice = addChoice.SelectedItem as string;
            switch (addKind.SelectedIndex)
            {
                case 0 when choice != null:
                    current.AddProject(new ScriptGroupProject(new ScriptProject(choice)));
                    break;
                case 1 when choice != null:
                    // like upstream: one project per route file in the folder
                    var folder = Path.Combine(MapPathingViewModel.PathJsonPath, choice == "." ? "" : choice);
                    foreach (var file in SafeFiles(folder, "*.json"))
                    {
                        current.AddProject(ScriptGroupProject.BuildPathingProject(file.Name, choice == "." ? "" : choice));
                    }

                    break;
                case 2 when choice != null:
                    current.AddProject(ScriptGroupProject.BuildKeyMouseProject(choice));
                    break;
                case 3 when !string.IsNullOrWhiteSpace(addText.Text):
                    current.AddProject(ScriptGroupProject.BuildShellProject(addText.Text!));
                    break;
                default:
                    return;
            }

            Save(current);
            LoadGroups(current.Name);
        }

        void EditProject(Action<ScriptGroup, int> edit)
        {
            if (current is null || projectList.SelectedIndex < 0)
            {
                return;
            }

            var index = projectList.SelectedIndex;
            edit(current, index);
            Save(current);
            var name = current.Name;
            LoadGroups(name);
            projectList.SelectedIndex = Math.Min(index, projectList.ItemCount - 1);
        }

        groupList.SelectionChanged += (_, _) =>
        {
            if (groupList.SelectedIndex >= 0 && groupList.SelectedIndex < groups.Count)
            {
                current = groups[groupList.SelectedIndex];
                ShowProjects();
            }
        };
        addKind.SelectionChanged += (_, _) => RefreshChoices();
        projectList.SelectionChanged += (_, _) =>
        {
            if (current is null || projectList.SelectedIndex < 0 || projectList.SelectedIndex >= current.Projects.Count)
            {
                projectDetails.Content = null;
                return;
            }

            var group = current;
            projectDetails.Content = ProjectEditor(group.Projects[projectList.SelectedIndex], () => Save(group));
        };

        var left = new StackPanel
        {
            Spacing = 8,
            Children =
            {
                groupList,
                PageUi.Row(newName, PageUi.Button("新建 New", () =>
                {
                    var name = (newName.Text ?? "").Trim();
                    if (name.Length == 0 || name.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0 || groups.Any(g => g.Name == name))
                    {
                        AppLog.Warn("Enter a new, valid group name.");
                        return;
                    }

                    Save(new ScriptGroup { Name = name, Index = groups.Count });
                    newName.Text = "";
                    LoadGroups(name);
                })),
                PageUi.Button("删除配置组 Delete group", () =>
                {
                    if (current is null)
                    {
                        return;
                    }

                    File.Delete(Path.Combine(GroupFolder, current.Name + ".json"));
                    AppLog.Info($"Deleted group {current.Name}");
                    LoadGroups();
                }),
            },
        };

        var right = new StackPanel
        {
            Spacing = 8,
            Margin = new Thickness(16, 0, 0, 0),
            Children =
            {
                groupTitle,
                PageUi.Row(
                    PageUi.Button("运行配置组 Run group", () =>
                    {
                        if (current is null)
                        {
                            return System.Threading.Tasks.Task.CompletedTask;
                        }

                        var group = current;
                        RunnerContext.Instance.Reset();
                        return new TaskRunner().RunThreadAsync((runtime, ct) =>
                            scriptService.RunMulti(runtime, ScriptControlViewModel.GetNextProjects(group), group.Name, ct));
                    }, accent: true),
                    PageUi.Button("停止 Stop", () => PageUi.StopAll(core)),
                    PageUi.Button("配置组设置 Group settings", () =>
                    {
                        if (current is null)
                        {
                            return;
                        }

                        var group = current;
                        projectList.SelectedIndex = -1;
                        projectDetails.Content = GroupSettings(group, () => Save(group));
                    })),
                projectList,
                PageUi.Row(
                    PageUi.Button("↑", () => EditProject((g, i) => { if (i > 0) g.Projects.Move(i, i - 1); })),
                    PageUi.Button("↓", () => EditProject((g, i) => { if (i < g.Projects.Count - 1) g.Projects.Move(i, i + 1); })),
                    PageUi.Button("移除 Remove", () => EditProject((g, i) => g.Projects.RemoveAt(i))),
                    PageUi.Button("从此处开始 Start from here", () => EditProject((g, i) =>
                    {
                        // upstream's "next" marker: the next run of the group begins at this item
                        for (var k = 0; k < g.Projects.Count; k++)
                        {
                            g.Projects[k].NextFlag = k == i;
                        }
                    }))),
                PageUi.Row(addKind, addChoice, addText, PageUi.Button("添加 Add", AddProject)),
                projectDetails,
            },
        };

        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("250,*"), RowDefinitions = new RowDefinitions("Auto,*") };
        var header = new StackPanel
        {
            Margin = new Thickness(0, 0, 0, 10),
            Children =
            {
                PageUi.Title("调度器 · Scheduler"),
                PageUi.Hint("Script groups run their items in order. Files are upstream's format (User/ScriptGroup), so groups can be copied to and from the Windows version."),
            },
        };
        Grid.SetColumnSpan(header, 2);
        grid.Children.Add(header);
        Grid.SetRow(left, 1);
        grid.Children.Add(left);
        var scroll = new ScrollViewer { Content = right };
        Grid.SetRow(scroll, 1);
        Grid.SetColumn(scroll, 1);
        grid.Children.Add(scroll);

        RefreshChoices();
        LoadGroups();
        return grid;
    }

    private static string Describe(Dictionary<string, string> names, string key) => names.GetValueOrDefault(key, key);

    private static IEnumerable<DirectoryInfo> SafeDirectories(string folder) =>
        Directory.Exists(folder) ? new DirectoryInfo(folder).GetDirectories().OrderBy(d => d.Name) : [];

    private static IEnumerable<FileInfo> SafeFiles(string folder, string pattern) =>
        Directory.Exists(folder) ? new DirectoryInfo(folder).GetFiles(pattern).OrderBy(f => f.Name) : [];

    /// <summary>Folders under User/AutoPathing that directly contain route files, relative to that root.</summary>
    private static IEnumerable<string> PathingFolders()
    {
        var root = MapPathingViewModel.PathJsonPath;
        if (!Directory.Exists(root))
        {
            return [];
        }

        return Directory.EnumerateDirectories(root, "*", SearchOption.AllDirectories).Prepend(root)
            .Where(d => Directory.EnumerateFiles(d, "*.json").Any())
            .Select(d => Path.GetRelativePath(root, d))
            .OrderBy(d => d)
            .Take(2000);
    }

    private static Control Labeled(string label, Control editor)
    {
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,260"), Margin = new Thickness(0, 4) };
        grid.Children.Add(new TextBlock { Text = label, TextWrapping = TextWrapping.Wrap, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 12, 0) });
        Grid.SetColumn(editor, 1);
        grid.Children.Add(editor);
        return grid;
    }

    /// <summary>Status, schedule, repeat count and, for JS scripts, the script's own settings.</summary>
    private static Control ProjectEditor(ScriptGroupProject project, Action save)
    {
        var panel = new StackPanel { Spacing = 2 };
        panel.Children.Add(new TextBlock { Text = project.Name, FontWeight = FontWeight.SemiBold, Margin = new Thickness(0, 8, 0, 4) });

        var status = new ComboBox { ItemsSource = ScriptGroupProjectExtensions.StatusDescriptions.Values.ToList(), HorizontalAlignment = HorizontalAlignment.Stretch };
        status.SelectedIndex = Math.Max(0, ScriptGroupProjectExtensions.StatusDescriptions.Keys.ToList().IndexOf(project.Status));
        status.SelectionChanged += (_, _) =>
        {
            project.Status = ScriptGroupProjectExtensions.StatusDescriptions.Keys.ElementAt(Math.Max(0, status.SelectedIndex));
            save();
        };
        panel.Children.Add(Labeled("状态 Status", status));

        var schedule = new ComboBox { ItemsSource = ScriptGroupProjectExtensions.ScheduleDescriptions.Values.ToList(), HorizontalAlignment = HorizontalAlignment.Stretch };
        schedule.SelectedIndex = Math.Max(0, ScriptGroupProjectExtensions.ScheduleDescriptions.Keys.ToList().IndexOf(project.Schedule));
        schedule.SelectionChanged += (_, _) =>
        {
            project.Schedule = ScriptGroupProjectExtensions.ScheduleDescriptions.Keys.ElementAt(Math.Max(0, schedule.SelectedIndex));
            save();
        };
        panel.Children.Add(Labeled("周期 Schedule", schedule));

        var runs = new TextBox { Text = project.RunNum.ToString() };
        runs.LostFocus += (_, _) =>
        {
            if (int.TryParse(runs.Text, out var count) && count > 0)
            {
                project.RunNum = count;
                save();
            }
            else
            {
                runs.Text = project.RunNum.ToString();
            }
        };
        panel.Children.Add(Labeled("执行次数 Runs", runs));

        if (project.Type == "Javascript")
        {
            panel.Children.Add(new TextBlock { Text = "脚本设置 Script settings", FontWeight = FontWeight.SemiBold, Margin = new Thickness(0, 12, 0, 4) });
            panel.Children.Add(ScriptSettings(project, save));
        }

        return panel;
    }

    /// <summary>
    /// The script's settings.json rendered as a form (upstream builds WPF controls for this). Values are
    /// stored in the project's JsScriptSettingsObject, exactly where upstream keeps them.
    /// </summary>
    private static Control ScriptSettings(ScriptGroupProject project, Action save)
    {
        List<SettingItem> items;
        try
        {
            project.BuildScriptProjectRelation();
            if (project.Project is null)
            {
                return PageUi.Hint("The script is not installed (User/JsScript/" + project.FolderName + ").");
            }

            items = project.Project.Manifest.LoadSettingItems(project.Project.ProjectPath);
        }
        catch (Exception e)
        {
            return PageUi.Hint("Settings could not be read: " + e.GetBaseException().Message);
        }

        if (items.Count == 0)
        {
            return PageUi.Hint("This script has no settings.");
        }

        project.JsScriptSettingsObject ??= new ExpandoObject();
        var values = (IDictionary<string, object?>)project.JsScriptSettingsObject;
        var panel = new StackPanel();
        foreach (var item in items)
        {
            if (string.IsNullOrEmpty(item.Name))
            {
                if (!string.IsNullOrEmpty(item.Label))
                {
                    panel.Children.Add(PageUi.Hint(item.Label));
                }

                continue;
            }

            var label = string.IsNullOrEmpty(item.Label) ? item.Name : item.Label;
            var fallback = DefaultText(item.Default);
            switch (item.Type)
            {
                case "checkbox":
                {
                    var initial = values.TryGetValue(item.Name, out var stored) ? AsBool(stored) : AsBool(item.Default);
                    var toggle = new ToggleSwitch { IsChecked = initial, OnContent = "", OffContent = "", HorizontalAlignment = HorizontalAlignment.Right };
                    toggle.IsCheckedChanged += (_, _) =>
                    {
                        values[item.Name] = toggle.IsChecked == true;
                        save();
                    };
                    panel.Children.Add(Labeled(label, toggle));
                    break;
                }
                case "select" when item.Options is { Count: > 0 }:
                {
                    var combo = new ComboBox { ItemsSource = item.Options, HorizontalAlignment = HorizontalAlignment.Stretch };
                    combo.SelectedItem = values.TryGetValue(item.Name, out var stored) && stored != null ? stored.ToString() : fallback;
                    combo.SelectionChanged += (_, _) =>
                    {
                        values[item.Name] = combo.SelectedItem as string;
                        save();
                    };
                    panel.Children.Add(Labeled(label, combo));
                    break;
                }
                case "multi-checkbox" when item.Options is { Count: > 0 }:
                {
                    var chosen = values.TryGetValue(item.Name, out var stored) ? AsStrings(stored) : AsStrings(item.Default);
                    var boxes = new WrapPanel();
                    foreach (var option in item.Options)
                    {
                        var box = new CheckBox { Content = option, IsChecked = chosen.Contains(option), Margin = new Thickness(0, 0, 12, 0) };
                        box.IsCheckedChanged += (_, _) =>
                        {
                            values[item.Name] = boxes.Children.OfType<CheckBox>().Where(c => c.IsChecked == true)
                                .Select(c => (string)c.Content!).ToList();
                            save();
                        };
                        boxes.Children.Add(box);
                    }

                    panel.Children.Add(new StackPanel { Margin = new Thickness(0, 4), Children = { PageUi.Text(label), boxes } });
                    break;
                }
                default:
                {
                    // input-text, cascade-select and anything newer: a text value
                    var box = new TextBox { Text = values.TryGetValue(item.Name, out var stored) && stored != null ? stored.ToString() : fallback };
                    box.LostFocus += (_, _) =>
                    {
                        values[item.Name] = box.Text ?? "";
                        save();
                    };
                    panel.Children.Add(Labeled(label, box));
                    break;
                }
            }
        }

        return panel;
    }

    private static string DefaultText(object? value) => value switch
    {
        null => "",
        JsonElement { ValueKind: JsonValueKind.String } element => element.GetString() ?? "",
        JsonElement element => element.ToString(),
        _ => value.ToString() ?? "",
    };

    private static bool AsBool(object? value) => value switch
    {
        bool flag => flag,
        JsonElement { ValueKind: JsonValueKind.True } => true,
        string text => bool.TryParse(text, out var parsed) && parsed,
        _ => false,
    };

    private static List<string> AsStrings(object? value) => value switch
    {
        JsonElement { ValueKind: JsonValueKind.Array } element => element.EnumerateArray().Select(e => e.ToString()).ToList(),
        IEnumerable<object> list => list.Select(o => o?.ToString() ?? "").ToList(),
        _ => [],
    };

    /// <summary>The group's own options and its nested option objects (party / pathing, shell).</summary>
    private static Control GroupSettings(ScriptGroup group, Action save)
    {
        var panel = new StackPanel { Spacing = 6 };
        panel.Children.Add(new TextBlock { Text = "配置组设置 Group settings", FontWeight = FontWeight.SemiBold, Margin = new Thickness(0, 8, 0, 0) });
        panel.Children.Add(PropertyGrid.Build(group.Config, save));
        foreach (var property in group.Config.GetType().GetProperties())
        {
            var type = property.PropertyType;
            if (!type.IsClass || type == typeof(string) || type.Namespace?.StartsWith("BetterGenshinImpact") != true)
            {
                continue;
            }

            if (property.GetValue(group.Config) is { } nested)
            {
                panel.Children.Add(new TextBlock { Text = ConfigDocs.Get(group.Config.GetType(), property.Name) ?? property.Name, FontWeight = FontWeight.SemiBold, Margin = new Thickness(0, 8, 0, 0) });
                panel.Children.Add(PropertyGrid.Build(nested, save));
            }
        }

        return panel;
    }
}
