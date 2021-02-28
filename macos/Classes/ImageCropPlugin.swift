import Cocoa
import FlutterMacOS

public class ImageCropPlugin: NSObject, FlutterPlugin {
  var impl: ImageCrop!

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "plugins.lykhonis.com/image_crop", binaryMessenger: registrar.messenger)
    let instance = ImageCropPlugin()
    instance.impl = ImageCrop()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    impl.handle(call, result: result)
  }
}
