// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

@_silgen_name("_Z23rime_require_module_luav")
func requireLua()

/// Real librime, factory schemas and private profiles; each invocation is a fresh process.
@main
struct RimeChecks {
  static func require(_ condition: @autoclosure () -> Bool, _ reason: String) {
    guard condition() else { fatalError(reason) }
  }
  static func main() {
    require(CommandLine.arguments.count == 6, "shared user build schema action required")
    let args = CommandLine.arguments
    requireLua()
    let api = rime_get_api_stdbool().pointee
    var traits = RimeTraits.rimeStructInit()
    traits.setCString(args[1], to: \.shared_data_dir)
    traits.setCString(args[2], to: \.user_data_dir)
    traits.setCString(args[3], to: \.staging_dir)
    traits.setCString(args[3], to: \.prebuilt_data_dir)
    traits.setCString("rime.roarkt.tests", to: \.app_name)
    traits.setCString(args[2], to: \.log_dir)
    traits.min_log_level = 3
    api.setup(&traits)
    api.initialize(&traits)
    let session = api.create_session()
    require(session != 0 && api.select_schema(session, args[4]), "schema selection")
    defer {
      _ = api.destroy_session(session)
      api.finalize()
    }
    api.set_property(session, "roarkt_translation_presentation", "panel")
    func refresh() { _ = api.simulate_key_sequence(session, "{F19}") }
    func property(_ name: String) -> String {
      var buffer = [CChar](repeating: 0, count: 16384)
      return api.get_property(session, name, &buffer, buffer.count) ? String(cString: buffer) : ""
    }
    func input(_ text: String) {
      api.clear_composition(session)
      api.set_option(session, "ascii_mode", false)
      for byte in text.utf8 {
        _ = api.process_key(session, Int32(byte), 0)
        refresh()
      }
    }
    func page() -> (words: [String], last: Bool, number: Int) {
      var context = RimeContext_stdbool.rimeStructInit()
      require(api.get_context(session, &context), "context")
      defer { _ = api.free_context(&context) }
      require(
        context.menu.page_size == 5 && context.menu.num_candidates <= 5, "five numbered candidates")
      let words = (0..<Int(context.menu.num_candidates)).map {
        String(cString: context.menu.candidates[$0].text)
      }
      return (words, context.menu.is_last_page, Int(context.menu.page_no))
    }
    func find(_ word: String) -> Int? {
      for _ in 0..<4096 {
        let current = page()
        if let index = current.words.firstIndex(of: word) { return current.number * 5 + index }
        if current.last { return nil }
        require(api.change_page(session, false), "page traversal")
        refresh()
      }
      fatalError("unbounded candidate traversal")
    }
    func consume(_ expected: String) {
      var commit = RimeCommit.rimeStructInit()
      require(api.get_commit(session, &commit), "missing commit: \(expected)")
      let actual = String(cString: commit.text)
      _ = api.free_commit(&commit)
      require(actual == expected, "commit expected \(expected), got \(actual)")
      refresh()
    }
    let reading = args[4] == "roarkt_flypy" ? "uijm" : "shijian"
    switch args[5] {
    case "samples":
      let samples =
        args[4] == "roarkt_flypy"
        ? [("nihc", "你好"), ("vsgo", "中国"), ("uijm", "时间")]
        : [("nihao", "你好"), ("zhongguo", "中国"), ("shijian", "时间")]
      for (raw, expected) in samples {
        input(raw)
        require(
          page().words.first == expected, "\(raw): expected first \(expected), got \(page().words)")
        require(api.select_candidate_on_current_page(session, 0), "select first")
        consume(expected)
      }
      // Fuzzy, abbreviation, spelling correction and transposed key samples.
      let cases =
        args[4] == "roarkt_flypy"
        ? [("vi", "字"), ("ni", "里")]
        : [("zongguo", "中国"), ("nh", "你好"), ("zhogn", "中"), ("nihoa", "你好")]
      for (raw, expected) in cases {
        input(raw)
        require(find(expected) != nil, "tolerant \(args[4]) \(raw) must include \(expected)")
      }
      print(
        "samples passed: \(args[4]); exact first, fuzzy/abbreviation/correction where applicable")
    case "shift":
      for key: Int32 in [0xffe1, 0xffe2] {
        input(args[4] == "roarkt_flypy" ? "nihc" : "nihao")
        _ = api.process_key(session, key, 1)
        refresh()
        _ = api.process_key(session, key, 1 << 30)
        require(api.get_option(session, "ascii_mode"), "Shift release enters English")
        consume(args[4] == "roarkt_flypy" ? "nihc" : "nihao")
        _ = api.commit_composition(session)
        require(api.get_option(session, "ascii_mode"), "English remains after composition")
        _ = api.process_key(session, key, 1)
        refresh()
        _ = api.process_key(session, key, 1 << 30)
        require(!api.get_option(session, "ascii_mode"), "Shift returns to Chinese")
        _ = api.process_key(session, key, 1)
        _ = api.process_key(session, 65, 1)
        _ = api.process_key(session, key, 1 << 30)
        require(!api.get_option(session, "ascii_mode"), "Shift+letter must not toggle")
      }
      print("Shift passed: \(args[4]), both sides, persistent English and letter chords")
    case "shift-prefix":
      let raw = args[4] == "roarkt_flypy" ? "ykwfuu" : "yingwenshu"
      let suffix = args[4] == "roarkt_flypy" ? "uu" : "shu"
      for key: Int32 in [0xffe1, 0xffe2] {
        input(raw)
        guard let rank = find("英文") else { fatalError("missing prefix candidate") }
        require(api.select_candidate_on_current_page(session, rank % 5), "confirm prefix")
        refresh()
        _ = api.process_key(session, key, 1)
        refresh()
        _ = api.process_key(session, key, 1 << 30)
        require(api.get_option(session, "ascii_mode"), "prefix Shift enters English")
        consume("英文" + suffix)
      }
      print("Shift confirmed-prefix/raw-suffix commit passed: \(args[4])")
    case "homophones":
      // Technical priorities must leave the most common everyday homophones first.
      for (pinyin, flypy, expected) in [
        ("duiqi", "dvqi", "对其"), ("xiancun", "xmcy", "现存"),
        ("yibu", "yibu", "一步"), ("zujian", "zujm", "逐渐"),
        ("huidiao", "hvdn", "毁掉"), ("tongshi", "tsui", "同时"),
        ("duandian", "drdm", "断电"), ("liantiao", "lmtn", "链条"),
        ("xiecheng", "xpig", "写成"), ("xiancheng", "xmig", "县城"),
      ] {
        input(args[4] == "roarkt_flypy" ? flypy : pinyin)
        require(page().words.first == expected, "everyday homophone first: \(expected), got \(page().words)")
      }
      print("Everyday homophone priorities passed: \(args[4])")
    case "domain":
      // Both schemes must encode the same domain terms, including polyphonic readings.
      let samples: [(String, String, String)] = [
        ("damoxing", "damoxk", "大模型"),
        ("tishici", "tiuici", "提示词"),
        ("zhinengti", "vingti", "智能体"),
        ("weitiao", "wwtn", "微调"),
        ("chongpaixu", "ispdxu", "重排序"),
        ("liantiao", "lmtn", "联调"),
        ("tiaoshi", "tnui", "调试"),
        ("huidiao", "hvdn", "回调"),
        ("xiangliangshujuku", "xllluujuku", "向量数据库"),
        ("gongjudiaoyong", "gsjudnys", "工具调用"),
        ("siweilian", "siwwlm", "思维链"),
        ("hanggao", "hhgc", "行高"),
        ("yaoshichuan", "ycuiir", "钥匙串"),
      ]
      for (pinyin, flypy, expected) in samples {
        input(args[4] == "roarkt_flypy" ? flypy : pinyin)
        guard let rank = find(expected) else { fatalError("missing domain reading: \(expected)") }
        require(api.select_candidate_on_current_page(session, rank % 5), "domain selection")
        consume(expected)
      }
      print("Domain readings and commits passed: \(args[4])")
    case "english":

      // Lowercase lookup preserves canonical case/punctuation when actually committed.
      for (raw, expected) in [
        ("llm", "LLM"), ("rag", "RAG"), ("mcp", "MCP"), ("agent", "Agent"),
        ("prompt", "prompt"), ("token", "token"), ("embedding", "embedding"),
        ("finetune", "fine-tune"), ("claude", "Claude"), ("gpt", "GPT"),
        ("gemini", "Gemini"), ("codex", "Codex"), ("cursor", "Cursor"),
        ("copilot", "Copilot"), ("openai", "OpenAI"), ("anthropic", "Anthropic"),
        ("swiftui", "SwiftUI"), ("xcode", "Xcode"), ("github", "GitHub"),
        ("api", "API"), ("sdk", "SDK"), ("json", "JSON"), ("yaml", "YAML"),
        ("kubernetes", "Kubernetes"),
      ] {
        input(raw)
        guard let rank = find(expected) else { fatalError("missing English casing: \(expected)") }
        require(api.select_candidate_on_current_page(session, rank % 5), "English selection")
        consume(expected)
      }
      input("what'are'you'doing")
      require(find("what are you doing") != nil, "apostrophe phrase candidate")
      let words = page().words
      require(
        api.select_candidate_on_current_page(session, words.firstIndex(of: "what are you doing")!),
        "phrase selection")
      consume("what are you doing")
      for (raw, expected) in [("gith", "github"), ("dock", "docker"), ("compu", "computer")] {
        input(raw)
        require(
          page().words.map { $0.lowercased() }.contains(expected), "English completion \(raw)")
      }
      let blocked: Set<String> = ["aaaah", "aargh", "aagh", "fuck", "fuckin", "fucking"]
      for raw in blocked {
        input(raw)
        var reachedEnd = false
        for _ in 0..<4096 {
          let current = page()
          require(
            current.words.allSatisfy { !blocked.contains($0.lowercased()) },
            "blocked English candidate")
          if current.last { reachedEnd = true; break }
          require(api.change_page(session, false), "blocked-word traversal")
        }
        require(reachedEnd, "blocked-word traversal exceeded safety bound")
      }
      print("English phrase/completion/blocklist passed: \(args[4])")
    case "baseline", "verify", "forgotten":
      input(reading)
      if args[5] == "verify" {
        require(page().words.first == "事件", "learning survives restart/schema switch")
      } else {
        require(page().words.first == "时间", "factory first must be restored")
        require((find("事件") ?? -1) > 0, "factory word still available below first")
        if args[5] == "forgotten" {
          let rank = find("事件")!
          _ = api.highlight_candidate_on_current_page(session, rank % 5)
          refresh()
          require(property("roarkt_panel_can_forget") == "0", "deleted learning is gone")
        }
      }
      print("\(args[5]) passed: \(args[4])")
    case "train":
      for _ in 0..<3 {
        input(reading)
        guard let rank = find("事件") else { fatalError("missing learning sample") }
        require(api.select_candidate_on_current_page(session, rank % 5), "learn selected word")
        consume("事件")
        _ = api.simulate_key_sequence(session, "{Return}")
        refresh()
      }
      print("learning trained: \(args[4])")
    case "forget":
      input(reading)
      guard let rank = find("事件") else { fatalError("missing learned word") }
      _ = api.highlight_candidate_on_current_page(session, rank % 5)
      refresh()
      require(property("roarkt_panel_can_forget") == "1", "learning menu action available")
      require(api.delete_candidate_on_current_page(session, rank % 5), "forget learned word")
      refresh()
      print("forget action passed: \(args[4])")
    case "translation":
      input(args[4] == "roarkt_flypy" ? "nihc" : "nihao")
      require(property("roarkt_panel_source") == "你好", "translation source")
      let oldIdentity = property("roarkt_panel_identity")
      for key in ["raw", "source", "identity", "scope"] {
        api.set_property(session, "roarkt_panel_commit_" + key, property("roarkt_panel_" + key))
      }
      api.set_property(session, "roarkt_panel_commit_text", "hello")
      require(api.highlight_candidate_on_current_page(session, 1), "change selection")
      refresh()
      require(property("roarkt_panel_identity") != oldIdentity, "selection changes identity")
      _ = api.simulate_key_sequence(session, "{F20}")
      require(property("roarkt_panel_committed") != "1", "old translation must not commit")
      require(api.change_page(session, false), "next page")
      refresh()
      require(property("roarkt_panel_identity") != oldIdentity, "page changes identity")
      input(args[4] == "roarkt_flypy" ? "nihc" : "nihao")
      for key in ["raw", "source", "identity", "scope"] {
        api.set_property(session, "roarkt_panel_commit_" + key, property("roarkt_panel_" + key))
      }
      api.set_property(session, "roarkt_panel_commit_text", "hello")
      _ = api.simulate_key_sequence(session, "{F20}")
      require(property("roarkt_panel_committed") == "1", "current translation commits")
      consume("hello")
      print("translation identity/page/commit passed: \(args[4])")
    default: fatalError("unknown action")
    }
  }
}
