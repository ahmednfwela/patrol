#include "patrol_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <UIAutomation.h>
#include <comdef.h>
#include <windows.h>

#include <chrono>
#include <memory>
#include <string>
#include <thread>
#include <vector>

namespace patrol {

static std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) return L"";
  int len = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, nullptr, 0);
  std::wstring wide(len - 1, 0);
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, &wide[0], len);
  return wide;
}

static std::string WideToUtf8(const std::wstring& wide) {
  if (wide.empty()) return "";
  int len = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), -1, nullptr, 0,
                                nullptr, nullptr);
  std::string utf8(len - 1, 0);
  WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), -1, &utf8[0], len, nullptr,
                      nullptr);
  return utf8;
}

static const std::string* GetOptionalString(
    const flutter::EncodableMap& args, const std::string& key) {
  auto it = args.find(flutter::EncodableValue(key));
  if (it != args.end() && std::holds_alternative<std::string>(it->second)) {
    return &std::get<std::string>(it->second);
  }
  return nullptr;
}

static int GetOptionalInt(const flutter::EncodableMap& args,
                          const std::string& key, int defaultVal) {
  auto it = args.find(flutter::EncodableValue(key));
  if (it != args.end() && std::holds_alternative<int32_t>(it->second)) {
    return std::get<int32_t>(it->second);
  }
  return defaultVal;
}

static double GetOptionalDouble(const flutter::EncodableMap& args,
                                const std::string& key, double defaultVal) {
  auto it = args.find(flutter::EncodableValue(key));
  if (it != args.end()) {
    if (std::holds_alternative<double>(it->second))
      return std::get<double>(it->second);
    if (std::holds_alternative<int32_t>(it->second))
      return static_cast<double>(std::get<int32_t>(it->second));
  }
  return defaultVal;
}

static bool GetOptionalBool(const flutter::EncodableMap& args,
                            const std::string& key, bool defaultVal) {
  auto it = args.find(flutter::EncodableValue(key));
  if (it != args.end() && std::holds_alternative<bool>(it->second)) {
    return std::get<bool>(it->second);
  }
  return defaultVal;
}

// static
void PatrolPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "pl.leancode.patrol/desktopAutomator",
      &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<PatrolPlugin>();
  channel->SetMethodCallHandler(
      [plugin_ptr = plugin.get()](const auto& call, auto result) {
        plugin_ptr->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

PatrolPlugin::PatrolPlugin() {}

PatrolPlugin::~PatrolPlugin() {
  if (automation_) {
    automation_->Release();
    automation_ = nullptr;
  }
  CoUninitialize();
}

bool PatrolPlugin::EnsureInitialized() {
  if (initialized_) return true;

  HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  if (FAILED(hr) && hr != RPC_E_CHANGED_MODE) return false;

  hr = CoCreateInstance(__uuidof(CUIAutomation), nullptr, CLSCTX_INPROC_SERVER,
                        __uuidof(IUIAutomation),
                        reinterpret_cast<void**>(&automation_));
  if (FAILED(hr) || !automation_) return false;

  initialized_ = true;
  return true;
}

IUIAutomationElement* PatrolPlugin::FindElementByProperties(
    const std::string* name, const std::string* className,
    const std::string* automationId, int timeoutMs) {
  if (!automation_) return nullptr;

  IUIAutomationElement* root = nullptr;
  automation_->GetRootElement(&root);
  if (!root) return nullptr;

  IUIAutomationCondition* condition = nullptr;

  if (name) {
    VARIANT val;
    val.vt = VT_BSTR;
    val.bstrVal = SysAllocString(Utf8ToWide(*name).c_str());
    automation_->CreatePropertyCondition(UIA_NamePropertyId, val, &condition);
    SysFreeString(val.bstrVal);
  } else if (automationId) {
    VARIANT val;
    val.vt = VT_BSTR;
    val.bstrVal = SysAllocString(Utf8ToWide(*automationId).c_str());
    automation_->CreatePropertyCondition(UIA_AutomationIdPropertyId, val,
                                         &condition);
    SysFreeString(val.bstrVal);
  } else if (className) {
    VARIANT val;
    val.vt = VT_BSTR;
    val.bstrVal = SysAllocString(Utf8ToWide(*className).c_str());
    automation_->CreatePropertyCondition(UIA_ClassNamePropertyId, val,
                                         &condition);
    SysFreeString(val.bstrVal);
  } else {
    root->Release();
    return nullptr;
  }

  if (!condition) {
    root->Release();
    return nullptr;
  }

  auto deadline = std::chrono::steady_clock::now() +
                  std::chrono::milliseconds(timeoutMs);

  IUIAutomationElement* found = nullptr;
  while (std::chrono::steady_clock::now() < deadline) {
    HRESULT hr =
        root->FindFirst(TreeScope_Subtree, condition, &found);
    if (SUCCEEDED(hr) && found) break;
    std::this_thread::sleep_for(std::chrono::milliseconds(200));
  }

  condition->Release();
  root->Release();
  return found;
}

void PatrolPlugin::ClickElement(IUIAutomationElement* element) {
  if (!element) return;

  // Try InvokePattern first
  IUIAutomationInvokePattern* invoke = nullptr;
  element->GetCurrentPatternAs(UIA_InvokePatternId,
                                __uuidof(IUIAutomationInvokePattern),
                                reinterpret_cast<void**>(&invoke));
  if (invoke) {
    invoke->Invoke();
    invoke->Release();
    return;
  }

  // Try TogglePattern
  IUIAutomationTogglePattern* toggle = nullptr;
  element->GetCurrentPatternAs(UIA_TogglePatternId,
                                __uuidof(IUIAutomationTogglePattern),
                                reinterpret_cast<void**>(&toggle));
  if (toggle) {
    toggle->Toggle();
    toggle->Release();
    return;
  }

  // Fall back to coordinate click
  RECT rect;
  HRESULT hr = element->get_CurrentBoundingRectangle(&rect);
  if (SUCCEEDED(hr)) {
    double cx = (rect.left + rect.right) / 2.0;
    double cy = (rect.top + rect.bottom) / 2.0;
    ClickAt(cx, cy);
  }
}

void PatrolPlugin::ClickAt(double x, double y) {
  double screenW = GetSystemMetrics(SM_CXSCREEN);
  double screenH = GetSystemMetrics(SM_CYSCREEN);
  LONG normX = static_cast<LONG>(x / screenW * 65535.0);
  LONG normY = static_cast<LONG>(y / screenH * 65535.0);

  INPUT inputs[3] = {};
  // Move
  inputs[0].type = INPUT_MOUSE;
  inputs[0].mi.dx = normX;
  inputs[0].mi.dy = normY;
  inputs[0].mi.dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE;
  // Down
  inputs[1].type = INPUT_MOUSE;
  inputs[1].mi.dwFlags = MOUSEEVENTF_LEFTDOWN;
  // Up
  inputs[2].type = INPUT_MOUSE;
  inputs[2].mi.dwFlags = MOUSEEVENTF_LEFTUP;

  SendInput(3, inputs, sizeof(INPUT));
}

void PatrolPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto& method = call.method_name();

  if (method == "initialize") {
    if (EnsureInitialized()) {
      result->Success();
    } else {
      result->Error("UIA_INIT_FAILED", "Failed to initialize UI Automation");
    }
    return;
  }

  if (!EnsureInitialized()) {
    result->Error("UIA_NOT_INIT", "UI Automation not initialized");
    return;
  }

  const auto* args_ptr = std::get_if<flutter::EncodableMap>(call.arguments());
  if (!args_ptr) {
    result->Error("INVALID_ARGS", "Expected map arguments");
    return;
  }
  const auto& args = *args_ptr;

  if (method == "tap") {
    auto* name = GetOptionalString(args, "name");
    auto* className = GetOptionalString(args, "className");
    auto* automationId = GetOptionalString(args, "automationId");
    int timeout = GetOptionalInt(args, "timeoutMs", 10000);

    auto* el = FindElementByProperties(name, className, automationId, timeout);
    if (el) {
      ClickElement(el);
      el->Release();
      result->Success();
    } else {
      result->Error("ELEMENT_NOT_FOUND", "No element matching criteria");
    }
  } else if (method == "tapAt") {
    double x = GetOptionalDouble(args, "x", 0);
    double y = GetOptionalDouble(args, "y", 0);
    ClickAt(x, y);
    result->Success();
  } else if (method == "doubleTap") {
    auto* name = GetOptionalString(args, "name");
    auto* className = GetOptionalString(args, "className");
    auto* automationId = GetOptionalString(args, "automationId");
    int timeout = GetOptionalInt(args, "timeoutMs", 10000);

    auto* el = FindElementByProperties(name, className, automationId, timeout);
    if (el) {
      ClickElement(el);
      std::this_thread::sleep_for(std::chrono::milliseconds(100));
      ClickElement(el);
      el->Release();
      result->Success();
    } else {
      result->Error("ELEMENT_NOT_FOUND", "No element matching criteria");
    }
  } else if (method == "enterText") {
    auto* name = GetOptionalString(args, "name");
    auto* className = GetOptionalString(args, "className");
    auto* text = GetOptionalString(args, "text");
    int timeout = GetOptionalInt(args, "timeoutMs", 10000);

    if (!text) {
      result->Error("MISSING_TEXT", "text argument required");
      return;
    }

    auto* el = FindElementByProperties(name, className, nullptr, timeout);
    if (el) {
      // Try ValuePattern
      IUIAutomationValuePattern* valPattern = nullptr;
      el->GetCurrentPatternAs(UIA_ValuePatternId,
                               __uuidof(IUIAutomationValuePattern),
                               reinterpret_cast<void**>(&valPattern));
      if (valPattern) {
        BSTR bstr = SysAllocString(Utf8ToWide(*text).c_str());
        valPattern->SetValue(bstr);
        SysFreeString(bstr);
        valPattern->Release();
        el->Release();
        result->Success();
      } else {
        // Fall back: focus element and type via keyboard
        el->SetFocus();
        std::this_thread::sleep_for(std::chrono::milliseconds(100));

        std::wstring wtext = Utf8ToWide(*text);
        std::vector<INPUT> inputs;
        for (wchar_t ch : wtext) {
          INPUT down = {};
          down.type = INPUT_KEYBOARD;
          down.ki.wScan = ch;
          down.ki.dwFlags = KEYEVENTF_UNICODE;
          inputs.push_back(down);

          INPUT up = {};
          up.type = INPUT_KEYBOARD;
          up.ki.wScan = ch;
          up.ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP;
          inputs.push_back(up);
        }
        if (!inputs.empty()) {
          SendInput(static_cast<UINT>(inputs.size()), inputs.data(),
                    sizeof(INPUT));
        }
        el->Release();
        result->Success();
      }
    } else {
      result->Error("ELEMENT_NOT_FOUND", "No element matching criteria");
    }
  } else if (method == "isElementVisible") {
    auto* name = GetOptionalString(args, "name");
    auto* className = GetOptionalString(args, "className");
    auto* automationId = GetOptionalString(args, "automationId");

    auto* el = FindElementByProperties(name, className, automationId, 500);
    bool visible = el != nullptr;
    if (el) el->Release();
    result->Success(flutter::EncodableValue(visible));
  } else if (method == "findElement") {
    auto* name = GetOptionalString(args, "name");
    auto* className = GetOptionalString(args, "className");
    auto* automationId = GetOptionalString(args, "automationId");
    int timeout = GetOptionalInt(args, "timeoutMs", 10000);

    auto* el = FindElementByProperties(name, className, automationId, timeout);
    if (el) {
      flutter::EncodableMap map;
      BSTR bstrName;
      if (SUCCEEDED(el->get_CurrentName(&bstrName)) && bstrName) {
        map[flutter::EncodableValue("name")] =
            flutter::EncodableValue(WideToUtf8(bstrName));
        SysFreeString(bstrName);
      }
      BSTR bstrClass;
      if (SUCCEEDED(el->get_CurrentClassName(&bstrClass)) && bstrClass) {
        map[flutter::EncodableValue("className")] =
            flutter::EncodableValue(WideToUtf8(bstrClass));
        SysFreeString(bstrClass);
      }
      RECT rect;
      if (SUCCEEDED(el->get_CurrentBoundingRectangle(&rect))) {
        map[flutter::EncodableValue("x")] =
            flutter::EncodableValue(static_cast<double>(rect.left));
        map[flutter::EncodableValue("y")] =
            flutter::EncodableValue(static_cast<double>(rect.top));
        map[flutter::EncodableValue("width")] =
            flutter::EncodableValue(static_cast<double>(rect.right - rect.left));
        map[flutter::EncodableValue("height")] =
            flutter::EncodableValue(
                static_cast<double>(rect.bottom - rect.top));
      }
      el->Release();
      result->Success(flutter::EncodableValue(map));
    } else {
      result->Success();  // null
    }
  } else if (method == "pressKey") {
    int keyCode = GetOptionalInt(args, "keyCode", 0);
    bool shift = GetOptionalBool(args, "shift", false);
    bool ctrl = GetOptionalBool(args, "ctrl", false);
    bool alt = GetOptionalBool(args, "alt", false);

    std::vector<INPUT> inputs;

    auto addKey = [&](WORD vk, bool down) {
      INPUT inp = {};
      inp.type = INPUT_KEYBOARD;
      inp.ki.wVk = vk;
      if (!down) inp.ki.dwFlags = KEYEVENTF_KEYUP;
      inputs.push_back(inp);
    };

    if (ctrl) addKey(VK_CONTROL, true);
    if (shift) addKey(VK_SHIFT, true);
    if (alt) addKey(VK_MENU, true);
    addKey(static_cast<WORD>(keyCode), true);
    addKey(static_cast<WORD>(keyCode), false);
    if (alt) addKey(VK_MENU, false);
    if (shift) addKey(VK_SHIFT, false);
    if (ctrl) addKey(VK_CONTROL, false);

    SendInput(static_cast<UINT>(inputs.size()), inputs.data(), sizeof(INPUT));
    result->Success();
  } else {
    result->NotImplemented();
  }
}

}  // namespace patrol
