import UIKit
import Flutter
import SwiftUI

// MARK: - iOS 26 Liquid Glass Bottom Navigation for V-Policy

@available(iOS 16.0, *)
class VPolicyLiquidGlassNavPlugin: NSObject, FlutterPlugin {
    private var tabBarOverlay: VPolicyNativeTabBar?
    private weak var registrar: FlutterPluginRegistrar?
    
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "v_policy_liquid_glass_nav", binaryMessenger: registrar.messenger())
        let instance = VPolicyLiquidGlassNavPlugin()
        instance.registrar = registrar
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isLiquidGlassSupported":
            if #available(iOS 26.0, *) {
                result(true)
            } else {
                result(false)
            }
        case "showLiquidGlassNav":
            if #available(iOS 26.0, *) {
                showLiquidGlassNav(result: result)
            } else {
                result(false)
            }
        case "hideLiquidGlassNav":
            hideLiquidGlassNav(result: result)
        case "setSelectedTab":
            if let index = call.arguments as? Int {
                setSelectedTab(index: index, result: result)
            } else {
                result(false)
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    @available(iOS 26.0, *)
    private func showLiquidGlassNav(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let flutterViewController = window.rootViewController as? FlutterViewController else {
                result(false)
                return
            }
            
            // Remove any existing overlay
            flutterViewController.view.subviews.filter { $0.tag == 8888 }.forEach { $0.removeFromSuperview() }
            
            // Create liquid glass tab bar
            let tabBarOverlay = VPolicyNativeTabBar(handler: self)
            tabBarOverlay.tag = 8888
            tabBarOverlay.translatesAutoresizingMaskIntoConstraints = false
            tabBarOverlay.isAccessibilityElement = false
            tabBarOverlay.accessibilityViewIsModal = false
            
            flutterViewController.view.addSubview(tabBarOverlay)
            
            NSLayoutConstraint.activate([
                tabBarOverlay.leadingAnchor.constraint(equalTo: flutterViewController.view.leadingAnchor),
                tabBarOverlay.trailingAnchor.constraint(equalTo: flutterViewController.view.trailingAnchor),
                tabBarOverlay.bottomAnchor.constraint(equalTo: flutterViewController.view.bottomAnchor),
                tabBarOverlay.heightAnchor.constraint(equalToConstant: 75 + window.safeAreaInsets.bottom)
            ])
            
            self.tabBarOverlay = tabBarOverlay
            print("✅ V-Policy Liquid Glass navigation created")
            result(true)
        }
    }
    
    private func hideLiquidGlassNav(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            self.tabBarOverlay?.isHidden = true
            result(true)
        }
    }
    
    private func setSelectedTab(index: Int, result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            self.tabBarOverlay?.setSelectedTab(index: index)
            result(true)
        }
    }
    
    func handleNavigation(action: String) {
        guard let registrar = self.registrar else { return }
        
        DispatchQueue.main.async {
            let channel = FlutterMethodChannel(name: "v_policy_navigation", binaryMessenger: registrar.messenger())
            channel.invokeMethod("navigate", arguments: action)
            print("📤 Navigation sent to Flutter: \(action)")
        }
    }
}

// MARK: - V-Policy Native Tab Bar

@available(iOS 16.0, *)
class VPolicyNativeTabBar: UIView {
    private weak var handler: VPolicyLiquidGlassNavPlugin?
    private var selectedIndex = 0
    private var tabBar: UITabBar?
    
    init(handler: VPolicyLiquidGlassNavPlugin) {
        self.handler = handler
        super.init(frame: .zero)
        setupTabBar()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupTabBar() {
        self.isUserInteractionEnabled = true
        
        let tabBar = UITabBar()
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        tabBar.tintColor = UIColor.systemBlue
        tabBar.unselectedItemTintColor = UIColor.white.withAlphaComponent(0.6)
        tabBar.isAccessibilityElement = false
        tabBar.shouldGroupAccessibilityChildren = true
        
        // iOS 26+ Liquid Glass styling
        if #available(iOS 26.0, *) {
            tabBar.isTranslucent = true
            let appearance = UITabBarAppearance()
            appearance.configureWithTransparentBackground()
            
            // Text styling with proper spacing
            let itemAppearance = appearance.stackedLayoutAppearance
            itemAppearance.normal.titleTextAttributes = [.font: UIFont.systemFont(ofSize: 11, weight: .medium)]
            itemAppearance.selected.titleTextAttributes = [.font: UIFont.systemFont(ofSize: 11, weight: .medium)]
            itemAppearance.normal.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: 4)
            itemAppearance.selected.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: 4)
            
            tabBar.standardAppearance = appearance
            tabBar.scrollEdgeAppearance = appearance
            print("✅ iOS 26+ Liquid Glass tab bar enabled")
        } else {
            tabBar.isTranslucent = false
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor.black
            
            // Text styling with proper spacing
            let itemAppearance = appearance.stackedLayoutAppearance
            itemAppearance.normal.titleTextAttributes = [.font: UIFont.systemFont(ofSize: 11, weight: .medium)]
            itemAppearance.selected.titleTextAttributes = [.font: UIFont.systemFont(ofSize: 11, weight: .medium)]
            itemAppearance.normal.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: 4)
            itemAppearance.selected.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: 4)
            
            tabBar.standardAppearance = appearance
            tabBar.scrollEdgeAppearance = appearance
            print("✅ iOS 18-25 solid tab bar enabled")
        }
        
        // Create 3 tab items: SSH, Terminal, Preview
        let sshItem = UITabBarItem(
            title: "SSH",
            image: UIImage(systemName: "antenna.radiowaves.left.and.right")?.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
            ),
            tag: 0
        )
        sshItem.accessibilityLabel = "SSH"
        sshItem.accessibilityHint = "Connect to your server and set project path"
        
        let terminalItem = UITabBarItem(
            title: "Terminal",
            image: UIImage(systemName: "apple.terminal")?.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
            ),
            tag: 1
        )
        terminalItem.accessibilityLabel = "Terminal"
        terminalItem.accessibilityHint = "Run commands and AI agents"
        
        let previewItem = UITabBarItem(
            title: "Preview",
            image: UIImage(systemName: "sparkles")?.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
            ),
            tag: 2
        )
        previewItem.accessibilityLabel = "Preview"
        previewItem.accessibilityHint = "Preview web applications"
        
        let items = [sshItem, terminalItem, previewItem]
        tabBar.items = items
        tabBar.selectedItem = items[0]
        tabBar.delegate = self
        
        addSubview(tabBar)
        
        NSLayoutConstraint.activate([
            tabBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            tabBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            tabBar.heightAnchor.constraint(equalToConstant: 80)
        ])
        
        self.tabBar = tabBar
        print("✅ V-Policy tab bar created with Liquid Glass styling and text labels")
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if UIAccessibility.isVoiceOverRunning {
            return super.hitTest(point, with: event)
        }
        
        if let tabBar = self.tabBar {
            let tabBarPoint = convert(point, to: tabBar)
            if tabBar.bounds.contains(tabBarPoint) {
                return super.hitTest(point, with: event)
            }
        }
        
        return nil
    }
    
    func setSelectedTab(index: Int) {
        guard let tabBar = self.tabBar,
              let items = tabBar.items,
              index < items.count else { return }
        
        tabBar.selectedItem = items[index]
        selectedIndex = index
    }
}

// MARK: - UITabBarDelegate

@available(iOS 16.0, *)
extension VPolicyNativeTabBar: UITabBarDelegate {
    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        let newIndex = item.tag
        
        if newIndex == selectedIndex {
            print("🎯 Same tab selected (\(newIndex)) - staying on current screen")
            return
        }
        
        let action = switch newIndex {
            case 0: "ssh"
            case 1: "terminal"
            case 2: "preview"
            default: "ssh"
        }
        
        print("🎯 Tab navigation: \(selectedIndex) → \(newIndex) (\(action))")
        selectedIndex = newIndex
        handler?.handleNavigation(action: action)
    }
}

