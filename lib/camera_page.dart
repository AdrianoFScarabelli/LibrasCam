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
    39: "Sinal Você",      // NOVO
    40: "Sinal Conhecer",  // NOVO
    41: "Sinal Licença",   // NOVO
    42: "Sinal Abraço",    // NOVO
    43: "Sinal Por Favor"  // NOVO
  };

  // --- Conjunto de índices que correspondem a letras (para lógica de contexto) ---
  final Set<int> letterIndices = {
    0, 8, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32
  };

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
    
    // Trava a orientação em modo paisagem
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    
    _loadModelFromBytes();
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.medium, // Medium para capturar, mas vamos redimensionar
      enableAudio: false,
    );
    _initializeControllerFuture = _controller.initialize().then((_) {
      if (!mounted) {
        return;
      }
      // Trava a orientação da câmera em paisagem
      _controller.lockCaptureOrientation(DeviceOrientation.landscapeRight);
      // Desativa o flash da câmera permanentemente
      _controller.setFlashMode(FlashMode.off);

      _startSendingPictures();
      setState(() {});
    }).catchError((e) {
      print("Erro ao inicializar a câmera: $e");
      setState(() {
        resultado = "Erro ao iniciar a câmera.";
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    interpreter?.close();
    
    // Restaura as orientações permitidas ao sair da tela
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    
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
        
        // --- OTIMIZAÇÃO: REDIMENSIONAR IMAGEM ANTES DE ENVIAR ---
        final Uint8List originalImageBytes = await File(imageFile.path).readAsBytes();
        img.Image? originalImage = img.decodeImage(originalImageBytes);
        Uint8List finalImageBytes;

        if (originalImage != null) {
          // Redimensiona para 192x192 (um bom tamanho para MediaPipe Hands)
          img.Image resizedImage = img.copyResize(originalImage, width: 192, height: 192);
          finalImageBytes = Uint8List.fromList(img.encodeJpg(resizedImage, quality: 85));
          // print("Imagem redimensionada para 192x192."); // Opcional: remover para logs mais limpos
        } else {
          print("⚠️ Erro: Não foi possível decodificar imagem, enviando original.");
          finalImageBytes = originalImageBytes; // Fallback
        }
        // --- FIM DA OTIMIZAÇÃO ---

        final uri = Uri.parse('http://148.230.76.27:5000/api/processar_imagem');
        var request = http.MultipartRequest('POST', uri);
        request.files.add(http.MultipartFile.fromBytes(
          'imagem',
          finalImageBytes, // Envia a imagem redimensionada
          filename: 'camera_frame.jpg',
          contentType: MediaType('image', 'jpeg'),
        ));

        var response = await request.send();

        if (response.statusCode == 200) {
          var responseBody = await response.stream.bytesToString();
          var jsonResponse = jsonDecode(responseBody);

          if (jsonResponse['landmarks'] != null) {
            List<dynamic> rawLandmarks = jsonResponse['landmarks'];
            
            // --- ATUALIZADO: VERIFICAR SE RECEBEU 126 FLOATS ---
            if (rawLandmarks.length == 126) {
              var landmarks = Float32List.fromList(rawLandmarks.map((e) => e as double).toList());
              _runInference(landmarks);
            } else {
              print("Erro: O servidor não retornou 126 landmarks. Recebido: ${rawLandmarks.length}");
              setState(() {
                resultado = "Erro de dados do servidor (landmarks)";
              });
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
            setState(() {
              resultado = 'Erro do servidor: ${response.statusCode}';
            });
          }
          print('Erro do servidor: ${response.statusCode}');
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            resultado = 'Falha na comunicação ou processamento: $e';
            print(e.runtimeType);
          });
        }
        print('Erro: $e');
      } finally {
        _isSendingPicture = false;
      }
    });
  }
  
  void _runInference(Float32List landmarks) {
    if (interpreter == null) {
      setState(() {
        resultado = "Modelo não carregado.";
      });
      return;
    }
    
    // --- ATUALIZADO: INPUT DE [1, 126] ---
    var input = landmarks.reshape([1, 126]);
    // --- ATUALIZADO: OUTPUT DE 44 CLASSES (0 a 43) ---
    var output = List<List<double>>.filled(1, List<double>.filled(44, 0.0)); 

    try {
      interpreter!.run(input, output);

      var probabilities = output[0];
      var predictedIndex = probabilities.indexOf(
          probabilities.reduce((curr, next) => curr > next ? curr : next));
      var confidence = probabilities[predictedIndex];

      if (confidence > 0.55) { // Limiar de confiança
        _predictionHistory.add(predictedIndex);
        if (_predictionHistory.length > _historyLength) {
          _predictionHistory.removeAt(0);
        }

        String finalResult;
        int finalIndex;

        // --- DEFINIÇÃO DE ÍNDICES DINÂMICOS E AMBÍGUOS ---
        // Estes índices DEVERÃO ser atualizados se o classMapping mudar
        final int kIndex = 18;  // K
        final int twoIndex = 2;   // Número 2
        final int iIndex = 20;  // I
        final int jIndex = 19;  // J
        
        bool isDynamicH = false;
        bool isDynamicJ = false;

        // 1. Verifica o sinal dinâmâmico 'H' (K -> 2)
        if (_predictionHistory.length >= 2 &&
            _predictionHistory[_predictionHistory.length - 2] == kIndex &&
            _predictionHistory[_predictionHistory.length - 1] == twoIndex) {
          isDynamicH = true;
        }

        // 2. Verifica o sinal dinâmico 'J' (I -> J)
        if (_predictionHistory.length >= 2 &&
            _predictionHistory[_predictionHistory.length - 2] == iIndex &&
            _predictionHistory[_predictionHistory.length - 1] == jIndex) { 
            isDynamicJ = true;
        }
        
        // --- LÓGICA DE DECISÃO ---
        if (isDynamicH) {
          finalResult = "Letra H (Sinal Dinâmico)";
          finalIndex = -1; // Índice customizado para H
          _predictionHistory.clear();
        } else if (isDynamicJ) {
          finalResult = "Letra J (Sinal Dinâmico)";
          finalIndex = -2; // Índice customizado para J
          _predictionHistory.clear();
        } 
        
        // --- LÓGICA DE CONTEXTO AMBÍGUO (Sinais estáticos) ---
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
          // Se não for dinâmico nem ambíguo, usa a previsão normal.
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
    // Obter dimensões da tela em modo paisagem
    final screenSize = MediaQuery.sizeOf(context);
    final screenHeight = screenSize.height; // Altura em paisagem (menor dimensão)
    
    // Calcular tamanhos proporcionais para modo paisagem
    final resultFontSize = screenHeight * 0.09; // 9% da altura
    final containerHeight = screenHeight * 0.15; // 15% da altura para o container de resultado
    
    return Scaffold(
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Stack(
              children: [
                // Preview da câmera ocupando toda a tela
                Positioned.fill(
                  child: CameraPreview(_controller),
                ),
                // Container com texto de resultado na parte inferior
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