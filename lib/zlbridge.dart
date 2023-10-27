import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

typedef JSCompletionHandler = void Function(Object? obj, String? error);
typedef JSCallbackHandler = void Function(Object? obj, {bool end});
typedef JSRegisterHandler = void Function(
    Object? obj, JSCallbackHandler? callback);
typedef JSRegisterUndefinedHandler = void Function(
    String? name, Object? obj, JSCallbackHandler? callback);

class ZLBridge {
  static const String channelName = "ZLBridge";
  Map<String, JSRegisterHandler>? _registerHandlers;
  Map<String, JSCompletionHandler>? _callHandlers;
  JSRegisterUndefinedHandler? _undefinedHandler;
  Future<String> Function(String js)? _evaluateJavascriptFunc;
  ZLBridge() {
    _registerHandlers = <String, JSRegisterHandler>{};
    _callHandlers = <String, JSCompletionHandler>{};
  }
  void evaluateJavascriptAction(
      Future<String> Function(String js) evaluateJavascriptFunc) {
    _evaluateJavascriptFunc = evaluateJavascriptFunc;
  }

  void handleJSMessage(String message) {
    if (_evaluateJavascriptFunc == null) return;
    _ZLMsgBody msgBody = _ZLMsgBody.initWithMap(message);
    String name = msgBody.name!;
    String callID = msgBody.callID ?? '';
    String error = msgBody.error ?? '';
    bool end = msgBody.end ?? false;
    String jsMethodId = msgBody.jsMethodId ?? '';
    Object? body = msgBody.body;
    if (callID.isNotEmpty) {
      JSCompletionHandler? callHandler = _callHandlers?[callID];
      if (callHandler != null) {
        callHandler(body, error);
        if (end) _callHandlers?.remove(callID);
      }
      return;
    }
    JSRegisterHandler? registerHandler = _registerHandlers?[name];
    callback(Object? result, {bool end = true}) {
      Map map = {};
      map["end"] = end ? 1 : 0;
      map["result"] = result;
      String jsonResult = json.encode(map);
      String js =
          "window.zlbridge._nativeCallback('$jsMethodId','$jsonResult');";
      _evaluateJavascriptFunc?.call(js);
    }

    registerHandler != null
        ? registerHandler(body, callback)
        : _undefinedHandler?.call(name, body, callback);
  }

  void injectLocalJS({void Function(Object? error)? callback}) async {
    rootBundle
        .loadString('packages/zlbridge_flutter/assets/zlbridge.js')
        .then((value) {
      _evaluateJavascriptFunc?.call(value).then((value) {
        if (callback != null) callback(null);
      }).catchError((onError) {
        if (callback != null) callback(onError);
      });
    }).catchError((onError) {
      callback?.call(onError);
    });
  }

  void registerHandler(String methodName, JSRegisterHandler registHandler) {
    if (methodName.isEmpty) return;
    _registerHandlers?[methodName] = registHandler;
  }

  void registerUndefinedHandler(JSRegisterUndefinedHandler registHandler) {
    _undefinedHandler = registHandler;
  }

  void removeRegisterHandlerWithMethodName(String name) {
    _registerHandlers?.remove(name);
  }

  void removeAllRegisterHandler() {
    _registerHandlers?.clear();
  }

  void hasNativeMethod(String name, void Function(bool exit)? callback) {
    if (_evaluateJavascriptFunc == null) return;
    if (callback == null) return;
    if (name.isEmpty) callback(false);
    String js = "window.zlbridge._hasNativeMethod('$name');";
    _evaluateJavascriptFunc?.call(js).then((value) {
      String v = value;
      callback(v == "1");
    }).catchError((onError) {
      callback(false);
    });
  }

  void callHandler(String methodName,
      {List? args, JSCompletionHandler? completionHandler}) {
    if (_evaluateJavascriptFunc == null) {
      if (completionHandler != null) {
        completionHandler(null, "请实现evaluateJavascriptAction");
      }
      return;
    }
    args = args ?? [];
    Map map = <String, dynamic>{};
    map["result"] = args;
    String id0 = '';
    if (completionHandler != null) {
      int id = DateTime.now().millisecondsSinceEpoch;
      id0 = "$id";
      map["callID"] = id0;
      _callHandlers?[id0] = completionHandler;
    }
    String jsonResult = json.encode(map);
    String js = "window.zlbridge._nativeCall('$methodName','$jsonResult')";
    _evaluateJavascriptFunc?.call(js).then((value) {}).catchError((onError) {
      if (completionHandler != null) {
        completionHandler(null, onError.toString());
        _callHandlers?.remove(id0);
      }
    });
  }

  void destroyBridge() {
    _registerHandlers?.clear();
    _callHandlers?.clear();
    _undefinedHandler = null;
  }
}

class _ZLMsgBody {
  String? name;
  String? jsMethodId;
  Object? body;
  String? callID;
  bool? end;
  String? error;
  _ZLMsgBody.initWithMap(String js) {
    Map<String, dynamic> map = jsonDecode(js);
    name = map["name"];
    jsMethodId = map["jsMethodId"];
    body = map["body"];
    callID = map["callID"];
    end = map["end"];
    error = map["error"];
  }
}
