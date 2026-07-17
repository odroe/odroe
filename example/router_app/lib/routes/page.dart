import 'package:flutter/material.dart';
import 'package:odroe/router.dart';

import '../routes.dart';

final route = pageRoute(
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
