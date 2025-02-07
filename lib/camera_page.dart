import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';

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

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.high,
    );
    _initializeControllerFuture = _controller.initialize();
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
      print(e);
    }
  }

  Future<void> enviarImagem(File imagem) async {
    final uri = Uri.parse('http://192.168.15.200:5000/api/reconhecer');
    final request = http.MultipartRequest('POST', uri);
    request.files.add(await http.MultipartFile.fromPath('imagem', imagem.path));

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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Mantenha seu celular parado"),
        actions: [
          IconButton(
            icon: const Icon(Icons.camera),
            onPressed: tirarFoto,
          ),
        ],
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
          child: Text(
            resultado,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18),
          ),
        ),
      ),
    );
  }
}
