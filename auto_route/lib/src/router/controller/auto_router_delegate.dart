part of 'routing_controller.dart';

/// An auto_route implementation for [RouterDelegate]
class AutoRouterDelegate extends RouterDelegate<UrlState> with ChangeNotifier {
  /// This initial list of routes
  /// overrides default-initial paths e.g => AutoRoute(path:'/')
  /// overrides initial paths coming from platform e.g browser's address bar
  ///
  /// Using this is not recommended if your App uses deep-links
  /// unless you know what you're doing.
  final List<PageRouteInfo>? initialRoutes;

  /// This initial path
  /// overrides default-initial paths e.g => AutoRoute(path:'/')
  /// overrides initial paths coming from platform e.g browser's address bar
  ///
  /// (NOTE): Flutter reports platform deep-links directly now
  ///
  /// Using this is not recommended if your App uses deep-links
  /// unless you know what you're doing.
  final String? initialDeepLink;

  /// An object that provides pages stack to [Navigator.pages]
  /// and wraps a navigator key to handle stack navigation actions
  final StackRouter controller;

  /// Passed to [Navigator.restorationScopeId]
  final String? navRestorationScopeId;

  /// A builder function that returns a list of observes
  ///
  /// Why isn't this a list of navigatorObservers?
  /// The reason for that is a [NavigatorObserver] instance can only
  /// be used by a single [Navigator], so unless you're using a one
  /// single router or you don't want your nested routers to inherit
  /// observers make sure navigatorObservers builder always returns
  /// fresh observer instances.
  final NavigatorObserversBuilder navigatorObservers;

  /// A builder for the placeholder page that is shown
  /// before the first route can be rendered. Defaults to
  /// an empty page with [Theme.scaffoldBackgroundColor].
  WidgetBuilder? placeholder;

  /// Builds an empty observers list
  static List<NavigatorObserver> defaultNavigatorObserversBuilder() => const [];

  /// Looks up and casts the scoped [Router] to [AutoRouterDelegate]
  static AutoRouterDelegate of(BuildContext context) {
    final delegate = Router.of(context).routerDelegate;
    assert(delegate is AutoRouterDelegate);
    return delegate as AutoRouterDelegate;
  }

  /// Forces a url update
  static reportUrlChanged(BuildContext context, String url) {
    Router.of(context)
        .routeInformationProvider
        ?.routerReportsNewRouteInformation(
          RouteInformation(location: url),
          type: RouteInformationReportingType.navigate,
        );
  }

  @override
  Future<bool> popRoute() async => controller.popTop();

  late List<NavigatorObserver> _navigatorObservers;

  /// Default constructor
  AutoRouterDelegate(
    this.controller, {
    this.initialRoutes,
    this.placeholder,
    this.navRestorationScopeId,
    this.initialDeepLink,
    this.navigatorObservers = defaultNavigatorObserversBuilder,
  }) : assert(initialDeepLink == null || initialRoutes == null) {
    _navigatorObservers = navigatorObservers();
    controller.navigationHistory.addListener(_handleRebuild);
  }

  /// Builds a [_DeclarativeAutoRouterDelegate] which uses
  /// a declarative list of routes to update navigator stack
  factory AutoRouterDelegate.declarative(
    RootStackRouter controller, {
    required RoutesBuilder routes,
    String? navRestorationScopeId,
    String? initialDeepLink,
    RoutePopCallBack? onPopRoute,
    OnNavigateCallBack? onNavigate,
    NavigatorObserversBuilder navigatorObservers,
  }) = _DeclarativeAutoRouterDelegate;

  /// Helper to access current urlState
  UrlState get urlState => controller.navigationHistory.urlState;

  @override
  UrlState? get currentConfiguration => urlState;

  @override
  Future<void> setInitialRoutePath(UrlState configuration) {
    // setInitialRoutePath is re-fired on enabling
    // select widget mode from flutter inspector,
    // this check is preventing it from rebuilding the app
    if (controller.hasEntries) {
      return SynchronousFuture(null);
    }

    if (initialRoutes?.isNotEmpty == true) {
      return controller.pushAll(initialRoutes!);
    } else if (initialDeepLink != null) {
      return controller.pushNamed(initialDeepLink!, includePrefixMatches: true);
    } else if (configuration.hasSegments) {
      _onNewUrlState(configuration);
      return controller.navigateAll(configuration.segments);
    } else {
      throw FlutterError("Can not resolve initial route");
    }
  }

  @override
  Future<void> setNewRoutePath(UrlState configuration) {
    final topMost = controller.topMostRouter();
    if (topMost is StackRouter && topMost.hasPagelessTopRoute) {
      topMost.popUntil((route) => route.settings is Page);
    }

    if (configuration.hasSegments) {
      _onNewUrlState(configuration);
      return controller.navigateAll(configuration.segments);
    }

    notifyListeners();
    return SynchronousFuture(null);
  }

  void _onNewUrlState(UrlState state) {
    final pathInBrowser = state.uri.path;
    var matchedUrlState = state.flatten;
    if (pathInBrowser != matchedUrlState.path) {
      matchedUrlState = matchedUrlState.copyWith(shouldReplace: true);
    }
    controller.navigationHistory.onNewUrlState(matchedUrlState);
  }

  @override
  Widget build(BuildContext context) => _AutoRootRouter(
        router: controller,
        navigatorObservers: _navigatorObservers,
        navigatorObserversBuilder: navigatorObservers,
        navRestorationScopeId: navRestorationScopeId,
        placeholder: placeholder,
      );

  void _handleRebuild() {
    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
    removeListener(_handleRebuild);
    controller.dispose();
  }

  /// Force this delegate to rebuild
  void notifyUrlChanged() => _handleRebuild();
}

class _AutoRootRouter extends StatefulWidget {
  const _AutoRootRouter({
    Key? key,
    required this.router,
    this.navRestorationScopeId,
    this.navigatorObservers = const [],
    required this.navigatorObserversBuilder,
    this.placeholder,
  }) : super(key: key);
  final StackRouter router;
  final String? navRestorationScopeId;
  final List<NavigatorObserver> navigatorObservers;
  final NavigatorObserversBuilder navigatorObserversBuilder;

  /// A builder for the placeholder page that is shown
  /// before the first route can be rendered. Defaults to
  /// an empty page with [Theme.scaffoldBackgroundColor].
  final WidgetBuilder? placeholder;

  @override
  _AutoRootRouterState createState() => _AutoRootRouterState();
}

class _AutoRootRouterState extends State<_AutoRootRouter> {
  StackRouter get router => widget.router;

  @override
  void initState() {
    super.initState();
    router.addListener(_handleRebuild);
  }

  @override
  void dispose() {
    super.dispose();
    router.removeListener(_handleRebuild);
  }

  void _handleRebuild() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final stateHash = router.stateHash;
    return RouterScope(
      controller: router,
      navigatorObservers: widget.navigatorObservers,
      inheritableObserversBuilder: widget.navigatorObserversBuilder,
      stateHash: stateHash,
      child: StackRouterScope(
        stateHash: stateHash,
        controller: router,
        child: AutoRouteNavigator(
          router: router,
          placeholder: widget.placeholder,
          navRestorationScopeId: widget.navRestorationScopeId,
          navigatorObservers: widget.navigatorObservers,
        ),
      ),
    );
  }
}

class _DeclarativeAutoRouterDelegate extends AutoRouterDelegate {
  final RoutesBuilder routes;
  final RoutePopCallBack? onPopRoute;
  final OnNavigateCallBack? onNavigate;

  _DeclarativeAutoRouterDelegate(
    RootStackRouter router, {
    required this.routes,
    String? navRestorationScopeId,
    String? initialDeepLink,
    this.onPopRoute,
    this.onNavigate,
    NavigatorObserversBuilder navigatorObservers =
        AutoRouterDelegate.defaultNavigatorObserversBuilder,
  }) : super(
          router,
          navRestorationScopeId: navRestorationScopeId,
          navigatorObservers: navigatorObservers,
          initialDeepLink: initialDeepLink,
        ) {
    router._managedByWidget = true;
  }

  @override
  Future<void> setInitialRoutePath(UrlState tree) {
    if (initialDeepLink != null) {
      final routes = controller.buildPageRoutesStack(initialDeepLink!);
      controller.pendingRoutesHandler._setPendingRoutes(routes);
    } else if (tree.hasSegments) {
      final routes = tree.segments.map((e) => e.toPageRouteInfo()).toList();
      controller.pendingRoutesHandler._setPendingRoutes(routes);
    }
    return SynchronousFuture(null);
  }

  @override
  Future<void> setNewRoutePath(UrlState tree) async {
    return _onNavigate(tree);
  }

  Future<void> _onNavigate(UrlState tree) {
    if (tree.hasSegments) {
      controller.navigateAll(tree.segments);
    }
    if (onNavigate != null) {
      onNavigate!(tree);
    }

    return SynchronousFuture(null);
  }

  @override
  Widget build(BuildContext context) {
    final stateHash = controller.stateHash;
    return RouterScope(
      controller: controller,
      inheritableObserversBuilder: navigatorObservers,
      stateHash: stateHash,
      navigatorObservers: _navigatorObservers,
      child: StackRouterScope(
        controller: controller,
        stateHash: stateHash,
        child: AutoRouteNavigator(
          router: controller,
          declarativeRoutesBuilder: routes,
          navRestorationScopeId: navRestorationScopeId,
          navigatorObservers: _navigatorObservers,
          didPop: onPopRoute,
        ),
      ),
    );
  }
}
