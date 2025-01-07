import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ThreadsApiService {
  final String _baseUrl = 'https://threads.net';
  final String _apiBaseUrl = 'https://graph.threads.net';
  String? _accessToken;
  String? _userId;

  void setCredentials(String accessToken, String userId) {
    _accessToken = accessToken;
    _userId = userId;
  }

  bool get isLoggedIn => _accessToken != null && _userId != null;

  Future<String> getAuthorizationUrl() async {
    final clientId = dotenv.env['THREADS_APP_ID'];
    print('Using client ID: $clientId');

    final url = '$_baseUrl/oauth/authorize'
        '?client_id=$clientId'
        '&redirect_uri=https://exchangecodefortokenv2-c6v7kntvaa-uc.a.run.app'
        '&scope=threads_basic,threads_content_publish'
        '&response_type=code'
        '&state=${DateTime.now().millisecondsSinceEpoch}';

    print('Authorization URL: $url');
    return url;
  }

  Future<Map<String, dynamic>> getProfile() async {
    if (!isLoggedIn) {
      throw Exception('사용자가 로그인하지 않았습니다.');
    }

    final url = Uri.parse('$_apiBaseUrl/me').replace(
      queryParameters: {
        'fields':
            'id,username,name,threads_profile_picture_url,threads_biography',
      },
    );

    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'Accept': 'application/json',
      },
    );

    print('Profile API Response: ${response.body}');

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('프로필을 가져오는데 실패했습니다: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> getPosts(
      {String? cursor, bool debugMode = false}) async {
    if (!isLoggedIn) {
      throw Exception('사용자가 로그인하지 않았습니다.');
    }

    final url = Uri.parse('$_apiBaseUrl/me/threads').replace(
      queryParameters: {
        if (cursor != null) 'cursor': cursor,
        'limit': '100',
        'fields': debugMode
            ? 'id,text,caption,timestamp,media_type,media_url,permalink_url'
            : 'id,caption,text,media_url,media_type,like_count,reply_count,timestamp,permalink_url',
      },
    );

    print('Posts API URL: $url');
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'Accept': 'application/json',
      },
    );

    print('Posts API Response: ${response.body}');

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final posts = List<Map<String, dynamic>>.from(data['data'] ?? []);
      final paging = data['paging'] ?? {};

      // 다음 페이지가 있는지 확인
      final hasMore = paging['next'] != null;

      // 리포스트가 아닌 게시물만 필터링
      final originalPosts = posts.where((post) {
        final isRepostFacade = post['media_type'] == 'REPOST_FACADE';

        print('\n=== Post Details ===');
        print('Post ID: ${post['id']}');
        print('Text: ${post['text']}');
        print('Caption: ${post['caption']}');
        print('Media Type: ${post['media_type']}');
        print('Media URL: ${post['media_url']}');
        print('Permalink: ${post['permalink_url']}');
        print('Is Repost Facade: $isRepostFacade');
        print('Timestamp: ${post['timestamp']}');
        print('==================\n');

        // 리포스트가 아닌 것만 반환
        return !isRepostFacade;
      }).toList();

      return {
        'posts': debugMode ? posts : originalPosts,
        'paging': paging,
        'summary': {
          'total_count': originalPosts.length,
          'has_more': hasMore,
        }
      };
    } else {
      throw Exception('포스트를 가져오는데 실패했습니다: ${response.body}');
    }
  }

  Future<int> getPostCount() async {
    if (!isLoggedIn) {
      throw Exception('사용자가 로그인하지 않았습니다.');
    }

    int totalCount = 0;
    String? nextCursor;
    bool hasMore = true;

    while (hasMore) {
      final url = Uri.parse('$_apiBaseUrl/me/threads').replace(
        queryParameters: {
          if (nextCursor != null) 'cursor': nextCursor,
          'fields': 'id,media_type',
          'limit': '100',
        },
      );

      print('Post Count API URL: $url');
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['data'] is List) {
          final posts = data['data'] as List;

          // 리포스트가 아닌 게시물만 필터링
          final originalPosts = posts.where((post) {
            if (post is! Map<String, dynamic>) return false;
            return post['media_type'] != 'REPOST_FACADE';
          }).toList();

          print('현재 페이지 전체 수: ${posts.length}');
          print('현재 페이지 원본 게시물 수: ${originalPosts.length}');
          print('현재 페이지 리포스트 수: ${posts.length - originalPosts.length}');

          totalCount += originalPosts.length;

          // 다음 페이지 확인
          final paging = data['paging'] as Map<String, dynamic>?;
          if (paging != null && paging['next'] is Map<String, dynamic>) {
            final nextData = paging['next'] as Map<String, dynamic>;
            nextCursor = nextData['cursor'] as String?;
            hasMore = nextCursor != null;
          } else {
            hasMore = false;
          }
        } else {
          hasMore = false;
        }
      } else {
        throw Exception('포스트 갯수를 가져오는데 실패했습니다: ${response.body}');
      }
    }

    print('최종 원본 게시물 수: $totalCount');
    return totalCount;
  }

  Map<String, dynamic> parseCallbackUri(String callbackUri) {
    print('Parsing callback URI: $callbackUri');
    final uri = Uri.parse(callbackUri);

    if (uri.queryParameters.containsKey('error')) {
      final error = uri.queryParameters['error'];
      final errorDescription = uri.queryParameters['error_description'];
      print('OAuth Error: $error - $errorDescription');
      return {
        'success': false,
        'error': error,
        'error_description': errorDescription,
      };
    }

    _accessToken = uri.queryParameters['access_token'];
    _userId = uri.queryParameters['user_id'];

    print('Access Token: $_accessToken');
    print('User ID: $_userId');

    return {
      'success': true,
      'access_token': _accessToken,
      'user_id': _userId,
    };
  }
}
