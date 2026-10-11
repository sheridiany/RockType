//
//  SquirrelView.swift
//  Squirrel
//
//  Created by Leo Liu on 5/9/24.
//

import AppKit

@MainActor
private class SquirrelLayoutDelegate: NSObject, @preconcurrency NSTextLayoutManagerDelegate {
  func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, shouldBreakLineBefore location: any NSTextLocation, hyphenating: Bool) -> Bool {
    let index = textLayoutManager.offset(from: textLayoutManager.documentRange.location, to: location)
    if let attributes = textLayoutManager.textContainer?.textView?.textContentStorage?.attributedString?.attributes(at: index, effectiveRange: nil),
       let noBreak = attributes[.noBreak] as? Bool, noBreak {
      return false
    }
    return true
  }
}

extension NSAttributedString.Key {
  static let noBreak = NSAttributedString.Key("noBreak")
}

final class SquirrelView: NSView {
  var onSelect: ((Int) -> Void)?
  let textView: NSTextView

  private let squirrelLayoutDelegate: SquirrelLayoutDelegate
  var candidateRanges: [NSRange] = []
  var hilightedIndex = 0
  var preeditRange: NSRange = .empty
  var canPageUp: Bool = false
  var canPageDown: Bool = false
  var highlightedPreeditRange: NSRange = .empty
  var separatorWidth: CGFloat = 0
  var shape = CAShapeLayer()
  private var downPath: CGPath?
  private var upPath: CGPath?

  var lightTheme = SquirrelTheme()
  var darkTheme = SquirrelTheme()
  var currentTheme: SquirrelTheme {
    if isDark && darkTheme.available { darkTheme } else { lightTheme }
  }
  var textLayoutManager: NSTextLayoutManager {
    textView.textLayoutManager!
  }
  var textContentStorage: NSTextContentStorage {
    textView.textContentStorage!
  }
  var textContainer: NSTextContainer {
    textLayoutManager.textContainer!
  }

  override func isAccessibilityElement() -> Bool { true }
  override func accessibilityRole() -> NSAccessibility.Role? { .group }
  override func accessibilityLabel() -> String? { "候选" }
  override func accessibilityChildren() -> [Any]? {
    // Keep the existing keyboard/VoiceOver action with the restored text layout.
    candidateRanges.enumerated().compactMap { index, range in
      guard hilightedIndex >= 0, let textRange = convert(range: range),
            let text = textContentStorage.attributedString else { return nil }
      let element = CandidateAccessibilityElement()
      element.setAccessibilityParent(self)
      element.setAccessibilityRole(.button)
      element.setAccessibilityLabel(text.attributedSubstring(from: range).string)
      element.setAccessibilitySelected(index == hilightedIndex)
      let rect = contentRect(range: textRange).offsetBy(
        dx: textView.textContainerInset.width, dy: textView.textContainerInset.height)
      element.setAccessibilityFrame(window?.convertToScreen(textView.convert(rect, to: nil)) ?? .zero)
      element.press = { [weak self] in self?.onSelect?(index) }
      return element
    }
  }

  override init(frame frameRect: NSRect) {
    squirrelLayoutDelegate = SquirrelLayoutDelegate()
    textView = NSTextView(frame: frameRect)
    textView.drawsBackground = false
    textView.isEditable = false
    textView.isSelectable = false
    textView.textLayoutManager?.delegate = squirrelLayoutDelegate
    super.init(frame: frameRect)
    textContainer.lineFragmentPadding = 0
    self.wantsLayer = true
    self.layer?.masksToBounds = true
  }
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var isFlipped: Bool {
    true
  }
  var isDark: Bool {
    NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
  }

  func convert(range: NSRange) -> NSTextRange? {
    guard range != .empty else { return nil }
    guard let startLocation = textLayoutManager.location(textLayoutManager.documentRange.location, offsetBy: range.location) else { return nil }
    guard let endLocation = textLayoutManager.location(startLocation, offsetBy: range.length) else { return nil }
    return NSTextRange(location: startLocation, end: endLocation)
  }

  // Get the rectangle containing entire contents, expensive to calculate
  var contentRect: NSRect {
    var ranges = candidateRanges
    if preeditRange.length > 0 {
      ranges.append(preeditRange)
    }
    // swiftlint:disable:next identifier_name
    var x0 = CGFloat.infinity, x1 = -CGFloat.infinity, y0 = CGFloat.infinity, y1 = -CGFloat.infinity
    for range in ranges {
      if let textRange = convert(range: range) {
        let rect = contentRect(range: textRange)
        x0 = min(rect.minX, x0)
        x1 = max(rect.maxX, x1)
        y0 = min(rect.minY, y0)
        y1 = max(rect.maxY, y1)
      }
    }
    return NSRect(x: x0, y: y0, width: x1-x0, height: y1-y0)
  }
  // Get the rectangle containing the range of text, will first convert to glyph range, expensive to calculate
  func contentRect(range: NSTextRange) -> NSRect {
    // swiftlint:disable:next identifier_name
    var x0 = CGFloat.infinity, x1 = -CGFloat.infinity, y0 = CGFloat.infinity, y1 = -CGFloat.infinity
    textLayoutManager.enumerateTextSegments(in: range, type: .selection, options: [.rangeNotRequired]) { _, rect, _, _ in
      x0 = min(rect.minX, x0)
      x1 = max(rect.maxX, x1)
      y0 = min(rect.minY, y0)
      y1 = max(rect.maxY, y1)
      return true
    }
    return NSRect(x: x0, y: y0, width: x1-x0, height: y1-y0)
  }

  // Will triger - (void)drawRect:(NSRect)dirtyRect
  // swiftlint:disable:next function_parameter_count
  func drawView(candidateRanges: [NSRange], hilightedIndex: Int, preeditRange: NSRange, highlightedPreeditRange: NSRange, canPageUp: Bool, canPageDown: Bool) {
    self.candidateRanges = candidateRanges
    self.hilightedIndex = hilightedIndex
    self.preeditRange = preeditRange
    self.highlightedPreeditRange = highlightedPreeditRange
    self.canPageUp = canPageUp
    self.canPageDown = canPageDown
    self.needsDisplay = true
  }

  // All draws happen here
  // swiftlint:disable:next cyclomatic_complexity
  override func draw(_ dirtyRect: NSRect) {
    var backgroundPath: CGPath?
    var preeditPath: CGPath?
    var candidatePaths: CGMutablePath?
    var highlightedPath: CGMutablePath?
    var highlightedPreeditPath: CGMutablePath?
    let theme = currentTheme

    var containingRect = dirtyRect
    containingRect.size.width -= theme.pagingOffset
    let backgroundRect = containingRect

    // Draw preedit Rect
    var preeditRect = NSRect.zero
    if preeditRange.length > 0, let preeditTextRange = convert(range: preeditRange) {
      preeditRect = contentRect(range: preeditTextRange)
      preeditRect.size.width = backgroundRect.size.width
      preeditRect.size.height += theme.edgeInset.height + theme.preeditLinespace / 2 + theme.hilitedCornerRadius / 2
      preeditRect.origin = backgroundRect.origin
      if candidateRanges.count == 0 {
        preeditRect.size.height += theme.edgeInset.height - theme.preeditLinespace / 2 - theme.hilitedCornerRadius / 2
      }
      containingRect.size.height -= preeditRect.size.height
      containingRect.origin.y += preeditRect.size.height
      if theme.preeditBackgroundColor != nil {
        preeditPath = drawSmoothLines(rectVertex(of: preeditRect), straightCorner: Set(), alpha: 0, beta: 0)
      }
    }

    containingRect = carveInset(rect: containingRect)
    // Draw candidate Rects
    for i in 0..<candidateRanges.count {
      let candidate = candidateRanges[i]
      if i == hilightedIndex {
        // Draw highlighted Rect
        if candidate.length > 0 && theme.highlightedBackColor != nil {
          highlightedPath = drawPath(highlightedRange: candidate, backgroundRect: backgroundRect, preeditRect: preeditRect, containingRect: containingRect, extraExpansion: 0)?.mutableCopy()
        }
      } else {
        // Draw other highlighted Rect
        if candidate.length > 0 && theme.candidateBackColor != nil {
          let candidatePath = drawPath(highlightedRange: candidate, backgroundRect: backgroundRect, preeditRect: preeditRect,
                                       containingRect: containingRect, extraExpansion: theme.surroundingExtraExpansion)
          if candidatePaths == nil {
            candidatePaths = CGMutablePath()
          }
          if let candidatePath = candidatePath {
            candidatePaths?.addPath(candidatePath)
          }
        }
      }
    }

    // Draw highlighted part of preedit text
    if (highlightedPreeditRange.length > 0) && (theme.highlightedPreeditColor != nil), let highlightedPreeditTextRange = convert(range: highlightedPreeditRange) {
      var innerBox = preeditRect
      innerBox.size.width -= (theme.edgeInset.width + 1) * 2
      innerBox.origin.x += theme.edgeInset.width + 1
      innerBox.origin.y += theme.edgeInset.height + 1
      if candidateRanges.count == 0 {
        innerBox.size.height -= (theme.edgeInset.height + 1) * 2
      } else {
        innerBox.size.height -= theme.edgeInset.height + theme.preeditLinespace / 2 + theme.hilitedCornerRadius / 2 + 2
      }
      var outerBox = preeditRect
      outerBox.size.height -= max(0, theme.hilitedCornerRadius + theme.borderLineWidth)
      outerBox.size.width -= max(0, theme.hilitedCornerRadius + theme.borderLineWidth)
      outerBox.origin.x += max(0, theme.hilitedCornerRadius + theme.borderLineWidth) / 2
      outerBox.origin.y += max(0, theme.hilitedCornerRadius + theme.borderLineWidth) / 2

      let (leadingRect, bodyRect, trailingRect) = multilineRects(forRange: highlightedPreeditTextRange, extraSurounding: 0, bounds: outerBox)
      var (highlightedPoints, highlightedPoints2, rightCorners, rightCorners2) = linearMultilineFor(body: bodyRect, leading: leadingRect, trailing: trailingRect)

      containingRect = carveInset(rect: preeditRect)
      highlightedPoints = expand(vertex: highlightedPoints, innerBorder: innerBox, outerBorder: outerBox)
      rightCorners = removeCorner(highlightedPoints: highlightedPoints, rightCorners: rightCorners, containingRect: containingRect)
      highlightedPreeditPath = drawSmoothLines(highlightedPoints, straightCorner: rightCorners, alpha: 0.3 * theme.hilitedCornerRadius, beta: 1.4 * theme.hilitedCornerRadius)?.mutableCopy()
      if highlightedPoints2.count > 0 {
        highlightedPoints2 = expand(vertex: highlightedPoints2, innerBorder: innerBox, outerBorder: outerBox)
        rightCorners2 = removeCorner(highlightedPoints: highlightedPoints2, rightCorners: rightCorners2, containingRect: containingRect)
        let highlightedPreeditPath2 = drawSmoothLines(highlightedPoints2, straightCorner: rightCorners2, alpha: 0.3 * theme.hilitedCornerRadius, beta: 1.4 * theme.hilitedCornerRadius)
        if let highlightedPreeditPath2 = highlightedPreeditPath2 {
          highlightedPreeditPath?.addPath(highlightedPreeditPath2)
        }
      }
    }

    NSBezierPath.defaultLineWidth = 0
    backgroundPath = drawSmoothLines(rectVertex(of: backgroundRect), straightCorner: Set(), alpha: 0.3 * theme.cornerRadius, beta: 1.4 * theme.cornerRadius)

    self.layer?.sublayers = nil
    let backPath = backgroundPath?.mutableCopy()
    if let path = preeditPath {
      backPath?.addPath(path)
    }
    if theme.mutualExclusive {
      if let path = highlightedPath {
        backPath?.addPath(path)
      }
      if let path = candidatePaths {
        backPath?.addPath(path)
      }
    }
    let panelLayer = shapeFromPath(path: backPath)
    panelLayer.fillColor = theme.backgroundColor.cgColor
    let panelLayerMask = shapeFromPath(path: backgroundPath)
    panelLayer.mask = panelLayerMask
    self.layer?.addSublayer(panelLayer)

    // Fill in colors
    if let color = theme.preeditBackgroundColor, let path = preeditPath {
      let layer = shapeFromPath(path: path)
      layer.fillColor = color.cgColor
      let maskPath = backgroundPath?.mutableCopy()
      if theme.mutualExclusive, let hilitedPath = highlightedPreeditPath {
        maskPath?.addPath(hilitedPath)
      }
      let mask = shapeFromPath(path: maskPath)
      layer.mask = mask
      panelLayer.addSublayer(layer)
    }
    if theme.borderLineWidth > 0, let color = theme.borderColor {
      let borderLayer = shapeFromPath(path: backgroundPath)
      borderLayer.lineWidth = theme.borderLineWidth * 2
      borderLayer.strokeColor = color.cgColor
      borderLayer.fillColor = nil
      panelLayer.addSublayer(borderLayer)
    }
    if let color = theme.highlightedPreeditColor, let path = highlightedPreeditPath {
      let layer = shapeFromPath(path: path)
      layer.fillColor = color.cgColor
      panelLayer.addSublayer(layer)
    }
    if let color = theme.candidateBackColor, let path = candidatePaths {
      let layer = shapeFromPath(path: path)
      layer.fillColor = color.cgColor
      panelLayer.addSublayer(layer)
    }
    if let color = theme.highlightedBackColor, let path = highlightedPath {
      let layer = shapeFromPath(path: path)
      layer.fillColor = color.cgColor
      if theme.shadowSize > 0 {
        let shadowLayer = CAShapeLayer()
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOffset = NSSize(width: theme.shadowSize/2, height: (theme.vertical ? -1 : 1) * theme.shadowSize/2)
        shadowLayer.shadowPath = highlightedPath
        shadowLayer.shadowRadius = theme.shadowSize
        shadowLayer.shadowOpacity = 0.2
        let outerPath = backgroundPath?.mutableCopy()
        outerPath?.addPath(path)
        let shadowLayerMask = shapeFromPath(path: outerPath)
        shadowLayer.mask = shadowLayerMask
        layer.strokeColor = NSColor.black.withAlphaComponent(0.15).cgColor
        layer.lineWidth = 0.5
        layer.addSublayer(shadowLayer)
      }
      panelLayer.addSublayer(layer)
    }
    panelLayer.setAffineTransform(CGAffineTransform(translationX: theme.pagingOffset, y: 0))
    let panelPath = CGMutablePath()
    panelPath.addPath(backgroundPath!, transform: panelLayer.affineTransform().scaledBy(x: 1, y: -1).translatedBy(x: 0, y: -dirtyRect.height))

    let (pagingLayer, downPath, upPath) = pagingLayer(theme: theme, preeditRect: preeditRect)
    if let sublayers = pagingLayer.sublayers, !sublayers.isEmpty {
      self.layer?.addSublayer(pagingLayer)
    }
    self.downPath = downPath?.copy()
    self.upPath = upPath?.copy()
    let flipTransform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -dirtyRect.height)
    if let downPath {
      panelPath.addPath(downPath, transform: flipTransform)
    }
    if let upPath {
      panelPath.addPath(upPath, transform: flipTransform)
    }

    shape.path = panelPath
  }

  func click(at clickPoint: NSPoint) -> (Int?, Int?, Bool?) {
    var index = 0
    var candidateIndex: Int?
    var preeditIndex: Int?
    if let downPath = self.downPath, downPath.contains(clickPoint) {
      return (nil, nil, false)
    }
    if let upPath = self.upPath, upPath.contains(clickPoint) {
      return (nil, nil, true)
    }
    if let path = shape.path, path.contains(clickPoint) {
      var point = NSPoint(x: clickPoint.x - textView.textContainerInset.width - currentTheme.pagingOffset,
                          y: clickPoint.y - textView.textContainerInset.height)
      let fragment = textLayoutManager.textLayoutFragment(for: point)
      if let fragment = fragment {
        point = NSPoint(x: point.x - fragment.layoutFragmentFrame.minX,
                        y: point.y - fragment.layoutFragmentFrame.minY)
        index = textLayoutManager.offset(from: textLayoutManager.documentRange.location, to: fragment.rangeInElement.location)
        for lineFragment in fragment.textLineFragments where lineFragment.typographicBounds.contains(point) {
          point = NSPoint(x: point.x - lineFragment.typographicBounds.minX,
                          y: point.y - lineFragment.typographicBounds.minY)
          index += lineFragment.characterIndex(for: point)
          if index >= preeditRange.location && index < preeditRange.upperBound {
            preeditIndex = index
          } else {
            for i in 0..<candidateRanges.count {
              let range = candidateRanges[i]
              if index >= range.location && index < range.upperBound {
                candidateIndex = i
                break
              }
            }
          }
          break
        }
      }
    }
    return (candidateIndex, preeditIndex, nil)
  }
}


private final class CandidateAccessibilityElement: NSAccessibilityElement {
  var press: (() -> Void)?
  override func accessibilityPerformPress() -> Bool {
    press?()
    return true
  }
}
