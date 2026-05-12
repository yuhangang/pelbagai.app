import Foundation
import HealthKit

@MainActor
struct HealthKitPlugin: NativePlugin {
    let id = "health_kit"
    let displayName = "Health"

    var capabilities: [NativePluginCapability] {
        [
            NativePluginCapability(
                id: "get_steps",
                displayName: "Get Steps",
                description: "Retrieve step count for today.",
                argumentSchema: [:],
                requiresUserApproval: false
            ),
            NativePluginCapability(
                id: "get_heart_rate",
                displayName: "Get Heart Rate",
                description: "Retrieve the most recent heart rate measurement.",
                argumentSchema: [:],
                requiresUserApproval: false
            )
        ]
    }

    var chatTools: [NativeChatTool] {
        [
            NativeChatTool(
                name: "get_step_count",
                displayName: "Step Count",
                description: "Use to retrieve the user's step count for today.",
                pluginID: id,
                capabilityID: "get_steps"
            ),
            NativeChatTool(
                name: "get_heart_rate",
                displayName: "Heart Rate",
                description: "Use to retrieve the user's latest heart rate.",
                pluginID: id,
                capabilityID: "get_heart_rate"
            )
        ]
    }

    func execute(capabilityID: String, arguments: [String: String]) async throws -> NativePluginResult {
        guard HKHealthStore.isHealthDataAvailable() else {
            return NativePluginResult(summary: "HealthKit is not available on this device.")
        }
        
        let store = HKHealthStore()
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        
        // Request authorization
        try await store.requestAuthorization(toShare: [], read: [stepType, heartRateType])

        switch capabilityID {
        case "get_steps":
            return try await getSteps(store: store, type: stepType)
        case "get_heart_rate":
            return try await getLatestHeartRate(store: store, type: heartRateType)
        default:
            throw NativePluginError.unknownCapability(pluginID: id, capabilityID: capabilityID)
        }
    }

    private func getSteps(store: HKHealthStore, type: HKQuantityType) async throws -> NativePluginResult {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                let steps = result?.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
                continuation.resume(returning: NativePluginResult(summary: "Today's steps: \(Int(steps))"))
            }
            store.execute(query)
        }
    }

    private func getLatestHeartRate(store: HKHealthStore, type: HKQuantityType) async throws -> NativePluginResult {
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: NativePluginResult(summary: "No heart rate data found."))
                    return
                }
                
                let hr = sample.quantity.doubleValue(for: HKUnit(from: "count/min"))
                continuation.resume(returning: NativePluginResult(summary: "Latest heart rate: \(Int(hr)) BPM"))
            }
            store.execute(query)
        }
    }
}
