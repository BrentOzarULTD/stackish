using System.Globalization;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;
using Stackish.Core;

namespace Stackish.Desktop;
public sealed class ComparisonChart : Control
{
    public static readonly StyledProperty<RunSnapshot?> CurrentProperty = AvaloniaProperty.Register<ComparisonChart, RunSnapshot?>(nameof(Current));
    public static readonly StyledProperty<RunSnapshot?> BaselineProperty = AvaloniaProperty.Register<ComparisonChart, RunSnapshot?>(nameof(Baseline));
    public RunSnapshot? Current { get => GetValue(CurrentProperty); set => SetValue(CurrentProperty, value); }
    public RunSnapshot? Baseline { get => GetValue(BaselineProperty); set => SetValue(BaselineProperty, value); }
    static ComparisonChart() => AffectsRender<ComparisonChart>(CurrentProperty, BaselineProperty);

    public override void Render(DrawingContext context)
    {
        base.Render(context);
        var plot = new Rect(42, 10, Math.Max(1, Bounds.Width - 50), Math.Max(1, Bounds.Height - 36));
        var current = Current?.Id == Baseline?.Id ? null : Current;
        double duration = Math.Max(30, Math.Max(Current?.Seconds ?? 0, Baseline?.Seconds ?? 0));
        var all = (Baseline?.Buckets ?? []).Concat(current?.Buckets ?? []).ToArray();
        double peak = Math.Max(1, all.Select(b => b.QueriesPerSecond).DefaultIfEmpty(0).Max());
        double magnitude = Math.Pow(10, Math.Floor(Math.Log10(peak / 3)));
        double max = 3 * Math.Ceiling(peak / 3 / magnitude) * magnitude;
        var grid = new Pen(Brush.Parse("#EEEAE4"), 1, new DashStyle([3, 3], 0));
        for (int i = 0; i <= 3; i++)
        {
            double y = plot.Bottom - i * plot.Height / 3;
            context.DrawLine(grid, new(plot.Left, y), new(plot.Right, y));
            Label(context, (max * i / 3).ToString(max < 10 ? "0.##" : "N0"), new(0, y - 7));
            double seconds = duration * i / 3;
            Label(context, MainViewModel.Duration(seconds, duration >= 3600), new(plot.Left + i * plot.Width / 3 - (i == 3 ? (duration >= 3600 ? 48 : 30) : 0), plot.Bottom + 8));
        }
        context.DrawLine(new Pen(Brush.Parse("#CFC9C1")), plot.BottomLeft, plot.BottomRight);
        DrawSeries(context, Baseline, plot, duration, max, "#6E717A", true);
        DrawSeries(context, current, plot, duration, max, "#2F6DB5", false);
        if (all.Length == 0) Label(context, "Start a run to capture your baseline.", new(plot.Left + 14, plot.Top + plot.Height / 2));
    }
    private static void DrawSeries(DrawingContext context, RunSnapshot? run, Rect plot, double duration, double max, string color, bool dashed)
    {
        if (run?.Buckets.Length is not > 0) return;
        var geometry = new StreamGeometry();
        using (var path = geometry.Open())
        {
            bool first = true;
            foreach (var bucket in run.Buckets)
            {
                var point = new Point(plot.Left + bucket.EndSeconds / duration * plot.Width,
                    plot.Bottom - bucket.QueriesPerSecond / max * plot.Height);
                if (first) { path.BeginFigure(point, false); first = false; } else path.LineTo(point);
            }
            path.EndFigure(false);
        }
        context.DrawGeometry(null, new Pen(Brush.Parse(color), 2, dashed ? new DashStyle([5, 4], 0) : null), geometry);
    }
    private static void Label(DrawingContext context, string text, Point point) => context.DrawText(
        new FormattedText(text, CultureInfo.CurrentCulture, FlowDirection.LeftToRight,
            new Typeface("avares://Stackish/Assets#IBM Plex Sans"), 11, Brush.Parse("#6E717A")), point);
}
