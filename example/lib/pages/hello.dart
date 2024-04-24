import 'package:flutter/material.dart';
import 'package:odroe/odroe.dart';

Widget hello() => setup(() {
      final name = $state<String>('Odroe!');

      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Hello ${name.get()}'),
              TextFormField(
                initialValue: name.get(),
                onChanged: name.set,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'Please enter your name',
                ),
                autofocus: true,
              ),
            ],
          ),
        ),
      );
    });
