import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/memo/presentation/memo_edit_page.dart';
import '../../features/memo/presentation/memo_list_page.dart';

/// アプリ内のパス定義。画面から直接文字列を書かないための集約点。
abstract final class AppRoutes {
  static const String memoList = '/';
  static const String memoNew = '/memos/new';

  static String memoEdit(String id) => '/memos/$id';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.memoList,
    routes: [
      GoRoute(
        path: AppRoutes.memoList,
        name: 'memoList',
        builder: (context, state) => const MemoListPage(),
        routes: [
          GoRoute(
            path: 'memos/new',
            name: 'memoNew',
            builder: (context, state) => const MemoEditPage(),
          ),
          GoRoute(
            path: 'memos/:id',
            name: 'memoEdit',
            builder: (context, state) => MemoEditPage(
              memoId: state.pathParameters['id'],
            ),
          ),
        ],
      ),
    ],
  );
});
