import 'package:flutter/material.dart';
import 'package:librascam/app_controller.dart';

class HomePage extends StatefulWidget{
  const HomePage({super.key});


  @override
  State<HomePage> createState() {
    return HomePageState();
  }

}

class HomePageState extends State<HomePage> {

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: ListView(
          children: [
            Container(
              height:20,
            ),
            const Center(
              child: Column(
                children: [
                  Text(
                    "LibrasCam",
                    style: TextStyle(
                      color: Colors.black,
                      fontFamily: 'Monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 40, 
                    ),
                  ),
                  Divider(
                    color: Colors.black,
                    thickness: 4,
                  ),
                ],
              ),
            ),
            const SizedBox(
              height: 20,
            ),
            const Center(
              child: Text(
                "Bem vindo ao LibrasCam",
                style: TextStyle(
                  fontSize: 25, 
                ),
              ),
            ),
            const SizedBox(
              height: 40,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(
                  width: 80,
                  height: 80,
                  child: Image.asset('assets/images/homem.png'),
                ),
                const SizedBox(
                  width: 60,
                ),
              ],
            ),
            const SizedBox(
              height: 40,
            ),
            SizedBox(
              width: 40,
              height: 40,
              child: Image.asset('assets/images/seta.png'),
            ),
            const SizedBox(
              height: 40,
            ),
            Row(
              children: [
                const SizedBox(
                  width: 60,
                ),
                SizedBox(
                  width: 80,
                  height: 80,
                  child: Image.asset('assets/images/mao.png'),
                ),
              ],
            ),
            const SizedBox(
              height: 40,
            ),
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  "Clique no botão abaixo para abrir a câmera do seu celular e traduzir gestos da língua brasileira de sinais!",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(
              height: 20,
            ),
            Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pushNamed('/camera');
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
                ),
                child: SizedBox(
                  width: 100,
                  height: 100,
                  child: Image.asset('assets/images/camera.png'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CustomSwitch extends StatelessWidget {
  const CustomSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    return Switch(
      value: AppController.instance.darkTheme,
      onChanged: (value){
        AppController.instance.changeTheme();
      },
      activeColor: const Color.fromARGB(255, 5, 125, 10),
    );
  }
}