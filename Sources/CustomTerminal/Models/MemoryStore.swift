import Foundation
import Wax

actor MemoryStore {
    static let shared = MemoryStore()

    private var memory: Memory?

    func open() async {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let storeDir = appSupport.appendingPathComponent("Mosby")
        let storeURL = storeDir.appendingPathComponent("memory.wax")
        try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)

        var config = Memory.Config.default
        config.enableVectorSearch = false

        memory = try? await Memory(at: storeURL, config: config)
    }

    func remember(_ text: String, metadata: [String: String] = [:]) async {
        try? await memory?.save(text, metadata: metadata)
    }

    func recall(query: String) async -> [String] {
        guard let ctx = try? await memory?.search(query) else { return [] }
        return ctx.items.map { $0.text }
    }

    func flush() async {
        try? await memory?.flush()
    }

    func close() async {
        try? await memory?.close()
        memory = nil
    }
}
