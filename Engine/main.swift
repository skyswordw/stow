import Foundation

/// StowEngine.xpc — launched on demand by Stow, sandboxed, with no access to people's files of its
/// own. It reads an archive only because Stow hands it that URL, and writes only to its container.
final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: EngineXPCProtocol.self)
        // Before the service asks for its progress proxy, or the proxy has no interface to speak.
        connection.remoteObjectInterface = NSXPCInterface(with: EngineClientXPCProtocol.self)
        let service = EngineService(connection: connection)
        connection.exportedObject = service
        connection.invalidationHandler = { service.invalidate() }
        connection.resume()
        return true
    }
}

EngineService.removeStaleOutputs()
let delegate = ServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
