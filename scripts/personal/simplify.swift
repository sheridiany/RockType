import Foundation

// ICU is supplied by macOS. Contents use private pipes, never arguments or logs.
let data = FileHandle.standardInput.readDataToEndOfFile()
guard let text = String(data: data, encoding: .utf8),
      let simplified = text.applyingTransform(StringTransform("Hant-Hans"), reverse: false)
else { exit(1) }
FileHandle.standardOutput.write(Data(simplified.utf8))
