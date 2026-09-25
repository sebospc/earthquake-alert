import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
// Regenerate: swift tools/app-icon.swift EarthquakeRelay/Assets.xcassets/AppIcon.appiconset/AppIcon.png
// Seismograph trace, white on red. Drawn by hand: SF Symbols may not be used in app icons.
let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let gradient = CGGradient(colorsSpace: space, colors: [CGColor(srgbRed: 0.94, green: 0.27, blue: 0.19, alpha: 1),
                                                       CGColor(srgbRed: 0.70, green: 0.09, blue: 0.10, alpha: 1)] as CFArray,
                          locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 1024), end: .zero, options: [])
let mid = 512.0
let points: [(Double, Double)] = [(150, 0), (330, 0), (400, 120), (470, -300), (560, 300), (640, -150), (700, 0), (874, 0)]
context.addLines(between: points.map { CGPoint(x: $0.0, y: mid + $0.1) })
context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
context.setLineWidth(78)
context.setLineCap(.round)
context.setLineJoin(.round)
context.strokePath()
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
CGImageDestinationFinalize(destination)
