import UIKit
import Flutter
import SwiftUI

// MARK: - Authentic iOS 26 Liquid Glass Info Button Overlay

// MARK: - Authentic SwiftUI Liquid Glass Info Button with Draggy Interactions

@available(iOS 26.0, *)
struct AuthenticLiquidGlassInfoButton: View {
    let onInfoTapped: () -> Void
    @Namespace private var namespace

    var body: some View {
        // 🎯 Clean iOS default positioning - let native constraints handle layout
        GlassEffectContainer {
            Button(action: onInfoTapped) {
                Image(systemName: "info")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain) // ✨ No glass conflicts - clean base
            .glassEffect(.regular.interactive()) // 🎯 Use default capsule shape for better liquid containment
            .glassEffectID("infoButton", in: namespace)
        }
    }
}

// MARK: - Simple iOS 26 Liquid Glass Info Button Plugin

@available(iOS 16.0, *)
class SimpleLiquidGlassInfoButtonPlugin: NSObject, FlutterPlugin {
    private var hostingController: UIHostingController<AnyView>?
    
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "liquid_glass_info_button", binaryMessenger: registrar.messenger())
        let instance = SimpleLiquidGlassInfoButtonPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isLiquidGlassSupported":
            // Check if we're running on iOS 26+ with authentic Liquid Glass support
            if #available(iOS 26.0, *) {
                result(true)
            } else {
                result(false)
            }
        case "enableNativeLiquidGlassInfoButton":
            if #available(iOS 26.0, *) {
                enableLiquidGlassForCurrentScreen(result: result)
            } else {
                result(false)
            }
        case "disableNativeLiquidGlassInfoButton":
            disableLiquidGlassForCurrentScreen(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    @available(iOS 26.0, *)
    private func enableLiquidGlassForCurrentScreen(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let flutterViewController = window.rootViewController as? FlutterViewController else {
                result(false)
                return
            }

            // Remove any existing overlay first
            flutterViewController.view.subviews.filter { $0.tag == 9997 }.forEach { $0.removeFromSuperview() }
            flutterViewController.children.forEach { child in
                if child.view?.tag == 9997 {
                    child.removeFromParent()
                }
            }

            // 🚀 AUTHENTIC SwiftUI Liquid Glass with draggy interactions
            let liquidGlassOverlay = AuthenticLiquidGlassInfoButton {
                // Handle info button tap
                let channel = FlutterMethodChannel(name: "liquid_glass_info_button", binaryMessenger: flutterViewController.binaryMessenger)
                channel.invokeMethod("onInfoButtonTapped", arguments: nil)
            }

            // Add SwiftUI overlay with UIHostingController
            let hostingController = UIHostingController(rootView: AnyView(liquidGlassOverlay))
            hostingController.view.backgroundColor = UIColor.clear
            hostingController.view.tag = 9997
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            hostingController.view.isAccessibilityElement = false
            hostingController.view.accessibilityViewIsModal = false
            
            // Add as child view controller for proper accessibility
            flutterViewController.addChild(hostingController)
            flutterViewController.view.addSubview(hostingController.view)
            NSLayoutConstraint.activate([
                hostingController.view.bottomAnchor.constraint(equalTo: flutterViewController.view.safeAreaLayoutGuide.bottomAnchor, constant: -60),
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
            flutterViewController.view.subviews.filter { $0.tag == 9997 }.forEach { $0.removeFromSuperview() }
            flutterViewController.children.forEach { child in
                if child.view?.tag == 9997 {
                    child.removeFromParent()
                }
            }
            self.hostingController = nil
            result(true)
        }
    }
}

