using System;
using System.Globalization;
using System.Windows.Data;

namespace FelixTrayApp.Converters;

public class ThemeToCheckedConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is string currentTheme && parameter is string targetTheme)
        {
            return currentTheme.Equals(targetTheme, StringComparison.OrdinalIgnoreCase);
        }
        return false;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is true && parameter is string theme)
        {
            return theme;
        }
        return Binding.DoNothing;
    }
}
