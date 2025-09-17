import AppIntents
import SwiftUI
import WidgetKit

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> ScooterStatusEntry {
        ScooterStatusEntry(
            date: Date(),
            connected: true,
            lastPingDifference: nil,
            lastPingText: nil,
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
            lockStateName: "Unknown",
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ScooterStatusEntry) -> Void) {
        let prefs = UserDefaults(suiteName: "group.de.freal.unustasis")
        let connected = prefs?.bool(forKey: "connected")
        let lastPingDifference = prefs?.string(forKey: "lastPingDifference")
        let lastPingText = prefs?.string(forKey: "iOSlastPingText")
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
            lastPingText: lastPingText,
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
    let lastPingText: String?
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
                    .containerBackground(.fill.quaternary, for: .widget)
            } else {
                ScooterWidgetEntryView(entry: entry)
                    .background()
            }
        }
        .supportedFamilies([
            .systemSmall,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
        .contentMarginsDisabled()
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
        case .accessoryRectangular:
            ScooterWidgetLockScreenView(entry: entry)
        case .accessoryCircular:
            ScooterWidgetCircularView(entry: entry)
        case .accessoryInline:
            ScooterWidgetInlineView(entry: entry)
        default:
            ScooterWidgetSmallView(entry: entry)
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
                Text(entry.lastPingText ?? "unustasis")
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
                    if let soc2 = entry.secondarySOC, soc2 > 0 {
                        BatteryItem(soc: soc2)
                    }
                }
            }
            if #available(iOSApplicationExtension 17, *) {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        if false {  // Placeholder for future use
                            let loading = entry.scanning ?? false
                            if !loading {
                                Button(
                                    intent: BackgroundIntent(
                                        url: URL(
                                            string: "unustasis://ping"
                                        ),
                                        appGroup: "group.de.freal.unustasis"
                                    )
                                ) {
                                    Image(systemName: "lock")
                                        .font(.system(size: 16))
                                        .foregroundColor(Color.primary)
                                }
                            } else {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(.quaternary.opacity(0.5))
                                        .frame(width: 36, height: 36)
                                    ProgressView()
                                        .progressViewStyle(
                                            CircularProgressViewStyle(tint: Color.primary))
                                }
                                .allowsHitTesting(false)  // disables interaction
                            }
                        }
                    }

                }
            }
        }
        .padding(16)
    }
}

// CIRCULAR WIDGET
struct ScooterWidgetCircularView: View {
    var entry: Provider.Entry
    var hasSecondarySOC: Bool {
        guard let soc2 = entry.secondarySOC else { return false }
        return soc2 > 0
    }
    var body: some View {
        ZStack {
            // primary SOC gauge
            Gauge(
                value: Double(entry.primarySOC ?? 0),
                in: 0...100,
            ) {
                let iconSize: CGFloat = hasSecondarySOC ? 24 : 32
                Image("scooter_icon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(Color.primary)
                    .frame(width: iconSize, height: iconSize)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            // secondary SOC gauge
            if hasSecondarySOC {
                Gauge(
                    value: Double(entry.secondarySOC!),
                    in: 0...100,
                ) {

                }.padding(8)
                    .gaugeStyle(.accessoryCircularCapacity)
            }
        }
    }
}

// RECTANGULAR LOCK SCREEN WIDGET
struct ScooterWidgetLockScreenView: View {
    var entry: Provider.Entry

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Scooter icon
            Image("scooter_icon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundColor(Color.primary)
                .frame(width: 24, height: 32)
                .padding(.top, 4)  // Shift scooter down slightly to adjust for top-heavy image
            // Scooter details
            VStack(alignment: .leading, spacing: 2) {
                // Scooter name and last ping
                Text(entry.scooterName ?? "unu Scooter")
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
                // Battery items
                VStack(alignment: .leading, spacing: 0) {
                    BatteryBar(soc: entry.primarySOC)
                    if let soc2 = entry.secondarySOC, soc2 > 0 {
                        BatteryBar(soc: soc2)
                    }
                }
            }
        }
    }
}

struct ScooterWidgetInlineView: View {
    var entry: Provider.Entry

    private var displayText: String {
        var text = "\(entry.scooterName ?? "unu Scooter"): \(entry.primarySOC ?? 0)%"
        if let secondarySOC = entry.secondarySOC, secondarySOC > 0 {
            text += "∙\(secondarySOC)%"
        }
        return text
    }

    var body: some View {
        Text(displayText)
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
            return Color.accentColor
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

struct BatteryBar: View {
    var soc: Int?

    var body: some View {
        if let soc = soc {
            HStack(alignment: .center, spacing: 4) {
                Text("\(soc)%")
                    .font(.system(size: 10))
                    .foregroundColor(Color.secondary)
                Gauge(
                    value: Double(soc),
                    in: 0...100
                ) {}
                .gaugeStyle(.accessoryLinearCapacity)
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
        lastPingText: nil,
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
        lastPingText: "2h ago",
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
