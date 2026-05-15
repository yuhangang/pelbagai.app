import Foundation
import Network
import Combine

class NetworkService: ObservableObject {
    static let shared = NetworkService()
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    @Published var isExpensive: Bool = false
    @Published var isConstrained: Bool = false
    @Published var interfaceType: NWInterface.InterfaceType = .other
    
    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isExpensive = path.isExpensive
                self?.isConstrained = path.isConstrained
                
                if path.usesInterfaceType(.wifi) {
                    self?.interfaceType = .wifi
                } else if path.usesInterfaceType(.cellular) {
                    self?.interfaceType = .cellular
                } else if path.usesInterfaceType(.wiredEthernet) {
                    self?.interfaceType = .wiredEthernet
                } else {
                    self?.interfaceType = .other
                }
            }
        }
        monitor.start(queue: queue)
    }
    
    var isCellularOrHotspot: Bool {
        // isExpensive is true for cellular and most hotspots
        return interfaceType == .cellular || isExpensive
    }
}
