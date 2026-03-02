import Foundation

final class FileWatcher {
    enum Event {
        case modified
        case deleted
        case renamed
    }

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let queue = DispatchQueue(label: "com.markdowneditor.filewatcher", qos: .utility)

    var onChange: ((Event) -> Void)?

    func start(url: URL) {
        stop()
        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            guard let self, let source = self.source else { return }
            let flags = source.data
            if flags.contains(.delete) {
                DispatchQueue.main.async { self.onChange?(.deleted) }
            } else if flags.contains(.rename) {
                DispatchQueue.main.async { self.onChange?(.renamed) }
            } else if flags.contains(.write) {
                DispatchQueue.main.async { self.onChange?(.modified) }
            }
        }

        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }

        self.source = source
        source.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    deinit {
        stop()
    }
}
