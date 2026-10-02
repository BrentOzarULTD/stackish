using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Input.Platform;
using Avalonia.Interactivity;
using Avalonia.Markup.Xaml;

namespace Stackish.Desktop;
public partial class MainWindow : Window
{
    private bool closingAfterStop;
    public MainWindow()
    {
        AvaloniaXamlLoader.Load(this);
        AddHandler(KeyDownEvent, HandleKeys, RoutingStrategies.Tunnel);
        Closing += OnClosing;
    }
    private async void CopyErrors(object? sender, RoutedEventArgs e)
    {
        if (DataContext is MainViewModel vm)
            await vm.CopyErrorsAsync(text => Clipboard is { } clipboard
                ? clipboard.SetTextAsync(text)
                : Task.FromException(new InvalidOperationException("Clipboard unavailable.")));
    }
    private void HandleKeys(object? sender, KeyEventArgs e)
    {
        if (DataContext is not MainViewModel vm) return;
        bool mac = OperatingSystem.IsMacOS();
        if ((!mac && e.Key == Key.F5 && e.KeyModifiers == KeyModifiers.None) ||
            (mac && e.Key == Key.R && e.KeyModifiers.HasFlag(KeyModifiers.Meta)))
        { vm.StartCommand.Execute(null); e.Handled = true; }
        else if ((!mac && e.Key == Key.F5 && e.KeyModifiers.HasFlag(KeyModifiers.Shift)) ||
                 (mac && e.Key == Key.OemPeriod && e.KeyModifiers.HasFlag(KeyModifiers.Meta)))
        { vm.StopCommand.Execute(null); e.Handled = true; }
        else if (e.Key == Key.Escape && vm.ShowDrawer) { vm.DrawerCommand.Execute(null); e.Handled = true; }
        else if (e.Key == Key.Enter && vm.ShowConnection) { vm.TestCommand.Execute(null); e.Handled = true; }
    }
    private async void OnClosing(object? sender, WindowClosingEventArgs e)
    {
        if (closingAfterStop || DataContext is not MainViewModel vm) return;
        if (!vm.Busy) { await vm.StopAndCloseAsync(); return; }
        e.Cancel = true;
        var dialog = new Window { Title = "Stop Stackish?", Width = vm.Deploying ? 460 : 360, Height = 180, CanResize = false, WindowStartupLocation = WindowStartupLocation.CenterOwner };
        var stop = new Button { Content = vm.Deploying ? "Stop installation and quit" : "Stop and quit" };
        var stay = new Button { Content = "Keep running" };
        stop.Click += (_, _) => dialog.Close(true);
        stay.Click += (_, _) => dialog.Close(false);
        dialog.Content = new StackPanel { Margin = new(20), Spacing = 18, Children =
        {
            new TextBlock { Text = vm.Deploying ? "Stop installation and quit?" : "Stop the workload and quit?", FontSize = 17 },
            new StackPanel { Orientation = Avalonia.Layout.Orientation.Horizontal, Spacing = 12, Children = { stay, stop } }
        }};
        if (await dialog.ShowDialog<bool>(this))
        {
            await vm.StopAndCloseAsync(); closingAfterStop = true; Close();
        }
    }
}
