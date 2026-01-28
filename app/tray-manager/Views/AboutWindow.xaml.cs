using System.Diagnostics;
using System.Reflection;
using System.Windows;
using System.Windows.Navigation;

namespace FelixTrayManager.Views;

/// <summary>
/// Interaction logic for AboutWindow.xaml
/// </summary>
public partial class AboutWindow : Window
{
    public AboutWindow()
    {
        InitializeComponent();
        LoadVersionInfo();
    }

    /// <summary>
    /// Loads version information from the assembly and displays it
    /// </summary>
    private void LoadVersionInfo()
    {
        try
        {
            // Get assembly version
            var assembly = Assembly.GetExecutingAssembly();
            var version = assembly.GetName().Version;

            if (version != null)
            {
                // Format version as Major.Minor.Build (omit revision if 0)
                var versionString = version.Revision == 0
                    ? $"Version {version.Major}.{version.Minor}.{version.Build}"
                    : $"Version {version.Major}.{version.Minor}.{version.Build}.{version.Revision}";

                VersionTextBlock.Text = versionString;
            }
            else
            {
                VersionTextBlock.Text = "Version 1.0.0";
            }
        }
        catch
        {
            // Fallback if version retrieval fails
            VersionTextBlock.Text = "Version 1.0.0";
        }
    }

    /// <summary>
    /// Handles hyperlink navigation to open URLs in the default browser
    /// </summary>
    private void OnHyperlinkClick(object sender, RequestNavigateEventArgs e)
    {
        try
        {
            // Open the URL in the default browser
            Process.Start(new ProcessStartInfo
            {
                FileName = e.Uri.AbsoluteUri,
                UseShellExecute = true
            });
            e.Handled = true;
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                $"Failed to open link: {ex.Message}",
                "Error",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
    }

    /// <summary>
    /// Handles the Close button click
    /// </summary>
    private void OnCloseClick(object sender, RoutedEventArgs e)
    {
        Close();
    }
}
