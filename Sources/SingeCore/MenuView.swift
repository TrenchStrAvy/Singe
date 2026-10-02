import ServiceManagement
import SwiftUI

/// The menu bar panel: History, Saved, and your coloured Lists.
struct MenuView: View {
    @ObservedObject var store: Store
    @ObservedObject var app: AppState
    var onExport: () -> Void
    var onQuit: () -> Void

    enum Tab: String, CaseIterable { case history = "History", saved = "Saved", lists = "Lists" }
    enum Sort: String, CaseIterable { case recent = "Recent", alpha = "A–Z", frequent = "Most looked up" }

    @State private var tab: Tab = .history
    @State private var sort: Sort = .recent
    @State private var search = ""
    @State private var colorFilter: String?
    @State private var listFilter: Int?
    @State private var expanded: String?
    @State private var newListName = ""
    @State private var newListColor = "blue"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !app.trusted { permissionBanner }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search Singed terms", text: $search).textFieldStyle(.plain)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor).opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1)))
            .padding(10)

            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(.horizontal, 10).padding(.bottom, 8)

            if tab != .lists { tools }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch tab {
                    case .history, .saved: termList
                    case .lists: listsPanel
                    }
                }
            }
            .frame(height: 330)

            Divider().padding(.vertical, 4)
            footer
        }
        .frame(width: 340)
    }

    // MARK: permission

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Singe needs Accessibility access").font(.system(size: 13, weight: .semibold))
            Text("It reads the text you highlight and listens for the Control key. Turn on Singe in Privacy & Security → Accessibility. If Singe is already listed and on but this message stays, select it, remove it with −, and add /Applications/Singe.app again with +.")
                .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Open Accessibility Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
        .padding([.horizontal, .top], 10)
    }

    // MARK: history & saved

    private var tools: some View {
        HStack(spacing: 7) {
            Text("Marks").foregroundStyle(.secondary)
            ForEach(ListColor.all, id: \.self) { c in
                Circle().fill(Color(nsColor: ListColor.nsColor(c))).frame(width: 9, height: 9)
                    .overlay(Circle().stroke(Color.primary, lineWidth: colorFilter == c ? 1.5 : 0))
                    .opacity(colorFilter == nil || colorFilter == c ? 1 : 0.35)
                    .onTapGesture { colorFilter = colorFilter == c ? nil : c; listFilter = nil }
                    .help(colorHelp(c))
            }
            Spacer()
            Menu(sort.rawValue) {
                ForEach(Sort.allCases, id: \.self) { s in Button(s.rawValue) { sort = s } }
            }
            .menuStyle(.borderlessButton).fixedSize()
        }
        .font(.system(size: 11.5))
        .padding(.horizontal, 12).padding(.bottom, 6)
    }

    private func colorHelp(_ c: String) -> String {
        let names = store.lists.filter { $0.color == c }.map(\.name)
        return names.isEmpty ? "No list with this colour yet" : names.joined(separator: ", ")
    }

    private var filtered: [TermRecord] {
        var items = store.records
        if tab == .saved { items = items.filter(\.starred) }
        if let c = colorFilter {
            let ids = Set(store.lists.filter { $0.color == c }.map(\.id))
            items = items.filter { !ids.isDisjoint(with: $0.lists) }
        }
        if let l = listFilter { items = items.filter { $0.lists.contains(l) } }
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

    @ViewBuilder private var termList: some View {
        if let l = listFilter, let list = store.lists.first(where: { $0.id == l }) {
            HStack {
                Circle().fill(Color(nsColor: ListColor.nsColor(list.color))).frame(width: 9, height: 9)
                Text(list.name).font(.system(size: 12, weight: .semibold))
                Spacer()
                Button("Show all") { listFilter = nil }.buttonStyle(.link).font(.system(size: 11.5))
            }
            .padding(.horizontal, 12).padding(.vertical, 4)
        }
        let items = filtered
        if items.isEmpty {
            Text(store.records.isEmpty
                 ? "Nothing Singed yet. Highlight a term anywhere and hold Left ⌃."
                 : "No terms match.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .padding(12)
        } else if sort == .recent {
            ForEach(groups(items), id: \.0) { title, group in
                Text(title.uppercased()).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 2)
                ForEach(group) { row($0) }
            }
        } else {
            ForEach(items) { row($0) }
        }
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

    private func row(_ r: TermRecord) -> some View {
        let time = DateFormatter.localizedString(from: r.lastSeen, dateStyle: .none, timeStyle: .short)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 9) {
                Image(systemName: r.starred ? "star.fill" : "star")
                    .font(.system(size: 11)).foregroundStyle(r.starred ? Color.primary : .secondary.opacity(0.5))
                    .onTapGesture { store.setStarred(r.key, !r.starred) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(r.term).font(.system(size: 13, weight: .semibold))
                    Text(r.meaning).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                HStack(spacing: 3) {
                    ForEach(store.lists.filter { r.lists.contains($0.id) }) { l in
                        Circle().fill(Color(nsColor: ListColor.nsColor(l.color))).frame(width: 8, height: 8)
                    }
                }
                Text("\(r.app) · \(time)").font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            if expanded == r.key {
                Text(r.gloss).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.leading, 20)
                Text("\(r.label) · looked up \(r.count)×").font(.system(size: 10.5)).foregroundStyle(.tertiary).padding(.leading, 20)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture { expanded = expanded == r.key ? nil : r.key }
        .contextMenu {
            Button(r.starred ? "Remove from Saved" : "Save") { store.setStarred(r.key, !r.starred) }
            Menu("Lists") {
                ForEach(store.lists) { l in
                    Button((r.lists.contains(l.id) ? "✓ " : "") + l.name) { store.toggle(r.key, in: l.id) }
                }
                if store.lists.isEmpty { Text("Create a list in the Lists tab") }
            }
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\(r.term): \(r.meaning). \(r.gloss)", forType: .string)
            }
            Divider()
            Button("Delete from History", role: .destructive) { store.delete(r.key) }
        }
    }

    // MARK: lists

    @ViewBuilder private var listsPanel: some View {
        ForEach(store.lists) { l in
            HStack(spacing: 9) {
                Circle().fill(Color(nsColor: ListColor.nsColor(l.color))).frame(width: 9, height: 9)
                Text(l.name).font(.system(size: 13))
                Spacer()
                Text("\(l.count)").font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .contentShape(Rectangle())
            .onTapGesture { listFilter = l.id; colorFilter = nil; tab = .history }
            .contextMenu { Button("Delete List", role: .destructive) { store.deleteList(l.id) } }
        }
        VStack(alignment: .leading, spacing: 8) {
            Text("New list").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("e.g. DORA", text: $newListName).textFieldStyle(.roundedBorder).font(.system(size: 12))
                    .onSubmit(createList)
                Button("Create", action: createList).controlSize(.small)
                    .disabled(newListName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack(spacing: 8) {
                ForEach(ListColor.all, id: \.self) { c in
                    Circle().fill(Color(nsColor: ListColor.nsColor(c))).frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.primary, lineWidth: newListColor == c ? 2 : 0))
                        .onTapGesture { newListColor = c }
                }
            }
            Text("Right-click a term in History to put it in a list. A list's colour is its mark.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
    }

    private func createList() {
        let name = newListName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        store.createList(name: name, color: newListColor)
        newListName = ""
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
                .toggleStyle(.checkbox).font(.system(size: 13))
                .padding(.horizontal, 12).padding(.vertical, 4)
            menuRow("Quit Singe", shortcut: "⌘Q", action: onQuit)
        }
        .padding(.bottom, 6)
    }

    private func menuRow(_ title: String, shortcut: String = "", action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Text(shortcut).foregroundStyle(.secondary)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 12).padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
