import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../utils/haptics.dart';
import 'capture_preview_screen.dart';

/// Camera capture screen for recording photos and short videos (up to 5 sec).
class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key});

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  bool _isRecording = false;
  bool _isPhotoMode = true; // true = photo, false = video
  int _recordingSeconds = 0;
  Timer? _recordingTimer;
  int _selectedCameraIndex = 0;
  bool _isSwitchingCamera = false;

  static const int _maxRecordingSeconds = 5;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recordingTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
      _controller = null;
      _isInitialized = false;
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No cameras available')),
          );
        }
        return;
      }
      await _setupCamera(_selectedCameraIndex);
    } catch (e) {
      debugPrint('Camera init error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: $e')),
        );
      }
    }
  }

  Future<void> _setupCamera(int cameraIndex) async {
    if (_cameras.isEmpty) return;

    final previousController = _controller;
    final camera = _cameras[cameraIndex];

    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: true,
    );

    _controller = controller;

    try {
      await controller.initialize();
      await previousController?.dispose();

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _selectedCameraIndex = cameraIndex;
          _isSwitchingCamera = false;
        });
      }
    } catch (e) {
      debugPrint('Camera setup error: $e');
      _isSwitchingCamera = false;
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _isSwitchingCamera || _isRecording) return;
    setState(() => _isSwitchingCamera = true);
    AppHaptics.selection();
    final nextIndex = (_selectedCameraIndex + 1) % _cameras.length;
    await _setupCamera(nextIndex);
  }

  Future<void> _takePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    AppHaptics.buttonPress();

    try {
      final file = await _controller!.takePicture();
      if (mounted) {
        _navigateToPreview(file.path, 'image');
      }
    } catch (e) {
      debugPrint('Photo capture error: $e');
    }
  }

  Future<void> _startRecording() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    AppHaptics.buttonPress();

    try {
      await _controller!.startVideoRecording();
      setState(() {
        _isRecording = true;
        _recordingSeconds = 0;
      });

      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) { timer.cancel(); return; }
        setState(() => _recordingSeconds++);
        if (_recordingSeconds >= _maxRecordingSeconds) {
          _stopRecording();
        }
      });
    } catch (e) {
      debugPrint('Start recording error: $e');
    }
  }

  Future<void> _stopRecording() async {
    if (_controller == null || !_isRecording) return;

    _recordingTimer?.cancel();

    try {
      final file = await _controller!.stopVideoRecording();
      setState(() => _isRecording = false);

      if (mounted) {
        _navigateToPreview(file.path, 'video');
      }
    } catch (e) {
      debugPrint('Stop recording error: $e');
      setState(() => _isRecording = false);
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final picker = ImagePicker();
      final XFile? file;

      if (_isPhotoMode) {
        file = await picker.pickImage(source: ImageSource.gallery);
      } else {
        file = await picker.pickVideo(
          source: ImageSource.gallery,
          maxDuration: Duration(seconds: _maxRecordingSeconds),
        );
      }

      if (file != null && mounted) {
        // Verify the file exists and is readable
        final fileObj = File(file.path);
        if (!await fileObj.exists()) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not access the selected file')),
            );
          }
          return;
        }
        _navigateToPreview(file.path, _isPhotoMode ? 'image' : 'video');
      }
    } catch (e) {
      debugPrint('Gallery picker error: $e');
      if (mounted) {
        final message = e.toString().contains('photo')
            ? 'Please allow photo access in Settings to upload from gallery'
            : 'Could not open gallery: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _navigateToPreview(String filePath, String contentType) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CapturePreviewScreen(
          filePath: filePath,
          contentType: contentType,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Camera preview
            if (_isInitialized && _controller != null)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CameraPreview(_controller!),
                ),
              )
            else
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),

            // Top bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTopBar(),
            ),

            // Recording timer
            if (_isRecording)
              Positioned(
                top: 60,
                left: 0,
                right: 0,
                child: _buildRecordingTimer(),
              ),

            // Bottom controls
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomControls(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Close button
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 28),
            onPressed: () async {
              if (_isRecording) {
                _recordingTimer?.cancel();
                try { await _controller?.stopVideoRecording(); } catch (_) {}
                setState(() => _isRecording = false);
              }
              if (mounted) Navigator.of(context).pop();
            },
          ),
          // Flash toggle (future enhancement)
          const SizedBox(width: 48),
          // Switch camera
          if (_cameras.length > 1)
            IconButton(
              icon: const Icon(Icons.flip_camera_ios, color: Colors.white, size: 28),
              onPressed: _switchCamera,
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildRecordingTimer() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha:0.8),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${_recordingSeconds}s / ${_maxRecordingSeconds}s',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mode toggle
          if (!_isRecording)
            _buildModeToggle(),
          const SizedBox(height: 24),

          // Capture controls row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Gallery picker
              if (!_isRecording)
                IconButton(
                  icon: const Icon(Icons.photo_library, color: Colors.white, size: 28),
                  onPressed: _pickFromGallery,
                )
              else
                const SizedBox(width: 48),

              // Capture / Record button
              _buildCaptureButton(),

              // Spacer for symmetry
              const SizedBox(width: 48),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha:0.15),
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModeChip('Photo', _isPhotoMode, () {
            setState(() => _isPhotoMode = true);
            AppHaptics.selection();
          }),
          _buildModeChip('Video', !_isPhotoMode, () {
            setState(() => _isPhotoMode = false);
            AppHaptics.selection();
          }),
        ],
      ),
    );
  }

  Widget _buildModeChip(String label, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.black : Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildCaptureButton() {
    if (_isPhotoMode) {
      // Photo shutter button
      return GestureDetector(
        onTap: _takePhoto,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
          child: Container(
            margin: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
          ),
        ),
      );
    } else {
      // Video record button
      return GestureDetector(
        onTap: _isRecording ? _stopRecording : _startRecording,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: _isRecording ? 28 : 56,
              height: _isRecording ? 28 : 56,
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(_isRecording ? 6 : 28),
              ),
            ),
          ),
        ),
      );
    }
  }
}
