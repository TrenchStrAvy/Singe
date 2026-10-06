import SwiftUI

/// State of one Singe lookup, shared by the popover view and the controller.
final class LookupModel: ObservableObject {
    @Published var term = ""
    @Published var senses: [Sense] = []
    @Published var selected: String?
    @Published var loading = false
    @Published var explaining = false       // the local model is writing the phrase explanation
    @Published var status: String?
    @Published var pinned = false
    @Published var interests: [String] = []
    @Published var arrowX: CGFloat = 190
    @Published var arrowUp = false          // popover sits below the term
    @Published var collections: [TermList] = []
    @Published var savedIn: [String: Set<Int>] = [:]   // sense id → collections holding that meaning
    @Published var saving: String?          // the meaning whose "Save to" panel is open

    var onSelect: ((Sense) -> Void)?
    var onToggle: ((Sense, Int) -> Void)?
    var onCreate: ((Sense, String) -> Void)?
    var onPin: (() -> Void)?

    var sourceNote: String {
        if senses.contains(where: { $0.source == .model }) { return "Local model · \(LocalModel.model)" }
        if senses.contains(where: { $0.source == .dictionary }) { return "Local · macOS Dictionary" }
        if senses.first?.source == .glossary { return "Local · Singe glossary" }
        return "Local · Wiktionary"
    }
}

/// The popover outline: a rounded rectangle with an arrow pointing at the term.
struct PopoverShape: Shape {
    var arrowX: CGFloat
    var arrowUp: Bool
    static let arrow: CGFloat = 8
    static let radius: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        let a = Self.arrow, r = Self.radius
        let body = arrowUp ? CGRect(x: rect.minX, y: rect.minY + a, width: rect.width, height: rect.height - a)
                           : CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - a)
        let x = min(max(arrowX, body.minX + r + a), body.maxX - r - a)
        var p = Path()
        p.move(to: CGPoint(x: body.minX + r, y: body.minY))
        if arrowUp {
            p.addLine(to: CGPoint(x: x - a, y: body.minY))
            p.addLine(to: CGPoint(x: x, y: rect.minY))
            p.addLine(to: CGPoint(x: x + a, y: body.minY))
        }
        p.addLine(to: CGPoint(x: body.maxX - r, y: body.minY))
        p.addArc(center: CGPoint(x: body.maxX - r, y: body.minY + r), radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: body.maxX, y: body.maxY - r))
        p.addArc(center: CGPoint(x: body.maxX - r, y: body.maxY - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        if !arrowUp {
            p.addLine(to: CGPoint(x: x + a, y: body.maxY))
            p.addLine(to: CGPoint(x: x, y: rect.maxY))
            p.addLine(to: CGPoint(x: x - a, y: body.maxY))
        }
        p.addLine(to: CGPoint(x: body.minX + r, y: body.maxY))
        p.addArc(center: CGPoint(x: body.minX + r, y: body.maxY - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: body.minX, y: body.minY + r))
        p.addArc(center: CGPoint(x: body.minX + r, y: body.minY + r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// Variant B from mockups/popover-refresh: white glass (drawn by PopoverWindow), the chosen
/// meaning lifted into a white card, one star per meaning that files it into collections.
struct PopoverView: View {
    @ObservedObject var model: LookupModel
    @Namespace private var lift
    @State private var hovered: String?
    @State private var newName = ""
    @State private var naming = false
    @FocusState private var nameFocused: Bool

    static let width: CGFloat = 380
    /// The mock-up's flow curve; PopoverWindow animates its frame on the same one.
    static let flow = Animation.timingCurve(0.22, 0.9, 0.25, 1, duration: 0.42)

    static let ink = Color(red: 0.043, green: 0.043, blue: 0.055)
    static let soft = Color(red: 0.227, green: 0.227, blue: 0.251)
    static let muted = Color(red: 0.541, green: 0.541, blue: 0.576)
    static let hair = Color.black.opacity(0.07)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.arrowUp { Spacer().frame(height: PopoverShape.arrow) }
            header
            if model.loading && model.senses.isEmpty {
                note(model.status ?? "Looking up…", spinner: true)
            } else if model.senses.isEmpty {
                note(model.status ?? "No meaning found on this Mac.", spinner: false)
            } else {
                if model.explaining { note("Explaining the whole phrase…", spinner: true) }
                VStack(spacing: 2) {
                    ForEach(model.senses) { row($0) }
                }
                .padding(.horizontal, 8)
            }
            followUp
            HStack(spacing: 0) {
                if model.pinned {
                    Text("Esc to close")
                } else {
                    Text("Release ")
                    Text("⌃").font(.system(size: 10.5)).foregroundStyle(Self.soft)
                        .frame(minWidth: 17, minHeight: 17)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.black.opacity(0.14), lineWidth: 1))
                        .padding(.horizontal, 2)
                    Text(" to close")
                }
                Spacer()
                Text(model.sourceNote)
            }
            .font(.system(size: 11)).foregroundStyle(Self.muted)
            .padding(.horizontal, 16).padding(.bottom, 10)
            if !model.arrowUp { Spacer().frame(height: PopoverShape.arrow) }
        }
        .frame(width: Self.width)
        .foregroundStyle(Self.ink)
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(model.term).font(.system(size: 20, weight: .bold)).tracking(-0.4).lineLimit(1)
            Spacer(minLength: 6)
            Text(subtitle).font(.system(size: 11.5)).foregroundStyle(Self.muted).lineLimit(1)
        }
        .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 8)
    }

    private var subtitle: String {
        guard !model.senses.isEmpty else { return "" }
        let n = model.senses.count
        var s = n == 1 ? "1 meaning" : "\(n) meanings"
        if !model.interests.isEmpty { s += " · ranked for \(model.interests.prefix(2).joined(separator: ", "))" }
        return s
    }

    private func note(_ text: String, spinner: Bool) -> some View {
        HStack(spacing: 8) {
            if spinner { ProgressView().controlSize(.small) }
            Text(text).font(.system(size: 12.5)).foregroundStyle(Self.muted)
        }
        .padding(.horizontal, 18).padding(.vertical, 9)
    }

    /// The gloss adds nothing when it only repeats the headline ("Any computer attached to a network.").
    private func gloss(_ sense: Sense) -> String? {
        func plain(_ s: String) -> String { s.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespaces)) }
        return plain(sense.gloss) == plain(sense.name) || sense.gloss.isEmpty ? nil : sense.gloss
    }

    private func row(_ sense: Sense) -> some View {
        let on = model.selected == sense.id
        let part = sense.term.caseInsensitiveCompare(model.term) != .orderedSame   // a part of a phrase
        let saved = model.savedIn[sense.id] ?? []
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(sense.name).font(.system(size: 14, weight: .semibold)).lineSpacing(1)
                        .foregroundStyle(on ? Self.ink : hovered == sense.id ? Self.soft : Self.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if part, sense.term.caseInsensitiveCompare(sense.name) != .orderedSame {
                        Text(sense.term).font(.system(size: 10.5)).foregroundStyle(Self.muted).padding(.top, 1)
                    }
                    if let g = gloss(sense), on || part {
                        // the chosen meaning in full; the parts of a phrase always show their definition
                        Text(g).font(.system(size: 13)).foregroundStyle(Self.soft).lineSpacing(2)
                            .lineLimit(on ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                            // the outgoing definition clears quickly so it never shows through the card gliding over it
                            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -4)),
                                                    removal: .opacity.animation(.easeOut(duration: 0.1))))
                    }
                    if !saved.isEmpty {
                        Text("Saved in " + model.collections.filter { saved.contains($0.id) }.map(\.name).joined(separator: ", "))
                            .font(.system(size: 11)).foregroundStyle(Self.muted).padding(.top, 3)
                    }
                }
                Spacer(minLength: 4)
                Text(sense.label).font(.system(size: 10.5)).foregroundStyle(Self.muted).lineLimit(1).padding(.top, 3)
                starButton(sense, saved: !saved.isEmpty)
            }
            if model.saving == sense.id {
                savePanel(sense, saved: saved)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .topTrailing)))
            }
        }
        .padding(.leading, 12).padding(.trailing, 6).padding(.vertical, 9)
        .background {
            if on {
                RoundedRectangle(cornerRadius: 12).fill(Color.white)
                    .shadow(color: Color(red: 0.08, green: 0.09, blue: 0.16).opacity(0.07), radius: 7, y: 4)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.06), lineWidth: 1))
                    .matchedGeometryEffect(id: "lift", in: lift)
            }
        }
        .contentShape(Rectangle())
        .onHover { inside in hovered = inside ? sense.id : (hovered == sense.id ? nil : hovered) }
        .onTapGesture { select(sense) }
    }

    private func select(_ sense: Sense) {
        guard model.selected != sense.id else { return }
        withAnimation(Self.flow) {
            model.selected = sense.id
            if model.saving != sense.id { model.saving = nil }
        }
        model.onSelect?(sense)
    }

    private func starButton(_ sense: Sense, saved: Bool) -> some View {
        Button {
            withAnimation(Self.flow) {
                model.selected = sense.id
                model.saving = model.saving == sense.id ? nil : sense.id
                naming = false
            }
            model.onPin?()          // the panel needs the popover to stay when Control is let go
            model.onSelect?(sense)
        } label: {
            Image(systemName: saved ? "star.fill" : "star")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(saved || model.saving == sense.id ? Self.ink : Self.muted)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.black.opacity(model.saving == sense.id ? 0.05 : 0)))
                .contentShape(Circle())
                .scaleEffect(saved ? 1.08 : 1)
        }
        .buttonStyle(.plain)
        .padding(.top, -5)
        .help(saved ? "Saved: change collections" : "Save this meaning")
    }

    /// "Save to": your collections as checkboxes, and a new one by name.
    private func savePanel(_ sense: Sense, saved: Set<Int>) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Save this meaning to").font(.system(size: 11)).foregroundStyle(Self.muted)
                .padding(.horizontal, 8).padding(.bottom, 3)
            ForEach(model.collections) { c in
                Button { model.onToggle?(sense, c.id) } label: {
                    HStack(spacing: 8) {
                        let on = saved.contains(c.id)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(on ? Self.ink : Color.clear)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(on ? Self.ink : Color.black.opacity(0.35), lineWidth: 1.3))
                            .overlay(Image(systemName: "checkmark").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(.white).opacity(on ? 1 : 0))
                            .frame(width: 15, height: 15)
                        Text(c.name).font(.system(size: 13))
                        Spacer()
                        Text("\(c.count)").font(.system(size: 11)).foregroundStyle(Self.muted)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if !model.collections.isEmpty { Rectangle().fill(Self.hair).frame(height: 1).padding(.vertical, 4).padding(.horizontal, 2) }
            if naming {
                TextField("Collection name, then Return", text: $newName)
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .focused($nameFocused)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Self.ink, lineWidth: 1))
                    .onSubmit {
                        let name = newName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        model.onCreate?(sense, name)
                        newName = ""
                        naming = false
                    }
                    .onExitCommand { naming = false }
            } else {
                Button {
                    naming = true
                    DispatchQueue.main.async { nameFocused = true }
                } label: {
                    Label("New collection…", systemImage: "plus").font(.system(size: 13)).foregroundStyle(Self.soft)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.975)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.06), lineWidth: 1))
        .padding(.top, 8).padding(.trailing, 6)
    }

    private var followUp: some View {
        HStack(spacing: 8) {
            Text(model.pinned ? "Follow-up questions are coming soon" : "Ask a follow-up…")
                .font(.system(size: 13)).foregroundStyle(Self.muted)
            Spacer()
            Text("Coming soon").font(.system(size: 10.5, weight: .semibold))
            Image(systemName: "arrow.up").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Self.ink))
                .opacity(0.25)
        }
        .padding(.leading, 15).padding(.trailing, 5).padding(.vertical, 5)
        .background(Capsule().fill(Color.white))
        .overlay(Capsule().stroke(Self.ink, lineWidth: 1.5))
        .contentShape(Capsule())
        .onTapGesture { model.onPin?() }
        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 10)
    }
}
