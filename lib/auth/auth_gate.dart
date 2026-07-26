import 'package:flutter/material.dart';

import '../network/api_client.dart';
import 'login_screen.dart';
import 'mobile_auth_service.dart';

class AuthGate extends StatefulWidget {
  final Widget child;

  const AuthGate({
    super.key,
    required this.child,
  });

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _authService = MobileAuthService();

  bool _isLoading = true;
  bool _isAuthorized = false;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    await ApiClient.init();

    final isAuthorized = await _authService.hasSavedSession();

    if (!mounted) return;

    setState(() {
      _isAuthorized = isAuthorized;
      _isLoading = false;
    });
  }

  void _onLoggedIn() {
    setState(() {
      _isAuthorized = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isAuthorized) {
      return LoginScreen(onLoggedIn: _onLoggedIn);
    }

    return widget.child;
  }
}
