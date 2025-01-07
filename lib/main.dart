import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_web_auth/flutter_web_auth.dart';
import 'services/threads_api_service.dart';
import 'dart:convert';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '가보자',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: '가보자'),
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
  final ThreadsApiService _apiService = ThreadsApiService();
  Map<String, dynamic>? _profile;
  int _totalPostCount = 0;
  bool _isLoading = false;
  bool _isLoadingPosts = false;

  @override
  void initState() {
    super.initState();
    _loadPostCount();
  }

  Future<void> _loadPostCount() async {
    if (!_apiService.isLoggedIn) return;

    try {
      setState(() {
        _isLoadingPosts = true;
      });

      final count = await _apiService.getPostCount();
      setState(() {
        _totalPostCount = count;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('포스트 갯수를 가져오는데 실패했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPosts = false;
        });
      }
    }
  }

  Future<void> _signInWithOAuth() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final authUrl = await _apiService.getAuthorizationUrl();

      final result = await FlutterWebAuth.authenticate(
        url: authUrl,
        callbackUrlScheme: 'thuft',
      );

      final tokenResult = _apiService.parseCallbackUri(result);

      if (tokenResult['success']) {
        final profile = await _apiService.getProfile();
        setState(() {
          _profile = profile;
        });
        await _loadPostCount();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('로그인 실패: ${tokenResult['error']}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('오류 발생: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signOut() async {
    setState(() {
      _profile = null;
      _totalPostCount = 0;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('로그아웃되었습니다.'),
        ),
      );
    }
  }

  Future<void> _refresh() async {
    await _loadPostCount();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          if (_apiService.isLoggedIn)
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: _signOut,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _profile != null
              ? RefreshIndicator(
                  onRefresh: _refresh,
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: _buildProfile(),
                      ),
                    ],
                  ),
                )
              : _buildLoginButton(),
    );
  }

  Widget _buildProfile() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundImage:
                    _profile?['threads_profile_picture_url'] != null
                        ? NetworkImage(_profile!['threads_profile_picture_url'])
                        : null,
                child: _profile?['threads_profile_picture_url'] == null
                    ? const Icon(Icons.person, size: 30)
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _profile?['name'] ?? '사용자',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '@${_profile?['username'] ?? ''}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                    const SizedBox(height: 8),
                    _isLoadingPosts
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            '총 $_totalPostCount개의 포스트',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Colors.grey[600],
                                ),
                          ),
                  ],
                ),
              ),
            ],
          ),
          if (_profile?['threads_biography'] != null &&
              _profile!['threads_biography'].toString().isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              _profile!['threads_biography'],
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 24),
          const Text(
            '디버그 정보',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _showDebugInfo,
            child: const Text('API 응답 데이터 보기'),
          ),
        ],
      ),
    );
  }

  void _showDebugInfo() async {
    setState(() {
      _isLoadingPosts = true;
    });

    try {
      final response = await _apiService.getPosts(
        debugMode: true,
      );

      if (!mounted) return;

      final posts = response['posts'] as List;

      showDialog(
        context: context,
        builder: (context) => Dialog(
          child: Container(
            width: double.maxFinite,
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'API 응답 데이터 (${posts.length}개)',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var post in posts) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.grey.shade50,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 기본 정보
                                _buildInfoRow('ID', post['id']),
                                _buildDivider(),

                                // 컨텐츠 정보
                                if (post['text'] != null)
                                  _buildInfoRow('텍스트', post['text']),
                                if (post['caption'] != null)
                                  _buildInfoRow('캡션', post['caption']),
                                if (post['text'] != null ||
                                    post['caption'] != null)
                                  _buildDivider(),

                                // 미디어 정보
                                if (post['media_type'] != null)
                                  _buildInfoRow('미디어 타입', post['media_type']),
                                if (post['media_url'] != null) ...[
                                  _buildInfoRow('미디어 URL', post['media_url']),
                                  const SizedBox(height: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      post['media_url'],
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              const Text('이미지를 불러올 수 없습니다'),
                                    ),
                                  ),
                                ],
                                if (post['media_type'] != null ||
                                    post['media_url'] != null)
                                  _buildDivider(),

                                // 게시물 타입 정보
                                Row(
                                  children: [
                                    _buildTypeChip(
                                      '댓글',
                                      post['is_reply'] == true,
                                      Colors.blue,
                                    ),
                                    const SizedBox(width: 8),
                                    _buildTypeChip(
                                      '답글',
                                      post['in_reply_to'] != null,
                                      Colors.green,
                                    ),
                                    const SizedBox(width: 8),
                                    _buildTypeChip(
                                      '리포스트',
                                      post['referenced_post'] != null,
                                      Colors.orange,
                                    ),
                                  ],
                                ),
                                _buildDivider(),

                                // 상세 정보
                                if (post['in_reply_to'] != null)
                                  _buildInfoRow('답글 대상',
                                      json.encode(post['in_reply_to'])),
                                if (post['referenced_post'] != null)
                                  _buildInfoRow('참조된 게시물',
                                      json.encode(post['referenced_post'])),
                                _buildInfoRow(
                                    '작성일', post['timestamp'] ?? '알 수 없음'),
                                if (post['permalink_url'] != null)
                                  _buildInfoRow(
                                      '게시물 링크', post['permalink_url']),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '원본 게시물: ${posts.where((p) => p['is_reply'] != true && p['in_reply_to'] == null && p['referenced_post'] == null).length}개',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '기타: ${posts.where((p) => p['is_reply'] == true || p['in_reply_to'] != null || p['referenced_post'] != null).length}개',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('데이터를 가져오는데 실패했습니다: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPosts = false;
        });
      }
    }
  }

  Widget _buildInfoRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.toString(),
              style: const TextStyle(
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Divider(
        color: Colors.grey.shade300,
        height: 1,
      ),
    );
  }

  Widget _buildTypeChip(String label, bool isActive, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? color.withOpacity(0.1) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? color : Colors.grey.shade300,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isActive ? color : Colors.grey,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildLoginButton() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Threads에 로그인하여 시작하세요',
            style: TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _signInWithOAuth,
            icon: const Icon(Icons.login),
            label: const Text('Threads로 로그인'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
