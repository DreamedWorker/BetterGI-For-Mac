using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Threading;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Recorder;
using BetterGenshinImpact.Core.Script;
using BetterGenshinImpact.Core.Script.Group;
using BetterGenshinImpact.Core.Script.Project;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.SoloTask;
using BetterGenshinImpact.GameTask.SoloTask.Execution;
using BetterGenshinImpact.Service.Interface;
using BetterGI.Mac.Ui;
using Microsoft.Extensions.DependencyInjection;
using Newtonsoft.Json.Linq;

namespace BetterGI.Mac.Pages;

/// <summary>
/// Small helpers shared by the pages, which are built in code: every page is a list on the left and
/// details on the right, driven directly by upstream's services.
/// </summary>
public static class PageUi
{
    public static TextBlock Title(string text) => new() { Text = text, FontSize = 18, FontWeight = FontWeight.SemiBold, Margin = new Thickness(0, 0, 0, 4) };

    public static TextBlock Hint(string text) => new() { Text = text, Opacity = 0.65, FontSize = 12, TextWrapping = TextWrapping.Wrap };

    public static TextBlock Text(string text) => new() { Text = text, TextWrapping = TextWrapping.Wrap };

    public static Button Button(string text, Action click, bool accent = false)
    {
        var button = new Button { Content = text };
        if (accent)
        {
            button.Classes.Add("accent");
        }

        button.Click += (_, _) => click();
        return button;
    }

    public static Button Button(string text, Func<Task> click, bool accent = false) => Button(text, () =>
    {
        _ = Guarded(click);
    }, accent);

    /// <summary>Runs a UI-started operation; failures go to the log instead of taking the app down.</summary>
    public static async Task Guarded(Func<Task> action)
    {
        try
        {
            await action();
        }
        catch (Exception e)
        {
            AppLog.Error(e.GetBaseException().Message);
        }
    }

    public static StackPanel Row(params Control[] children)
    {
        var panel = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        panel.Children.AddRange(children);
        return panel;
    }

    /// <summary>List on the left, a scrolling details area on the right.</summary>
    public static (Grid Root, ListBox List, ContentControl Details) MasterDetail(double listWidth, Control? header = null)
    {
        var list = new ListBox();
        var details = new ContentControl();
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions($"{listWidth},*"), RowDefinitions = new RowDefinitions("Auto,*") };
        if (header != null)
        {
            header.Margin = new Thickness(0, 0, 0, 10);
            Grid.SetColumnSpan(header, 2);
            grid.Children.Add(header);
        }

        Grid.SetRow(list, 1);
        grid.Children.Add(list);
        var scroll = new ScrollViewer { Content = details, Margin = new Thickness(16, 0, 0, 0) };
        Grid.SetRow(scroll, 1);
        Grid.SetColumn(scroll, 1);
        grid.Children.Add(scroll);
        return (grid, list, details);
    }

    public static Control TwoLine(string first, string second)
    {
        var panel = new StackPanel();
        panel.Children.Add(new TextBlock { Text = first, TextTrimming = TextTrimming.CharacterEllipsis });
        if (!string.IsNullOrWhiteSpace(second))
        {
            panel.Children.Add(new TextBlock { Text = second, Opacity = 0.6, FontSize = 11.5, TextTrimming = TextTrimming.CharacterEllipsis });
        }

        return panel;
    }

    /// <summary>Stops whatever task or script is running (upstream's stop-all).</summary>
    public static void StopAll(CoreSession core) =>
        core.Services.GetRequiredService<BetterGenshinImpact.Service.TaskStopService>()
            .StopAll(BetterGenshinImpact.Service.TaskStopReason.UserRequested);
}

/// <summary>
/// Settings: every upstream config section, edited through the reflection property grid.
/// </summary>
public static class SettingsPage
{
    /// <param name="only">Config property names to show (AllConfig members); null shows everything.</param>
    public static Control Build(CoreSession core, string title, string hint, string[]? only = null)
    {
        var header = new StackPanel { Children = { PageUi.Title(title), PageUi.Hint(hint) } };
        var (root, list, details) = PageUi.MasterDetail(250, header);
        var sections = new List<(string Title, object Target)>();
        var config = core.Config;
        if (only is null)
        {
            sections.Add(("通用 · General", config));
        }

        foreach (var property in typeof(AllConfig).GetProperties().OrderBy(p => p.MetadataToken))
        {
            if (only != null && !only.Contains(property.Name))
            {
                continue;
            }

            var type = property.PropertyType;
            if (!type.IsClass || type == typeof(string) || type.Namespace?.StartsWith("BetterGenshinImpact") != true)
            {
                continue;
            }

            object? value;
            try
            {
                value = property.GetValue(config);
            }
            catch
            {
                continue;
            }

            if (value is null)
            {
                continue;
            }

            var name = ConfigDocs.Get(typeof(AllConfig), property.Name);
            name = string.IsNullOrEmpty(name) ? property.Name : name.Replace("配置", "");
            sections.Add((name, value));
        }

        list.ItemsSource = sections.Select(s => PageUi.TwoLine(s.Title, s.Target == config ? "AllConfig" : s.Target.GetType().Name)).ToList();
        list.SelectionChanged += (_, _) =>
        {
            if (list.SelectedIndex < 0)
            {
                return;
            }

            var (sectionTitle, target) = sections[list.SelectedIndex];
            details.Content = new StackPanel
            {
                Spacing = 6,
                Children =
                {
                    new TextBlock { Text = sectionTitle, FontSize = 15, FontWeight = FontWeight.SemiBold },
                    PropertyGrid.Build(target, () => core.ConfigService.Save()),
                },
            };
        };
        list.SelectedIndex = sections.Count > 0 ? 0 : -1;
        return root;
    }
}

/// <summary>
/// Solo tasks (独立任务): auto domain, auto fight, boss, ley line, fishing, wood... discovered from
/// upstream's task registry and run through its execution service.
/// </summary>
public static class TasksPage
{
    public static Control Build(CoreSession core)
    {
        var registry = core.Services.GetRequiredService<SoloTaskRegistry>();
        var executor = core.Services.GetRequiredService<SoloTaskExecutionService>();
        var tasks = registry.All.OrderBy(d => d.Group).ThenBy(d => d.Order).ToList();
        var status = PageUi.Hint("");
        var header = new StackPanel
        {
            Children =
            {
                PageUi.Title("独立任务 · Solo tasks"),
                PageUi.Hint("Start capture on the Home page first, or the task starts it with the selected game window. Parameters shown are this run's; each task's permanent options are under Settings."),
                status,
            },
        };
        var (root, list, details) = PageUi.MasterDetail(260, header);
        list.ItemsSource = tasks.Select(d => PageUi.TwoLine(d.DisplayName, d.Group)).ToList();

        Guid? runId = null;
        void ShowStatus(SoloTaskStatusSnapshot snapshot) => Dispatcher.UIThread.Post(() =>
        {
            var name = snapshot.TaskId is null ? "" : registry.GetDisplayName(snapshot.TaskId);
            status.Text = snapshot.IsActive
                ? $"▶ {name}: {snapshot.State}"
                : string.IsNullOrEmpty(snapshot.ErrorMessage) ? "No task is running." : $"Stopped: {snapshot.ErrorMessage}";
            if (!snapshot.IsActive)
            {
                runId = null;
            }
        });
        executor.StatusChanged += (_, e) => ShowStatus(executor.GetStatus());
        ShowStatus(executor.GetStatus());

        list.SelectionChanged += (_, _) =>
        {
            if (list.SelectedIndex < 0)
            {
                return;
            }

            var descriptor = tasks[list.SelectedIndex];
            object? param = null;
            Control editor;
            try
            {
                param = descriptor.HasParameters ? descriptor.CreateDefaultParam() : null;
                editor = param is null ? PageUi.Hint("This task has no parameters.") : PropertyGrid.Build(param);
            }
            catch (Exception e)
            {
                editor = PageUi.Hint("Default parameters are used (" + e.GetBaseException().Message + ").");
            }

            var start = PageUi.Button("开始 Start", async () =>
            {
                var id = Guid.NewGuid();
                var response = await executor.StartAsync(new SoloTaskStartRequest
                {
                    RunId = id,
                    TaskId = descriptor.TaskId,
                    Parameters = param is null ? null : JObject.Parse(descriptor.SerializeParam(param)),
                });
                if (response.Accepted)
                {
                    runId = id;
                }
                else
                {
                    AppLog.Warn(response.Status.ErrorMessage ?? "The task was not started.");
                }
            }, accent: true);
            var stop = PageUi.Button("停止 Stop", async () =>
            {
                var active = runId ?? executor.GetStatus().RunId;
                if (active is { } id)
                {
                    await executor.StopAsync(new SoloTaskStopRequest { RunId = id });
                }
            });

            details.Content = new StackPanel
            {
                Spacing = 10,
                Children =
                {
                    new TextBlock { Text = descriptor.DisplayName, FontSize = 15, FontWeight = FontWeight.SemiBold },
                    PageUi.Text(descriptor.Description),
                    PageUi.Row(start, stop),
                    editor,
                },
            };
        };
        list.SelectedIndex = tasks.Count > 0 ? 0 : -1;
        return root;
    }
}

/// <summary>
/// JS scripts: installed scripts (User/JsScript) can be run; the central script repository can be
/// updated with git and scripts imported from it.
/// </summary>
public static class ScriptsPage
{
    public static Control Build(CoreSession core)
    {
        var scriptService = core.Services.GetRequiredService<IScriptService>();
        var status = PageUi.Hint("");
        var repoList = new ListBox { Height = 220 };
        var repoKind = new ComboBox { ItemsSource = new[] { "js", "pathing", "combat", "tcg" }, SelectedIndex = 0, Width = 110 };
        var repoEntries = new List<string>();
        List<ScriptProject> projects = [];
        ListBox list = null!;
        ContentControl details = null!;

        void LoadInstalled()
        {
            projects = [];
            var folder = Global.ScriptPath();
            Directory.CreateDirectory(folder);
            foreach (var directory in new DirectoryInfo(folder).GetDirectories().OrderBy(d => d.Name))
            {
                try
                {
                    projects.Add(new ScriptProject(directory.Name));
                }
                catch (Exception e)
                {
                    AppLog.Warn($"脚本 {directory.Name} 载入失败：{e.GetBaseException().Message}");
                }
            }

            list.ItemsSource = projects.Select(p => PageUi.TwoLine(p.Manifest.Name, $"{p.FolderName} · v{p.Manifest.Version}")).ToList();
            details.Content = projects.Count == 0
                ? PageUi.Hint("No scripts installed yet. Update the script repository below and import some, or copy script folders into " + folder)
                : null;
        }

        void LoadRepo()
        {
            repoEntries.Clear();
            try
            {
                var kind = (string)repoKind.SelectedItem!;
                var root = Path.Combine(ScriptRepoUpdater.Instance.FindCenterRepoPath(), kind);
                if (Directory.Exists(root))
                {
                    repoEntries.AddRange(new DirectoryInfo(root).GetFileSystemInfos().Where(i => !i.Name.StartsWith('.'))
                        .OrderBy(i => i.Name).Select(i => $"{kind}/{i.Name}"));
                }

                status.Text = $"Repository: {repoEntries.Count} entries under '{kind}'.";
            }
            catch (Exception e)
            {
                status.Text = "Repository not downloaded yet (" + e.GetBaseException().Message + ")";
            }

            repoList.ItemsSource = repoEntries.ToList();
        }

        var update = PageUi.Button("更新脚本仓库 Update repository", async () =>
        {
            status.Text = "Updating the script repository (git)…";
            var channel = ScriptRepoUpdater.RepoChannels.TryGetValue("GitHub", out var url) ? url : ScriptRepoUpdater.RepoChannels.Values.First();
            var (path, updated) = await Task.Run(() => ScriptRepoUpdater.Instance.UpdateCenterRepoByGit(channel, null));
            AppLog.Info($"Script repository {(updated ? "updated" : "already up to date")}: {path}");
            LoadRepo();
        });
        var import = PageUi.Button("导入所选 Import selected", async () =>
        {
            if (repoList.SelectedIndex < 0)
            {
                return;
            }

            var entry = repoEntries[repoList.SelectedIndex];
            await ScriptRepoUpdater.Instance.ImportScriptFromPathJson(Newtonsoft.Json.JsonConvert.SerializeObject(new[] { entry }));
            AppLog.Info($"Imported {entry}");
            LoadInstalled();
        }, accent: true);
        repoKind.SelectionChanged += (_, _) => LoadRepo();

        var header = new StackPanel
        {
            Children =
            {
                PageUi.Title("JS 脚本 · Scripts"),
                PageUi.Hint("Scripts from upstream's ecosystem run in the same V8 engine as on Windows. Script APIs that are not available on macOS yet: keyMouseHook and htmlMask."),
            },
        };
        var (root, masterList, masterDetails) = PageUi.MasterDetail(280, header);
        list = masterList;
        details = masterDetails;
        root.RowDefinitions = new RowDefinitions("Auto,*,Auto");
        var repoPanel = new Border
        {
            Margin = new Thickness(0, 12, 0, 0),
            Child = new StackPanel
            {
                Spacing = 6,
                Children =
                {
                    new TextBlock { Text = "脚本仓库 · Script repository", FontWeight = FontWeight.SemiBold },
                    PageUi.Row(update, repoKind, import, PageUi.Button("Refresh", () => { LoadInstalled(); LoadRepo(); })),
                    status,
                    repoList,
                },
            },
        };
        Grid.SetRow(repoPanel, 2);
        Grid.SetColumnSpan(repoPanel, 2);
        root.Children.Add(repoPanel);

        list.SelectionChanged += (_, _) =>
        {
            if (list.SelectedIndex < 0 || list.SelectedIndex >= projects.Count)
            {
                return;
            }

            var project = projects[list.SelectedIndex];
            var authors = string.Join(", ", project.Manifest.Authors.Select(a => a.Name));
            details.Content = new StackPanel
            {
                Spacing = 10,
                Children =
                {
                    new TextBlock { Text = project.Manifest.Name, FontSize = 15, FontWeight = FontWeight.SemiBold },
                    PageUi.Hint($"v{project.Manifest.Version}" + (authors.Length > 0 ? " · " + authors : "") + " · " + project.ProjectPath),
                    PageUi.Text(project.Manifest.Description),
                    PageUi.Row(
                        PageUi.Button("运行 Run", () => new TaskRunner().RunThreadAsync((runtime, ct) =>
                            scriptService.RunMulti(runtime, [new ScriptGroupProject(project)], null, ct)), accent: true),
                        PageUi.Button("停止 Stop", () => PageUi.StopAll(core))),
                },
            };
        };

        LoadInstalled();
        LoadRepo();
        return root;
    }
}

/// <summary>
/// Files page used for both map-tracking routes (User/AutoPathing, *.json) and key-mouse macros
/// (User/KeyMouseScript): browse the folder tree and run one file.
/// </summary>
public static class FilesPage
{
    public static Control Build(CoreSession core, string title, string hint, string relativeFolder, string pattern,
        Func<string, Task> run)
    {
        var root = Global.Absolute(relativeFolder);
        Directory.CreateDirectory(root);
        var current = root;
        var entries = new List<FileSystemInfo>();
        var location = PageUi.Hint("");
        var header = new StackPanel { Children = { PageUi.Title(title), PageUi.Hint(hint), location } };
        var (grid, list, details) = PageUi.MasterDetail(360, header);

        void Load()
        {
            entries.Clear();
            var directory = new DirectoryInfo(current);
            entries.AddRange(directory.GetDirectories().Where(d => !d.Name.StartsWith('.')).OrderBy(d => d.Name));
            entries.AddRange(directory.GetFiles(pattern).OrderBy(f => f.Name));
            var items = entries.Select(e => (Control)new TextBlock { Text = (e is DirectoryInfo ? "📁 " : "") + e.Name, TextTrimming = TextTrimming.CharacterEllipsis }).ToList();
            if (current != root)
            {
                items.Insert(0, new TextBlock { Text = "⬆ .." });
            }

            list.ItemsSource = items;
            location.Text = current;
            details.Content = entries.Count == 0 && current == root
                ? PageUi.Hint("Nothing here yet. Import from the script repository on the Scripts page, or copy files into this folder.")
                : null;
        }

        list.SelectionChanged += (_, _) =>
        {
            var index = list.SelectedIndex;
            if (index < 0)
            {
                return;
            }

            if (current != root)
            {
                if (index == 0)
                {
                    current = Path.GetDirectoryName(current)!;
                    Load();
                    return;
                }

                index--;
            }

            if (index >= entries.Count)
            {
                return;
            }

            if (entries[index] is DirectoryInfo directory)
            {
                current = directory.FullName;
                Load();
                return;
            }

            var file = (FileInfo)entries[index];
            details.Content = new StackPanel
            {
                Spacing = 10,
                Children =
                {
                    new TextBlock { Text = file.Name, FontSize = 15, FontWeight = FontWeight.SemiBold, TextWrapping = TextWrapping.Wrap },
                    PageUi.Hint($"{file.Length / 1024.0:0.#} KB · {file.LastWriteTime:yyyy-MM-dd HH:mm}"),
                    PageUi.Row(
                        PageUi.Button("运行 Run", () => run(file.FullName), accent: true),
                        PageUi.Button("停止 Stop", () => PageUi.StopAll(core))),
                },
            };
        };

        var refresh = PageUi.Button("Refresh", Load);
        refresh.HorizontalAlignment = HorizontalAlignment.Left;
        header.Children.Add(refresh);
        Load();
        return grid;
    }

    public static Control Pathing(CoreSession core)
    {
        var scriptService = core.Services.GetRequiredService<IScriptService>();
        return Build(core, "地图追踪 · Pathing", "Runs one route file. To run many routes in order, use a script group (scheduler) — not ported yet.",
            @"User\AutoPathing", "*.json", path =>
            {
                var file = new FileInfo(path);
                var project = ScriptGroupProject.BuildPathingProject(file.Name, file.DirectoryName!);
                return new TaskRunner().RunThreadAsync((runtime, ct) => scriptService.RunMulti(runtime, [project], null, ct));
            });
    }

    public static Control Macros(CoreSession core) =>
        Build(core, "键鼠录制 · Key-mouse macros", "Plays back a recorded macro. Recording new macros is not available on macOS yet.",
            @"User\KeyMouseScript", "*.json", path => new TaskRunner().RunThreadAsync(async (runtime, ct) =>
            {
                var script = await File.ReadAllTextAsync(path, ct);
                await KeyMouseMacroPlayer.PlayMacro(runtime, script, ct);
            }));
}
