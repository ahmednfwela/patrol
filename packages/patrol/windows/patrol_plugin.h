#ifndef FLUTTER_PLUGIN_PATROL_PLUGIN_INTERNAL_H_
#define FLUTTER_PLUGIN_PATROL_PLUGIN_INTERNAL_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

struct IUIAutomation;
struct IUIAutomationElement;

namespace patrol {

class PatrolPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  PatrolPlugin();
  virtual ~PatrolPlugin();

  PatrolPlugin(const PatrolPlugin&) = delete;
  PatrolPlugin& operator=(const PatrolPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  bool EnsureInitialized();
  IUIAutomationElement* FindElementByProperties(
      const std::string* name,
      const std::string* className,
      const std::string* automationId,
      int timeoutMs);
  void ClickElement(IUIAutomationElement* element);
  void ClickAt(double x, double y);

  IUIAutomation* automation_ = nullptr;
  bool initialized_ = false;
};

}  // namespace patrol

#endif  // FLUTTER_PLUGIN_PATROL_PLUGIN_INTERNAL_H_
