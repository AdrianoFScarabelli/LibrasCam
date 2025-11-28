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
  String _accumulatedText = ''; 
  String _lastAddedSignal = ''; 
  Interpreter? interpreter;
  Timer? _timer;
  bool _isSendingPicture = false;


  int? _lastRecognizedIndex;
  final List<int> _predictionHistory = [];
  final int _historyLength = 5;
  
  int? _pendingSignalIndex;
  String? _pendingSignalName;
  int _zConsecutiveCount = 0;
  
  // 🆕 Controller para scroll automático
  final ScrollController _scrollController = ScrollController();




  // --- Variáveis de Zoom ---
  double _minAvailableZoom = 1.0;
  double _maxAvailableZoom = 1.0;
  double _currentZoomLevel = 1.0;




  // --- Mapeamento de rótulos (52 CLASSES: 0 a 51) ---
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
    48: "Sinal Onde", 49: "Sinal Até", 50: "Sinal Banheiro", 51: "Letra Z",
  };




  // --- LISTAS DE CONTROLE DE SINAIS ---
  final Set<int> oneHandedSignalIndices = {
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
    11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
    33, 34, 35, 36, 37, 38, 39, 40, 46, 47, 51
  };


  final Set<int> twoHandedSignalIndices = {
    41, 42, 43, 44, 45, 48, 49, 50,
  };


  final Set<int> letterIndices = {
    10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 51
  };


  final Set<int> numberIndices = {
    1,2,3,4,5,6,7,9
  };


  final Set<int> saudacoesIndices = {
    33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50
  };
  
  // 🆕 Letras do alfabeto para verificar contexto
  final Set<String> letterCharacters = {
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z'
  };



  Future<void> _loadModelFromBytes() async {
    try {
      final ByteData bytes = await rootBundle.load('assets/libras_landmarks_126_ate_Z.tflite');
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
    _scrollController.dispose(); // 🆕 Dispose do scroll controller
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }


  // 🆕 Função para scroll automático ao final
  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }


  // 🆕 Função para verificar contexto baseado no último caractere adicionado
  bool _lastCharIsLetter() {
    if (_accumulatedText.isEmpty) return false;
    
    // Pega o último caractere não-espaço
    String trimmed = _accumulatedText.trimRight();
    if (trimmed.isEmpty) return false;
    
    String lastChar = trimmed[trimmed.length - 1].toUpperCase();
    return letterCharacters.contains(lastChar);
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
          finalImageBytes = Uint8List.fromList(img.encodeJpg(resizedImage, quality: 75));
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




        final stopwatch = Stopwatch()..start();
        var response = await request.send();
        stopwatch.stop();
        print('⏱️ Tempo Total (Round Trip): ${stopwatch.elapsedMilliseconds} ms');




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
            print('🚫 Nenhuma mão detectada pela API');
            _processPendingSignal();
          }
        }
      } catch (e) {
        print('Erro: $e');
      } finally {
        _isSendingPicture = false;
      }
    });
  }


  void _processPendingSignal() {
    if (_pendingSignalIndex != null && _pendingSignalName != null) {
      String extractedText = _extractSignText(_pendingSignalName!, _pendingSignalIndex!);
      
      if (extractedText != _lastAddedSignal) {
        _accumulatedText += extractedText;
        _lastAddedSignal = extractedText;
        
        print('✅ SINAL PENDENTE ADICIONADO: "$extractedText"');
        
        if (mounted) {
          setState(() {
            resultado = _accumulatedText;
            _lastRecognizedIndex = _pendingSignalIndex;
          });
          _scrollToEnd(); // 🆕 Scroll automático
        }
      }
      
      _pendingSignalIndex = null;
      _pendingSignalName = null;
    }
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




  String _extractSignText(String signalName, int signalIndex) {
    String baseText = "";
    
    // Números (0-9)
    if (signalIndex >= 0 && signalIndex <= 9) {
      baseText = signalIndex.toString();
    }
    // Letras (A-Z)
    else if (signalName.contains("Letra ")) {
      baseText = signalName.replaceAll("Letra ", "").replaceAll(" (Contexto)", "").replaceAll(" (Dinâmico)", "").trim();
    }
    // Sinais compostos/palavras (já têm espaço definido)
    else if (signalName == "Tudo bem") {
      baseText = "Tudo bem ";
    }
    else if (signalName == "Bom dia") {
      baseText = "Bom dia ";
    }
    else if (signalName == "Boa tarde") {
      baseText = "Boa tarde ";
    }
    else if (signalName == "Boa noite") {
      baseText = "Boa noite ";
    }
    else if (signalName == "Qual é o seu nome") {
      baseText = "Qual é o seu nome? ";
    }
    else if (signalName == "O meu nome é ") {
      baseText = "O meu nome é ";
    }
    // Outros sinais
    else if (signalName.contains("Sinal ")) {
      baseText = signalName.replaceAll("Sinal ", "").split("/")[0].trim();
    }
    // Fallback
    else {
      baseText = signalName.trim();
    }
    
    // Se o sinal está em saudacoesIndices e ainda não tem espaço, adiciona
    if (signalIndex >= 0 && saudacoesIndices.contains(signalIndex) && !baseText.endsWith(" ")) {
      baseText += " ";
    }
    
    return baseText;
  }
  
  void _runInference(Float32List landmarks) {
    if (interpreter == null) return;




    var input = landmarks.reshape([1, 126]);
    var output = List<List<double>>.filled(1, List<double>.filled(52, 0.0));




    try {
      interpreter!.run(input, output);
      var probabilities = output[0];




      int handsDetected = _getDetectedHandCount(landmarks);
      print('👋 Mãos detectadas: $handsDetected');




      // Filtro de mãos
      if (handsDetected == 1) {
        for (int index in twoHandedSignalIndices) probabilities[index] = 0.0;
      } else if (handsDetected == 2) {
        for (int index in oneHandedSignalIndices) probabilities[index] = 0.0;
      } else {
          print('⚠️ Nenhuma mão válida detectada');
          _processPendingSignal();
          return;
      }
      
      var predictedIndex = probabilities.indexOf(
          probabilities.reduce((curr, next) => curr > next ? curr : next));
      var confidence = probabilities[predictedIndex];
      
      print('🎯 Predição: Índice $predictedIndex | Confiança: ${(confidence * 100).toStringAsFixed(1)}%');




      // Lógica de Substituição
      final int conhecerIndex = 40; 
      final int porfavorIndex = 43;
      if (predictedIndex == porfavorIndex && handsDetected == 1) {
          predictedIndex = conhecerIndex; 
          confidence = probabilities[conhecerIndex]; 
      } else if (predictedIndex == conhecerIndex && handsDetected == 2) {
          predictedIndex = porfavorIndex; 
          confidence = probabilities[porfavorIndex]; 
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
        final int noiteIndex = 46;
        final int uIndex = 28;
        final int zIndex = 51;
        
        bool isDynamicH = false;
        bool isDynamicJ = false;
        bool isTudoBem = false;
        bool isBomDia = false;
        bool isBoaTarde = false;
        bool isBoaNoite = false;
        bool isQualSeuNome = false;
        bool isMeuNomeE = false;
        bool shouldSkipAdding = false;




        if (_predictionHistory.length >= 2) {
          int lastSignal = _predictionHistory[_predictionHistory.length - 2];
          int currentSignal = _predictionHistory[_predictionHistory.length - 1];




          if (lastSignal == kIndex && currentSignal == twoIndex) isDynamicH = true;
          if (lastSignal == iIndex && currentSignal == jIndex) isDynamicJ = true;
          if (lastSignal == bomIndex && currentSignal == joiaIndex) isTudoBem = true;
          if (lastSignal == bomIndex && currentSignal == dIndex) isBomDia = true;
          if (lastSignal == bomIndex && currentSignal == conhecerIndex) isBoaTarde = true;
          if (lastSignal == bomIndex && currentSignal == noiteIndex) isBoaNoite = true;
          if (lastSignal == uIndex && currentSignal == uIndex) isQualSeuNome = true;
          if (lastSignal == twoIndex && currentSignal == twoIndex) isMeuNomeE = true;
        }
        
        if (isDynamicH) {
          finalResultName = "Letra H (Dinâmico)";
          finalIndex = -1; 
          _predictionHistory.clear();
          _pendingSignalIndex = null;
          _pendingSignalName = null;
        } else if (isDynamicJ) {
          finalResultName = "Letra J (Dinâmico)";
          finalIndex = -2; 
          _predictionHistory.clear();
          _pendingSignalIndex = null;
          _pendingSignalName = null;
        } else if (isTudoBem) {
          finalResultName = "Tudo bem";
          finalIndex = -3; 
          _predictionHistory.clear();
          _pendingSignalIndex = null;
          _pendingSignalName = null;
        } else if (isBomDia) {
          finalResultName = "Bom dia";
          finalIndex = -4; 
          _predictionHistory.clear();
          _pendingSignalIndex = null;
          _pendingSignalName = null;
        } else if (isBoaTarde) {
          finalResultName = "Boa tarde";
          finalIndex = -5; 
          _predictionHistory.clear();
          _pendingSignalIndex = null;
          _pendingSignalName = null;
        } else if (isBoaNoite) {
          finalResultName = "Boa noite";
          finalIndex = -6; 
          _predictionHistory.clear();
          _pendingSignalIndex = null;
          _pendingSignalName = null;
        } else if (isQualSeuNome) {
          finalResultName = "Qual é o seu nome";
          finalIndex = -7; 
          _predictionHistory.clear();
          _pendingSignalIndex = null;
          _pendingSignalName = null;
        } else if (isMeuNomeE) {
          finalResultName = "O meu nome é ";
          finalIndex = -8; 
          _predictionHistory.clear();
          _pendingSignalIndex = null;
          _pendingSignalName = null;
        }
        else if (predictedIndex == twoIndex) {
          if (_pendingSignalIndex == twoIndex) {
            finalResultName = "O meu nome é ";
            finalIndex = -8;
            _predictionHistory.clear();
            _pendingSignalIndex = null;
            _pendingSignalName = null;
          } else {
            _processPendingSignal();
            
            _pendingSignalIndex = twoIndex;
            _pendingSignalName = "Número 2";
            print('⏸️ Número 2 ficou PENDENTE, aguardando próximo sinal...');
            shouldSkipAdding = true;
            finalResultName = "";
            finalIndex = twoIndex;
          }
        }
        else if (predictedIndex == bomIndex) {
          _processPendingSignal();
          
          _pendingSignalIndex = bomIndex;
          _pendingSignalName = "Sinal Obrigado";
          print('⏸️ "Bom" ficou PENDENTE, aguardando composição...');
          shouldSkipAdding = true;
          finalResultName = "";
          finalIndex = bomIndex;
        }
        else if (predictedIndex == noiteIndex) {
          _processPendingSignal();
          
          print('⏭️ "Noite" detectado sozinho, ignorando (só aparece em "Boa noite")');
          shouldSkipAdding = true;
          finalResultName = "";
          finalIndex = noiteIndex;
        }
        else if (predictedIndex == zIndex) {
          _zConsecutiveCount++;
          print('🔤 Z detectado $_zConsecutiveCount vez(es) consecutivas');
          
          if (_zConsecutiveCount >= 3) {
            finalResultName = "Letra Z";
            finalIndex = zIndex;
            _zConsecutiveCount = 0;
            _processPendingSignal();
          } else {
            shouldSkipAdding = true;
            finalResultName = "";
            finalIndex = zIndex;
          }
        }
        // 🆕 LÓGICA ATUALIZADA DO 0/O - verifica último caractere do texto
        else if (predictedIndex == 0) {
          _zConsecutiveCount = 0;
          _processPendingSignal();
          
          if (_lastCharIsLetter()) {
            finalResultName = "Letra O (Contexto)";
            finalIndex = 0;
            print('🔤 Contexto: último char é letra, mostrando O');
          } else {
            finalResultName = "Número 0 (Contexto)";
            finalIndex = 0;
            print('🔢 Contexto: último char não é letra, mostrando 0');
          }
        }
        // 🆕 LÓGICA ATUALIZADA DO 8/S - verifica último caractere do texto
        else if (predictedIndex == 8) {
          _zConsecutiveCount = 0;
          _processPendingSignal();
          
          if (_lastCharIsLetter()) {
            finalResultName = "Letra S (Contexto)";
            finalIndex = 8;
            print('🔤 Contexto: último char é letra, mostrando S');
          } else {
            finalResultName = "Número 8 (Contexto)";
            finalIndex = 8;
            print('🔢 Contexto: último char não é letra, mostrando 8');
          } 
        } 
        else {
          _zConsecutiveCount = 0;
          _processPendingSignal();
          
          if (predictedIndex == conhecerIndex) {
            finalResultName = "Conhecer/Tarde"; 
          } else {
            finalResultName = classMapping[predictedIndex] ?? "Desconhecido";
          }
          finalIndex = predictedIndex;
        }


        if (!shouldSkipAdding && finalResultName.isNotEmpty) {
          String extractedText = _extractSignText(finalResultName, finalIndex);
          
          print('📝 Sinal reconhecido: "$finalResultName" → Texto extraído: "$extractedText"');
          print('📋 Último sinal adicionado: "$_lastAddedSignal"');
          
          if (extractedText != _lastAddedSignal) {
            _accumulatedText += extractedText;
            _lastAddedSignal = extractedText;
            
            print('✅ ADICIONADO! Texto acumulado agora: "$_accumulatedText"');
            
            if (mounted) {
              setState(() {
                resultado = _accumulatedText;
                _lastRecognizedIndex = finalIndex;
              });
              _scrollToEnd(); // 🆕 Scroll automático ao adicionar
            }
          } else {
            print('⏭️ Mesmo sinal repetido, não adicionado');
          }
        }
      } else {
        print('❌ Confiança baixa (${(confidence * 100).toStringAsFixed(1)}%), ignorando');
        _processPendingSignal();
      }
    } catch (e) {
      print('Erro TFLite: $e');
    }
  }




  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final screenHeight = screenSize.height; 
    final resultFontSize = screenHeight * 0.06;
    final containerHeight = screenHeight * 0.20;
    
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
                    quarterTurns: 3,
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
                // --- BOTÃO PARA LIMPAR TEXTO ---
                Positioned(
                  left: 60,
                  bottom: containerHeight + 25, // 🆕 Diminuído de 30 para 25
                  child: FloatingActionButton(
                    mini: true,
                    backgroundColor: Colors.red.withOpacity(0.8),
                    onPressed: () {
                      setState(() {
                        _accumulatedText = '';
                        resultado = '';
                        _lastAddedSignal = '';
                        _pendingSignalIndex = null;
                        _pendingSignalName = null;
                        _zConsecutiveCount = 0;
                      });
                      print('🗑️ Texto limpo!');
                    },
                    child: const Icon(Icons.clear, color: Colors.white),
                  ),
                ),
                // --- TEXTO DE RESULTADO ---
                Positioned(
                  bottom: 0,
                  left: 30,
                  right: 30,
                  child: Container(
                    height: containerHeight,
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                    color: Colors.black87,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      controller: _scrollController, // 🆕 Adicionado controller
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          resultado.isEmpty ? '' : resultado,
                          textAlign: TextAlign.left,
                          style: TextStyle(
                            fontSize: resultFontSize.clamp(16.0, 24.0), 
                            color: Colors.white, 
                            fontWeight: FontWeight.bold,
                          ),
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