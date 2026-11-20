//
//  LinkDragAndDrop.swift
//  Reynard
//

import UIKit

/// Links and text, dragged out of Reynard and dropped into it, through the system's drag and drop.
///
/// A link leaves as a URL, with the page's title as its name, so that any app that takes links can take it.
/// What is dropped is a copy: the Human Interface Guidelines have a drag between apps always copy.
enum LinkDragAndDrop {
    /// The item for a link, for a drag interaction to begin with. Nothing to drag where there is no URL.
    static func dragItems(for urlString: String?, title: String?) -> [UIDragItem] {
        guard let urlString,
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            return []
        }
        
        let provider = NSItemProvider(object: url as NSURL)
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        provider.suggestedName = trimmedTitle.isEmpty ? url.host : trimmedTitle
        let item = UIDragItem(itemProvider: provider)
        item.localObject = url
        return [item]
    }
}

/// Takes links and text dropped on a view.
///
/// Links are handed over as links. Text is handed over as it is, for the receiver to treat as an address or
/// as something to search for. A view that takes only links ignores a drag that carries only text.
final class LinkDropHandler: NSObject, UIDropInteractionDelegate {
    enum Content {
        case links([URL])
        case text(String)
    }
    
    private let acceptsText: Bool
    private let onHighlight: ((Bool) -> Void)?
    private let onDrop: (Content) -> Void
    
    /// - Parameters:
    ///   - acceptsText: Whether plain text is taken as well as links.
    ///   - onHighlight: Called as a drag that can be dropped here enters and leaves the view.
    init(
        acceptsText: Bool,
        onHighlight: ((Bool) -> Void)? = nil,
        onDrop: @escaping (Content) -> Void
    ) {
        self.acceptsText = acceptsText
        self.onHighlight = onHighlight
        self.onDrop = onDrop
    }
    
    /// Adds a drop interaction with this handler to `view`. The view keeps the handler alive.
    func install(on view: UIView) {
        view.addInteraction(UIDropInteraction(delegate: self))
        objc_setAssociatedObject(view, &LinkDropHandler.associationKey, self, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    
    private static var associationKey: UInt8 = 0
    
    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        return session.canLoadObjects(ofClass: NSURL.self)
        || (acceptsText && session.canLoadObjects(ofClass: NSString.self))
    }
    
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnter session: UIDropSession) {
        onHighlight?(true)
    }
    
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        return UIDropProposal(operation: .copy)
    }
    
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: UIDropSession) {
        onHighlight?(false)
    }
    
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: UIDropSession) {
        onHighlight?(false)
    }
    
    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        onHighlight?(false)
        if session.canLoadObjects(ofClass: NSURL.self) {
            session.loadObjects(ofClass: NSURL.self) { [onDrop] objects in
                let urls = objects.compactMap { $0 as? URL }.filter { url in
                    ["http", "https"].contains(url.scheme?.lowercased() ?? "")
                }
                if !urls.isEmpty {
                    onDrop(.links(urls))
                }
            }
            return
        }
        
        guard acceptsText else {
            return
        }
        session.loadObjects(ofClass: NSString.self) { [onDrop] objects in
            let text = objects
                .compactMap { $0 as? String }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                onDrop(.text(text))
            }
        }
    }
}
