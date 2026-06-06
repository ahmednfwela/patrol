import 'package:e2e_app/keys.dart';
import 'package:flutter/material.dart';

class AtFinderScreen extends StatefulWidget {
  const AtFinderScreen({super.key});

  @override
  State<AtFinderScreen> createState() => _AtFinderScreenState();
}

class _AtFinderScreenState extends State<AtFinderScreen> {
  var _firstItemTapped = 0;
  var _secondItemTapped = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('at() finder')),
      body: ListView(
        children: [
          AtFinderItem(
            onTap: () {
              setState(() {
                _firstItemTapped++;
              });
            },
          ),
          AtFinderItem(
            onTap: () {
              setState(() {
                _secondItemTapped++;
              });
            },
          ),
          if (_secondItemTapped > 0)
            Text(
              'Second item tapped $_secondItemTapped',
              key: K.atFinderSecondItemTapped,
            ),
          if (_firstItemTapped > 0)
            Text(
              'First item tapped $_firstItemTapped',
              key: K.atFinderFirstItemTapped,
            ),
        ],
      ),
    );
  }
}

class AtFinderItem extends StatelessWidget {
  const AtFinderItem({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(key: K.atFinderItem, title: Text('Item'), onTap: onTap);
  }
}
