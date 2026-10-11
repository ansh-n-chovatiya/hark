import Foundation

/// Quick sums, percentages and unit conversions answered locally with no model: "what is 18 percent of 240",
/// "12 times 7", "how many kilometres is 26 miles", "convert 5 pounds to kilograms". The units are physical dimensions
/// (length, mass, volume, temperature, time, speed), not anything about an app.
public enum Calculator {
    private static let units: [String: Dimension] = [
        "mile": UnitLength.miles, "miles": UnitLength.miles, "kilometre": UnitLength.kilometers, "kilometres": UnitLength.kilometers,
        "kilometer": UnitLength.kilometers, "kilometers": UnitLength.kilometers, "km": UnitLength.kilometers,
        "metre": UnitLength.meters, "metres": UnitLength.meters, "meter": UnitLength.meters, "meters": UnitLength.meters,
        "foot": UnitLength.feet, "feet": UnitLength.feet, "inch": UnitLength.inches, "inches": UnitLength.inches,
        "centimetre": UnitLength.centimeters, "centimetres": UnitLength.centimeters, "centimeter": UnitLength.centimeters,
        "centimeters": UnitLength.centimeters, "cm": UnitLength.centimeters, "yard": UnitLength.yards, "yards": UnitLength.yards,
        "kilogram": UnitMass.kilograms, "kilograms": UnitMass.kilograms, "kg": UnitMass.kilograms, "kilo": UnitMass.kilograms,
        "kilos": UnitMass.kilograms, "gram": UnitMass.grams, "grams": UnitMass.grams, "pound": UnitMass.pounds,
        "pounds": UnitMass.pounds, "ounce": UnitMass.ounces, "ounces": UnitMass.ounces,
        "litre": UnitVolume.liters, "litres": UnitVolume.liters, "liter": UnitVolume.liters, "liters": UnitVolume.liters,
        "millilitre": UnitVolume.milliliters, "millilitres": UnitVolume.milliliters, "gallon": UnitVolume.gallons,
        "gallons": UnitVolume.gallons, "cup": UnitVolume.cups, "cups": UnitVolume.cups,
        "celsius": UnitTemperature.celsius, "fahrenheit": UnitTemperature.fahrenheit, "kelvin": UnitTemperature.kelvin,
        "second": UnitDuration.seconds, "seconds": UnitDuration.seconds, "minute": UnitDuration.minutes,
        "minutes": UnitDuration.minutes, "hour": UnitDuration.hours, "hours": UnitDuration.hours,
    ]

    /// The answer in words, or nil when the sentence is not a calculation.
    public static func answer(_ transcript: String) -> String? {
        var text = transcript.lowercased()
        text = text.replacingOccurrences(of: ",", with: "")
        for noise in ["what is ", "what's ", "whats ", "calculate ", "work out ", "how much is ", "convert ", "compute "] where text.hasPrefix(noise) {
            text.removeFirst(noise.count)
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " ?.!"))
        if let value = percent(text) { return value }
        if let value = conversion(transcript.lowercased().replacingOccurrences(of: ",", with: "")) { return value }
        if let value = arithmetic(text) { return value }
        return nil
    }

    private static func number(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e12 { return String(Int(value)) }
        let formatted = String(format: "%.4f", value)
        return formatted.replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }

    private static func percent(_ text: String) -> String? {
        let pattern = #"^(-?\d+(?:\.\d+)?) ?(?:percent|%) of (-?\d+(?:\.\d+)?)$"#
        guard let match = text.range(of: pattern, options: .regularExpression) else { return nil }
        let numbers = text[match].components(separatedBy: CharacterSet(charactersIn: "0123456789.-").inverted).filter { !$0.isEmpty }
        guard numbers.count == 2, let rate = Double(numbers[0]), let base = Double(numbers[1]) else { return nil }
        return "\(number(rate)) percent of \(number(base)) is \(number(base * rate / 100))"
    }

    private static func arithmetic(_ text: String) -> String? {
        var expression = text
        for (word, symbol) in [(" divided by ", "/"), (" multiplied by ", "*"), (" times ", "*"), (" plus ", "+"),
                               (" minus ", "-"), (" over ", "/"), (" x ", "*")] {
            expression = expression.replacingOccurrences(of: word, with: symbol)
        }
        expression = expression.replacingOccurrences(of: " ", with: "")
        guard expression.range(of: #"^[0-9.+\-*/()]+$"#, options: .regularExpression) != nil,
              expression.contains(where: { "+-*/".contains($0) }) else { return nil }
        // NSExpression raises on a malformed sum, so the shape is checked first: numbers joined by single operators.
        guard expression.range(of: #"^\(*-?\d+(\.\d+)?\)*([+\-*/]\(*-?\d+(\.\d+)?\)*)+$"#, options: .regularExpression) != nil
        else { return nil }
        let result = NSExpression(format: expression.replacingOccurrences(of: "/", with: ".0/")).expressionValue(with: nil, context: nil)
        guard let value = (result as? NSNumber)?.doubleValue, value.isFinite else { return nil }
        return "\(text) is \(number(value))"
    }

    private static func conversion(_ text: String) -> String? {
        let pattern = #"(-?\d+(?:\.\d+)?) ?([a-z]+) (?:to|in|into) ([a-z]+)"#
        let asked = #"how (?:many|much) ([a-z]+) (?:is|are|in) (-?\d+(?:\.\d+)?) ?([a-z]+)"#
        var amount: Double?, from: String?, to: String?
        if let range = text.range(of: pattern, options: .regularExpression) {
            let parts = text[range].split(whereSeparator: { $0 == " " }).map(String.init)
            if parts.count >= 4, let value = Double(parts[0]) { amount = value; from = parts[1]; to = parts[3] }
            else if parts.count == 3 { /* "5km to miles" */
                let head = parts[0]
                if let split = head.firstIndex(where: { $0.isLetter }) {
                    amount = Double(head[..<split]); from = String(head[split...]); to = parts[2]
                }
            }
        } else if let range = text.range(of: asked, options: .regularExpression) {
            let parts = text[range].split(separator: " ").map(String.init)
            if let index = parts.firstIndex(where: { Double($0) != nil }), index >= 1, index + 1 < parts.count || parts[index].contains(where: \.isLetter) == false {
                to = parts[parts.count > 3 ? 2 : 0]
                amount = Double(parts[index]); from = index + 1 < parts.count ? parts[index + 1] : nil
                to = parts[2] == "is" || parts[2] == "are" || parts[2] == "in" ? parts[1] : parts[2]
            }
        }
        guard let amount, let from, let to, let source = units[from], let target = units[to],
              type(of: source) == type(of: target) else { return nil }
        let converted = Measurement(value: amount, unit: source).converted(to: target)
        return "\(number(amount)) \(from) is \(number(converted.value)) \(to)"
    }
}
