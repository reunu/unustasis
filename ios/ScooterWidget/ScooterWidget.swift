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

    var lastPingString: String {
        if let lastPing = entry.lastPing {
            let now = Date().timeIntervalSince1970 * 1000.0
            let diff = now - Double(lastPing)
            let hours = Int(diff / 3_600_000)
            return "(\(hours)h)"
        }
        return ""
    }

    var body: some View {
        ZStack {
            // Background color
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    HStack(alignment: .top, spacing: 2) {
                        // Scooter name and last ping
                        Text(entry.scooterName ?? "No Scooter")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(Color.black.opacity(0.5))
                        Text(lastPingString)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(Color.black.opacity(0.5))
                    }
                    Spacer()
                    // Scooter image (placeholder)
                    // Image("scooter_widget")
                    //     .resizable()
                    //     .aspectRatio(contentMode: .fit)
                    //     .frame(width: 80, height: 80)
                    //     .padding(.top, 8)
                }
                Spacer()
                // Status and battery
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.stateName ?? (entry.connected ? "Connected" : "Disconnected"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color.black)
                    HStack(spacing: 16) {
                        if let soc1 = entry.primarySOC {
                            HStack(spacing: 4) {
                                Image(systemName: "battery.100")
                                    .foregroundColor(Color.black)
                                    .font(.system(size: 12))
                                Text("\(soc1)%")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Color.black)
                            }
                        }
                        if let soc2 = entry.secondarySOC {
                            HStack(spacing: 4) {
                                Image(systemName: "battery.100")
                                    .foregroundColor(Color.black)
                                    .font(.system(size: 12))
                                Text("\(soc2)%")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Color.black)
                            }
                        }
                    }
                }
                Spacer()
                // Buttons row
                HStack(spacing: 0) {
                    // location button
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.blue.opacity(0.7))
                            .frame(height: 32)
                        Image(systemName: "mappin")
                            .font(.system(size: 16))
                            .foregroundColor(Color.black)
                    }.onTapGesture {
                        print("Location button tapped")
                    }
                    Spacer()
                    // wind button
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 32)
                        Image(systemName: "wind")
                            .font(.system(size: 16))
                            .foregroundColor(Color.black)
                    }.onTapGesture {
                        print("Wind button tapped")
                    }
                    Spacer()
                    // lock button
                    Button(
                        action: {
                            print("Lock button tapped")
                            // Handle lock action here
                        }
                    ) {
                        Image(systemName: "lock")
                            .font(.system(size: 16))
                            .foregroundColor(Color.black)
                    }.buttonStyle(.plain).background(Color.gray.opacity(0.3))
                        .cornerRadius(16)
                        .frame(height: 32)
                }
            }
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
                    .padding(24)
                    .background()
            }
        }
        .supportedFamilies([.systemMedium])
        .configurationDisplayName("Scooter Status")
        .description("Shows your scooter's status and quick actions.")
    }
}

#Preview(as: .systemMedium) {
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
