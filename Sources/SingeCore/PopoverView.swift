import SwiftUI

/// State of one Singe lookup, shared by the popover view and the controller.
final class LookupModel: ObservableObject {
    @Published var term = ""
    @Published var senses: [Sense] = []
    @Published var selected: String?
    @Published var loading = false
    @Published var explaining = false       // the local model is writing the phrase explanation
    @Published var status: String?
    @Published var starred = false
    @Published var pinned = false
    @Published var interests: [String] = []
    @Published var arrowX: CGFloat = 180
    @Published var arrowUp = false          // popover sits below the term

    var onSelect: ((Sense) -> Void)?
    var onStar: ((Bool) -> Void)?
    var onFollowUp: (() -> Void)?

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
    static let radius: CGFloat = 12

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

/// Variant B: a native macOS popover. Only the highlight carries the Sorph glass.
struct PopoverView: View {
    @ObservedObject var model: LookupModel
    @Environment(\.colorScheme) private var scheme

    private var line: Color { scheme == .dark ? .white.opacity(0.10) : .black.opacity(0.09) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.arrowUp { Spacer().frame(height: PopoverShape.arrow) }
            header
            if model.loading && model.senses.isEmpty {
                Divider().overlay(line)
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.status ?? "Looking up…").font(.system(size: 12)).foregroundStyle(.secondary)
                }.padding(.horizontal, 16).padding(.vertical, 12)
            } else if model.senses.isEmpty {
                Divider().overlay(line)
                Text(model.status ?? "No meaning found on this Mac.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.vertical, 12)
            } else {
                if model.explaining {
                    Rectangle().fill(line).frame(height: 1)
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Explaining the whole phrase…").font(.system(size: 12)).foregroundStyle(.secondary)
                    }.padding(.horizontal, 16).padding(.vertical, 9)
                }
                ForEach(Array(model.senses.enumerated()), id: \.element.id) { i, sense in
                    row(i, sense)
                }
                if !model.interests.isEmpty {
                    Rectangle().fill(line).frame(height: 1)
                    Text("Ranked by your history · \(model.interests.prefix(3).joined(separator: ", "))")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                }
            }
            Rectangle().fill(line).frame(height: 1)
            followUp
            HStack {
                Text(model.pinned ? "Esc to close" : "Release ⌃ to close")
                Spacer()
                Text(model.sourceNote)
            }
            .font(.system(size: 10.5)).foregroundStyle(.secondary)
            .padding(.horizontal, 16).padding(.bottom, 10)
            if !model.arrowUp { Spacer().frame(height: PopoverShape.arrow) }
        }
        .frame(width: 360)
        .overlay(PopoverShape(arrowX: model.arrowX, arrowUp: model.arrowUp).stroke(line, lineWidth: 1))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(model.term).font(.system(size: 17, weight: .bold)).lineLimit(1)
            Spacer()
            Button {
                model.starred.toggle()
                model.onStar?(model.starred)
            } label: {
                Image(systemName: model.starred ? "star.fill" : "star")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(model.starred ? Color.primary : .secondary)
                    .frame(width: 30, height: 30)
                    .overlay(Circle().stroke(model.starred ? Color.primary : line, lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(model.starred ? "Remove from Saved" : "Save term")
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
    }

    private func row(_ i: Int, _ sense: Sense) -> some View {
        let on = model.selected == sense.id
        return VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(line).frame(height: 1).padding(.horizontal, -16)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(i + 1)").font(.system(size: 11)).foregroundStyle(.secondary).frame(minWidth: 12, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(sense.name).font(.system(size: 14, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    if sense.term.caseInsensitiveCompare(model.term) != .orderedSame,
                       sense.term.caseInsensitiveCompare(sense.name) != .orderedSame {
                        Text(sense.term).font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 6)
                Text(sense.label)
                    .font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .overlay(Capsule().stroke(line, lineWidth: 1))
            }
            if on || sense.term.caseInsensitiveCompare(model.term) != .orderedSame {
                // the selected meaning in full; the parts of a phrase always show their definition
                Text(sense.gloss)
                    .lineLimit(on ? nil : 2)
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 20)
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            model.selected = sense.id
            model.onSelect?(sense)
        }
    }

    private var followUp: some View {
        HStack(spacing: 8) {
            Text(model.pinned ? "Follow-up questions are coming soon" : "Ask a follow-up…")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            Spacer()
            Text("Coming soon")
                .font(.system(size: 10.5)).foregroundStyle(Color.accentColor)
                .padding(.horizontal, 7).padding(.vertical, 1)
                .overlay(Capsule().stroke(Color.accentColor, lineWidth: 1))
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(scheme == .dark ? Color.white.opacity(0.06) : Color.white))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(model.pinned ? Color.accentColor : line, lineWidth: 1))
        .shadow(color: model.pinned ? Color.accentColor.opacity(0.25) : .clear, radius: 3)
        .contentShape(Rectangle())
        .onTapGesture { model.onFollowUp?() }
        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 8)
    }
}
