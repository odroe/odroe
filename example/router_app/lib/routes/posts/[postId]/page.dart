import 'package:flutter/material.dart';
import 'package:odroe/router.dart';

import 'route.dart' as definition;

final route = definition.route.page(
  build: (context) => Center(
    child: Text(
      'Post ${context.params.postId}; '
      'preview=${context.search.preview}; '
      'tags=${context.search.tags.join(',')}',
    ),
  ),
);
