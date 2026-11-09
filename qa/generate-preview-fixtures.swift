import AppKit

// Synthetic visual QA data, never copied into the system clipboard.
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let fixtures: [(String, Int, Int, NSColor)] = [
  ("01-Landscape", 3840, 2160, .systemBlue),
  ("02-Portrait", 1200, 2400, .systemTeal),
  ("03-Long-screenshot", 800, 8000, .systemOrange),
  ("04-Small-icon", 48, 48, .systemPurple),
  ("05-Square", 1600, 1600, .systemGreen),
  ("06-Ultrawide", 8000, 500, .systemPink)
]
for (name, width, height, color) in fixtures {
  let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
  )!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
  color.setFill()
  NSRect(x: 0, y: 0, width: width, height: height).fill()
  for row in 0..<20 where row.isMultiple(of: 2) {
    NSColor.white.withAlphaComponent(0.15).setFill()
    NSRect(x: 0, y: height * row / 20, width: width, height: max(1, height / 20)).fill()
  }
  let border = CGFloat(max(2, min(width, height) / 50))
  NSColor.white.setStroke()
  let rect = NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height).insetBy(dx: border, dy: border))
  rect.lineWidth = border
  rect.stroke()
  if width > 100 {
    let font = NSFont.boldSystemFont(ofSize: CGFloat(min(width, height)) / 12)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
    ("\(name)\n\(width) × \(height)" as NSString).draw(
      at: NSPoint(x: border * 3, y: CGFloat(height) / 2), withAttributes: attributes
    )
    ("TOP" as NSString).draw(at: NSPoint(x: border * 3, y: CGFloat(height) - font.pointSize * 2),
                             withAttributes: attributes)
    ("BOTTOM" as NSString).draw(at: NSPoint(x: border * 3, y: font.pointSize), withAttributes: attributes)
  }
  NSGraphicsContext.restoreGraphicsState()
  try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
}
for index in 7...26 {
  try "Preview QA note \(index) — mouse navigation and scrolling".write(
    to: directory.appendingPathComponent(String(format: "%02d-Note.txt", index)),
    atomically: true, encoding: .utf8
  )
}
print("Created synthetic preview fixtures at \(directory.path)")
