import CmuxFoundation
import AppKit
import Bonsplit
import SwiftUI
import CmuxTerminal
import CmuxTerminalCore

private extension NSView {
    func cmuxAncestor<T: NSView>(of type: T.Type) -> T? {
        var current: NSView? = self
        while let view = current {
            if let target = view as? T {
                return target
            }
            current = view.superview
        }
        return nil
    }
}

/// Hosting root for the terminal find bar: the overlay plus the cmux accent
/// environment, since it mounts outside any window root.
typealias SurfaceSearchOverlayRoot = ModifiedContent<SurfaceSearchOverlay, CmuxAccentColorEnvironmentModifier>

struct SurfaceSearchOverlay: View {
    @Environment(\.cmuxAccentColor) private var cmuxAccent
    let tabId: UUID
    let surfaceId: UUID
    @ObservedObject var searchState: TerminalSurface.SearchState
    let canApplyFocusRequest: () -> Bool
    let onNavigateSearch: (_ direction: TerminalSearchNavigation) -> Void
    let onSearchTextChanged: () -> Void
    let onFieldDidFocus: () -> Void
    let onClose: () -> Void
    let makeFilterSource: () -> any TerminalLineFilterSource
    let makeFilterAppearance: () -> TerminalLineFilterAppearance
    @State private var corner: Corner = .topRight
    @State private var dragOffset: CGSize = .zero
    @State private var barSize: CGSize = .zero
    @State private var isSearchFieldFocused: Bool = true
    @State private var isSearchFieldEditing: Bool = false
    /// Non-nil while the filter is on: the pane shows only matching lines.
    @State private var filterModel: TerminalLineFilterModel?
    @State private var filterAppearance: TerminalLineFilterAppearance?

    private let padding: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 4) {
                SearchTextFieldRepresentable(
                    text: $searchState.needle,
                    isFocused: $isSearchFieldFocused,
                    surfaceId: surfaceId,
                    selectionOwner: searchState,
                    canApplyFocusRequest: canApplyFocusRequest,
                    onTextChanged: onSearchTextChanged,
                    onFieldDidFocus: onFieldDidFocus,
                    onEditingChanged: { isSearchFieldEditing = $0 },
                    onEscape: {
                        #if DEBUG
                        cmuxDebugLog("find.nativeField.escape surface=\(surfaceId.uuidString.prefix(5)) needleEmpty=\(searchState.needle.isEmpty)")
                        #endif
                        onClose()
                    },
                    onReturn: { isShift in
                        onNavigateSearch(isShift ? .previous : .next)
                    },
                    onToggleFilter: toggleFilter
                )
                .accessibilityIdentifier("TerminalFindSearchTextField")
                .frame(width: 180)
                .padding(.leading, 8)
                .padding(.trailing, 50)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.1))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSearchFieldEditing ? cmuxAccent.color : Color.clear, lineWidth: 1)
                )
                .overlay(alignment: .trailing) {
                    if let selected = searchState.selected {
                        let totalText = searchState.total.map { String($0) } ?? "?"
                        Text("\(selected + 1)/\(totalText)")
                            .cmuxFont(.caption)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                            .padding(.trailing, 8)
                    } else if let total = searchState.total {
                        Text("-/\(total)")
                            .cmuxFont(.caption)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                            .padding(.trailing, 8)
                    }
                }

                Button(action: toggleFilter) {
                    Image(systemName: "line.3.horizontal.decrease")
                }
                .buttonStyle(SearchButtonStyle())
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(cmuxAccent.color.opacity(filterModel == nil ? 0 : 0.3))
                )
                .accessibilityIdentifier("TerminalFindFilterToggle")
                .accessibilityAddTraits(filterModel == nil ? [] : .isSelected)
                .safeHelp(String(localized: "search.filter.toggle.help", defaultValue: "Show only matching lines (⌥⌘L)"))

                Button(action: {
                    #if DEBUG
                    cmuxDebugLog("findbar.next surface=\(surfaceId.uuidString.prefix(5))")
                    #endif
                    onNavigateSearch(.next)
                }) {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(SearchButtonStyle())
                .safeHelp(String(localized: "search.nextMatch.help", defaultValue: "Next match (Return)"))

                Button(action: {
                    #if DEBUG
                    cmuxDebugLog("findbar.prev surface=\(surfaceId.uuidString.prefix(5))")
                    #endif
                    onNavigateSearch(.previous)
                }) {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(SearchButtonStyle())
                .safeHelp(String(localized: "search.previousMatch.help", defaultValue: "Previous match (Shift+Return)"))

                Button(action: {
                    #if DEBUG
                    cmuxDebugLog("findbar.close surface=\(surfaceId.uuidString.prefix(5))")
                    #endif
                    onClose()
                }) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(SearchButtonStyle())
                .safeHelp(String(localized: "search.close.help", defaultValue: "Close (Esc)"))
            }
            .padding(8)
            .background(.background)
            .clipShape(clipShape)
            .shadow(radius: 4)
            .onAppear {
                #if DEBUG
                cmuxDebugLog("find.overlay.appear tab=\(tabId.uuidString.prefix(5)) surface=\(surfaceId.uuidString.prefix(5))")
                #endif
                isSearchFieldFocused = true
            }
            .background(
                GeometryReader { barGeo in
                    Color.clear.onAppear {
                        barSize = barGeo.size
                    }
                }
            )
            .padding(padding)
            .offset(dragOffset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner.alignment)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        let centerPos = centerPosition(for: corner, in: geo.size, barSize: barSize)
                        let newCenter = CGPoint(
                            x: centerPos.x + value.translation.width,
                            y: centerPos.y + value.translation.height
                        )
                        let newCorner = closestCorner(to: newCenter, in: geo.size)
                        withAnimation(.easeOut(duration: 0.2)) {
                            corner = newCorner
                            dragOffset = .zero
                        }
                    }
            )
            // Behind the bar and outside its drag gesture, so the list scrolls
            // and takes clicks without moving the bar.
            .background { filterList }
            .onChange(of: searchState.needle) { _, needle in
                filterModel?.update(needle: needle)
            }
            .onReceive(NotificationCenter.default.publisher(for: .ghosttyDidUpdateScrollbar)) { notification in
                guard let filterModel,
                      (notification.object as? GhosttyNSView)?.terminalSurface?.id == surfaceId else { return }
                filterModel.refresh()
            }
            .task(id: filterModel == nil) {
                // The scrollbar only reports rows scrolling into history. Text
                // rewritten in place on the active screen needs a slow reread.
                guard filterModel != nil else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    filterModel?.refresh()
                }
            }
            .onDisappear {
                filterModel?.stop()
                filterModel = nil
            }
        }
    }

    @ViewBuilder
    private var filterList: some View {
        if let filterModel, let filterAppearance {
            TerminalLineFilterListView(
                lines: filterModel.lines,
                isNeedleEmpty: searchState.needle.isEmpty,
                isScanning: filterModel.isScanning,
                isTruncated: filterModel.isTruncated,
                appearance: filterAppearance,
                accent: cmuxAccent.color,
                findBarEdge: corner.isTop ? .top : .bottom,
                onReveal: reveal
            )
        }
    }

    private func toggleFilter() {
        if let filterModel {
            #if DEBUG
            cmuxDebugLog("findbar.filter.off surface=\(surfaceId.uuidString.prefix(5))")
            #endif
            filterModel.stop()
            self.filterModel = nil
        } else {
            #if DEBUG
            cmuxDebugLog("findbar.filter.on surface=\(surfaceId.uuidString.prefix(5))")
            #endif
            let model = TerminalLineFilterModel(source: makeFilterSource())
            model.start()
            model.update(needle: searchState.needle)
            filterAppearance = makeFilterAppearance()
            filterModel = model
        }
        isSearchFieldFocused = true
    }

    /// Scrolls the terminal to a filtered line and uncovers it. Find stays
    /// open, so the match is still highlighted in context.
    private func reveal(_ line: TerminalLineFilterLine) {
        guard let filterModel, filterModel.reveal(line) else { return }
        filterModel.stop()
        self.filterModel = nil
    }

    private var clipShape: some Shape {
        RoundedRectangle(cornerRadius: 8)
    }

    enum Corner {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight

        var alignment: Alignment {
            switch self {
            case .topLeft: return .topLeading
            case .topRight: return .topTrailing
            case .bottomLeft: return .bottomLeading
            case .bottomRight: return .bottomTrailing
            }
        }

        var isTop: Bool {
            self == .topLeft || self == .topRight
        }
    }

    private func centerPosition(for corner: Corner, in containerSize: CGSize, barSize: CGSize) -> CGPoint {
        let halfWidth = barSize.width / 2 + padding
        let halfHeight = barSize.height / 2 + padding

        switch corner {
        case .topLeft:
            return CGPoint(x: halfWidth, y: halfHeight)
        case .topRight:
            return CGPoint(x: containerSize.width - halfWidth, y: halfHeight)
        case .bottomLeft:
            return CGPoint(x: halfWidth, y: containerSize.height - halfHeight)
        case .bottomRight:
            return CGPoint(x: containerSize.width - halfWidth, y: containerSize.height - halfHeight)
        }
    }

    private func closestCorner(to point: CGPoint, in containerSize: CGSize) -> Corner {
        let midX = containerSize.width / 2
        let midY = containerSize.height / 2

        if point.x < midX {
            return point.y < midY ? .topLeft : .bottomLeft
        }
        return point.y < midY ? .topRight : .bottomRight
    }
}

// MARK: - Native Search Text Field (AppKit)

/// NSTextField subclass for the terminal find bar.
/// Strips visual chrome so SwiftUI handles the background/border appearance.
private final class SearchNativeTextField: FindSelectionTrackingTextField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        usesSingleLineMode = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var cmuxOnToggleFilter: (() -> Void)?

    /// Handles ⌥⌘L (filter) while the field is being edited.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.intersection([.command, .option, .control, .shift]) == [.command, .option],
              let window,
              cmuxTextFieldIsFirstResponder(self, in: window),
              KeyboardLayout.normalizedCharacters(for: event) == "l",
              let cmuxOnToggleFilter else {
            return super.performKeyEquivalent(with: event)
        }
        cmuxOnToggleFilter()
        return true
    }
}

/// NSViewRepresentable wrapping SearchNativeTextField.
/// Handles Escape and Return at the AppKit delegate level, eliminating the
/// SwiftUI @FocusState / AppKit first-responder mismatch that broke focus
/// after window switching.
private struct SearchTextFieldRepresentable: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let surfaceId: UUID
    let selectionOwner: AnyObject
    let canApplyFocusRequest: () -> Bool
    let onTextChanged: () -> Void
    let onFieldDidFocus: () -> Void
    /// Actual editing state, reported by the field itself. `isFocused` is only
    /// the focus request and can stay true when focus never lands.
    let onEditingChanged: (Bool) -> Void
    let onEscape: () -> Void
    let onReturn: (_ isShift: Bool) -> Void
    let onToggleFilter: () -> Void
    @Environment(\.cmuxGlobalFontMagnificationPercent) private var globalFontPercent

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchTextFieldRepresentable
        var isProgrammaticMutation = false
        weak var parentField: SearchNativeTextField?
        var pendingFocusRequest: Bool?
        var searchFocusObserver: NSObjectProtocol?
        var lastSelectedRange: NSRange?

        init(parent: SearchTextFieldRepresentable) {
            self.parent = parent
        }

        deinit {
            if let searchFocusObserver {
                NotificationCenter.default.removeObserver(searchFocusObserver)
            }
        }

        func focusField(_ field: SearchNativeTextField, in window: NSWindow, selectAll: Bool) {
            let alreadyFocused = cmuxTextFieldIsFirstResponder(field, in: window)
            guard alreadyFocused || window.makeFirstResponder(field) else { return }
            let rememberedRange = field.cmuxLastSelectedRange ?? cmuxStoredFindSelection(for: self.parent.selectionOwner) ?? self.lastSelectedRange
            if let selection = cmuxApplyFindFocusSelection(field: field, selectAll: selectAll, alreadyFocused: alreadyFocused, rememberedRange: rememberedRange) { self.lastSelectedRange = selection; return }
            DispatchQueue.main.async { [weak field, weak self] in
                guard let field, let self,
                      let selection = cmuxApplyFindFocusSelection(field: field, selectAll: selectAll, alreadyFocused: alreadyFocused, rememberedRange: rememberedRange) else { return }
                self.lastSelectedRange = selection
            }
        }

        func controlTextDidChange(_ obj: Notification) {
            guard !isProgrammaticMutation else { return }
            guard let field = obj.object as? NSTextField else { return }
            parent.onTextChanged()
            parent.text = field.stringValue
            rememberSelection(from: field)
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            #if DEBUG
            cmuxDebugLog("find.nativeField.beginEditing surface=\(parent.surfaceId.uuidString.prefix(5))")
            #endif
            parent.onFieldDidFocus()
            if !parent.isFocused {
                DispatchQueue.main.async {
                    self.parent.isFocused = true
                }
            }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            #if DEBUG
            cmuxDebugLog("find.nativeField.endEditing surface=\(parent.surfaceId.uuidString.prefix(5))")
            #endif
            if let field = obj.object as? NSTextField {
                rememberSelection(from: field)
            }
            if parent.isFocused {
                DispatchQueue.main.async {
                    self.parent.isFocused = false
                }
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.cancelOperation(_:)):
                return handleEscape(from: textView, control: control)
            case #selector(NSResponder.insertNewline(_:)):
                if textView.hasMarkedText() { return false }
                rememberSelection(from: textView)
                let isShift = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
                parent.onReturn(isShift)
                return true
            default:
                if cmuxFindCommandMayChangeSelection(commandSelector) {
                    DispatchQueue.main.async { [weak self, weak textView] in
                        guard let textView else { return }
                        self?.rememberSelection(from: textView)
                    }
                }
                return false
            }
        }

        func handleEscape(from textView: NSTextView, control: NSControl? = nil) -> Bool {
            // Don't intercept Escape during CJK IME composition (issue #118)
            if textView.hasMarkedText() { return false }
            rememberSelection(from: textView)
            (control ?? parentField)?.cmuxAncestor(of: GhosttySurfaceScrollView.self)?.beginFindEscapeSuppression()
            parent.onEscape()
            return true
        }

        private func rememberSelection(from field: NSTextField) {
            if let field = field as? SearchNativeTextField,
               let selection = field.cmuxRememberSelectionFromCurrentEditor() {
                lastSelectedRange = selection
                return
            }
            guard let editor = field.currentEditor() as? NSTextView else { return }
            rememberSelection(from: editor)
        }

        private func rememberSelection(from textView: NSTextView) {
            let selection = cmuxClampedFindSelection(textView.selectedRange(), in: textView.string)
            lastSelectedRange = selection
            parentField?.cmuxLastSelectedRange = selection
            cmuxStoreFindSelection(selection, for: parent.selectionOwner)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> SearchNativeTextField {
        let field = SearchNativeTextField(frame: .zero)
        field.font = GlobalFontMagnification.systemFont(ofSize: NSFont.systemFontSize)
        field.placeholderString = String(localized: "search.placeholder", defaultValue: "Search")
        field.setAccessibilityIdentifier("TerminalFindSearchTextField")
        field.cmuxOnEditingChanged = { [weak coordinator = context.coordinator] isEditing in
            // Deferred like the isFocused writes: AppKit can report this while
            // SwiftUI is updating the view.
            DispatchQueue.main.async {
                coordinator?.parent.onEditingChanged(isEditing)
            }
        }
        field.delegate = context.coordinator
        field.cmuxSelectionOwner = selectionOwner
        field.cmuxOnEscape = { [weak coordinator = context.coordinator] textView in coordinator?.handleEscape(from: textView) ?? false }
        field.cmuxOnToggleFilter = { [weak coordinator = context.coordinator] in coordinator?.parent.onToggleFilter() }
        field.stringValue = text
        context.coordinator.parentField = field

        // Observe .ghosttySearchFocus to immediately focus from AppKit level.
        // This is the primary mechanism for restoring focus after window switches.
        context.coordinator.searchFocusObserver = NotificationCenter.default.addObserver(
            forName: .ghosttySearchFocus,
            object: nil,
            queue: .main
        ) { [weak field, weak coordinator = context.coordinator] notification in
            guard let field, let coordinator else { return }
            guard let surface = notification.object as? TerminalSurface,
                  surface.id == coordinator.parent.surfaceId else { return }
            guard coordinator.parent.canApplyFocusRequest() else { return }
            guard let window = field.window else { return }
            let selectAll = notification.userInfo?[FindFocusNotificationKey.selectAll] as? Bool == true
            // Don't re-focus if already first responder. makeFirstResponder on an
            // already-editing NSTextField ends the editing session and restarts it
            // with all text selected, causing typed characters to replace each other.
            let alreadyFocused = cmuxTextFieldIsFirstResponder(field, in: window)
            #if DEBUG
            cmuxDebugLog(
                "find.nativeField.searchFocusNotification surface=\(coordinator.parent.surfaceId.uuidString.prefix(5)) " +
                "alreadyFocused=\(alreadyFocused) firstResponder=\(String(describing: window.firstResponder))"
            )
            #endif
            guard !alreadyFocused else { return }
            coordinator.focusField(field, in: window, selectAll: selectAll)
#if DEBUG
            cmuxDebugLog(
                "find.nativeField.searchFocusApply surface=\(coordinator.parent.surfaceId.uuidString.prefix(5)) " +
                "selectAll=\(selectAll ? 1 : 0) firstResponder=\(String(describing: window.firstResponder))"
            )
#endif
        }

        return field
    }

    func updateNSView(_ nsView: SearchNativeTextField, context: Context) {
        context.coordinator.parent = self
        context.coordinator.parentField = nsView
        nsView.delegate = context.coordinator
        nsView.cmuxSelectionOwner = selectionOwner
        nsView.cmuxOnEscape = { [weak coordinator = context.coordinator] textView in coordinator?.handleEscape(from: textView) ?? false }
        nsView.cmuxOnToggleFilter = { [weak coordinator = context.coordinator] in coordinator?.parent.onToggleFilter() }
        nsView.font = GlobalFontMagnification.systemFont(ofSize: NSFont.systemFontSize)

        // Sync text from binding to field (skip during active IME composition)
        if let editor = nsView.currentEditor() as? NSTextView {
            if editor.string != text, !editor.hasMarkedText() {
                let selectedRange = nsView.cmuxRememberSelection(editor.selectedRange(), in: text)
                context.coordinator.isProgrammaticMutation = true
                editor.string = text
                nsView.stringValue = text
                editor.setSelectedRange(selectedRange)
                context.coordinator.lastSelectedRange = selectedRange
                cmuxStoreFindSelection(selectedRange, for: selectionOwner)
                context.coordinator.isProgrammaticMutation = false
            }
        } else if nsView.stringValue != text {
            nsView.stringValue = text
        }

        // Sync focus from binding to AppKit
        if let window = nsView.window {
            let isFirstResponder = cmuxTextFieldIsFirstResponder(nsView, in: window)

            if isFocused,
               canApplyFocusRequest(),
               !isFirstResponder,
               context.coordinator.pendingFocusRequest != true {
                context.coordinator.pendingFocusRequest = true
                DispatchQueue.main.async { [weak nsView, weak coordinator = context.coordinator] in
                    coordinator?.pendingFocusRequest = nil
                    guard let coordinator,
                          coordinator.parent.isFocused,
                          coordinator.parent.canApplyFocusRequest() else { return }
                    guard let nsView, let window = nsView.window else { return }
                    let alreadyFocused = cmuxTextFieldIsFirstResponder(nsView, in: window)
                    guard !alreadyFocused else { return }
                    coordinator.focusField(nsView, in: window, selectAll: false)
                }
            }
        }
    }

    static func dismantleNSView(_ nsView: SearchNativeTextField, coordinator: Coordinator) {
        if let observer = coordinator.searchFocusObserver {
            NotificationCenter.default.removeObserver(observer)
            coordinator.searchFocusObserver = nil
        }
        nsView.delegate = nil
        nsView.cmuxSelectionOwner = nil
        nsView.cmuxOnEscape = nil
        nsView.cmuxOnToggleFilter = nil
        coordinator.parentField = nil
    }
}

struct SearchButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isHovered || configuration.isPressed ? .primary : .secondary)
            .padding(.horizontal, 2)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .onHover { hovering in
                isHovered = hovering
            }
            .backport.pointerStyle(.link)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return Color.primary.opacity(0.2)
        }
        if isHovered {
            return Color.primary.opacity(0.1)
        }
        return Color.clear
    }
}
