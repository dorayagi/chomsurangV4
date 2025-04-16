import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart';

// นำเข้า FileDownloadHelper และ WebViewDownloadMixin จากไฟล์หลัก
// หรือในกรณีที่ต้องการเก็บในไฟล์นี้ ก็ให้เพิ่มคลาสเหล่านี้เข้ามาด้วย

// คลาสช่วยสำหรับดาวน์โหลดไฟล์ (ในกรณีที่แยกไฟล์)
class FileDownloadHelper {
  static final Dio _dio = Dio();

  // ตรวจสอบสิทธิ์การเข้าถึงพื้นที่จัดเก็บข้อมูล
  static Future<bool> checkPermissions() async {
    if (Platform.isAndroid) {
      PermissionStatus status = await Permission.storage.status;
      if (status.isDenied) {
        status = await Permission.storage.request();
      }
      return status.isGranted;
    }
    return true; // สำหรับ iOS ไม่จำเป็นต้องขอสิทธิ์
  }

  // ตรวจสอบว่าเป็น URL ดาวน์โหลดหรือไม่
  static bool isDownloadUrl(String url) {
    final downloadExtensions = [
      '.pdf',
      '.doc',
      '.docx',
      '.xls',
      '.xlsx',
      '.ppt',
      '.pptx',
      '.zip',
      '.rar',
      '.7z',
      '.txt',
      '.csv',
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.mp3',
      '.mp4',
      '.wav',
      '.avi',
      '.mov',
      '.apk',
    ];

    return downloadExtensions.any((ext) => url.toLowerCase().endsWith(ext)) ||
        url.contains('download') ||
        url.contains('attachment') ||
        url.contains('file');
  }

  // ดาวน์โหลดไฟล์
  static Future<void> downloadFile(
    BuildContext context,
    String url,
    Function(double) onProgress,
    Function(bool, String, String) onComplete,
  ) async {
    if (!await checkPermissions()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่ได้รับอนุญาตให้ดาวน์โหลดไฟล์')),
      );
      onComplete(false, '', '');
      return;
    }

    try {
      // แยกชื่อไฟล์จาก URL
      String fileName = url.split('/').last;
      if (fileName.contains('?')) {
        fileName = fileName.split('?').first;
      }

      // ถ้าชื่อไฟล์ว่างหรือไม่มีนามสกุล ให้ตั้งชื่อเป็นค่าเริ่มต้น
      if (fileName.isEmpty || !fileName.contains('.')) {
        fileName = 'download_${DateTime.now().millisecondsSinceEpoch}.dat';
      }

      // กำหนดพาธสำหรับบันทึกไฟล์
      final Directory? directory =
          Platform.isAndroid
              ? await getExternalStorageDirectory()
              : await getApplicationDocumentsDirectory();

      if (directory == null) {
        throw Exception('ไม่สามารถเข้าถึงไดเรกทอรีจัดเก็บข้อมูลได้');
      }

      final String filePath = '${directory.path}/$fileName';

      // ดาวน์โหลดไฟล์
      await _dio.download(
        url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = received / total;
            onProgress(progress);
          }
        },
      );

      // แจ้งว่าดาวน์โหลดเสร็จแล้ว
      onComplete(true, filePath, fileName);
    } catch (e) {
      onComplete(false, '', e.toString());
    }
  }
}

// Mixin สำหรับหน้า WebView ที่มีการดาวน์โหลดไฟล์ (ในกรณีที่แยกไฟล์)
mixin WebViewDownloadMixin<T extends StatefulWidget> on State<T> {
  bool isDownloading = false;
  double downloadProgress = 0.0;
  String downloadingFileName = '';

  // Widget แสดงความคืบหน้าการดาวน์โหลด
  Widget buildDownloadingIndicator() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          width: 300,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'กำลังดาวน์โหลด...',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                downloadingFileName,
                style: const TextStyle(fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: downloadProgress),
              const SizedBox(height: 8),
              Text('${(downloadProgress * 100).toStringAsFixed(1)}%'),
            ],
          ),
        ),
      ),
    );
  }

  // เริ่มดาวน์โหลดไฟล์
  void startDownload(BuildContext context, String url) {
    // ตัดสตริงพิเศษออกจาก URL ถ้ามี
    String cleanUrl = url;
    if (cleanUrl.startsWith('"') && cleanUrl.endsWith('"')) {
      cleanUrl = cleanUrl.substring(1, cleanUrl.length - 1);
    }

    String fileName = cleanUrl.split('/').last;
    if (fileName.contains('?')) {
      fileName = fileName.split('?').first;
    }

    setState(() {
      isDownloading = true;
      downloadProgress = 0.0;
      downloadingFileName = fileName;
    });

    FileDownloadHelper.downloadFile(
      context,
      cleanUrl,
      (progress) {
        setState(() {
          downloadProgress = progress;
        });
      },
      (success, filePath, error) {
        setState(() {
          isDownloading = false;
        });

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('ดาวน์โหลด $fileName สำเร็จแล้ว'),
              action: SnackBarAction(
                label: 'เปิด',
                onPressed: () {
                  OpenFilex.open(filePath);
                },
              ),
              duration: const Duration(seconds: 5),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('เกิดข้อผิดพลาดในการดาวน์โหลด: $error'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      },
    );
  }

  // ตรวจสอบสิทธิ์การเข้าถึงพื้นที่จัดเก็บข้อมูล
  Future<void> checkStoragePermission() async {
    await FileDownloadHelper.checkPermissions();
  }
}

// หน้า WebView สำหรับระบบครู
class TeacherSystemPage extends StatefulWidget {
  const TeacherSystemPage({super.key});

  @override
  State<TeacherSystemPage> createState() => _TeacherSystemPageState();
}

class _TeacherSystemPageState extends State<TeacherSystemPage>
    with WebViewDownloadMixin {
  late final WebViewController controller;
  bool isLoading = true;
  bool canGoBack = false;

  @override
  void initState() {
    super.initState();
    // ขอสิทธิ์การเข้าถึงพื้นที่จัดเก็บข้อมูลเมื่อเริ่มต้น
    checkStoragePermission();

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
                final canGoBackCheck = await controller.canGoBack();
                setState(() {
                  isLoading = false;
                  canGoBack = canGoBackCheck;
                });
              },
              onNavigationRequest: (NavigationRequest request) {
                // ตรวจสอบว่าเป็น URL ดาวน์โหลดหรือไม่
                if (FileDownloadHelper.isDownloadUrl(request.url)) {
                  startDownload(context, request.url);
                  return NavigationDecision.prevent;
                }
                // อนุญาตให้นำทางตามปกติ
                return NavigationDecision.navigate;
              },
            ),
          )
          ..loadRequest(Uri.parse('https://www.chomsurang.ac.th/applogin/'));
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (canGoBack) {
          await controller.goBack();
          return false;
        } else {
          return true;
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ระบบครู'),
          backgroundColor: Colors.cyan[800],
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              if (await controller.canGoBack()) {
                await controller.goBack();
              } else {
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
            if (isDownloading) buildDownloadingIndicator(),
          ],
        ),
      ),
    );
  }
}
