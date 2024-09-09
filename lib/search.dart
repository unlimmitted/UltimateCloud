import 'package:flutter/material.dart';

class SearchContainer extends StatelessWidget {
  const SearchContainer({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(20),
      child: Column(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: const Text(
              'Search',
              style: TextStyle(fontSize: 20),
            ),
          ),
          TextFormField(
            decoration: const InputDecoration(
                hintText: 'Type name'
            ),
          )
        ],
      ),
    );
  }
}