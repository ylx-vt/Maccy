import AppKit
import KeyboardShortcuts
import SwiftUI

struct PreviewItemView: View {
  private static let largeTextThreshold = 1_000

  var item: HistoryItemDecorator
  @State private var zoom = ImagePreviewZoom()
  @GestureState private var isMagnifying = false

  @ViewBuilder
  func previewImage(content: @escaping () -> some View) -> some View {
    // The image (and its loading placeholder) must accept the sidebar's proposal,
    // rather than contributing a screen-sized intrinsic size to the window.
    GeometryReader { geometry in
      let size = ImagePreviewSizing.fittedSize(
        item.item.image?.size ?? ImagePreviewSizing.maximumSize,
        in: geometry.size
      )
      content()
        .frame(width: size.width, height: size.height)
        .clipShape(.rect(cornerRadius: 5))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(maxHeight: ImagePreviewSizing.maximumSize.height)
    .accessibilityIdentifier("image-preview")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if item.hasImage {
        AsyncView<NSImage?, _, _>(id: item.id) {
          return await item.asyncGetPreviewImage()
        } content: { image in
          if let image = image {
            VStack(spacing: 6) {
              GeometryReader { geometry in
                ZoomableImagePreview(image: item.item.image ?? image, identity: item.id, zoom: zoom)
                  .frame(width: min(geometry.size.width, ImagePreviewSizing.maximumSize.width))
                  // A nonempty hit surface is needed for gestures on recent macOS.
                  .background(Color.white.opacity(0.001))
                  .contentShape(Rectangle())
                  .highPriorityGesture(
                    MagnifyGesture(minimumScaleDelta: 0.005)
                      .updating($isMagnifying) { _, active, _ in active = true }
                      .onChanged { value in
                        zoom.updateMagnification(value.magnification, anchor: value.startAnchor)
                      }
                      .onEnded { _ in zoom.endMagnification() }
                  )
                  .frame(maxWidth: .infinity, maxHeight: .infinity)
              }
              .frame(maxHeight: ImagePreviewSizing.maximumSize.height)
              .clipShape(.rect(cornerRadius: 5))

              HStack(spacing: 12) {
                Spacer()
                Button(action: zoom.zoomOut) { Image(systemName: "minus.magnifyingglass") }
                  .accessibilityLabel(Text("ZoomOutImage", tableName: "PreviewItemView"))
                  .accessibilityIdentifier("zoom-out-image")
                Button(action: zoom.fit) { Text("FitImage", tableName: "PreviewItemView") }
                  .accessibilityIdentifier("fit-image")
                Button(action: zoom.zoomIn) { Image(systemName: "plus.magnifyingglass") }
                  .accessibilityLabel(Text("ZoomInImage", tableName: "PreviewItemView"))
                  .accessibilityIdentifier("zoom-in-image")
                Spacer()
              }
              .buttonStyle(.borderless)
              .excludeFromWindowMovableByBackground()
            }
            .help(Text("ImageZoomHint", tableName: "PreviewItemView"))
          } else {
            previewImage {
              ZStack {
                Color.gray.opacity(0.3)
                Image(systemName: "photo.badge.exclamationmark")
                  .symbolRenderingMode(.multicolor)
                  .frame(alignment: .center)
              }
            }
          }
        } placeholder: {
          previewImage {
            ZStack {
              Color.gray.opacity(0.3)
              ProgressView()
                .frame(alignment: .center)
            }
          }
        }
      } else {
        if item.previewText.byteCount >= Self.largeTextThreshold {
          LargeTextView(text: item.previewText.string)
            .id("textpreview-\(item.id)")
        } else {
          ScrollView {
            Text(item.previewText.string)
              .font(.body)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .frame(maxWidth: .infinity)
        }
      }

      Spacer(minLength: 0)

      Divider()
        .padding(.bottom)

      if let application = item.application {
        HStack(spacing: 3) {
          Text("Application", tableName: "PreviewItemView")
          AppImageView(
            appImage: item.applicationImage,
            size: NSSize(width: 11, height: 11)
          )
          Text(application)
        }
      }

      if item.hasImage, let image = item.item.image {
        HStack(spacing: 3) {
          Text("Dimensions", tableName: "PreviewItemView")
          Text("\(Int(image.pixelSize.width))×\(Int(image.pixelSize.height))")
        }
      }

      if item.hasImage, let size = item.imageSize {
        HStack(spacing: 3) {
          Text("Size", tableName: "PreviewItemView")
          Text(size)
        }
      }

      HStack(spacing: 3) {
        Text("FirstCopyTime", tableName: "PreviewItemView")
        Text(item.item.firstCopiedAt, style: .date)
        Text(item.item.firstCopiedAt, style: .time)
      }

      HStack(spacing: 3) {
        Text("LastCopyTime", tableName: "PreviewItemView")
        Text(item.item.lastCopiedAt, style: .date)
        Text(item.item.lastCopiedAt, style: .time)
      }

      HStack(spacing: 3) {
        Text("NumberOfCopies", tableName: "PreviewItemView")
        Text(String(item.item.numberOfCopies))
      }
    }
    .controlSize(.small)
    .onChange(of: isMagnifying) { _, active in
      // GestureState also resets after cancellation, which has no onEnded call.
      if !active { zoom.endMagnification() }
    }
  }
}

nonisolated enum ImagePreviewSizing {
  static let maximumSize = NSSize(width: 400, height: 480)

  static func fittedSize(_ image: NSSize, in available: NSSize) -> NSSize {
    guard image.width > 0, image.height > 0,
          available.width > 0, available.height > 0 else { return .zero }
    let scale = min(
      1,
      min(available.width, maximumSize.width) / image.width,
      min(available.height, maximumSize.height) / image.height
    )
    return NSSize(width: image.width * scale, height: image.height * scale)
  }
}
