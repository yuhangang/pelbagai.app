import Foundation
import Darwin

/// Memory usage utility for monitoring application footprint and jetsam limits.
enum MemoryStats {

    /// (footprint MB, jetsam limit MB) via task_info.
    static func footprintMB() -> (Double, Double) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return (0, 0) }
        let footprint = Double(info.phys_footprint) / 1_048_576
        let limit = Double(info.limit_bytes_remaining) / 1_048_576 + footprint
        return (footprint, limit)
    }

    /// Current available memory headroom (MB), used for safety checks before heavy inference.
    static var headroomMB: Int {
        let (footprint, limit) = footprintMB()
        #if os(macOS)
        // On macOS, task_vm_info.limit_bytes_remaining is always 0.
        // Simulate a typical high-end iPhone jetsam limit (~6GB) for testing.
        let simulatedJetsamMB = 6144
        return max(0, simulatedJetsamMB - Int(footprint))
        #else
        return max(0, Int(limit - footprint))
        #endif
    }

    /// Total physical memory in GB.
    static var totalMemoryGB: Double {
        Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
    }
}
