import SwiftUI
import WidgetKit

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> ScooterStatusEntry {
        ScooterStatusEntry(
            date: Date(),
            connected: true,
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
            scanning: false,
            lockStateName: "Unknown"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ScooterStatusEntry) -> Void) {
        let prefs = UserDefaults(suiteName: "group.de.freal.unustasis")
        let connected = prefs?.bool(forKey: "connected")
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
        let lockStateName = prefs?.string(forKey: "lockStateName") ?? "Unknown"
        let entry = ScooterStatusEntry(
            date: Date(),
            connected: connected ?? false,
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
            scanning: scanning,
            lockStateName: lockStateName
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
    let lockStateName: String

}

// DEFINITIONS
struct ScooterWidget: Widget {
    let kind: String = "ScooterWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(iOS 17.0, *) {
                ScooterWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                ScooterWidgetEntryView(entry: entry)
                    .background()
            }
        }
        .supportedFamilies([.systemSmall])
        .configurationDisplayName("Scooter Status")
        .description("Shows your unu Scooter's last known status")
    }
}

// OVERARCHING VIEW
struct ScooterWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        // case .systemMedium:
        //     ScooterWidgetMediumView(entry: entry)
        default:
            ScooterWidgetSmallView(entry: entry)
        }
    }
}

// MEDIUM WIDGET
struct ScooterWidgetMediumView: View {
    var entry: Provider.Entry

    var body: some View {
        ZStack {
            // Background color
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    HStack(alignment: .top, spacing: 2) {
                        // Scooter name and last ping
                        Text(entry.scooterName ?? "No Scooter")
                            .font(.system(size: 12, weight: .regular))

                            .foregroundColor(Color.secondary)
                        Text(
                            (entry.lastPingDifference != nil) ? "\(entry.lastPingDifference!)" : ""
                        )
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Color.secondary)
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
                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.stateName ?? (entry.connected ? "Connected" : "Disconnected"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color.primary)
                    HStack(spacing: 8) {
                        BatteryItem(soc: entry.primarySOC)
                        if let soc2 = entry.secondarySOC, soc2 > 0 {
                            BatteryItem(soc: soc2)
                        }
                    }
                }
                Spacer()
                // Buttons row
                HStack(spacing: 0) {
                    // location button
                    let hasLocation = (entry.lastLat != nil && entry.lastLon != nil)
                    Link(
                        destination: hasLocation
                            ? URL(string: "maps://?ll=" + entry.lastLat! + "," + entry.lastLon!)!
                            : URL(string: "about:blank")!
                    ) {
                        // Only enable the link if location is available
                        if hasLocation {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.accentColor)
                                    .frame(height: 32)
                                Image(systemName: "location")
                                    .font(.system(size: 16))
                                    .foregroundColor(Color.primary)
                            }
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.accentColor.opacity(0.5))
                                    .frame(height: 32)
                                Image(systemName: "location.slash")
                                    .font(.system(size: 16))
                                    .foregroundColor(Color.secondary)
                            }
                            .allowsHitTesting(false)  // disables interaction
                        }
                    }.buttonStyle(.plain)
                    Spacer()
                    // wind button
                    Button(
                        action: {},
                    ) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.quaternary)
                                .frame(height: 32)
                            Image(systemName: "lock")
                                .font(.system(size: 16))
                                .foregroundColor(Color.primary)
                        }
                    }.buttonStyle(.plain)
                    Spacer()
                    // lock button
                    Button(
                        action: {},
                    ) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.quaternary)
                                .frame(height: 32)
                            Image(systemName: "bolt.car")
                                .font(.system(size: 16))
                                .foregroundColor(Color.primary)
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

// SMALL WIDGET
struct ScooterWidgetSmallView: View {
    var entry: Provider.Entry

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 6) {
                // Scooter name and last ping
                Text(entry.lockStateName)
                    .font(.system(size: 12, weight: .regular))
                    .multilineTextAlignment(.leading)
                    .foregroundColor(Color.secondary)
                Text(entry.scooterName ?? "No Scooter")
                    .font(.system(size: 26, weight: .bold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .foregroundColor(Color.primary)
                VStack(alignment: .leading, spacing: 4) {
                    BatteryItem(soc: entry.primarySOC)
                    if let soc2 = entry.secondarySOC, soc2 >= 0 {
                        BatteryItem(soc: soc2)
                    }
                }
            }
            // Location button always at bottom trailing
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    let hasLocation = (entry.lastLat != "0.0" && entry.lastLon != "0.0")
                    if hasLocation {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.quaternary)
                                .frame(width: 40, height: 40)
                            Image(systemName: "location")
                                .font(.system(size: 16))
                                .foregroundColor(Color.primary)
                        }
                        .widgetURL(
                            URL(string: "maps://?ll=" + entry.lastLat! + "," + entry.lastLon!))
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.quaternary.opacity(0.5))
                                .frame(width: 36, height: 36)
                            Image(systemName: "location.slash")
                                .font(.system(size: 16))
                                .foregroundColor(Color.secondary)
                        }
                        .allowsHitTesting(false)  // disables interaction
                    }
                }
            }
        }
    }
}

// COMPONENTS
struct BatteryItem: View {
    var soc: Int?

    var batteryIcon: String {
        guard let soc = soc else { return "battery.0percent" }
        switch soc {
        case 0...12:
            return "battery.0percent"
        case 13...37:
            return "battery.25percent"
        case 38...62:
            return "battery.50percent"
        case 63...87:
            return "battery.75percent"
        default:
            return "battery.100percent"
        }
    }

    var batteryColor: Color {
        guard let soc = soc else { return Color.primary }
        switch soc {
        case 0...20:
            return Color.red
        default:
            return Color.primary
        }
    }

    var body: some View {
        if let soc = soc {
            // Battery icon and percentage
            HStack(spacing: 4) {
                // Battery icon
                Image(systemName: batteryIcon)
                    .foregroundColor(batteryColor)
                    .font(.system(size: 12))
                // Battery percentage text
                Text("\(soc)%")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.primary)
            }
        } else {
            EmptyView()
        }
    }
}

#Preview(as: .systemMedium) {
    ScooterWidget()
} timeline: {
    ScooterStatusEntry(
        date: Date(),
        connected: true,
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
        scanning: false,
        lockStateName: "Locked"
    )
}

#Preview(as: .systemSmall) {
    ScooterWidget()
} timeline: {
    ScooterStatusEntry(
        date: Date(),
        connected: true,
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
        scanning: false,
        lockStateName: "Locked"
    )
}
