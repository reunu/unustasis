import SwiftUI
import WidgetKit

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> ScooterStatusEntry {
        ScooterStatusEntry(
            date: Date(),
            connected: true,
            lastPing: nil,
            lastPingDifference: nil,
            stateName: "Standby",
            locked: true,
            seatOpenable: true,
            primarySOC: 87,
            secondarySOC: 100,
            scooterName: "Scooter Pro",
            scooterColor: 1,
            lastLat: "37.7749",
            lastLon: "-122.4194",
            seatClosed: true,
            scanning: false
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ScooterStatusEntry) -> Void) {
        let prefs = UserDefaults(suiteName: "group.de.freal.unustasis")
        let connected = prefs?.bool(forKey: "connected")
        let lastPing = prefs?.integer(forKey: "lastPing")
        let lastPingDifference = prefs?.string(forKey: "lastPingDifference")
        let stateName = prefs?.string(forKey: "stateName")
        let locked = prefs?.bool(forKey: "locked")
        let seatOpenable = prefs?.bool(forKey: "seatOpenable")
        let primarySOC = prefs?.integer(forKey: "soc1")
        let secondarySOC = prefs?.integer(forKey: "soc2")
        let scooterName = prefs?.string(forKey: "scooterName")
        let scooterColor = prefs?.integer(forKey: "scooterColor")
        let lastLat = prefs?.string(forKey: "lastLat")
        let lastLon = prefs?.string(forKey: "lastLon")
        let seatClosed = prefs?.bool(forKey: "seatClosed")
        let scanning = prefs?.bool(forKey: "scanning")
        let entry = ScooterStatusEntry(
            date: Date(),
            connected: connected ?? false,
            lastPing: lastPing,
            lastPingDifference: lastPingDifference,
            stateName: stateName,
            locked: locked,
            seatOpenable: seatOpenable,
            primarySOC: primarySOC,
            secondarySOC: secondarySOC,
            scooterName: scooterName,
            scooterColor: scooterColor,
            lastLat: lastLat,
            lastLon: lastLon,
            seatClosed: seatClosed,
            scanning: scanning
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        getSnapshot(in: context) { (entry) in
            let timeline = Timeline(entries: [entry], policy: .atEnd)
            completion(timeline)
        }
    }
}

struct ScooterStatusEntry: TimelineEntry {
    let date: Date  // Required by TimelineEntry

    // Data fields as saved by widget_handler.dart
    let connected: Bool
    let lastPing: Int?  // MillisecondsSinceEpoch
    let lastPingDifference: String?
    let stateName: String?
    let locked: Bool?
    let seatOpenable: Bool?
    let primarySOC: Int?  // from "soc1"
    let secondarySOC: Int?  // from "soc2"
    let scooterName: String?
    let scooterColor: Int?
    let lastLat: String?
    let lastLon: String?
    let seatClosed: Bool?
    let scanning: Bool?

    // Computed property to get lastPing as Date
    var lastPingDate: Date? {
        guard let ts = lastPing else { return nil }
        return Date(timeIntervalSince1970: Double(ts) / 1000.0)
    }

    var calculatedLastPingDifference: String {
        guard let lastPing = lastPing else { return "N/A" }
        let now = Date().timeIntervalSince1970 * 1000.0
        let difference = now - Double(lastPing)
        // return hours ago
        let hours = Int(difference / 3_600_000)
        return "\(hours) hours ago"
    }
}

struct ScooterWidgetEntryView: View {
    var entry: Provider.Entry

    var body: some View {
        VStack {
            Text("Widget update:")
            Text(entry.date, style: .time)

            Text("\(entry.scooterName ?? "Unnamed scooter") is \(entry.stateName ?? "Unknown")")

            Text("Connected: \(entry.connected ? "Yes" : "No")")

            Text("Last Ping: \(entry.calculatedLastPingDifference)")
        }
    }
}

struct ScooterWidget: Widget {
    let kind: String = "ScooterWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(iOS 17.0, *) {
                ScooterWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                ScooterWidgetEntryView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName("My Widget")
        .description("This is an example widget.")
    }
}

#Preview(as: .systemSmall) {
    ScooterWidget()
} timeline: {
    ScooterStatusEntry(
        date: Date(),
        connected: true,
        lastPing: nil,
        lastPingDifference: nil,
        stateName: "Standby",
        locked: true,
        seatOpenable: true,
        primarySOC: 87,
        secondarySOC: 100,
        scooterName: "Scooter Pro",
        scooterColor: 1,
        lastLat: "37.7749",
        lastLon: "-122.4194",
        seatClosed: true,
        scanning: false
    )
}
