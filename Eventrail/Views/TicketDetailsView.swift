import SwiftUI

/// The reader's own record for one night — the ticket, the lottery, the seat,
/// what it cost and a note — asked on a sheet of its own over the event's.
///
/// The event's sheet shows these answers as two tiles and a line of note, so
/// the facts Eventernote publishes are not pushed down a screen by a form. A
/// tap on any of them opens this, where each answer is asked the way it is
/// answered: chips for a choice, a stepper for a count, a field for anything
/// written.
///
/// Every answer takes effect as it is given, like everything else in the app;
/// Done only puts the sheet away.
struct TicketDetailsView: View {
    @Environment(EventStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let event: Event

    private var tracking: Binding<Tracking> {
        Binding(
            get: { store.tracking(for: event) },
            set: { store.setTracking($0, for: event) }
        )
    }

    /// Whether there is a ticket to say anything about.
    ///
    /// Not asked for a past event: the night happened, so the ticket existed.
    /// Still to come, it is there when the reader says they have bought it.
    private var hasTicket: Bool {
        !event.isUpcoming || tracking.wrappedValue.ticket == .purchased
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // The one question the library does not already answer,
                    // and only while it is still open to ask — see
                    // ``Tracking``. A night already over was a night they held
                    // a ticket for.
                    if event.isUpcoming { ticketSection }
                    // Asked whether or not there is a ticket: the applications
                    // went in long before anybody knew, and a night applied for
                    // six times and lost is worth having written down.
                    lotterySection
                    if hasTicket {
                        seatSection
                        costSection
                    }
                    notesSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Ticket Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .tint(.primary)
                }
            }
        }
    }

    // MARK: - Sections

    private var ticketSection: some View {
        section("Ticket") {
            FlowLayout(spacing: 8) {
                ForEach(TicketStatus.allCases) { status in
                    chip(isOn: tracking.wrappedValue.ticket == status) {
                        tracking.ticket.wrappedValue = status
                    } label: {
                        Text(status.label)
                    }
                }
            }
        }
    }

    /// How many entries the reader put into the lottery for this night.
    ///
    /// Stepped rather than typed, because the answer is nearly always one of
    /// the first few numbers — but the count itself is still a field, for the
    /// reader who applied eleven times. An empty field is "not written down",
    /// and so is 0 — see ``Tracking/lotteryEntries``.
    private var lotterySection: some View {
        section("Lottery entries") {
            // The stepper sits nearer the field's edge than the text does, so
            // it reads as a control inside the field rather than a second one.
            field(symbol: "ticket", trailingInset: 6) {
                TextField("Lottery entries", value: tracking.lotteryEntries,
                          format: .entries, prompt: Text(verbatim: "—"))
                    .keyboardType(.numberPad)
                    .monospacedDigit()
                lotteryStepper
            }
        }
    }

    /// Where the reader sat, as the ticket printed it, and the class of seat it
    /// was sold as.
    private var seatSection: some View {
        section("Seat") {
            field(symbol: "sofa") {
                // A block, a row and a number in three languages worth of
                // conventions: nothing the keyboard would correct here is a
                // correction.
                TextField("Seat", text: tracking.seat, prompt: Text("Seat"))
                    .autocorrectionDisabled()
            }

            FlowLayout(spacing: 8) {
                ForEach(SeatClass.allCases) { seatClass in
                    let isOn = tracking.wrappedValue.seatClass == seatClass.rawValue
                    // A second tap takes the answer back: the chips are the
                    // only way to give one, so they are the way to clear it.
                    chip(isOn: isOn) {
                        tracking.seatClass.wrappedValue = isOn ? "" : seatClass.rawValue
                    } label: {
                        HStack(spacing: 7) {
                            seatClass.badge
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(isOn ? Color.brandTint : Color(.systemBackground))
                                .padding(.horizontal, 4)
                                .frame(minWidth: 18, minHeight: 18)
                                .background(isOn ? Color.white : Color.primary, in: .capsule)
                            Text(seatClass.label)
                        }
                    }
                }
            }
        }
    }

    private var costSection: some View {
        section("Cost") {
            field(symbol: "yensign.circle") {
                TextField("Cost", value: tracking.cost, format: .yen,
                          prompt: Text(verbatim: "¥0"))
                    .keyboardType(.numberPad)
            }
        }
    }

    /// The one answer that is not a line at all, so it is given room to grow.
    private var notesSection: some View {
        section("Notes") {
            TextField("Notes", text: tracking.note,
                      prompt: Text("Something only you will see"), axis: .vertical)
                .lineLimit(3...12)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .labelsHidden()
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(Self.fieldFill, in: Self.fieldShape)
        }
    }

    // MARK: - The lottery stepper

    private var lotteryStepper: some View {
        HStack(spacing: 0) {
            lotteryStep(by: -1, symbol: "minus")
            Rectangle()
                .fill(.quaternary)
                .frame(width: 0.5)
                .padding(.vertical, 8)
            lotteryStep(by: 1, symbol: "plus")
        }
        .frame(height: 34)
        .background(Color(.secondarySystemGroupedBackground),
                    in: .rect(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 1.5, y: 1)
        .sensoryFeedback(.selection, trigger: tracking.wrappedValue.lotteryEntries)
    }

    /// One end of the lottery stepper.
    ///
    /// Counting up from nothing written down means 1 rather than 0, and
    /// counting down off 1 empties the field again, because 0 is that same
    /// nothing rather than a step below it — so minus is dead on an empty
    /// field. Both ends fall out of one comparison: a step that would leave
    /// the field saying what it says now is not offered. The ceiling is
    /// ``EntryCount``'s own four digits.
    private func lotteryStep(by delta: Int, symbol: String) -> some View {
        let current = tracking.wrappedValue.lotteryEntries
        let stepped = min(max((current ?? 0) + delta, 0), 9999)
        let next: Int? = stepped == 0 ? nil : stepped
        let enabled = next != current

        return Button {
            tracking.lotteryEntries.wrappedValue = next
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(enabled ? AnyShapeStyle(Color.brandTint) : AnyShapeStyle(.quaternary))
                .frame(width: 40)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(delta < 0 ? Text("Fewer lottery entries") : Text("More lottery entries"))
    }

    // MARK: - Pieces

    /// One question: what is being asked, and under it where it is answered.
    private func section<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
            content()
        }
    }

    /// A one-line field, with the symbol for what it holds at its leading edge.
    private func field<Content: View>(
        symbol: String,
        trailingInset: CGFloat = 14,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(.tertiary)
                .frame(width: 20)
                .accessibilityHidden(true)
            content()
        }
        .textFieldStyle(.plain)
        .font(.system(size: 16))
        .labelsHidden()
        .padding(.leading, 14)
        .padding(.trailing, trailingInset)
        .frame(minHeight: 46)
        .background(Self.fieldFill, in: Self.fieldShape)
    }

    /// One answer among a few, as a capsule: filled in the app's colour when
    /// it is the answer given, outlined when it is not.
    private func chip<Label: View>(
        isOn: Bool,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            label()
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(isOn ? Color.brandTint : Color(.systemBackground), in: .capsule)
                .overlay {
                    if !isOn { Capsule().strokeBorder(Color.primary.opacity(0.14), lineWidth: 1) }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .animation(.snappy, value: isOn)
    }

    /// Flat rather than glass: the fields sit on the sheet itself, with
    /// nothing under them for glass to refract.
    private static let fieldFill = Color(.tertiarySystemFill)
    private static let fieldShape = RoundedRectangle(cornerRadius: 14, style: .continuous)
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        TicketDetailsView(event: PreviewData.events[0])
            .library(EventStore.preview)
    }
}
