import 'package:flutter/material.dart';
import 'package:odroe/router_flutter.dart';

import '../routes.dart';
import 'route.dart' as definition;

final route = definition.route.page(
  build: (context) => Center(
    child: FilledButton(
      onPressed: () => context.router.go(
        routes.posts.postId.to(
          params: (postId: 42),
          search: (preview: true, tags: const <String>['flutter', 'dart']),
        ),
      ),
      child: const Text('Open post 42'),
    ),
  ),
);
