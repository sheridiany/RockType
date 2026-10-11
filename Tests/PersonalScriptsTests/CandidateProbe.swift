// Standalone synthetic integration probe of the public librime API.
import Foundation

@_silgen_name("_Z23rime_require_module_luav")
func loadLuaModule()

let args = CommandLine.arguments
loadLuaModule()
let api = rime_get_api_stdbool().pointee
var traits = RimeTraits()
traits.data_size = Int32(MemoryLayout<RimeTraits>.size - MemoryLayout<Int32>.size)
traits.shared_data_dir = UnsafePointer(strdup(args[1]))
traits.user_data_dir = UnsafePointer(strdup(args[2]))
traits.staging_dir = UnsafePointer(strdup(args[3]))
traits.prebuilt_data_dir = UnsafePointer(strdup(args[3]))
traits.app_name = UnsafePointer(strdup("rime.rocktype.personal.tests"))
traits.log_dir = UnsafePointer(strdup(args[2]))
traits.min_log_level = 3
api.setup(&traits)
api.initialize(&traits)
let session = api.create_session()
guard session != 0 && api.select_schema(session, args[4]) else { exit(2) }
api.set_option(session, "ascii_mode", false)
for key in args[5].utf8 { _ = api.process_key(session, Int32(key), 0) }
var found = false
for _ in 0..<40 {
    var context = RimeContext_stdbool()
    context.data_size = Int32(MemoryLayout<RimeContext_stdbool>.size - MemoryLayout<Int32>.size)
    guard api.get_context(session, &context) else { exit(3) }
    if args[6] == "--first" {
        guard context.menu.num_candidates > 0 else { exit(5) }
        print(String(cString: context.menu.candidates[0].text))
        _ = api.free_context(&context)
        found = true
        break
    }
    for i in 0..<Int(context.menu.num_candidates) {
        if String(cString: context.menu.candidates[i].text) == args[6] { found = true }
    }
    let last = context.menu.is_last_page
    _ = api.free_context(&context)
    if found || last { break }
    guard api.change_page(session, false) else { break }
}
_ = api.destroy_session(session)
api.finalize()
exit(found ? 0 : 4)
