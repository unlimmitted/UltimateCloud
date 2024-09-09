import 'package:flutter/material.dart';

void main() => runApp(App());

class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        primaryColor: Colors.white,
        fontFamily: 'Inter',
      ),
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: const Text(
            'UltimateCloud',
            style: TextStyle(fontSize: 30),
          ),
        ),
        body: const MainContent(),
      ),
    );
  }
}

class MainContent extends StatelessWidget {
  const MainContent({Key? key}) : super(key: key);

  static const String imageUrl =
      'https://media2.giphy.com/media/v1.Y2lkPTc5MGI3NjExOHZjZnNoaGlnam05NnJmYnNodHBscGhvcGRjaDVjaThwaDJycWcycCZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9Zw/SMZlv6CzzUXqU/giphy.webp';

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Center(
        child: Container(
          child: Column(
            children: List.generate(15, (index) => ImageContainer()),
          ),
        ),
      ),
    );
  }
}

class ImageContainer extends StatelessWidget {
  const ImageContainer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(5),
      child: const Image(
        image: NetworkImage(MainContent.imageUrl),
      ),
    );
  }
}
