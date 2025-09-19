// import 'dart:typed_data';
// import 'package:camera/camera.dart';
// import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart';
// import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
//
// Future<void> main() async {
//   WidgetsFlutterBinding.ensureInitialized();
//   final cameras = await availableCameras();
//   runApp(MyApp(camera: cameras.first));
// }
//
// class MyApp extends StatelessWidget {
//   final CameraDescription camera;
//   const MyApp({super.key, required this.camera});
//
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'Flutter AR Object Detection',
//       debugShowCheckedModeBanner: false,
//       home: ObjectDetectionPage(camera: camera),
//     );
//   }
// }
//
// class ObjectDetectionPage extends StatefulWidget {
//   final CameraDescription camera;
//   const ObjectDetectionPage({super.key, required this.camera});
//
//   @override
//   State<ObjectDetectionPage> createState() => _ObjectDetectionPageState();
// }
//
// class _ObjectDetectionPageState extends State<ObjectDetectionPage> {
//   late CameraController _cameraController;
//   late ObjectDetector _objectDetector;
//   bool _isBusy = false;
//   List<DetectedObject> _detectedObjects = [];
//
//   @override
//   void initState() {
//     super.initState();
//     _initializeCamera();
//     _objectDetector = ObjectDetector(
//       options: ObjectDetectorOptions(
//         mode: DetectionMode.stream,
//         classifyObjects: true,
//         multipleObjects: true,
//       ),
//     );
//   }
//
//   void _initializeCamera() async {
//     _cameraController = CameraController(
//       widget.camera,
//       ResolutionPreset.medium,
//       enableAudio: false,
//     );
//     await _cameraController.initialize();
//
//     _cameraController.startImageStream((CameraImage cameraImage) async {
//       if (_isBusy) return;
//       _isBusy = true;
//
//       try {
//         // Convert YUV420 image to bytes
//         final WriteBuffer allBytes = WriteBuffer();
//         for (final plane in cameraImage.planes) {
//           allBytes.putUint8List(plane.bytes);
//         }
//         final bytes = allBytes.done().buffer.asUint8List();
//
//         final plane = cameraImage.planes[0]; // take the first plane
//         final inputImage = InputImage.fromBytes(
//           bytes: plane.bytes,
//           metadata: InputImageMetadata(
//             size: Size(cameraImage.width.toDouble(), cameraImage.height.toDouble()),
//             rotation: InputImageRotation.rotation0deg,
//             format: InputImageFormat.yuv420,
//             bytesPerRow: plane.bytesPerRow,
//           ),
//         );
//
//
//         final objects = await _objectDetector.processImage(inputImage);
//         if (mounted) setState(() => _detectedObjects = objects);
//       } catch (e) {
//         print("Error: $e");
//       } finally {
//         _isBusy = false;
//       }
//     });
//
//     setState(() {});
//   }
//
//   @override
//   void dispose() {
//     _cameraController.dispose();
//     _objectDetector.close();
//     super.dispose();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     if (!_cameraController.value.isInitialized) {
//       return const Scaffold(
//         body: Center(child: CircularProgressIndicator()),
//       );
//     }
//
//     return Scaffold(
//       body: Stack(
//         children: [
//           CameraPreview(_cameraController),
//           CustomPaint(
//             painter: ObjectPainter(
//               objects: _detectedObjects,
//               imageSize: Size(
//                 _cameraController.value.previewSize!.height,
//                 _cameraController.value.previewSize!.width,
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }
//
// class ObjectPainter extends CustomPainter {
//   final List<DetectedObject> objects;
//   final Size imageSize;
//
//   ObjectPainter({required this.objects, required this.imageSize});
//
//   @override
//   void paint(Canvas canvas, Size size) {
//     final paint = Paint()
//       ..color = Colors.red
//       ..style = PaintingStyle.stroke
//       ..strokeWidth = 3;
//
//     final scaleX = size.width / imageSize.width;
//     final scaleY = size.height / imageSize.height;
//
//     for (final obj in objects) {
//       final rect = Rect.fromLTRB(
//         obj.boundingBox.left * scaleX,
//         obj.boundingBox.top * scaleY,
//         obj.boundingBox.right * scaleX,
//         obj.boundingBox.bottom * scaleY,
//       );
//       canvas.drawRect(rect, paint);
//
//       for (final label in obj.labels) {
//         final textPainter = TextPainter(
//           text: TextSpan(
//             text: '${label.text} ${(label.confidence * 100).toStringAsFixed(0)}%',
//             style: const TextStyle(
//               color: Colors.red,
//               fontSize: 14,
//               backgroundColor: Colors.black54,
//             ),
//           ),
//           textDirection: TextDirection.ltr,
//         );
//         textPainter.layout();
//         textPainter.paint(canvas, Offset(rect.left, rect.top - 20));
//       }
//     }
//   }
//
//   @override
//   bool shouldRepaint(covariant ObjectPainter oldDelegate) => true;
// }
import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:js/js.dart';

/// JS interop to call TensorFlow.js COCO-SSD detect function
@JS('detectObjects')
external dynamic detectObjects(html.VideoElement video);

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter Web Object Detection',
      home: const ObjectDetectionWebPage(),
    );
  }
}

class ObjectDetectionWebPage extends StatefulWidget {
  const ObjectDetectionWebPage({super.key});

  @override
  State<ObjectDetectionWebPage> createState() =>
      _ObjectDetectionWebPageState();
}

class _ObjectDetectionWebPageState extends State<ObjectDetectionWebPage> {
  late html.VideoElement _videoElement;
  List<dynamic> _predictions = [];

  @override
  void initState() {
    super.initState();
    _initCamera();
    _startDetectionLoop();
  }

  void _initCamera() {
    // Create video element
    _videoElement = html.VideoElement()
      ..autoplay = true
      ..width = 640
      ..height = 480;

    // Get user camera
    html.window.navigator.getUserMedia(video: true).then((stream) {
      _videoElement.srcObject = stream;
    });
  }

  void _startDetectionLoop() async {
    while (true) {
      try {
        final results = await detectObjects(_videoElement);
        setState(() {
          _predictions = results;
        });
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Flutter Web Object Detection")),
      body: Stack(
        children: [
          // Display the camera
          HtmlElementView(viewType: 'videoElement'),
          // Draw bounding boxes
          CustomPaint(
            painter: ObjectPainterWeb(
              predictions: _predictions,
              videoWidth: _videoElement.width!.toDouble(),
              videoHeight: _videoElement.height!.toDouble(),
            ),
          ),
        ],
      ),
    );
  }
}

class ObjectPainterWeb extends CustomPainter {
  final List<dynamic> predictions;
  final double videoWidth;
  final double videoHeight;

  ObjectPainterWeb({
    required this.predictions,
    required this.videoWidth,
    required this.videoHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / videoWidth;
    final scaleY = size.height / videoHeight;

    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (var p in predictions) {
      final bbox = p['bbox']; // [x, y, width, height]
      final rect = Rect.fromLTWH(
        bbox[0] * scaleX,
        bbox[1] * scaleY,
        bbox[2] * scaleX,
        bbox[3] * scaleY,
      );
      canvas.drawRect(rect, paint);

      final textSpan = TextSpan(
        text: '${p['class']} ${(p['score'] * 100).toStringAsFixed(0)}%',
        style: const TextStyle(
          color: Colors.red,
          fontSize: 14,
          backgroundColor: Colors.black54,
        ),
      );
      textPainter.text = textSpan;
      textPainter.layout();
      textPainter.paint(canvas, Offset(rect.left, rect.top - 16));
    }
  }

  @override
  bool shouldRepaint(covariant ObjectPainterWeb oldDelegate) => true;
}
