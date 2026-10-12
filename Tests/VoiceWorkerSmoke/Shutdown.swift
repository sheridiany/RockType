import Darwin
import Foundation

// An ordinary exit runs process-global destructors on the calling XPC thread.
// The sentinel makes that unsafe path deterministic without crashing Metal or loading a model.
@main enum WorkerShutdownCheck {
    static func main() {
        atexit { _exit(99) }
        DispatchQueue.global().async { WorkerTermination.terminate() }
        dispatchMain()
    }
}
