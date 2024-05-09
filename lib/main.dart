import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:readsms/readsms.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    return MaterialApp(
      title: 'SMS Proxy',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'SMS Proxy'),
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
              FilledButton(
                  onPressed: () async {
                    final status = await Permission.sms.status;
                    print(status);

                    final isGranted = await Permission.sms.request().isGranted;
                    print(isGranted);

                    final plugin = Readsms();
                    plugin.read();
                    plugin.smsStream.listen((sms) async {
                      print("${sms.sender} : ${sms.body}");

                      if (!sms.body.contains(setting.keyword)) {
                        return;
                      }

                      final dio = Dio();
                      await dio.post(setting.url, data: {"text": sms.body});
                    });

                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("SMS Proxy installed!")));
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
                  hintText: "URL to Post",
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
}
