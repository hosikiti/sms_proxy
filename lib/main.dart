import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:readsms/readsms.dart';
import 'package:shared_preferences/shared_preferences.dart';

@pragma('vm:entry-point')
void startCallback() {
  // The setTaskHandler function must be called to handle the task in the background.
  FlutterForegroundTask.setTaskHandler(SMSHandler());
}

class Setting {
  final String url;
  final String keyword;

  Setting({required this.url, required this.keyword});

  factory Setting.fromJson(Map<String, dynamic> json) {
    return Setting(
      url: json['url'] ?? "",
      keyword: json['keyword'] ?? "",
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'keyword': keyword,
      };
}

late final SharedPreferences prefs;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Obtain shared preferences.
  prefs = await SharedPreferences.getInstance();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: MaterialApp(
        title: 'SMS Proxy',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: const MyHomePage(title: 'SMS Proxy'),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final urlController = TextEditingController();
  final keywordController = TextEditingController();
  Setting setting = Setting(url: "", keyword: "");
  ReceivePort? _receivePort;
  bool isRunning = false;

  Future<bool> _startForegroundTask() async {
    FlutterForegroundTask.saveData(key: "url", value: setting.url);
    FlutterForegroundTask.saveData(key: "keyword", value: setting.keyword);

    // Register the receivePort before starting the service.
    final ReceivePort? receivePort = FlutterForegroundTask.receivePort;
    final bool isRegistered = _registerReceivePort(receivePort);
    if (!isRegistered) {
      print('Failed to register receivePort!');
      return false;
    }

    if (await FlutterForegroundTask.isRunningService) {
      if (!isRunning) {
        setState(() {
          isRunning = true;
        });
      }

      return FlutterForegroundTask.restartService();
    } else {
      return FlutterForegroundTask.startService(
        notificationTitle: 'SMS Proxy Service is running',
        notificationText: 'Tap to return to the app',
        callback: startCallback,
      );
    }
  }

  bool _registerReceivePort(ReceivePort? newReceivePort) {
    if (newReceivePort == null) {
      return false;
    }

    _closeReceivePort();

    _receivePort = newReceivePort;
    _receivePort?.listen((data) async {
      print("received: $data");
    });

    return _receivePort != null;
  }

  void _closeReceivePort() {
    _receivePort?.close();
    _receivePort = null;
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        foregroundServiceType: AndroidForegroundServiceType.DATA_SYNC,
        channelId: 'sms_proxy_service',
        channelName: 'SMS Proxy Service',
        channelDescription:
            'This notification appears when the foreground service is running.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        iconData: const NotificationIconData(
          resType: ResourceType.mipmap,
          resPrefix: ResourcePrefix.ic,
          name: 'launcher',
        ),
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 5000,
        isOnceEvent: false,
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<void> _requestPermissionForAndroid() async {
    if (!Platform.isAndroid) {
      return;
    }
    // Android 12 or higher, there are restrictions on starting a foreground service.
    //
    // To restart the service on device reboot or unexpected problem, you need to allow below permission.
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      // This function requires `android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` permission.
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }

    // Android 13 and higher, you need to allow notification permission to expose foreground service notification.
    final NotificationPermission notificationPermissionStatus =
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermissionStatus != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _requestPermissionForAndroid();
      _initForegroundTask();

      // You can get the previous ReceivePort without restarting the service.
      if (await FlutterForegroundTask.isRunningService) {
        print("Service is running.");
        // final newReceivePort = FlutterForegroundTask.receivePort;
        // _registerReceivePort(newReceivePort);
        _startForegroundTask();
      } else {
        print("Service is not running.");
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final json = prefs.getString("settings");
    if (json != null) {
      final decoded = jsonDecode(json);

      for (var settingJson in decoded) {
        setting = Setting.fromJson(settingJson);
        urlController.text = setting.url;
        keywordController.text = setting.keyword;
        break; // only 1 setting is allowed for now
      }
    }

    return Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          title: Text(widget.title),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Status : ${isRunning ? "Running" : "Not Running"}",
              ),
              FilledButton(
                  onPressed: () async {
                    final isGranted = await Permission.sms.request().isGranted;
                    if (!isGranted) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text(
                                "Please grant SMS permission to use this app!")));
                      }
                      return;
                    }

                    if (context.mounted) {
                      await install(context);
                    }
                  },
                  child: const Text("Install")),
              const SizedBox(height: 64.0),
              const Text(
                "When SMS contains ...",
              ),
              TextField(
                controller: keywordController,
                decoration: const InputDecoration(
                  hintText: "String to match",
                ),
              ),
              const SizedBox(height: 64.0),
              const Text(
                "Post to ...",
              ),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  hintText: "Slack Webhook URL to Post",
                ),
                keyboardType: TextInputType.multiline,
                maxLines: null,
              ),
              const SizedBox(height: 16.0),
              FilledButton(
                  onPressed: () {
                    final settings = [
                      Setting(
                          url: urlController.text,
                          keyword: keywordController.text)
                    ];
                    setting = settings[0];
                    prefs.setString("settings", jsonEncode(settings));
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Settings saved!")));
                  },
                  child: const Text("Save")),
            ],
          ),
        ));
  }

  Future<void> install(BuildContext context) async {
    await FlutterForegroundTask.requestIgnoreBatteryOptimization();

    await _startForegroundTask();

    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("SMS Proxy installed!")));
      setState(() {
        isRunning = true;
      });
    }
  }
}

class SMSHandler extends TaskHandler {
  StreamSubscription<SMS>? _streamSubscription;

  @override
  void onStart(DateTime timestamp, SendPort? sendPort) async {
    final plugin = Readsms();
    plugin.read();

    _streamSubscription = plugin.smsStream.listen((sms) async {
      final url = await FlutterForegroundTask.getData<String>(key: 'url') ?? "";
      final keyword =
          await FlutterForegroundTask.getData<String>(key: 'keyword') ?? "";

      if (url.isEmpty || keyword.isEmpty) {
        return;
      }

      sendPort?.send("keyword: $keyword, url: $url");
      if (sms.body.contains(keyword)) {
        final dio = Dio();
        await dio.post(url, data: {"text": sms.body});
      }
    });

    sendPort?.send("SMS Proxy is started!");
  }

  @override
  void onRepeatEvent(DateTime timestamp, SendPort? sendPort) async {}

  @override
  void onDestroy(DateTime timestamp, SendPort? sendPort) async {
    await _streamSubscription?.cancel();
  }
}
