import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart';
import 'package:device_info_plus/device_info_plus.dart';

// นำเข้าหน้า Splash Screen
import 'splash_screen.dart';

void main() {
  runApp(const MyApp());
}

// คลาสช่วยในการคำนวณขนาดตามสัดส่วนของหน้าจอ
class ResponsiveSize {
  static double width(BuildContext context, double percentage) {
    return MediaQuery.of(context).size.width * percentage;
  }

  static double height(BuildContext context, double percentage) {
    return MediaQuery.of(context).size.height * percentage;
  }

  static double font(BuildContext context, double percentage) {
    return MediaQuery.of(context).size.width * percentage;
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chomsurang Upatham Application',
      theme: ThemeData(primarySwatch: Colors.blue, fontFamily: 'Kanit'),
      home: SplashScreen(nextScreen: const HomePage()),
      debugShowCheckedModeBanner: false,
    );
  }
}

// คลาสช่วยสำหรับดาวน์โหลดไฟล์
class FileDownloadHelper {
  static final Dio _dio = Dio();

  // ตรวจสอบสิทธิ์การเข้าถึงพื้นที่จัดเก็บข้อมูล
  static Future<bool> checkPermissions() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final androidVersion = androidInfo.version.sdkInt;

      if (androidVersion >= 33) {
        // Android 13+ ขอ permission เช่น audio
        final audioStatus = await Permission.audio.request();
        print('Audio permission: $audioStatus');
        return audioStatus.isGranted;
      } else {
        final storageStatus = await Permission.storage.request();
        print('Storage permission: $storageStatus');
        return storageStatus.isGranted;
      }
    }

    return true; // iOS ไม่ต้องขอ
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
        const SnackBar(
          content: Text(
            'ไม่ได้รับอนุญาตให้ดาวน์โหลดไฟล์ โปรดเปิดสิทธิ์การเข้าถึงพื้นที่จัดเก็บข้อมูลในการตั้งค่า',
          ),
        ),
      );
      onComplete(false, '', 'ไม่ได้รับอนุญาตให้เข้าถึงพื้นที่จัดเก็บข้อมูล');
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
      Directory? directory;

      if (Platform.isAndroid) {
        try {
          // ใช้ path ปลอดภัยที่เข้าถึงได้จากแอป
          directory = await getExternalStorageDirectory();

          // เพิ่ม subfolder เช่น "Download" ถ้าต้องการ
          if (directory != null) {
            directory = Directory('${directory.path}/Download');
            if (!await directory.exists()) {
              await directory.create(recursive: true);
            }
          }
        } catch (e) {
          print('ไม่สามารถเข้าถึง ExternalStorageDirectory: $e');
        }
      } else {
        // iOS
        directory = await getApplicationDocumentsDirectory();
      }

      if (directory == null) {
        throw Exception('ไม่สามารถเข้าถึงไดเรกทอรีจัดเก็บข้อมูลได้');
      }

      final String filePath = '${directory.path}/$fileName';
      final File file = File(filePath);

      // ตรวจสอบว่าไฟล์มีอยู่แล้วหรือไม่
      if (await file.exists()) {
        // ถ้ามีไฟล์อยู่แล้ว เปิดเลย
        onComplete(true, filePath, fileName);
        return;
      }

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
        options: Options(
          headers: {
            'Accept': '*/*',
            'User-Agent':
                'Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0 Mobile/15E148 Safari/604.1',
          },
          followRedirects: true,
          validateStatus: (status) {
            return status! < 500;
          },
        ),
      );

      // ตรวจสอบว่าไฟล์ถูกดาวน์โหลดสำเร็จหรือไม่
      if (await file.exists() && await file.length() > 0) {
        // แจ้งว่าดาวน์โหลดเสร็จแล้ว
        onComplete(true, filePath, fileName);
      } else {
        throw Exception('ไฟล์ดาวน์โหลดไม่สมบูรณ์');
      }
    } catch (e) {
      print('เกิดข้อผิดพลาดในการดาวน์โหลด: $e');
      onComplete(false, '', e.toString());
    }
  }
}

// Mixin สำหรับหน้า WebView ที่มีการดาวน์โหลดไฟล์
mixin WebViewDownloadMixin<T extends StatefulWidget> on State<T> {
  bool isDownloading = false;
  double downloadProgress = 0.0;
  String downloadingFileName = '';

  // Widget แสดงความคืบหน้าการดาวน์โหลดที่ปรับตามขนาดหน้าจอ
  Widget buildDownloadingIndicator() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          width: ResponsiveSize.width(context, 0.8), // ปรับขนาดตามหน้าจอ
          padding: EdgeInsets.all(ResponsiveSize.width(context, 0.04)),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'กำลังดาวน์โหลด...',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: ResponsiveSize.font(context, 0.04),
                ),
              ),
              SizedBox(height: ResponsiveSize.height(context, 0.01)),
              Text(
                downloadingFileName,
                style: TextStyle(fontSize: ResponsiveSize.font(context, 0.03)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: ResponsiveSize.height(context, 0.02)),
              LinearProgressIndicator(value: downloadProgress),
              SizedBox(height: ResponsiveSize.height(context, 0.01)),
              Text(
                '${(downloadProgress * 100).toStringAsFixed(1)}%',
                style: TextStyle(fontSize: ResponsiveSize.font(context, 0.035)),
              ),
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

    print('เริ่มดาวน์โหลด: $cleanUrl');
    print('ชื่อไฟล์: $fileName');

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
                  _openFile(filePath);
                },
              ),
              duration: const Duration(seconds: 5),
            ),
          );

          // เปิดไฟล์อัตโนมัติหลังดาวน์โหลดเสร็จ
          _openFile(filePath);
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

  // เปิดไฟล์ที่ดาวน์โหลดมาแล้ว
  Future<void> _openFile(String filePath) async {
    try {
      final result = await OpenFilex.open(filePath); // ส่งต่อให้แอปภายนอก

      if (result.type != ResultType.done && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ไม่สามารถเปิดไฟล์ได้: ${result.message}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการเปิดไฟล์: $e')),
        );
      }
    }
  }

  // ตรวจสอบสิทธิ์การเข้าถึงพื้นที่จัดเก็บข้อมูล
  Future<void> checkStoragePermission() async {
    await FileDownloadHelper.checkPermissions();
  }
}

// หน้าหลักแบบ WebView
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WebViewDownloadMixin {
  late final WebViewController controller;
  bool isLoading = true;
  bool canGoBack = false;

  // เริ่มต้นค่า WebViewController
  @override
  void initState() {
    super.initState();
    // ขอสิทธิ์การเข้าถึงพื้นที่จัดเก็บข้อมูลเมื่อเริ่มต้น

    checkStoragePermission();

    // กำหนดค่า WebViewController
    controller =
        WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(const Color(0x00000000))
          // กำหนด user agent ให้เป็น mobile เพื่อให้เว็บไซต์แสดงในรูปแบบมือถือ
          ..setUserAgent(
            'Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0 Mobile/15E148 Safari/604.1',
          )
          ..setNavigationDelegate(
            NavigationDelegate(
              onWebResourceError: (WebResourceError error) {
                print('WebView error: ${error.description}');
                setState(() {
                  isLoading = false;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'เกิดข้อผิดพลาดในการโหลดเว็บไซต์: ${error.description}',
                    ),
                  ),
                );
              },
              onPageStarted: (String url) {
                print('Page started loading: $url');
                setState(() {
                  isLoading = true;
                });
              },
              onPageFinished: (String url) async {
                print('Page finished loading: $url');
                // ตรวจสอบว่าสามารถย้อนกลับได้หรือไม่
                final canGoBackCheck = await controller.canGoBack();
                setState(() {
                  isLoading = false;
                  canGoBack = canGoBackCheck;
                });
              },
              onNavigationRequest: (NavigationRequest request) {
                print('Navigation request: ${request.url}');
                // ตรวจสอบว่าเป็น URL ดาวน์โหลดหรือไม่
                if (FileDownloadHelper.isDownloadUrl(request.url)) {
                  print('Detected download URL: ${request.url}');
                  startDownload(context, request.url);
                  return NavigationDecision.prevent;
                }

                // ตรวจสอบว่าเป็นลิงก์ภายนอกที่ควรเปิดในเบราว์เซอร์หรือไม่
                if (_isExternalLink(request.url)) {
                  _launchExternalUrl(request.url);
                  return NavigationDecision.prevent;
                }

                // อนุญาตให้นำทางตามปกติ
                return NavigationDecision.navigate;
              },
            ),
          )
          ..enableZoom(true)
          // โหลดหน้าเว็บไซต์ที่ต้องการแสดง
          ..loadRequest(Uri.parse('https://chomsurang.ac.th/application/'));
  }

  // ตรวจสอบว่าเป็นลิงก์ภายนอกที่ควรเปิดในเบราว์เซอร์หรือไม่
  bool _isExternalLink(String url) {
    // ไม่นับลิงก์ที่มาจากโดเมนของโรงเรียนเป็นลิงก์ภายนอก
    if (url.contains('chomsurang.ac.th')) {
      return false;
    }

    // ตรวจสอบลิงก์ภายนอกที่ต้องการให้เปิดในเบราว์เซอร์
    final externalDomains = [
      'facebook.com',
      'youtube.com',
      'google.com',
      'maps.google.com',
      'line.me',
    ];

    return externalDomains.any((domain) => url.contains(domain));
  }

  // เปิดลิงก์ภายนอกในเบราว์เซอร์
  Future<void> _launchExternalUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่สามารถเปิด URL ภายนอกได้')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      // จัดการเมื่อกดปุ่ม Back ของระบบ
      onWillPop: () async {
        if (canGoBack) {
          await controller.goBack();
          // ตรวจสอบอีกครั้งหลังจาก goBack
          final canGoBackCheck = await controller.canGoBack();
          setState(() {
            canGoBack = canGoBackCheck;
          });
          return false; // ไม่ให้ pop หน้านี้
        } else {
          return true; // ให้ pop หน้านี้ (ออกจากแอป)
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Chomsurang Upatham'),
          backgroundColor: Colors.blue[800],
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              // ถ้าสามารถย้อนกลับได้ใน WebView
              if (await controller.canGoBack()) {
                await controller.goBack();
                // อัปเดตสถานะการย้อนกลับหลังจากกดปุ่ม Back
                final canGoBackCheck = await controller.canGoBack();
                setState(() {
                  canGoBack = canGoBackCheck;
                });
              } else {
                // ถ้าไม่สามารถย้อนกลับได้ใน WebView ให้ออกจากแอป
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('กดอีกครั้งเพื่อออกจากแอปพลิเคชัน'),
                    ),
                  );
                }
              }
            },
          ),
          actions: [
            // ปุ่มรีเฟรช
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                controller.reload();
              },
            ),
            // ปุ่มหน้าหลัก
            IconButton(
              icon: const Icon(Icons.home),
              onPressed: () {
                controller.loadRequest(
                  Uri.parse('https://chomsurang.ac.th/application/'),
                );
              },
            ),
          ],
        ),
        body: Stack(
          children: [
            // แสดง WebView
            WebViewWidget(controller: controller),
            // แสดงตัวโหลดระหว่างที่หน้าเว็บกำลังโหลด
            if (isLoading)
              const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
              ),
            // แสดงตัวโหลดระหว่างที่กำลังดาวน์โหลดไฟล์
            if (isDownloading) buildDownloadingIndicator(),
          ],
        ),
      ),
    );
  }
}
