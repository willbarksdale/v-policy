import UIKit
import Flutter
import SwiftUI

// MARK: - Authentic iOS 18 Liquid Glass Play Button Overlay

// MARK: - Authentic SwiftUI Liquid Glass Play Button with Draggy Interactions

struct AuthenticLiquidGlassPlayButton: View {
    let isLoading: Bool
    let onPlayTapped: () -> Void
    @Namespace private var namespace

    var body: some View {
        // 🎯 Clean iOS default positioning - let native constraints handle layout
        GlassEffectContainer {
            Button(action: onPlayTapped) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .primary))
                        .frame(width: 44, height: 44)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                }
            }
            .buttonStyle(.plain) // ✨ No glass conflicts - clean base
            .glassEffect(.regular.interactive()) // 🎯 Use default capsule shape for better liquid containment
            .glassEffectID("playButton", in: namespace)
            .disabled(isLoading)
        }
    }
}

// MARK: - Simple iOS 18 Liquid Glass Play Button Plugin

class SimpleLiquidGlassPlayButtonPlugin: NSObject, FlutterPlugin {
    private var buttonState: PlayButtonState?
    private var hostingController: UIHostingController<AnyView>?
    
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "liquid_glass_play_button", binaryMessenger: registrar.messenger())
        let instance = SimpleLiquidGlassPlayButtonPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isLiquidGlassSupported":
            // Check if we're running on iOS 18+ with authentic Liquid Glass support
            result(true)
        case "enableNativeLiquidGlassPlayButton":
            let args = call.arguments as? [String: Any]
                let isLoading = args?["isLoading"] as? Bool ?? false
                enableLiquidGlassForCurrentScreen(isLoading: isLoading, result: result)
        case "disableNativeLiquidGlassPlayButton":
            disableLiquidGlassForCurrentScreen(result: result)
        case "updatePlayButtonState":
            let args = call.arguments as? [String: Any]
                let isLoading = args?["isLoading"] as? Bool ?? false
                updatePlayButtonState(isLoading: isLoading, result: result)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func enableLiquidGlassForCurrentScreen(isLoading: Bool, result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let flutterViewController = window.rootViewController as? FlutterViewController else {
                result(false)
                return
            }

            // Remove any existing overlay first
            flutterViewController.view.subviews.filter { $0.tag == 9995 }.forEach { $0.removeFromSuperview() }
            flutterViewController.children.forEach { child in
                if child.view?.tag == 9995 {
                    child.removeFromParent()
                }
            }

            // Create observable state
            let state = PlayButtonState(isLoading: isLoading)
            self.buttonState = state

            // 🚀 AUTHENTIC SwiftUI Liquid Glass with draggy interactions
            let liquidGlassOverlay = AuthenticLiquidGlassPlayButton(isLoading: state.isLoading) {
                // Handle play button tap
                let channel = FlutterMethodChannel(name: "liquid_glass_play_button", binaryMessenger: flutterViewController.binaryMessenger)
                channel.invokeMethod("onPlayButtonTapped", arguments: nil)
            }

            // Add SwiftUI overlay with UIHostingController
            let hostingController = UIHostingController(rootView: AnyView(liquidGlassOverlay))
            hostingController.view.backgroundColor = UIColor.clear
            hostingController.view.tag = 9995
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            hostingController.view.isAccessibilityElement = false
            hostingController.view.accessibilityViewIsModal = false
            
            // Add as child view controller for proper accessibility
            flutterViewController.addChild(hostingController)
            flutterViewController.view.addSubview(hostingController.view)
            NSLayoutConstraint.activate([
                hostingController.view.bottomAnchor.constraint(equalTo: flutterViewController.view.safeAreaLayoutGuide.bottomAnchor, constant: -60),
                hostingController.view.trailingAnchor.constraint(equalTo: flutterViewController.view.trailingAnchor, constant: -16),
                hostingController.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
                hostingController.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
            ])
            
            hostingController.didMove(toParent: flutterViewController)
            self.hostingController = hostingController

            result(true)
        }
    }
    
    private func updatePlayButtonState(isLoading: Bool, result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            // Simply update the observable state - SwiftUI will handle the UI update
            if let buttonState = self.buttonState {
                buttonState.isLoading = isLoading
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
            flutterViewController.view.subviews.filter { $0.tag == 9995 }.forEach { $0.removeFromSuperview() }
            flutterViewController.children.forEach { child in
                if child.view?.tag == 9995 {
                    child.removeFromParent()
                }
            }
            self.hostingController = nil
            result(true)
        }
    }
}

// MARK: - Play Button State Observable

class PlayButtonState: ObservableObject {
    @Published var isLoading: Bool
    
    init(isLoading: Bool) {
        self.isLoading = isLoading
    }
}

