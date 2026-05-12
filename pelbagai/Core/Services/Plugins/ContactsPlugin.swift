import Foundation
import Contacts

@MainActor
struct ContactsPlugin: NativePlugin {
    let id = "contacts"
    let displayName = "Contacts"

    var capabilities: [NativePluginCapability] {
        [
            NativePluginCapability(
                id: "search_contacts",
                displayName: "Search Contacts",
                description: "Search for contacts by name.",
                argumentSchema: ["query": "The name or part of the name to search for."],
                requiresUserApproval: false
            ),
            NativePluginCapability(
                id: "create_contact",
                displayName: "Create Contact",
                description: "Create a new contact in the address book.",
                argumentSchema: [
                    "firstName": "First name of the contact",
                    "lastName": "Last name of the contact",
                    "phone": "Phone number"
                ],
                requiresUserApproval: true
            ),
            NativePluginCapability(
                id: "update_contact",
                displayName: "Update Contact",
                description: "Update an existing contact's phone number.",
                argumentSchema: [
                    "id": "The identifier of the contact",
                    "phone": "New phone number"
                ],
                requiresUserApproval: true
            )
        ]
    }

    var chatTools: [NativeChatTool] {
        [
            NativeChatTool(
                name: "search_contacts",
                displayName: "Search Contacts",
                description: "Use to find contacts when the user asks for someone's info.",
                pluginID: id,
                capabilityID: "search_contacts"
            ),
            NativeChatTool(
                name: "create_contact",
                displayName: "Create Contact",
                description: "Use to add a new person to the address book.",
                pluginID: id,
                capabilityID: "create_contact"
            )
        ]
    }

    func execute(capabilityID: String, arguments: [String: String]) async throws -> NativePluginResult {
        let store = CNContactStore()
        
        // Check authorization
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .notDetermined {
            try await store.requestAccess(for: .contacts)
        } else if status == .denied || status == .restricted {
            return NativePluginResult(summary: "Access to contacts was denied by the user.")
        }

        switch capabilityID {
        case "search_contacts":
            return try searchContacts(store: store, query: arguments["query"] ?? "")
        case "create_contact":
            return try createContact(store: store, firstName: arguments["firstName"] ?? "", lastName: arguments["lastName"] ?? "", phone: arguments["phone"] ?? "")
        case "update_contact":
            return try updateContact(store: store, id: arguments["id"] ?? "", phone: arguments["phone"] ?? "")
        default:
            throw NativePluginError.unknownCapability(pluginID: id, capabilityID: capabilityID)
        }
    }

    private func searchContacts(store: CNContactStore, query: String) throws -> NativePluginResult {
        let keysToFetch = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactIdentifierKey as CNKeyDescriptor
        ]
        
        guard !query.isEmpty else {
            return NativePluginResult(summary: "Please provide a name to search for.")
        }
        
        let predicate = CNContact.predicateForContacts(matchingName: query)
        let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
        
        if contacts.isEmpty {
            return NativePluginResult(summary: "No contacts found for '\(query)'.")
        }
        
        let contactList = contacts.map { contact in
            let phone = contact.phoneNumbers.first?.value.stringValue ?? "No phone"
            return "\(contact.givenName) \(contact.familyName) (ID: \(contact.identifier)): \(phone)"
        }.joined(separator: "\n")
        
        return NativePluginResult(
            summary: "Found \(contacts.count) contacts:\n\(contactList)",
            data: ["count": "\(contacts.count)"]
        )
    }

    private func createContact(store: CNContactStore, firstName: String, lastName: String, phone: String) throws -> NativePluginResult {
        let contact = CNMutableContact()
        contact.givenName = firstName
        contact.familyName = lastName
        contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMain, value: CNPhoneNumber(stringValue: phone))]
        
        let saveRequest = CNSaveRequest()
        saveRequest.add(contact, toContainerWithIdentifier: nil)
        try store.execute(saveRequest)
        
        return NativePluginResult(summary: "Successfully created contact for \(firstName) \(lastName).")
    }

    private func updateContact(store: CNContactStore, id: String, phone: String) throws -> NativePluginResult {
        let keysToFetch = [CNContactPhoneNumbersKey as CNKeyDescriptor]
        let contact = try store.unifiedContact(withIdentifier: id, keysToFetch: keysToFetch).mutableCopy() as! CNMutableContact
        
        contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMain, value: CNPhoneNumber(stringValue: phone))]
        
        let saveRequest = CNSaveRequest()
        saveRequest.update(contact)
        try store.execute(saveRequest)
        
        return NativePluginResult(summary: "Successfully updated contact with ID \(id).")
    }
}
