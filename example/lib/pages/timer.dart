import 'dart:async';

import 'package:flutter/material.dart';
import 'package:odroe/odroe.dart';

Widget timer() => setup(() {
      final now = $state(DateTime.now());

      $effect(() {
        final timer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!timer.isActive) return;

          now.set(DateTime.now());
        });

        return timer.cancel;
      });

      return Scaffold(
        appBar: AppBar(title: const Text('Timer')),
        body: Center(
          child: Text('now: ${now.get()}'),
        ),
      );
    });
