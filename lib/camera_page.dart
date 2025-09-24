import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:http_parser/http_parser.dart';
import 'package:flutter/services.dart' show rootBundle;

// Certifique-se de que a variável global _cameras é inicializada em main.dart
// late List<CameraDescription> _cameras;
// Future<void> main() async {
//  WidgetsFlutterBinding.ensureInitialized();
//  _cameras = await availableCameras();
//  runApp(const MyApp());
// }

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

  // Variável para armazenar o último sinal reconhecido.
  int? _lastRecognizedIndex;
  // Nova lista para armazenar os últimos 'N' frames para lógica de contexto.
  final List<int> _predictionHistory = [];

  // --- NOVO MAPeamento de rótulos ---
  // Este mapeamento deve ser idêntico ao do `captLandmarks.py` e `treinoLandmarks.py`
  final Map<int, String> classMapping = {
    0: "Sinal Ambíguo 0/O",
    1: "Número 1", 2: "Número 2", 3: "Número 3", 4: "Número 4",
    5: "Número 5", 6: "Número 6", 7: "Número 7",
    8: "Sinal Ambíguo 8/S",
    9: "Número 9",
    10: "Outros Sinais",
    11: "Letra A", 12: "Letra B", 13: "Letra C", 14: "Letra D",
    15: "Letra E", 16: "Letra F", 17: "Letra G",
    18: "Letra K", // NOVO
    19: "Letra I", // Reindexado
    20: "Letra L", // Reindexado
    21: "Letra M", // Reindexado
    22: "Letra N", // Reindexado
    23: "Letra P", // Reindexado
    24: "Letra Q", // Reindexado
    25: "Letra R", // Reindexado
    26: "Letra T", // Reindexado
    27: "Letra U", // Reindexado
    28: "Letra V", // Reindexado
    29: "Letra W", // Reindexado
    30: "Letra X", // Reindexado
    31: "Letra Y", // Reindexado
  };

  // --- NOVO Conjunto de índices que correspondem a letras (inclui os ambíguos) ---
  final Set<int> letterIndices = {
    0, 8, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, // K foi adicionado
  };

  Future<void> _loadModelFromBytes() async {
    try {
      // --- NOVO NOME DO MODELO TFLITE ---
      final ByteData bytes = await rootBundle.load('assets/libras_landmarks_0_a_9_outros_A_a_X.tflite');
      final Uint8List modelBytes = bytes.buffer.asUint8List();
      if (modelBytes.isEmpty) {
        print('Erro: Modelo carregado como dados vazios.');
        setState(() { resultado = "Erro: Modelo vazio."; });
        return;
      }
      interpreter = Interpreter.fromBuffer(modelBytes);
      print('✅ Modelo TFLite (libras_landmarks_0_a_9_outros_A_a_X.tflite) carregado com sucesso.');
    } catch (e) {
      print('❌ Falha ao carregar o modelo TFLite: $e');
      setState(() { resultado = "Erro ao carregar o modelo de reconhecimento."; });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadModelFromBytes();
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    _initializeControllerFuture = _controller.initialize().then((_) {
      if (!mounted) {
        return;
      }
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
    super.dispose();
  }

  void _startSendingPictures() {
    _timer = Timer.periodic(const Duration(milliseconds: 300), (timer) async { // Aumentando a frequência de captura para 300ms
      if (!_controller.value.isInitialized || _isSendingPicture) {
        return;
      }
      _isSendingPicture = true;

      try {
        final XFile imageFile = await _controller.takePicture();
        final File file = File(imageFile.path);
        final Uint8List imageBytes = await file.readAsBytes();

        final uri = Uri.parse('http://148.230.76.27:5000/api/processar_imagem');
        var request = http.MultipartRequest('POST', uri);
        request.files.add(http.MultipartFile.fromBytes(
          'imagem',
          imageBytes,
          filename: 'camera_frame.jpg',
          contentType: MediaType('image', 'jpeg'),
        ));

        var response = await request.send();

        if (response.statusCode == 200) {
          var responseBody = await response.stream.bytesToString();
          var jsonResponse = jsonDecode(responseBody);

          if (jsonResponse['landmarks'] != null) {
            List<dynamic> rawLandmarks = jsonResponse['landmarks'];
            var landmarks = Float32List.fromList(rawLandmarks.map((e) => e as double).toList());
            _runInference(landmarks);
          } else {
            if (mounted) {
              setState(() {
                resultado = jsonResponse['mensagem'] ?? "Nenhuma mão detectada.";
                _lastRecognizedIndex = null;
                _predictionHistory.clear(); // Limpa o histórico se a mão for perdida
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

    var input = landmarks.reshape([1, 63]);
    // O tamanho da lista de saída deve corresponder ao número de classes do seu novo modelo (31 classes)
    var output = List<List<double>>.filled(1, List<double>.filled(32, 0.0));

    try {
      interpreter!.run(input, output);

      var probabilities = output[0];
      var predictedIndex = probabilities.indexOf(
          probabilities.reduce((curr, next) => curr > next ? curr : next));
      var confidence = probabilities[predictedIndex];

      if (confidence > 0.55) {
        // Adiciona a previsão ao histórico
        _predictionHistory.add(predictedIndex);
        if (_predictionHistory.length > 5) { // Mantém os últimos 5 frames no histórico
          _predictionHistory.removeAt(0);
        }

        // --- LÓGICA DE CONTEXTO E DINÂMICA (NOVA) ---
        String finalResult;
        int finalIndex;

        // Verifica o sinal dinâmico 'H' (K seguido de 2)
        // K é o índice 18 e 2 é o índice 2.
        final int kIndex = 18;
        final int twoIndex = 2;

        // Verifica se a sequência K-2 apareceu nos últimos frames
        bool isDynamicH = false;
        if (_predictionHistory.length >= 2) {
          // Checa se o último frame foi 2 e o penúltimo foi K
          if (_predictionHistory[_predictionHistory.length - 1] == twoIndex &&
              _predictionHistory[_predictionHistory.length - 2] == kIndex) {
            isDynamicH = true;
          }
          // Pode adicionar outras variações, como K-K-2
          // if (_predictionHistory.length >= 3 &&
          //     _predictionHistory[_predictionHistory.length - 1] == twoIndex &&
          //     _predictionHistory[_predictionHistory.length - 2] == kIndex &&
          //     _predictionHistory[_predictionHistory.length - 3] == kIndex) {
          //   isDynamicH = true;
          // }
        }

        if (isDynamicH) {
          finalResult = "Letra H";
          finalIndex = -1; // Use um índice único para sinais dinâmicos, ex: -1 para 'H'
          _predictionHistory.clear(); // Limpa o histórico após a detecção
        } else if (predictedIndex == 0) {
          if (_lastRecognizedIndex != null && letterIndices.contains(_lastRecognizedIndex)) {
            finalResult = "Letra O (Inferido por contexto)";
            finalIndex = 0; // O é 0, reajustando para um valor que já existe.
          } else {
            finalResult = "Número 0 (Inferido por contexto)";
            finalIndex = 0;
          }
        } else if (predictedIndex == 8) {
          if (_lastRecognizedIndex != null && letterIndices.contains(_lastRecognizedIndex)) {
            finalResult = "Letra S (Inferido por contexto)";
            finalIndex = 8;
          } else {
            finalResult = "Número 8 (Inferido por contexto)";
            finalIndex = 8;
          }
        } else {
          // Se não for um sinal dinâmico nem ambíguo, use a previsão normal.
          finalResult = "${classMapping[predictedIndex]} (Conf: ${(confidence * 100).toStringAsFixed(2)}%)";
          finalIndex = predictedIndex;
        }

        // --- FIM DA LÓGICA DE CONTEXTO E DINÂMICA ---

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
            _predictionHistory.clear(); // Limpa o histórico se a confiança for baixa
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
    return Scaffold(
      appBar: AppBar(
        title: const Text("Reconhecimento de Libras"),
      ),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Stack(
              children: [
                Positioned.fill(
                  child: AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: CameraPreview(_controller),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    padding: const EdgeInsets.all(16.0),
                    color: Colors.black54,
                    width: double.infinity,
                    child: Text(
                      resultado,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold),
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