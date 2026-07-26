import 'package:flutter/material.dart';

import 'auth/mobile_auth_service.dart';

class SettingsContainer extends StatelessWidget {
  const SettingsContainer({super.key});

  Future<void> _logout(BuildContext context) async {
    await MobileAuthService().logout();

    if (!context.mounted) return;

    Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Выйти'),
              onTap: () => _logout(context),
            ),
          ],
        ),
      ),
    );
  }
}
