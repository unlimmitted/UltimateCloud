import 'package:flutter/material.dart';

class FilesContent extends StatelessWidget {
  const FilesContent({super.key});

  static const String imageUrl =
      'https://media1.giphy.com/media/v1.Y2lkPTc5MGI3NjExYTJpYTRkMGZwM2RkN2hsMGRicXY2YjNnYmhncmIxZ2RxNGVoZHp5NSZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9Zw/iHmodiTc8t0BO/giphy.webp';

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(20),
          child: Column(
            children: List.generate(15, (index) => const ImageWithText()),
          ),
        ),
      ),
    );
  }
}

class ImageWithText extends StatelessWidget {
  const ImageWithText({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(5),
      child: const Column(
        children: [
          Image(
            image: NetworkImage(FilesContent.imageUrl),
          ),
          SizedBox(height: 5),
          Text(
            'Text',
            style: TextStyle(fontSize: 16),
          ),
        ],
      ),
    );
  }
}