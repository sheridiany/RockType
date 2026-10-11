import Foundation
import Testing
import RoarkTCore
@testable import RoarkTApp

@Test func toolbarPlacementAvoidsSelectionAndClampsToNegativeDisplay() {
    let screen = CGRect(x: -1440, y: -200, width: 1440, height: 900)
    for selected in [CGRect(x: -1300, y: 200, width: 600, height: 40), CGRect(x: -1400, y: -190, width: 1000, height: 50)] {
        let frame = SelectionToolbarLayout.frame(selection: selected, cursor: CGPoint(x: selected.maxX, y: selected.midY),
            size: CGSize(width: 400, height: 40), screen: screen)
        #expect(screen.contains(frame))
        #expect(!frame.intersects(selected))
    }
    let frame = SelectionToolbarLayout.frame(selection: nil, cursor: CGPoint(x: -1, y: -199),
        size: CGSize(width: 400, height: 40), screen: screen)
    #expect(screen.contains(frame))
}

@Test @MainActor func toolbarOrderFiltersDisabledUnknownDuplicatesAndImageActions() {
    var settings = AppSettings()
    settings.templates.append(.init(id: "image", name: "Image", icon: "photo", prompt: "", input: .image))
    settings.selection.toolbarActions = ["explain", "copy", "translate", "explain", "gone", "image", "search"]
    settings.selection.disabledActions = ["translate"]
    let actions = SelectionToolbarAction.configured(in: settings, aiConfigured: false)
    #expect(actions.map(\.id) == ["explain", "copy", "search"])
    #expect(actions.map(\.enabled) == [false, true, true])
}
