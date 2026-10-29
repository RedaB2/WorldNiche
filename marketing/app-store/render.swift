import AppKit
import Foundation

// Run from the repository root: swift marketing/app-store/render.swift
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let base = root.appendingPathComponent("marketing/app-store")
let output = base.appendingPathComponent("1.0/en-US/iphone/screenshots")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}

let paper = color(0xF5F3ED)
let pine = color(0x203C33)
let sage = color(0xDCE5D2)

struct Poster {
    let file: String
    let label: String
    let title: String
    let subtitle: String
    let background: NSColor
    let foreground: NSColor
}

let posters = [
    Poster(file: "01-globe", label: "FOLLOW YOUR CURIOSITY", title: "A little more world,\nevery day.",
           subtitle: "Turn the globe. Find your next discovery.", background: paper, foreground: pine),
    Poster(file: "02-local-lens", label: "THE LOCAL LENS", title: "Small details.\nBigger discoveries.",
           subtitle: "Get to know a place through its culture.", background: pine, foreground: paper),
    Poster(file: "03-atlas", label: "YOUR WORLD ATLAS", title: "195 countries.\nEndless curiosity.",
           subtitle: "A new place is always a tap away.", background: sage, foreground: pine),
    Poster(file: "04-journal", label: "YOUR PRIVATE JOURNAL", title: "Keep a little\nof everywhere.",
           subtitle: "Save a place. Leave yourself a note.", background: paper, foreground: pine),
    Poster(file: "05-friends", label: "BETTER TOGETHER", title: "One link closer.\nA world to explore.",
           subtitle: "Invite a friend. Share your discoveries.", background: pine, foreground: paper)
]

func font(_ size: CGFloat, serif: Bool = false, weight: NSFont.Weight = .regular) -> NSFont {
    let system = NSFont.systemFont(ofSize: size, weight: weight)
    guard serif, let descriptor = system.fontDescriptor.withDesign(.serif) else { return system }
    return NSFont(descriptor: descriptor, size: size) ?? system
}

func text(_ string: String, in rect: NSRect, size: CGFloat, color: NSColor,
          serif: Bool = false, weight: NSFont.Weight = .regular, tracking: CGFloat = 0) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .left
    paragraph.lineSpacing = serif ? 0 : 8
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font(size, serif: serif, weight: weight), .foregroundColor: color,
        .paragraphStyle: paragraph, .kern: tracking
    ]
    NSAttributedString(string: string, attributes: attributes).draw(
        with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
}

func render(_ poster: Poster, iPad: Bool = false) throws {
    let width = iPad ? 2064 : 1320, height = iPad ? 2752 : 2868
    let prefix = iPad ? "ipad-" : ""
    let destination = iPad ? base.appendingPathComponent("1.0/en-US/ipad/screenshots") : output
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    guard let cg = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                             bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("Canvas allocation failed") }
    let context = NSGraphicsContext(cgContext: cg, flipped: false)
    guard let screenshot = NSImage(contentsOf: base.appendingPathComponent("source/\(prefix)\(poster.file).png")) else {
        fatalError("Missing source image for \(poster.file)")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.translateBy(x: 0, y: CGFloat(height))
    context.cgContext.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
    poster.background.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    let dark = poster.background == pine
    let logoName = dark ? "AppLogo-dark.png" : "AppLogo.png"
    let logoURL = root.appendingPathComponent("apps/ios/WorldNiche/Assets.xcassets/AppLogo.imageset/\(logoName)")
    if let logo = NSImage(contentsOf: logoURL) {
        let tinted = NSImage(size: NSSize(width: 180, height: 165))
        tinted.lockFocusFlipped(true)
        logo.draw(in: NSRect(x: 0, y: 0, width: 180, height: 165))
        poster.foreground.setFill()
        NSRect(x: 0, y: 0, width: 180, height: 165).fill(using: .sourceIn)
        tinted.unlockFocus()
        tinted.draw(in: NSRect(x: 84, y: 65, width: 180, height: 165), from: .zero,
                  operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
    text(poster.label, in: NSRect(x: 310, y: 122, width: 940, height: 50), size: 24,
         color: poster.foreground.withAlphaComponent(0.76), weight: .medium, tracking: 4)
    text(poster.title, in: NSRect(x: 96, y: 278, width: iPad ? 1840 : 1160, height: 330), size: iPad ? 128 : 113,
         color: poster.foreground, serif: true, weight: .medium, tracking: -3)
    text(poster.subtitle, in: NSRect(x: 100, y: iPad ? 620 : 590, width: iPad ? 1800 : 1120, height: 90), size: iPad ? 42 : 34,
         color: poster.foreground.withAlphaComponent(0.78))

    let orbit = NSBezierPath(ovalIn: NSRect(x: -510, y: 1380, width: 2320, height: 820))
    poster.foreground.withAlphaComponent(0.12).setStroke()
    orbit.lineWidth = 2
    orbit.stroke()

    let screen = iPad ? NSRect(x: 342, y: 800, width: 1380, height: 1840) : NSRect(x: 194, y: 739, width: 932, height: 2025)
    let frame = screen.insetBy(dx: -15, dy: -15)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.32 : 0.16)
    shadow.shadowBlurRadius = 70
    shadow.shadowOffset = NSSize(width: 0, height: 20)
    shadow.set()
    color(0x282B29).setFill()
    NSBezierPath(roundedRect: frame, xRadius: 104, yRadius: 104).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: screen, xRadius: 91, yRadius: 91).addClip()
    screenshot.draw(in: screen, from: .zero, operation: .sourceOver, fraction: 1,
                    respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    guard let rendered = cg.makeImage(),
          let data = NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
    try data.write(to: destination.appendingPathComponent("\(poster.file).png"))
    print("Rendered \(poster.file): \(width)x\(height)")
}

for poster in posters { try render(poster) }
for index in [0, 2, 3] { try render(posters[index], iPad: true) }

func renderDuo(_ poster: Poster, title: String) throws {
    let width = 2034, height = 1398
    let destination = base.appendingPathComponent("1.0/en-US/duo/screenshots")
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let cg = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    cg.translateBy(x: 0, y: CGFloat(height))
    cg.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    poster.background.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    let logo = NSImage(contentsOf: root.appendingPathComponent("apps/ios/WorldNiche/Assets.xcassets/AppLogo.imageset/AppLogo.png"))!
    logo.draw(in: NSRect(x: 70, y: 75, width: 180, height: 165), from: .zero, operation: .sourceOver,
              fraction: 1, respectFlipped: true, hints: nil)
    text("WORLDNICHE ON IPHONE DUO", in: NSRect(x: 80, y: 325, width: 640, height: 70),
         size: 22, color: pine.withAlphaComponent(0.7), weight: .medium, tracking: 3)
    text(title, in: NSRect(x: 75, y: 445, width: 720, height: 520), size: 90, color: pine,
         serif: true, weight: .medium, tracking: -2)
    text(poster.subtitle, in: NSRect(x: 80, y: 1000, width: 610, height: 180), size: 30, color: pine.withAlphaComponent(0.76))
    let screen = NSRect(x: 800, y: 345, width: 1160, height: 1160 * 2007 / 2853)
    color(0x282B29).setFill()
    NSBezierPath(roundedRect: screen.insetBy(dx: -12, dy: -12), xRadius: 64, yRadius: 64).fill()
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: screen, xRadius: 52, yRadius: 52).addClip()
    let capture = NSImage(contentsOf: base.appendingPathComponent("source/duo-\(poster.file).png"))!
    capture.draw(in: screen, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                 hints: [.interpolation: NSImageInterpolation.high])
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    try NSBitmapImageRep(cgImage: cg.makeImage()!).representation(using: .png, properties: [:])!
        .write(to: destination.appendingPathComponent("\(poster.file).png"))
    print("Rendered Duo \(poster.file): \(width)x\(height)")
}

try renderDuo(posters[0], title: "A little more\nworld,\nevery day.")
try renderDuo(posters[2], title: "195 countries.\nEndless\ncuriosity.")
