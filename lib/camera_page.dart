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

// Extensão para reshape (necessária para tflite_flutter)
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

  // --- MAPeamento de rótulos (ATUALIZADO PARA 44 CLASSES - 0 a 43) ---
  final Map<int, String> classMapping = {
    0: "Sinal Ambiguo 0/O", 1: "Número 1", 2: "Número 2", 3: "Número 3", 4: "Número 4",
    5: "Número 5", 6: "Número 6", 7: "Número 7", 8: "Sinal Ambiguo 8/S", 9: "Número 9",
    10: "Outros Sinais", 11: "Letra A", 12: "Letra B", 13: "Letra C", 14: "Letra D",
    15: "Letra E", 16: "Letra F", 17: "Letra G", 18: "Letra K", 19: "Letra J",
    20: "Letra I", 21: "Letra L", 22: "Letra M", 23: "Letra N", 24: "Letra P",
    25: "Letra Q", 26: "Letra R", 27: "Letra T", 28: "Letra U", 29: "Letra V",
    30: "Letra W", 31: "Letra X", 32: "Letra Y",
    33: "Sinal Oi",
    34: "Sinal Olá/Tchau",
    35: "Sinal Joia",
    36: "Sinal Desculpa",
    37: "Sinal Saudade",
    38: "Sinal Obrigado",
    39: "Sinal Você",
    40: "Sinal Conhecer",
    41: "Sinal Licença",
    42: "Sinal Abraço",
    43: "Sinal Por Favor",
  };

  // --- CONJUNTOS DE FILTROS DE MÃOS ---
  
  // Índices de sinais que DEVEM usar DUAS MÃOS
  final Set<int> twoHandedSignalIndices = {
    41, // Licença (2 mãos)
    42, // Abraço (2 mãos)
    43, // Por Favor (2 mãos)
    // Revise seus sinais de duas mãos. Se "Conhecer" (40) usa 2 mãos, adicione aqui.
    // Se "Joia" (35) usa 2 mãos, adicione aqui.
  };

  // Índices de sinais que DEVEM usar UMA MÃO
  final Set<int> oneHandedSignalIndices = {
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, // Números e Ambíguos
    11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, // Letras
    33, // Oi
    34, // Olá/Tchau (depende da variação, mas geralmente é 1 mão)
    35, // Joia
    36, // Desculpa (geralmente 1 mão)
    37, // Saudade
    38, // Obrigado
    39, // Você
    40, // Conhecer
    // Revise seus sinais. Se "Joia" (35) for 1 mão, adicione aqui.
    // Se "Olá/Tchau" (34) for 1 mão, adicione aqui.
  };

  // Conjunto de índices que correspondem a letras (para lógica de contexto)
  final Set<int> letterIndices = {
    0, 8, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32
  };
  // --- FIM DOS CONJUNTOS DE FILTROS ---


  Future<void> _loadModelFromBytes() async {
    try {
      // --- NOVO NOME DO MODELO TFLITE (126 FLOATS) ---
      final ByteData bytes = await rootBundle.load('assets/libras_landmarks_126_ate_porfavor.tflite');
      final Uint8List modelBytes = bytes.buffer.asUint8List();
      if (modelBytes.isEmpty) {
        print('Erro: Modelo carregado como dados vazios.');
        setState(() { resultado = "Erro: Modelo vazio."; });
        return;
      }
      interpreter = Interpreter.fromBuffer(modelBytes);
      print('✅ Modelo TFLite (126 floats) carregado com sucesso.');
    } catch (e) {
      print('❌ Falha ao carregar o modelo TFLite: $e');
      setState(() { resultado = "Erro ao carregar o modelo de reconhecimento."; });
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
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    _initializeControllerFuture = _controller.initialize().then((_) {
      if (!mounted) return;
      _controller.lockCaptureOrientation(DeviceOrientation.landscapeRight);
      _controller.setFlashMode(FlashMode.off);
      _startSendingPictures();
      setState(() {});
    }).catchError((e) {
      print("Erro ao inicializar a câmera: $e");
      setState(() { resultado = "Erro ao iniciar a câmera."; });
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
    _timer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      if (!_controller.value.isInitialized || _isSendingPicture) {
        return;
      }
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
          print("⚠️ Erro: Não foi possível decodificar imagem, enviando original.");
          finalImageBytes = originalImageBytes;
        }

        final uri = Uri.parse('http://148.230.76.27:5000/api/processar_imagem');
        var request = http.MultipartRequest('POST', uri);
        request.files.add(http.MultipartFile.fromBytes(
          'imagem',
          finalImageBytes,
          filename: 'camera_frame.jpg',
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
            } else {
              print("Erro: O servidor não retornou 126 landmarks. Recebido: ${rawLandmarks.length}");
              setState(() { resultado = "Erro de dados do servidor (landmarks)"; });
            }

          } else {
            if (mounted) {
              setState(() {
                resultado = jsonResponse['mensagem'] ?? "Nenhuma mão detectada.";
                _lastRecognizedIndex = null;
                _predictionHistory.clear();
              });
            }
          }
        } else {
          if (mounted) {
            setState(() { resultado = 'Erro do servidor: ${response.statusCode}'; });
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            resultado = 'Falha na comunicação ou processamento: $e';
            print(e.runtimeType);
          });
        }
      } finally {
        _isSendingPicture = false;
      }
    });
  }

  // --- NOVA FUNÇÃO: Verificador de Mãos ---
  int _getDetectedHandCount(Float32List landmarks) {
    // Verifica se a Mão Esquerda (primeira metade) tem dados
    // Usamos um limiar pequeno (0.01) para evitar falsos positivos de ruído
    double leftHandSum = landmarks.sublist(0, 63).fold(0.0, (prev, e) => prev + e.abs());
    
    // Verifica se a Mão Direita (segunda metade) tem dados
    double rightHandSum = landmarks.sublist(63, 126).fold(0.0, (prev, e) => prev + e.abs());

    bool isLeftHandDetected = leftHandSum > 0.1;
    bool isRightHandDetected = rightHandSum > 0.1;

    if (isLeftHandDetected && isRightHandDetected) {
      return 2;
    } else if (isLeftHandDetected || isRightHandDetected) {
      return 1;
    } else {
      return 0;
    }
  }
  
  void _runInference(Float32List landmarks) {
    if (interpreter == null) {
      setState(() { resultado = "Modelo não carregado."; });
      return;
    }
    
    var input = landmarks.reshape([1, 126]);
    var output = List<List<double>>.filled(1, List<double>.filled(44, 0.0)); // ATUALIZADO: 44 classes

    try {
      interpreter!.run(input, output);

      var probabilities = output[0];
      var predictedIndex = probabilities.indexOf(
          probabilities.reduce((curr, next) => curr > next ? curr : next));
      var confidence = probabilities[predictedIndex];

      if (confidence > 0.55) {
        
        // --- NOVO: FILTRO DE CONTAGEM DE MÃOS ---
        int detectedHandCount = _getDetectedHandCount(landmarks);
        bool expectedTwoHands = twoHandedSignalIndices.contains(predictedIndex);
        bool expectedOneHand = oneHandedSignalIndices.contains(predictedIndex);

        // Se o modelo previu um sinal de DUAS MÃOS, mas só UMA foi detectada
        if (expectedTwoHands && detectedHandCount == 1) {
          if (mounted) {
            setState(() {
              resultado = "${classMapping[predictedIndex]} (Requer 2 Mãos)";
              _lastRecognizedIndex = null;
              _predictionHistory.clear();
            });
          }
          return; // Interrompe a lógica
        }
        
        // Se o modelo previu um sinal de UMA MÃO, mas DUAS foram detectadas
        if (expectedOneHand && detectedHandCount == 2) {
          if (mounted) {
            setState(() {
              resultado = "${classMapping[predictedIndex]} (Requer 1 Mão)";
              _lastRecognizedIndex = null;
              _predictionHistory.clear();
            });
          }
          return; // Interrompe a lógica
        }
        // --- FIM DO FILTRO ---


        _predictionHistory.add(predictedIndex);
        if (_predictionHistory.length > _historyLength) {
          _predictionHistory.removeAt(0);
        }

        String finalResult;
        int finalIndex;

        // Índices para lógica dinâmica e ambígua
        final int kIndex = 18;
        final int twoIndex = 2;
        final int iIndex = 20;
        final int jIndex = 19;
        
        bool isDynamicH = false;
        bool isDynamicJ = false;

        if (_predictionHistory.length >= 2) {
          if (_predictionHistory[_predictionHistory.length - 2] == kIndex &&
              _predictionHistory[_predictionHistory.length - 1] == twoIndex) {
            isDynamicH = true;
          }
          if (_predictionHistory[_predictionHistory.length - 2] == iIndex &&
              _predictionHistory[_predictionHistory.length - 1] == jIndex) { 
            isDynamicJ = true;
          }
        }
        
        if (isDynamicH) {
          finalResult = "Letra H (Sinal Dinâmico)";
          finalIndex = -1; 
          _predictionHistory.clear();
        } else if (isDynamicJ) {
          finalResult = "Letra J (Sinal Dinâmico)";
          finalIndex = -2;
          _predictionHistory.clear();
        } 
        
        else if (predictedIndex == 0) { // Sinal Ambíguo 0/O
          if (_lastRecognizedIndex != null && letterIndices.contains(_lastRecognizedIndex!)) {
            finalResult = "Letra O (Contexto)";
            finalIndex = 0;
          } else {
            finalResult = "Número 0 (Contexto)";
            finalIndex = 0;
          }
        } else if (predictedIndex == 8) { // Sinal Ambíguo 8/S
          if (_lastRecognizedIndex != null && letterIndices.contains(_lastRecognizedIndex!)) {
            finalResult = "Letra S (Contexto)";
            finalIndex = 8;
          } else {
            finalResult = "Número 8 (Contexto)";
            finalIndex = 8;
          } 
        } 
        else {
          // Previsão normal (passou no filtro de contagem de mãos)
          finalResult = "${classMapping[predictedIndex]} (Conf: ${(confidence * 100).toStringAsFixed(2)}%)";
          finalIndex = predictedIndex;
        }

        if (mounted) {
          setState(() {
            resultado = finalResult;
            _lastRecognizedIndex = finalIndex;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            resultado = "Sinal não reconhecido (TFLite - Baixa Confiança)";
            _lastRecognizedIndex = null;
            _predictionHistory.clear();
          });
        }
      }
    } catch (e) {
      print('Erro ao executar inferência com TFLite: $e');
      if (mounted) {
        setState(() {
          resultado = "Erro na inferência do modelo.";
        });
      }
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