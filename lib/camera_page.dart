import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Para SystemChrome e rootBundle
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image/image.dart' as img; // Para redimensionamento

// Extensão para reshape
extension on List<double> {
  List<List<double>> reshape(List<int> shape) {
    if (shape.length != 2 || shape[0] * shape[1] != length) {
      throw ArgumentError('A forma fornecida não é compatível com o tamanho da lista.');
    }
    final result = <List<double>>[];
    for (int i = 0; i < shape[0]; i++) {
      result.add(sublist(i * shape[1], (i + 1) * shape[1]));
    }
    return result;
  }
}

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
  Interpreter? interpreter;
  Timer? _timer;
  bool _isSendingPicture = false;

  int? _lastRecognizedIndex;
  final List<int> _predictionHistory = [];
  final int _historyLength = 5;

  // --- MAPeamento de rótulos (44 CLASSES: 0 a 43) ---
  final Map<int, String> classMapping = {
    0: "Sinal Ambiguo 0/O", 1: "Número 1", 2: "Número 2", 3: "Número 3", 4: "Número 4",
    5: "Número 5", 6: "Número 6", 7: "Número 7", 8: "Sinal Ambiguo 8/S", 9: "Número 9",
    10: "Outros Sinais", 11: "Letra A", 12: "Letra B", 13: "Letra C", 14: "Letra D",
    15: "Letra E", 16: "Letra F", 17: "Letra G", 18: "Letra K", 19: "Letra J",
    20: "Letra I", 21: "Letra L", 22: "Letra M", 23: "Letra N", 24: "Letra P",
    25: "Letra Q", 26: "Letra R", 27: "Letra T", 28: "Letra U", 29: "Letra V",
    30: "Letra W", 31: "Letra X", 32: "Letra Y",
    33: "Sinal Oi", 34: "Sinal Olá/Tchau", 35: "Sinal Joia", 36: "Sinal Desculpa",
    37: "Sinal Saudade", 38: "Sinal Obrigado", 39: "Sinal Você", 40: "Sinal Conhecer",
    41: "Sinal Licença", 42: "Sinal Abraço", 43: "Sinal Por Favor"
  };

  // --- LISTAS DE CONTROLE DE MÃOS ---
  final Set<int> twoHandedSignalIndices = {
    41, // Licença
    42, // Abraço
    43, // Por Favor
  };
  final Set<int> oneHandedSignalIndices = {
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, // Números e Outros
    11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, // Letras
    33, // Oi
    34, // Olá/Tchau
    35, // Joia
    36, // Desculpa (Geralmente 1 mão em Y no queixo)
    37, // Saudade (Geralmente 1 mão em A girando no peito)
    38, // Obrigado (Geralmente 1 mão na testa/peito ou 2 mãos. Ajuste conforme seu treino)
    39, // Você (Apontar - 1 mão)
    40, // Conhecer (1 mão no queixo)
  };
  final Set<int> letterIndices = {
    0, 8, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32
  };


  Future<void> _loadModelFromBytes() async {
    try {
      final ByteData bytes = await rootBundle.load('assets/libras_landmarks_126_ate_porfavor.tflite');
      final Uint8List modelBytes = bytes.buffer.asUint8List();
      if (modelBytes.isEmpty) {
        setState(() { resultado = "Erro: Modelo vazio."; });
        return;
      }
      interpreter = Interpreter.fromBuffer(modelBytes);
      print('✅ Modelo TFLite (126 floats) carregado com sucesso.');
    } catch (e) {
      print('❌ Falha ao carregar: $e');
      setState(() { resultado = "Erro ao carregar modelo."; });
    }
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _loadModelFromBytes();
    _controller = CameraController(widget.camera, ResolutionPreset.medium, enableAudio: false);
    _initializeControllerFuture = _controller.initialize().then((_) {
      if (!mounted) return;
      _controller.lockCaptureOrientation(DeviceOrientation.landscapeRight);
      _controller.setFlashMode(FlashMode.off);
      _startSendingPictures();
      setState(() {});
    }).catchError((e) {
      print("Erro câmera: $e");
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    interpreter?.close();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  void _startSendingPictures() {
    _timer = Timer.periodic(const Duration(milliseconds: 1000), (timer) async {
      if (!_controller.value.isInitialized || _isSendingPicture) return;
      _isSendingPicture = true;

      try {
        final XFile imageFile = await _controller.takePicture();
        final Uint8List originalImageBytes = await File(imageFile.path).readAsBytes();
        img.Image? originalImage = img.decodeImage(originalImageBytes);
        Uint8List finalImageBytes;

        if (originalImage != null) {
          img.Image resizedImage = img.copyResize(originalImage, width: 192, height: 192);
          finalImageBytes = Uint8List.fromList(img.encodeJpg(resizedImage, quality: 85));
        } else {
          finalImageBytes = originalImageBytes;
        }

        final uri = Uri.parse('http://148.230.76.27:5000/api/processar_imagem');
        var request = http.MultipartRequest('POST', uri);
        request.files.add(http.MultipartFile.fromBytes(
          'imagem',
          finalImageBytes,
          filename: 'frame.jpg',
          contentType: MediaType('image', 'jpeg'),
        ));

        var response = await request.send();

        if (response.statusCode == 200) {
          var responseBody = await response.stream.bytesToString();
          var jsonResponse = jsonDecode(responseBody);

          if (jsonResponse['landmarks'] != null) {
            List<dynamic> rawLandmarks = jsonResponse['landmarks'];
            if (rawLandmarks.length == 126) {
              var landmarks = Float32List.fromList(rawLandmarks.map((e) => e as double).toList());
              _runInference(landmarks);
            }
          } else {
            if (mounted) {
              setState(() {
                resultado = "Nenhuma mão detectada";
                _lastRecognizedIndex = null;
                _predictionHistory.clear();
              });
            }
          }
        }
      } catch (e) {
        print('Erro: $e');
      } finally {
        _isSendingPicture = false;
      }
    });
  }

  int _getDetectedHandCount(Float32List landmarks) {
    double sumLeft = 0;
    for(int i=0; i<63; i++) sumLeft += landmarks[i].abs();
    double sumRight = 0;
    for(int i=63; i<126; i++) sumRight += landmarks[i].abs();
    int count = 0;
    if (sumLeft > 0.1) count++;
    if (sumRight > 0.1) count++;
    return count;
  }
  
  void _runInference(Float32List landmarks) {
    if (interpreter == null) return;

    var input = landmarks.reshape([1, 126]);
    var output = List<List<double>>.filled(1, List<double>.filled(44, 0.0)); // 44 classes

    try {
      interpreter!.run(input, output);
      var probabilities = output[0];
      
      int handsDetected = _getDetectedHandCount(landmarks);

      if (handsDetected == 1) {
        for (int index in twoHandedSignalIndices) {
          probabilities[index] = 0.0;
        }
      } else if (handsDetected == 2) {
        for (int index in oneHandedSignalIndices) {
          probabilities[index] = 0.0;
        }
      } else {
          if (mounted) setState(() { resultado = "..."; });
          return;
      }

      var predictedIndex = probabilities.indexOf(
          probabilities.reduce((curr, next) => curr > next ? curr : next));
      var confidence = probabilities[predictedIndex];

      if (confidence > 0.55) {
        
        // Evita adicionar previsões repetidas ao histórico
        if (_predictionHistory.isEmpty || _predictionHistory.last != predictedIndex) {
          _predictionHistory.add(predictedIndex);
          if (_predictionHistory.length > _historyLength) {
            _predictionHistory.removeAt(0);
          }
        }

        String finalResultName;
        int finalIndex;

        // --- DEFINIÇÃO DE ÍNDICES DINÂMICOS E AMBÍGUOS ---
        final int kIndex = 18;
        final int twoIndex = 2;
        final int iIndex = 20;
        final int jIndex = 19;
        
        // --- NOVO: Índices para "Tudo bem" ---
        final int bomIndex = 38; // Mapeado de "Obrigado"
        final int joiaIndex = 35; // Sinal Joia

        bool isDynamicH = false;
        bool isDynamicJ = false;
        bool isTudoBem = false; // Nova flag

        // 1. Verifica o sinal dinâmico 'H' (K -> 2)
        if (_predictionHistory.length >= 2) {
          if (_predictionHistory[_predictionHistory.length - 2] == kIndex &&
              _predictionHistory[_predictionHistory.length - 1] == twoIndex) {
            isDynamicH = true;
          }
          // 2. Verifica o sinal dinâmico 'J' (I -> J)
          if (_predictionHistory[_predictionHistory.length - 2] == iIndex &&
              _predictionHistory[_predictionHistory.length - 1] == jIndex) { 
            isDynamicJ = true;
          }
          // 3. Verifica o sinal dinâmico 'Tudo bem' (Bom/Obrigado -> Joia)
          if (_predictionHistory[_predictionHistory.length - 2] == bomIndex &&
              _predictionHistory[_predictionHistory.length - 1] == joiaIndex) {
            isTudoBem = true;
          }
        }
        
        // --- LÓGICA DE DECISÃO ---
        if (isDynamicH) {
          finalResultName = "Letra H (Dinâmico)";
          finalIndex = -1; 
          _predictionHistory.clear();
        } else if (isDynamicJ) {
          finalResultName = "Letra J (Dinâmico)";
          finalIndex = -2;
          _predictionHistory.clear();
        } else if (isTudoBem) {
          finalResultName = "Tudo bem?"; // Tradução da sequência
          finalIndex = -3; // Índice customizado para "Tudo bem"
          _predictionHistory.clear(); // Limpa após reconhecer a sequência
        }
        
        // --- LÓGICA DE CONTEXTO AMBÍGUO (Sinais estáticos) ---
        else if (predictedIndex == 0) { // 0/O
          if (_lastRecognizedIndex != null && letterIndices.contains(_lastRecognizedIndex!)) {
            finalResultName = "Letra O";
            finalIndex = 0;
          } else {
            finalResultName = "Número 0";
            finalIndex = 0;
          }
        } else if (predictedIndex == 8) { // 8/S
          if (_lastRecognizedIndex != null && letterIndices.contains(_lastRecognizedIndex!)) {
            finalResultName = "Letra S";
            finalIndex = 8;
          } else {
            finalResultName = "Número 8";
            finalIndex = 8;
          } 
        } 
        else {
          // Resultado Normal (Passou no filtro de mãos)
          // Mapeia "Obrigado" (38) para "Bom"
          if (predictedIndex == bomIndex) {
            finalResultName = "Bom (Obrigado)";
          } else {
            finalResultName = classMapping[predictedIndex]!;
          }
          finalIndex = predictedIndex;
        }

        if (mounted) {
          setState(() {
            // Mostra a confiança apenas para sinais estáticos (não dinâmicos ou de contexto)
            if (finalIndex >= 0 && predictedIndex == finalIndex) {
               resultado = "$finalResultName (${(confidence * 100).toStringAsFixed(0)}%)";
            } else {
               resultado = finalResultName;
            }
            _lastRecognizedIndex = finalIndex;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            resultado = "Sinal não reconhecido";
            _lastRecognizedIndex = null;
            _predictionHistory.clear();
          });
        }
      }
    } catch (e) {
      print('Erro TFLite: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final screenHeight = screenSize.height; 
    final resultFontSize = screenHeight * 0.09;
    final containerHeight = screenHeight * 0.15;
    
    return Scaffold(
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Stack(
              children: [
                Positioned.fill(
                  child: CameraPreview(_controller),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: containerHeight,
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    color: Colors.black87,
                    child: Center(
                      child: Text(
                        resultado,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: resultFontSize.clamp(16.0, 28.0), 
                          color: Colors.white, 
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
    );
  }
}