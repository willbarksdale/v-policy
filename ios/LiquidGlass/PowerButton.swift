import UIKit
import Flutter
import SwiftUI

// MARK: - Authentic iOS 18 Liquid Glass Power Button Overlay

// MARK: - Power Button State Observable

class PowerButtonState: ObservableObject {
    @Published var isConnected: Bool
    
    init(isConnected: Bool) {
        self.isConnected = isConnected
    }
}

// MARK: - Authentic SwiftUI Liquid Glass Power Button with Draggy Interactions

struct AuthenticLiquidGlassPowerButton: View {
    @ObservedObject var state: PowerButtonState
    let onPowerTapped: () -> Void
    @Namespace private var namespace

    var body: some View {
        // 🎯 Clean iOS default positioning - let native constraints handle layout
        GlassEffectContainer {
            Button(action: onPowerTapped) {
                Image(systemName: "power")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(state.isConnected ? .blue : .primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain) // ✨ No glass conflicts - clean base
            .glassEffect(.regular.interactive()) // 🎯 Use default capsule shape for better liquid containment
            .glassEffectID("powerButton", in: namespace)
        }
    }
}

// MARK: - Simple iOS 18 Liquid Glass Power Button Plugin

class SimpleLiquidGlassPowerButtonPlugin: NSObject, FlutterPlugin {
    private var buttonState: PowerButtonState?
    private var hostingController: UIHostingController<AnyView>?
    
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "liquid_glass_power_button", binaryMessenger: registrar.messenger())
        let instance = SimpleLiquidGlassPowerButtonPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isLiquidGlassSupported":
            // iOS 18+ always supports Liquid Glass
            result(true)
        case "enableNativeLiquidGlassPowerButton":
            let args = call.arguments as? [String: Any]
            let isConnected = args?["isConnected"] as? Bool ?? false
            enableLiquidGlassForCurrentScreen(isConnected: isConnected, result: result)
        case "disableNativeLiquidGlassPowerButton":
            disableLiquidGlassForCurrentScreen(result: result)
        case "updatePowerButtonState":
            let args = call.arguments as? [String: Any]
            let isConnected = args?["isConnected"] as? Bool ?? false
            updatePowerButtonState(isConnected: isConnected, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func enableLiquidGlassForCurrentScreen(isConnected: Bool, result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let flutterViewController = window.rootViewController as? FlutterViewController else {
                result(false)
                return
            }

            // Remove any existing overlay first
            flutterViewController.view.subviews.filter { $0.tag == 9998 }.forEach { $0.removeFromSuperview() }
            flutterViewController.children.forEach { child in
                if child.view?.tag == 9998 {
                    child.removeFromParent()
                }
            }

            // Create observable state
            let state = PowerButtonState(isConnected: isConnected)
            self.buttonState = state

            // 🚀 AUTHENTIC SwiftUI Liquid Glass with draggy interactions
            let liquidGlassOverlay = AuthenticLiquidGlassPowerButton(state: state) {
                // Handle power button tap
                let channel = FlutterMethodChannel(name: "liquid_glass_power_button", binaryMessenger: flutterViewController.binaryMessenger)
                channel.invokeMethod("onPowerButtonTapped", arguments: nil)
            }

            // Add SwiftUI overlay with UIHostingController
            let hostingController = UIHostingController(rootView: AnyView(liquidGlassOverlay))
            hostingController.view.backgroundColor = UIColor.clear
            hostingController.view.tag = 9998
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            hostingController.view.isAccessibilityElement = false
            hostingController.view.accessibilityViewIsModal = false
            
            // Add as child view controller for proper accessibility
            flutterViewController.addChild(hostingController)
            flutterViewController.view.addSubview(hostingController.view)
            NSLayoutConstraint.activate([
                hostingController.view.bottomAnchor.constraint(equalTo: flutterViewController.view.safeAreaLayoutGuide.bottomAnchor, constant: -60),
                hostingController.view.trailingAnchor.constraint(equalTo: flutterViewController.view.trailingAnchor, constant: -16),
                hostingController.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),  // Minimum size, consistent with other buttons
                hostingController.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 44) // Minimum size, consistent with other buttons
            ])
            
            hostingController.didMove(toParent: flutterViewController)
            self.hostingController = hostingController

            result(true)
        }
    }
    
    private func updatePowerButtonState(isConnected: Bool, result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            // Simply update the observable state - SwiftUI will handle the UI update
            if let buttonState = self.buttonState {
                buttonState.isConnected = isConnected
                result(true)
            } else {
                result(false)
            }
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
            flutterViewController.view.subviews.filter { $0.tag == 9998 }.forEach { $0.removeFromSuperview() }
            flutterViewController.children.forEach { child in
                if child.view?.tag == 9998 {
                    child.removeFromParent()
                }
            }
            self.hostingController = nil
            result(true)
        }
    }
}

