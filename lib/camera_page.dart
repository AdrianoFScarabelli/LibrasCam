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
  int _kConsecutiveCount = 0;



  final ScrollController _scrollController = ScrollController();



  // --- Variáveis de Zoom ---
  double _minAvailableZoom = 1.0;
  double _maxAvailableZoom = 1.0;
  double _currentZoomLevel = 1.0;



  // --- Mapeamento de rótulos (52 CLASSES: 0 a 51) ---
  final Map<int, String> classMapping = {
    0: "Sinal Ambiguo 0/O",
    1: "Número 1",
    2: "Número 2",
    3: "Número 3",
    4: "Número 4",
    5: "Número 5",
    6: "Número 6",
    7: "Número 7",
    8: "Sinal Ambiguo 8/S",
    9: "Número 9",
    10: "Te Amo",
    11: "Letra A",
    12: "Letra B",
    13: "Letra C",
    14: "Letra D",
    15: "Letra E",
    16: "Letra F",
    17: "Letra G",
    18: "Letra K",
    19: "Letra J",
    20: "Letra I",
    21: "Letra L",
    22: "Letra M",
    23: "Letra N",
    24: "Letra P",
    25: "Letra Q",
    26: "Letra R",
    27: "Letra T",
    28: "Letra U",
    29: "Letra V",
    30: "Letra W",
    31: "Letra X",
    32: "Letra Y",
    33: "Sinal Oi",
    34: "Sinal Olá/Tchau",
    35: "Sinal Joia",
    36: "Sinal Desculpa",
    37: "Sinal Idade",
    38: "Sinal Obrigado",
    39: "Sinal Você",
    40: "Sinal Conhecer",
    41: "Sinal Licença",
    42: "Sinal Abraço",
    43: "Sinal Por Favor",
    44: "Sinal Horas",
    45: "Sinal De Nada",
    46: "Sinal Noite",
    47: "Sinal Vírgula",
    48: "Sinal Onde",
    49: "Sinal Até",
    50: "Sinal Banheiro",
    51: "Letra Z",
  };



  // --- LISTAS DE CONTROLE DE SINAIS ---
  final Set<int> oneHandedSignalIndices = {
    0,
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    20,
    21,
    22,
    23,
    24,
    25,
    26,
    27,
    28,
    29,
    30,
    31,
    32,
    33,
    34,
    35,
    36,
    46,
    47,
    51
  };



  final Set<int> twoHandedSignalIndices = {
    41,
    42,
    45,
    49,
  };



  final Set<int> letterIndices = {
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    20,
    21,
    22,
    23,
    24,
    25,
    26,
    27,
    28,
    29,
    30,
    31,
    32,
    51
  };



  final Set<int> numberIndices = {1, 2, 3, 4, 5, 6, 7, 9};



  // Saudações e expressões comuns
  final Set<int> saudacoesEExpressoesIndices = {
    10, // Te Amo
    33, // Oi
    34, // Olá/Tchau
    35, // Joia
    36, // Desculpa
    37, // Idade
    38, // Obrigado
    39, // Você
    40, // Conhecer
    41, // Licença
    42, // Abraço
    43, // Por Favor
    44, // Horas
    45, // De Nada
    46, // Noite
    48, // Onde
    49, // Até
    50, // Banheiro
  };



  final Set<String> letterCharacters = {
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z'
  };



  Future<void> _loadModelFromBytes() async {
    try {
      final ByteData bytes =
          await rootBundle.load('assets/libras_landmarks_126_ate_Z_atualizado.tflite');
      final Uint8List modelBytes = bytes.buffer.asUint8List();
      if (modelBytes.isEmpty) {
        setState(() {
          resultado = "Erro: Modelo vazio.";
        });
        return;
      }
      interpreter = Interpreter.fromBuffer(modelBytes);
      print('✅ Modelo TFLite (126 floats) carregado com sucesso.');
    } catch (e) {
      print('❌ Falha ao carregar: $e');
      setState(() {
        resultado = "Erro ao carregar modelo.";
      });
    }
  }



  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeRight,
    ]);
    _loadModelFromBytes();
    _controller =
        CameraController(widget.camera, ResolutionPreset.medium, enableAudio: false);
    _initializeControllerFuture =
        _controller.initialize().then((_) async {
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
    _scrollController.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }



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



  bool _lastCharIsLetter() {
    if (_accumulatedText.isEmpty) return false;



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
        final Uint8List originalImageBytes =
            await File(imageFile.path).readAsBytes();
        img.Image? originalImage = img.decodeImage(originalImageBytes);
        Uint8List finalImageBytes;



        if (originalImage != null) {
          img.Image resizedImage =
              img.copyResize(originalImage, width: 224, height: 224);
          finalImageBytes =
              Uint8List.fromList(img.encodeJpg(resizedImage, quality: 85));
        } else {
          finalImageBytes = originalImageBytes;
        }



        final uri =
            Uri.parse('http://148.230.76.27:5000/api/processar_imagem');
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
              var landmarks = Float32List.fromList(
                  rawLandmarks.map((e) => e as double).toList());
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
      String extractedText =
          _extractSignText(_pendingSignalName!, _pendingSignalIndex!);



      if (extractedText != _lastAddedSignal) {
        _accumulatedText += extractedText;
        _lastAddedSignal = extractedText;



        print('✅ SINAL PENDENTE ADICIONADO: "$extractedText"');



        if (mounted) {
          setState(() {
            resultado = _accumulatedText;
            _lastRecognizedIndex = _pendingSignalIndex;
          });
          _scrollToEnd();
        }
      }



      _pendingSignalIndex = null;
      _pendingSignalName = null;
    }
  }



  int _getDetectedHandCount(Float32List landmarks) {
    double sumLeft = 0;
    for (int i = 0; i < 63; i++) sumLeft += landmarks[i].abs();
    double sumRight = 0;
    for (int i = 63; i < 126; i++) sumRight += landmarks[i].abs();
    int count = 0;
    if (sumLeft > 0.1) count++;
    if (sumRight > 0.1) count++;
    return count;
  }



  // Helper para ajustar maiúscula/minúscula da primeira letra de saudações/expressões
  String _applySentenceCase(String text) {
    if (text.isEmpty) return text;
    bool isFirstInText = _accumulatedText.trim().isEmpty;
    String first = text[0];
    String rest = text.substring(1);
    if (isFirstInText) {
      return first.toUpperCase() + rest;
    } else {
      return first.toLowerCase() + rest;
    }
  }



  String _extractSignText(String signalName, int signalIndex) {
    String baseText = "";



    // Número 9 com espaço
    if (signalIndex == 9) {
      baseText = "9 ";
    }
    // Números (0-8)
    else if (signalIndex >= 0 && signalIndex <= 8) {
      baseText = signalIndex.toString();
    }
    // Te Amo - aplica sentence case
    else if (signalIndex == 10) {
      baseText = _applySentenceCase("te amo");
    }
    // Letras (A-Z)
    else if (signalName.contains("Letra ")) {
      baseText = signalName
          .replaceAll("Letra ", "")
          .replaceAll(" (Contexto)", "")
          .replaceAll(" (Dinâmico)", "")
          .trim();
    }
    // Frases compostas
    else if (signalName == "Tudo bem") {
      baseText = _applySentenceCase("tudo bem");
    } else if (signalName == "Bom dia") {
      baseText = _applySentenceCase("bom dia");
    } else if (signalName == "Boa tarde") {
      baseText = _applySentenceCase("boa tarde");
    } else if (signalName == "Boa noite") {
      baseText = _applySentenceCase("boa noite");
    } else if (signalName == "Prazer em conhecer você") {
      baseText = _applySentenceCase("prazer em conhecer você");
    } else if (signalName == "Amanhã após Até") {
      // Novo caso especial para quando vier Conhecer depois de Até
      baseText = "amanhã";
    }
    // Perguntas (com espaço depois do "?")
    else if (signalName == "Qual é o seu nome") {
      baseText = _applySentenceCase("qual é o seu nome?") + " ";
    } else if (signalName == "Que horas são") {
      baseText = _applySentenceCase("que horas são?") + " ";
    } else if (signalName == "Quantos anos você tem") {
      baseText = _applySentenceCase("quantos anos você tem?") + " ";
    } else if (signalName == "Onde é o banheiro") {
      baseText = _applySentenceCase("onde é o banheiro?") + " ";
    }
    // "O meu nome é " - precisa do espaço no final
    else if (signalName == "O meu nome é ") {
      baseText = _applySentenceCase("o meu nome é ");
    }
    // Sinal Obrigado - aplica sentence case
    else if (signalName == "Sinal Obrigado") {
      baseText = _applySentenceCase("obrigado");
    }
    // Sinal Licença → "Com Licença"
    else if (signalName == "Sinal Licença") {
      baseText = _applySentenceCase("com licença");
    }
    // Sinal Abraço - aplica sentence case
    else if (signalName == "Sinal Abraço") {
      baseText = _applySentenceCase("abraço");
    }
    // Pontuações
    else if (signalName == "Ponto Final") {
      baseText = ".";
    } else if (signalName == "Sinal Vírgula") {
      baseText = ", ";
    } else if (signalName == "Ponto de Exclamação") {
      baseText = "!";
    }
    // Outros sinais simples (Oi, Joia, Desculpa, De Nada, etc)
    else if (signalName.contains("Sinal ")) {
      String cleanName = signalName.replaceAll("Sinal ", "").split("/")[0].trim();
      baseText = _applySentenceCase(cleanName.toLowerCase());
    } else {
      baseText = signalName.trim();
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

      // DESABILITA "Que horas são" (índice 44)
      probabilities[44] = 0.0;

      int handsDetected = _getDetectedHandCount(landmarks);
      print('👋 Mãos detectadas: $handsDetected');



      // Filtro de mãos
      if (handsDetected == 1) {
        for (int index in twoHandedSignalIndices) {
          probabilities[index] = 0.0;
        }
      } else if (handsDetected == 2) {
        for (int index in oneHandedSignalIndices) {
          probabilities[index] = 0.0;
        }
      } else {
        print('⚠️ Nenhuma mão válida detectada');
        _processPendingSignal();
        return;
      }



      var predictedIndex = probabilities.indexOf(
          probabilities.reduce((curr, next) => curr > next ? curr : next));
      var confidence = probabilities[predictedIndex];



      print(
          '🎯 Predição: Índice $predictedIndex | Confiança: ${(confidence * 100).toStringAsFixed(1)}%');



      // Lógica de Substituição para Conhecer/Por favor baseada em número de mãos
      final int conhecerIndex = 40;
      final int porfavorIndex = 43;
      if (predictedIndex == porfavorIndex && handsDetected == 1) {
        predictedIndex = conhecerIndex;
        confidence = probabilities[conhecerIndex];
        print('🔄 Por favor → Conhecer (1 mão detectada)');
      } else if (predictedIndex == conhecerIndex && handsDetected == 2) {
        predictedIndex = porfavorIndex;
        confidence = probabilities[porfavorIndex];
        print('🔄 Conhecer → Por favor (2 mãos detectadas)');
      }



      if (confidence > 0.55) {
        _predictionHistory.add(predictedIndex);
        if (_predictionHistory.length > _historyLength) {
          _predictionHistory.removeAt(0);
        }



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
        final int olaIndex = 34;
        final int noiteIndex = 46;
        final int uIndex = 28;
        final int zIndex = 51;
        final int voceIndex = 39;
        final int fIndex = 16;
        final int horasIndex = 44;
        final int ateIndex = 49;
        final int idadeIndex = 37;
        final int ondeIndex = 48;
        final int banheiroIndex = 50;



        bool isDynamicH = false;
        bool isDynamicJ = false;
        bool isTudoBem = false;
        bool isBomDia = false;
        bool isBoaTarde = false;
        bool isBoaNoite = false;
        bool isQualSeuNome = false;
        bool isMeuNomeE = false;
        bool isPontoFinal = false;
        bool isPontoExclamacao = false;
        bool isPrazerConhecerVoce = false;
        bool isAmanhaAposAte = false;
        bool isOndeEoBanheiro = false;
        bool shouldSkipAdding = false;



        if (_predictionHistory.length >= 2) {
          int lastSignal = _predictionHistory[_predictionHistory.length - 2];
          int currentSignal = _predictionHistory[_predictionHistory.length - 1];



          if (lastSignal == kIndex && currentSignal == twoIndex) {
            isDynamicH = true;
          }
          if (lastSignal == iIndex && currentSignal == jIndex) {
            isDynamicJ = true;
          }
          if (lastSignal == bomIndex && currentSignal == joiaIndex) {
            isTudoBem = true;
          }
          if (lastSignal == bomIndex && currentSignal == dIndex) {
            isBomDia = true;
          }
          // NOVA LÓGICA: Boa Tarde = Bom + Olá
          if (lastSignal == bomIndex && currentSignal == olaIndex) {
            isBoaTarde = true;
          }
          if (lastSignal == bomIndex && currentSignal == noiteIndex) {
            isBoaNoite = true;
          }
          if (lastSignal == uIndex && currentSignal == uIndex) {
            isQualSeuNome = true;
          }
          if (lastSignal == twoIndex && currentSignal == twoIndex) {
            isMeuNomeE = true;
          }



          // Ponto Final (Você + F = ".")
          if (lastSignal == voceIndex && currentSignal == fIndex) {
            isPontoFinal = true;
          }



          // Ponto de Exclamação (Z + Você = "!")
          if (lastSignal == zIndex && currentSignal == voceIndex) {
            isPontoExclamacao = true;
          }



          // NOVA LÓGICA: Conhecer após Até = "amanhã"
          if (lastSignal == ateIndex && currentSignal == conhecerIndex) {
            isAmanhaAposAte = true;
          }



          // Onde é o banheiro (Onde + Banheiro)
          if (lastSignal == ondeIndex && currentSignal == banheiroIndex) {
            isOndeEoBanheiro = true;
          }
        }



        // Verifica sequência de 3 sinais (Bom + Conhecer + Você)
        if (_predictionHistory.length >= 3) {
          int thirdLast = _predictionHistory[_predictionHistory.length - 3];
          int secondLast = _predictionHistory[_predictionHistory.length - 2];
          int lastSignal = _predictionHistory[_predictionHistory.length - 1];



          if (thirdLast == bomIndex &&
              secondLast == conhecerIndex &&
              lastSignal == voceIndex) {
            isPrazerConhecerVoce = true;
          }
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
        } else if (isPrazerConhecerVoce) {
          finalResultName = "Prazer em conhecer você";
          finalIndex = -11;
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
        } else if (isPontoFinal) {
          finalResultName = "Ponto Final";
          finalIndex = -9;
          _predictionHistory.clear();
          _pendingSignalIndex = null;
          _pendingSignalName = null;
        } else if (isPontoExclamacao) {
          finalResultName = "Ponto de Exclamação";
          finalIndex = -10;
          _predictionHistory.clear();
          _pendingSignalIndex = null;
          _pendingSignalName = null;
          _zConsecutiveCount = 0;
        } else if (isAmanhaAposAte) {
          // NOVA LÓGICA: "amanhã" após "até"
          finalResultName = "Amanhã após Até";
          finalIndex = -12;
          _predictionHistory.clear();
          _pendingSignalIndex = null;
          _pendingSignalName = null;
        }
        // Onde é o banheiro
        else if (isOndeEoBanheiro) {
          finalResultName = "Onde é o banheiro";
          finalIndex = -15;
          _predictionHistory.clear();
          _pendingSignalIndex = null;
          _pendingSignalName = null;
        } else if (predictedIndex == horasIndex) {
          // "Que horas são" DESABILITADO - ignora
          print('⏭️ "Que horas são" detectado mas está desabilitado');
          shouldSkipAdding = true;
          finalResultName = "";
          finalIndex = horasIndex;
        } else if (predictedIndex == idadeIndex) {
          finalResultName = "Quantos anos você tem";
          finalIndex = -14;
          _processPendingSignal();
        } else if (predictedIndex == twoIndex) {
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
            print(
                '⏸️ Número 2 ficou PENDENTE, aguardando próximo sinal...');
            shouldSkipAdding = true;
            finalResultName = "";
            finalIndex = twoIndex;
          }
        } else if (predictedIndex == bomIndex) {
          // Verifica se o sinal anterior foi bomIndex também
          // Se sim, escreve "Obrigado" na primeira vez
          if (_pendingSignalIndex == bomIndex) {
            finalResultName = "Sinal Obrigado";
            finalIndex = bomIndex;
            _predictionHistory.clear();
            _pendingSignalIndex = null;
            _pendingSignalName = null;
          } else {
            _processPendingSignal();

            print(
                '⏸️ "Obrigado/Bom" detectado, aguardando composição (dia/tarde/noite/tudo bem)...');
            _pendingSignalIndex = bomIndex;
            _pendingSignalName = "Sinal Obrigado";
            shouldSkipAdding = true;
            finalResultName = "";
            finalIndex = bomIndex;
          }
        } else if (predictedIndex == conhecerIndex && handsDetected == 1) {
          // Verifica se o último sinal reconhecido foi "Até"
          if (_lastRecognizedIndex == ateIndex) {
            // Se sim, adiciona "amanhã"
            finalResultName = "Amanhã após Até";
            finalIndex = -12;
            _processPendingSignal();
          } else {
            print(
                '⏸️ "Conhecer" (1 mão) detectado, aguardando composição (prazer)...');
            shouldSkipAdding = true;
            finalResultName = "";
            finalIndex = conhecerIndex;
          }
        } else if (predictedIndex == voceIndex) {
          print(
              '⏸️ "Você" detectado, aguardando composição (ponto final/exclamação/prazer)...');
          shouldSkipAdding = true;
          finalResultName = "";
          finalIndex = voceIndex;
        } else if (predictedIndex == ateIndex) {
          // NOVA LÓGICA: Até pode aparecer sozinho agora
          finalResultName = "Sinal Até";
          finalIndex = ateIndex;
          _processPendingSignal();
        }
        // Joia: não adiciona sozinho (só aparece em "Tudo bem")
        else if (predictedIndex == joiaIndex) {
          _processPendingSignal();

          print(
              '⏭️ "Joia" detectado sozinho, ignorando (só aparece em "Tudo bem")');
          shouldSkipAdding = true;
          finalResultName = "";
          finalIndex = joiaIndex;
        }
        // Olá: permite aparecer sozinho, mas também compõe "Boa tarde"
        else if (predictedIndex == olaIndex) {
          _processPendingSignal();
          finalResultName = "Sinal Olá/Tchau";
          finalIndex = olaIndex;
        }
        // Onde: não adiciona sozinho (parte de "onde é o banheiro")
        else if (predictedIndex == ondeIndex) {
          print(
              '⏸️ "Onde" detectado, aguardando composição (onde é o banheiro)...');
          shouldSkipAdding = true;
          finalResultName = "";
          finalIndex = ondeIndex;
        }
        // Banheiro: não adiciona sozinho (parte de "onde é o banheiro")
        else if (predictedIndex == banheiroIndex) {
          print(
              '⏸️ "Banheiro" detectado, aguardando composição (onde é o banheiro)...');
          shouldSkipAdding = true;
          finalResultName = "";
          finalIndex = banheiroIndex;
        } else if (predictedIndex == noiteIndex) {
          _processPendingSignal();



          print(
              '⏭️ "Noite" detectado sozinho, ignorando (só aparece em "Boa noite")');
          shouldSkipAdding = true;
          finalResultName = "";
          finalIndex = noiteIndex;
        } else if (predictedIndex == kIndex) {
          _kConsecutiveCount++;
          print('🔤 K detectado $_kConsecutiveCount vez(es) consecutivas');



          if (_kConsecutiveCount >= 2) {
            finalResultName = "Letra K";
            finalIndex = kIndex;
            _kConsecutiveCount = 0;
            _processPendingSignal();
          } else {
            shouldSkipAdding = true;
            finalResultName = "";
            finalIndex = kIndex;
          }
        } else if (predictedIndex == zIndex) {
          _zConsecutiveCount++;
          print('🔤 Z detectado $_zConsecutiveCount vez(es) consecutivas');



          if (_zConsecutiveCount >= 2) {
            finalResultName = "Letra Z";
            finalIndex = zIndex;
            _zConsecutiveCount = 0;
            _processPendingSignal();
          } else {
            shouldSkipAdding = true;
            finalResultName = "";
            finalIndex = zIndex;
          }
        } else if (predictedIndex == 0) {
          _zConsecutiveCount = 0;
          _kConsecutiveCount = 0;
          _processPendingSignal();



          if (_lastCharIsLetter()) {
            finalResultName = "Letra O (Contexto)";
            finalIndex = 0;
            print(
                '🔤 Contexto: último char é letra, mostrando O');
          } else {
            finalResultName = "Número 0 (Contexto)";
            finalIndex = 0;
            print(
                '🔢 Contexto: último char não é letra, mostrando 0');
          }
        } else if (predictedIndex == 8) {
          _zConsecutiveCount = 0;
          _kConsecutiveCount = 0;
          _processPendingSignal();



          if (_lastCharIsLetter()) {
            finalResultName = "Letra S (Contexto)";
            finalIndex = 8;
            print(
                '🔤 Contexto: último char é letra, mostrando S');
          } else {
            finalResultName = "Número 8 (Contexto)";
            finalIndex = 8;
            print(
                '🔢 Contexto: último char não é letra, mostrando 8');
          }
        } else {
          _zConsecutiveCount = 0;
          _kConsecutiveCount = 0;
          _processPendingSignal();



          if (predictedIndex == porfavorIndex) {
            finalResultName = "Por Favor";
          } else {
            finalResultName =
                classMapping[predictedIndex] ?? "Desconhecido";
          }
          finalIndex = predictedIndex;
        }



        if (!shouldSkipAdding && finalResultName.isNotEmpty) {
          String extractedText =
              _extractSignText(finalResultName, finalIndex);



          print(
              '📝 Sinal reconhecido: "$finalResultName" → Texto extraído: "$extractedText"');
          print(
              '📋 Último sinal adicionado: "$_lastAddedSignal"');



          bool canAdd = extractedText != _lastAddedSignal;



          // Exceção: Se for Conhecer/Por favor, sempre permite adicionar
          if ((finalIndex == conhecerIndex || finalIndex == porfavorIndex) &&
              (_lastRecognizedIndex == conhecerIndex ||
                  _lastRecognizedIndex == porfavorIndex)) {
            canAdd = true;
          }



          if (canAdd) {
            _accumulatedText += extractedText;
            _lastAddedSignal = extractedText;



            print(
                '✅ ADICIONADO! Texto acumulado agora: "$_accumulatedText"');



            if (mounted) {
              setState(() {
                resultado = _accumulatedText;
                _lastRecognizedIndex = finalIndex;
              });
              _scrollToEnd();
            }
          } else {
            print('⏭️ Mesmo sinal repetido, não adicionado');
          }
        }
      } else {
        print(
            '❌ Confiança baixa (${(confidence * 100).toStringAsFixed(1)}%), ignorando');
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
                  bottom: containerHeight + 25,
                  child: FloatingActionButton(
                    mini: true,
                    backgroundColor:
                        Colors.red.withOpacity(0.8),
                    onPressed: () {
                      setState(() {
                        _accumulatedText = '';
                        resultado = '';
                        _lastAddedSignal = '';
                        _pendingSignalIndex = null;
                        _pendingSignalName = null;
                        _zConsecutiveCount = 0;
                        _kConsecutiveCount = 0;
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24.0, vertical: 12.0),
                    color: Colors.black87,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      controller: _scrollController,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          resultado.isEmpty ? '' : resultado,
                          textAlign: TextAlign.left,
                          style: TextStyle(
                            fontSize:
                                resultFontSize.clamp(16.0, 24.0),
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
            return const Center(
                child: CircularProgressIndicator());
          }
        },
      ),
    );
  }
}