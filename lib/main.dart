import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:tflite/tflite.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:arcore_flutter_plugin/arcore_flutter_plugin.dart';
import 'package:image/image.dart' as img;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Get the list of available cameras
  final cameras = await availableCameras();
  final firstCamera = cameras.firstWhere(
    (camera) => camera.lensDirection == CameraLensDirection.back,
    orElse: () => cameras.first,
  );

  // Run the app with the first available camera
  runApp(MyApp(camera: firstCamera));
}

class MyApp extends StatelessWidget {
  final CameraDescription camera;

  const MyApp({super.key, required this.camera});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AR Object Detection',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: CameraPreviewScreen(camera: camera),
    );
  }
}

class CameraPreviewScreen extends StatefulWidget {
  final CameraDescription camera;

  const CameraPreviewScreen({super.key, required this.camera});

  @override
  State<CameraPreviewScreen> createState() => _CameraPreviewScreenState();
}

class _CameraPreviewScreenState extends State<CameraPreviewScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  List<dynamic> _recognitions = [];
  bool _isDetecting = false;
  bool _isArViewActive = false;
  ArCoreController? _arCoreController;
  String? _detectedObject;

  // COCO dataset labels (simplified)
  static const List<String> labels = [
    'person', 'bicycle', 'car', 'motorcycle', 'airplane', 'bus', 'train',
    'truck', 'boat', 'traffic light', 'fire hydrant', 'stop sign',
    'parking meter', 'bench', 'bird', 'cat', 'dog', 'horse', 'sheep', 'cow',
    'elephant', 'bear', 'zebra', 'giraffe', 'backpack', 'umbrella',
    'handbag', 'tie', 'suitcase', 'frisbee', 'skis', 'snowboard',
    'sports ball', 'kite', 'baseball bat', 'baseball glove', 'skateboard',
    'surfboard', 'tennis racket', 'bottle', 'wine glass', 'cup', 'fork',
    'knife', 'spoon', 'bowl', 'banana', 'apple', 'sandwich', 'orange',
    'broccoli', 'carrot', 'hot dog', 'pizza', 'donut', 'cake', 'chair',
    'couch', 'potted plant', 'bed', 'dining table', 'toilet', 'tv',
    'laptop', 'mouse', 'remote', 'keyboard', 'cell phone', 'microwave',
    'oven', 'toaster', 'sink', 'refrigerator', 'book', 'clock', 'vase',
    'scissors', 'teddy bear', 'hair drier', 'toothbrush'
  ];

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.medium,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    
    _initializeControllerFuture = _controller.initialize().then((_) {
      loadModel();
      startDetection();
    });
  }

  Future<void> loadModel() async {
    try {
      await Tflite.loadModel(
        model: "assets/ssd_mobilenet.tflite",
        labels: "assets/ssd_mobilenet.txt",
      );
    } catch (e) {
      print('Error loading model: $e');
    }
  }

  void startDetection() {
    _controller.startImageStream((CameraImage image) {
      if (_isDetecting) return;
      _isDetecting = true;
      
      detectObjects(image).then((recognitions) {
        setState(() {
          _recognitions = recognitions;
        });
        _isDetecting = false;
      });
    });
  }

  Future<List<dynamic>> detectObjects(CameraImage image) async {
    try {
      var recognitions = await Tflite.detectObjectOnFrame(
        bytesList: image.planes.map((plane) {
          return plane.bytes;
        }).toList(),
        imageHeight: image.height,
        imageWidth: image.width,
        imageMean: 127.5,
        imageStd: 127.5,
        numResultsPerClass: 1,
        threshold: 0.4,
      );
      
      return recognitions ?? [];
    } catch (e) {
      print('Detection error: $e');
      return [];
    }
  }

  void _onArViewCreated(ArCoreController controller) {
    _arCoreController = controller;
    _add3DObject();
  }

  void _add3DObject() {
    if (_detectedObject == null || _arCoreController == null) return;

    // Create a 3D object based on detected object type
    final node = ArCoreReferenceNode(
      name: _detectedObject,
      object3DFileName: _get3DModelForObject(_detectedObject!),
      position: Vector3(0, 0, -1.5),
      scale: Vector3(0.5, 0.5, 0.5),
    );

    _arCoreController!.addArCoreNode(node);
  }

  String _get3DModelForObject(String object) {
    // Map objects to 3D models (you'll need to provide these models)
    final modelMap = {
      'chair': 'chair.sfb',
      'table': 'table.sfb',
      'car': 'car.sfb',
      'cup': 'cup.sfb',
      // Add more mappings as needed
    };
    
    return modelMap[object.toLowerCase()] ?? 'cube.sfb';
  }

  void _startArView() {
    if (_recognitions.isNotEmpty) {
      final detection = _recognitions.first;
      final detectedClass = labels[detection['detectedClass']];
      
      setState(() {
        _isArViewActive = true;
        _detectedObject = detectedClass;
      });
    }
  }

  void _exitArView() {
    setState(() {
      _isArViewActive = false;
      _detectedObject = null;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    Tflite.close();
    _arCoreController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isArViewActive ? 'AR View' : 'Object Detection'),
        actions: _isArViewActive
            ? [
                IconButton(
                  icon: Icon(Icons.exit_to_app),
                  onPressed: _exitArView,
                )
              ]
            : null,
      ),
      body: _isArViewActive ? _buildArView() : _buildCameraView(),
      floatingActionButton: _isArViewActive
          ? null
          : FloatingActionButton(
              onPressed: _startArView,
              child: Icon(Icons.visibility),
              tooltip: 'View in AR',
            ),
    );
  }

  Widget _buildArView() {
    return ArCoreView(
      onArCoreViewCreated: _onArViewCreated,
      enableTapRecognizer: true,
      enableUpdateListener: true,
    );
  }

  Widget _buildCameraView() {
    return Stack(
      children: [
        FutureBuilder<void>(
          future: _initializeControllerFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.done) {
              return CameraPreview(_controller);
            } else {
              return const Center(child: CircularProgressIndicator());
            }
          },
        ),
        _buildDetectionOverlay(),
      ],
    );
  }

  Widget _buildDetectionOverlay() {
    if (_recognitions.isEmpty) {
      return Container();
    }

    return CustomPaint(
      painter: DetectionPainter(_recognitions, labels),
    );
  }
}

class DetectionPainter extends CustomPainter {
  final List<dynamic> recognitions;
  final List<String> labels;

  DetectionPainter(this.recognitions, this.labels);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final textPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    for (var recognition in recognitions) {
      final rect = recognition['rect'];
      final detectedClass = recognition['detectedClass'];
      final confidence = recognition['confidenceInClass'];

      final left = rect['x'] * size.width;
      final top = rect['y'] * size.height;
      final right = (rect['x'] + rect['w']) * size.width;
      final bottom = (rect['y'] + rect['h']) * size.height;

      // Draw bounding box
      canvas.drawRect(
        Rect.fromLTRB(left, top, right, bottom),
        paint,
      );

      // Draw label
      final text = '${labels[detectedClass]} ${(confidence * 100).toStringAsFixed(1)}%';
      final textSpan = TextSpan(
        text: text,
        style: TextStyle(backgroundColor: Colors.red, color: Colors.white),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(left, top - 20));
    }
  }

  @override
  bool shouldRepaint(DetectionPainter oldDelegate) {
    return oldDelegate.recognitions != recognitions;
  }
}
