import 'package:flutter/material.dart';
import 'package:odroe/store.dart';

final lightThemeStore = writeable(ThemeData());
final darkThemeStore = writeable(ThemeData.dark());
final modeThemeStore = writeable(ThemeMode.system);
