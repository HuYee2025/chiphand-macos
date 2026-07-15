import Foundation
import Network

final class LocalMediaServer {
    enum ServerError: LocalizedError {
        case missingPort

        var errorDescription: String? {
            switch self {
            case .missingPort: "无法取得本机 MediaPipe 服务端口"
            }
        }
    }

    private let root: URL
    private let queue = DispatchQueue(label: "com.huyee.gesture-control.mediapipe-http")
    private var listener: NWListener?

    init(root: URL) {
        self.root = root.standardizedFileURL
    }

    func start(completion: @escaping (Result<URL, Error>) -> Void) {
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            let listener = try NWListener(using: parameters)
            self.listener = listener
            listener.newConnectionHandler = { [root] connection in
                Self.serve(connection: connection, root: root)
            }
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self, let listener, self.listener === listener else { return }
                switch state {
                case .ready:
                    guard let port = listener.port,
                          let url = URL(string: "http://127.0.0.1:\(port.rawValue)/") else {
                        DispatchQueue.main.async { completion(.failure(ServerError.missingPort)) }
                        return
                    }
                    DispatchQueue.main.async { completion(.success(url)) }
                case let .failed(error):
                    DispatchQueue.main.async { completion(.failure(error)) }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        } catch {
            completion(.failure(error))
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private static func serve(connection: NWConnection, root: URL) {
        connection.start(queue: DispatchQueue.global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) {
            data, _, _, error in
            guard error == nil,
                  let data,
                  let request = String(data: data, encoding: .utf8),
                  let requestLine = request.split(separator: "\r\n").first else {
                connection.cancel()
                return
            }
            let parts = requestLine.split(separator: " ")
            guard parts.count >= 2 else {
                send(status: "400 Bad Request", body: Data(), mime: "text/plain", connection: connection)
                return
            }
            let method = String(parts[0])
            guard method == "GET" || method == "HEAD" else {
                send(status: "405 Method Not Allowed", body: Data(), mime: "text/plain", connection: connection)
                return
            }
            let rawTarget = String(parts[1]).split(separator: "?", maxSplits: 1).first.map(String.init) ?? "/"
            let decoded = rawTarget.removingPercentEncoding ?? rawTarget
            let relative = decoded.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !relative.isEmpty,
                  !relative.split(separator: "/").contains("..") else {
                send(status: "404 Not Found", body: Data(), mime: "text/plain", connection: connection)
                return
            }
            let file = root.appendingPathComponent(relative).standardizedFileURL
            guard file.path.hasPrefix(root.path + "/"),
                  let body = try? Data(contentsOf: file) else {
                send(status: "404 Not Found", body: Data(), mime: "text/plain", connection: connection)
                return
            }
            send(
                status: "200 OK",
                body: method == "HEAD" ? Data() : body,
                contentLength: body.count,
                mime: mimeType(for: file.pathExtension),
                connection: connection
            )
        }
    }

    private static func mimeType(for extensionName: String) -> String {
        switch extensionName.lowercased() {
        case "html": "text/html; charset=utf-8"
        case "js": "text/javascript; charset=utf-8"
        case "wasm": "application/wasm"
        case "task": "application/octet-stream"
        default: "application/octet-stream"
        }
    }

    private static func send(
        status: String,
        body: Data,
        contentLength: Int? = nil,
        mime: String,
        connection: NWConnection
    ) {
        let header = """
        HTTP/1.1 \(status)\r
        Content-Type: \(mime)\r
        Content-Length: \(contentLength ?? body.count)\r
        Cache-Control: no-store\r
        Connection: close\r
        \r

        """
        var response = Data(header.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
