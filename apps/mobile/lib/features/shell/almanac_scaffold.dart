/// The persistent app shell: a body, the floating nav island, and the
/// assistant button docked into it.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../assistant/assistant_sheet.dart';
import 'bottom_nav_island.dart';

/// Wraps a screen in the shell.
///
/// The island is an overlay rather than a `bottomNavigationBar`, because the
/// design requires content to scroll *underneath* it — that is the whole point
/// of the glass. Screens leave [BottomNavIsland.bottomInset] clear at the foot
/// of their scroll view so nothing is trapped beneath it.
class AlmanacScaffold extends StatelessWidget {
  final Widget body;
  final NavDestination destination;

  /// Zone Detail is reached from Home but belongs to Farm, and the island
  /// should say so. Passing the destination explicitly is how.
  const AlmanacScaffold({
    super.key,
    required this.body,
    required this.destination,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    // The body deliberately extends behind the island.
    extendBody: true,
    body: body,
    bottomNavigationBar: SafeArea(
      top: false,
      child: SizedBox(
        // The island's own 64 plus its 16 of bottom inset, and enough above it
        // for the assistant button's top half and its word to ride proud.
        height: 112,
        child: Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            BottomNavIsland(
              current: destination,
              onSelect: (d) {
                if (d == destination) return;
                context.go(d.route);
              },
            ),
            AIActionButton(onPressed: () => showAssistantSheet(context)),
          ],
        ),
      ),
    ),
  );
}
