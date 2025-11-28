import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image/image.dart' as img;

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

  // --- Variáveis de Zoom ---
  double _minAvailableZoom = 1.0;
  double _maxAvailableZoom = 1.0;
  double _currentZoomLevel = 1.0;

  // --- MAPeamento de rótulos (51 CLASSES: 0 a 50) ---
  final Map<int, String> classMapping = {
    0: "Sinal Ambiguo 0/O", 1: "Número 1", 2: "Número 2", 3: "Número 3", 4: "Número 4",
    5: "Número 5", 6: "Número 6", 7: "Número 7", 8: "Sinal Ambiguo 8/S", 9: "Número 9",
    10: "Te Amo", 11: "Letra A", 12: "Letra B", 13: "Letra C", 14: "Letra D",
    15: "Letra E", 16: "Letra F", 17: "Letra G", 18: "Letra K", 19: "Letra J",
    20: "Letra I", 21: "Letra L", 22: "Letra M", 23: "Letra N", 24: "Letra P",
    25: "Letra Q", 26: "Letra R", 27: "Letra T", 28: "Letra U", 29: "Letra V",
    30: "Letra W", 31: "Letra X", 32: "Letra Y",
    33: "Sinal Oi", 34: "Sinal Olá/Tchau", 35: "Sinal Joia", 36: "Sinal Desculpa",
    37: "Sinal Idade", 38: "Sinal Obrigado", 39: "Sinal Você", 40: "Sinal Conhecer",
    41: "Sinal Licença", 42: "Sinal Abraço", 43: "Sinal Por Favor",
    44: "Sinal Horas", 45: "Sinal De Nada", 46: "Sinal Noite", 47: "Sinal Virgula",
    48: "Sinal Onde", 49: "Sinal Até", 50: "Sinal Banheiro"
  };

  // --- LISTAS DE CONTROLE DE MÃOS ---
  // Ajuste conforme o seu treinamento.
  final Set<int> oneHandedSignalIndices = {
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
    11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
    33, 34, 35, 36, 37, 38, 39, 40, 46, 47
  };

  final Set<int> twoHandedSignalIndices = {
    41, 42, 43, 44, 45, 48, 49, 50,
  };

  final Set<int> letterIndices = {
    10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41,
    42, 43, 44, 45, 46, 47, 48, 49, 50
  };

  Future<void> _loadModelFromBytes() async {
    try {
      final ByteData bytes = await rootBundle.load('assets/libras_landmarks_126_ate_idade.tflite');
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
      DeviceOrientation.landscapeRight,
    ]);
    _loadModelFromBytes();
    _controller = CameraController(widget.camera, ResolutionPreset.medium, enableAudio: false);
    _initializeControllerFuture = _controller.initialize().then((_) async {
      if (!mounted) return;
      _controller.lockCaptureOrientation(DeviceOrientation.landscapeRight);
      _controller.setFlashMode(FlashMode.off);

      // --- Configuração do Zoom ---
      _maxAvailableZoom = await _controller.getMaxZoomLevel();
      _minAvailableZoom = await _controller.getMinZoomLevel();
      
      // Define um zoom inicial (ex: 1.0x = sem zoom, 1.5x = leve aproximação)
      // Se estiver a 1 metro, talvez começar com 1.5x ajude.
      _currentZoomLevel = 1.8; 
      await _controller.setZoomLevel(_currentZoomLevel);

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

        // --- INÍCIO DA MEDIÇÃO ---
        final stopwatch = Stopwatch()..start(); // Inicia o cronômetro
        
        var response = await request.send();
        
        stopwatch.stop(); // Para o cronômetro
        print('⏱️ Tempo Total (Round Trip): ${stopwatch.elapsedMilliseconds} ms');
        // --- FIM DA MEDIÇÃO ---

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
    var output = List<List<double>>.filled(1, List<double>.filled(51, 0.0)); // 51 classes

    try {
      interpreter!.run(input, output);
      var probabilities = output[0];
      
      // --- 🔴 BLOQUEIO TEMPORÁRIO PARA TESTE 🔴 ---
      // Zera a chance do sinal "Conhecer" (Índice 40)
      // Isso impede que ele seja escolhido, permitindo testar se o modelo
      // reconhece "Morar" ou outros sinais sem essa interferência.
      //probabilities[40] = 0.0; 
      // ---------------------------------------------

      int handsDetected = _getDetectedHandCount(landmarks);

      // Filtro de mãos
      if (handsDetected == 1) {
        for (int index in twoHandedSignalIndices) probabilities[index] = 0.0;
      } else if (handsDetected == 2) {
        for (int index in oneHandedSignalIndices) probabilities[index] = 0.0;
      } else {
          return; // 0 mãos
      }
      
      var predictedIndex = probabilities.indexOf(
          probabilities.reduce((curr, next) => curr > next ? curr : next));
      var confidence = probabilities[predictedIndex];

      // Lógica de Substituição
      final int conhecerIndex = 40; final int porfavorIndex = 43;
      if (predictedIndex == porfavorIndex && handsDetected == 1) {
          predictedIndex = conhecerIndex; confidence = probabilities[conhecerIndex]; 
      } else if (predictedIndex == conhecerIndex && handsDetected == 2) {
          predictedIndex = porfavorIndex; confidence = probabilities[porfavorIndex]; 
      }

      if (confidence > 0.55) {
        _predictionHistory.add(predictedIndex);
        if (_predictionHistory.length > _historyLength) _predictionHistory.removeAt(0);

        String finalResultName;
        int finalIndex;

        // Índices para lógica dinâmica e ambígua
        final int kIndex = 18;
        final int twoIndex = 2;
        final int iIndex = 20;
        final int jIndex = 19;
        
        final int bomIndex = 38; 
        final int joiaIndex = 35; 
        final int dIndex = 14; 
        final int conhecerIndex = 40; 
        final int noiteIndex = 46; 
        
        // --- NOVOS ÍNDICES PARA NOVAS LÓGICAS ---
        final int uIndex = 28; // Letra U
        
        bool isDynamicH = false;
        bool isDynamicJ = false;
        bool isTudoBem = false;
        bool isBomDia = false;
        bool isBoaTarde = false;
        bool isBoaNoite = false;
        bool isQualSeuNome = false; // NOVO
        bool isMeuNomeE = false;    // NOVO

        if (_predictionHistory.length >= 2) {
          int lastSignal = _predictionHistory[_predictionHistory.length - 2];
          int currentSignal = _predictionHistory[_predictionHistory.length - 1];

          if (lastSignal == kIndex && currentSignal == twoIndex) isDynamicH = true;
          if (lastSignal == iIndex && currentSignal == jIndex) isDynamicJ = true;
          if (lastSignal == bomIndex && currentSignal == joiaIndex) isTudoBem = true;
          if (lastSignal == bomIndex && currentSignal == dIndex) isBomDia = true;
          if (lastSignal == bomIndex && currentSignal == conhecerIndex) isBoaTarde = true;
          if (lastSignal == bomIndex && currentSignal == noiteIndex) isBoaNoite = true;
          
          // --- NOVA LÓGICA: "Qual é o seu nome?" (U + U) ---
          if (lastSignal == uIndex && currentSignal == uIndex) {
            isQualSeuNome = true;
          }
          
          // --- NOVA LÓGICA: "O meu nome é" (2 + 2) ---
          if (lastSignal == twoIndex && currentSignal == twoIndex) {
            isMeuNomeE = true;
          }
        }
        
        if (isDynamicH) {
          finalResultName = "Letra H (Dinâmico)";
          finalIndex = -1; _predictionHistory.clear();
        } else if (isDynamicJ) {
          finalResultName = "Letra J (Dinâmico)";
          finalIndex = -2; _predictionHistory.clear();
        } else if (isTudoBem) {
          finalResultName = "Tudo bem";
          finalIndex = -3; _predictionHistory.clear();
        } else if (isBomDia) {
          finalResultName = "Bom dia";
          finalIndex = -4; _predictionHistory.clear();
        } else if (isBoaTarde) {
          finalResultName = "Boa tarde";
          finalIndex = -5; _predictionHistory.clear();
        } else if (isBoaNoite) {
          finalResultName = "Boa noite";
          finalIndex = -6; _predictionHistory.clear();
        } else if (isQualSeuNome) { // --- NOVO RESULTADO ---
          finalResultName = "Qual é o seu nome";
          finalIndex = -7; _predictionHistory.clear();
        } else if (isMeuNomeE) { // --- NOVO RESULTADO ---
          finalResultName = "O meu nome é ";
          finalIndex = -8; _predictionHistory.clear();
        }
        
        else if (predictedIndex == 0) { // 0/O
          if (_lastRecognizedIndex != null && letterIndices.contains(_lastRecognizedIndex!)) {
            finalResultName = "Letra O (Contexto)";
            finalIndex = 0;
          } else {
            finalResultName = "Número 0 (Contexto)";
            finalIndex = 0;
          }
        } else if (predictedIndex == 8) { // 8/S
          if (_lastRecognizedIndex != null && letterIndices.contains(_lastRecognizedIndex!)) {
            finalResultName = "Letra S (Contexto)";
            finalIndex = 8;
          } else {
            finalResultName = "Número 8 (Contexto)";
            finalIndex = 8;
          } 
        } 
        else {
          // Mapeamento de nomes para sinais estáticos com duplo sentido
          if (predictedIndex == bomIndex) {
            finalResultName = "Bom/Obrigado"; 
          } else if (predictedIndex == conhecerIndex) {
            finalResultName = "Conhecer/Tarde"; 
          } else {
            finalResultName = classMapping[predictedIndex] ?? "Desconhecido";
          }
          finalIndex = predictedIndex;
        }

        if (mounted) {
          setState(() {
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
                // --- SLIDER DE ZOOM ---
                Positioned(
                  right: 10,
                  top: 50,
                  bottom: 100,
                  child: RotatedBox(
                    quarterTurns: 3, // Slider vertical
                    child: Slider(
                      value: _currentZoomLevel,
                      min: _minAvailableZoom,
                      max: _maxAvailableZoom,
                      activeColor: Colors.white,
                      inactiveColor: Colors.white30,
                      onChanged: (value) async {
                        setState(() {
                          _currentZoomLevel = value;
                        });
                        await _controller.setZoomLevel(value);
                      },
                    ),
                  ),
                ),
                // --- TEXTO DE RESULTADO ---
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