import 'package:flutter/material.dart';

class LoginPage extends StatefulWidget {

  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();

}

class _LoginPageState extends State<LoginPage> {

  Widget _body() {
    return SingleChildScrollView(
      child: SizedBox(
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height,
        child: Padding(
          padding: const EdgeInsets.only(
            left: 12, right: 12, top: 12, bottom: 12
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 150,
                height: 150,
                child: Image.asset('assets/images/logo.png'),
              ),
              const SizedBox(
                height: 10,
              ),
              const Text(
                "LibrasCam",
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'Monospace',
                  fontWeight: FontWeight.bold,
                  fontSize: 40, 
                ),
              ),
              const SizedBox(
                height: 40,
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pushNamed('/home');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: const Text(
                    'Iniciar',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                    ),
                  ),
                ), 
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
            Container(
              color: const Color.fromRGBO(61, 109, 147, 1),
            ),
          _body(),
        ],
      ),
    );
  }
}