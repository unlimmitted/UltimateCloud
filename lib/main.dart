import 'package:flutter/material.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:media_kit/media_kit.dart';
import 'package:ultimate_cloud/last_views.dart';
import 'package:ultimate_cloud/search.dart';
import 'package:ultimate_cloud/files.dart';
import 'package:ultimate_cloud/settings.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(
    const MaterialApp(
      home: App(),
    ),
  );
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Navigation(),
    );
  }
}

class Navigation extends StatefulWidget {
  const Navigation({super.key});

  @override
  State<Navigation> createState() => _NavigationState();
}

class _NavigationState extends State<Navigation> {
  int _selectedIndex = 0;

  late final List<Widget> _widgetOptions;
  final GlobalKey<FilesScreenState> _filesScreenKey = GlobalKey<FilesScreenState>();

  @override
  void initState() {
    super.initState();

    _widgetOptions = [
      FilesScreen(key: _filesScreenKey),
      const LastViewsContent(),
      const SearchContainer(),
      const SettingsContainer(),
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Widget? _buildFab() {
    if (_selectedIndex == 0) {
      return SpeedDial(
        animatedIcon: AnimatedIcons.menu_close,
        backgroundColor: Colors.grey[300],
        overlayOpacity: 0.1,
        children: [
          SpeedDialChild(
            child: const Icon(Icons.cloud_upload),
            label: 'Загрузить файл',
            onTap: _filesScreenKey.currentState?.uploadFile,
          ),
          SpeedDialChild(
            child: const Icon(Icons.create_new_folder),
            label: 'Создать папку',
            onTap: () => _filesScreenKey.currentState?.showCreateFolderDialog(context),
          ),
        ],
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _widgetOptions.elementAt(_selectedIndex),
      floatingActionButton: _buildFab(),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.insert_drive_file_sharp),
            label: 'My files',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'Last views',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: 'Search',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.black,
        unselectedItemColor: Colors.black54,
        onTap: _onItemTapped,
      ),
    );
  }
}
