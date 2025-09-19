import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:ar_flutter_plugin/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin/datatypes/node_types.dart';
import 'package:ar_flutter_plugin/models/ar_node.dart';
import 'package:permission_handler/permission_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Request camera permission
  await Permission.camera.request();
  
  // Get the list of available cameras
  final cameras = await availableCameras();
  final firstCamera = cameras.firstWhere(
    (camera) => camera.lensDirection == CameraLensDirection.back,
    orElse: () => cameras.first,
  );

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
  List<DetectedObject> _detectedObjects = [];
  bool _isDetecting = false;
  bool _isArViewActive = false;
  String? _selectedObject;
  Interpreter? _interpreter;
  final _objectDetector = ObjectDetector(options: ObjectDetectorOptions());

  // COCO dataset labels
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
    _initializeCamera();
    _loadModel();
  }

  Future<void> _initializeCamera() async {
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.medium,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    
    _initializeControllerFuture = _controller.initialize().then((_) {
      if (mounted) {
        startDetection();
      }
    });
  }

  Future<void> _loadModel() async {
    try {
      // Load TFLite model
      _interpreter = await Interpreter.fromAsset('assets/models/ssd_mobilenet.tflite');
    } catch (e) {
      print('Error loading model: $e');
    }
  }

  void startDetection() {
    _controller.startImageStream((CameraImage image) {
      if (_isDetecting) return;
      _isDetecting = true;
      
      detectObjects(image).then((objects) {
        if (mounted) {
          setState(() {
            _detectedObjects = objects;
          });
        }
        _isDetecting = false;
      });
    });
  }

  Future<List<DetectedObject>> detectObjects(CameraImage image) async {
    try {
      // Convert CameraImage to InputImage format for ML Kit
      final inputImage = _convertCameraImage(image);
      final objects = await _objectDetector.processImage(inputImage);
      return objects;
    } catch (e) {
      print('Detection error: $e');
      return [];
    }
  }

  InputImage _convertCameraImage(CameraImage image) {
    // Simplified conversion - in real app, you'd need proper conversion
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    return InputImage.fromBytes(
      bytes: bytes,
      inputImageData: InputImageData(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        imageRotation: InputImageRotation.rotation0deg,
        inputImageFormat: InputImageFormat.nv21,
        planeData: image.planes.map((plane) {
          return InputImagePlaneMetadata(
            bytesPerRow: plane.bytesPerRow,
            height: plane.height,
            width: plane.width,
          );
        }).toList(),
      ),
    );
  }

  void _startArView(String objectLabel) {
    setState(() {
      _isArViewActive = true;
      _selectedObject = objectLabel;
    });
  }

  void _exitArView() {
    setState(() {
      _isArViewActive = false;
      _selectedObject = null;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _objectDetector.close();
    _interpreter?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isArViewActive ? 'AR View - $_selectedObject' : 'Object Detection'),
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
    );
  }

  Widget _buildArView() {
    return ARView(
      onARViewCreated: _onArViewCreated,
      planeDetectionConfig: PlaneDetectionConfig.horizontalAndVertical,
    );
  }

  void _onArViewCreated(ARViewController controller) {
    // Add AR objects when view is created
    _addArObject(controller);
  }

  void _addArObject(ARViewController controller) {
    if (_selectedObject == null) return;

    // Create AR node based on detected object
    final node = ARNode(
      type: NodeType.webGLB,
      uri: _get3DModelUrl(_selectedObject!),
      position: Vector3(0, 0, -1.5),
      scale: Vector3(0.3, 0.3, 0.3),
    );

    controller.addNode(node);
  }

  String _get3DModelUrl(String object) {
    // Map objects to 3D model URLs (you can use local assets or web URLs)
    final modelMap = {
      'chair': 'https://modelviewer.dev/shared-assets/models/Chair.glb',
      'table': 'https://modelviewer.dev/shared-assets/models/Table.glb',
      'car': 'https://modelviewer.dev/shared-assets/models/Car.glb',
      'cup': 'https://modelviewer.dev/shared-assets/models/Cup.glb',
    };
    
    return modelMap[object.toLowerCase()] ?? 
           'https://modelviewer.dev/shared-assets/models/Cube.glb';
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
        _buildObjectList(),
      ],
    );
  }

  Widget _buildDetectionOverlay() {
    return CustomPaint(
      painter: DetectionPainter(_detectedObjects),
      size: Size.infinite,
    );
  }

  Widget _buildObjectList() {
    if (_detectedObjects.isEmpty) {
      return Container();
    }

    return Positioned(
      bottom: 20,
      left: 20,
      right: 20,
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(10),
        ),
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: _detectedObjects.length,
          itemBuilder: (context, index) {
            final object = _detectedObjects[index];
            final label = object.labels.isNotEmpty ? object.labels.first.text : 'Unknown';
            final confidence = object.labels.isNotEmpty 
                ? (object.labels.first.confidence * 100).toStringAsFixed(1) 
                : '0.0';

            return GestureDetector(
              onTap: () => _startArView(label),
              child: Container(
                margin: EdgeInsets.all(8),
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '$confidence%',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class DetectionPainter extends CustomPainter {
  final List<DetectedObject> detectedObjects;

  DetectionPainter(this.detectedObjects);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final textPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    for (var object in detectedObjects) {
      final boundingBox = object.boundingBox;
      final left = boundingBox.left;
      final top = boundingBox.top;
      final right = boundingBox.right;
      final bottom = boundingBox.bottom;

      // Draw bounding box
      canvas.drawRect(
        Rect.fromLTRB(left, top, right, bottom),
        paint,
      );

      // Draw label if available
      if (object.labels.isNotEmpty) {
        final label = object.labels.first;
        final text = '${label.text} ${(label.confidence * 100).toStringAsFixed(1)}%';
        final textSpan = TextSpan(
          text: text,
          style: TextStyle(backgroundColor: Colors.red, color: Colors.white, fontSize: 14),
        );
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(left, top - 20));
      }
    }
  }

  @override
  bool shouldRepaint(DetectionPainter oldDelegate) {
    return oldDelegate.detectedObjects != detectedObjects;
  }
}
