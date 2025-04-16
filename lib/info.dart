import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class InfoPage extends StatefulWidget {
  const InfoPage({super.key});

  @override
  State<InfoPage> createState() => _InfoPageState();
}

class _InfoPageState extends State<InfoPage> {
  late final WebViewController controller;
  bool isLoading = true;
  bool canGoBack = false;

  @override
  void initState() {
    super.initState();
    controller =
        WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setNavigationDelegate(
            NavigationDelegate(
              onPageStarted: (String url) {
                setState(() {
                  isLoading = true;
                });
              },
              onPageFinished: (String url) async {
                // ตรวจสอบว่าสามารถย้อนกลับได้หรือไม่
                final canGoBackCheck = await controller.canGoBack();
                setState(() {
                  isLoading = false;
                  canGoBack = canGoBackCheck;
                });
              },
              onNavigationRequest: (NavigationRequest request) {
                // อนุญาตให้นำทางตามปกติ
                return NavigationDecision.navigate;
              },
            ),
          )
          ..loadRequest(
            Uri.parse('https://www.chomsurang.ac.th/appchom/theme/data1.html'),
          );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      // จัดการเมื่อกดปุ่ม Back ของระบบ
      onWillPop: () async {
        if (canGoBack) {
          await controller.goBack();
          return false; // ไม่ให้ pop หน้านี้
        } else {
          return true; // ให้ pop หน้านี้
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ข้อมูลพื้นฐาน'),
          backgroundColor: Colors.blue[800],
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              // ถ้าสามารถย้อนกลับได้ใน WebView
              if (await controller.canGoBack()) {
                await controller.goBack();
              } else {
                // ถ้าไม่สามารถย้อนกลับได้ใน WebView ให้กลับไปหน้าก่อนหน้า
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              }
            },
          ),
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: controller),
            if (isLoading) const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}
