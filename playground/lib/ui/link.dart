import 'package:flutter/material.dart';
import 'package:odroe/odroe.dart';
import 'package:odroe/ui.dart';

Widget linkExample() => setup(() {
      return () => Scaffold(
            body: Center(child: link('Link', disabled: false)),
          );
    });
