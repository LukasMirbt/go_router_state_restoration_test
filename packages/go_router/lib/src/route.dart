// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
// TODO(loic-sharma): Remove meta library prefix.
// https://github.com/flutter/flutter/issues/171410
import 'package:meta/meta.dart' as meta;

import 'configuration.dart';
import 'match.dart';
import 'path_utils.dart';
import 'router.dart';
import 'state.dart';

typedef GoRouterPageBuilder =
    Page<dynamic> Function(BuildContext context, GoRouterState state);

typedef GoRouterWidgetBuilder =
    Widget Function(BuildContext context, GoRouterState state);

typedef ShellRouteBuilder =
    Widget Function(BuildContext context, GoRouterState state, Widget child);

typedef ShellRoutePageBuilder =
    Page<dynamic> Function(
      BuildContext context,
      GoRouterState state,
      Widget child,
    );

typedef StatefulShellRouteBuilder =
    Widget Function(
      BuildContext context,
      GoRouterState state,
      StatefulNavigationShell navigationShell,
    );

typedef StatefulShellRoutePageBuilder =
    Page<dynamic> Function(
      BuildContext context,
      GoRouterState state,
      StatefulNavigationShell navigationShell,
    );

typedef NavigatorBuilder =
    Widget Function(
      GlobalKey<NavigatorState> navigatorKey,
      ShellRouteMatch match,
      RouteMatchList matchList,
      List<NavigatorObserver>? observers,
      String? restorationScopeId,
    );

typedef ExitCallback =
    FutureOr<bool> Function(BuildContext context, GoRouterState state);

@immutable
abstract class RouteBase with Diagnosticable {
  const RouteBase._({
    this.redirect,
    required this.routes,
    required this.parentNavigatorKey,
  });

  final GoRouterRedirect? redirect;

  final List<RouteBase> routes;

  final GlobalKey<NavigatorState>? parentNavigatorKey;

  static Iterable<RouteBase> routesRecursively(Iterable<RouteBase> routes) {
    return routes.expand(
      (RouteBase e) => <RouteBase>[e, ...routesRecursively(e.routes)],
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    if (parentNavigatorKey != null) {
      properties.add(
        DiagnosticsProperty<GlobalKey<NavigatorState>>(
          'parentNavKey',
          parentNavigatorKey,
        ),
      );
    }
  }
}

class GoRoute extends RouteBase {
  /// Constructs a [GoRoute].
  /// - [path] and [name] cannot be empty strings.
  /// - One of either [builder] or [pageBuilder] must be provided.
  GoRoute({
    required this.path,
    this.name,
    this.builder,
    this.pageBuilder,
    super.parentNavigatorKey,
    super.redirect,
    this.onExit,
    this.caseSensitive = true,
    super.routes = const <RouteBase>[],
  }) : assert(path.isNotEmpty, 'GoRoute path cannot be empty'),
       assert(name == null || name.isNotEmpty, 'GoRoute name cannot be empty'),
       assert(
         pageBuilder != null || builder != null || redirect != null,
         'builder, pageBuilder, or redirect must be provided',
       ),
       assert(
         onExit == null || pageBuilder != null || builder != null,
         'if onExit is provided, one of pageBuilder or builder must be provided',
       ),
       super._() {
    // cache the path regexp and parameters
    _pathRE = patternToRegExp(
      path,
      pathParameters,
      caseSensitive: caseSensitive,
    );
  }

  /// Whether this [GoRoute] only redirects to another route.
  ///
  /// If this is true, this route must redirect location other than itself.
  bool get redirectOnly => pageBuilder == null && builder == null;

  /// Optional name of the route.
  ///
  /// If used, a unique string name must be provided and it can not be empty.
  ///
  /// This is used in [GoRouter.namedLocation] and its related API. This
  /// property can be used to navigate to this route without knowing exact the
  /// URI of it.
  ///
  /// Typical usage is as follows:
  ///
  /// ```dart
  /// GoRoute(
  ///   name: 'home',
  ///   path: '/',
  ///   builder: (BuildContext context, GoRouterState state) =>
  ///       HomeScreen(),
  ///   routes: <GoRoute>[
  ///     GoRoute(
  ///       name: 'family',
  ///       path: 'family/:fid',
  ///       builder: (BuildContext context, GoRouterState state) =>
  ///           FamilyScreen(),
  ///     ),
  ///   ],
  /// );
  ///
  /// context.go(
  ///   context.namedLocation('family'),
  ///   pathParameters: <String, String>{'fid': 123},
  ///   queryParameters: <String, String>{'qid': 'quid'},
  /// );
  /// ```
  ///
  /// See the [named routes example](https://github.com/flutter/packages/blob/main/packages/go_router/example/lib/named_routes.dart)
  /// for a complete runnable app.
  final String? name;

  /// The path of this go route.
  ///
  /// For example:
  /// ```dart
  /// GoRoute(
  ///   path: '/',
  ///   pageBuilder: (BuildContext context, GoRouterState state) => MaterialPage<void>(
  ///     key: state.pageKey,
  ///     child: HomePage(families: Families.data),
  ///   ),
  /// ),
  /// ```
  ///
  /// The path also support path parameters. For a path: `/family/:fid`, it
  /// matches all URIs start with `/family/...`, e.g. `/family/123`,
  /// `/family/456` and etc. The parameter values are stored in [GoRouterState]
  /// that are passed into [pageBuilder] and [builder].
  ///
  /// The query parameter are also capture during the route parsing and stored
  /// in [GoRouterState].
  ///
  /// See [Query parameters and path parameters](https://github.com/flutter/packages/blob/main/packages/go_router/example/lib/path_and_query_parameters.dart)
  /// to learn more about parameters.
  final String path;

  /// A page builder for this route.
  ///
  /// Typically a MaterialPage, as in:
  /// ```dart
  /// GoRoute(
  ///   path: '/',
  ///   pageBuilder: (BuildContext context, GoRouterState state) => MaterialPage<void>(
  ///     key: state.pageKey,
  ///     child: HomePage(families: Families.data),
  ///   ),
  /// ),
  /// ```
  ///
  /// You can also use CupertinoPage, and for a custom page builder to use
  /// custom page transitions, you can use [CustomTransitionPage].
  final GoRouterPageBuilder? pageBuilder;

  /// A custom builder for this route.
  ///
  /// For example:
  /// ```dart
  /// GoRoute(
  ///   path: '/',
  ///   builder: (BuildContext context, GoRouterState state) => FamilyPage(
  ///     families: Families.family(
  ///       state.pathParameters['id'],
  ///     ),
  ///   ),
  /// ),
  /// ```
  ///
  final GoRouterWidgetBuilder? builder;

  /// Called when this route is removed from GoRouter's route history.
  ///
  /// Some example this callback may be called:
  ///  * This route is removed as the result of [GoRouter.pop].
  ///  * This route is no longer in the route history after a [GoRouter.go].
  ///
  /// This method can be useful it one wants to launch a dialog for user to
  /// confirm if they want to exit the screen.
  ///
  /// ```dart
  /// final GoRouter _router = GoRouter(
  ///   routes: <GoRoute>[
  ///     GoRoute(
  ///       path: '/',
  ///       onExit: (BuildContext context) => showDialog<bool>(
  ///         context: context,
  ///         builder: (BuildContext context) {
  ///           return AlertDialog(
  ///             title: const Text('Do you want to exit this page?'),
  ///             actions: <Widget>[
  ///               TextButton(
  ///                 style: TextButton.styleFrom(
  ///                   textStyle: Theme.of(context).textTheme.labelLarge,
  ///                 ),
  ///                 child: const Text('Go Back'),
  ///                 onPressed: () {
  ///                   Navigator.of(context).pop(false);
  ///                 },
  ///               ),
  ///               TextButton(
  ///                 style: TextButton.styleFrom(
  ///                   textStyle: Theme.of(context).textTheme.labelLarge,
  ///                 ),
  ///                 child: const Text('Confirm'),
  ///                 onPressed: () {
  ///                   Navigator.of(context).pop(true);
  ///                 },
  ///               ),
  ///             ],
  ///           );
  ///         },
  ///       ),
  ///     ),
  ///   ],
  /// );
  /// ```
  final ExitCallback? onExit;

  /// Determines whether the route matching is case sensitive.
  ///
  /// When `true`, the path must match the specified case. For example,
  /// a [GoRoute] with `path: '/family/:fid'` will not match `/FaMiLy/f2`.
  ///
  /// When `false`, the path matching is case insensitive.  The route
  /// with `path: '/family/:fid'` will match `/FaMiLy/f2`.
  ///
  /// Defaults to `true`.
  final bool caseSensitive;

  // TODO(chunhtai): move all regex related help methods to path_utils.dart.
  /// Match this route against a location.
  RegExpMatch? matchPatternAsPrefix(String loc) {
    return _pathRE.matchAsPrefix('/$loc') as RegExpMatch? ??
        _pathRE.matchAsPrefix(loc) as RegExpMatch?;
  }

  /// Extract the path parameters from a match.
  Map<String, String> extractPathParams(RegExpMatch match) =>
      extractPathParameters(pathParameters, match);

  /// The path parameters in this route.
  // TODO(loic-sharma): Remove meta library prefix.
  // https://github.com/flutter/flutter/issues/171410
  @meta.internal
  final List<String> pathParameters = <String>[];

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('name', name));
    properties.add(StringProperty('path', path));
    properties.add(
      FlagProperty('redirect', value: redirectOnly, ifTrue: 'Redirect Only'),
    );
  }

  late final RegExp _pathRE;
}

abstract class ShellRouteBase extends RouteBase {
  const ShellRouteBase._({
    super.redirect,
    required super.routes,
    required super.parentNavigatorKey,
  }) : super._();

  static void _debugCheckSubRouteParentNavigatorKeys(
    List<RouteBase> subRoutes,
    GlobalKey<NavigatorState> navigatorKey,
  ) {
    for (final RouteBase route in subRoutes) {
      assert(
        route.parentNavigatorKey == null ||
            route.parentNavigatorKey == navigatorKey,
        "sub-route's parent navigator key must either be null or has the same navigator key as parent's key",
      );
      if (route is GoRoute && route.redirectOnly) {
        _debugCheckSubRouteParentNavigatorKeys(route.routes, navigatorKey);
      }
    }
  }

  Widget? buildWidget(
    BuildContext context,
    GoRouterState state,
    ShellRouteContext shellRouteContext,
  );

  Page<dynamic>? buildPage(
    BuildContext context,
    GoRouterState state,
    ShellRouteContext shellRouteContext,
  );

  GlobalKey<NavigatorState> navigatorKeyForSubRoute(RouteBase subRoute);
}

class ShellRouteContext {
  ShellRouteContext({
    required this.route,
    required this.routerState,
    required this.navigatorKey,
    required this.match,
    required this.routeMatchList,
    required this.navigatorBuilder,
  });

  final ShellRouteBase route;
  final GoRouterState routerState;
  final GlobalKey<NavigatorState> navigatorKey;
  final ShellRouteMatch match;
  final RouteMatchList routeMatchList;
  final NavigatorBuilder navigatorBuilder;

  Widget _buildNavigatorForCurrentRoute(
    List<NavigatorObserver>? observers,
    String? restorationScopeId,
  ) {
    return navigatorBuilder(
      navigatorKey,
      match,
      routeMatchList,
      observers,
      restorationScopeId,
    );
  }
}

class ShellRoute extends ShellRouteBase {
  ShellRoute({
    super.redirect,
    this.builder,
    this.pageBuilder,
    this.observers,
    required super.routes,
    super.parentNavigatorKey,
    GlobalKey<NavigatorState>? navigatorKey,
    this.restorationScopeId,
  }) : assert(routes.isNotEmpty),
       navigatorKey = navigatorKey ?? GlobalKey<NavigatorState>(),
       super._() {
    assert(() {
      ShellRouteBase._debugCheckSubRouteParentNavigatorKeys(
        routes,
        this.navigatorKey,
      );
      return true;
    }());
  }

  final ShellRouteBuilder? builder;
  final ShellRoutePageBuilder? pageBuilder;

  @override
  Widget? buildWidget(
    BuildContext context,
    GoRouterState state,
    ShellRouteContext shellRouteContext,
  ) {
    if (builder != null) {
      final Widget navigator = shellRouteContext._buildNavigatorForCurrentRoute(
        observers,
        restorationScopeId,
      );
      return builder!(context, state, navigator);
    }
    return null;
  }

  @override
  Page<dynamic>? buildPage(
    BuildContext context,
    GoRouterState state,
    ShellRouteContext shellRouteContext,
  ) {
    if (pageBuilder != null) {
      final Widget navigator = shellRouteContext._buildNavigatorForCurrentRoute(
        observers,
        restorationScopeId,
      );
      return pageBuilder!(context, state, navigator);
    }
    return null;
  }

  final List<NavigatorObserver>? observers;
  final GlobalKey<NavigatorState> navigatorKey;
  final String? restorationScopeId;

  @override
  GlobalKey<NavigatorState> navigatorKeyForSubRoute(RouteBase subRoute) {
    assert(routes.contains(subRoute));
    return navigatorKey;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      DiagnosticsProperty<GlobalKey<NavigatorState>>(
        'navigatorKey',
        navigatorKey,
      ),
    );
  }
}

class StatefulShellRoute extends ShellRouteBase {
  /// Constructs a [StatefulShellRoute] from a list of [StatefulShellBranch]es,
  /// each representing a separate nested navigation tree (branch).
  ///
  /// A separate [Navigator] will be created for each of the branches, using
  /// the navigator key specified in [StatefulShellBranch]. The Widget
  /// implementing the container for the branch Navigators is provided by
  /// [navigatorContainerBuilder].
  StatefulShellRoute({
    required this.branches,
    super.redirect,
    this.builder,
    this.pageBuilder,
    required this.navigatorContainerBuilder,
    super.parentNavigatorKey,
    this.restorationScopeId,
    GlobalKey<StatefulNavigationShellState>? key,
  }) : assert(branches.isNotEmpty),
       assert(
         (pageBuilder != null) || (builder != null),
         'One of builder or pageBuilder must be provided',
       ),
       assert(
         _debugUniqueNavigatorKeys(branches).length == branches.length,
         'Navigator keys must be unique',
       ),
       assert(_debugValidateParentNavigatorKeys(branches)),
       assert(_debugValidateRestorationScopeIds(restorationScopeId, branches)),
       _shellStateKey = key ?? GlobalKey<StatefulNavigationShellState>(),
       super._(routes: _routes(branches));

  /// Constructs a StatefulShellRoute that uses an [IndexedStack] for its
  /// nested [Navigator]s.
  ///
  /// This constructor provides an IndexedStack based implementation for the
  /// container ([navigatorContainerBuilder]) used to manage the Widgets
  /// representing the branch Navigators. Apart from that, this constructor
  /// works the same way as the default constructor.
  ///
  /// See [Stateful Nested Navigation](https://github.com/flutter/packages/blob/main/packages/go_router/example/lib/stacked_shell_route.dart)
  /// for a complete runnable example using StatefulShellRoute.indexedStack.
  StatefulShellRoute.indexedStack({
    required List<StatefulShellBranch> branches,
    GoRouterRedirect? redirect,
    StatefulShellRouteBuilder? builder,
    GlobalKey<NavigatorState>? parentNavigatorKey,
    StatefulShellRoutePageBuilder? pageBuilder,
    String? restorationScopeId,
    GlobalKey<StatefulNavigationShellState>? key,
  }) : this(
         branches: branches,
         redirect: redirect,
         builder: builder,
         pageBuilder: pageBuilder,
         parentNavigatorKey: parentNavigatorKey,
         restorationScopeId: restorationScopeId,
         navigatorContainerBuilder: _indexedStackContainerBuilder,
         key: key,
       );

  /// Restoration ID to save and restore the state of the navigator, including
  /// its history.
  final String? restorationScopeId;

  /// The widget builder for a stateful shell route.
  ///
  /// Similar to [GoRoute.builder], but with an additional
  /// [StatefulNavigationShell] parameter. StatefulNavigationShell is a Widget
  /// responsible for managing the nested navigation for the
  /// matching sub-routes. Typically, a shell route builds its shell around this
  /// Widget. StatefulNavigationShell can also be used to access information
  /// about which branch is active, and also to navigate to a different branch
  /// (using [StatefulNavigationShell.goBranch]).
  ///
  /// Custom implementations may choose to ignore the child parameter passed to
  /// the builder function, and instead use [StatefulNavigationShell] to
  /// create a custom container for the branch Navigators.
  final StatefulShellRouteBuilder? builder;

  /// The page builder for a stateful shell route.
  ///
  /// Similar to [GoRoute.pageBuilder], but with an additional
  /// [StatefulNavigationShell] parameter. StatefulNavigationShell is a Widget
  /// responsible for managing the nested navigation for the
  /// matching sub-routes. Typically, a shell route builds its shell around this
  /// Widget. StatefulNavigationShell can also be used to access information
  /// about which branch is active, and also to navigate to a different branch
  /// (using [StatefulNavigationShell.goBranch]).
  ///
  /// Custom implementations may choose to ignore the child parameter passed to
  /// the builder function, and instead use [StatefulNavigationShell] to
  /// create a custom container for the branch Navigators.
  final StatefulShellRoutePageBuilder? pageBuilder;

  /// The builder for the branch Navigator container.
  ///
  /// The function responsible for building the container for the branch
  /// Navigators. When this function is invoked, access is provided to a List of
  /// Widgets representing the branch Navigators, where the the index
  /// corresponds to the index of in [branches].
  ///
  /// The builder function is expected to return a Widget that ensures that the
  /// state of the branch Widgets is maintained, for instance by inducting them
  /// in the Widget tree.
  final ShellNavigationContainerBuilder navigatorContainerBuilder;

  /// Representations of the different stateful route branches that this
  /// shell route will manage.
  ///
  /// Each branch uses a separate [Navigator], identified
  /// [StatefulShellBranch.navigatorKey].
  final List<StatefulShellBranch> branches;

  final GlobalKey<StatefulNavigationShellState> _shellStateKey;

  @override
  Widget? buildWidget(
    BuildContext context,
    GoRouterState state,
    ShellRouteContext shellRouteContext,
  ) {
    if (builder != null) {
      return builder!(context, state, _createShell(context, shellRouteContext));
    }
    return null;
  }

  @override
  Page<dynamic>? buildPage(
    BuildContext context,
    GoRouterState state,
    ShellRouteContext shellRouteContext,
  ) {
    if (pageBuilder != null) {
      return pageBuilder!(
        context,
        state,
        _createShell(context, shellRouteContext),
      );
    }
    return null;
  }

  @override
  GlobalKey<NavigatorState> navigatorKeyForSubRoute(RouteBase subRoute) {
    final StatefulShellBranch? branch = branches.firstWhereOrNull(
      (StatefulShellBranch e) => e.routes.contains(subRoute),
    );
    assert(branch != null);
    return branch!.navigatorKey;
  }

  Iterable<GlobalKey<NavigatorState>> get _navigatorKeys =>
      branches.map((StatefulShellBranch b) => b.navigatorKey);

  StatefulNavigationShell _createShell(
    BuildContext context,
    ShellRouteContext shellRouteContext,
  ) => StatefulNavigationShell(
    shellRouteContext: shellRouteContext,
    router: GoRouter.of(context),
    containerBuilder: navigatorContainerBuilder,
  );

  static Widget _indexedStackContainerBuilder(
    BuildContext context,
    StatefulNavigationShell navigationShell,
    List<Widget> children,
  ) {
    return _IndexedStackedRouteBranchContainer(
      currentIndex: navigationShell.currentIndex,
      children: children,
    );
  }

  static List<RouteBase> _routes(List<StatefulShellBranch> branches) =>
      branches.expand((StatefulShellBranch e) => e.routes).toList();

  static Set<GlobalKey<NavigatorState>> _debugUniqueNavigatorKeys(
    List<StatefulShellBranch> branches,
  ) => Set<GlobalKey<NavigatorState>>.from(
    branches.map((StatefulShellBranch e) => e.navigatorKey),
  );

  static bool _debugValidateParentNavigatorKeys(
    List<StatefulShellBranch> branches,
  ) {
    for (final StatefulShellBranch branch in branches) {
      for (final RouteBase route in branch.routes) {
        if (route is GoRoute) {
          assert(
            route.parentNavigatorKey == null ||
                route.parentNavigatorKey == branch.navigatorKey,
          );
        }
      }
    }
    return true;
  }

  static bool _debugValidateRestorationScopeIds(
    String? restorationScopeId,
    List<StatefulShellBranch> branches,
  ) {
    if (branches
        .map((StatefulShellBranch e) => e.restorationScopeId)
        .nonNulls
        .isNotEmpty) {
      assert(
        restorationScopeId != null,
        'A restorationScopeId must be set for '
        'the StatefulShellRoute when using restorationScopeIds on one or more '
        'of the branches',
      );
    }
    return true;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      DiagnosticsProperty<Iterable<GlobalKey<NavigatorState>>>(
        'navigatorKeys',
        _navigatorKeys,
      ),
    );
  }
}

@immutable
class StatefulShellBranch {
  StatefulShellBranch({
    required this.routes,
    GlobalKey<NavigatorState>? navigatorKey,
    this.initialLocation,
    this.restorationScopeId,
    this.observers,
    this.preload = false,
  }) : navigatorKey = navigatorKey ?? GlobalKey<NavigatorState>() {
    assert(() {
      ShellRouteBase._debugCheckSubRouteParentNavigatorKeys(
        routes,
        this.navigatorKey,
      );
      return true;
    }());
  }

  final GlobalKey<NavigatorState> navigatorKey;

  final List<RouteBase> routes;

  final String? initialLocation;

  final String? restorationScopeId;

  final List<NavigatorObserver>? observers;

  final bool preload;

  GoRoute? get defaultRoute =>
      RouteBase.routesRecursively(routes).whereType<GoRoute>().firstOrNull;
}

typedef ShellNavigationContainerBuilder =
    Widget Function(
      BuildContext context,
      StatefulNavigationShell navigationShell,
      List<Widget> children,
    );

class StatefulNavigationShell extends StatefulWidget {
  StatefulNavigationShell({
    required this.shellRouteContext,
    required GoRouter router,
    required this.containerBuilder,
  }) : assert(shellRouteContext.route is StatefulShellRoute),
       _router = router,
       currentIndex = _indexOfBranchNavigatorKey(
         shellRouteContext.route as StatefulShellRoute,
         shellRouteContext.navigatorKey,
       ),
       super(
         key: (shellRouteContext.route as StatefulShellRoute)._shellStateKey,
       );

  final ShellRouteContext shellRouteContext;

  final GoRouter _router;

  final ShellNavigationContainerBuilder containerBuilder;

  final int currentIndex;

  StatefulShellRoute get route => shellRouteContext.route as StatefulShellRoute;

  void goBranch(int index, {bool initialLocation = false}) {
    final StatefulShellRoute route =
        shellRouteContext.route as StatefulShellRoute;
    final StatefulNavigationShellState? shellState =
        route._shellStateKey.currentState;
    if (shellState != null) {
      shellState.goBranch(index, initialLocation: initialLocation);
    } else {
      _router.go(_effectiveInitialBranchLocation(index));
    }
  }

  @visibleForTesting
  List<StatefulShellBranch> get debugLoadedBranches =>
      route._shellStateKey.currentState?._loadedBranches ??
      <StatefulShellBranch>[];

  String _effectiveInitialBranchLocation(int index) {
    final StatefulShellRoute route =
        shellRouteContext.route as StatefulShellRoute;
    final StatefulShellBranch branch = route.branches[index];
    final String? initialLocation = branch.initialLocation;
    if (initialLocation != null) {
      return initialLocation;
    } else {
      final GoRoute route = branch.defaultRoute!;
      final List<String> parameters = <String>[];
      patternToRegExp(
        route.path,
        parameters,
        caseSensitive: route.caseSensitive,
      );
      assert(parameters.isEmpty);
      final String fullPath = _router.configuration.locationForRoute(route)!;
      return patternToPath(
        fullPath,
        shellRouteContext.routerState.pathParameters,
      );
    }
  }

  @override
  State<StatefulWidget> createState() => StatefulNavigationShellState();

  static StatefulNavigationShellState of(BuildContext context) {
    final StatefulNavigationShellState? shellState =
        context.findAncestorStateOfType<StatefulNavigationShellState>();
    assert(shellState != null);
    return shellState!;
  }

  static StatefulNavigationShellState? maybeOf(BuildContext context) {
    final StatefulNavigationShellState? shellState =
        context.findAncestorStateOfType<StatefulNavigationShellState>();
    return shellState;
  }

  static int _indexOfBranchNavigatorKey(
    StatefulShellRoute route,
    GlobalKey<NavigatorState> navigatorKey,
  ) {
    final int index = route.branches.indexWhere(
      (StatefulShellBranch branch) => branch.navigatorKey == navigatorKey,
    );
    assert(index >= 0);
    return index;
  }
}

class StatefulNavigationShellState extends State<StatefulNavigationShell>
    with RestorationMixin {
  final Map<StatefulShellBranch, _StatefulShellBranchState> _branchState =
      <StatefulShellBranch, _StatefulShellBranchState>{};

  StatefulShellRoute get route => widget.route;

  GoRouter get _router => widget._router;

  bool _isBranchLoaded(StatefulShellBranch branch) =>
      _branchState[branch] != null;

  List<StatefulShellBranch> get _loadedBranches => _branchState.keys.toList();

  @override
  String? get restorationId => route.restorationScopeId;

  String _branchLocationRestorationScopeId(StatefulShellBranch branch) {
    return branch.restorationScopeId != null
        ? '${branch.restorationScopeId}-location'
        : identityHashCode(branch).toString();
  }

  _StatefulShellBranchState _branchStateFor(
    StatefulShellBranch branch, [
    bool register = true,
  ]) {
    return _branchState.putIfAbsent(branch, () {
      final _StatefulShellBranchState branchState = _StatefulShellBranchState(
        location: _RestorableRouteMatchList(_router.configuration),
      );
      if (register) {
        registerForRestoration(
          branchState.location,
          _branchLocationRestorationScopeId(branch),
        );
      }
      return branchState;
    });
  }

  RouteMatchList? _matchListForBranch(int index) =>
      _branchState[route.branches[index]]?.location.value;

  RouteMatchList _scopedMatchList(RouteMatchList matchList) {
    return matchList.copyWith(matches: _scopeMatches(matchList.matches));
  }

  List<RouteMatchBase> _scopeMatches(List<RouteMatchBase> matches) {
    final List<RouteMatchBase> result = <RouteMatchBase>[];
    for (final RouteMatchBase match in matches) {
      if (match is ShellRouteMatch) {
        if (match.route == route) {
          result.add(match);
          break;
        }
        result.add(match.copyWith(matches: _scopeMatches(match.matches)));
        continue;
      }
      result.add(match);
    }
    return result;
  }

  void _updateCurrentBranchStateFromWidget() {
    _preloadBranches();

    final StatefulShellBranch branch = route.branches[widget.currentIndex];
    final ShellRouteContext shellRouteContext = widget.shellRouteContext;
    final RouteMatchList currentBranchLocation = _scopedMatchList(
      shellRouteContext.routeMatchList,
    );

    final _StatefulShellBranchState branchState = _branchStateFor(
      branch,
      false,
    );
    final RouteMatchList previousBranchLocation = branchState.location.value;
    branchState.location.value = currentBranchLocation;
    final bool hasExistingNavigator = branchState.navigator != null;

    final bool locationChanged =
        previousBranchLocation != currentBranchLocation;
    if (locationChanged || !hasExistingNavigator) {
      branchState.navigator = shellRouteContext._buildNavigatorForCurrentRoute(
        branch.observers,
        branch.restorationScopeId,
      );
    }

    _cleanUpObsoleteBranches();
  }

  void _preloadBranches() {
    for (int i = 0; i < route.branches.length; i++) {
      final StatefulShellBranch branch = route.branches[i];
      if (i != currentIndex && branch.preload && !_isBranchLoaded(branch)) {
        final RouteMatchList matchList = _router.configuration.findMatch(
          Uri.parse(widget._effectiveInitialBranchLocation(i)),
        );
        ShellRouteMatch? match;
        matchList.visitRouteMatches((RouteMatchBase e) {
          match = e is ShellRouteMatch && e.route == route ? e : match;
          return match == null;
        });
        assert(match != null);

        final Widget navigator = widget.shellRouteContext.navigatorBuilder(
          branch.navigatorKey,
          match!,
          matchList,
          branch.observers,
          branch.restorationScopeId,
        );

        final _StatefulShellBranchState branchState = _branchStateFor(
          branch,
          false,
        );
        branchState.location.value = matchList;
        branchState.navigator = navigator;
      }
    }
  }

  void _cleanUpObsoleteBranches() {
    _branchState.removeWhere((
      StatefulShellBranch branch,
      _StatefulShellBranchState branchState,
    ) {
      if (!route.branches.contains(branch)) {
        branchState.dispose();
        return true;
      }
      return false;
    });
  }

  int get currentIndex => widget.currentIndex;

  void goBranch(int index, {bool initialLocation = false}) {
    assert(index >= 0 && index < route.branches.length);
    final RouteMatchList? matchList =
        initialLocation ? null : _matchListForBranch(index);
    if (matchList != null && matchList.isNotEmpty) {
      _router.restore(matchList);
    } else {
      _router.go(widget._effectiveInitialBranchLocation(index));
    }
  }

  @override
  void initState() {
    super.initState();
    _updateCurrentBranchStateFromWidget();
  }

  @override
  void dispose() {
    super.dispose();
    for (final _StatefulShellBranchState branchState in _branchState.values) {
      branchState.dispose();
    }
  }

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    route.branches.forEach(_branchStateFor);
  }

  @override
  void didUpdateWidget(covariant StatefulNavigationShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateCurrentBranchStateFromWidget();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> children =
        route.branches
            .map(
              (StatefulShellBranch branch) => _BranchNavigatorProxy(
                key: ObjectKey(branch),
                branch: branch,
                navigatorForBranch:
                    (StatefulShellBranch branch) =>
                        _branchState[branch]?.navigator,
              ),
            )
            .toList();

    return widget.containerBuilder(context, widget, children);
  }
}

class _StatefulShellBranchState {
  _StatefulShellBranchState({required this.location});

  Widget? navigator;
  final _RestorableRouteMatchList location;

  void dispose() {
    location.dispose();
  }
}

class _RestorableRouteMatchList extends RestorableProperty<RouteMatchList> {
  _RestorableRouteMatchList(RouteConfiguration configuration)
    : _matchListCodec = RouteMatchListCodec(configuration);

  final RouteMatchListCodec _matchListCodec;

  RouteMatchList get value => _value;
  RouteMatchList _value = RouteMatchList.empty;
  set value(RouteMatchList newValue) {
    if (newValue != _value) {
      _value = newValue;
      notifyListeners();
    }
  }

  @override
  void initWithValue(RouteMatchList value) {
    _value = value;
  }

  @override
  RouteMatchList createDefaultValue() => RouteMatchList.empty;

  @override
  RouteMatchList fromPrimitives(Object? data) {
    return data == null
        ? RouteMatchList.empty
        : _matchListCodec.decode(data as Map<Object?, Object?>);
  }

  @override
  Object? toPrimitives() {
    if (value.isNotEmpty) {
      return _matchListCodec.encode(value);
    }
    return null;
  }
}

typedef _NavigatorForBranch = Widget? Function(StatefulShellBranch);

class _BranchNavigatorProxy extends StatefulWidget {
  const _BranchNavigatorProxy({
    super.key,
    required this.branch,
    required this.navigatorForBranch,
  });

  final StatefulShellBranch branch;
  final _NavigatorForBranch navigatorForBranch;

  @override
  State<StatefulWidget> createState() => _BranchNavigatorProxyState();
}

class _BranchNavigatorProxyState extends State<_BranchNavigatorProxy>
    with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.navigatorForBranch(widget.branch) ?? const SizedBox.shrink();
  }

  @override
  bool get wantKeepAlive => true;
}

class _IndexedStackedRouteBranchContainer extends StatelessWidget {
  const _IndexedStackedRouteBranchContainer({
    required this.currentIndex,
    required this.children,
  });

  final int currentIndex;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final List<Widget> stackItems =
        children
            .mapIndexed(
              (int index, Widget child) => _buildRouteBranchContainer(
                context,
                currentIndex == index,
                child,
              ),
            )
            .toList();

    return IndexedStack(index: currentIndex, children: stackItems);
  }

  Widget _buildRouteBranchContainer(
    BuildContext context,
    bool isActive,
    Widget child,
  ) {
    return Offstage(
      offstage: !isActive,
      child: TickerMode(enabled: isActive, child: child),
    );
  }
}
