import SwiftUI

/// One event: what Eventernote publishes about it, and what the reader records
/// about it. The two are kept visually distinct throughout.
struct EventDetailView: View {
    @Environment(EventStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let event: Event

    private var tracking: Binding<Tracking> {
        Binding(
            get: { store.tracking(for: event) },
            set: { store.setTracking($0, for: event) }
        )
    }

    private var directionsURL: URL? {
        let query = event.venue.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://maps.apple.com/?q=\(query)")
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    actions
                    statistics
                    trackingCard
                    performersCard
                    venueCard
                    openInEventernote
                    footnote
                }
                .padding(.bottom, 32)
            }
            .ignoresSafeArea(edges: .top)

            doneButton
                .padding(.horizontal, 20)
                .padding(.top, 8)
        }
        .washBackground()
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var header: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(.quaternary)
                .overlay {
                    Image(systemName: "music.microphone")
                        .font(.system(size: 72, weight: .ultraLight))
                        .foregroundStyle(.tertiary)
                }
                .overlay {
                    // Fades the flyer into the wash so the title stays readable.
                    LinearGradient(
                        stops: [
                            .init(color: .washBase.opacity(0), location: 0),
                            .init(color: .washBase.opacity(0.75), location: 0.62),
                            .init(color: .washBase, location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                }
                .frame(height: 392)
                .accessibilityLabel("Event flyer")

            VStack(spacing: 9) {
                Text(event.title)
                    .font(.system(size: 22, weight: .bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(event.longDateLine) · Doors \(event.doorsLine) · Start \(event.timeLine)")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 14)
        }
    }

    private var doneButton: some View {
        Button("Done") { dismiss() }
            .font(.system(size: 14.5, weight: .semibold))
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .glassCapsule(interactive: true)
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 13) {
            if let directionsURL {
                circularAction {
                    Link(destination: directionsURL) {
                        actionIcon("location.fill", tint: .brandTint)
                    }
                    .accessibilityLabel("Directions to the venue")
                }
            }

            circularAction {
                ShareLink(item: event.sourceURL) {
                    actionIcon("square.and.arrow.up", tint: .primary)
                }
                .accessibilityLabel("Share event")
            }

            circularAction {
                Button {
                    withAnimation(.snappy) { store.toggleFavorite(event) }
                } label: {
                    actionIcon(
                        store.isFavorite(event) ? "heart.fill" : "heart",
                        tint: store.isFavorite(event) ? .favorite : .secondary
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(store.isFavorite(event) ? "Remove favourite" : "Mark as favourite")
            }

            circularAction {
                Menu {
                    Link("Open in Eventernote", destination: event.sourceURL)
                    ShareLink("Share Link", item: event.sourceURL)
                } label: {
                    actionIcon("ellipsis", tint: .primary)
                }
                .accessibilityLabel("More actions")
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    private func circularAction<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: 56, height: 56)
            .glassCircle(interactive: true)
    }

    private func actionIcon(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 56, height: 56)
            .contentShape(.rect)
    }

    // MARK: - Imported facts

    private var statistics: some View {
        HStack(spacing: 11) {
            StatTile(tint: .trackInterest, value: event.listedAttendees.formatted(),
                     label: "Listed on Eventernote")
            StatTile(tint: .trackTicket, value: event.doorsLine, label: "Doors open")
            StatTile(tint: .trackAttended, value: event.timeLine, label: "Performance")
        }
        .padding(.horizontal, 18)
    }

    // MARK: - The reader's own record

    private var trackingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Text("My tracking")
                    .font(.system(size: 17, weight: .bold))
                Text("Private to you")
                    .font(.system(size: 9.5, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .glassCapsule()
            }

            segment("Interest", selection: tracking.interest, options: Interest.allCases)
            segment("Ticket", selection: tracking.ticket, options: TicketStatus.allCases)
            segment("Attendance", selection: tracking.attendance, options: Attendance.allCases)

            VStack(alignment: .leading, spacing: 7) {
                fieldLabel("Notes")
                TextField(
                    "Notes",
                    text: tracking.note,
                    prompt: Text("Something only you will see"),
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(2...6)
                .labelsHidden()
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .glassPanel(cornerRadius: 20)
            }
        }
        .padding(18)
        .glassPanel(cornerRadius: 28)
        .padding(.horizontal, 18)
    }

    private func segment<Value: Hashable & Identifiable>(
        _ label: LocalizedStringKey,
        selection: Binding<Value>,
        options: [Value]
    ) -> some View where Value.ID == Value {
        VStack(alignment: .leading, spacing: 7) {
            fieldLabel(label)
            Picker(label, selection: selection) {
                ForEach(options) { option in
                    Text(title(of: option)).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private func title<Value>(of option: Value) -> LocalizedStringKey {
        switch option {
        case let value as Interest: value.label
        case let value as TicketStatus: value.label
        case let value as Attendance: value.label
        default: ""
        }
    }

    private func fieldLabel(_ label: LocalizedStringKey) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .kerning(0.44)
            .textCase(.uppercase)
            .foregroundStyle(.tertiary)
    }

    // MARK: - Performers

    private var performersCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Performers")
                    .font(.system(size: 17, weight: .bold))
                Text(event.performers.count.formatted())
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 3) {
                ForEach(event.performers) { performer in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(.quaternary)
                            .overlay {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(width: 38, height: 38)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(performer.name)
                                .font(.system(size: 14, weight: .semibold))
                            Text(performer.role)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if performer.name == event.artist {
                            Text("Headliner")
                                .font(.system(size: 10, weight: .semibold))
                                .textCase(.uppercase)
                                .foregroundStyle(Color.brandTint)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .glassCapsule()
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 8)
                }
            }
        }
        .padding(18)
        .glassPanel(cornerRadius: 28)
        .padding(.horizontal, 18)
    }

    // MARK: - Venue

    private var venueCard: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.quaternary)
                .overlay {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.favorite)
                        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                }
                .frame(height: 150)
                .accessibilityLabel("Venue map")

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(event.venue)
                        .font(.system(size: 14.5, weight: .semibold))
                    Text(event.venueDetail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let directionsURL {
                    Link(destination: directionsURL) {
                        Text("Directions")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Color.brandTint)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 9)
                    }
                    .glassCapsule(interactive: true)
                }
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 15)
        }
        .glassPanel(cornerRadius: 28)
        .clipShape(.rect(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 18)
    }

    // MARK: - Provenance

    /// Anything that changes the reader's Eventernote account happens on the
    /// official site, where they authenticate directly.
    private var openInEventernote: some View {
        Link(destination: event.sourceURL) {
            HStack(spacing: 9) {
                Text("Open in Eventernote")
                    .font(.system(size: 14.5, weight: .semibold))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Color.brandTint)
            .frame(maxWidth: .infinity)
            .padding(16)
        }
        .glassPanel(interactive: true)
        .padding(.horizontal, 18)
    }

    private var footnote: some View {
        Group {
            if let lastRefreshed = store.lastRefreshed {
                Text("Event data imported from the public Eventernote page. Last successful import \(lastRefreshed, format: .relative(presentation: .named)).")
            } else {
                Text("Event data imported from the public Eventernote page.")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 26)
        .padding(.top, 2)
    }
}

#Preview {
    EventDetailView(event: SampleData.library[0])
        .environment(EventStore())
}
