import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';

//VERSÃO DO LIBRASCAM QUE USA SERVIDOR E MEDIAPIPE
//FUNCIONOU APENAS ATÉ O NÚMERO 4

class CameraScreen extends StatefulWidget {
  final CameraDescription camera;

  const CameraScreen({super.key, required this.camera});

  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  String resultado = '';
  bool isLoading = false; // Para indicar quando a requisição está em andamento
  bool isCapturing = true; // Controla a captura contínua

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.high,
    );
    _initializeControllerFuture = _controller.initialize();
    
    // Iniciar a captura repetitiva logo após o carregamento da câmera
    _iniciarCapturaRepetitiva();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> tirarFoto() async {
    try {
      await _initializeControllerFuture;
      final image = await _controller.takePicture();
      await enviarImagem(File(image.path));
    } catch (e) {
      print('Erro ao tirar foto: $e');
    }
  }

  Future<void> enviarImagem(File imagem) async {
    final uri = Uri.parse('https://fierce-peak-85954-ebe519c2f978.herokuapp.com/api/reconhecer'); // Verifique o IP do servidor
    final request = http.MultipartRequest('POST', uri);
    request.files.add(await http.MultipartFile.fromPath('imagem', imagem.path));

    setState(() {
      isLoading = true; // Enquanto envia a imagem, mostramos um carregamento
    });

    try {
      final response = await request.send();

      if (response.statusCode == 200) {
        final resposta = await http.Response.fromStream(response);
        final jsonResponse = json.decode(resposta.body);
        setState(() {
          resultado = jsonResponse['significado'];
        });
      } else {
        setState(() {
          resultado = 'Erro ao reconhecer o sinal';
        });
      }
    } catch (e) {
      print('Erro na requisição: $e');
      setState(() {
        resultado = 'Falha ao conectar ao servidor';
      });
    } finally {
      setState(() {
        isLoading = false; // Finaliza o carregamento após a requisição
      });
    }
  }

  // Função para capturar fotos repetidamente a cada 1 segundos
  void _iniciarCapturaRepetitiva() {
    if (isCapturing) {
      Future.doWhile(() async {
        await tirarFoto();
        await Future.delayed(Duration(seconds: 1)); // Intervalo de 1 segundos entre as fotos
        return isCapturing; // Continua capturando enquanto isCapturing for verdadeiro
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Mantenha seu celular parado"),
      ),
      body: SizedBox(
        width: 410,
        height: 600,
        child: FutureBuilder<void>(
          future: _initializeControllerFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.done) {
              return CameraPreview(_controller);
            } else {
              return const Center(child: CircularProgressIndicator());
            }
          },
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: isLoading
              ? const CircularProgressIndicator() // Exibe o carregamento enquanto a requisição está em andamento
              : Text(
                  resultado,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18),
                ),
        ),
      ),
    );
  }
}