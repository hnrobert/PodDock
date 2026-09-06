import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

// Generates the PodDock app icons (light variant) with real alpha channels.
// Geometry mirrors docs/logo/poddock-logo.svg; SVG y-down coords are reused
// via a flip transform. Run from anywhere: swift scripts/generate-app-icons.swift
// Writes into PodDock/Resources/Assets.xcassets/AppIcon.appiconset/.

let W = 1024.0
let rgb = CGColorSpace(name: CGColorSpace.sRGB)!

func grad(_ comps: [CGFloat]) -> CGGradient {
  let c1 = CGColor(colorSpace: rgb, components: Array(comps[0..<4]))!
  let c2 = CGColor(colorSpace: rgb, components: Array(comps[4..<8]))!
  return CGGradient(colorsSpace: rgb, colors: [c1, c2] as CFArray, locations: [0, 1])!
}

let tileG = grad([0.949, 0.984, 0.957, 1, 0.843, 0.941, 0.867, 1])         // #f2fbf4 -> #d7f0dd
let vigG  = grad([0.204, 0.780, 0.349, 0.18, 0.204, 0.780, 0.349, 0])       // #34c759 glow
let dotG  = grad([0.188, 0.820, 0.345, 1, 0.129, 0.510, 0.235, 1])          // #30d158 -> #21823c (system green)
let beamG = grad([0.204, 0.780, 0.349, 0.45, 0.204, 0.780, 0.349, 0])       // #34c759 beam fade

func drawMark(_ ctx: CGContext, squircle: Bool) {
  // background
  ctx.saveGState()
  if squircle {
    ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: W, height: W),
      cornerWidth: 232, cornerHeight: 232, transform: nil))
    ctx.clip()
  }
  ctx.drawLinearGradient(tileG, start: .zero, end: CGPoint(x: W, y: W), options: [])
  ctx.drawRadialGradient(vigG, startCenter: CGPoint(x: W/2, y: W*0.42), startRadius: 0,
    endCenter: CGPoint(x: W/2, y: W*0.42), endRadius: W*0.75, options: [])
  ctx.restoreGState()

  // beam
  ctx.saveGState()
  ctx.addPath(CGPath(roundedRect: CGRect(x: 504, y: 556, width: 16, height: 116),
    cornerWidth: 8, cornerHeight: 8, transform: nil))
  ctx.clip()
  ctx.drawLinearGradient(beamG, start: CGPoint(x: 512, y: 556), end: CGPoint(x: 512, y: 672), options: [])
  ctx.restoreGState()

  // tray #101b14
  ctx.setFillColor(CGColor(red: 0.063, green: 0.137, blue: 0.102, alpha: 1)) // #10231a
  ctx.addPath(CGPath(roundedRect: CGRect(x: 232, y: 668, width: 560, height: 108),
    cornerWidth: 54, cornerHeight: 54, transform: nil))
  ctx.fillPath()

  // dots
  for c in [(x: 382.0, y: 722.0, r: 34.0), (x: 642.0, y: 722.0, r: 34.0), (x: 512.0, y: 500.0, r: 48.0)] {
    let rect = CGRect(x: c.x - c.r, y: c.y - c.r, width: 2*c.r, height: 2*c.r)
    ctx.saveGState()
    ctx.addEllipse(in: rect); ctx.clip()
    ctx.drawLinearGradient(dotG, start: CGPoint(x: rect.minX, y: rect.minY),
      end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
    ctx.restoreGState()
  }

  // ring
  ctx.setStrokeColor(CGColor(red: 0.204, green: 0.780, blue: 0.349, alpha: 0.35))
  ctx.setLineWidth(3)
  ctx.strokeEllipse(in: CGRect(x: 512-48, y: 500-48, width: 96, height: 96))
}

func render(macStyle: Bool, to path: String, px: Int) {
  let N = CGFloat(px)
  let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
    space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  ctx.clear(CGRect(x: 0, y: 0, width: N, height: N))
  ctx.translateBy(x: 0, y: N)       // SVG y-down coordinates
  ctx.scaleBy(x: 1, y: -1)
  ctx.scaleBy(x: N/1024, y: N/1024) // design space stays 1024
  if macStyle {
    ctx.translateBy(x: 100, y: 100) // squircle 824 centered, transparent margins
    ctx.scaleBy(x: 0.8047, y: 0.8047)
    drawMark(ctx, squircle: true)
  } else {
    drawMark(ctx, squircle: false)  // full-bleed; iOS masks corners
  }
  guard let img = ctx.makeImage() else { fatalError("image") }
  let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
    UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(dest, img, nil)
  CGImageDestinationFinalize(dest)
  print("wrote \(path)")
}

let outDir = URL(fileURLWithPath: #filePath)  // .../scripts/generate-app-icons.swift
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("PodDock/Resources/Assets.xcassets/AppIcon.appiconset").path

render(macStyle: false, to: outDir + "/icon-ios-1024.png", px: 1024)
for px in [16, 32, 64, 128, 256, 512, 1024] {
  render(macStyle: true, to: String(format: "%@/icon-%d.png", outDir, px), px: px)
}
