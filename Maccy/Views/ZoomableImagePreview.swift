import AppKit
import SwiftUI

final class ImagePreviewZoom {
  fileprivate weak var scrollView: ZoomableImageScrollView?

  func zoomIn() { scrollView?.zoom(by: 1.5) }
  func zoomOut() { scrollView?.zoom(by: 1 / 1.5) }
  func fit() { scrollView?.resetToFit() }
}

struct ZoomableImagePreview: NSViewRepresentable {
  let image: NSImage
  let identity: UUID
  let zoom: ImagePreviewZoom

  func makeNSView(context: Context) -> ZoomableImageScrollView {
    let view = ZoomableImageScrollView()
    zoom.scrollView = view
    view.display(image, identity: identity)
    return view
  }

  func updateNSView(_ view: ZoomableImageScrollView, context: Context) {
    zoom.scrollView = view
    // Re-rendering metadata must not reset an in-progress pinch or pan.
    view.display(image, identity: identity)
  }
}

class ZoomableImageScrollView: NSScrollView {
  private let imageView = PreviewZoomImageView()
  private var imageIdentity: UUID?
  private var lastViewportSize = NSSize.zero
  private var needsInitialFit = true
  private(set) var fittedMagnification: CGFloat = 1

  override var mouseDownCanMoveWindow: Bool { false }
  override var acceptsFirstResponder: Bool { false }
  override var intrinsicContentSize: NSSize {
    NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    contentView = CenteredImageClipView()
    contentView.drawsBackground = false
    drawsBackground = false
    borderType = .noBorder
    hasHorizontalScroller = true
    hasVerticalScroller = true
    scrollerStyle = .overlay
    autohidesScrollers = true
    horizontalScrollElasticity = .none
    verticalScrollElasticity = .none
    // AppKit handles trackpad magnification and keeps the gesture's focal point.
    allowsMagnification = true
    minMagnification = 0.0001
    maxMagnification = 8
    imageView.imageScaling = .scaleProportionallyUpOrDown
    imageView.imageAlignment = .alignCenter
    documentView = imageView
    setAccessibilityIdentifier("image-preview")
    setAccessibilityLabel(NSLocalizedString("ImageZoomHint", tableName: "PreviewItemView", comment: ""))
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func display(_ image: NSImage, identity: UUID) {
    guard imageIdentity != identity else { return }
    imageIdentity = identity
    imageView.image = image
    imageView.setFrameSize(image.size)
    needsInitialFit = true
    lastViewportSize = .zero
    needsLayout = true
  }

  override func layout() {
    super.layout()
    let viewport = contentSize
    let source = imageView.frame.size
    guard source.width > 0, source.height > 0, viewport.width > 0, viewport.height > 0 else { return }
    guard needsInitialFit || viewport != lastViewportSize else { return }
    let wasFitted = needsInitialFit || abs(magnification - fittedMagnification) < 0.0001
    lastViewportSize = viewport
    fittedMagnification = ImagePreviewSizing.fittedSize(source, in: viewport).width / source.width
    minMagnification = fittedMagnification
    maxMagnification = max(4, fittedMagnification * 8)
    needsInitialFit = false
    if wasFitted {
      applyFit()
    } else {
      magnification = min(max(magnification, minMagnification), maxMagnification)
    }
  }

  func zoom(by factor: CGFloat) {
    layoutSubtreeIfNeeded()
    let scale = min(max(magnification * factor, minMagnification), maxMagnification)
    let center = NSPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
    setMagnification(scale, centeredAt: center)
  }

  func resetToFit() {
    layoutSubtreeIfNeeded()
    applyFit()
  }

  private func applyFit() {
    setMagnification(fittedMagnification, centeredAt: NSPoint(
      x: imageView.bounds.midX, y: imageView.bounds.midY
    ))
    contentView.scroll(to: NSPoint(
      x: (imageView.frame.width - contentView.bounds.width) / 2,
      y: (imageView.frame.height - contentView.bounds.height) / 2
    ))
    reflectScrolledClipView(contentView)
  }
}

private class CenteredImageClipView: NSClipView {
  override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
    var bounds = super.constrainBoundsRect(proposedBounds)
    guard let document = documentView else { return bounds }
    if bounds.width > document.frame.width {
      bounds.origin.x = (document.frame.width - bounds.width) / 2
    }
    if bounds.height > document.frame.height {
      bounds.origin.y = (document.frame.height - bounds.height) / 2
    }
    return bounds
  }
}

private class PreviewZoomImageView: NSImageView {
  override var mouseDownCanMoveWindow: Bool { false }

  override func mouseDown(with event: NSEvent) {
    if event.clickCount == 2 {
      (enclosingScrollView as? ZoomableImageScrollView)?.resetToFit()
    } else {
      super.mouseDown(with: event)
    }
  }
}
