using System;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.ComponentModel;
using Avalonia.Controls;
using BetterGI.Mac.Pages;

namespace BetterGI.Mac;

/// <summary>
/// Navigation shell: a page list on the left, the selected page, a status line and the log.
/// Pages other than Home are created on first use, once upstream's core has started.
/// </summary>
public partial class MainWindow : Window
{
    private static readonly string[] TriggerConfigs =
    [
        "AutoPickConfig", "AutoSkipConfig", "QuickTeleportConfig", "AutoFishingConfig", "AutoEatConfig",
        "SkillCdConfig", "MapMaskConfig",
    ];

    private readonly Dictionary<int, Control> _pages = [];

    public MainWindow()
    {
        InitializeComponent();
        Nav.SelectionChanged += (_, _) => ShowPage();
        DataContextChanged += (_, _) =>
        {
            if (DataContext is not MainViewModel viewModel)
            {
                return;
            }

            // keep the newest log line visible
            viewModel.LogLines.CollectionChanged += (_, e) =>
            {
                if (e.Action == NotifyCollectionChangedAction.Add && viewModel.LogLines.Count > 0)
                {
                    LogList.ScrollIntoView(viewModel.LogLines[^1]);
                }
            };
            viewModel.PropertyChanged += OnViewModelChanged;
            ShowPage();
        };
    }

    /// <summary>Selects a page by its position in the navigation list.</summary>
    public void SelectPage(int index) => Nav.SelectedIndex = index;

    private void OnViewModelChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(MainViewModel.CoreReady))
        {
            ShowPage();
        }
    }

    private void ShowPage()
    {
        if (DataContext is not MainViewModel viewModel)
        {
            return;
        }

        var index = Math.Max(0, Nav.SelectedIndex);
        if (!_pages.TryGetValue(index, out var page))
        {
            if (index != 0 && !viewModel.CoreReady)
            {
                PageHost.Content = new TextBlock { Text = "BetterGI core is starting…", Margin = new Avalonia.Thickness(8) };
                return;
            }

            try
            {
                page = CreatePage(index, viewModel);
            }
            catch (Exception e)
            {
                AppLog.Error("Page failed to load: " + e.GetBaseException().Message);
                page = new TextBlock { Text = "This page failed to load: " + e.GetBaseException().Message, TextWrapping = Avalonia.Media.TextWrapping.Wrap };
            }

            _pages[index] = page;
        }

        PageHost.Content = page;
    }

    private static Control CreatePage(int index, MainViewModel viewModel)
    {
        var core = viewModel.Core;
        return index switch
        {
            1 => SettingsPage.Build(core, "实时触发 · Real-time triggers",
                "Each trigger has an Enabled switch at the top of its section and runs while capture is on.", TriggerConfigs),
            2 => TasksPage.Build(core),
            3 => ScriptsPage.Build(core),
            4 => FilesPage.Pathing(core),
            5 => FilesPage.Macros(core),
            6 => SchedulerPage.Build(core),
            7 => SettingsPage.Build(core, "设置 · Settings",
                "All of upstream BetterGI's options. Descriptions come from upstream's source; changes are saved immediately."),
            _ => new HomePage { DataContext = viewModel },
        };
    }
}
