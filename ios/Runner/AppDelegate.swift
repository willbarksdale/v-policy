import Flutter
import UIKit

@main
@available(iOS 26.0, *)
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Register Liquid Glass power button plugin
    SimpleLiquidGlassPowerButtonPlugin.register(with: self.registrar(forPlugin: "SimpleLiquidGlassPowerButtonPlugin")!)
    
    // Register Liquid Glass info button plugin
    SimpleLiquidGlassInfoButtonPlugin.register(with: self.registrar(forPlugin: "SimpleLiquidGlassInfoButtonPlugin")!)
    
    // Register Liquid Glass back button plugin
    SimpleLiquidGlassBackButtonPlugin.register(with: self.registrar(forPlugin: "SimpleLiquidGlassBackButtonPlugin")!)
    
    // Register Liquid Glass play button plugin
    SimpleLiquidGlassPlayButtonPlugin.register(with: self.registrar(forPlugin: "SimpleLiquidGlassPlayButtonPlugin")!)
    
    // Register Liquid Glass history button plugin
    SimpleLiquidGlassHistoryButtonPlugin.register(with: self.registrar(forPlugin: "SimpleLiquidGlassHistoryButtonPlugin")!)
    
    // Register Liquid Glass terminal input plugin
    LiquidGlassTerminalInputPlugin.register(with: self.registrar(forPlugin: "LiquidGlassTerminalInputPlugin")!)
    
    // Register Liquid Glass terminal tabs plugin
    LiquidGlassTerminalTabsPlugin.register(with: self.registrar(forPlugin: "LiquidGlassTerminalTabsPlugin")!)
    
    // Register Liquid Glass URL bar plugin
    SimpleLiquidGlassURLBarPlugin.register(with: self.registrar(forPlugin: "SimpleLiquidGlassURLBarPlugin")!)
    
    // Register Liquid Glass toast plugin
    LiquidGlassToastPlugin.register(with: self.registrar(forPlugin: "LiquidGlassToastPlugin")!)
    
    // Register Shortcut Alerts plugin
    ShortcutAlertsPlugin.register(with: self.registrar(forPlugin: "ShortcutAlertsPlugin")!)
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
