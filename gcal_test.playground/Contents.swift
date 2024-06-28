//
//  parser.swift
//  gcal-test
//
//  Created by Hoon Shin on 26/6/2024.
//
import Foundation
import NaturalLanguage
import SwiftyChrono
import EventKit


extension String {
    func removingTrailingCommasAndWhitespaces() -> String {
        // Remove trailing whitespaces and commas
        var trimmedString = self.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        // Remove trailing commas
        while trimmedString.hasSuffix(",") {
            trimmedString.removeLast()
            trimmedString = trimmedString.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        }
        
        return trimmedString
    }
}

struct Event {
    var title: String?
    var dateTime: Date?
    var people: String?
    var location: String?
    var zoomLink: String?
}

func parseEvent(bulletPoint: String) -> Event {
    let tagger = NLTagger(tagSchemes: [.nameType, .nameTypeOrLexicalClass])
    tagger.string = bulletPoint
    
    let chrono = Chrono()
    var event = Event()
    
    var people = [String]()
    var locations = [String]()
    
    // get times
    var times = [Date]()
    var filter_times = [String]()
    let date_text = chrono.parse(text: bulletPoint, refDate: Date()).map{$0.text}
    let date = chrono.parseDate(text: bulletPoint, refDate: Date())
    times.append(date ?? Date())
    filter_times.append(date_text.first ?? "")
    
    let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
    let tags: [NLTag] = [.personalName, .placeName, .organizationName]
    
    tagger.enumerateTags(in: bulletPoint.startIndex..<bulletPoint.endIndex, unit: .word, scheme: .nameTypeOrLexicalClass, options: options) { tag, tokenRange in
        guard let tag = tag, tags.contains(tag) else { return true }
        
        let token = String(bulletPoint[tokenRange])
        
        switch tag {
        case .personalName:
            people.append(token)
        case .placeName, .organizationName:
            locations.append(token)
        default:
            break
        }
        
        return true
    }
    
    // Extract event title by removing known entities
    var eventTitle = bulletPoint
    for person in people {
        eventTitle = eventTitle.replacingOccurrences(of: person, with: "")
    }
    for time in filter_times {
        eventTitle = eventTitle.replacingOccurrences(of: time, with: "")
    }
    for location in locations {
        eventTitle = eventTitle.replacingOccurrences(of: location, with: "")
    }
    
    eventTitle = eventTitle.replacingOccurrences(of: " with ", with: "").replacingOccurrences(of: " at ", with: "")
    
    // Check for Zoom link
    if bulletPoint.lowercased().contains("zoom") {
        event.zoomLink = "Zoom"
        eventTitle = eventTitle
            .replacingOccurrences(of: "zoom meeting", with: "", options: .caseInsensitive, range: nil)
            .replacingOccurrences(of: "zoom", with: "", options: .caseInsensitive, range: nil)
    }
    
    // Regular expression pattern to match leading and trailing commas and whitespaces
    let pattern = "^\\s*,+|,+\\s*$"

    // Use NSRegularExpression for pattern matching and replacement
    let regex = try! NSRegularExpression(pattern: pattern, options: [])

    // Define the range of the original string to be searched
    let range = NSRange(location: 0, length: eventTitle.utf16.count)

    // Perform the replacement
    eventTitle = regex.stringByReplacingMatches(in: eventTitle, options: [], range: range, withTemplate: "").trimmingCharacters(in: .whitespacesAndNewlines)
    
    // Capitalize first letter
    eventTitle = eventTitle.prefix(1).capitalized + eventTitle.dropFirst()

    event.title = eventTitle.isEmpty ? nil : eventTitle
    event.dateTime = times.first
    event.people = people.joined(separator: ", ")
    event.location = locations.joined(separator: ", ")
    
    
    
    return event
}

// Examples
let examples = [
    "Zoom meeting, run through presentation, 4pm with Patrick",
    "Dinner with Michelle, 8 pm at Fairwood",
    "Review exam 6, 10 pm",
    "Run code check at 7 am"
]

func parseAllEvents(examples : [String] ) -> [Event] {
    var parsed = [Event]()
    for example in examples {
        let event = parseEvent(bulletPoint: example)
        parsed.append(event)
        print("Event title: \(event.title ?? "N/A")")
        print("Date/Time: \(event.dateTime ?? Date())")
        print("People: \(event.people ?? "N/A")")
        print("Location: \(event.location ?? "N/A")")
        print("Zoom link: \(event.zoomLink ?? "N/A")")
        print("---")
    }
    return parsed
}

print("Events: ", examples)
print()

var parsed_events = parseAllEvents(examples: examples)


for parsed_event in parsed_events {
    // Create an instance of EKEventStore
    let eventStore = EKEventStore()

    // Request access to the calendar
    eventStore.requestFullAccessToEvents { (granted, error) in
        if granted {
            // Access granted
            print("Access to calendar granted")
            
            // Create an event
            let event = EKEvent(eventStore: eventStore)
            event.title = (parsed_event.title ?? "") + " with " + (parsed_event.people ?? "")
            event.startDate = parsed_event.dateTime // Set start date to current date and time
            event.endDate = event.startDate.addingTimeInterval(60 * 60) // Set end date one hour later
            event.structuredLocation = EKStructuredLocation(title: event.location ?? "")
            event.calendar = eventStore.defaultCalendarForNewEvents
            
            // Save the event
            do {
                try eventStore.save(event, span: .thisEvent)
                print("Event saved successfully")
            } catch let error as NSError {
                print("Failed to save the event with error: \(error)")
            }
        } else {
            // Access denied
            print("Access to calendar denied or an error occurred: \(String(describing: error))")
        }
    }
}

