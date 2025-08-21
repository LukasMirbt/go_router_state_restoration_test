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
        GoRoute(
          path: '/',
          builder: (context, state) {
            return Scaffold(
              appBar: AppBar(
                title: Text('Home'),
              ),
              body: Center(
                child: TextField(
                  restorationId: 'details_text_field',
                ),
              ),
            );
          },
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
