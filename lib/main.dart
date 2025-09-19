import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(MyApp(camera: cameras.first));
}

class MyApp extends StatelessWidget {
  final CameraDescription camera;
  const MyApp({super.key, required this.camera});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter AR Object Detection',
      debugShowCheckedModeBanner: false,
      home: ObjectDetectionPage(camera: camera),
    );
  }
}

class ObjectDetectionPage extends StatefulWidget {
  final CameraDescription camera;
  const ObjectDetectionPage({super.key, required this.camera});

  @override
  State<ObjectDetectionPage> createState() => _ObjectDetectionPageState();
}

class _ObjectDetectionPageState extends State<ObjectDetectionPage> {
  late CameraController _cameraController;
  late ObjectDetector _objectDetector;
  bool _isBusy = false;
  List<DetectedObject> _detectedObjects = [];

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _objectDetector = ObjectDetector(
      options: ObjectDetectorOptions(
        mode: DetectionMode.stream,
        classifyObjects: true,
        multipleObjects: true,
      ),
    );
  }

  void _initializeCamera() async {
    _cameraController = CameraController(
      widget.camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    await _cameraController.initialize();

    _cameraController.startImageStream((CameraImage cameraImage) async {
      if (_isBusy) return;
      _isBusy = true;

      try {
        final WriteBuffer allBytes = WriteBuffer();
        for (final plane in cameraImage.planes) {
          allBytes.putUint8List(plane.bytes);
        }

        final plane = cameraImage.planes[0]; // use first plane
        final inputImage = InputImage.fromBytes(
          bytes: plane.bytes,
          metadata: InputImageMetadata(
            size: Size(
              cameraImage.width.toDouble(),
              cameraImage.height.toDouble(),
            ),
            rotation: InputImageRotation.rotation0deg,
            format: InputImageFormat.yuv420,
            bytesPerRow: plane.bytesPerRow,
          ),
        );

        final objects = await _objectDetector.processImage(inputImage);
        if (mounted) setState(() => _detectedObjects = objects);
      } catch (e) {
        debugPrint("Error: $e");
      } finally {
        _isBusy = false;
      }
    });

    setState(() {});
  }

  @override
  void dispose() {
    _cameraController.dispose();
    _objectDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_cameraController.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          CameraPreview(_cameraController),
          CustomPaint(
            painter: ObjectPainter(
              objects: _detectedObjects,
              imageSize: Size(
                _cameraController.value.previewSize!.height,
                _cameraController.value.previewSize!.width,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ObjectPainter extends CustomPainter {
  final List<DetectedObject> objects;
  final Size imageSize;

  ObjectPainter({required this.objects, required this.imageSize});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final scaleX = size.width / imageSize.width;
    final scaleY = size.height / imageSize.height;

    for (final obj in objects) {
      final rect = Rect.fromLTRB(
        obj.boundingBox.left * scaleX,
        obj.boundingBox.top * scaleY,
        obj.boundingBox.right * scaleX,
        obj.boundingBox.bottom * scaleY,
      );
      canvas.drawRect(rect, paint);

      for (final label in obj.labels) {
        final textPainter = TextPainter(
          text: TextSpan(
            text:
                '${label.text} ${(label.confidence * 100).toStringAsFixed(0)}%',
            style: const TextStyle(
              color: Colors.red,
              fontSize: 14,
              backgroundColor: Colors.black54,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(rect.left, rect.top - 20));
      }
    }
  }

  @override
  bool shouldRepaint(covariant ObjectPainter oldDelegate) => true;
}
