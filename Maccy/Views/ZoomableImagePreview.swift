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
  private var magnificationMonitor: Any?
  private var hoverTrackingArea: NSTrackingArea?
  private var keyWindowObserver: NSObjectProtocol?
  private var hoverActivationScheduled = false
  private var gestureStartMagnification: CGFloat?
  private var pinchAnchor = UnitPoint.center
  private(set) var fittedMagnification: CGFloat = 1

  override var mouseDownCanMoveWindow: Bool { false }
  override var acceptsFirstResponder: Bool { false }
  override var needsPanelToBecomeKey: Bool { true }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
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
    // One native recognizer owns pinch input, including cancellation. The scroll
    // view retains native transforms and scrolling without a second pinch path.
    allowsMagnification = false
    minMagnification = 0.0001
    maxMagnification = 8
    imageView.imageScaling = .scaleProportionallyUpOrDown
    imageView.imageAlignment = .alignCenter
    documentView = imageView
    let pinch = NSMagnificationGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
    pinch.delaysMagnificationEvents = true
    addGestureRecognizer(pinch)
    setAccessibilityIdentifier("image-preview")
    setAccessibilityLabel(NSLocalizedString("ImageZoomHint", tableName: "PreviewItemView", comment: ""))
  }

  @objc private func handlePinch(_ recognizer: NSMagnificationGestureRecognizer) {
    if recognizer.state == .began {
      endMagnification()
      let location = recognizer.location(in: self)
      let x = (location.x - bounds.minX) / max(bounds.width, 1)
      let y = (location.y - bounds.minY) / max(bounds.height, 1)
      pinchAnchor = UnitPoint(x: x, y: isFlipped ? y : 1 - y)
    }
    switch recognizer.state {
    case .began, .changed, .ended:
      PreviewGestureDiagnostics.write("native-pinch phase=\(recognizer.state.rawValue) scale=\(recognizer.magnification)")
      updateMagnification(1 + recognizer.magnification, anchor: pinchAnchor)
    default:
      break
    }
    if recognizer.state == .ended || recognizer.state == .cancelled || recognizer.state == .failed {
      endMagnification()
    }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func activateForPointerInteraction() {
    (window as? any ImagePreviewActivating)?.activateForImagePreview()
  }

  // The clipboard panel can be key while its app stays inactive. Prepare the
  // existing native pinch path when the pointer enters the visible canvas.
  // Checking the key window prevents a retained preview from taking focus while
  // the user is working in another window.
  func activateForHover(at windowPoint: NSPoint) {
    guard let window, window.isVisible, window.isKeyWindow,
          !isHiddenOrHasHiddenAncestor,
          visibleRect.contains(convert(windowPoint, from: nil)) else { return }
    activateForPointerInteraction()
  }

  private func activateForCurrentPointer() {
    guard let window else { return }
    activateForHover(at: window.convertPoint(fromScreen: NSEvent.mouseLocation))
  }

  private func scheduleHoverActivation() {
    guard !hoverActivationScheduled else { return }
    hoverActivationScheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.hoverActivationScheduled = false
      self.activateForCurrentPointer()
    }
  }

  override func updateTrackingAreas() {
    if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
    super.updateTrackingAreas()
    let area = NSTrackingArea(
      rect: .zero,
      options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
      owner: self, userInfo: nil
    )
    hoverTrackingArea = area
    addTrackingArea(area)
    // A preview can appear beneath a stationary pointer after selecting an
    // image or reopening the popup, without receiving a new mouse-enter event.
    // Activation may lay out the window; run after AppKit finishes this update.
    scheduleHoverActivation()
  }

  override func mouseEntered(with event: NSEvent) {
    activateForHover(at: event.locationInWindow)
  }

  override func mouseMoved(with event: NSEvent) {
    activateForHover(at: event.locationInWindow)
  }

  override func mouseDown(with event: NSEvent) {
    activateForPointerInteraction()
    super.mouseDown(with: event)
  }

  isolated deinit {
    if let magnificationMonitor { NSEvent.removeMonitor(magnificationMonitor) }
    if let keyWindowObserver { NotificationCenter.default.removeObserver(keyWindowObserver) }
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if let magnificationMonitor { NSEvent.removeMonitor(magnificationMonitor) }
    magnificationMonitor = nil
    if let keyWindowObserver { NotificationCenter.default.removeObserver(keyWindowObserver) }
    keyWindowObserver = nil
    endMagnification()
    guard let window else { return }
    keyWindowObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.scheduleHoverActivation() }
    }
    scheduleHoverActivation()
    if PreviewGestureDiagnostics.isEnabled {
      PreviewGestureDiagnostics.write("attached key=\(window.isKeyWindow) active=\(NSApp.isActive)")
      recordWindowState("attached")
    }
    // Keep the same AppKit gesture subscription in ordinary and diagnostic
    // launches. Logging is optional; event delivery must not depend on it.
    magnificationMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.magnify, .beginGesture, .endGesture, .gesture, .scrollWheel]
    ) { [weak self] event in
      guard PreviewGestureDiagnostics.isEnabled else { return event }
      guard let self, let window = self.window else { return event }
      // Gesture events need not carry a window or a mouse-event location.
      let point = window.convertPoint(fromScreen: NSEvent.mouseLocation)
      let inside = self.visibleRect.contains(self.convert(point, from: nil))
      let sameWindow = event.window === window || (event.window == nil && window.isKeyWindow)
      PreviewGestureDiagnostics.write(
        "event=\(event.type.rawValue) sameWindow=\(sameWindow) nilWindow=\(event.window == nil) "
          + "key=\(window.isKeyWindow) active=\(NSApp.isActive) inside=\(inside)"
      )
      return event
    }
  }

  func updateMagnification(_ scale: CGFloat, anchor: UnitPoint) {
    guard scale.isFinite, scale > 0 else { return }
    layoutSubtreeIfNeeded()
    let start = gestureStartMagnification ?? magnification
    gestureStartMagnification = start
    let point = NSPoint(
      x: contentView.bounds.minX + anchor.x * contentView.bounds.width,
      y: contentView.bounds.minY + (contentView.isFlipped ? anchor.y : 1 - anchor.y) * contentView.bounds.height
    )
    let before = magnification
    setMagnification(min(max(start * scale, minMagnification), maxMagnification), centeredAt: point)
    PreviewGestureDiagnostics.write("zoom scale=\(scale) before=\(before) after=\(magnification)")
  }

  func endMagnification() {
    gestureStartMagnification = nil
  }

  override func scrollWheel(with event: NSEvent) {
    let before = contentView.bounds.origin
    super.scrollWheel(with: event)
    PreviewGestureDiagnostics.write("native-scroll moved=\(contentView.bounds.origin != before)")
  }

  func display(_ image: NSImage, identity: UUID) {
    guard imageIdentity != identity else { return }
    imageIdentity = identity
    endMagnification()
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
    recordWindowState("zoom-control")
    layoutSubtreeIfNeeded()
    let scale = min(max(magnification * factor, minMagnification), maxMagnification)
    let center = NSPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
    setMagnification(scale, centeredAt: center)
  }

  private func recordWindowState(_ context: String) {
    guard PreviewGestureDiagnostics.isEnabled, let window else { return }
    PreviewGestureDiagnostics.write(
      "window-state context=\(context) opaque=\(window.isOpaque) alpha=\(window.backgroundColor.alphaComponent) "
        + "viewOpaque=\(isOpaque) imageOpaque=\(imageView.isOpaque) key=\(window.isKeyWindow)"
    )
  }

  func resetToFit() {
    endMagnification()
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

// Opt-in, bounded local diagnostics. Never records images, text, app names, or
// clipboard identifiers, and is inactive in ordinary launches and login items.
private enum PreviewGestureDiagnostics {
  static let isEnabled = CommandLine.arguments.contains("--preview-gesture-diagnostics")
  private static var remaining = 500
  private static var remainingScroll = 20
  private static let output: FileHandle? = {
    guard isEnabled else { return nil }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("Maccy-preview-gesture.log")
    guard FileManager.default.createFile(atPath: url.path, contents: nil,
                                        attributes: [.posixPermissions: 0o600]) else { return nil }
    return try? FileHandle(forWritingTo: url)
  }()

  static func write(_ message: String) {
    guard let output, remaining > 0 else { return }
    if message.hasPrefix("event=22 ") || message.hasPrefix("native-scroll ") {
      guard remainingScroll > 0 else { return }
      remainingScroll -= 1
    }
    remaining -= 1
    try? output.write(contentsOf: Data((message + "\n").utf8))
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
  override var acceptsFirstResponder: Bool { false }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func mouseDown(with event: NSEvent) {
    (enclosingScrollView as? ZoomableImageScrollView)?.activateForPointerInteraction()
    if event.clickCount == 2 {
      (enclosingScrollView as? ZoomableImageScrollView)?.resetToFit()
    } else {
      super.mouseDown(with: event)
    }
  }
}
