import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────
//  🔑  REPLACE THESE WITH YOUR SUPABASE CREDS
// ─────────────────────────────────────────────
const String _supabaseUrl = 'https://myulnungaxqohezkwyxz.supabase.co';
const String _supabaseAnonKey =
'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im15dWxudW5nYXhxb2hlemt3eXh6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ1Mjk0ODYsImV4cCI6MjA5MDEwNTQ4Nn0.z28F2hylxWy9sOFerDb-F6xYiNWiNEvdKj3zP-LV9ow'
;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: _supabaseUrl,
    anonKey: _supabaseAnonKey,

  );
  print("SUPABASE URL: $_supabaseUrl");
  runApp(const MyApp());
}

final supabase = Supabase.instance.client;

// ─────────────────────────────────────────────
//  App Root
// ─────────────────────────────────────────────
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SnapVault',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'sans-serif',
      ),
      home: const UploadPage(),
    );
  }
}

// ─────────────────────────────────────────────
//  Upload Page
// ─────────────────────────────────────────────
class UploadPage extends StatefulWidget {
  const UploadPage({super.key});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  final ImagePicker _picker = ImagePicker();

  File? _selectedFile;
  bool _isUploading = false;
  String? _statusMessage;
  double _uploadProgress = 0;

  // ── Pick image from gallery or camera ──────
  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? xfile = await _picker.pickImage(
        source: source,
        imageQuality: 80, // compress before upload
      );
      if (xfile == null) return;

      setState(() {
        _selectedFile = File(xfile.path);
        _statusMessage = null;
      });
    } catch (e) {
      _showSnack('Failed to pick image: $e');
    }
  }

  // ── Upload → Store → Navigate ──────────────
  Future<void> _uploadAndSave() async {
    if (_selectedFile == null) {
      _showSnack('Please select an image first.');
      return;
    }

    setState(() {
      _isUploading = true;
      _statusMessage = 'Uploading…';
      _uploadProgress = 0;
    });

    try {
      // 1️⃣ Upload to Storage
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}.jpg';

      setState(() => _uploadProgress = 0.3);

      await supabase.storage
          .from('images')
          .upload(fileName, _selectedFile!);

      setState(() => _uploadProgress = 0.7);

      // 2️⃣ Get public URL
      final imageUrl = supabase.storage
          .from('images')
          .getPublicUrl(fileName);

      setState(() => _uploadProgress = 0.85);

      // 3️⃣ Save URL to DB
      await supabase.from('images').insert({'image_url': imageUrl});

      setState(() {
        _uploadProgress = 1.0;
        _statusMessage = '✅ Uploaded successfully!';
        _selectedFile = null;
      });

      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 600));

      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ImageGalleryPage()),
      );
    } catch (e) {
      // ignore: avoid_print
      print('UPLOAD ERROR: $e');
      setState(() => _statusMessage = '❌ Error: $e');
    } finally {
      setState(() => _isUploading = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          '📷 SnapVault',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: 1.2,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_library_rounded,
                color: Colors.white70),
            tooltip: 'View Gallery',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ImageGalleryPage()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Preview Box ───────────────────
              Expanded(
                child: GestureDetector(
                  onTap: () => _pickImage(ImageSource.gallery),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A24),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: _selectedFile != null
                            ? const Color(0xFF6C63FF)
                            : Colors.white12,
                        width: 2,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: _selectedFile != null
                          ? Image.file(
                        _selectedFile!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                      )
                          : const _EmptyPreview(),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ── Source Buttons ────────────────
              Row(
                children: [
                  Expanded(
                    child: _SourceButton(
                      icon: Icons.photo_rounded,
                      label: 'Gallery',
                      onTap: () => _pickImage(ImageSource.gallery),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SourceButton(
                      icon: Icons.camera_alt_rounded,
                      label: 'Camera',
                      onTap: () => _pickImage(ImageSource.camera),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ── Progress ──────────────────────
              if (_isUploading) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _uploadProgress,
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation(cs.primary),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 10),
              ],

              // ── Status ────────────────────────
              if (_statusMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    _statusMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white60),
                  ),
                ),

              // ── Upload Button ─────────────────
              FilledButton.icon(
                onPressed: _isUploading ? null : _uploadAndSave,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: _isUploading
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : const Icon(Icons.cloud_upload_rounded),
                label: Text(
                  _isUploading ? 'Uploading…' : 'Upload to Cloud',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Gallery Page
// ─────────────────────────────────────────────
class ImageGalleryPage extends StatefulWidget {
  const ImageGalleryPage({super.key});

  @override
  State<ImageGalleryPage> createState() => _ImageGalleryPageState();
}

class _ImageGalleryPageState extends State<ImageGalleryPage> {
  List<Map<String, dynamic>> _images = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  Future<void> _loadImages() async {
    setState(() => _isLoading = true);

    try {
      final data = await supabase
          .from('images')
          .select()
          .order('created_at', ascending: false);

      setState(() {
        _images = List<Map<String, dynamic>>.from(data);
      });
    } catch (e) {
      print("LOAD ERROR: $e");
    }

    setState(() => _isLoading = false);
  }

  Future<void> _deleteImage(String id, String imageUrl) async {
    final fileName = Uri.parse(imageUrl).pathSegments.last;

    try {
      await supabase.storage.from('images').remove([fileName]);
      await supabase.from('images').delete().eq('id', id);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🗑️ Image deleted')),
      );

      await _loadImages(); // 🔥 reload after delete
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting: $e')),
      );
    }
  }

  void _confirmDelete(String id, String imageUrl) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A24),
        title: const Text('Delete Image?',
            style: TextStyle(color: Colors.white)),
        content: const Text('This cannot be undone.',
            style: TextStyle(color: Colors.white60)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(context);
              _deleteImage(id, imageUrl);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          '🖼️ My Gallery',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: _loadImages,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF6C63FF),
        ),
      )
          : _images.isEmpty
          ? const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_album_outlined,
                size: 64, color: Colors.white24),
            SizedBox(height: 16),
            Text(
              'No images yet.\nUpload your first one!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 16),
            ),
          ],
        ),
      )
          : Padding(
        padding: const EdgeInsets.all(12),
        child: GridView.builder(
          itemCount: _images.length,
          gridDelegate:
          const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemBuilder: (context, index) {
            final item = _images[index];
            final url = item['image_url'];
            final id = item['id'].toString();

            return _GalleryTile(
              url: url,
              onDelete: () => _confirmDelete(id, url),
              onTap: () => _openFullscreen(context, url),
            );
          },
        ),
      ),
    );
  }

  void _openFullscreen(BuildContext context, String url) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullscreenImage(url: url),
      ),
    );
  }
}
// ─────────────────────────────────────────────
//  Fullscreen Viewer
// ─────────────────────────────────────────────
class _FullscreenImage extends StatelessWidget {
  final String url;
  const _FullscreenImage({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, elevation: 0),
      body: Center(
        child: InteractiveViewer(
          child: Image.network(url, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Widgets
// ─────────────────────────────────────────────
class _EmptyPreview extends StatelessWidget {
  const _EmptyPreview();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_photo_alternate_rounded,
            size: 64, color: Colors.white24),
        const SizedBox(height: 12),
        const Text(
          'Tap to select an image',
          style: TextStyle(color: Colors.white38, fontSize: 15),
        ),
      ],
    );
  }
}

class _SourceButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SourceButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white70,
        side: const BorderSide(color: Colors.white12),
        backgroundColor: const Color(0xFF1A1A24),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      icon: Icon(icon, size: 20),
      label: Text(label, style: const TextStyle(fontSize: 14)),
    );
  }
}

class _GalleryTile extends StatelessWidget {
  final String url;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const _GalleryTile({
    required this.url,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(
              url,
              fit: BoxFit.cover,
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A24),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF6C63FF)),
                  ),
                );
              },
              errorBuilder: (_, __, ___) => Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A24),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.broken_image_rounded,
                    color: Colors.white24),
              ),
            ),
          ),
          // Delete button overlay
          Positioned(
            top: 6,
            right: 6,
            child: GestureDetector(
              onTap: onDelete,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.delete_rounded,
                    size: 18, color: Colors.redAccent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}