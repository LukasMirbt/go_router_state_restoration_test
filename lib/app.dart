import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      restorationScopeId: 'router',
      routes: [
        StatefulShellRoute.indexedStack(
          restorationScopeId: 'stateful_shell',
          pageBuilder: (context, state, navigationShell) {
            return MaterialPage(
              restorationId: 'stateful_shell_page',
              child: Scaffold(
                appBar: AppBar(
                  title: Text('Branch ${navigationShell.currentIndex}'),
                ),
                body: navigationShell,
              ),
            );
          },
          branches: [
            StatefulShellBranch(
              restorationScopeId: 'first_branch',
              routes: [
                GoRoute(
                  path: '/',
                  builder: (context, state) {
                    return Center(
                      child: Column(
                        children: [
                          FilledButton(
                            onPressed: () {
                              GoRouter.of(context).go('/second');
                            },
                            child: Text('Go to Second'),
                          ),
                          TextField(
                            restorationId: 'first_branch_text_field',
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
            StatefulShellBranch(
              restorationScopeId: 'second_branch',
              routes: [
                GoRoute(
                  path: '/second',
                  builder: (context, state) {
                    return Column(
                      children: [
                        FilledButton(
                          onPressed: () {
                            GoRouter.of(context).go('/');
                          },
                          child: Text('Go to First'),
                        ),
                        Center(
                          child: TextField(
                            restorationId: 'second_branch_text_field',
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      restorationScopeId: 'app',
      routerConfig: _router,
    );
  }
}
