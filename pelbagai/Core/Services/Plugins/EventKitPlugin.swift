import Foundation
import EventKit

@MainActor
struct EventKitPlugin: NativePlugin {
    let id = "event_kit"
    let displayName = "Calendar & Reminders"

    var capabilities: [NativePluginCapability] {
        [
            NativePluginCapability(
                id: "create_event",
                displayName: "Create Event",
                description: "Add a new event to the calendar.",
                argumentSchema: [
                    "title": "Title of the event",
                    "startDate": "Start date in ISO8601 format",
                    "endDate": "End date in ISO8601 format"
                ],
                requiresUserApproval: true
            ),
            NativePluginCapability(
                id: "list_events",
                displayName: "List Events",
                description: "List calendar events for a specific date range.",
                argumentSchema: [
                    "startDate": "Start date (ISO8601)",
                    "endDate": "End date (ISO8601)"
                ],
                requiresUserApproval: false
            ),
            NativePluginCapability(
                id: "create_reminder",
                displayName: "Create Reminder",
                description: "Add a new reminder.",
                argumentSchema: ["title": "Title of the reminder"],
                requiresUserApproval: true
            ),
            NativePluginCapability(
                id: "list_reminders",
                displayName: "List Reminders",
                description: "List all incomplete reminders.",
                argumentSchema: [:],
                requiresUserApproval: false
            )
        ]
    }

    var chatTools: [NativeChatTool] {
        [
            NativeChatTool(
                name: "add_calendar_event",
                displayName: "Add Calendar Event",
                description: "Use to schedule something in the user's calendar.",
                pluginID: id,
                capabilityID: "create_event"
            ),
            NativeChatTool(
                name: "get_calendar_events",
                displayName: "Get Calendar Events",
                description: "Use to check the user's schedule.",
                pluginID: id,
                capabilityID: "list_events"
            ),
            NativeChatTool(
                name: "add_reminder",
                displayName: "Add Reminder",
                description: "Use to create a reminder or to-do item.",
                pluginID: id,
                capabilityID: "create_reminder"
            ),
            NativeChatTool(
                name: "get_reminders",
                displayName: "Get Reminders",
                description: "Use to list existing reminders.",
                pluginID: id,
                capabilityID: "list_reminders"
            )
        ]
    }

    func execute(capabilityID: String, arguments: [String: String]) async throws -> NativePluginResult {
        let eventStore = EKEventStore()
        
        // Request access
        if #available(iOS 17.0, *) {
            // New iOS 17 permission model
            if capabilityID.contains("event") {
                let status = EKEventStore.authorizationStatus(for: .event)
                if status == .notDetermined {
                    try await eventStore.requestFullAccessToEvents()
                } else if status == .denied {
                    return NativePluginResult(summary: "Calendar access denied.")
                }
            } else {
                let status = EKEventStore.authorizationStatus(for: .reminder)
                if status == .notDetermined {
                    try await eventStore.requestFullAccessToReminders()
                } else if status == .denied {
                    return NativePluginResult(summary: "Reminders access denied.")
                }
            }
        } else {
            // Legacy permission model
            let entityType: EKEntityType = capabilityID.contains("event") ? .event : .reminder
            let status = EKEventStore.authorizationStatus(for: entityType)
            if status == .notDetermined {
                _ = try await eventStore.requestAccess(to: entityType)
            } else if status == .denied {
                return NativePluginResult(summary: "Access denied.")
            }
        }

        switch capabilityID {
        case "create_event":
            return try createEvent(store: eventStore, title: arguments["title"] ?? "", startStr: arguments["startDate"] ?? "", endStr: arguments["endDate"] ?? "")
        case "list_events":
            return try listEvents(store: eventStore, startStr: arguments["startDate"] ?? "", endStr: arguments["endDate"] ?? "")
        case "create_reminder":
            return try createReminder(store: eventStore, title: arguments["title"] ?? "")
        case "list_reminders":
            return try await listReminders(store: eventStore)
        default:
            throw NativePluginError.unknownCapability(pluginID: id, capabilityID: capabilityID)
        }
    }

    private func createEvent(store: EKEventStore, title: String, startStr: String, endStr: String) throws -> NativePluginResult {
        let formatter = ISO8601DateFormatter()
        guard let startDate = formatter.date(from: startStr),
              let endDate = formatter.date(from: endStr) else {
            return NativePluginResult(summary: "Invalid date format. Use ISO8601.")
        }
        
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.calendar = store.defaultCalendarForNewEvents
        
        try store.save(event, span: .thisEvent)
        return NativePluginResult(summary: "Successfully scheduled '\(title)' from \(startDate) to \(endDate).")
    }

    private func listEvents(store: EKEventStore, startStr: String, endStr: String) throws -> NativePluginResult {
        let formatter = ISO8601DateFormatter()
        let startDate = formatter.date(from: startStr) ?? Date()
        let endDate = formatter.date(from: endStr) ?? Date().addingTimeInterval(86400 * 7) // Default to 1 week
        
        let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let events = store.events(matching: predicate)
        
        if events.isEmpty {
            return NativePluginResult(summary: "No events found between \(startDate) and \(endDate).")
        }
        
        let eventSummary = events.map { "\($0.title ?? "Untitled") (\($0.startDate!) - \($0.endDate!))" }.joined(separator: "\n")
        return NativePluginResult(summary: "Found \(events.count) events:\n\(eventSummary)")
    }

    private func createReminder(store: EKEventStore, title: String) throws -> NativePluginResult {
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = store.defaultCalendarForNewReminders()
        
        try store.save(reminder, commit: true)
        return NativePluginResult(summary: "Successfully added reminder: '\(title)'.")
    }

    private func listReminders(store: EKEventStore) async throws -> NativePluginResult {
        return try await withCheckedThrowingContinuation { continuation in
            let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
            store.fetchReminders(matching: predicate) { reminders in
                let list = reminders?.map { $0.title ?? "Untitled" }.joined(separator: "\n") ?? "None"
                continuation.resume(returning: NativePluginResult(summary: "Reminders:\n\(list)"))
            }
        }
    }
}
