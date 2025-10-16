import SwiftUI

// MARK: - Shared Glass Effect Container
// This is a simple container that wraps content for liquid glass effects

struct GlassEffectContainer<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
    }
}

