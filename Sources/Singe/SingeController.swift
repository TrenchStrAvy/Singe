import AppKit
import Combine

/// Hold Left Control over highlighted text → glass highlight + popover with the three
/// most relevant meanings. Release → both close, unless the follow-up box was clicked.
final class SingeController {
    let store: Store
    let index = TermIndex()
    let monitor = HoldKeyMonitor()
    private let highlight = HighlightWindow()
    let popover = PopoverWindow()
    private var lookupID = 0
    private var bag: Set<AnyCancellable> = []

    init(store: Store) {
        self.store = store
        let model = popover.model
        model.onSelect = { [weak self] sense in
            guard let self else { return }
            self.store.choose(term: model.term, sense: sense)
            DispatchQueue.main.async { self.popover.relayout() }
        }
        model.onStar = { [weak self] on in self?.store.setStarred(model.term, on) }
        model.onFollowUp = { [weak self] in
            model.pinned = true
            DispatchQueue.main.async { self?.popover.relayout() }
        }
        // @Published fires before the value changes, so resize once SwiftUI has
        // re-rendered: results arriving, a meaning expanding, the pin.
        model.objectWillChange
            .debounce(for: .milliseconds(12), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.popover.relayout() }
            .store(in: &bag)

        monitor.holdDelay = UserDefaults.standard.object(forKey: "holdDelay") as? Double ?? 0.35
        monitor.onHold = { [weak self] in self?.open() }
        monitor.onRelease = { [weak self] in
            guard let self, !self.popover.model.pinned else { return }
            self.close()
        }
        monitor.onEscape = { [weak self] in
            guard let self, self.isOpen else { return false }
            self.close()
            return true
        }
        monitor.onClick = { [weak self] p in
            guard let self, self.isOpen, !self.popover.frame.contains(p) else { return }
            self.close()
        }
        monitor.isInsideSinge = { [weak self] p in self?.popover.isVisible == true && self?.popover.frame.contains(p) == true }
        monitor.isOpen = { [weak self] in self?.isOpen ?? false }
    }

    var isOpen: Bool { popover.isVisible }

    func setHoldDelay(_ seconds: Double) {
        monitor.holdDelay = seconds
        UserDefaults.standard.set(seconds, forKey: "holdDelay")
    }

    // MARK: open / close

    func open() {
        guard !isOpen else { return }
        guard let sel = SelectionReader.read() else { return }       // nothing highlighted: do nothing
        open(sel)
    }

    func open(_ sel: Selection) {
        let text = TermIndex.normalize(sel.text)
        guard !text.isEmpty, text.count <= 80, text.split(separator: " ").count <= 8 else { return }

        lookupID += 1
        let id = lookupID
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let anchor: CGRect
        if let rect = sel.rect, rect.height < 60 {
            highlight.show(text: sel.text.trimmingCharacters(in: .whitespacesAndNewlines), over: rect, font: sel.font, dark: dark)
            anchor = rect.insetBy(dx: -HighlightWindow.padX, dy: -HighlightWindow.padY)
        } else {
            let m = NSEvent.mouseLocation
            anchor = sel.rect ?? CGRect(x: m.x - 1, y: m.y - 8, width: 2, height: 16)
        }

        let model = popover.model
        model.term = text
        model.senses = []
        model.selected = nil
        model.pinned = false
        model.loading = true
        model.status = nil
        model.starred = store.isStarred(text)
        model.interests = []
        popover.present(anchor: anchor)

        let profile = store.profile()
        let interests = store.topInterests(6)
        let recent = store.records.map(\.term).filter { $0.caseInsensitiveCompare(text) != .orderedSame }.prefix(3)
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self else { return }
            let ranked = Ranker.rank(self.index.candidates(for: text), profile: profile)
            DispatchQueue.main.async {
                guard id == self.lookupID else { return }
                if ranked.isEmpty {
                    model.status = "Asking the local model…"
                    Task { @MainActor in
                        let senses = await LocalModel.meanings(for: text, profileHint: interests)
                        guard id == self.lookupID else { return }
                        self.show(senses, for: text, app: sel.appName, interests: [])
                        if senses.isEmpty { model.status = "No meaning found on this Mac." }
                    }
                } else {
                    self.show(Array(ranked.prefix(3)), for: text, app: sel.appName,
                              interests: Array(recent))
                }
            }
        }
    }

    private func show(_ senses: [Sense], for term: String, app: String, interests: [String]) {
        let model = popover.model
        // A meaning you chose before for this term comes first again.
        var ordered = senses
        if let chosen = store.chosenMeaning(for: term), let i = ordered.firstIndex(where: { $0.name == chosen }), i > 0 {
            ordered.insert(ordered.remove(at: i), at: 0)
        }
        model.loading = false
        model.senses = ordered
        model.selected = ordered.first?.id
        model.interests = interests
        if let top = ordered.first {
            store.recordLookup(term: term, sense: top, app: app)
            model.starred = store.isStarred(term)
        }
    }

    func close() {
        lookupID += 1
        highlight.hide()
        popover.dismiss()
    }
}
