import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'Auth/login.dart';
import 'main.dart';

class StoreImg extends StatelessWidget {
  const StoreImg({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PersonaLens',
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
        imageQuality: 80,
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

  String? _userEmail;

  @override
  void initState() {
    super.initState();
    _getUser();
  }

  void _getUser() {
    final user = supabase.auth.currentUser;
    setState(() {
      _userEmail = user?.email ?? "Guest";
    });
  }

  // ── Upload → Store into face_embeddings → Navigate ──────────────
  //
  // Schema flow:
  //   1. Upload image file to Storage bucket 'faces'
  //   2. Get the public URL of the uploaded file
  //   3. Fetch (or create) a default known_person to associate the face with.
  //      In a real app you would pass a specific known_person_id from a
  //      person-selection UI; here we upsert a placeholder person so the
  //      foreign-key constraint on face_embeddings.known_person_id is satisfied.
  //   4. Insert a row into face_embeddings:
  //        known_person_id  → the person this face belongs to
  //        image_url        → the public storage URL
  //        confidence_score → default 1.0 (manually uploaded, assumed correct)
  //        embedding        → null until a real ML pipeline populates it
  //
  // ⚠️  Make sure a public bucket named exactly 'faces' exists in your
  //     Supabase project → Storage → New bucket → name: faces → Public ✓
  //
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
      // ── Step 1: Upload image to Storage ───────────────────────────
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';

      setState(() => _uploadProgress = 0.3);

      await supabase.storage
          .from('faces')        // ← bucket name: 'faces'
          .upload(fileName, _selectedFile!);

      setState(() => _uploadProgress = 0.5);

      // ── Step 2: Get the public URL ─────────────────────────────────
      final imageUrl =
      supabase.storage.from('faces').getPublicUrl(fileName); // ← same bucket

      setState(() => _uploadProgress = 0.65);

      // ── Step 3: Resolve a known_person to attach the embedding to ──
      //
      // We look for an existing "unassigned" placeholder person.
      // If none exists yet, we first need a patient row (required by
      // the known_persons FK).  A real app would let the user pick/create
      // a patient; here we upsert a single default patient and person.
      //
      final String knownPersonId = await _resolveDefaultKnownPersonId();

      setState(() => _uploadProgress = 0.8);

      // ── Step 4: Insert into face_embeddings ────────────────────────
      //
      // `embedding` is intentionally omitted (null) — it will be filled
      // later by your server-side face-recognition pipeline.
      // `confidence_score` is set to 1.0 because the image was manually
      // chosen by the user, so we treat it as a confirmed reference photo.
      //
      await supabase.from('face_embeddings').insert({
        'known_person_id': knownPersonId,
        'image_url': imageUrl,
      });

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

  // ── Upsert a default patient + known_person and return the person id ──
  //
  // This helper ensures that a valid known_person_id always exists before
  // inserting into face_embeddings.  Replace this with real patient /
  // person selection logic as your app grows.
  //
  Future<String> _resolveDefaultKnownPersonId() async {
    // 1. Try to find an existing default patient
    final patientRows = await supabase
        .from('patients')
        .select('id')
        .eq('full_name', 'Default Patient')
        .limit(1);

    late String patientId;

    if (patientRows.isEmpty) {
      // Insert a default patient row
      final inserted = await supabase
          .from('patients')
          .insert({'full_name': 'Default Patient'})
          .select('id')
          .single();
      patientId = inserted['id'] as String;
    } else {
      patientId = patientRows[0]['id'] as String;
    }

    // 2. Try to find an existing default known_person for this patient
    final personRows = await supabase
        .from('known_persons')
        .select('id')
        .eq('patient_id', patientId)
        .eq('name', 'Unassigned')
        .limit(1);

    if (personRows.isEmpty) {
      // Insert a placeholder known_person
      final inserted = await supabase
          .from('known_persons')
          .insert({
        'patient_id': patientId,
        'name': 'Unassigned',
        'relationship': 'unknown',
      })
          .select('id')
          .single();
      return inserted['id'] as String;
    } else {
      return personRows[0]['id'] as String;
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
          '📷 PersonaLens',
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
              // ── Profile Card ─────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A24),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    // Avatar
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: const Color(0xFF6C63FF),
                      child: Text(
                        _userEmail != null && _userEmail!.isNotEmpty
                            ? _userEmail![0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Email + subtitle
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Logged in as",
                            style: TextStyle(color: Colors.white38, fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _userEmail ?? "Loading...",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),

                    // Logout button (optional 🔥)
                    IconButton(
                      onPressed: () async {
                        await supabase.auth.signOut();

                        if (!mounted) return;
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                              (route) => false,
                        );                      },
                      icon: const Icon(Icons.logout, color: Colors.redAccent),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

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
  // Each item holds the face_embeddings row plus the joined known_person name.
  // Shape: { 'id': String, 'image_url': String, 'known_person_id': String,
  //          'person_name': String, 'captured_at': String }
  List<Map<String, dynamic>> _images = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  // ── Load all face_embeddings, joining known_persons for the name ──
  //
  // Supabase PostgREST join syntax:
  //   .select('*, known_persons(name)')
  // returns each embedding row with a nested `known_persons` map.
  //
  Future<void> _loadImages() async {
    setState(() => _isLoading = true);

    try {
      final data = await supabase
          .from('face_embeddings')
          .select('id, image_url, known_person_id, captured_at, known_persons(name)')
          .order('captured_at', ascending: false);

      setState(() {
        _images = (data as List).map((row) {
          final personMap = row['known_persons'] as Map<String, dynamic>?;
          return {
            'id': row['id'].toString(),
            'image_url': row['image_url'] as String,
            'known_person_id': row['known_person_id'].toString(),
            'person_name': personMap?['name'] ?? 'Unknown',
            'captured_at': row['captured_at'] ?? '',
          };
        }).toList();
      });
    } catch (e) {
      // ignore: avoid_print
      print('LOAD ERROR: $e');
    }

    setState(() => _isLoading = false);
  }

  // ── Delete a face_embedding row + the corresponding Storage object ──
  //
  // Deletion order:
  //   1. Remove the file from the 'images' Storage bucket.
  //   2. Delete the face_embeddings row by its primary key.
  //
  // The known_persons / patients rows are intentionally left intact —
  // a person may have multiple embeddings and we only remove this one photo.
  //
  Future<void> _deleteImage(String id, String imageUrl) async {
    // Extract just the filename from the full public URL.
    // e.g. "https://.../storage/v1/object/public/images/1234567890.jpg"
    //       → "1234567890.jpg"
    final fileName = Uri.parse(imageUrl).pathSegments.last;

    try {
      // 1. Remove from Storage
      await supabase.storage.from('faces').remove([fileName]); // ← bucket: 'faces'

      // 2. Delete the face_embeddings record
      await supabase.from('face_embeddings').delete().eq('id', id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🗑️ Image deleted')),
      );

      await _loadImages();
    } catch (e) {
      if (!mounted) return;
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
            icon:
            const Icon(Icons.refresh_rounded, color: Colors.white70),
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
              style:
              TextStyle(color: Colors.white38, fontSize: 16),
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
            final url = item['image_url'] as String;
            final id = item['id'] as String;

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