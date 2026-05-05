import 'package:flutter/material.dart';
import 'package:logis_agent/pages/home.dart';
import 'package:logis_agent/pages/login.dart';
import 'package:logis_agent/services/auth_service.dart';

class Splash extends StatelessWidget {
  const Splash({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: AuthService.instance.restoreSession(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final session = AuthService.instance.session;
        if (session != null) {
          return const Home();
        }

        return const Login();
      },
    );
  }
}
