import ServiceManagement
import SwiftUI

/// The menu bar panel: History, Saved, your Collections of saved meanings, and the Apps
/// Singe has been used in, each with its Highlight switch. Same
/// design as the popover (variant B): ink on white glass, the chosen thing on a white card.
struct MenuView: View {
    @ObservedObject var store: Store
    @ObservedObject var app: AppState
    @ObservedObject var access = AppAccess.shared
    var onExport: () -> Void
    var onQuit: () -> Void

    enum Tab: String, CaseIterable { case history = "History", saved = "Saved", lists = "Collections", apps = "Apps" }
    enum Sort: String, CaseIterable { case recent = "Recent", alpha = "A–Z", frequent = "Most looked up" }

    @State private var tab: Tab
    @State private var sort: Sort = .recent
    @State private var search = ""
    @State private var openList: Int?          // the collection open in the Collections tab
    @State private var expanded: String?
    @State private var hovered: String?
    @State private var newListName = ""
    @Namespace private var tabs
    @Namespace private var lift

    init(store: Store, app: AppState, onExport: @escaping () -> Void, onQuit: @escaping () -> Void, startTab: Tab = .history) {
        self.store = store
        self.app = app
        self.onExport = onExport
        self.onQuit = onQuit
        _tab = State(initialValue: startTab)
    }

    /// `Singe --menu-demo` opens the first collection with this.
    static let openFirstForDemo = Notification.Name("SingeMenuOpenFirst")

    private let ink = PopoverView.ink, soft = PopoverView.soft, muted = PopoverView.muted, hair = PopoverView.hair

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !app.trusted { permissionBanner }
            searchField
            tabBar
            if tab == .history || tab == .saved { tools }

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    switch tab {
                    case .history, .saved: records
                    case .apps: appsPanel
                    case .lists:
                        if let id = openList, let list = store.lists.first(where: { $0.id == id }) {
                            collectionView(list)
                        } else {
                            listsPanel
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            }
            .frame(height: 330)

            Rectangle().fill(hair).frame(height: 1).padding(.horizontal, 12).padding(.bottom, 4)
            footer
        }
        .foregroundStyle(ink)
        .onReceive(NotificationCenter.default.publisher(for: Self.openFirstForDemo)) { _ in
            withAnimation(PopoverView.flow) { openList = store.lists.first?.id }
        }
    }

    // MARK: header

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").foregroundStyle(muted)
            TextField(tab == .apps ? "Search apps" : "Search Singed terms", text: $search).textFieldStyle(.plain)
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(muted) }
                    .buttonStyle(.plain)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Capsule().fill(Color.white))
        .overlay(Capsule().stroke(Color.black.opacity(0.08), lineWidth: 1))
        .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 10)
    }

    /// The tabs: the chosen one sits on a white card that glides between them.
    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases, id: \.self) { t in
                Text(t.rawValue)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(tab == t ? ink : muted)
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .background {
                        if tab == t {
                            Capsule().fill(Color.white)
                                .shadow(color: Color(red: 0.08, green: 0.09, blue: 0.16).opacity(0.08), radius: 5, y: 2)
                                .overlay(Capsule().stroke(Color.black.opacity(0.06), lineWidth: 1))
                                .matchedGeometryEffect(id: "tab", in: tabs)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture { withAnimation(PopoverView.flow) { tab = t; if t != .lists { openList = nil } } }
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.black.opacity(0.045)))
        .padding(.horizontal, 12).padding(.bottom, 8)
    }

    // MARK: permission

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Singe needs Accessibility access").font(.system(size: 13, weight: .semibold))
            Text("It reads the text you highlight and listens for the Control key. Turn on Singe in Privacy & Security → Accessibility. If Singe is already listed and on but this message stays, select it, remove it with −, and add /Applications/Singe.app again with +.")
                .font(.system(size: 11.5)).foregroundStyle(soft).fixedSize(horizontal: false, vertical: true)
            Button("Open Accessibility Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            .buttonStyle(OutlinePill())
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ink, lineWidth: 1.5))
        .padding([.horizontal, .top], 12)
    }

    // MARK: history & saved

    private var tools: some View {
        HStack {
            Text(tab == .saved ? "\(filtered.count) saved" : "\(store.records.count) terms")
                .foregroundStyle(muted)
            Spacer()
            Menu(sort.rawValue) {
                ForEach(Sort.allCases, id: \.self) { s in Button(s.rawValue) { sort = s } }
            }
            .menuStyle(.borderlessButton).fixedSize()
        }
        .font(.system(size: 11.5))
        .padding(.horizontal, 18).padding(.bottom, 4)
    }

    private var filtered: [TermRecord] {
        var items = store.records
        if tab == .saved { items = items.filter(\.starred) }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            items = items.filter { $0.term.lowercased().contains(q) || $0.meaning.lowercased().contains(q) || $0.gloss.lowercased().contains(q) }
        }
        switch sort {
        case .recent: break
        case .alpha: items.sort { $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending }
        case .frequent: items.sort { $0.count > $1.count }
        }
        return items
    }

    @ViewBuilder private var records: some View {
        let items = filtered
        if items.isEmpty {
            emptyNote(store.records.isEmpty
                      ? "Nothing Singed yet. Highlight a term anywhere and hold Left ⌃."
                      : tab == .saved ? "Nothing saved yet. Click the star next to a meaning in the popover." : "No terms match.")
        } else if sort == .recent {
            ForEach(groups(items), id: \.0) { title, group in
                sectionTitle(title)
                ForEach(group) { row($0) }
            }
        } else {
            ForEach(items) { row($0) }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(0.4).foregroundStyle(muted)
            .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 2)
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10).padding(.vertical, 12)
    }

    private func groups(_ items: [TermRecord]) -> [(String, [TermRecord])] {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE d MMM"
        var out: [(String, [TermRecord])] = []
        for r in items {
            let title = cal.isDateInToday(r.lastSeen) ? "Today" : cal.isDateInYesterday(r.lastSeen) ? "Yesterday" : fmt.string(from: r.lastSeen)
            if out.last?.0 == title { out[out.count - 1].1.append(r) } else { out.append((title, [r])) }
        }
        return out
    }

    /// A white card under the open row, gliding from row to row like the popover's.
    @ViewBuilder private func card(_ on: Bool) -> some View {
        if on {
            RoundedRectangle(cornerRadius: 12).fill(Color.white)
                .shadow(color: Color(red: 0.08, green: 0.09, blue: 0.16).opacity(0.07), radius: 7, y: 4)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.06), lineWidth: 1))
                .matchedGeometryEffect(id: "lift", in: lift)
        }
    }

    private func toggleExpanded(_ id: String) {
        withAnimation(PopoverView.flow) { expanded = expanded == id ? nil : id }
    }

    private func row(_ r: TermRecord) -> some View {
        let time = DateFormatter.localizedString(from: r.lastSeen, dateStyle: .none, timeStyle: .short)
        let on = expanded == r.key
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 9) {
                Image(systemName: r.starred ? "star.fill" : "star")
                    .font(.system(size: 11)).foregroundStyle(r.starred ? ink : muted.opacity(0.7))
                    .onTapGesture { store.setStarred(r.key, !r.starred) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(r.term).font(.system(size: 13, weight: .semibold))
                    Text(r.meaning).font(.system(size: 11.5)).foregroundStyle(on || hovered == r.key ? soft : muted).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text("\(r.app) · \(time)").font(.system(size: 10.5)).foregroundStyle(muted).lineLimit(1)
            }
            if on {
                Text(r.gloss).font(.system(size: 12)).foregroundStyle(soft)
                    .fixedSize(horizontal: false, vertical: true).padding(.leading, 20)
                    .transition(.opacity.combined(with: .offset(y: -3)))
                Text("\(r.label) · looked up \(r.count)×").font(.system(size: 10.5)).foregroundStyle(muted).padding(.leading, 20)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background { card(on) }
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? r.key : (hovered == r.key ? nil : hovered) }
        .onTapGesture { toggleExpanded(r.key) }
        .contextMenu {
            Button(r.starred ? "Remove from Saved" : "Save") { store.setStarred(r.key, !r.starred) }
            Menu("Save to Collection") {
                ForEach(store.lists) { l in
                    Button((store.collections(term: r.term, meaning: r.meaning).contains(l.id) ? "✓ " : "") + l.name) {
                        store.toggle(r.key, in: l.id)
                    }
                }
                if store.lists.isEmpty { Text("Create one in the Collections tab") }
            }
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\(r.term): \(r.meaning). \(r.gloss)", forType: .string)
            }
            Divider()
            Button("Delete from History", role: .destructive) { store.delete(r.key) }
        }
    }

    // MARK: collections

    @ViewBuilder private var listsPanel: some View {
        if store.lists.isEmpty {
            emptyNote("No collections yet. Make one here, or with the star next to a meaning in the popover.")
        }
        ForEach(store.lists) { l in
            HStack(spacing: 10) {
                Image(systemName: "folder").font(.system(size: 12)).foregroundStyle(hovered == "l\(l.id)" ? ink : soft)
                Text(l.name).font(.system(size: 13, weight: .medium))
                Spacer()
                Text("\(l.count)").font(.system(size: 11.5)).foregroundStyle(muted)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(muted)
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(hovered == "l\(l.id)" ? 0.035 : 0)))
            .contentShape(Rectangle())
            .onHover { hovered = $0 ? "l\(l.id)" : (hovered == "l\(l.id)" ? nil : hovered) }
            .onTapGesture { withAnimation(PopoverView.flow) { openList = l.id; expanded = nil } }
            .contextMenu { Button("Delete Collection", role: .destructive) { store.deleteList(l.id) } }
        }
        VStack(alignment: .leading, spacing: 8) {
            Text("New collection").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(muted)
            HStack(spacing: 8) {
                TextField("e.g. DORA", text: $newListName)
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(Color.white))
                    .overlay(Capsule().stroke(Color.black.opacity(0.1), lineWidth: 1))
                    .onSubmit(createList)
                Button("Create", action: createList)
                    .buttonStyle(OutlinePill())
                    .disabled(newListName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("In the popover, click the star next to a meaning to save that meaning to a collection.")
                .font(.system(size: 11)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10).padding(.top, 14)
    }

    /// One collection, opened in place: the meanings saved in it, each with its definition.
    @ViewBuilder private func collectionView(_ list: TermList) -> some View {
        Button { withAnimation(PopoverView.flow) { openList = nil; expanded = nil } } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                Text("Collections").font(.system(size: 12))
            }
            .foregroundStyle(soft).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10).padding(.top, 2)
        HStack(alignment: .firstTextBaseline) {
            Text(list.name).font(.system(size: 18, weight: .bold)).tracking(-0.3)
            Spacer()
            Text(list.count == 1 ? "1 meaning" : "\(list.count) meanings").font(.system(size: 11.5)).foregroundStyle(muted)
        }
        .padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 4)
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let items = store.items(in: list.id).filter {
            q.isEmpty || $0.term.lowercased().contains(q) || $0.meaning.lowercased().contains(q) || $0.gloss.lowercased().contains(q)
        }
        if items.isEmpty {
            emptyNote(q.isEmpty ? "Nothing saved here yet. Click the star next to a meaning in the popover to save it." : "No saved meanings match.")
        }
        ForEach(items) { it in
            let on = expanded == it.id
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 9) {
                    Image(systemName: "star.fill").font(.system(size: 11))
                    Text(it.term).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(it.label).font(.system(size: 10.5)).foregroundStyle(muted).lineLimit(1)
                }
                Text(it.meaning).font(.system(size: 12)).foregroundStyle(on ? ink : soft).padding(.leading, 20)
                    .fixedSize(horizontal: false, vertical: true)
                if on, !it.gloss.isEmpty {
                    Text(it.gloss).font(.system(size: 12)).foregroundStyle(soft)
                        .fixedSize(horizontal: false, vertical: true).padding(.leading, 20)
                        .transition(.opacity.combined(with: .offset(y: -3)))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background { card(on) }
            .contentShape(Rectangle())
            .onTapGesture { toggleExpanded(it.id) }
            .contextMenu {
                Button("Remove from \(list.name)") {
                    store.toggle(term: it.term, meaning: it.meaning, gloss: it.gloss, label: it.label, in: list.id)
                }
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("\(it.term): \(it.meaning). \(it.gloss)", forType: .string)
                }
            }
        }
    }

    private func createList() {
        let name = newListName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        store.createList(name: name)
        newListName = ""
    }

    // MARK: apps

    /// Every app Singe was used in, with how often it could place the highlight there and the
    /// switch that allows it. Off: meanings only, and Singe leaves that app's settings alone.
    @ViewBuilder private var appsPanel: some View {
        Text("Singe highlights the word in apps that say where it is on screen. Some apps only do once their full accessibility mode is on; Singe turns it on for them the first time it is needed. Switch an app off for meanings only.")
            .font(.system(size: 11.5)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10).padding(.top, 2).padding(.bottom, 6)
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let apps = access.apps.filter { q.isEmpty || $0.name.lowercased().contains(q) }
        if apps.isEmpty {
            emptyNote(access.apps.isEmpty ? "No apps yet. Each app you hold Left ⌃ in appears here." : "No apps match.")
        }
        ForEach(apps) { a in
            HStack(spacing: 10) {
                appIcon(a.bundle)
                VStack(alignment: .leading, spacing: 1) {
                    Text(a.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(status(a)).font(.system(size: 11)).foregroundStyle(muted).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Toggle("", isOn: Binding(get: { a.highlight }, set: { access.setHighlight($0, for: a.bundle) }))
                    .toggleStyle(.switch).controlSize(.small).labelsHidden().tint(ink)
                    .help("Highlight the word in \(a.name)")
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .contextMenu { Button("Forget \(a.name)", role: .destructive) { access.forget(a.bundle) } }
        }
    }

    private func status(_ a: AppRecord) -> String {
        guard a.highlight else { return "Meanings only" }
        let n = a.lookups == 1 ? "1 lookup" : "\(a.lookups) lookups"
        if a.lookups == 0 { return a.deep ? "Full accessibility mode on" : "Not used yet" }
        if a.placed == 0 { return "\(n), none placed: this app does not say where its text is" }
        let mode = a.deep ? " · full accessibility mode" : ""
        return "Highlighted \(a.placed) of \(n)\(mode)"
    }

    private func appIcon(_ bundle: String) -> some View {
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
            .map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!
        return Image(nsImage: icon).resizable().frame(width: 22, height: 22)
    }

    // MARK: footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            menuRow("Export to Obsidian…", action: onExport)
            HStack {
                Text("Hold delay").font(.system(size: 13))
                Spacer()
                Picker("", selection: $app.holdDelay) {
                    Text("0.25 s").tag(0.25)
                    Text("0.35 s").tag(0.35)
                    Text("0.5 s").tag(0.5)
                }
                .labelsHidden().fixedSize()
            }
            .padding(.horizontal, 12).padding(.vertical, 3)
            Toggle("Open at login", isOn: $app.launchAtLogin)
                .toggleStyle(.checkbox).font(.system(size: 13)).tint(ink)
                .padding(.horizontal, 12).padding(.vertical, 4)
            menuRow("Quit Singe", shortcut: "⌘Q", action: onQuit)
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 10)
    }

    private func menuRow(_ title: String, shortcut: String = "", action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Text(shortcut).foregroundStyle(muted)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(hovered == "m" + title ? 0.04 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? "m" + title : (hovered == "m" + title ? nil : hovered) }
    }
}

/// The popover's follow-up look as a button: black outline, white pill.
struct OutlinePill: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(PopoverView.ink)
            .padding(.horizontal, 13).padding(.vertical, 6)
            .background(Capsule().fill(configuration.isPressed ? Color(white: 0.94) : Color.white))
            .overlay(Capsule().stroke(PopoverView.ink, lineWidth: 1.5))
            .opacity(enabled ? 1 : 0.35)
    }
}

/// App-level settings shown in the menu panel.
final class AppState: ObservableObject {
    @Published var trusted = false
    @Published var holdDelay: Double {
        didSet { onHoldDelay?(holdDelay) }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Singe: login item: \(error)")
            }
        }
    }
    var onHoldDelay: ((Double) -> Void)?

    init() {
        holdDelay = UserDefaults.standard.object(forKey: "holdDelay") as? Double ?? 0.35
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
