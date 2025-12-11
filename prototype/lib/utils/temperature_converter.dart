/// Utility for converting temperatures between Fahrenheit and Celsius
class TemperatureConverter {
  /// Convert Fahrenheit to Celsius
  static double fahrenheitToCelsius(double fahrenheit) {
    return (fahrenheit - 32) * 5 / 9;
  }

  /// Convert Celsius to Fahrenheit
  static double celsiusToFahrenheit(double celsius) {
    return (celsius * 9 / 5) + 32;
  }

  /// Round temperature to nearest 5 or 10 for cleaner display
  static int roundTemp(double temp) {
    // Round to nearest 5 for temps < 100, nearest 10 for temps >= 100
    if (temp < 100) {
      return (temp / 5).round() * 5;
    } else {
      return (temp / 10).round() * 10;
    }
  }

  /// Convert all temperature references in a text string based on target unit system
  /// Handles patterns like "400°F", "200°C", "400F", "200C"
  ///
  /// If targetSystem is 'metric', converts F to C
  /// If targetSystem is 'imperial', converts C to F
  static String convertTemperaturesInText(String text, String targetSystem) {
    if (targetSystem != 'metric' && targetSystem != 'imperial') {
      return text; // Invalid system, return unchanged
    }

    // Pattern to match temperatures like "400°F" or "200°C" or "400F" or "200C"
    final pattern = RegExp(r'(\d+)°?([FC])\b');

    return text.replaceAllMapped(pattern, (match) {
      final valueStr = match.group(1)!;
      final unit = match.group(2)!;
      final value = double.tryParse(valueStr);

      if (value == null) return match.group(0)!;

      // If target is metric and current is F, convert F to C
      if (targetSystem == 'metric' && unit == 'F') {
        final celsius = fahrenheitToCelsius(value);
        final rounded = roundTemp(celsius);
        return '$rounded°C';
      }

      // If target is imperial and current is C, convert C to F
      if (targetSystem == 'imperial' && unit == 'C') {
        final fahrenheit = celsiusToFahrenheit(value);
        final rounded = roundTemp(fahrenheit);
        return '$rounded°F';
      }

      // Already in target system, just ensure degree symbol is present
      return '$valueStr°$unit';
    });
  }

  /// Extract dual temperature format like "400°F (200°C)" and convert to target system
  /// Returns just the target unit, e.g., "200°C" for metric or "400°F" for imperial
  static String convertDualTemperature(String text, String targetSystem) {
    // Pattern to match dual temps like "400°F (200°C)" or "200°C (400°F)"
    final dualPattern = RegExp(r'(\d+)°?([FC])\s*\((\d+)°?([FC])\)');

    return text.replaceAllMapped(dualPattern, (match) {
      final value1 = double.tryParse(match.group(1)!);
      final unit1 = match.group(2)!;
      final value2 = double.tryParse(match.group(3)!);
      final unit2 = match.group(4)!;

      if (value1 == null || value2 == null) return match.group(0)!;

      // Return the temp that matches the target system
      if (targetSystem == 'metric') {
        // Return Celsius value
        if (unit1 == 'C') return '${value1.toInt()}°C';
        if (unit2 == 'C') return '${value2.toInt()}°C';
      } else if (targetSystem == 'imperial') {
        // Return Fahrenheit value
        if (unit1 == 'F') return '${value1.toInt()}°F';
        if (unit2 == 'F') return '${value2.toInt()}°F';
      }

      return match.group(0)!;
    });
  }
}
