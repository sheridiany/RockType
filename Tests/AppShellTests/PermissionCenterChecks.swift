import RoarkTPlatform

@main struct PermissionCenterChecks {
    @MainActor static func main() async {
        var statuses: [Permissions.Kind: Permissions.Status] = [.accessibility: .notGranted, .screenRecording: .granted, .microphone: .notDetermined]
        var requests: [Permissions.Kind] = []
        var opened: [Permissions.Kind] = []
        let center = PermissionCenter(read: { statuses[$0]! }, request: {
            requests.append($0); statuses[$0] = .denied
        }, open: { opened.append($0); return false })
        precondition(requests.isEmpty)
        center.start(); center.start(); center.stop()
        precondition(requests.isEmpty, "Polling must never request access")
        await center.request(.microphone)
        precondition(requests == [.microphone])
        precondition(center.items.first { $0.kind == .microphone }?.status == .denied)
        statuses[.microphone] = .granted; center.refresh()
        precondition(center.items.first { $0.kind == .microphone }?.status == .granted)
        statuses[.microphone] = .denied; center.refresh()
        precondition(center.items.first { $0.kind == .microphone }?.status == .denied)
        center.openSettings(.screenRecording)
        precondition(opened == [.screenRecording] && center.message != nil)
        precondition(center.requesting == nil)
        print("Permission center checks passed")
    }
}
