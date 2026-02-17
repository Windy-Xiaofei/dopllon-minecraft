import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';

// 切换深/浅/系统主题
class AppTheme {
  static final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

  static Future<void> loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mode = prefs.getString('theme_mode') ?? 'system';
      switch (mode) {
        case 'light':
          themeNotifier.value = ThemeMode.light;
          break;
        case 'dark':
          themeNotifier.value = ThemeMode.dark;
          break;
        default:
          themeNotifier.value = ThemeMode.system;
      }
    } catch (e) {
      themeNotifier.value = ThemeMode.system;
    }
  }

  static Future<void> saveTheme(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode);
    switch (mode) {
      case 'light':
        themeNotifier.value = ThemeMode.light;
        break;
      case 'dark':
        themeNotifier.value = ThemeMode.dark;
        break;
      default:
        themeNotifier.value = ThemeMode.system;
    }
  }
}

// 获取系统总内存（MB）的简单实现，跨平台尝试读取。
Future<int> getTotalSystemMemoryMB() async {
  try {
    if (Platform.isWindows) {
      final result = await Process.run('wmic', ['ComputerSystem', 'get', 'TotalPhysicalMemory'], runInShell: true);
      final lines = result.stdout.toString().split(RegExp(r'\r?\n')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (lines.length >= 2) {
        final value = int.tryParse(lines[1].replaceAll(RegExp(r'[^0-9]'), ''));
        if (value != null) return (value / 1024 / 1024).round();
      }
    } else if (Platform.isLinux) {
      final f = File('/proc/meminfo');
      if (await f.exists()) {
        final content = await f.readAsLines();
        final line = content.firstWhere((l) => l.startsWith('MemTotal'), orElse: () => '');
        final m = RegExp(r"\d+").firstMatch(line);
        if (m != null) {
          final kb = int.parse(m.group(0)!);
          return (kb / 1024).round();
        }
      }
    } else if (Platform.isMacOS) {
      final result = await Process.run('sysctl', ['-n', 'hw.memsize'], runInShell: true);
      final value = int.tryParse(result.stdout.toString().trim());
      if (value != null) return (value / 1024 / 1024).round();
    }
  } catch (e) {
    // ignore and fallback
  }
  return 4096; // fallback 4GB
}

// Java 版本检测工具
Future<List<String>> detectInstalledJavaVersions() async {
  List<String> javaVersions = [];
  
  try {
    List<String> commonPaths = [];
    
    if (Platform.isWindows) {
      // Windows 常见 Java 路径
      commonPaths = [
        'C:\\Program Files\\Java',
        'C:\\Program Files (x86)\\Java',
        'C:\\java',
      ];
    } else if (Platform.isMacOS) {
      commonPaths = [
        '/Library/Java/JavaVirtualMachines',
        '/usr/libexec/java_home',
      ];
    } else if (Platform.isLinux) {
      commonPaths = [
        '/usr/lib/jvm',
        '/opt/java',
      ];
    }
    
    // 首先尝试直接运行 java -version
    try {
      final result = await Process.run('java', ['-version'], runInShell: true);
      final output = result.stderr.toString() + result.stdout.toString();
      
      if (output.isNotEmpty) {
        RegExp versionRegex = RegExp(r'version "([\d.]+)"');
        Match? match = versionRegex.firstMatch(output);
        
        if (match != null) {
          String version = match.group(1) ?? 'Unknown';
          String javaBinary = 'java';
          if (!javaVersions.contains('$javaBinary ($version)')) {
            javaVersions.add('$javaBinary ($version)');
          }
        }
      }
    } catch (e) {
      // java 命令不在 PATH 中
    }
    
    // 尝试检查常见目录
    for (String path in commonPaths) {
      try {
        final dir = Directory(path);
        if (await dir.exists()) {
          final items = await dir.list().toList();
          for (var item in items) {
            if (item is Directory) {
              String dirName = item.path.split(Platform.pathSeparator).last;
              if (dirName.startsWith('jdk') || dirName.startsWith('java')) {
                if (!javaVersions.contains(dirName)) {
                  javaVersions.add(dirName);
                }
              }
            }
          }
        }
      } catch (e) {
        // 无法访问该路径
      }
    }
    
    // 尝试通过命令行查找 (仅 Linux/Mac)
    if (Platform.isLinux || Platform.isMacOS) {
      try {
        final result = await Process.run('which', ['java'], runInShell: true);
        if (result.stdout.toString().isNotEmpty) {
          final javaPath = result.stdout.toString().trim();
          
          final versionResult = await Process.run(javaPath, ['-version'], runInShell: true);
          final versionOutput = versionResult.stderr.toString();
          
          RegExp versionRegex = RegExp(r'version "([\d.]+)"');
          Match? match = versionRegex.firstMatch(versionOutput);
          
          if (match != null) {
            String version = match.group(1) ?? 'Unknown';
            if (!javaVersions.contains('java ($version)')) {
              javaVersions.add('java ($version)');
            }
          }
        }
      } catch (e) {
        // 无法执行 which
      }
    }
  } catch (e) {
    print('Java 检测出错: $e');
  }
  
  return javaVersions;
}

// 验证Java路径是否有效
Future<String?> validateJavaPath(String javaPath) async {
  try {
    String executablePath = javaPath;
    
    // 如果是文件夹，尝试找到 java 可执行文件
    if (FileSystemEntity.typeSync(javaPath) == FileSystemEntityType.directory) {
      String binPath = Platform.isWindows 
          ? '$javaPath\\bin\\java.exe' 
          : '$javaPath/bin/java';
      
      if (await File(binPath).exists()) {
        executablePath = binPath;
      } else {
        return null; // Java 可执行文件不存在
      }
    }
    
    // 检测 Java 版本
    final result = await Process.run(executablePath, ['-version'], runInShell: true);
    final output = result.stderr.toString() + result.stdout.toString();
    
    RegExp versionRegex = RegExp(r'version "([\d.]+)"');
    Match? match = versionRegex.firstMatch(output);
    
    if (match != null) {
      String version = match.group(1) ?? 'Unknown';
      return 'Java ($version)';
    }
    
    return null;
  } catch (e) {
    return null;
  }
}

// OAuth 本地回调服务器辅助类（loopback）
class OAuthLocalServer {
  HttpServer? _server;
  int? port;

  /// 启动本地服务器，绑定到 loopback 任意可用端口
  Future<void> start() async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = _server!.port;
  }

  /// 返回用于 OAuth redirect_uri 的地址
  String get redirectUri {
    if (port == null) throw StateError('Server not started');
    return 'http://127.0.0.1:$port/callback';
  }

  /// 启动监听并等待一次回调，返回查询参数（例如 code/state），超时返回 null
  Future<Map<String, String>?> listenForCode({Duration timeout = const Duration(minutes: 5)}) async {
    await start();

    final completer = Completer<Map<String, String>?>();

    _server!.listen((HttpRequest req) async {
      try {
        if (req.uri.path == '/callback') {
          final params = Map<String, String>.from(req.uri.queryParameters);

          // 简单的响应页面，让用户知道可以关闭窗口
          req.response.statusCode = 200;
          req.response.headers.contentType = ContentType.html;
          req.response.write('<html><body><h3>登录完成，你可以关闭此窗口。</h3></body></html>');
          await req.response.close();

          if (!completer.isCompleted) completer.complete(params);

          // 处理完成后延迟关闭服务器
          Future.microtask(() async {
            await stop();
          });
        } else {
          req.response.statusCode = 404;
          await req.response.close();
        }
      } catch (e) {
        if (!completer.isCompleted) completer.completeError(e);
      }
    }, onError: (e) {
      if (!completer.isCompleted) completer.completeError(e);
    }, cancelOnError: true);

    return completer.future.timeout(timeout, onTimeout: () async {
      await stop();
      return null;
    });
  }

  Future<void> stop() async {
    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;
    port = null;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppTheme.loadTheme();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppTheme.themeNotifier,
      builder: (context, themeMode, child) {
        return MaterialApp(
          title: 'DopllonLauncher',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.light),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.dark),
            useMaterial3: true,
          ),
          themeMode: themeMode,
          home: const SplashScreen(),
          routes: {
            '/home': (context) => const MyHomePage(),
            '/create_instance': (context) => const CreateInstancePage(),
            '/instance_created': (context) => const InstanceCreatedPage(),
            '/settings': (context) => const SettingsPage(),
          },
        );
      },
    );
  }
}

// 启动画面 - 显示加载条
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _loadApp();
  }

  Future<void> _loadApp() async {
    // 模拟加载延迟（可以替换为实际的异步操作）
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '加载中...',
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 200,
              child: LinearProgressIndicator(),
            ),
          ],
        ),
      ),
    );
  }
}

// 主页面
class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DopllonLauncher'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              const Text(
                '欢迎使用 DopllonLauncher',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              const Text(
                'Flutter 制作的 Minecraft 启动器',
                style: TextStyle(fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // 账户卡片：离线 / 正版 / 皮肤站
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('账户', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      if (_offlineUsername != null)
                        Text('已以离线用户登录：$_offlineUsername', style: const TextStyle(fontSize: 14))
                      else
                        const Text('登录到你的 Minecraft 账户或使用离线账户。'),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _showOfflineLoginDialog,
                            icon: const Icon(Icons.person_outline),
                            label: const Text('离线登录'),
                          ),
                          ElevatedButton.icon(
                            onPressed: _startMicrosoftOAuthFlow,
                            icon: const Icon(Icons.lock),
                            label: const Text('正版登录'),
                          ),
                          ElevatedButton.icon(
                            onPressed: () => _showYggdrasilLoginDialog(context),
                            icon: const Icon(Icons.brush),
                            label: const Text('皮肤站登录（Yggdrasil）'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // 实例管理卡片：新建 / 我的实例 / 设置
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('实例管理', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text('创建并管理你的 Minecraft 实例'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () { Navigator.pushNamed(context, '/create_instance'); },
                              child: const Text('新建实例'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {},
                              child: const Text('我的实例'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () { Navigator.pushNamed(context, '/settings'); },
                        child: const Text('设置'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _offlineUsername;

  @override
  void initState() {
    super.initState();
    _loadOfflineUser();
  }

  Future<void> _loadOfflineUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _offlineUsername = prefs.getString('offline_username');
      });
    } catch (e) {
      // ignore
    }
  }

  Future<void> _openUrl(String url) async {
    try {
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', url], runInShell: true);
      } else if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else {
        await Process.run('xdg-open', [url]);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('无法打开链接: $e')));
    }
  }

  String _generateCodeVerifier([int length = 64]) {
    final rand = Random.secure();
    final bytes = List<int>.generate(length, (_) => rand.nextInt(256));
    final verifier = base64UrlEncode(bytes).replaceAll('=', '');
    return verifier;
  }

  String _codeChallengeFromVerifier(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  Future<void> _startMicrosoftOAuthFlow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? clientId = prefs.getString('ms_oauth_client_id');

      if (clientId == null || clientId.isEmpty) {
        // 请求用户输入 client id
        final TextEditingController idController = TextEditingController();
        bool saveId = true;
        final res = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('请输入 Microsoft OAuth Client ID'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('需要在 Azure/微软应用注册中获取 client id，若不清楚请先注册应用。'),
                  const SizedBox(height: 8),
                  TextField(controller: idController, decoration: const InputDecoration(hintText: 'Client ID')),
                  Row(
                    children: [
                      Checkbox(value: saveId, onChanged: (v) { saveId = v ?? true; }),
                      const SizedBox(width: 4),
                      const Flexible(child: Text('保存该 Client ID 到本地')),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
                ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('确认')),
              ],
            );
          },
        );

        if (res != true) return;
        clientId = idController.text.trim();
        if (clientId.isEmpty) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Client ID 不能为空')));
          return;
        }
        await prefs.setString('ms_oauth_client_id', clientId);
      }

      final oauthServer = OAuthLocalServer();
      await oauthServer.start();
      final redirectUri = oauthServer.redirectUri;

      final verifier = _generateCodeVerifier();
      final challenge = _codeChallengeFromVerifier(verifier);

      final scopes = ['offline_access', 'openid', 'profile'];
      final authUrl = Uri.https('login.microsoftonline.com', '/consumers/oauth2/v2.0/authorize', {
        'client_id': clientId,
        'response_type': 'code',
        'redirect_uri': redirectUri,
        'response_mode': 'query',
        'scope': scopes.join(' '),
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
      }).toString();

      await _openUrl(authUrl);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请在浏览器中完成登录，等待回调...')));

      final params = await oauthServer.listenForCode(timeout: const Duration(minutes: 5));
      if (params == null || !params.containsKey('code')) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未收到授权 code')));
        return;
      }

      final code = params['code']!;

      // 交换 token
      final tokenEndpoint = Uri.parse('https://login.microsoftonline.com/consumers/oauth2/v2.0/token');
      final body = {
        'client_id': clientId,
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirectUri,
        'code_verifier': verifier,
      };

      final tokenResp = await http.post(tokenEndpoint, headers: {'Content-Type': 'application/x-www-form-urlencoded'}, body: body).timeout(const Duration(seconds: 20));
      if (tokenResp.statusCode != 200) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Token 交换失败：${tokenResp.statusCode} ${tokenResp.body}')));
        return;
      }

      final tokenData = jsonDecode(tokenResp.body);
      // 保存 token
      await prefs.setString('ms_oauth_tokens', jsonEncode(tokenData));

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('微软登录成功，正在交换 Minecraft Token...')));

      await _completeMicrosoftToMinecraft(tokenData);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('OAuth 流失败: $e')));
    }
  }

  void _showOfflineLoginDialog() {
    final TextEditingController nameController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('离线登录'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('离线模式下输入一个用户名开始游戏（仅用于本地识别）'),
              const SizedBox(height: 8),
              TextField(controller: nameController, decoration: const InputDecoration(hintText: '用户名')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入用户名')));
                  return;
                }
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('offline_username', name);
                setState(() { _offlineUsername = name; });
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已以离线用户 $name 登录')));
                Navigator.of(context).pop();
              },
              child: const Text('登录'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _completeMicrosoftToMinecraft(Map tokenData) async {
    try {
      final accessToken = tokenData['access_token'] as String?;
      if (accessToken == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('缺少 Microsoft access_token')));
        return;
      }

      // 1) XBL Authenticate
      final xbl = await _xblAuthenticate(accessToken);
      if (xbl == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('XBL 认证失败')));
        return;
      }

      // 2) XSTS Authenticate
      final xsts = await _xstsAuthenticate(xbl['token']);
      if (xsts == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('XSTS 认证失败')));
        return;
      }

      // 3) Minecraft login with XBOX
      final mc = await _minecraftLoginWithXbox(xbl['uhs'], xsts['token']);
      if (mc == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Minecraft 登录失败')));
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('minecraft_token', mc['accessToken']);
      if (mc.containsKey('profile')) {
        await prefs.setString('minecraft_profile', jsonEncode(mc['profile']));
      }

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Minecraft 登录成功')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('交换流程失败: $e')));
    }
  }

  Future<Map<String, dynamic>?> _xblAuthenticate(String msAccessToken) async {
    final url = Uri.parse('https://user.auth.xboxlive.com/user/authenticate');
    final body = {
      'Properties': {
        'AuthMethod': 'RPS',
        'SiteName': 'user.auth.xboxlive.com',
        'RpsTicket': 'd=$msAccessToken'
      },
      'RelyingParty': 'http://auth.xboxlive.com',
      'TokenType': 'JWT'
    };

    final resp = await http.post(url, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body)).timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) return null;
    final data = jsonDecode(resp.body);
    final token = data['Token'];
    final display = data['DisplayClaims']?['xui']?[0];
    final uhs = display?['uhs'];
    if (token == null || uhs == null) return null;
    return {'token': token, 'uhs': uhs};
  }

  Future<Map<String, dynamic>?> _xstsAuthenticate(String xblToken) async {
    final url = Uri.parse('https://xsts.auth.xboxlive.com/xsts/authorize');
    final body = {
      'Properties': {
        'SandboxId': 'RETAIL',
        'UserTokens': [xblToken]
      },
      'RelyingParty': 'rp://api.minecraftservices.com/',
      'TokenType': 'JWT'
    };

    final resp = await http.post(url, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body)).timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) return null;
    final data = jsonDecode(resp.body);
    final token = data['Token'];
    final display = data['DisplayClaims']?['xui']?[0];
    final uhs = display?['uhs'];
    if (token == null) return null;
    return {'token': token, 'uhs': uhs};
  }

  Future<Map<String, dynamic>?> _minecraftLoginWithXbox(String uhs, String xstsToken) async {
    final url = Uri.parse('https://api.minecraftservices.com/authentication/login_with_xbox');
    final identity = 'XBL3.0 x=$uhs;$xstsToken';
    final body = {'identityToken': identity};

    final resp = await http.post(url, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body)).timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) return null;
    final data = jsonDecode(resp.body);
    // 返回 accessToken 等
    return data;
  }
}

// 新建实例页面 - 左对齐，内容调小，添加版本选择
class CreateInstancePage extends StatefulWidget {
  const CreateInstancePage({super.key});

  @override
  State<CreateInstancePage> createState() => _CreateInstancePageState();
}

class _CreateInstancePageState extends State<CreateInstancePage> {
  final TextEditingController _instanceNameController = TextEditingController();
  String? _selectedGameVersion;
  List<String> _gameVersions = [];
  bool _isLoadingVersions = true;
  String? _errorMessage;
  List<String> _installedJavaVersions = [];
  bool _isLoadingJava = true;
  String? _selectedJavaVersion;

  @override
  void initState() {
    super.initState();
    _loadGameVersions();
    _loadInstalledJavaVersions();
  }
  Future<void> _loadInstalledJavaVersions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final customJavaPaths = prefs.getStringList('custom_java_paths') ?? [];

      final javaVersions = await detectInstalledJavaVersions();
      final all = <String>{...javaVersions, ...customJavaPaths}.toList();

      setState(() {
        _installedJavaVersions = all;
        if (all.isNotEmpty) {
          _selectedJavaVersion = all.first;
        }
        _isLoadingJava = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '检测 Java 失败: $e';
        _installedJavaVersions = [];
        _isLoadingJava = false;
      });
    }
  }

  Future<void> _addJavaPath() async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
      if (selectedDirectory == null) return;

      String? javaVersion = await validateJavaPath(selectedDirectory);
      if (javaVersion == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✗ 该路径不是有效的 Java 安装目录')),
          );
        }
        return;
      }

      if (!_installedJavaVersions.contains(javaVersion)) {
        setState(() {
          _installedJavaVersions.add(javaVersion);
          _selectedJavaVersion = javaVersion;
        });

        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('custom_java_paths', _installedJavaVersions);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✓ 已添加：$javaVersion')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('添加失败: $e')),
        );
      }
    }
  }

  Future<void> _loadGameVersions() async {
    try {
      const String url = 'https://bmclapi2.bangbang93.com/mc/game/version_manifest_v2.json';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final versions = data['versions'] as List;
        
        setState(() {
          _gameVersions = versions.map<String>((v) => v['id'].toString()).toList();
          _selectedGameVersion = _gameVersions.isNotEmpty ? _gameVersions.first : null;
          _isLoadingVersions = false;
        });
      } else {
        _showError('获取版本列表失败：${response.statusCode}');
      }
    } catch (e) {
      _showError('加载版本失败：$e');
    }
  }

  void _showError(String message) {
    setState(() {
      _errorMessage = message;
      _isLoadingVersions = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('新建实例'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              const Text(
                '创建新的游戏实例',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              // Java 检测状态显示
              _buildJavaDetectionStatus(),
              const SizedBox(height: 16),
              const Text(
                '实例名称：',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _instanceNameController,
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  hintText: '输入实例名称',
                  hintStyle: const TextStyle(fontSize: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '游戏版本：',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              _isLoadingVersions
                  ? const CircularProgressIndicator()
                  : _errorMessage != null
                      ? Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red, fontSize: 14),
                        )
                      : DropdownButton<String>(
                          value: _selectedGameVersion,
                          isExpanded: true,
                          items: _gameVersions.map<DropdownMenuItem<String>>((String version) {
                            return DropdownMenuItem<String>(
                              value: version,
                              child: Text(version, style: const TextStyle(fontSize: 14)),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedGameVersion = value;
                            });
                          },
                        ),
              const SizedBox(height: 24),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: const Text('取消', style: TextStyle(fontSize: 16)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () {
                      if (_instanceNameController.text.isNotEmpty && _selectedGameVersion != null) {
                        final instanceInfo = '${_instanceNameController.text}|$_selectedGameVersion';
                        Navigator.pushNamed(context, '/instance_created', arguments: instanceInfo);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请填写所有必要信息')),
                        );
                      }
                    },
                    child: const Text('创建', style: TextStyle(fontSize: 16)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildJavaDetectionStatus() {
    if (_isLoadingJava) {
      return const Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text('正在检测 Java...', style: TextStyle(fontSize: 14)),
        ],
      );
    }

    if (_errorMessage != null) {
      return Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 14));
    }

    if (_installedJavaVersions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange[50],
          border: Border.all(color: Colors.orange, width: 1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '⚠ 未检测到 Java (0 个)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange),
            ),
            const SizedBox(height: 8),
            const Text(
              '请选择 Java 安装路径',
              style: TextStyle(fontSize: 12, color: Colors.orange),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _addJavaPath,
              icon: const Icon(Icons.add),
              label: const Text('添加 Java 路径'),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(6),
          ),
          child: DropdownButton<String>(
            value: _selectedJavaVersion,
            isExpanded: true,
            underline: const SizedBox(),
            items: _installedJavaVersions.map<DropdownMenuItem<String>>((version) {
              return DropdownMenuItem<String>(
                value: version,
                child: Text(version, style: const TextStyle(fontSize: 14)),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                _selectedJavaVersion = value;
              });
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '已检测到 ${_installedJavaVersions.length} 个 Java 版本',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            ElevatedButton.icon(
              onPressed: _addJavaPath,
              icon: const Icon(Icons.add),
              label: const Text('添加'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  void dispose() {
    _instanceNameController.dispose();
    super.dispose();
  }
}
  
  Future<void> _showYggdrasilLoginDialog(BuildContext ctx) async {
    final TextEditingController userController = TextEditingController();
    final TextEditingController passController = TextEditingController();
    final TextEditingController apiController = TextEditingController();

    final prefs = await SharedPreferences.getInstance();
    final savedApi = prefs.getString('ygg_api') ?? 'https://authserver.mojang.com';
    apiController.text = savedApi;

    await showDialog<void>(
      context: ctx,
      builder: (context) {
        return AlertDialog(
          title: const Text('Yggdrasil 登录'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: apiController, decoration: const InputDecoration(labelText: 'Yggdrasil API 地址', hintText: 'https://authserver.mojang.com')),
              const SizedBox(height: 8),
              TextField(controller: userController, decoration: const InputDecoration(hintText: '邮箱 / 用户名')),
              const SizedBox(height: 8),
              TextField(controller: passController, obscureText: true, decoration: const InputDecoration(hintText: '密码')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
            ElevatedButton(
              onPressed: () async {
                final api = apiController.text.trim();
                final username = userController.text.trim();
                final password = passController.text;
                if (api.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('请输入 Yggdrasil API 地址')));
                  return;
                }
                if (username.isEmpty || password.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('请输入用户名和密码')));
                  return;
                }

                // 保存 api 地址
                await prefs.setString('ygg_api', api);

                Navigator.of(context).pop();
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('正在登录 Yggdrasil...')));
                final res = await _yggdrasilAuthenticate(username, password, api);
                if (res == null) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Yggdrasil 登录失败')));
                  return;
                }
                await prefs.setString('ygg_access_token', res['accessToken']);
                if (res.containsKey('selectedProfile')) {
                  await prefs.setString('ygg_profile', jsonEncode(res['selectedProfile']));
                }
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Yggdrasil 登录成功')));
              },
              child: const Text('登录'),
            ),
          ],
        );
      },
    );
  }

  Future<Map<String, dynamic>?> _yggdrasilAuthenticate(String username, String password, [String? apiBase]) async {
    try {
      final base = (apiBase == null || apiBase.isEmpty) ? 'https://authserver.mojang.com' : apiBase;
      var endpoint = base;
      // 如果只输入了域名，则拼接路径
      if (!endpoint.endsWith('/authenticate')) {
        endpoint = endpoint.endsWith('/') ? endpoint + 'authenticate' : '$endpoint/authenticate';
      }
      final url = Uri.parse(endpoint);
      final body = {
        'agent': {'name': 'Minecraft', 'version': 1},
        'username': username,
        'password': password,
        'requestUser': true
      };

      final resp = await http.post(url, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body)).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body);
      return data;
    } catch (e) {
      return null;
    }
  }

// 实例创建完成页面
class InstanceCreatedPage extends StatelessWidget {
  const InstanceCreatedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final instanceInfo = ModalRoute.of(context)?.settings.arguments as String? ?? '新实例||';
    final parts = instanceInfo.split('|');
    final instanceName = parts.isNotEmpty ? parts[0] : '新实例';
    final gameVersion = parts.length > 1 ? parts[1] : '未知';

    return Scaffold(
      appBar: AppBar(
        title: const Text('实例创建成功'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, size: 80, color: Colors.green),
              const SizedBox(height: 30),
              const Text(
                '实例创建成功！',
                style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 30),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey, width: 1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '实例名称：$instanceName',
                      style: const TextStyle(fontSize: 18),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '游戏版本：$gameVersion',
                      style: const TextStyle(fontSize: 18),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 50),
              ElevatedButton(
                onPressed: () {
                  Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
                },
                child: const Text('返回主菜单', style: TextStyle(fontSize: 18)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 设置页面
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String? _selectedJavaVersion;
  int _maxMemory = 2048;
  bool _autoManageMemory = false;
  String _themeModeSelection = 'system'; // 'system' | 'light' | 'dark'
  int _recommendedMemory = 2048;
  List<String> _installedJavaVersions = [];
  bool _isLoadingJava = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      // 加载保存的设置
      final prefs = await SharedPreferences.getInstance();
      final savedJavaVersion = prefs.getString('java_version');
      final savedMaxMemory = prefs.getInt('max_memory') ?? 2048;
      final savedAuto = prefs.getBool('auto_memory') ?? false;
      final savedTheme = prefs.getString('theme_mode') ?? 'system';
      final customJavaPaths = prefs.getStringList('custom_java_paths') ?? [];

      // 检测已安装的 Java 版本
      final javaVersions = await detectInstalledJavaVersions();
      
      // 组合自动检测和自定义的Java版本
      final allJavaVersions = <String>{...javaVersions, ...customJavaPaths}.toList();

      // 计算推荐内存（取系统总内存的一半，约束在 1024 - 8192 之间）
      final totalMB = await getTotalSystemMemoryMB();
      int recommended = (totalMB / 2).round();
      if (recommended < 1024) recommended = 1024;
      if (recommended > 8192) recommended = 8192;

      setState(() {
        _installedJavaVersions = allJavaVersions;
        _maxMemory = savedMaxMemory;
        _autoManageMemory = savedAuto;
        _themeModeSelection = savedTheme;
        _recommendedMemory = recommended;

        // 如果有保存的版本且存在于已安装版本中，使用保存的
        if (savedJavaVersion != null && allJavaVersions.contains(savedJavaVersion)) {
          _selectedJavaVersion = savedJavaVersion;
        } else if (allJavaVersions.isNotEmpty) {
          // 否则使用第一个检测到的版本
          _selectedJavaVersion = allJavaVersions.first;
        }

        // 如果启用了自动管理内存，则把当前选择的内存设置为推荐值
        if (_autoManageMemory) {
          _maxMemory = _recommendedMemory;
        }

        _isLoadingJava = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '加载设置失败: $e';
        _isLoadingJava = false;
        _installedJavaVersions = [];
      });
    }
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      if (_selectedJavaVersion != null && _selectedJavaVersion != '未检测到 Java') {
        await prefs.setString('java_version', _selectedJavaVersion!);
      }
      await prefs.setInt('max_memory', _maxMemory);
      await prefs.setBool('auto_memory', _autoManageMemory);
      await prefs.setString('theme_mode', _themeModeSelection);

      // 同步应用主题
      await AppTheme.saveTheme(_themeModeSelection);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('设置已保存')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  Future<void> _addJavaPath() async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
      
      if (selectedDirectory == null) return; // 用户取消

      // 验证Java路径
      String? javaVersion = await validateJavaPath(selectedDirectory);
      
      if (javaVersion == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✗ 该路径不是有效的 Java 安装目录')),
          );
        }
        return;
      }

      // 添加到列表
      if (!_installedJavaVersions.contains(javaVersion)) {
        setState(() {
          _installedJavaVersions.add(javaVersion);
          _selectedJavaVersion = javaVersion;
        });

        // 保存到本地
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('custom_java_paths', _installedJavaVersions);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✓ 已添加：$javaVersion')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('添加失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              const Text(
                '游戏设置',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'Java 版本：',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              _isLoadingJava
                  ? const Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Text('正在检测 Java...', style: TextStyle(fontSize: 14)),
                      ],
                    )
                  : _errorMessage != null
                      ? Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red, fontSize: 14),
                        )
                      : _installedJavaVersions.isEmpty
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.orange[50],
                                    border: Border.all(color: Colors.orange, width: 1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        '⚠ 未检测到 Java (0 个)',
                                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange),
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        '请选择 Java 安装路径',
                                        style: TextStyle(fontSize: 12, color: Colors.orange),
                                      ),
                                      const SizedBox(height: 8),
                                      ElevatedButton.icon(
                                        onPressed: _addJavaPath,
                                        icon: const Icon(Icons.add),
                                        label: const Text('添加 Java 路径'),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: DropdownButton<String>(
                                    value: _selectedJavaVersion,
                                    isExpanded: true,
                                    underline: const SizedBox(),
                                    items: _installedJavaVersions.map<DropdownMenuItem<String>>((version) {
                                      return DropdownMenuItem<String>(
                                        value: version,
                                        child: Text(version, style: const TextStyle(fontSize: 14)),
                                      );
                                    }).toList(),
                                    onChanged: (value) {
                                      setState(() {
                                        _selectedJavaVersion = value;
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '已检测到 ${_installedJavaVersions.length} 个 Java 版本',
                                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                    ElevatedButton.icon(
                                      onPressed: _addJavaPath,
                                      icon: const Icon(Icons.add),
                                      label: const Text('添加'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
              const SizedBox(height: 24),
              SwitchListTile(
                title: const Text('自动管理内存'),
                subtitle: const Text('根据系统内存自动选择推荐的最大内存'),
                value: _autoManageMemory,
                onChanged: (v) {
                  setState(() {
                    _autoManageMemory = v;
                    if (_autoManageMemory) {
                      _maxMemory = _recommendedMemory;
                    }
                  });
                },
              ),
              const SizedBox(height: 8),
              const Text(
                '主题：',
                style: TextStyle(fontSize: 16),
              ),
              Column(
                children: [
                  RadioListTile<String>(
                    title: const Text('跟随系统'),
                    value: 'system',
                    groupValue: _themeModeSelection,
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _themeModeSelection = v;
                      });
                      AppTheme.saveTheme(v);
                    },
                  ),
                  RadioListTile<String>(
                    title: const Text('浅色'),
                    value: 'light',
                    groupValue: _themeModeSelection,
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _themeModeSelection = v;
                      });
                      AppTheme.saveTheme(v);
                    },
                  ),
                  RadioListTile<String>(
                    title: const Text('深色'),
                    value: 'dark',
                    groupValue: _themeModeSelection,
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _themeModeSelection = v;
                      });
                      AppTheme.saveTheme(v);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                '最大内存（MB）：',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _maxMemory.toDouble(),
                      min: 512,
                      max: 8192,
                      divisions: 15,
                      label: '${_maxMemory} MB',
                      onChanged: _autoManageMemory
                          ? null
                          : (value) {
                              setState(() {
                                _maxMemory = value.toInt();
                              });
                            },
                    ),
                  ),
                  SizedBox(
                    width: 80,
                    child: Text(
                      '$_maxMemory MB',
                      style: const TextStyle(fontSize: 16),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
              if (_autoManageMemory)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text('推荐：$_recommendedMemory MB（根据系统内存自动计算）', style: const TextStyle(color: Colors.grey)),
                ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 24),
              const Text(
                '关于',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                '应用名称：DopllonLauncher',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 12),
              const Text(
                '版本：1.0.0',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 12),
              const Text(
                'Flutter 制作的 Minecraft 启动器',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 40),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: const Text('返回', style: TextStyle(fontSize: 16)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _saveSettings,
                    child: const Text('保存', style: TextStyle(fontSize: 16)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}