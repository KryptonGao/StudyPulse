//
//  AIModeHeader.swift
//  StudyPulse
//
//  The top bar of the AI Mode main panel, built from the system navigation bar:
//  a drawer button, the title (or wordmark) and one trailing action. The system
//  draws the bar (Liquid Glass buttons on iOS 26) and its scroll-edge effect.
//

import SwiftUI

enum AIModeBarTrailing {
    case none
    case newChat
    case back
}

private struct AIModeToolbar: ViewModifier {
    let title: String
    let showsWordmark: Bool
    let trailing: AIModeBarTrailing
    let onDrawer: () -> Void
    let onTrailing: () -> Void

    @Environment(\.aiTheme) private var theme

    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onDrawer) {
                        Image(systemName: "line.3.horizontal")
                    }
                    .accessibilityLabel("aiMode.drawer.open".localized())
                }
                ToolbarItem(placement: .principal) {
                    if showsWordmark {
                        Label {
                            Text("aiMode.title".localized())
                                .font(.title3.weight(.semibold))
                        } icon: {
                            Image(systemName: "leaf.fill").foregroundStyle(theme.accent)
                        }
                        .labelStyle(.titleAndIcon)
                        .accessibilityElement(children: .combine)
                    } else {
                        Text(title)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    switch trailing {
                    case .newChat:
                        Button(action: onTrailing) { Image(systemName: "square.and.pencil") }
                            .accessibilityLabel("aiMode.sidebar.newChat".localized())
                    case .back:
                        Button(action: onTrailing) { Image(systemName: "bubble.left") }
                            .accessibilityLabel("aiMode.data.backToChat".localized())
                    case .none:
                        EmptyView()
                    }
                }
            }
            .foregroundStyle(theme.ink)
    }
}

extension View {
    /// Puts the AI Mode drawer button, title and trailing action in the system navigation bar.
    func aiModeToolbar(
        title: String,
        showsWordmark: Bool = false,
        trailing: AIModeBarTrailing = .newChat,
        onDrawer: @escaping () -> Void,
        onTrailing: @escaping () -> Void = {}
    ) -> some View {
        modifier(AIModeToolbar(
            title: title,
            showsWordmark: showsWordmark,
            trailing: trailing,
            onDrawer: onDrawer,
            onTrailing: onTrailing
        ))
    }
}
