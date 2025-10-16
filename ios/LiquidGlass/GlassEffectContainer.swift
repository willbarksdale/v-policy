import SwiftUI

// MARK: - Shared Glass Effect Container
// This is a simple container that wraps content for liquid glass effects

@available(iOS 26.0, *)
struct GlassEffectContainer<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
    }
}

