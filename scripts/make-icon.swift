// Draws Hark's app icon: a white waveform on a saffron rounded square. The two colours are Hark's brand
// colours (HarkBrand in Sources/HarkMac/Settings/HarkTheme.swift); change them together.
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let side: CGFloat = 1024
let image = NSImage(size: NSSize(width: side, height: side))
image.lockFocus()

// Apple's icon grid leaves a margin round the shape so its shadow has room.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)
NSGradient(
    starting: NSColor(calibratedRed: 0.94, green: 0.64, blue: 0.22, alpha: 1),
    ending: NSColor(calibratedRed: 0.76, green: 0.40, blue: 0.08, alpha: 1)
)?.draw(in: shape, angle: -90)

// Bars of a waveform, tallest in the middle, like the symbol in the menu bar.
let heights: [CGFloat] = [0.22, 0.46, 0.74, 1.0, 0.62, 0.86, 0.40, 0.20]
let barWidth: CGFloat = 46
let gap: CGFloat = 30
let tallest: CGFloat = 440
let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
var x = (side - total) / 2
NSColor.white.setFill()
for height in heights {
    let barHeight = tallest * height
    let bar = NSRect(x: x, y: (side - barHeight) / 2, width: barWidth, height: barHeight)
    NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
    x += barWidth + gap
}

image.unlockFocus()
guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:])
else { fatalError("could not draw the icon") }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
