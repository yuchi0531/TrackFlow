import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:trackflow/presentation/tracking_list/tracking_list_page.dart';
import 'package:trackflow/presentation/settings/settings_page.dart';
import 'package:trackflow/presentation/add_tracking/add_tracking_page.dart';
import 'package:trackflow/presentation/detail/detail_page.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) {
        final location = state.matchedLocation;

        int selectedIndex = 0;
        if (location == '/settings') {
          selectedIndex = 1;
        }

        return Scaffold(
          body: child,
          bottomNavigationBar: NavigationBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) {
              switch (index) {
                case 0:
                  context.go('/');
                case 1:
                  context.go('/settings');
              }
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.inventory_2_outlined),
                label: '追跡一覧',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                label: '設定',
              ),
            ],
          ),
        );
      },
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const TrackingListPage(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsPage(),
        ),
      ],
    ),
    GoRoute(
      path: '/add',
      builder: (context, state) => const AddTrackingPage(),
    ),
    GoRoute(
      path: '/detail/:trackingNumber',
      builder: (context, state) => DetailPage(
        trackingNumber: state.pathParameters['trackingNumber'] ?? '',
        carrier: state.uri.queryParameters['carrier'] ?? 'japanPost',
      ),
    ),
  ],
);
