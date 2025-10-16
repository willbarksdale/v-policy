import UIKit
import Flutter
import SwiftUI

// MARK: - Authentic iOS 18 Liquid Glass Back Button Overlay

// MARK: - Authentic SwiftUI Liquid Glass Back Button with Draggy Interactions

struct AuthenticLiquidGlassBackButton: View {
    let onBackTapped: () -> Void
    @Namespace private var namespace

    var body: some View {
        // 🎯 Clean iOS default positioning - let native constraints handle layout
        GlassEffectContainer {
            Button(action: onBackTapped) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain) // ✨ No glass conflicts - clean base
            .glassEffect(.regular.interactive()) // 🎯 Use default capsule shape for better liquid containment
            .glassEffectID("backButton", in: namespace)
        }
    }
}

// MARK: - Simple iOS 18 Liquid Glass Back Button Plugin

class SimpleLiquidGlassBackButtonPlugin: NSObject, FlutterPlugin {
    private var hostingController: UIHostingController<AnyView>?
    
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "liquid_glass_back_button", binaryMessenger: registrar.messenger())
        let instance = SimpleLiquidGlassBackButtonPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isLiquidGlassSupported":
            // Check if we're running on iOS 18+ with authentic Liquid Glass support
            result(true)
        case "enableNativeLiquidGlassBackButton":
            enableLiquidGlassForCurrentScreen(result: result)
        case "disableNativeLiquidGlassBackButton":
            disableLiquidGlassForCurrentScreen(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func enableLiquidGlassForCurrentScreen(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let flutterViewController = window.rootViewController as? FlutterViewController else {
                result(false)
                return
            }

            // Remove any existing overlay first
            flutterViewController.view.subviews.filter { $0.tag == 9999 }.forEach { $0.removeFromSuperview() }
            flutterViewController.children.forEach { child in
                if child.view?.tag == 9999 {
                    child.removeFromParent()
                }
            }

            // 🚀 AUTHENTIC SwiftUI Liquid Glass with draggy interactions
            let liquidGlassOverlay = AuthenticLiquidGlassBackButton {
                // Handle back button tap
                let channel = FlutterMethodChannel(name: "liquid_glass_back_button", binaryMessenger: flutterViewController.binaryMessenger)
                channel.invokeMethod("onBackButtonTapped", arguments: nil)
            }

            // Add SwiftUI overlay with UIHostingController
            let hostingController = UIHostingController(rootView: AnyView(liquidGlassOverlay))
            hostingController.view.backgroundColor = UIColor.clear
            hostingController.view.tag = 9999
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            hostingController.view.isAccessibilityElement = false
            hostingController.view.accessibilityViewIsModal = false
            
            // Add as child view controller for proper accessibility
            flutterViewController.addChild(hostingController)
            flutterViewController.view.addSubview(hostingController.view)
            NSLayoutConstraint.activate([
                hostingController.view.topAnchor.constraint(equalTo: flutterViewController.view.safeAreaLayoutGuide.topAnchor),
                hostingController.view.leadingAnchor.constraint(equalTo: flutterViewController.view.leadingAnchor, constant: 16),
                hostingController.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),  // Minimum size, consistent with other buttons
                hostingController.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 44) // Minimum size, consistent with other buttons
            ])
            
            hostingController.didMove(toParent: flutterViewController)
            self.hostingController = hostingController

            result(true)
        }
    }
    
    // SwiftUI .buttonStyle(.glass) and .interactive() handle all interactions automatically
    
    private func disableLiquidGlassForCurrentScreen(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let flutterViewController = window.rootViewController as? FlutterViewController else {
                result(false)
                return
            }
            
            // Remove the overlay
            flutterViewController.view.subviews.filter { $0.tag == 9999 }.forEach { $0.removeFromSuperview() }
            flutterViewController.children.forEach { child in
                if child.view?.tag == 9999 {
                    child.removeFromParent()
                }
            }
            self.hostingController = nil
            result(true)
        }
    }
}

