import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DiaDet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        primaryColor: const Color(0xFF1976D2),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1976D2),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Color(0xFF1976D2),
          foregroundColor: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 3,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        cardTheme: const CardThemeData(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),
      ),
      home: const DiabetesPredictorScreen(),
    );
  }
}

class DiabetesPredictorScreen extends StatefulWidget {
  const DiabetesPredictorScreen({super.key});

  @override
  State<DiabetesPredictorScreen> createState() =>
      _DiabetesPredictorScreenState();
}

class _DiabetesPredictorScreenState extends State<DiabetesPredictorScreen>
    with TickerProviderStateMixin {
  // Core functionality
  Interpreter? _interpreter;
  File? _selectedImage;

  // UI State
  bool _isLoading = false;
  bool _isModelLoaded = false;
  String _status = "Initializing...";

  // Prediction results
  Map<String, dynamic>? _predictionResult;

  // Animation controllers
  late AnimationController _fadeController;
  late AnimationController _scaleController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  List<String> labels = [];
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeApp();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _scaleController.dispose();
    _interpreter?.close();
    super.dispose();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut),
    );

    _fadeController.forward();
  }

  Future<void> _initializeApp() async {
    await _loadLabels();
    await _loadModel();
  }

  Future<void> _loadLabels() async {
    setState(() {
      _status = "Loading labels...";
    });

    try {
      String labelsData = await DefaultAssetBundle.of(
        context,
      ).loadString('assets/labels.txt');
      labels = labelsData
          .trim()
          .split('\n')
          .where((label) => label.isNotEmpty)
          .toList();
      debugPrint("✅ Labels loaded: $labels");

      setState(() {
        _status = "Labels loaded successfully";
      });
    } catch (e) {
      debugPrint("❌ Error loading labels: $e");
      labels = ["diabetes", "nondiabetes"];
      setState(() {
        _status = "Using fallback labels";
      });
    }
  }

  Future<void> _loadModel() async {
    setState(() {
      _status = "Loading AI model...";
      _isLoading = true;
    });

    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/mbv3_diabetes_2class_fp16.tflite',
      );
      debugPrint("✅ Model loaded successfully!");

      setState(() {
        _isModelLoaded = true;
        _isLoading = false;
        _status = "AI model ready for predictions";
      });

      _scaleController.forward();
    } catch (e) {
      debugPrint("❌ Error loading model: $e");
      setState(() {
        _isLoading = false;
        _status = "Error loading model: $e";
      });
    }
  }

  Future<void> _pickImageFromGallery() async {
    if (!_isModelLoaded) {
      _showSnackBar("Please wait for the AI model to load", Colors.orange);
      return;
    }

    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxHeight: 1024,
        maxWidth: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
          _predictionResult = null;
          _status = "Image selected - ready for prediction";
        });
        _scaleController.reset();
        _scaleController.forward();
      }
    } catch (e) {
      _showSnackBar("Error picking image: $e", Colors.red);
    }
  }

  Future<void> _pickImageFromCamera() async {
    if (!_isModelLoaded) {
      _showSnackBar("Please wait for the AI model to load", Colors.orange);
      return;
    }

    // Show camera guidelines dialog
    bool? shouldProceed = await _showCameraGuidelines();
    if (shouldProceed != true) return;

    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxHeight: 1024,
        maxWidth: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
          _predictionResult = null;
          _status = "Photo captured - ready for prediction";
        });
        _scaleController.reset();
        _scaleController.forward();
      }
    } catch (e) {
      _showSnackBar("Error capturing photo: $e", Colors.red);
    }
  }

  Future<void> _predict() async {
    if (_selectedImage == null || _interpreter == null) {
      _showSnackBar("Please select an image first", Colors.orange);
      return;
    }

    setState(() {
      _isLoading = true;
      _status = "Analyzing image with AI...";
    });

    try {
      debugPrint("🔄 Starting prediction...");

      // Load and resize image
      img.Image originalImage = img.decodeImage(
        await _selectedImage!.readAsBytes(),
      )!;
      img.Image resizedImage = img.copyResize(
        originalImage,
        width: 224,
        height: 224,
      );

      debugPrint(
        "Image processed: ${resizedImage.width}x${resizedImage.height}",
      );

      // Create input tensor with RAW pixel values [0-255]
      List<List<List<List<double>>>> input = [];

      List<List<List<double>>> batchData = [];
      for (int y = 0; y < 224; y++) {
        List<List<double>> rowData = [];
        for (int x = 0; x < 224; x++) {
          var pixel = resizedImage.getPixel(x, y);
          double r = pixel.r.toDouble();
          double g = pixel.g.toDouble();
          double b = pixel.b.toDouble();
          rowData.add([r, g, b]);
        }
        batchData.add(rowData);
      }
      input.add(batchData);

      // Prepare output tensor
      var output = [List.filled(2, 0.0)];

      // Run inference
      final stopwatch = Stopwatch()..start();
      _interpreter!.run(input, output);
      stopwatch.stop();

      // Process results
      List<double> probabilities = output[0].cast<double>();
      int predictedIndex = probabilities[0] > probabilities[1] ? 0 : 1;
      double confidence = probabilities[predictedIndex];

      // Create detailed result
      _predictionResult = {
        'prediction': labels[predictedIndex],
        'confidence': confidence,
        'probabilities': {
          labels[0]: probabilities[0],
          labels[1]: probabilities[1],
        },
        'inferenceTime': stopwatch.elapsedMilliseconds,
        'imageSize': '${originalImage.width}x${originalImage.height}',
        'processedSize': '224x224',
      };

      setState(() {
        _isLoading = false;
        _status = "Prediction completed successfully";
      });

      _showSnackBar(
        "Prediction: ${labels[predictedIndex]} (${(confidence * 100).toStringAsFixed(1)}%)",
        confidence > 0.7 ? Colors.green : Colors.orange,
      );

      debugPrint(
        "Prediction completed: ${labels[predictedIndex]} with ${(confidence * 100).toStringAsFixed(1)}% confidence",
      );
    } catch (e) {
      debugPrint("❌ Prediction error: $e");
      setState(() {
        _isLoading = false;
        _status = "Error during prediction";
        _predictionResult = {'error': e.toString()};
      });
      _showSnackBar("Prediction failed: $e", Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<bool?> _showCameraGuidelines() async {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.camera_alt, color: Colors.green[600]),
              const SizedBox(width: 8),
              const Text('Camera Guidelines'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'For best results, please follow these guidelines:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 16),
              _buildDialogItem(Icons.flash_on, 'Ensure good lighting'),
              _buildDialogItem(Icons.center_focus_strong, 'Keep camera steady'),
              _buildDialogItem(Icons.zoom_in, 'Fill the frame with subject'),
              _buildDialogItem(Icons.high_quality, 'Take a clear, focused shot'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.amber[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This is for educational purposes only',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.amber[800],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[600],
                foregroundColor: Colors.white,
              ),
              child: const Text('Take Photo'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDialogItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.green[600], size: 18),
          const SizedBox(width: 12),
          Text(
            text,
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionItem(IconData icon, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: Colors.blue[600],
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'DiaDet',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Status Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Icon(
                        _isModelLoaded
                            ? Icons.check_circle
                            : Icons.hourglass_empty,
                        color: _isModelLoaded ? Colors.green : Colors.orange,
                        size: 32,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _status,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: _isModelLoaded
                              ? Colors.green[700]
                              : Colors.orange[700],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (_isLoading)
                        const Padding(
                          padding: EdgeInsets.only(top: 16),
                          child: LinearProgressIndicator(),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Instructions Card
              Card(
                color: Colors.blue[50],
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.blue[700],
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Photo Guidelines',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[700],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildInstructionItem(
                        Icons.center_focus_strong,
                        'Take a clear, focused photo',
                        'Ensure the image is sharp and not blurry',
                      ),
                      _buildInstructionItem(
                        Icons.wb_sunny,
                        'Use good lighting',
                        'Avoid shadows or overly bright areas',
                      ),
                      _buildInstructionItem(
                        Icons.straighten,
                        'Hold phone steady',
                        'Keep the camera stable for best results',
                      ),
                      _buildInstructionItem(
                        Icons.zoom_in,
                        'Fill the frame',
                        'Make sure the subject covers most of the image',
                      ),
                      _buildInstructionItem(
                        Icons.warning_amber,
                        'Medical disclaimer',
                        'This is for educational purposes only. Consult a healthcare professional for medical advice.',
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Image Display
              if (_selectedImage != null)
                ScaleTransition(
                  scale: _scaleAnimation,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          const Text(
                            'Selected Image',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            height: 250,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(
                                _selectedImage!,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 20),

              // Quick Tips Card
              if (_selectedImage == null && _isModelLoaded)
                Card(
                  color: Colors.green[50],
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lightbulb_outline,
                          color: Colors.green[700],
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Quick Tip',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green[700],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'For best results, take a clear photo in good lighting. The AI model will analyze the image for diabetic indicators.',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.green[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 20),

              // Action Buttons
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Text(
                        'Select Image',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isLoading
                                  ? null
                                  : _pickImageFromGallery,
                              icon: const Icon(Icons.photo_library),
                              label: const Text('Gallery'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue[600],
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isLoading
                                  ? null
                                  : _pickImageFromCamera,
                              icon: const Icon(Icons.camera_alt),
                              label: const Text('Camera'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green[600],
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: (_selectedImage != null && !_isLoading)
                              ? _predict
                              : null,
                          icon: const Icon(Icons.psychology),
                          label: Text(
                            _isLoading ? 'Analyzing...' : 'Analyze Image',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple[600],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Results Card
              if (_predictionResult != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Analysis Results',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildResultsWidget(),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultsWidget() {
    if (_predictionResult!.containsKey('error')) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red[200]!),
        ),
        child: Column(
          children: [
            Icon(Icons.error, color: Colors.red[600], size: 32),
            const SizedBox(height: 8),
            Text(
              'Error: ${_predictionResult!['error']}',
              style: TextStyle(color: Colors.red[700]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final prediction = _predictionResult!['prediction'] as String;
    final confidence = _predictionResult!['confidence'] as double;
    final probabilities =
        _predictionResult!['probabilities'] as Map<String, double>;
    final inferenceTime = _predictionResult!['inferenceTime'] as int;
    final imageSize = _predictionResult!['imageSize'] as String;
    final processedSize = _predictionResult!['processedSize'] as String;

    final isDiabetes = prediction.toLowerCase() == 'diabetes';
    final resultColor = isDiabetes ? Colors.red : Colors.green;

    return Column(
      children: [
        // Main Result
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: resultColor[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: resultColor[200]!),
          ),
          child: Column(
            children: [
              Icon(
                isDiabetes ? Icons.warning : Icons.check_circle,
                color: resultColor[600],
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                prediction.toUpperCase(),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: resultColor[700],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Confidence: ${(confidence * 100).toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: resultColor[600],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Detailed Probabilities
        const Text(
          'Detailed Probabilities',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...probabilities.entries.map((entry) {
          final percentage = entry.value * 100;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    entry.key.toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: LinearProgressIndicator(
                    value: entry.value,
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      entry.key.toLowerCase() == 'diabetes'
                          ? Colors.red[400]!
                          : Colors.green[400]!,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 60,
                  child: Text(
                    '${percentage.toStringAsFixed(1)}%',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          );
        }).toList(),

        const SizedBox(height: 16),

        // Technical Details
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              const Text(
                'Technical Details',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Inference Time:'),
                  Text('${inferenceTime}ms'),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [const Text('Original Size:'), Text(imageSize)],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [const Text('Processed Size:'), Text(processedSize)],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
