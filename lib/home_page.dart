import 'package:flutter/material.dart';
import 'package:librascam/app_controller.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() {
    return HomePageState();
  }
}

class HomePageState extends State<HomePage> {
  @override
  Widget build(BuildContext context) {
    // Obter dimensões da tela
    final screenSize = MediaQuery.sizeOf(context);
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;
    
    // Calcular tamanhos proporcionais
    final titleFontSize = screenWidth * 0.1; // 10% da largura
    final welcomeFontSize = screenWidth * 0.055; // 5.5% da largura
    final descriptionFontSize = screenWidth * 0.045; // 4.5% da largura
    final imageSize = screenWidth * 0.18; // 18% da largura
    final arrowSize = screenWidth * 0.09; // 9% da largura
    final cameraButtonSize = screenWidth * 0.25; // 25% da largura
    final horizontalPadding = screenWidth * 0.15; // 15% da largura
    
    return Scaffold(
      body: SafeArea(
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: ListView(
            padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.04),
            children: [
              SizedBox(height: screenHeight * 0.02),
              Center(
                child: Column(
                  children: [
                    Text(
                      "LibrasCam",
                      style: TextStyle(
                        color: Colors.black,
                        fontFamily: 'Monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: titleFontSize.clamp(30.0, 50.0),
                      ),
                    ),
                    const Divider(
                      color: Colors.black,
                      thickness: 4,
                    ),
                  ],
                ),
              ),
              SizedBox(height: screenHeight * 0.025),
              Center(
                child: Text(
                  "Bem vindo ao LibrasCam",
                  style: TextStyle(
                    fontSize: welcomeFontSize.clamp(20.0, 35.0),
                  ),
                ),
              ),
              SizedBox(height: screenHeight * 0.04),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(
                    width: imageSize,
                    height: imageSize,
                    child: Image.asset(
                      'assets/images/homem.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                  SizedBox(width: horizontalPadding),
                ],
              ),
              SizedBox(height: screenHeight * 0.04),
              Center(
                child: SizedBox(
                  width: arrowSize,
                  height: arrowSize,
                  child: Image.asset(
                    'assets/images/seta.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              SizedBox(height: screenHeight * 0.04),
              Row(
                children: [
                  SizedBox(width: horizontalPadding),
                  SizedBox(
                    width: imageSize,
                    height: imageSize,
                    child: Image.asset(
                      'assets/images/mao.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ],
              ),
              SizedBox(height: screenHeight * 0.04),
              Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.08),
                  child: Text(
                    "Clique no botão abaixo para abrir a câmera do seu celular e traduzir gestos da língua brasileira de sinais!",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: descriptionFontSize.clamp(16.0, 28.0),
                    ),
                  ),
                ),
              ),
              SizedBox(height: screenHeight * 0.05),
              Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pushNamed('/camera');
                  },
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.all(screenWidth * 0.03),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(screenWidth * 0.1),
                    ),
                  ),
                  child: SizedBox(
                    width: cameraButtonSize,
                    height: cameraButtonSize,
                    child: Image.asset(
                      'assets/images/camera.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              SizedBox(height: screenHeight * 0.02),
            ],
          ),
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
      onChanged: (value) {
        AppController.instance.changeTheme();
      },
      activeColor: const Color.fromARGB(255, 5, 125, 10),
    );
  }
}
