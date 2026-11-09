import Defaults
import Logging
import Observation
import SwiftUI

enum SlideoutState {
  case opening
  case closing
  case open
  case closed

  var isAnimating: Bool {
    switch self {
    case .closed, .open:
      return false
    case .opening, .closing:
      return true
    }
  }

  var isOpen: Bool {
    switch self {
    case .open, .opening:
      return true
    case .closed, .closing:
      return false
    }
  }

  fileprivate func toggleWithAnimation() -> SlideoutState {
    switch self {
    case .open, .opening:
      return .closing
    case .closed, .closing:
      return .opening
    }
  }

  func animationDone() -> SlideoutState {
    switch self {
    case .open, .opening:
      return .open
    case .closed, .closing:
      return .closed
    }
  }
}

enum SlideoutPlacement {
  case left
  case right
}

enum SlideoutToggleTrigger {
  case autoOpen
  case manual
}

enum ResizingMode {
  case none
  case content
  case slideout
}

@Observable
class SlideoutController {
  let logger = Logger(label: "org.p0deje.Maccy")
  private static let animationDuration = 0.25

  let onContentResize: (CGFloat) -> Void
  let onSlideoutResize: (CGFloat) -> Void

  let minimumContentWidth: CGFloat = 200
  var contentResizeWidth: CGFloat = 0
  var contentAnimationWidth: CGFloat?

  let minimumSlideoutWidth: CGFloat = 200
  var slideoutResizeWidth: CGFloat = 0

  private var _contentWidth: CGFloat = 0
  var contentWidth: CGFloat {
    get { return _contentWidth }
    set {
      _contentWidth = max(minimumContentWidth, newValue).rounded()
      onContentResize(_contentWidth)
    }
  }
  private var _slideoutWidth: CGFloat = 400
  var slideoutWidth: CGFloat {
    get { return _slideoutWidth }
    set {
      _slideoutWidth = max(minimumSlideoutWidth, newValue).rounded()
      onSlideoutResize(_slideoutWidth)
    }
  }

  var placement: SlideoutPlacement = .right
  var state: SlideoutState = .closed
  var resizingMode: ResizingMode = .none

  var nswindow: NSWindow? {
    return AppState.shared.appDelegate?.panel
  }

  var displayedContentWidth: CGFloat {
    widths(in: nswindow?.screen?.visibleFrame.width ?? .greatestFiniteMagnitude,
           previewVisible: state != .closed).content
  }

  var displayedSlideoutWidth: CGFloat {
    widths(in: nswindow?.screen?.visibleFrame.width ?? .greatestFiniteMagnitude,
           previewVisible: true).preview
  }

  // Fit the two columns without overwriting the user's saved widths when moving
  // between displays. The list always retains its own space beside the preview.
  func widths(in availableWidth: CGFloat, previewVisible: Bool) -> (content: CGFloat, preview: CGFloat) {
    let width = max(0, availableWidth)
    guard previewVisible else { return (min(contentWidth, width), 0) }
    let reservedPreview = min(minimumSlideoutWidth, width / 2)
    let content = min(contentWidth, width - reservedPreview)
    return (content, min(slideoutWidth, width - content))
  }

  static func constrainedFrame(_ frame: NSRect, to screen: NSRect) -> NSRect {
    let size = NSSize(width: min(frame.width, screen.width), height: min(frame.height, screen.height))
    return NSRect(
      x: min(max(frame.minX, screen.minX), screen.maxX - size.width),
      y: min(max(frame.minY, screen.minY), screen.maxY - size.height),
      width: size.width,
      height: size.height
    )
  }

  private var windowAnimationOrigin: CGPoint?
  private var windowAnimationOriginBaseState: SlideoutState = .closed

  private var autoOpenTask: Task<Void, Never>?
  private var autoOpenSuppressed = false
  private var autoOpenEnabled = true

  init(onContentResize: @escaping (CGFloat) -> Void, onSlideoutResize: @escaping (CGFloat) -> Void) {
    self.onContentResize = onContentResize
    self.onSlideoutResize = onSlideoutResize
  }

  private func togglePreviewStateWithAnimation(windowFrame: NSRect) {
    let newValue = state.toggleWithAnimation()
    if !state.isAnimating && newValue.isAnimating {
      contentAnimationWidth = contentWidth
      windowAnimationOrigin = windowFrame.origin
      windowAnimationOriginBaseState = state
    }
    state = newValue
  }

  func computePlacement(window: NSWindow, for size: NSSize) -> SlideoutPlacement {
    guard let screen = window.screen?.visibleFrame else { return placement }
    let windowFrame = window.frame
    if windowFrame.minX + size.width <= screen.maxX {
      return .right
    }
    if windowFrame.maxX - size.width >= screen.minX {
      return .left
    }
    return screen.maxX - windowFrame.maxX >= windowFrame.minX - screen.minX ? .right : .left
  }

  func computeSizeWithPreview(_ size: NSSize, state newState: SlideoutState) -> NSSize {
    var newSize = size
    let screen = nswindow?.screen?.visibleFrame
    let layout = widths(in: screen?.width ?? .greatestFiniteMagnitude, previewVisible: newState.isOpen)
    newSize.width = layout.content + layout.preview
    let popup = AppState.shared.popup
    newSize.height = min(popup.preferredHeight(for: popup.height), screen?.height ?? .greatestFiniteMagnitude)
    return newSize
  }

  func togglePreview(trigger: SlideoutToggleTrigger = .manual) {
    if !state.isOpen {
      let navigator = AppState.shared.navigator
      guard navigator.leadHistoryItem != nil || navigator.pasteStackSelected else { return }
    }

    if trigger == .manual {
      if state.isOpen {
        autoOpenSuppressed = true
      } else {
        autoOpenSuppressed = false
      }
    }

    cancelAutoOpen()
    withAnimation(.easeInOut(duration: Self.animationDuration), completionCriteria: .removed) {
      if let window = nswindow {
        togglePreviewStateWithAnimation(windowFrame: window.frame)
        var newSize = window.frame.size
        newSize.width = contentWidth
        newSize = computeSizeWithPreview(newSize, state: self.state)
        if state.isOpen {
          placement = computePlacement(window: window, for: newSize)
        }

        let expectedAnimationState = state
        NSAnimationContext.runAnimationGroup { (context) in
          var newOrigin = windowAnimationOrigin ?? window.frame.origin
          newOrigin.y += (window.frame.height - newSize.height)

          if placement == .left {
            if windowAnimationOriginBaseState == .closed && state.isOpen {
              newOrigin.x -= displayedSlideoutWidth
            } else if windowAnimationOriginBaseState == .open
              && !state.isOpen {
              newOrigin.x += displayedSlideoutWidth
            }
            // Otherwise the base is the desired position
          }
          context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
          context.completionHandler = {
            if self.state == expectedAnimationState {
              self.state = expectedAnimationState.animationDone()
            }
          }
          context.duration = Self.animationDuration
          var frame = NSRect(origin: newOrigin, size: newSize)
          if let screen = window.screen?.visibleFrame {
            frame = Self.constrainedFrame(frame, to: screen)
          }
          window.animator().setFrame(frame, display: true)
        }
      }
    } completion: {
    }
  }

  func startResize(mode: ResizingMode) {
    logger.info("Starting resize with mode \(mode)")
    resizingMode = mode
    contentWidth = contentResizeWidth
    slideoutWidth = slideoutResizeWidth
  }

  func endResize() {
    logger.info("Ended resize. Mode was \(resizingMode)")
    switch resizingMode {
    case .none:
      return
    case .content:
      contentWidth = contentResizeWidth
    case .slideout:
      slideoutWidth = slideoutResizeWidth
    }
    resizingMode = .none
  }

  func startAutoOpen() {
    cancelAutoOpen()

    guard Defaults[.openPreviewAutomatically] else { return }
    guard autoOpenEnabled else { return }
    guard !autoOpenSuppressed else { return }
    guard !state.isOpen else { return }

    autoOpenTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(Defaults[.previewDelay]))
      guard !Task.isCancelled else { return }
      guard Defaults[.openPreviewAutomatically] else { return }

      if !state.isOpen {
        togglePreview(trigger: .autoOpen)
      }
    }
  }

  func cancelAutoOpen() {
    autoOpenTask?.cancel()
    autoOpenTask = nil
  }

  func enableAutoOpen() {
    autoOpenEnabled = true
  }

  func disableAutoOpen() {
    autoOpenEnabled = false
    cancelAutoOpen()
  }

  func resetAutoOpenSuppression() {
    autoOpenSuppressed = false
  }
}
