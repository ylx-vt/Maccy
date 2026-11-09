import AppKit
import Testing
@testable import Maccy

@Suite(.serialized)
@MainActor
struct PreviewTests {
  @Test("Recognized pinches use cumulative scale without compounding and reset between gestures")
  func recognizedGestureMagnification() {
    let view = zoomPreview(NSImage(size: NSSize(width: 1200, height: 2400)))
    let fitted = view.fittedMagnification
    let frame = view.frame
    view.updateMagnification(1.5, anchor: .center)
    #expect(abs(view.magnification - fitted * 1.5) < 0.0001)
    #expect(view.frame == frame)
    view.updateMagnification(2, anchor: .center)
    #expect(abs(view.magnification - fitted * 2) < 0.0001)
    view.endMagnification()
    view.updateMagnification(1.5, anchor: .center)
    #expect(abs(view.magnification - fitted * 3) < 0.0001)
    view.updateMagnification(0.01, anchor: .center)
    #expect(view.magnification == view.minMagnification)
    view.updateMagnification(10000, anchor: .center)
    #expect(view.magnification == view.maxMagnification)
    view.updateMagnification(.nan, anchor: .center)
    view.updateMagnification(-1, anchor: .center)
    #expect(view.magnification == view.maxMagnification)
  }

  @Test("Native preview preserves source and zoom controls without a duplicate pinch handler")
  func nativePinchPreview() throws {
    let image = NSImage(size: NSSize(width: 1200, height: 2400))
    let view = zoomPreview(image)
    #expect(!view.allowsMagnification)
    #expect(view.hasHorizontalScroller && view.hasVerticalScroller)
    #expect((view.documentView as? NSImageView)?.image === image)
    #expect(abs(view.magnification - view.fittedMagnification) < 0.0001)
    let frame = view.frame
    let documentSize = try #require(view.documentView).frame.size
    view.zoom(by: 3)
    #expect(view.magnification > view.fittedMagnification)
    #expect(view.frame == frame)
    #expect(view.documentView?.frame.size == documentSize)
    view.resetToFit()
    #expect(abs(view.magnification - view.fittedMagnification) < 0.0001)
  }

  @Test("Long images fit below AppKit's default minimum zoom and can be panned")
  func nativeLongImageZoom() throws {
    let view = zoomPreview(NSImage(size: NSSize(width: 800, height: 8000)))
    #expect(view.minMagnification < 0.25)
    view.zoom(by: 10)
    let before = view.contentView.bounds.origin
    view.contentView.scroll(to: NSPoint(x: before.x, y: before.y + 200))
    view.reflectScrolledClipView(view.contentView)
    #expect(view.contentView.bounds.origin.y != before.y)
    #expect(view.magnification <= view.maxMagnification)
  }

  @Test("Metadata updates preserve zoom while switching images resets it")
  func nativeImageSwitchResetsZoom() {
    let image = NSImage(size: NSSize(width: 1600, height: 1600))
    let identity = UUID()
    let view = zoomPreview(image, identity: identity)
    view.zoom(by: 2)
    let zoomed = view.magnification
    view.display(image, identity: identity)
    view.layoutSubtreeIfNeeded()
    #expect(view.magnification == zoomed)
    view.display(NSImage(size: NSSize(width: 3840, height: 2160)), identity: UUID())
    view.layoutSubtreeIfNeeded()
    #expect(abs(view.magnification - view.fittedMagnification) < 0.0001)
  }

  @Test("Resizing a preview refits an idle image and preserves a zoomed image")
  func nativeResizePreservesZoom() {
    let view = zoomPreview(NSImage(size: NSSize(width: 1200, height: 2400)))
    view.setFrameSize(NSSize(width: 300, height: 300))
    view.layoutSubtreeIfNeeded()
    #expect(abs(view.magnification - view.fittedMagnification) < 0.0001)
    view.zoom(by: 3)
    let zoomed = view.magnification
    view.setFrameSize(NSSize(width: 320, height: 320))
    view.layoutSubtreeIfNeeded()
    #expect(abs(view.magnification - zoomed) < 0.0001)
  }

  private func zoomPreview(_ image: NSImage, identity: UUID = UUID()) -> ZoomableImageScrollView {
    let view = ZoomableImageScrollView(frame: NSRect(x: 0, y: 0, width: 340, height: 400))
    view.display(image, identity: identity)
    view.layoutSubtreeIfNeeded()
    return view
  }

  @Test("Preview fits wide, portrait, long and small images", arguments: [
    (NSSize(width: 3840, height: 2160), NSSize(width: 400, height: 225)),
    (NSSize(width: 1200, height: 2400), NSSize(width: 240, height: 480)),
    (NSSize(width: 800, height: 8000), NSSize(width: 48, height: 480)),
    (NSSize(width: 48, height: 48), NSSize(width: 48, height: 48))
  ])
  func previewFitsImage(image: NSSize, expected: NSSize) {
    #expect(ImagePreviewSizing.fittedSize(image, in: NSSize(width: 1000, height: 1000)) == expected)
  }

  @Test("Preview respects a short sidebar and empty layout proposals")
  func previewFitsAvailableSpace() {
    #expect(ImagePreviewSizing.fittedSize(
      NSSize(width: 1200, height: 2400), in: NSSize(width: 300, height: 180)
    ) == NSSize(width: 90, height: 180))
    #expect(ImagePreviewSizing.fittedSize(.zero, in: NSSize(width: 400, height: 480)) == .zero)
    #expect(ImagePreviewSizing.fittedSize(NSSize(width: 400, height: 480), in: .zero) == .zero)
  }

  @Test("Preview resizing keeps the original image data")
  func previewPreservesOriginal() throws {
    let image = NSImage(size: NSSize(width: 1600, height: 3200), flipped: false) { rect in
      NSColor.blue.setFill()
      rect.fill()
      return true
    }
    let item = HistoryItem(contents: [HistoryItemContent(
      type: NSPasteboard.PasteboardType.tiff.rawValue, value: image.tiffRepresentation
    )])
    let decorator = HistoryItemDecorator(item)
    let original = decorator.item.imageData
    let originalSize = decorator.item.image?.pixelSize
    decorator.sizeImages()
    let preview = try #require(decorator.previewImage)
    #expect(preview.size.height <= HistoryItemDecorator.previewImageSize.height)
    #expect(decorator.item.imageData == original)
    #expect(decorator.item.image?.pixelSize == originalSize)
  }

  @Test("Preview columns fit narrow displays without changing saved widths")
  func previewFitsScreenWidth() {
    let controller = SlideoutController(onContentResize: { _ in }, onSlideoutResize: { _ in })
    controller.contentWidth = 450
    controller.slideoutWidth = 400
    for width: CGFloat in [640, 800, 1440] {
      let columns = controller.widths(in: width, previewVisible: true)
      #expect(columns.content >= controller.minimumContentWidth)
      #expect(columns.preview >= controller.minimumSlideoutWidth)
      #expect(columns.content + columns.preview <= width)
    }
    #expect(controller.contentWidth == 450)
    #expect(controller.slideoutWidth == 400)
    #expect(controller.widths(in: 640, previewVisible: false).content == 450)
  }

  @Test("Preview stays in the usable area at screen edges and on a secondary display")
  func previewStaysOnScreen() {
    for screen in [
      NSRect(x: 0, y: 25, width: 1440, height: 800),
      NSRect(x: -1280, y: 25, width: 1280, height: 700)
    ] {
      for origin in [NSPoint(x: screen.minX - 200, y: -500), NSPoint(x: screen.maxX - 10, y: 500)] {
        let frame = SlideoutController.constrainedFrame(
          NSRect(origin: origin, size: NSSize(width: 850, height: 900)), to: screen
        )
        #expect(screen.contains(frame))
      }
    }
  }
}
