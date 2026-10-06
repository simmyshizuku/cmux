import AppKit
import CmuxAppKitSupportUI
import UniformTypeIdentifiers

final class FileExplorerCellView: NSTableCellView {
    private let iconView = CmuxResolvedIconImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let loadingIndicator = NSProgressIndicator()
    private var trackingArea: NSTrackingArea?
    private var thumbnailTask: Task<Void, Never>?
    private var displayedThumbnail: NSImage?
    var onHover: ((Bool) -> Void)?
    private var nameLabelTrailingToLoadingConstraint: NSLayoutConstraint!
    private var nameLabelTrailingToContainerConstraint: NSLayoutConstraint!

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var iconWidthConstraint: NSLayoutConstraint!
    private var iconHeightConstraint: NSLayoutConstraint!
    private var iconToTextConstraint: NSLayoutConstraint!
    private var loadingWidthConstraint: NSLayoutConstraint!

    private func setupViews() {
        iconView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.maximumNumberOfLines = 1

        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.style = .spinning
        loadingIndicator.controlSize = .small
        loadingIndicator.isHidden = true
        loadingIndicator.setAccessibilityIdentifier("FileExplorerLoadingIndicator")

        addSubview(iconView)
        addSubview(nameLabel)
        addSubview(loadingIndicator)

        iconWidthConstraint = iconView.widthAnchor.constraint(equalToConstant: 16)
        iconHeightConstraint = iconView.heightAnchor.constraint(equalToConstant: 16)
        iconToTextConstraint = nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 4)
        loadingWidthConstraint = loadingIndicator.widthAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconWidthConstraint,
            iconHeightConstraint,

            iconToTextConstraint,
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            loadingIndicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            loadingIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            loadingWidthConstraint,
            loadingIndicator.heightAnchor.constraint(equalToConstant: 12),
        ])

        nameLabelTrailingToLoadingConstraint = nameLabel.trailingAnchor.constraint(
            equalTo: loadingIndicator.leadingAnchor,
            constant: -2
        )
        nameLabelTrailingToContainerConstraint = nameLabel.trailingAnchor.constraint(
            equalTo: trailingAnchor,
            constant: -2
        )
        NSLayoutConstraint.activate([
            nameLabelTrailingToLoadingConstraint,
            nameLabelTrailingToContainerConstraint
        ])
        nameLabelTrailingToLoadingConstraint.isActive = false
    }

    /// - Parameter thumbnails: When given, an image file shows its thumbnail in
    ///   place of the generic icon. Pass `nil` for files that are not on this Mac.
    func configure(
        with node: FileExplorerNode,
        gitStatus: GitFileStatus? = nil,
        thumbnails: FileExplorerThumbnailCache? = nil
    ) {
        assert(Thread.isMainThread, "AppKit image updates must run on the main thread")
        let style = FileExplorerStyle.current
        nameLabel.stringValue = node.name
        nameLabel.font = style.nameFont
        iconWidthConstraint.constant = style.iconSize
        iconHeightConstraint.constant = style.iconSize
        iconToTextConstraint.constant = style.iconToTextSpacing

        thumbnailTask?.cancel()
        thumbnailTask = nil
        displayedThumbnail = nil
        let iconSize = NSSize(width: style.iconSize, height: style.iconSize)
        let showsThumbnail = thumbnails != nil
            && !node.isDirectory
            && FileExplorerThumbnailCache.isThumbnailable(fileName: node.name)
        if showsThumbnail, let cached = thumbnails?.cachedThumbnail(forPath: node.path) {
            showThumbnail(cached, size: iconSize)
        } else {
            iconView.apply(Self.iconRequest(for: node, style: style, size: iconSize))
        }
        if showsThumbnail, let thumbnails {
            let path = node.path
            let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
            thumbnailTask = Task { [weak self] in
                let image = await thumbnails.thumbnail(forPath: path, pointSize: iconSize.width, scale: scale)
                guard !Task.isCancelled, let self, let image else { return }
                self.showThumbnail(image, size: iconSize)
            }
        }

        if node.isLoading {
            loadingWidthConstraint.constant = 12
            loadingIndicator.isHidden = false
            loadingIndicator.startAnimation(nil)
            nameLabelTrailingToLoadingConstraint.isActive = true
            nameLabelTrailingToContainerConstraint.isActive = false
        } else {
            loadingWidthConstraint.constant = 0
            loadingIndicator.isHidden = true
            loadingIndicator.stopAnimation(nil)
            nameLabelTrailingToLoadingConstraint.isActive = false
            nameLabelTrailingToContainerConstraint.isActive = true
        }

        if let error = node.error {
            nameLabel.textColor = .systemRed
            nameLabel.toolTip = error
        } else if let gitStatus {
            nameLabel.textColor = style.gitColor(for: gitStatus)
            nameLabel.toolTip = node.path
        } else {
            nameLabel.textColor = .labelColor
            nameLabel.toolTip = node.path
        }
    }

    private func showThumbnail(_ image: NSImage, size: NSSize) {
        guard displayedThumbnail !== image else { return }
        displayedThumbnail = image
        iconView.apply(CmuxResolvedIconRequest(source: .image(image), size: size))
    }

    private static func iconRequest(
        for node: FileExplorerNode,
        style: FileExplorerStyle,
        size: NSSize
    ) -> CmuxResolvedIconRequest {
        if style == .finder {
            // Native Finder icon pixels miss 3:1 in light mode; use their masks with the dynamic palette tint.
            if node.isDirectory {
                return CmuxResolvedIconRequest(
                    source: .image(NSWorkspace.shared.icon(for: .folder)),
                    size: size,
                    tintColor: style.folderIconTint
                )
            }
            let pathExtension = (node.name as NSString).pathExtension
            return CmuxResolvedIconRequest(
                source: .image(NSWorkspace.shared.icon(for: UTType(filenameExtension: pathExtension) ?? .data)),
                size: size,
                tintColor: style.fileIconTint
            )
        }
        if node.isDirectory {
            return CmuxResolvedIconRequest(
                source: .systemSymbol(name: "folder.fill", accessibilityDescription: nil),
                size: size,
                tintColor: style.folderIconTint,
                symbolWeight: style.iconWeight
            )
        }
        return CmuxResolvedIconRequest(
            source: .systemSymbol(name: "doc", accessibilityDescription: nil),
            size: size,
            tintColor: style.fileIconTint,
            symbolWeight: style.iconWeight
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }
}
