import Darwin

/// XPC cancellation can arrive while another thread is inside MLX/Metal.
/// Process-global destructors must not race that work; the OS reclaims worker resources.
enum WorkerTermination {
    static func terminate() -> Never {
        _exit(EXIT_SUCCESS)
    }
}
